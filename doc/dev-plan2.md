# Incremental Development Plan: Threading, GC Safepoints, and Exceptions

**Scope:** CM3-derived Modula-3 compiler (m3front → shared IR → m3llhost/LLVM-C backend),
targeting x86_64 Linux first, wasm32 (Wasmer/WAMR) as a subsequent port.

**Convention:** Each Milestone is a self-contained, compilable, testable unit. Commit at
Milestone granularity in Phases 1–2 and 5; commit at **sub-milestone** granularity in
Phases 3–4 and 6, since those are where the highest risk of "spaghetti and revert" lives.

**Revision note (this version):** Original Phase 6 ("mechanical wasm32 port, all logic
frozen") has been replaced. Investigation of CM3's existing thread backends
(Common / POSIX / PTHREAD / WIN32, plus the coroutine layer that sits atop PTHREAD)
established that:

- **x86_64/Linux keeps the existing PTHREAD backend unchanged.** It is proven, requires
  no shadow-stack codegen, no safepoint-check codegen changes, and no new root-feeding
  logic — the conservative native stack scan already in Milestones 9a/9b applies as-is.
- **wasm32 cannot reuse PTHREAD.** PTHREAD's `StopWorld` relies on `pthread_kill`-delivered
  signals (`SignalThread`/`SignalHandler`) to asynchronously force a running thread to a
  safepoint; wasm32 has no asynchronous preemption mechanism at all, under any runtime.
  This is a hard platform wall, not a missing convenience function.
- A new **WTHREAD** backend is introduced instead: a minimal, purpose-built thread layer
  for wasm32 (`clone`-free, built on `wasi_thread_spawn`-equivalent primitives), using
  **cooperative, voluntarily-reached safepoints** in place of signal-forced suspension,
  and a **precise shadow stack** in place of conservative native-stack scanning (wasm32
  locals/operand stack are not addressable memory and cannot be walked).
- This is a deliberate, evidence-based fork, not an abandonment of the "common code"
  goal: PTHREAD's own `StopWorld` already encodes a safepoint-like concept
  (`inCritical`, maintained by `LockHeap`/`UnlockHeap`) that WTHREAD must replicate
  faithfully, so the two backends remain semantically aligned even though their
  mechanisms differ.

---

## Phase 1 — Thread Architecture & Infrastructure Scaffolding

No active GC intervention in this phase. Goal: threads can spawn, run, and terminate
using the new scaffolding, with zero behavioral change to existing programs.

### Milestone 1 — Cross-Platform Synchronization Wrapper (`M3Sync`)
- Create `M3Sync.h` with the target-blind interface (`m3_runtime_park_mutator`,
  `m3_runtime_notify_coordinator`, `m3_runtime_coordinator_wait`, `m3_runtime_wake_mutators`).
- Implement `M3Sync_x86.c` using `pthread_mutex_t` / `pthread_cond_t` (the existing,
  proven CM3 PTHREAD backend — **left unchanged**).
- Stub `M3Sync_wasm.c` with identical signatures (bodies deferred to Phase 6/WTHREAD).
- Convert RTReference's `lock_grab` / `lock_drop` from spinlocks to `pthread_mutex_t`.
- **Test:** Re-run the existing multi-threaded RTReference C test harness. Confirm no
  regressions and no starvation under sustained concurrent malloc/free load.

### Milestone 2 — Thread Context Layout and Global Registry
- Define `M3_Thread_Context` (list pointers, `stack_base`, `stack_limit`,
  `stack_current`, status enum, exception cells reserved but unused for now).
  Reserve, but do not yet populate, a shadow-stack pointer/depth pair for later wasm32 use.
- Build `M3_Thread_Registry` (global lock, intrusive doubly linked active list).
- Declare the TLS global `current_thread_context`.
- **Test:** Standalone C harness — instantiate several contexts, link/unlink them in
  varying orders, print the list to verify pointer integrity. No dependency on the
  Modula-3 runtime yet. Registry/TLS design is shared by both PTHREAD and WTHREAD.

### Milestone 3a — Uniform Bootstrap Wrapper (default stack)
- Implement `m3_wasm_thread_bootstrap(void* arg)`: writes context to TLS, links into
  the registry, runs a placeholder function pointer, unlinks and frees on exit.
- Register the main thread manually at startup using the *same* wrapper contract
  (default `pthread_create` stack — no custom stack attribute yet).
- **Test:** Compile and run a simple multi-threaded Modula-3 program on x86_64 using
  standard thread stacks. Confirms registry/TLS/bootstrap logic in isolation from
  stack-carving concerns.

### Milestone 3b — Pre-Allocated Stacks via `pthread_attr_setstack`
- Update `RTThread.Fork` to call `m3_allocate_untraced(size)` for the stack block
  (default 64KB, see Milestone 4), populate `stack_base` / `stack_limit` from that
  block, and pass it to `pthread_attr_setstack` before `pthread_create`.
- **Test:** Same multi-threaded program as 3a, now with custom-carved stacks. If this
  fails while 3a passed, the fault is isolated to stack-attribute plumbing, not the
  registry/bootstrap logic.

---

## Phase 2 — Compiler Front-End & GC Canvas Initialization

### Milestone 4 — Front-End Stack-Size Pragma → Shared IR
- Register `<*STACKSIZE n*>` in m3front's pragma handling; add `stack_size` field to
  `Proc.T`, default 65536.
- Emit an IR metadata attribute (`m3_stack_size`) when non-default.
- **Test:** Compile a file using the pragma; inspect the emitted IR text to confirm
  the attribute is present and correctly valued. No backend consumption required yet.

### Milestone 4.5 — Object Header Layout Sanity Check
- Before wiring header offsets into the real code generator, hand-write a small C
  test: allocate a fixed-layout 32-byte header + payload via RTReference, populate
  each header field by hand, and verify (via debugger or printf) that address
  `user_ptr - 32` correctly recovers each field on both the wasm32 and x86_64 layout
  variants you designed.
- **Why:** This isolates a header-offset or alignment bug from every downstream
  milestone that will assume the layout is correct. Cheap insurance, five minutes of
  work, catches an entire class of otherwise-hard-to-diagnose corruption.
- **Test:** Standalone C program, no compiler involvement.

### Milestone 5 — Card Table Allocation & Backend Offset Matrix
- Allocate the 64KB card table once at startup from the `Virtual` heap.
- In `m3llhost`, define the target offset matrix (`type_cell_offset`, `gc_flags_offset`,
  etc.) per target, gated by the sanity check in Milestone 4.5.
- Update the `NEW(TRACED REF ...)` codegen path to request `size + 32` bytes.
- **Test:** Compile and run a program that allocates and accesses fields on a TRACED
  object. Verify field access arithmetic lands correctly (no header offset used yet
  by any GC logic — this only proves allocation-side math is sound).

---

## Phase 3 — Write Barriers & Safepoints (GC disabled, x86_64)

Everything in this phase is validated with `gc_world.gc_pending` hard-wired to 0 —
i.e., all fast-path checks compile and run, but never actually trigger a pause.
**Commit per sub-milestone here.** This phase targets x86_64/PTHREAD; the wasm32/WTHREAD
analog is Phase 6, WTHREAD-3.

### Milestone 6a — Centralized Write Barrier Function
- Implement `m3_write_barrier_64kb(void** field, void* val)` in C, per the LLVM-C
  layout established earlier (null fast-path, card shift, atomic dirty store).
- **Test:** Unit-test the function directly in C against a mock card table buffer —
  confirm correct card index computation and no writes outside table bounds.

### Milestone 6b — Centralized Safepoint Cold-Park Function
- Implement `m3_safepoint_cold_park(void)`: stack-limit check → panic path, atomic
  increment of `threads_parked`, call into `m3_runtime_park_mutator()`.
- **Test:** Unit-test in isolation — force `gc_world.gc_pending = 1` manually from a
  second thread and confirm a calling thread parks and later resumes correctly.

### Milestone 7a — Backend Emission: Write Barrier Fast-Path
- Modify `m3llhost` to emit the null-check fast path plus `call` to
  `m3_write_barrier_64kb` on every TRACED field assignment.
- **Test:** Compile and run an existing non-trivial Modula-3 program. Since
  `gc_pending` stays 0, correctness of *program behavior* should be unaffected —
  this test is really about the compiler emitting valid, non-crashing bitcode.

### Milestone 7b — Backend Emission: Safepoint Fast-Path
- Emit the combined `(gc_pending == 1) OR (sp <= stack_limit)` check at function
  prologues and loop back-edges, branching to `m3_safepoint_cold_park` when true.
- **Test:** Same program as 7a. Additionally, deliberately trigger a stack overflow
  (deep unbounded recursion) and confirm the panic path fires cleanly instead of
  silently corrupting memory.

---

## Phase 4 — GC Coordination (GC enabled, x86_64)

This is the highest-risk phase on the native side. Sub-milestones are deliberately
narrow so a failure points at a specific mechanism rather than "the whole GC is broken."

### Milestone 8 — Stop-The-World Pause/Resume Cycle Only
- Implement `m3_gc_stop_the_world_unified()` and `m3_gc_resume_world_unified()`,
  modeled on PTHREAD's proven `StopWorld`/`SignalHandler` state machine
  (`Started → Stopping → Stopped`, gated by `inCritical`, two-phase
  parked-ack/resumed-ack rendezvous via semaphore).
- Do **not** implement root scanning yet — the coordinator simply pauses all threads,
  waits a fixed short interval (or a manual trigger), and resumes them.
- **Test:** Manually flip `gc_pending` from a test-only background thread. Log
  `threads_parked` reaching the target count and all mutators resuming cleanly. This
  isolates the pause/resume synchronization mechanism from any scanning logic.

### Milestone 9a — Conservative Stack Scan Against a Synthetic Heap
- Implement `scan_thread_roots_unified()`, but validate it first against a
  **hand-built synthetic scenario**: plant known live and known dead objects at
  known stack offsets in a controlled single-threaded test, and assert the scan
  correctly identifies and pins exactly the live ones.
- **Why:** Isolates root-scanning correctness from real-program nondeterminism
  before it's ever exercised under actual GC pressure with real allocation patterns.
- **Test:** Deterministic, repeatable, no reliance on real program crash/no-crash as
  the only signal.

### Milestone 9b — Wire Scanning Into the Live Coordinator
- Connect Milestone 9a's scanning logic into the Milestone 8 pause cycle, running
  against real multi-threaded programs with GC now genuinely active.
- Limit test programs to allocations **under 64KB** (defer Large Object Space).
- **Test:** Run data-intensive Modula-3 programs under real GC pressure on x86_64.

### Milestone 9c — Object Pinning, Page Recycling, Large Object Space
- Add `PINNED_BIT` handling, free-page recycling, and the Large Object Space
  subsystem for allocations exceeding 64KB.
- **Test:** Extend the test suite with allocations that exceed 64KB; confirm
  multi-page objects are tracked, pinned/moved correctly, and reclaimed when dead.

---

## Phase 5 — Exception Handling

**Hard dependency:** Milestone 10 assumes Phase 4 (a live, working GC coordinator) is
in place, since the safepoint check inside `RAISE` is untestable in isolation
otherwise. Do not parallelize this phase against unfinished GC work.

### Milestone 10 — Exception Root Registration & Safepoint-Guarded Raise
- Add `active_exception_id` / `active_exception_arg` to `M3_Thread_Context`.
- Modify the `RAISE` runtime stub: register exception payload into the thread
  context, perform the safepoint check, **then** invoke `llvm.eh.sjlj.longjmp`.
- Extend `scan_thread_roots_unified` to treat these two fields as precise roots.
- **Test:** Trigger an exception while forcing a concurrent GC sweep (via a
  test-only hook); confirm the exception payload survives and is correctly updated
  if moved.

### Milestone 11 — Re-Throw Cascades & Root Clearance
- Emit the automatic re-throw fallback at the end of unmatched `EXCEPT` bodies
  (fetch parent frame, null-check, `longjmp`).
- Emit root-clearance code (`active_exception_arg = NULL`) at the entry of a
  successful matching handler body.
- **Test:** Run the compiler's existing exception test suite (nested try/except,
  try/finally with lock release) on x86_64; confirm full behavioral parity with the
  pre-GC/threading implementation.

