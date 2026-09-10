# Incremental Development Plan: wasm32 Threading, Safepoints, and GC Integration

**Scope:** CM3-derived Modula-3 compiler. The x86_64/Linux target, via the `m3llhost`
backend and the existing PTHREAD runtime module, is an **already-working baseline** —
proven card-table/write-barrier/safepoint/stop-the-world GC, in production use today.
This plan covers only the **new work required for the wasm32 target**, built through
the new `m3llwasm` backend and a new `WTHREAD` (implemented as `WThread`/`nthr`/`nsyn`)
runtime module.

**Revision note (this version):** Phase A is complete and tested — `WThread.i3`/
`WThread.m3`, `nthr.c`/`nthr.h`, and the architecture-specific `nthr_x86_64.c`
(the Ubuntu test harness) and `nthr_wasm32.c` files are working, including
`SuspendOthers`/`ResumeOthers` with both `SAFE_WAIT` polling timeouts eliminated in
favor of pure blocking waits. Getting there surfaced several genuine concurrency bugs
and one real design gap (the `relief` watch state), each of which encodes an
**invariant that Phase B onward must not violate**. These are pulled into their own
section below rather than left buried in commit history, since B/C/D's codegen and
collector-integration work will depend on them holding.

| Status | Item |
|---|---|
| ✅ Confirmed reusable | `SuspendOthers` / `ResumeOthers` as the safepoint-coordination interface. PTHREAD implements it via `pthread_kill`/`StopWorld`; WTHREAD implements it via the cooperative `nthr_park`/nexus mechanism. Same call sites in the GC, same contract, different mechanism underneath. |
| ✅ Confirmed by build config | Target exclusivity: `TARGET=wasm32` (which now forces `M3_BACKEND=Wasm`) builds and publishes WTHREAD and the wasm runtime; PTHREAD is not built into that library at all. Resolved entirely at build/link time via the existing TARGET-keyed publish directories, no runtime dispatch inside the GC. |
| ✅ Resolved (Phase C) | Shadow-stack root feeding: WTHREAD's `RTThread.ProcessStacks` presents each thread's shadow stack as an ordinary `(start, limit)` address range, scanned by the **existing, unmodified** `NoteStackLocations`/`AddressToPage`/`PromotePage` machinery. **Zero changes to `RTCollector.m3`.** |
| ✅ Complete, tested (Phase A) | WTHREAD's thread lifecycle, recursive heap-lock emulation, and cooperative `SuspendOthers`/`ResumeOthers` coordination — see below for the invariants this depends on. |
| 🔍 To validate (Phase B2) | Whether GC-visible temporaries can ride on LLVM's own `alloca`/`__stack_pointer` lowering rather than requiring bespoke spill/fill codegen. Not yet reached. |

---

## Baseline (no new work) — x86_64 / Linux via `m3llhost` + PTHREAD

Unchanged from prior versions; documented for reference only. **None of this is a
task in this plan.**

- `m3fe` produces target-invariant in-memory IR.
- For `M3_BACKEND=Llvm` (or `C`), the driver invokes `m3llhost` (or `m3C`), which is
  x86_64/Linux-only. `m3llhost` emits LLVM bitcode, `llc` produces x86_64 object code.
- Card table, write barrier fast-path, combined safepoint check, `m3_safepoint_cold_park`,
  and the full stop-the-world/conservative-scan/copying-generational collector are
  all implemented and working today against this codegen.
- PTHREAD implements `SuspendOthers`/`StopWorld` via `pthread_kill` + `SignalHandler`,
  gated by `ThreadState.inCritical` (incremented/decremented by `RTAllocator` around
  every traced allocation, and by `IncInCritical`/`DecInCritical` around coroutine
  stack switches). Resume is a two-phase `sem_post`/`sigsuspend` handshake.
- `RTThread.ProcessStacks(callback)` is the abstraction point the collector calls to
  obtain root ranges. `NoteStackLocations` (in `RTCollector.m3`) receives whatever
  `(start, limit)` range it's handed and scans it **conservatively and
  indiscriminately** — every word is a candidate, filtered only by `AddressToPage`'s
  page-validity check. A false positive only causes an extra page to be conservatively
  pinned for a cycle; it never causes an under-collection.
- Exception handling (`RAISE`, re-throw cascades, root clearance) is implemented and
  working against this same x86_64 codegen and collector.

