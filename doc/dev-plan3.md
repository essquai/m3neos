# Incremental Development Plan: wasm32 Threading, Safepoints, and GC Integration

**Scope:** CM3-derived Modula-3 compiler. The x86_64/Linux target, via the `m3llhost`
backend and the existing PTHREAD runtime module, is an **already-working baseline** —
proven card-table/write-barrier/safepoint/stop-the-world GC, in production use today.
This plan covers only the **new work required for the wasm32 target**, built through
the new `m3llwasm` backend and a new `WTHREAD` runtime module.

**Revision note (this version):** The previous draft treated card tables, write
barriers, safepoint codegen, and stop-the-world coordination as new work items to be
built for both targets. That was incorrect: on x86_64, all of this **already exists
and works today**, driven by `m3llhost` and the PTHREAD runtime module. The real
scope of new work is:

1. A new wasm32-specific runtime library (`m3core/runtime/wasm`), pulled into the
   published object library only when `TARGET=wasm32`.
2. A new `WTHREAD` runtime module, built only for `TARGET=wasm32`, which is **not**
   present alongside PTHREAD but substitutes for it entirely in that build.
3. New codegen exclusively inside the `m3llwasm` backend (safepoint checks, shadow
   stack spill/fill) — `m3llhost` is untouched, since it only ever targets x86_64.
4. Getting shadow-stack root information into the collector — which, per
   investigation so far, is **not a solved problem** and is called out explicitly
   below rather than folded into a "wire up scanning" step.

Two things are now confirmed as a clean, reusable abstraction across both targets;
one thing is confirmed as *not* free and needs dedicated investigation:

| Status | Item |
|---|---|
| ✅ Confirmed reusable | `SuspendOthers` / `ResumeOthers` as the safepoint-coordination interface. PTHREAD implements it via `pthread_kill`/`StopWorld`; WTHREAD implements it via the cooperative `ngcs_request_stop`/`ngcs_resume` mechanism. Same call sites in the GC, same contract, different mechanism underneath. |
| ✅ Confirmed by build config | Target exclusivity: `TARGET=wasm32` (which now forces `M3_BACKEND=Wasm`) builds and publishes WTHREAD and the wasm runtime; PTHREAD is not built into that library at all. No runtime-dispatch or `#ifdef` branching needed inside the GC to choose between them — it's resolved entirely at build/link time via the existing TARGET-keyed publish directories. |
| ❓ Open, needs investigation | How the collector obtains shadow-stack root ranges/pointers per parked thread. The existing x86_64 collector reaches into PTHREAD's per-thread stack-bookkeeping fairly directly (not through a fully clean abstraction) to get `stacks.context`/`stacks.bsp`. Whether the equivalent wasm32 hook lives in `RTThread`, in the collector itself, or in a new small interface, is undetermined and is **not assumed solved** anywhere below. |

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
  gated by `inCritical` (set/cleared by `LockHeap`/`UnlockHeap`); resume is a
  two-phase `sem_post`/`sigsuspend` handshake. The collector reads
  `stacks.context`/`stacks.bsp`, captured at signal time, to scan each parked
  thread's real stack conservatively.
- Exception handling (`RAISE`, re-throw cascades, root clearance) is implemented and
  working against this same x86_64 codegen and collector.

---

## Phase A — wasm32 Runtime Scaffolding (`m3core/runtime/wasm`, WTHREAD)

Goal: threads can spawn, run, and terminate under WTHREAD, with `SuspendOthers`/
`ResumeOthers` mechanically wired but not yet doing anything GC-relevant. No card
table, no write barrier, no safepoint codegen involvement yet — pure thread-lifecycle
plumbing, analogous in spirit to old Milestones 1–3b but scoped only to wasm32, since
x86_64 needs none of this.

### A1 — Fork/Join Only, No Locking, No Safepoint Concepts
- New `m3core/runtime/wasm` directory; minimal WTHREAD create/join on top of a
  `wasi_thread_spawn`-equivalent primitive (confirm exact symbol/ABI against the
  target WAMR version).
- Reuse the existing target-blind thread-context/registry design where it applies;
  reserve (do not populate) fields for shadow-stack pointer/depth.
- **Test:** Spawn N threads under WAMR, trivial work, clean join. No locking, no
  `SuspendOthers`, no shadow stack.

### A2 — `LockHeap`/`UnlockHeap` Emulation
- Implement heap-lock emulation via the pthread-independent nsync-style lock/condition
  module already prototyped, matching `inCritical` increment/decrement semantics
  exactly as used by the existing x86_64 collector.
- **Test:** Multiple threads contending on the emulated heap lock with dummy
  critical-section work; verify mutual exclusion and no deadlock under load. No GC,
  no safepoints yet.