---

## Phase 6 — WebAssembly Port: WTHREAD

**Revised scope.** Earlier drafts of this plan assumed wasm32 could reuse PTHREAD
almost mechanically once `M3Sync_wasm.c`'s bodies were filled in. That assumption does
not hold: PTHREAD's stop-the-world path depends on `pthread_kill`-delivered signals to
*force* a non-cooperating thread to a safepoint, and wasm32 has no equivalent — no
asynchronous preemption exists on the platform, under Wasmer, WAMR, or any other
runtime. Every wasm32 thread must *voluntarily* reach a safepoint; there is no fallback.
wasm32 also has no addressable native stack to scan conservatively (locals and the
operand stack live inside VM state, not linear memory), so Phase 4's conservative
scanner cannot be reused either — wasm32 requires a **precise shadow stack** instead.

This phase is therefore treated with the same sub-milestone discipline as Phases 3–4,
**not** as a mechanical port. **Commit per sub-milestone.**

Design correspondences to keep in view while implementing, so the two backends stay
semantically aligned despite differing mechanisms:

| PTHREAD concept | WTHREAD analog |
|---|---|
| `pthread_mutex_t`/`pthread_cond_t` (`M3Sync_x86.c`) | nsync-style lock/condition module (already prototyped, pthread-independent) |
| `pthread_kill` + `SignalHandler` forced suspension | Voluntary safepoint check at prologues/back-edges (cooperative-yield, `ngcs`-style) |
| `inCritical` (set/cleared by `LockHeap`/`UnlockHeap`) | Same exclusion semantics, emulated without a native mutex; must gate parking identically |
| `stacks.context`/`stacks.bsp` captured at signal time | Shadow stack, kept structurally consistent at every voluntary park point |
| Two-phase `sem_post`/`sigsuspend` park–resume handshake | Equivalent parked-ack / resumed-ack rendezvous in the WTHREAD coordinator |
| Conservative `scan_thread_roots_unified` (native stack walk) | Precise shadow-stack walk (parallel path off the same dispatch, or a wasm32-specific context variant) |