---

## Phase A — wasm32 Runtime Scaffolding (complete, tested)

Implemented as `WThread.i3`/`WThread.m3` (Modula-3), `nthr.c`/`nthr.h` (target-blind
C), `nthr_x86_64.c` (Ubuntu test harness, exercising the same nexus logic under real
pthreads before wasm32 tooling is exercised) and `nthr_wasm32.c` (wasi-threads
target), with locking/condition primitives via `RTSync.i3` over `nsyn.c`/`nsyn.h`'s
fair, FIFO ticket-lock implementation.

- **Thread lifecycle** (`nthr_create`/`nthr_vigil`/`WThread.Fork`/`Join`): working,
  tested, including proper stack pre-allocation and TLS setup per architecture.
- **Recursive heap-lock emulation** (`RecMutex`/`LockRec`/`UnlockRec`/`WaitRec`/
  `BroadcastRec` in `WThread.m3`): mirrors PTHREAD's `holder`/`inCritical` recursive-
  lock pattern over `nsyn`'s non-recursive primitive, built as a small reusable unit
  rather than generalized into `nsyn` itself.
- **`SuspendOthers`/`ResumeOthers`**: implemented via a `Nexus` record
  (`safePoint`, `safeSyn`, `parkSyn`, `dangerSyn`, `forkList`/`forkSyn`) and a
  five-state `Recce` watch enum (`detached`, `vigilant`, `deferred`, `relief`,
  `joined`) rather than a simple boolean. Both polling timeouts originally needed
  during development (`SAFE_WAIT`, on `acquireSafe`'s and `allSafe`'s waits) have
  been eliminated — both segments now block indefinitely (`-1.0D0`) and pass testing.

### Invariants established in Phase A — required reading before Phase B

These aren't implementation trivia; each one is a genuine race or deadlock found and
fixed during Phase A testing, and each constrains what B/C/D are allowed to do.

**1. Every writer of a thread's `watch` state must be serialized under `parkSyn`,
not just the "obvious" one.** The pattern — lock `parkSyn`, mutate `watch`, unlock,
*then* broadcast `parkSyn` — has to be applied at *every* site that transitions a
thread's watch state in a way `allSafe`'s recount cares about: `nthr_park`,
`SuspendOthers`'s own `watch := relief` transition, `nthr_vigil`, `nthr_func32`
(x86_64 harness), and `wasi_thread_start` (wasm32). Missing any one reopens the same
class of TOCTOU gap: `allSafe`'s recount and its `nsyn_wait` sequence-number capture
must never be interleavable with an un-serialized mutation, or a park/unpark
transition can be silently missed and only recovered by polling. **Any future code
that adds a new way for a thread's watch state to change must go through this same
discipline — there is no "it's just a quick flag flip" exception.**

**2. Any blocking primitive must recheck the safepoint on *both* sides of the
block, not just before.** `nthr_wait`'s fast path checks `safePoint` before calling
`nsyn_wait`, but originally didn't recheck after waking — meaning a thread woken by
an ordinary (non-GC) broadcast could resume running application code while
`SuspendOthers` still believed the world was stopped. The fix is symmetric: check
before blocking *and* after waking, parking on either side if needed. **This applies
to every current and future blocking call, not just `nthr_wait` — if a new blocking
primitive is ever added outside the existing centralized wrapper, it needs this
same before-and-after check, not just a courtesy call into the existing one.**

**3. `relief` must be held for the entire bracketed region, not just inside
`SuspendOthers`/`ResumeOthers`'s own procedure bodies.** `SuspendOthers` and
`ResumeOthers` are ordinary compiled Modula-3 and receive the same codegen-inserted
safepoint checks as everything else — without a distinct watch state, the
coordinator would hit its own inserted check inside its own `allSafe` loop and park
itself, deadlocking permanently since nothing else can call `ResumeOthers`. `relief`
fixes this, but only because the *contract* is: the calling thread's watch is
`relief` from the moment it decides to coordinate until `ResumeOthers` returns — and
this must remain true through **whatever GC work runs between the two calls**, not
just through `SuspendOthers`/`ResumeOthers`'s own bodies. That GC work (root
scanning, object moving — Phase D) will itself be ordinary compiled code full of
loops with inserted safepoint checks. **Nothing that runs between `SuspendOthers`
and `ResumeOthers` may touch its own watch state.** Worth an assertion at the top of
`ResumeOthers` (already partly present) and a comment at the top of whatever Phase D
GC-driver procedure calls both, stating this contract explicitly.