### A3 — `SuspendOthers`/`ResumeOthers` Wired to `ngcs_request_stop`/`ngcs_resume`
- Implement WTHREAD's `SuspendOthers`/`ResumeOthers` as the same entry points the
  collector already calls on x86_64 (confirming the abstraction from the table
  above), backed by the cooperative `ngcs_request_stop`/`ngcs_resume` mechanism
  instead of signals.
- Safepoint check (see Phase B) must consult `inCritical` before honoring a stop
  request, mirroring `SignalHandler`'s refusal to stop a thread mid-critical-section.
- **Test:** Manually trigger `SuspendOthers` from a test-only hook; confirm all
  WTHREAD threads voluntarily park at their next safepoint (respecting `inCritical`),
  confirm the parked count reaches target, confirm `ResumeOthers` cleanly resumes all
  threads via the two-phase handshake. Still zero shadow-stack involvement — this
  isolates the coordination mechanism exactly as Milestone 8 did on x86_64.

---

## Phase B — `m3llwasm` Codegen: Safepoint Checks and Shadow Stack

Entirely new codegen, entirely contained within `m3llwasm`. `m3llhost` is not
touched — it only ever emits x86_64 code and already has its own working safepoint/
write-barrier emission.

### B1 — Safepoint Check Emission
- Emit the cooperative safepoint check at function prologues and loop back-edges in
  `m3llwasm`, branching into the WTHREAD park path, gated by `inCritical` exactly as
  in A3.
- **Test:** Compile and run existing wasm32 programs; confirm no behavioral change
  (nothing actually parks yet, since nothing is driving `SuspendOthers` in real
  program flow). Analogous to old Milestone 7b, scoped to `m3llwasm` only.

### B2 — Shadow Stack Spill/Fill Codegen
- Emit spill/fill sequences for TRACED locals against a linear-memory shadow stack
  in `m3llwasm`; populate the shadow-stack pointer/depth fields reserved in A1.
- **Test:** Verify by inspection/printf (same spirit as the original header-layout
  sanity check) that shadow stack contents are correct and left in a fully
  consistent state at every point a thread could park — not mid-spill. This is a
  pure codegen-correctness test, independent of the collector.

---

## Phase C — Shadow Stack Root-Feeding Investigation (open problem)

**This phase exists because the answer is not yet known.** Do not treat any later
phase as unblocked until this one produces a concrete design. Suggested investigation
steps, not milestones with fixed deliverables:

- Examine exactly how the x86_64 collector currently obtains `stacks.context`/
  `stacks.bsp` from PTHREAD's per-thread structures — is this reached via `RTThread`,
  or does the collector reach directly into PTHREAD-owned storage? This determines
  whether the existing coupling is already "collector reaches into runtime module
  storage by convention" (in which case WTHREAD exposing an equivalent field in the
  same convention is sufficient), or something more bespoke to PTHREAD specifically
  that has no obvious wasm32 analog.
- Determine where the shadow-stack pointer/depth pair populated in B2 should be
  *read from* by the collector: directly from `M3_Thread_Context` (if the collector's
  existing access pattern already goes through a context-like structure), or via a
  new small accessor exposed by WTHREAD, matching however the question above resolves.
- Determine whether the shadow stack needs to be walked while the owning thread is
  parked (analogous to scanning a conservatively-parked native stack) or whether
  there's a reason to snapshot/copy it at park time instead — this affects whether
  Phase B2's "consistent at every park point" requirement is sufficient on its own,
  or whether additional synchronization is needed between the parked thread and the
  scanning coordinator.

**Exit criterion for this phase:** a concrete, written-down design for how the
collector obtains a scannable root range from a parked WTHREAD thread's shadow stack
— reviewed before Phase D begins, since Phase D's synthetic-heap test depends on it.

---

## Phase D — Wire Shadow-Stack Scanning Into the Coordinator

Depends on Phase C's design being settled.

### D1 — Synthetic Heap, Deterministic Scan
- Implement the scan function per Phase C's design; validate first against a
  hand-built synthetic scenario (known live/dead objects at known shadow-stack
  depths) — same discipline as the original Milestone 9a.
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

---

## Phase E — Exception Handling Parity for wasm32

The existing `RAISE`/re-throw/root-clearance logic is proven on x86_64 (baseline,
above) but depends on `m3llhost`-specific codegen and the x86_64 safepoint check.
Needs a `m3llwasm`-side equivalent once Phase D is stable — deferred until then,
since (per the original hard dependency) the safepoint check inside `RAISE` is
untestable without a genuinely working GC coordinator underneath it.

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
| B (B1–B2) | Per sub-milestone | New codegen confined to `m3llwasm`; `m3llhost` untouched |
| C | Investigation, not code | Open problem — must produce a design, not just working code, before D can proceed |
| D (D1–D3) | Per sub-milestone | Mirrors the risk profile of the original native GC-coordination phase, now scoped to wasm32 |
| E | Per milestone | Depends on Phase D being complete and stable, same dependency shape as the original exception-handling phase |