### WTHREAD-1 — Fork/Join Only, No Locking, No GC Concepts
- Minimal thread create/join on wasm32 (`wasi_thread_spawn`-equivalent — confirm exact
  symbol/ABI against the target WAMR version), reusing the existing target-blind
  `M3_Thread_Registry`/TLS design from Milestone 2 unchanged.
- **Test:** Spawn N threads, each does trivial work, all join cleanly under WAMR.
  No locking, no safepoints, no shadow stack yet.

### WTHREAD-2 — LockHeap/UnlockHeap Emulation, Still No GC
- Implement the heap-lock emulation using the pthread-independent nsync-style
  lock/condition module, matching `inCritical` increment/decrement semantics.
- **Test:** Multiple threads contending on the emulated heap lock with dummy
  critical-section work; verify mutual exclusion and no deadlock under sustained load.
  Entirely isolated from GC and from safepoints.

### WTHREAD-3 — Safepoint Check Wired to `inCritical`, `gc_pending` Hard-Wired to 0
- Instrument prologues/back-edges with the cooperative safepoint check; the check
  must consult both `gc_pending` and the emulated `inCritical` state, mirroring
  PTHREAD's `SignalHandler` refusal to stop a thread mid-critical-section.
- **Test:** Existing wasm32 programs compile and run with identical behavior;
  `gc_pending` never actually triggers a park. This is the wasm32 analog of Phase 3.