**4. The safepoint-check exemption is role-based (per-thread, per-moment), not
location-based (per-module) — and must stay that way.** The alternative considered
and rejected was suppressing safepoint-check codegen for specific modules
(WThread, or WThread+RTCollector+RTAllocator). Rejected because: the set of modules
needing exemption isn't fixed (any code invoked during a GC pause needs it, which
isn't a static, enumerable list); a thread's role changes over time (an ordinary
mutator can become the GC coordinator mid-allocation, per the Baseline's own
`RTAllocator.AllocTraced` pattern); and blanket module exemption would stop
*every* thread executing that code from ever yielding at a safepoint, not just the
coordinator, needlessly increasing worst-case pause latency. **Phase B's codegen
must emit the identical safepoint check everywhere, uniformly, with no per-module
suppression — the watch-state check is the only exemption mechanism.**

---

## Phase B — `m3llwasm` Codegen: Safepoint Checks and Shadow Stack

Entirely new codegen, entirely contained within `m3llwasm`. `m3llhost` is not
touched.

### B1 — Safepoint Check Emission

The check's predicate is now settled by Phase A testing:

```c
if (safePoint && atomic_load_explicit(&nthr_current->watch, memory_order_acquire) != relief)
    nthr_park();
```

Per Invariant 4, this exact check must be emitted uniformly at every function
prologue and loop back-edge, with no module-based exceptions.

**Forward-looking note for when `RTAllocator` is wired to WTHREAD** (per Baseline,
this is currently deferred — see Phase A's "not yet wired" item from the code
review): once `ThreadState.inCritical` becomes live, the check needs a second term
(`&& inCritical == 0`), mirroring PTHREAD's own gating. When that happens, apply
**Invariant 2's pattern to it as well**: a critical section's *exit* (wherever
`inCritical` is decremented back to zero) must recheck `safePoint` immediately and
park if needed, rather than waiting for the next unrelated safepoint check —
otherwise a park request that arrives mid-critical-section is only honored late,
not silently dropped, but later than it should be. This isn't optional
future-proofing; it's the same before-and-after discipline Invariant 2 already
established for blocking waits, applied to the other place a thread can be
temporarily unparkable.

- **Test:** Compile and run existing wasm32 programs; confirm no behavioral change.

### B2 — GC-Visible Temporary Placement: Investigate LLVM `alloca` Before Committing to Bespoke Codegen

Unchanged from prior version — not yet reached. Three approaches remain on the
table, to be tried in order:

**B2a — Validate: plain LLVM `alloca` + `stacksave`/`stackrestore`.** LLVM's wasm32
backend already lowers `alloca` to adjustments of a linear-memory-resident
`__stack_pointer` global — confirmed real, existing machinery (and, per the code
review, `nthr_arch_stack32` on wasm32 already reads `__stack_pointer` directly,
meaning the runtime side is already shaped for this option without having
explicitly chosen it yet). Two things need confirming: whether a thread must
explicitly publish its stack-pointer value into shared memory at the safepoint
check (very likely yes, since each wasm32 "thread" is probably a separate module
instantiation with private globals), and whether each thread's stack base is fixed
and known at creation time.

**B2b — Fallback: bespoke shadow-stack spill/fill codegen**, if B2a doesn't hold up
against the specific WAMR/wasi-threads toolchain in use.

**B2c — Two-pass hoist-to-locals**, scoped as an optimization only (shrinking the
scanned range for provably-scalar, address-never-taken temporaries), not a
substitute for B2a/B2b — wasm locals aren't memory-addressable and can't solve root
visibility for pointer-holding temporaries on their own.

**Content constraint, either way:** the shadow stack does not need to hold only
traced-reference values — mixing scalars and pointers is safe, since it's scanned by
the same indiscriminate conservative mechanism the native x86_64 stack already is.

- **Test:** Verify shadow stack contents are stable and fully published at every
  point a safepoint check can fire.

---

## Phase C — Shadow Stack Root-Feeding: Design (resolved)

Unchanged in substance. WTHREAD's `RTThread.ProcessStacks` presents each thread's
shadow stack as an ordinary `(start, limit)` range, scanned by the existing,
unmodified `NoteStackLocations`. No changes to `RTCollector.m3`.

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

