# Incremental Development Plan: wasm32 Threading, Safepoints, and GC Integration

**Scope:** CM3-derived Modula-3 compiler. The x86_64/Linux target, via the `m3llhost`
backend and the existing PTHREAD runtime module, is an **already-working baseline** —
proven card-table/write-barrier/safepoint/stop-the-world GC, in production use today.
This plan covers only the **new work required for the wasm32 target**, built through
the new `m3llwasm` backend and a new `WTHREAD` runtime module.

**Revision note (this version):** Two refinements to the previous draft:

1. **Phase B2 (temp-variable placement) is reopened as a real design choice, not a
   settled one.** The two-pass "hoist compiler-generated temporaries to wasm locals
   at function start" technique, floated earlier and then set aside as unappealing,
   is **not ruled out** — and there is a third option worth investigating first:
   LLVM's wasm32 backend already implements `alloca`-based stack allocation via a
   linear-memory-resident `__stack_pointer` global, adjusted at function
   prologue/epilogue. If `m3llwasm` simply emits ordinary `alloca` for
   inline-introduced temporaries (no hoisting pass needed) and reads the current
   stack pointer back via LLVM's `stacksave`/`stackrestore` intrinsics at each
   safepoint check, most or all of the custom shadow-stack spill/fill codegen
   originally envisioned may be unnecessary. This needs validation before either
   approach is committed to — see B2, below.