### WTHREAD-4 — Cooperative Park/Resume Rendezvous, Manually Triggered, No Scanning
- Flip `gc_pending` from a test-only hook; confirm threads voluntarily park at their
  next safepoint (respecting `inCritical`), confirm `threads_parked` reaches the
  target count, confirm the two-phase resume handshake works cleanly.
- **Test:** No scanning, no shadow stack reads yet — pure coordination-mechanism
  validation, the wasm32 analog of Milestone 8.

### WTHREAD-5 — Shadow Stack Populated but Not Yet Scanned
- Emit spill/fill codegen for TRACED locals against a linear-memory shadow stack;
  add the shadow-stack pointer/depth fields to `M3_Thread_Context` (reserved since
  Milestone 2).
- **Test:** Verify by inspection/printf (same spirit as Milestone 4.5) that shadow
  stack contents are correct and stable at the moment a thread parks, *before* any
  collector logic reads it. Explicitly confirm the shadow stack is left in a fully
  consistent state at every park point — not mid-spill.

### WTHREAD-6 — Wire Shadow-Stack Scanning Into the WTHREAD-4 Coordinator, Synthetic Heap First
- Implement the precise shadow-stack scan and connect it to the WTHREAD-4 pause
  cycle; validate against a hand-built synthetic scenario first (known live/dead
  objects at known shadow-stack depths), mirroring Milestone 9a's discipline.
- **Test:** Deterministic, repeatable; no reliance on real-program crash/no-crash.

### WTHREAD-7 — Real GC Pressure, Small Allocations, Real Programs
- Run data-intensive Modula-3 programs compiled to `wasm32-unknown-unknown` (or the
  appropriate WASI target) under real GC pressure, loaded under Wasmer or WAMR.
- Limit to allocations under 64KB, consistent with Milestone 9b; Large Object
  Space / pinning parity with Milestone 9c is deferred to a later sub-milestone
  once WTHREAD-7 is stable.
- **Test:** Full Phase 1–5 behavioral test suite, now running end-to-end on wasm32
  via WTHREAD instead of PTHREAD.

---

## Commit Granularity Summary

| Phase | Granularity | Rationale |
|---|---|---|
| 1 | Per milestone (1, 2, 3a, 3b) | Split 3a/3b isolates registry logic from stack-attribute plumbing |
| 2 | Per milestone (4, 4.5, 5) | 4.5 is cheap insurance against header-offset bugs propagating forward |
| 3 | Per sub-milestone (6a, 6b, 7a, 7b) | GC-disabled testing; still highest density of new codegen paths (x86_64) |
| 4 | Per sub-milestone (8, 9a, 9b, 9c) | Highest-risk phase on native; narrow milestones give diagnosable failure points |
| 5 | Per milestone (10, 11) | Hard-depends on Phase 4 being complete and stable |
| 6 | Per sub-milestone (WTHREAD-1…7) | Not a mechanical port: cooperative scheduling + precise shadow-stack scanning are new mechanisms with no proven wasm32 precedent; same discipline as Phases 3–4 |