`ProcessStacks` is currently still a stub in `WThread.m3` (calls `thread_stack32()`
for the coordinator only; the loop-and-callback above is not yet implemented) —
that's expected at this stage; it's Phase D's job.

**Confirmed during Phase A/code review, worth stating explicitly here since it
wasn't written down before:** `thread_stack32()`/`nthr_arch_stack32()` correctly
captures each architecture's real current stack/`__stack_pointer` value into
`ctxt->stack_ptr`, paired with `ctxt->stack_top` (the fixed, high-address bound set
once at thread creation). When Phase D wires up the real callback, **the argument
order matters**: `NoteStackLocations` scans upward (`WHILE fp <= stop`), so the call
must be `p(ctx.stack_ptr, ctx.stack_top)` — current (low) first, base (high) second.
Reversing this doesn't crash; it silently scans zero bytes, since the loop condition
is false immediately. This is exactly the kind of under-collection bug that's
invisible until something gets collected that shouldn't have been — worth a comment
at the `ProcessStacks` call site now, before Phase D writes the real loop.

Trade-off (unchanged): shadow-stack references are scanned conservatively, so any
object they reference has its page pinned rather than relocated. A precise
alternative remains possible as later work (Phase D4).

---

## Phase D — Wire Shadow-Stack Scanning Into the Coordinator

Unchanged in structure from prior version.

### D1 — Synthetic Heap, Deterministic Scan
- Implement `ProcessStacks`'s real loop-and-callback per Phase C's design (fed by
  whichever of B2a/B2b was chosen) — **respecting the `stack_ptr`/`stack_top`
  argument order noted above**; validate first against a hand-built synthetic
  scenario (known live/dead objects at known shadow-stack depths, including a mix of
  pointer and scalar slots).
- **Also the first point at which Invariant 3 becomes load-bearing in practice**:
  whatever procedure performs the actual scan (called between `SuspendOthers` and
  `ResumeOthers`) must not mutate its own watch state, and its loops will receive
  the same B1 safepoint checks as everything else — correctness here depends on
  `relief` still being held, not on this code being somehow exempt.
- **Test:** Deterministic, repeatable, no reliance on real-program crash/no-crash.

### D2 — Real GC Pressure, Small Allocations
- Connect D1's scan into the Phase A `SuspendOthers`/`ResumeOthers` coordination,
  running against real multi-threaded wasm32 programs with GC genuinely active.
- Limit to allocations under 64KB, consistent with the existing x86_64 Large Object
  Space deferral.
- **Test:** Data-intensive Modula-3 programs under real GC pressure, loaded under
  Wasmer or WAMR.

### D3 — Large Object Space / Pinning Parity
- Extend to allocations exceeding 64KB, matching the existing x86_64 collector's
  handling, once D2 is stable.

### D4 — (Deferred, optional) Precise Shadow-Stack Roots
- Revisit only if page-pinning from D1–D3 proves costly in practice. Not scheduled.

---

## Phase E — Exception Handling Parity for wasm32

Unchanged. Deferred until Phase D is stable, since the safepoint check inside
`RAISE` is untestable without a genuinely working GC coordinator underneath it.

- Add `active_exception_id`/`active_exception_arg` to the wasm32 thread context.
- Emit the equivalent `RAISE` sequence in `m3llwasm`: register exception payload,
  perform the safepoint check, transfer control.
- Extend the Phase D scan to treat these fields as precise roots.

---

## Commit Granularity Summary

| Phase | Granularity | Rationale |
|---|---|---|
| Baseline | N/A — already done | x86_64/PTHREAD/m3llhost GC and threading is existing, working code; not part of this plan |
| A | Complete, tested | Thread lifecycle, recursive heap lock, `SuspendOthers`/`ResumeOthers` all working with polling timeouts eliminated; four invariants recorded above govern everything downstream |
| B (B1, B2a/b/c) | Per sub-milestone | B1's check predicate is now fixed by Phase A; B2 explicitly investigates before committing to bespoke codegen |
| C | Design captured, no code | Resolved; argument-order pitfall now documented ahead of D1 rather than discovered during it |
| D (D1–D4) | Per sub-milestone | D1 is where Invariant 3 first becomes load-bearing in practice, not just in the coordination procedures themselves |
| E | Per milestone | Depends on Phase D being complete and stable |