2. **Phase C's closing note is confirmed and sharpened.** A pre-allocated, fixed-
   bounds traced heap (via `RTReference`'s memory map) gives the collector's existing
   `p0`/`p1` bounds check a hard, known range to test shadow-stack words against —
   worth applying at wasm32 runtime init specifically because wasm threads already
   require a maximum memory size to be declared up front, so this costs nothing extra
   to decide.

Everything else — the resolved Phase C design (`ProcessStacks` reusing
`NoteStackLocations` unmodified), Phase A, and the overall structure — is unchanged
from the prior draft and is restated here in full for a clean, complete reference.

| Status | Item |
|---|---|
| ✅ Confirmed reusable | `SuspendOthers` / `ResumeOthers` as the safepoint-coordination interface. PTHREAD implements it via `pthread_kill`/`StopWorld`; WTHREAD implements it via the cooperative `ngcs_request_stop`/`ngcs_resume` mechanism. Same call sites in the GC, same contract, different mechanism underneath. |
| ✅ Confirmed by build config | Target exclusivity: `TARGET=wasm32` (which now forces `M3_BACKEND=Wasm`) builds and publishes WTHREAD and the wasm runtime; PTHREAD is not built into that library at all. Resolved entirely at build/link time via the existing TARGET-keyed publish directories, no runtime dispatch inside the GC. |
| ✅ Resolved (Phase C) | Shadow-stack root feeding: WTHREAD's `RTThread.ProcessStacks` presents each thread's shadow stack as an ordinary `(start, limit)` address range, scanned by the **existing, unmodified** `NoteStackLocations`/`AddressToPage`/`PromotePage` machinery. **Zero changes to `RTCollector.m3`.** |
| 🔍 To validate (Phase B2) | Whether GC-visible temporaries can ride on LLVM's own `alloca`/`__stack_pointer` lowering rather than requiring bespoke spill/fill codegen. Genuinely promising, not yet confirmed against the specific WAMR/wasi-threads toolchain in use. |

---

## Baseline (no new work) — x86_64 / Linux via `m3llhost` + PTHREAD

Documented here for reference only, so the wasm32 plan below can point back to a
known-working analog at each step. **None of this is a task in this plan.**

- `m3fe` produces target-invariant in-memory IR.
- For `M3_BACKEND=Llvm` (or `C`), the driver invokes `m3llhost` (or `m3C`), which is
  x86_64/Linux-only. `m3llhost` emits LLVM bitcode, `llc` produces x86_64 object code.
- Card table, write barrier fast-path, combined safepoint check
  (`gc_pending`/stack-limit) at prologues/back-edges, `m3_safepoint_cold_park`,
  and the full stop-the-world/conservative-scan/copying-generational collector are
  all implemented and working today against this codegen.
- PTHREAD implements `SuspendOthers`/`StopWorld` via `pthread_kill` + `SignalHandler`,
  gated by `ThreadState.inCritical` (incremented/decremented by `RTAllocator` around
  every traced allocation, and by `IncInCritical`/`DecInCritical` around coroutine
  stack switches — a distinct counter from the `LockHeap`/`UnlockHeap` mutex's own
  internal recursion-depth counter, which shares the name `inCritical` but a different
  purpose). Resume is a two-phase `sem_post`/`sigsuspend` handshake.
- `RTThread.ProcessStacks(callback)` is the abstraction point the collector calls to
  obtain root ranges. PTHREAD's implementation walks its private `Activation` list:
  the currently-running thread is scanned live (`ProcessLive`, an `alloca`/register-
  flush trick); every other (signal-stopped) thread is scanned via `ProcessStopped`,
  using the OS-delivered `ucontext_t` address (captured into `stacks.context` by
  `SignalHandler`) as a stand-in for "current stack pointer," scanned up to the
  recorded `stackbase`. `NoteStackLocations` (in `RTCollector.m3`) receives whatever
  `(start, limit)` range `ProcessStacks` hands it and scans it **conservatively and
  indiscriminately** — every word is a candidate, regardless of whether it's actually
  a pointer, a loop counter, a saved register, or padding — filtered only by
  `AddressToPage`'s page-validity check (`p0 <= p < p1`, `desc[p-p0] >= 0`). A false
  positive only causes an extra page to be conservatively pinned for a cycle; it
  never causes an under-collection.
- Exception handling (`RAISE`, re-throw cascades, root clearance) is implemented and
  working against this same x86_64 codegen and collector.

---

## Phase A — wasm32 Runtime Scaffolding (`m3core/runtime/wasm`, WTHREAD)

Goal: threads can spawn, run, and terminate under WTHREAD, with `SuspendOthers`/
`ResumeOthers` mechanically wired but not yet doing anything GC-relevant. No card
table, no write barrier, no safepoint codegen involvement yet — pure thread-lifecycle
plumbing.

### A1 — Fork/Join Only, No Locking, No Safepoint Concepts
- New `m3core/runtime/wasm` directory; minimal WTHREAD create/join on top of a
  `wasi_thread_spawn`-equivalent primitive (confirm exact symbol/ABI against the
  target WAMR version).
- Reuse the existing target-blind thread-context/registry design where it applies;
  reserve (do not populate) fields for shadow-stack pointer/depth.
- Decide the wasm32 `RTReference` memory map here: untraced memory first, then a
  **fixed-size, fixed-location traced-heap region**, allocated once at startup. This
  is motivated independently by the fact that wasm threads already require a maximum
  memory size to be declared up front — deciding the traced-heap's bounds at the same
  time costs nothing extra, and directly feeds Phase C's bounds-check note below.
- **Test:** Spawn N threads under WAMR, trivial work, clean join. No locking, no
  `SuspendOthers`, no shadow stack.

### A2 — `LockHeap`/`UnlockHeap` Emulation
- Implement heap-lock emulation via the pthread-independent nsync-style lock/condition
  module already prototyped, matching `ThreadState.inCritical` increment/decrement
  semantics exactly as used by the existing x86_64 collector and allocator.
- **Test:** Multiple threads contending on the emulated heap lock with dummy
  critical-section work; verify mutual exclusion and no deadlock under load. No GC,
  no safepoints yet.

### A3 — `SuspendOthers`/`ResumeOthers` Wired to `ngcs_request_stop`/`ngcs_resume`
- Implement WTHREAD's `SuspendOthers`/`ResumeOthers` as the same entry points the
  collector already calls on x86_64, backed by the cooperative
  `ngcs_request_stop`/`ngcs_resume` mechanism instead of signals.
- Safepoint check (see Phase B) must consult `ThreadState.inCritical` before honoring
  a stop request — mirroring `SignalHandler`'s refusal to stop a thread mid-critical-
  section, where "critical section" specifically means mid-allocation (header not yet
  written, `initProc` not yet run) or mid coroutine-style context switch.
- **Test:** Manually trigger `SuspendOthers` from a test-only hook; confirm all
  WTHREAD threads voluntarily park at their next safepoint (respecting
  `ThreadState.inCritical`), confirm the parked count reaches target, confirm
  `ResumeOthers` cleanly resumes all threads via the two-phase handshake. Still zero
  shadow-stack involvement.

---

## Phase B — `m3llwasm` Codegen: Safepoint Checks and Shadow Stack

Entirely new codegen, entirely contained within `m3llwasm`. `m3llhost` is not
touched.

### B1 — Safepoint Check Emission
- Emit the cooperative safepoint check at function prologues and loop back-edges in
  `m3llwasm`, branching into the WTHREAD park path, gated by `ThreadState.inCritical`
  exactly as in A3.
- **Test:** Compile and run existing wasm32 programs; confirm no behavioral change.

### B2 — GC-Visible Temporary Placement: Investigate LLVM `alloca` Before Committing to Bespoke Codegen

Modula-3 IR introduces compiler-generated temporaries (loop counters, result values)
inline, at the point they arise — mirroring `alloca`-style stack growth, which wasm
has no *native* stack support for. Three approaches are on the table; the plan is to
validate the first before falling back to the others, rather than committing upfront.

**B2a — Validate: plain LLVM `alloca` + `stacksave`/`stackrestore` (investigate first).**
LLVM's wasm32 backend already lowers `alloca` to adjustments of a linear-memory-
resident `__stack_pointer` global at function entry/exit — this is existing,
production LLVM machinery (used for ordinary C/C++ stack-allocated locals under
Emscripten/wasi-threads), not something to build from scratch. If `m3llwasm` simply
emits an ordinary `alloca` for each temporary exactly where the IR introduces it (no
hoisting pass, single translation pass, same shape as the original inline design),
and reads the current stack pointer back via `llvm.stacksave` at each safepoint
check, `ProcessStacks` may be able to use that value directly as `shadow_current`
against a per-thread fixed `shadow_base`, with **no custom spill/fill codegen at
all**. Two things specifically need confirming before relying on this:
  - Whether the safepoint check's `llvm.stacksave` read, plus a store of that value
    into the shared per-thread context struct, is sufficient — i.e., whether anything
    beyond "publish the current stack-pointer value at the safepoint" is needed for
    the coordinator to later read it while this thread is parked. (Each wasm32
    "thread" is typically a separate module instantiation sharing linear memory but
    *not* sharing globals, so `__stack_pointer` itself is very likely not directly
    readable cross-instance — the parked thread publishing its own value into shared
    memory at the safepoint is the part that still needs explicit codegen, even if
    the underlying stack bookkeeping itself is free.)
  - Whether the per-thread stack region's base is fixed and known at thread-creation
    time (analogous to how PTHREAD pre-carves a stack via `pthread_attr_setstack`),
    so a static `shadow_base` exists to pair with the published `shadow_current`.
- **Test:** Small standalone `m3llwasm`-emitted program using `alloca` for a few
  inline temporaries; confirm via `wasm-objdump` (or equivalent) that `__stack_pointer`
  moves as expected, and confirm the published value/fixed base pair correctly
  bounds the live temporaries at a manually-triggered safepoint. If this validates,
  it substantially reduces B2's remaining scope.

**B2b — Fallback: bespoke shadow-stack spill/fill codegen.**
If B2a doesn't hold up against the specific WAMR/wasi-threads toolchain in use (e.g.,
cross-instance visibility or per-thread base assumptions don't pan out), fall back to
the originally-envisioned design: `m3llwasm` explicitly emits store/load sequences
against an explicitly-managed linear-memory region, incrementing/decrementing a
per-thread "shadow stack current" value maintained entirely by our own codegen,
independent of LLVM's own `alloca` lowering.

**B2c — Two-pass hoist-to-locals: not ruled out, but scoped as an optimization, not
a substitute.** Hoisting temporaries into ordinary wasm locals at function start
(via a first IR pass to collect them) remains a legitimate technique — but only for
temporaries that provably never hold a traced reference and never have their address
taken. Wasm locals are not memory-addressable at all and cannot be found by any stack
walk, conservative or precise — so hoisting does not, by itself, solve root
visibility for pointer-holding temporaries; those still need placement under B2a or
B2b regardless. Worth keeping in the toolbox as a later optimization (shrinking the
scanned region, per Phase C's false-positive discussion) rather than pursuing now.

**Content constraint, either way (B2a or B2b):** the shadow stack does not need to
hold only traced-reference values. Whatever the placement mechanism, mixing scalars
and pointers introduces no new risk beyond what the native x86_64 stack already
tolerates today (see Baseline) — every word is scanned indiscriminately, filtered
only by page-validity.

- **Test (whichever path is taken):** Verify by inspection that shadow stack contents
  are stable and fully published at every point a safepoint check can fire —
  consistency at park time is the requirement, not content typing.

---

## Phase C — Shadow Stack Root-Feeding: Design (resolved)

**This phase's exit criterion — a concrete, written design — has been met.**
Recorded here for reference; Phase D implements and validates it. This design holds
regardless of which of B2a/B2b is ultimately chosen — both produce a per-thread
`(shadow_base, shadow_current)` pair; only how that pair is populated differs.

### Design

WTHREAD's `RTThread.ProcessStacks` presents each thread's shadow stack as an ordinary
`(start, limit)` address range, exactly the shape `NoteStackLocations` already
expects:

```
PROCEDURE ProcessStacks (p: PROCEDURE (start, limit: ADDRESS)) =
  (* LL = W_activeMu; only called within {SuspendOthers, ResumeOthers} *)
  VAR me := GetCurrentContext(); ctx := me;
  BEGIN
    LOOP
      RTHeapRep.FlushThreadState(ctx.heapState);
      p(ctx.shadow_base, ctx.shadow_current);
      ctx := ctx.next;
      IF ctx = me THEN EXIT END;
    END;
  END ProcessStacks;
```

This requires **no changes to `RTCollector.m3`** — `NoteStackLocations`,
`AddressToPage`, `PromotePage`, and `Space.Previous` filtering all run completely
unmodified, exactly as they do for the native x86_64 stack.

Notably, this is *simpler* than PTHREAD's implementation, not merely a port of it:
there is no `ProcessLive`/`ProcessStopped` split, because cooperative parking makes
the initiating thread and every other thread symmetric. Whichever thread reaches
`CollectSomeInStateZero` — even via its own allocation slow path, exactly as
`RTAllocator.AllocTraced` does today — is, at that exact moment, sitting at its own
safepoint check with its shadow stack already fully published by construction. There
is no "not yet suspended" case to special-case, because nothing is ever
asynchronously interrupted.

`RTHeapRep.ThreadState` (the bump-allocator pool bookkeeping) is reused entirely
unchanged — it was already target-blind, with no PTHREAD dependency.

### Trade-off, accepted for the minimal design

Because shadow-stack references are scanned conservatively rather than precisely,
any object they reference has its page **pinned**, never relocated — the same
over-approximation the native stack already lives with. A precise alternative
(route each shadow-stack slot through `RTHeapMap.WalkRef`/`Move` directly, the way
`WalkGlobals` already treats global variable slots, permitting real relocation)
remains possible as later work (Phase D4) — not undertaken now, since it requires a
new collector-side entry point and a type-carrying shadow-stack layout, in tension
with either B2a or B2b's untyped, conservatively-scanned design.

### Closing note — bounding false positives via a fixed traced-heap region

Conservative scanning's false-positive rate depends on how often a non-pointer word's
bit pattern coincidentally maps to a currently-valid heap page. `AddressToPage`
already bounds this today via `FirstPage`'s `p0 <= p < p1` check — a scalar that
doesn't fall within the currently-allocated page range is rejected immediately,
regardless of target.

Since wasm threads require a maximum memory size to be declared up front regardless
(per A1), the wasm32 `RTReference` memory map allocates its **fixed-size, fixed-
location traced-heap region** once at startup, giving `p0`/`p1` known, constant lower
and upper bounds for the life of the program on wasm32 — unlike the dynamically-
growing region `GrowHeap` manages on x86_64. This is not a new mechanism (it's the
same `FirstPage` check already in `RTCollector.m3`, unmodified) but it does make the
bound as tight as it can be: a stray scalar on the shadow stack can only be mistaken
for a root if its value happens to fall inside that one fixed, known, comparatively
small region, rather than anywhere a dynamically-grown heap might have reached. This
costs nothing beyond a decision already required for the wasm threads max-memory
declaration, and is worth locking in as part of A1.

---

## Phase D — Wire Shadow-Stack Scanning Into the Coordinator

### D1 — Synthetic Heap, Deterministic Scan
- Implement `ProcessStacks` per Phase C's design (fed by whichever of B2a/B2b was
  chosen); validate first against a hand-built synthetic scenario (known live/dead
  objects at known shadow-stack depths, including a mix of pointer and scalar slots
  to exercise the relaxed content constraint).
- **Test:** Deterministic, repeatable, no reliance on real-program crash/no-crash.

### D2 — Real GC Pressure, Small Allocations
- Connect D1's scan into the Phase A3 `SuspendOthers`/`ResumeOthers` coordination,
  running against real multi-threaded wasm32 programs with GC genuinely active.
- Limit to allocations under 64KB, consistent with the existing x86_64 Large Object
  Space deferral.
- **Test:** Data-intensive Modula-3 programs under real GC pressure, loaded under
  Wasmer or WAMR.

### D3 — Large Object Space / Pinning Parity
- Extend to allocations exceeding 64KB, matching the existing x86_64 collector's
  handling, once D2 is stable.
- **Test:** Multi-page objects tracked, pinned/moved correctly, reclaimed when dead.

### D4 — (Deferred, optional) Precise Shadow-Stack Roots
- If page-pinning from D1–D3 proves costly in practice (e.g., long-running wasm32
  programs accumulating pinned pages), revisit the precise-root design noted in
  Phase C's trade-off section.
- Not scheduled; recorded here only so it isn't rediscovered from scratch later.

---

## Phase E — Exception Handling Parity for wasm32

The existing `RAISE`/re-throw/root-clearance logic is proven on x86_64 (baseline,
above) but depends on `m3llhost`-specific codegen and the x86_64 safepoint check.
Needs a `m3llwasm`-side equivalent once Phase D is stable — deferred until then,
since the safepoint check inside `RAISE` is untestable without a genuinely working
GC coordinator underneath it.

- Add `active_exception_id`/`active_exception_arg` to the wasm32 thread context.
- Emit the equivalent `RAISE` sequence in `m3llwasm`: register exception payload,
  perform the safepoint check, transfer control.
- Extend the Phase D scan to treat these fields as precise roots.
- **Test:** Trigger an exception while forcing a concurrent GC sweep on wasm32;
  confirm the exception payload survives and is correctly updated if moved. Then run
  the existing exception test suite end-to-end on wasm32 and confirm parity with the
  x86_64 baseline.

---

## Commit Granularity Summary

| Phase | Granularity | Rationale |
|---|---|---|
| Baseline | N/A — already done | x86_64/PTHREAD/m3llhost GC and threading is existing, working code; not part of this plan |
| A (A1–A3) | Per sub-milestone | New thread-lifecycle plumbing for wasm32 only; narrow steps isolate registry/lock/coordination failures |
| B (B1, B2a/b/c) | Per sub-milestone | New codegen confined to `m3llwasm`; B2 explicitly investigates before committing, to avoid building bespoke codegen LLVM may already provide |
| C | Design captured, no code | Resolved: `ProcessStacks` reuses `NoteStackLocations` unmodified; recorded so the rationale (and the deferred precise-root alternative) isn't lost |
| D (D1–D4) | Per sub-milestone | Mirrors the risk profile of the original native GC-coordination phase, now scoped to wasm32; D4 deferred/optional |
| E | Per milestone | Depends on Phase D being complete and stable, same dependency shape as the original exception-handling phase |
