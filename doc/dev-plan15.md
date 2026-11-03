# Incremental Development Plan: wasm32 Threading, Safepoints, GC Integration, and the Core Library

**Plan v15 — checkpoint 2026-11-02**

**Scope:** CM3-derived Modula-3 compiler. The x86_64/Linux target, via the `m3llhost`
backend and the existing PTHREAD runtime module, is an **already-working baseline**.
This plan covers only the **new work required for the wasm32 target**, built through
the new `m3llwasm` backend and a new `WTHREAD` (`WThread`/`nthr`/`nsyn`) runtime
module, and (since v12) the work to bring the Modula-3 core library up on wasm32. Since v13
the WTHREAD runtime is also wired into m3neos as `pkg/neocore` (an `m3core` built on `WTHREAD`,
x86_64 for now, next to the PTHREAD-based `pkg/neosys`); that build is the vehicle on which
stop-the-world, pinning and the heap-tracing behaviour are tested under the real collector.

**Revision note (this version, v15):** v15 closes **Phase C stage 3 (the `ms9` harness)** on x86_64 and records what it
found. Nothing from v14 is dropped; sections are updated in place. The analysis note
(`claude/optimisation-and-visibility-analysis.md`) is unchanged.

- **ms9 validated (cases 1 to 8; the local-`REF` variant runs of cases 1, 2, 3 and 6 are the only matrix cells left).** Fixed and
  open arrays (depth 1, 2 and 3, bytes and `REF` elements), interior views (`WITH`, `SUBARRAY`, `VAR`), `VALUE` open-array
  parameter copies (1-D and 3-D), by-value records and fixed arrays holding `REF`s two levels deep (as a local copy, a module
  global and a `VALUE` parameter), and a text-heavy threaded smoke test all ran under the unmodified collector and WTHREAD
  stop-the-world with every content assertion intact. The case matrix with results is in Phase C, stage 3.
- **Open arrays move correctly at every depth tested.** The elements pointer of the dope is rewritten as `np + dataSize`; three
  open dimensions (a 40 by 40 by 25 byte array, 40,000 elements verified after every move), two open dimensions of `REF`
  elements, an open outer dimension over a fixed inner one, and a by-value 3-D copy all passed. A pinned multi-dimensional
  `REF` array is traced through its page and its referents still move and are fixed up.
- **Views pin; copies are independent; second-level references follow.** An interior view (`VAR`, `WITH`, `SUBARRAY`) keeps its
  array's page where it is; a `VALUE` open-array formal is a heap copy whose writes never reach the source. For a by-value
  aggregate held on the stack, the objects it points at stay (page pin) while the objects *they* point at move, through the
  pinned impure page, and the pointers follow.
- **The minor fix (register 47, closed): `ClassifyVar`.** The first ms9 build failed LLVM verification
  (`llvm.gcroot parameter #1 must either be a pointer alloca...`). The front end declares the 24-byte dope temporary of an
  open-array `NEW` with the `REF` type's UID, so `ClassifyTrace` called it a scalar root although the alloca is a struct. The
  back end now decides per variable: a Scalar classification is kept only when the variable's own representation is a pointer.
  `ClassifyTrace` is untouched, the front end is untouched, and `m3llhost` is unaffected (the change is in `m3llwasm`).
- **The smoke test (case 8) ran twelve threads, four of them allocating text flat out**, about 987,000 loop iterations in one
  run, with eleven collections (six explicit, five allocation-triggered) and no corruption.
- **Bounded heap: the mechanism is now identified (register 41, updated).** Stress runs with a capped traced heap failed
  intermittently with `NEW() was unable to allocate more memory`. A debugger trace shows the failure happens while an
  **incremental collection is in flight**, and that the allocator gives up without finishing the collection and retrying.
  The collector documents its own space bound (about four times the live pages when incremental, three when stop-and-copy);
  the 20 MB and 22 MB caps sit at that bound for this workload. With `@M3noincremental` the same 20 MB cap passed 10 of 10
  runs; at 32 MB incremental also passed 10 of 10. This is a design bound, not a defect, but it fixes how the wasm32 cap must be
  chosen and exposes two robustness gaps (register 48).
- **Harness rules added (Phase C rules 9 to 13).** Keep small allocations off an array's last page (`burnPage`); log the address
  of an element to see a referent move when its container is pinned; check row identity, not only content; do not pass the
  array under test through a long-lived formal; pause before closing the logger.
- **Evidence this sprint.** All runtime evidence is from the user's runs on x86_64 under `pkg/neocore` (logs listed in Phase C,
  stage 3). My part: log-decoding scripts, the code review of every harness revision, and reading the runtime sources in the
  repo to explain the out-of-memory trace. **No wasm32 run of the collector has happened yet** (registers 30, 31, 44).
- **Road ahead.** Compile for wasm32 (registers 3, 8, 23), then the audit gate on `neocore` bitcode (42), then the wasm32
  collector smoke test (44), now using ms9 itself as the regression suite. Then the bounded-heap work (41, 48, 49). See
  "Near-term sequence".
- **Register:** all earlier numbers are stable. Closed or updated at this checkpoint: 11, 41, 46. New items are 47 to 50.

**Previous revision note (v14, condensed):** v14 closed Phase C stage 2 (`ms8`: embedded `REF` fields in a heap record and an object,
65 of 65 stay/move outcomes explained) and decided the **root strategy: roots stay conservative** on both targets (the unmodified
collector, whole-stack scan through `ProcessStacks`/`NoteStackLocations`, pin-only; `llvm.gcroot` keeps traced values in memory and
was never meant to make roots precise; precise roots, the chain walk 25b, `WalkStack` and aggregate root-slot addressing 13 parked).
It explained the n=3 residue pins as `llc -O0` spill slots in the subject's own frame (helper procedures remove them), recorded the
constraints on the optimiser and `llc` levels (any `llc` level -O0 to -O3, no IR-level optimiser), added the wasm32 visibility
harness and the SSA-across-safepoint audit (a gate, register 42), observed collector behaviour under a 6 MB traced cap (register
41), and added two working rules (one variable per experiment; capture stdout and stderr).

**Previous revision note (v13, condensed):** v13 closed the wiring and pinning sprint. WTHREAD became the thread
implementation of `pkg/neocore` (`beta.17`, `beta.18`); the startup shape was settled (the nthr context becomes an
untraced ref record paired with an untraced `Axis` record owned by `WThread.m3`; `Init`, `InitialThread`, `Fork`);
`nthr_lock` (a safe-region lock with a `no_park` mode) and the watch-transition rules were recorded (Phase A addendum 3);
the heap-lock invariant for `SuspendOthers` was recorded; `ProcessStacks` was implemented (whole-stack ranges plus `regs`
of every non-detached thread to the unmodified `NoteStackLocations`) and pinning validated with `ms7` (stage 1); the
collector pins its own highest page (accepted, register 38); the principle was extended so that `RTCollector.m3` stays
unmodified and byte-identical in `pkg/neocore` and `pkg/neosys`. Registers 19, 22, 24, 25, 26, 28 were closed or updated and
33–40 were new.

**Previous revision notes (v10 to v12, condensed further):** v12 closed the nthr/nref review sprint: exit, join and reap redesigned
(the exiting thread signals under `joinSyn`; `nthr_vigil` releases `joinSyn` around `nthr_arch_reap32`, `pthread_join` on x86_64 and
a wait on an `ended` flag on wasm32); the context layout settled (`regs` as `uintptr_t regs[NREGS]`, `ended` last, `thread_match`
first in `WThread.Init`); the safepoint re-check ordering decided; `nref` size options accept `K` and `M`; the wasm32 target triple
became `wasm32-wasi-threads`; the libc-surface survey produced Phase L. v11 recorded the stop-the-world and parking work (publish
order, state restore after a poll-initiated park, lost wake-up, tail race in `nthr_wait`, starvation; adopted design: `safeSyn` is
both mutex and condition for parking, a `parked` counter drains the previous stop before the next, `dangerSyn` retired, `parkSyn`
renamed `watchSyn`), loop-edge polls and WTHREAD codegen through `m3llwasm` on x86_64. v10 closed parameter rooting (real `m3t`,
size, alignment and `inProc` on parameter slots in `begin_procedure`), corrected B1.4 (park iff `watch >= vigilant`), added the LLVM
root-initialisation rule to B1.2, closed objects (scalar roots; fields reached through the header typecode), moved the open-array
VALUE parameter copy to the arrays sprint, and parked the opaque-type `traced` fix (register 12, reminder carried).

Carried forward unchanged in substance: `BITS N FOR T` packed fields (deferred), the `superType` correction sprint
(deferred), the `BuiltinTypes.KindUID` future note, the `refs_only`/`gc_map` finding, the target-description rename and
datalayout findings, nested procedures on wasm32 (parked), and the frozen-baseline principle.

---

## Standing principle: the x86_64/`m3llhost` baseline is frozen

Established gradually, then named explicitly and treated as forceful going forward.
**Read from freely — algorithms, data structures, existing proven logic — but never
modified, and never made conditionally different, regardless of how well-reasoned or
minor the wasm32-side benefit would be.** This governed, directly:

- The original PTHREAD/WTHREAD split (wasm32 gets its own runtime module; PTHREAD
  untouched).
- Rejecting `Call_direct`'s `m3t` on the shared `M3IR_Asm` interface — confined to
  `IR.Call_direct`'s own front-end parameter instead.
- Rejecting a "generate metadata unconditionally in the front end" hybrid — even
  though it would have avoided writing a second bytecode compiler, because it would
  have meant x86_64 carrying permanent, un-strippable data for a feature it never
  uses, and (in the front-end-conditional-generation variant) the AST itself
  diverging structurally per target for the first time in this project.
- Rejecting a direct call from `m3llwasm` into `TipeMap.Finish` — not just a
  process-boundary problem (the front end's `Type.T` never reaches the backend at
  all), but a restructuring of proven, decades-stable machinery both targets
  currently depend on.
- The resolution actually adopted: **copy `TipeMap`'s core encoder into a new,
  wasm32-owned module (`TypeComp`) and drive it from `debugTable`/`RecordDebug`
  instead of `Type.T`.** Reuse the *knowledge* (the algorithm, proven since 2001 per
  the upstream CM3 repo's own history), never the *code path*, whenever the code
  path would touch anything x86_64 depends on.
- (B1) The `Target.m3` plan for a generic wasm32 system: it must be excluded
  from the 32-bit alignment downgrade applied to non-C backends, precisely so that
  `m3llhost` output is unchanged.
- **(v15)** The `ClassifyVar` fix (register 47) was made in `m3llwasm`'s own `LLVM_WASM.m3`, not in the front end that creates the
  odd temporary, and not by overriding the shared `ClassifyTrace`: the abstraction-correct place was the per-variable decision.

**Scope note (refined since v8).** Two things are explicitly *not* violations:
(1) modernising x86_64 output to track the LLVM toolchain (e.g. the function-attribute
cleanup recorded in B1: `uwtable` as an integer-valued attribute, the calling
convention set through `LLVMSetFunctionCallConv`, deprecated `unsafe-fp-math`/
`use-soft-float` dropped) — the baseline is frozen against *behavioural* drift, not
against keeping pace with LLVM; and (2) running the new `m3llwasm` backend against
an x86_64 target description (see Target descriptions below, and the register's
WTHREAD-on-Ubuntu item), because that is a separate backend and runtime module.
New functionality targets wasm32.

**Applied to the core library (v12).** Phase L changes are made behind a wasm32/WASI guard
(`m3core.h` and per-target module selection), so the x86_64 build of `m3core`/`libm3` is
unchanged.

**The collector is part of the baseline (v13).** `RTCollector.m3` (with `RTHeapRep`, `RTAllocator`
and `RTHeapMap`) is read from freely and **not modified**. The copy in `pkg/neocore` is
byte-identical to the one in `pkg/neosys`. Behaviour the collector exhibits is documented and
designed around, not patched. Phase C was done this way: pinning is fed to the unmodified
`NoteStackLocations` through `RTThread.ProcessStacks`, the one entry point the collector gives the
thread package. Diagnostics placed in `RTCollector.m3` while investigating (the per-hit trace in
`NoteStackLocations`, and in ms9 the `GCKIND` and `PROMOTE` lines) are temporary and are reverted before a checkpoint. The accepted consequence
of this choice is recorded in Phase C ("The collector pins its own highest page"). The working motto:
*the enemy of good enough is better.*

**What the principle means in practice (clarified 2026-10-29).** The absolute wording above states
the default. The focus of the changes is WTHREAD and `m3llwasm`. In places it is necessary to change
code outside them, which is the domain of the existing x86_64 implementation. The cases so far are
front-end changes that thread `m3t` through the various stack levels and re-instate it in procedure
declarations, and the startup code around `InitialThread` (the default-thread launch). Besides these
there are LLVM toolchain modernisation (scope note above), version upgrades and clear errors. Each
was a deliberate, named decision taken because the work could not be done otherwise; the default
remains to read and not to change.

**Roots are conservative; the collector gets no precise-root API (v14).** The decision below keeps the
collector exactly as it is: stack words are nominated as ambiguous roots, referents of stack words are pinned,
and no stack referent is ever moved. A collector change would be needed only to move stack referents, which is
neither wanted nor safe while unrooted derived copies exist (Phase B2, derived-copy rule). Where a design needs
the type map of a stack-resident record it is our own code (in `WThread`) that would interpret it, as `TypeComp`
already does at compile time, never the collector.

**The bounded heap does not change this (v15).** The out-of-memory behaviour found under a capped heap (register 41) is
a property of the documented space bound and of the allocator's slow path. Options that touch `RTAllocator.m3` or
`RTCollector.m3` are listed in register 48 as options, not decisions; none is adopted. Sizing the cap to the documented bound
needs no change to either file.

Any future decision that would touch `m3llhost`, `TipeMap`, or any other
x86_64-shared machinery — however small — should be checked against this principle
first.

---

## Decision (v14): roots are conservative; gcroot keeps traced values in memory

**Status: decided 2026-10-31**, after the ms8 results, the wasm32 visibility harness and the audit. It supersedes the
v12/v13 intention (register 25) of walking each thread's `llvm_gc_root_chain` precisely. Re-open conditions are listed below.
**(v15) ms9 supports the decision on x86_64:** nothing in arrays, views, copies or by-value aggregates needed the chain or
the composite metadata; every case was served by the whole-stack scan (stack-held cases) or the heap type maps (heap cases).

**What is decided**

1. **Stack roots are found by the existing conservative scan.** `RTThread.ProcessStacks` feeds each non-detached
   thread's whole stack range (`stack_ptr..stack_top`) and its `regs` array to the unmodified `NoteStackLocations`.
   Pin-only: whatever a stack word points to stays where it is. The same mechanism serves x86_64 and wasm32.
2. **The compiler's obligation is memory residence.** Every traced value that is live across a safepoint must have a
   home in memory inside the thread's stack range. Variables and front-end temporaries are allocas; traced scalar
   variables and traced temporaries are `llvm.gcroot` slots, which is what keeps them in memory (and, were an optimiser
   ever added, keeps them there). On wasm32 a value held only in a wasm local, or on the wasm operand stack, is invisible
   to any scan.
3. **`llvm.gcroot` is a visibility guarantee, not a precision mechanism.** The shadow-stack chain and the frame map exist
   and are maintained (thread-local head, published at park time), but nothing in the collector path reads them.
4. **Composite roots stay as built and validated and stay dormant.** `TypeComp` metadata, the marker workaround and
   aggregate gcroots are not removed and not extended. Nothing consumes the metadata; the aggregates are visible to the
   conservative scan with no map (wasm32 harness, case 2).
5. **Parked by this decision:** the chain-walk pinning of `llvm_gc_root_chain` roots (25b), `WalkStack` in `RTTypeMap`
   (Phase D prerequisite), aggregate root-slot addressing (13), the `type_map`-versus-`gc_map` question for stack walkers
   (9), and Phase D's D1–D4 as a group. They stay documented (Phase D, parked) so that nothing has to be rediscovered.

**Why**

- gcroot was adopted because statepoints need native stack unwinding (which wasm lacks) and because a plain alloca is
  eliminated by `mem2reg`; its job is to put traced values in memory. The composite metadata was a consequence of rooting
  aggregates, not a goal.
- Under a pin-only collector, a type map can add only **precision** (no false pins from integers that look like pointers).
  It cannot add **visibility**: the gcroot slots and the aggregates are in the scanned range anyway.
- Precision is cheap to give up: the whole-stack scan is on the order of 10–30 µs per collection in ms8 (about 4,000
  words, an estimate) against roughly a millisecond for a collection that copies about thirty large objects; the retention
  cost is at most one 64 KB page per false pin. It could matter more on wasm32, where heap addresses are small numbers and
  the heap is bounded (register 41), but nothing measured says so yet.
- Moving stack referents would need a collector change and would turn the derived-copy rule from an audit rule into a hard
  requirement. Rejected under the standing principle.
- *Make it work first.* The mutator-side cost of gcroot is the same whichever way the collector reads roots (measured: about
  1.5 ns per call of a function with roots, x86_64, general-dynamic TLS; see the analysis note), so it is not an argument for
  or against precision.

**What would re-open it**

1. A requirement that stack referents move or compact.
2. Measured false retention in bounded wasm32 heaps that matters (register 41).
3. An optimiser (Phase O) that needs aggregates and arrays rooted: the first step would then be **address roots with null
   metadata** (the aggregate stays an ordinary aligned alloca and a gcroot slot holds its address, which keeps it in memory
   under an optimiser and retires the marker workaround and both LLVM-bug dependencies), not a precise walker.
4. A failure of the visibility assumptions on the real wasm32 toolchain (registers 42, 44).

### Constraints on the optimiser and `llc` levels (correctness of the current scheme)

The scheme is correct **only if no traced value lives in a wasm local (or an LLVM SSA value) across a safepoint without also
having a memory home in the thread's stack range.** `m3llwasm` emits IR with that property by construction: it is a stack
machine over memory (every expression intermediate goes through a `tmp.N` alloca), and the audit confirms it. What may and
may not be done to that IR follows.

| Stage | Permitted | Not permitted | Evidence |
|---|---|---|---|
| `m3llwasm` IR to object, `llc` codegen level | Any of **-O0, -O1, -O2, -O3**, with **no** IR-level optimiser first. `-O0` is the validated level for every x86_64 run so far (ms7, ms8, ms9). `-O1`+ removes the `-O0` spill slots (recrTest frame 1000 to 392 bytes, 82 spill slots to 0) and so removes the stale-slot pins of ms8, at the price of stale values in registers (scanned through `regs[]`). | | wasm32 harness: identical visibility results at `llc` -O0, -O1, -O2, -O3 (cases 1, 2, 3, 6 found; case 4 invisible as expected; control clean). Audit: 0 live-across pairs on the IR llc consumes. |
| Any mid-end optimiser (`opt`, `clang -O1`+ applied to the `.ll` or bitcode, LTO, inlining, mem2reg, SROA, GVN, instcombine, LICM) | | **Not permitted** until Phase O's entry criteria are met. | `opt -O2` on ms8's IR: 483 call sites, **2,781** pointer values live across a safepoint, **2,702** with no memory home (slot copies 2,015; call results 292; phis 195; heap loads 103; ptrtoint 91). Without gcroot calls every pointer alloca is promoted (recrTest 23 to 0). With gcroot only the 14 rooted slots survive. |
| C runtime built by clang (`nthr`, `nsyn`, `nref`, `RTIOc`) | Any optimisation level. | Holding a **traced** reference across a call that can reach a safepoint. | These files traffic in untraced contexts, raw arenas and stack addresses by design. Re-check whenever a C file starts to touch traced memory. |
| Library Modula-3 (`m3core`, `libm3`) compiled by `m3llwasm` | Same rule as user code: `llc` -O0..-O3, no `opt`. | | **Unaudited** (no wasm32 library IR yet). The audit gate applies before the first wasm32 run (register 42). |
| Changes to `m3llwasm` or the front end that alter IR shape (for example keeping expression values in SSA instead of temporaries) | Allowed after the gate. | Landing without it. | Any such change must re-run the audit and the harness. |

**Rules that follow**

1. **Audit gate.** `audit.py` must report **zero not-homed pairs** on every `.ll` or bitcode that will run under the collector
   (project doc `claude/audit.py`). It must be run on the **`neocore` bitcode produced for wasm32 as soon as we can compile
   for that target** (registers 3, 8, 23), and again after any `m3llwasm`/front-end change that alters IR shape. A nonzero
   result is a correctness finding, not a warning. **(v15)** The `ClassifyVar` change alters which variables receive a gcroot, so
   the audit is to be re-run on a build that contains open-array `NEW` (the ms9 build) before the wasm32 audit.
2. **Harness gate.** The wasm32 visibility harness (analysis note) must pass at the chosen `llc` level; it is the cheap check
   that a codegen change did not introduce a cross-call wasm local.
3. **No individual `opt` pass is certified.** If a subset of passes is ever wanted it must pass rules 1 and 2 on real output.
4. **Changing the `llc` level is a one-variable experiment**: rerun ms8 and ms9 at the new level before
   adopting it. `llc -O1` is also the natural way to try to obtain the first `regs[]` pin (register 46).
5. **The derived-copy rule stays an audit rule** while the optimiser is excluded. It becomes load-bearing only in Phase O.

### Audit and visibility results (summary; detail in the analysis note)

- **Audit** (`audit.py`, run on the two ms8 builds that exist as bitcode, same source before the helper-procedure
  restructure): 463 and 462 safepoint call sites over 18 functions (469 over 19 including the module body); **0** pointer values
  live across a safepoint. The script analyses every function by default and warns on an empty result (a first version filtered
  silently to the test program's names; fixed before first use on library bitcode). Validated
  against six known-bad controls (pure SSA across a call; stored before the call; stored after the call; parameter used
  after the call; allocation result held across a call; value live around a loop back-edge), all correctly flagged.
- **wasm32 visibility harness** (freestanding module, sandbox, Node 22): scalar gcroot, aggregate gcroot with a `REF` word,
  nested gcroot frames and (at `llc` -O0..-O3) ordinary variables are found by a conservative scan of the range
  `__stack_pointer..stack top` (the `nthr_arch_stack32` mechanism); a pointer held only in a wasm local is not found; an
  unreferenced control is not found. All gcroot frames of the chain lie inside the scanned range.
- **Not covered:** another thread's stack (publishing the right `sp`/top at park time on wasm32 is covered only by the earlier
  node thread harnesses), a real collector on wasm32, library code, and constructs ms8 and ms9 lack (exceptions, nested
  procedures). **(v15)** ms9 adds open arrays, views, by-value aggregates and text to the *runtime* evidence on x86_64, but no ms9
  build has been audited yet (see rule 1).

---

| Status | Item |
|---|---|
| ✅ Reused, revised in v11 | `SuspendOthers` / `ResumeOthers` (WTHREAD only; PTHREAD untouched): same bracket, protocol revised — see the Phase A addendum. |
| ✅ Confirmed by build config | Target exclusivity via `TARGET=wasm32`/`M3_BACKEND=Wasm` — unchanged. |
| ✅ Decided (v14) | **Stack roots are conservative on both targets** (whole-stack scan through `ProcessStacks`/`NoteStackLocations`, unmodified collector, pin-only). gcroot is a visibility guarantee. The chain-walk half (25b) is not required. See "Decision (v14)". |
| ✅ Complete, tested (Phase A) | WTHREAD thread lifecycle, cooperative `SuspendOthers`/`ResumeOthers`. Parking protocol revised in v11. **v12:** exit/join/reap protocol revised and verified in my harnesses (trimmed copies; x86_64 and wasm32 under node) — see the Phase A addendum 2. **v13:** `nthr_lock`, the watch-transition rules and the heap-lock invariant recorded — see the Phase A addendum 3. |
| ✅ Implemented, validated on x86_64 (Phase B1) | Safepoint check emission (park iff `watch >= vigilant`); gcroot frame scaffolding (entry → prolog → body); aggregate-root marker workaround; thread-local `llvm_gc_root_chain`; loop-edge polls. **Not yet validated end to end on wasm32** (blocked on `Target.m3`, below). |
| ✅ Complete, verified (Phase B2) | `m3t` propagation chain; `ClassifyTrace` scalar/composite dispatch; composite `gcroot` metadata, byte-verified (now dormant, v14). `Gen_Call_indirect`/`Invoke_indirect` sourcing resolved. |
| ✅ Closed (v15) | **`ClassifyVar` guard (register 47):** a Scalar classification is kept only for a variable whose own representation is a pointer. Fixes the verifier failure on the open-array `NEW` dope temporary. |
| ✅ Implemented, verified by IR inspection and audit (Phase B2) | Parameter rooting (v10). The audit (v14) shows that no parameter value is used across a safepoint (all are spilled to slots at entry). |
| ✅ Closed (Phase B2) | Objects: scalar root; fields reached through the header typecode and the runtime type map. |
| ✅ Closed (v12) | **nthr/nref review sprint**: `regs`/`ended` layout, `thread_match`, join/reap protocol, safepoint re-check ordering, `nref` K/M suffix. Small leftovers are register 27–28. |
| ✅ Closed (v13) | **Wiring and pinning sprint**: WTHREAD wired into m3neos as `pkg/neocore` (`beta.17`/`beta.18`); startup shape; `nthr_lock`; watch-transition rules; `ProcessStacks` implemented. |
| ✅ Validated (v13) | **Conservative `ProcessStacks` pinning, stage 1** with the `ms7` harness. |
| ✅ Validated (v14) | **Phase C stage 2 (`ms8`): embedded `REF` fields in a heap record and an object**, under the unmodified collector: fields walked and rewritten (also for pinned owners), contents intact, 65 of 65 stay/move outcomes accounted for. |
| ✅ Validated (v15) | **Phase C stage 3 (`ms9`): arrays (fixed, open, multi-dimensional, `REF` elements), interior views, `VALUE` open-array copies, by-value aggregates two levels deep, text-heavy threaded smoke test**, under the unmodified collector, on x86_64. Open cells: local-`REF` variants of cases 1, 2, 3, 6 (register 46). |
| ✅ Validated (v14) | **wasm32 visibility harness** and **SSA-across-safepoint audit** (analysis note). Gates for the next steps (register 42). |
| ✅ Explained (v14) | **Stale-pointer pins from `llc -O0` spill slots** in the subject's own frame (register 45). An accepted pin class, like the collector's own highest page. |
| 🅿️ Accepted (v13) | **The collector pins its own highest page** (register 38). At most one page per collection; the collector stays unmodified. |
| 🔶 **Next (v15)** | **Compile for wasm32** (registers 3, 8, 23), then the **audit gate on `neocore` wasm32 bitcode** (42), then the **wasm32 collector smoke test** (44) with ms9 as the regression suite, then the **bounded-heap work** (41, 48, 49). |
| 🔶 Open (mechanism identified, v15) | **Collector behaviour under a bounded traced heap** (register 41): the failure mode and the documented space bound are known; the cap must be chosen from the bound; two robustness gaps are options for later (48). Matters because `--max-memory` is mandatory on wasm32. |
| 🔶 **New, before Phase E (v12)** | **Phase L — core library on wasm32**, two stages: (1) use wasi-sdk's libc as is; (2) backfill the system calls WASI lacks (register 23). |
| 🔶 Open (wasm32 enablement) | `Target.m3` generic wasm32 system; debug-info NIL element; remaining wasm32 attribute cleanup (waits on Phase L stage 1). (`LLVMVerifyModule` is done; the target triple is `wasm32-wasi-threads`.) |
| 🔶 Open (upstream) | Two LLVM bugs to report (reproducers ready); WAMR issues to report (register 30). |
| 🅿️ Parked by decision (v14) | **Precise stack roots**: chain-walk pinning (25b), `WalkStack`, aggregate root-slot addressing (13), `type_map` versus `gc_map` for stack walkers (9), Phase D (D1–D4). Re-open conditions in "Decision (v14)". |
| 🅿️ Parked by decision | Opaque-type `traced` derivation in `declare_opaque` (register 12 — reminder carried). |
| 🅿️ Parked | Nested procedures on wasm32 (`nest` static-link attribute unsupported by the wasm backend). |
| 🔲 Future, not scheduled (v14) | **Phase O — optimiser enablement.** Entry criteria in its section. |
| ✅ Closed (2026-10-29) | Startup ordering for the default thread (register 22). |
| 🔲 Deferred, own sprint | `InitUids`'s `superType` fields (DWARF-correctness only). |
| 🔲 Deferred, scope | `BITS N FOR T` packed fields; exception handling (Phase E). (Fixed and open arrays, including the open-array VALUE parameter copy, are no longer deferred: exercised by ms9 in v15.) |
| 🔲 Future note | `BuiltinTypes.KindUID` — backend should consume the front end's computed builtin TypeUIDs instead of hard-coded `UID_*` constants. |

---

## Near-term sequence (rewritten in v15)

In order. Each step is a prerequisite for, or de-risks, the next. Steps 1 to 3 are unchanged from v14; ms9, which was step 4, is
done on x86_64 and its remaining cells are folded into step 4; the bounded-heap step now starts from an identified mechanism.

1. **Compile for wasm32.** `Target.m3` generic wasm32 system (register 3), the remaining wasm32 attribute cleanup (8) and Phase L
   stage 1 (23): the system dependencies built for wasm32 so that the front end can build user-space programs and `neocore`.
   This is close, and it unblocks everything below.
2. **Audit gate on `neocore` wasm32 bitcode (register 42).** Run `claude/audit.py` over the bitcode produced for wasm32
   (`neocore` library modules and a test program) and require zero not-homed pairs; run the wasm32 visibility harness at the
   chosen `llc` level. Include an **ms9 build** (it contains open-array `NEW`, views, by-value aggregates and text, none of which
   ms8 had, and it is the first build compiled with the `ClassifyVar` guard). A nonzero result is fixed in `m3llwasm`/the front
   end before anything runs under the collector.
3. **wasm32 collector smoke test (register 44), with ms9 as the regression suite.** `ProcessStacks` and the unmodified collector
   on wasm32, single thread first under node, then multiple threads (the coordinator reading another thread's published
   `sp`/top), then WAMR (30, 31). Run the ms9 subjects in this order: first the ones that do not depend on the stack (`aggGlobTest`,
   the module-global arrays, `valMultiTest`), then the stack-dependent ones (`aggLocTest`, `aggValTest`, the interior-view and
   `VALUE` cases), whose pass depends on a frame copy being in memory the scan covers. A failure of only the stack-dependent subjects
   means a visibility problem; the x86_64 results are the reference.
4. **ms9 residue (register 46), x86_64, as convenient:** the local-`REF` variant of cases 1, 2, 3 and 6 (one edit each: move the
   outermost variable from a global to a local of the subject), sizes 1 and 100 for case 2, and a `regs[]` hit (try `llc -O1`).
5. **Bounded heap (registers 41, 48, 49).** Decide the wasm32 collector mode (does `m3llwasm` set `Host.doIncGC` or `Host.doGenGC`
   by default? register 49), measure A (the pages of accessible objects) for representative wasm32 programs, size `--max-memory`
   from the documented bound, and decide whether the two robustness gaps (allocator collect-and-retry; the collector's own
   allocation in `InitStack`) are worth closing before wasm32 programs run under a tight cap.
6. **Small items, as convenient:** the heap-lock invariant for `After`/`VisitAllRefs` (34); the library poll policy (35); the
   unclaimed-thread reaper and the slot table (37); the v12 leftovers (27, 28); diagnostics hygiene (40).
7. **Phase L stage 2 (register 23)**, then `Target.m3`-dependent cleanup, then Phase E.
8. **Phase O (optimiser enablement)** only when measurement says it is worth it and its entry criteria can be met.

---

## Baseline (no new work) — x86_64 / Linux via `m3llhost` + PTHREAD

Unchanged; documented for reference only. `m3fe` produces target-invariant IR;
`m3llhost` emits LLVM bitcode via `M3IR_Asm`. The proven card-table/write-
barrier/safepoint/stop-the-world/conservative-scan collector is unchanged, via
`RTThread.ProcessStacks`/`NoteStackLocations`. `RTType`/`RTTipe`/`RTTypeMap` are
runtime interfaces (linked into the *target* program); `RTTipe`'s own front-end
producer is `TipeDesc.i3`, a third, separate module from `TipeMap` — serves
`RTPickle`'s cross-architecture concerns, not the collector's, and is out of scope
here entirely.

**How the front end and backend are split (reference for everything below).** The
`.ast` is a linear, target-invariant serialization of `M3IR_Asm` calls: the front end
(parser, `IR.m3`) writes it, the backend replays it into LLVM-C calls. Front-end-only
types: the `ValRec` stack, `Type.T`, the front-end `Proc`. Backend-only types:
`LvProc`, `LvExpr`, `LvVar`. `IR.m3` treats `Proc`/`Var` as opaque handles. Every
`M3IR_Asm` change must reach all of its writers, readers and implementers — binary
and ASCII reader/writer, `Tee`, `Check`, `DoNothing` — and **defaulted `:=`
parameters on `M3IR_Asm` procedures can silently drop data** (`return_typeid` was the
case that surfaced this).

**AST conventions worth remembering.** `m3t` is a `TypeUID`; `NO_UID` is `16_FFFFFFFF`
(printed as `-1`). `declare_param`/`declare_local` sizes and alignments are in **bytes**
in the AST (e.g. `8 8`, `1 1`). Front-end temporaries are `declare_temp` entries;
those printed as `Addr -1` carry no type and classify as `None`. **(v15)** A temporary's
`m3t` is not always the type of its *representation*: the dope temporary of an open-array `NEW` (`New.m3`, `GenOpenArray`)
is declared with the `REF` type's UID but is a 24-byte struct; `ClassifyVar` (register 47) is the guard.

**Build pipeline fact (v14).** The `m3neos` driver compiles each unit with `m3front`, then `m3llwasm -b -g -t <target>`, then
`llc -frame-pointer=all -mtriple=<target> -filetype=obj -relocation-model=pic -O0`. **There is no optimiser in the pipeline**
(confirmed by the user from the full command listing). This is the premise of the optimiser constraints above.

**Runtime parameters used by the harnesses (v15, reference).** `@M3traced=<n>[K|M]` and `@M3untraced=<n>[K|M]` cap the traced and
untraced arenas (a plain number is bytes); `@M3virtual=<n>` is retained as the temporary WAMR workaround; `@M3noincremental`
selects stop-and-copy collection (`RTCollector.Init` checks `noincremental`; `nogenerational`, `nogc`, `heapstats` and
`paranoidgc` exist as well). Capture both stdout and stderr (`2>&1 | tee`).

---

## Target descriptions and datalayout (m3llwasm)

Findings recorded so they are not rediscovered:

- **Renames.** `AMD64_LINUX` was renamed `x86_64`; it carries the **proven,
  historical datalayout** (`e-m:e-p:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128`,
  as in the current `phb.ll`). The modern x86_64 datalayout string became `CUR_X86_64`,
  **opt-in only**. The proven string stays the default.
- **wasm32 datalayout:** `e-m:e-p:32:32-p10:8:8-p20:8:8-i64:64-n32:64-S128-ni:1:10:20`.
  It is **identical for `wasm32` and `wasm32-unknown-wasi`**, confirmed independently
  with clang-18 (18.1.3) in a sandbox.
- **Sysroot problem for `wasm32-unknown-wasi`** in the user's environment: **deferred.**
  (Note: the C runtime pieces are built for `wasm32-wasip1-threads`; see "wasm32 build
  flags".)
- **Target triple (v12):** `m3llwasm` now uses `wasm32-wasi-threads` (previously
  `wasm32-unknown-threads`).
- **`llvmByval = FALSE` is required for wasm32.**
- **The "invalid wasm32 module" root cause (B1 finding).** The module verified as
  invalid not because of function attributes but because the **front end produced a
  64-bit AST** (`Target.Init`) that was then emitted against the 32-bit wasm32
  datalayout. Fixing this is the `Target.m3` item in the register: add a generic
  wasm32 system (`WASM32_WASI`) that selects 32-bit width **deterministically**
  rather than by a name-substring test; exclude it from the 32-bit alignment
  downgrade for non-C backends (frozen-baseline principle: `m3llhost` unchanged);
  then confirm that `phb.ast` shows `Int.32` and a 4-byte `Addr`.

### wasm32 build flags (reference)

Recorded so they are not rediscovered. Applies to the C and assembler parts of the runtime
(`nthr*`, `nsyn`, `nref`, `RTIOc`, …) built for wasm32.

- **Compile (`.c`):** `--target=wasm32-wasip1-threads -pthread` (clang then enables
  `+atomics`, `+bulk-memory`, `+mutable-globals`, `+sign-ext`), plus `--sysroot` and
  `-resource-dir`; `-D_WASI_EMULATED_SIGNAL` where needed.
- **Assemble (`.s`):** the same command line plus `-matomics`; `-pthread` does nothing for the
  assembler. The m3make driver compiles stand-alone `.s` files with the C compiler using the
  same command line as C files, and the command lines come from per-target scripts, so
  `-matomics` goes **only in the wasm32 script** (never x86_64: it is an error on x86_64 `.c`
  files and unused on x86_64 `.s`).
- **Link:** `-Wl,--shared-memory,--import-memory,--max-memory=<bytes>`. The driver does not add
  these. The maximum must be a multiple of 64 KiB and must match the host's memory. **(v15)** The maximum is also the
  hard bound the collector will see: see register 41 for how to size it.
- **Platform facts:** `long` is 32 bits on wasm32 (use `size_t`/`unsigned long long` with
  overflow checks for size arithmetic). On wasm32 `Virtual`'s `sbrk(numBytes)` needs a multiple
  of 64 KiB or wasi-libc traps with `unreachable`. Stock wasi-sdk 24 `malloc.h` lacks
  `struct mallinfo`, so `nref.c`/`nref.h` do not compile against it unmodified (register 27).

---

## Phase A — wasm32 Runtime Scaffolding (complete, tested; parking revised in v11; join/reap revised in v12; `nthr_lock` and the lock rules in v13)

The parking protocol was revised in v11, the exit/join/reap protocol in v12, and the lock path
and the watch-transition rules were recorded in v13 (see the three addenda at the end of this
section); the four invariants stand. Files: `WThread.i3`/`.m3`,
`nthr.c`/`.h`, `nthr_x86_64.c`/`nthr_wasm32.c`, `nthr_sysv.s`/`nthr_wasi.s`,
`RTSync.i3`/`nsyn.c`/`.h`. Four invariants (watch-state serialization under
`watchSyn`, formerly `parkSyn`; before-and-after safepoint recheck around blocking primitives;
`relief` held for the entire `SuspendOthers`↔`ResumeOthers` bracket; role-based not
module-based safepoint exemption) — unchanged. (Phase D is parked as of v14, but these invariants remain required for
every blocking primitive.)
B1's emitted check is the compiled-code half of these invariants: its watch-state test
(park iff `watch >= vigilant`) is the `relief` bracket as seen from generated code —
`relief` and `deferred` both fall through, so a thread inside a
`SuspendOthers`↔`ResumeOthers` bracket never parks itself.

### Phase A addendum (v11) — stop-the-world and parking revised

Applies to the WTHREAD runtime only. The four invariants above stand. Working rule the
design follows (the user's): **mutexes are for exclusion; condition variables are for
waiting on, and announcing changes in, a condition. The safepoint flag is itself the
condition, so it is protected by its mutex.**

**What was wrong, in order of discovery** (each reproduced with a harness against the real
`nthr`/`nsyn` before it was fixed):

1. **Publish order.** A thread advertised `deferred` before it had published `stack_ptr`
   and `stack_chain`, so a coordinator could read a stale chain. Fixed: publish first,
   then advertise (B1.5).
2. **Missing restore.** A park taken from a poll left `watch` at `deferred`. The poll
   parks only at `watch >= vigilant` and `SuspendOthers` counts only vigilant threads, so
   the thread was silently exempt from every later stop. Fixed: `nthr_park` restores the
   state it was entered with (push at entry, pop at exit); it never restores a fixed value.
3. **Lost wake-up.** `nthr_park` slept on an *event* (a `dangerSyn` broadcast from
   `ResumeOthers`) while the *condition* (`safePoint = 0`) is written under `safeSyn`, and
   `ResumeOthers` never takes `dangerSyn`. A resume between "advertised `deferred`" and
   "asleep" was lost and the thread stranded (reproduced). There was also no loop around
   the wait, so a spurious or interrupted return left park early, and a thread entering park
   from `nthr_wait` was already `deferred`, so the coordinator did not wait for it and its
   stop could end before it parked. `dangerSyn` dated from before safepoint polls existed;
   it was a channel for parkers, redundant once the flag is the condition.
4. **Tail race in `nthr_wait`.** A stop could begin after the final `safePoint` check and
   before `watch` was restored; the coordinator counted the thread safe while it ran again.
5. **Starvation.** Ticket locks are fair, but fair locks do not give *condition*
   fairness: a woken parker draws its ticket after the running coordinator and loses, and a
   level condition (`safePoint = 0`) can flip back before it is observed. In a back-to-back
   storm a thread could sit out thousands of stops in a row.

**Adopted design.**

- **`nthr_park`:** count in (`parked`, atomic) first; take `safeSyn`; publish the chain;
  advertise `deferred` under `watchSyn` and broadcast; Mesa loop `while safePoint: wait on
  safeSyn`; release `safeSyn`; restore the entry state under `watchSyn` and broadcast;
  assert the exit invariant; count out. The last thread out takes `safeSyn` and broadcasts
  it, so the broadcast cannot fall between a coordinator's test and its wait.
- **Exit invariant (user-written assertion; replaces the `goto again` loop).** While a
  thread is counted in `parked`, no new stop can begin, so a thread that was not `deferred`
  on entry must find `safePoint = 0` at exit; otherwise the runtime aborts. The branch never
  fired in about 42,000 park calls across two harness builds.
- **`SuspendOthers`:** waits while `safePoint = 1 OR parked > 0` (the drain: every thread
  that parked for the previous stop gets to run before the next stop begins). No closing
  broadcast. **`ResumeOthers`:** broadcasts `safeSyn` only. The Modula-3 read of `parked` is
  a plain load, which is sufficient: the coordinator tests it under `safeSyn`, `Wait`
  samples `cond_seq` under `safeSyn`, and the decrementer broadcasts under `safeSyn`.
- **`nthr_wait`:** re-checks `safePoint` after restoring `watch`, with a sequentially
  consistent store and load so the thread's `watch` store and `safePoint` load cannot both
  read stale values against the coordinator's `safePoint` store and `watch` load (a
  store-buffer / Dekker pattern). (v11 also described an explicit fence here; v12 records that
  the `seq_cst` pair alone provides the ordering and the fence is redundant — the comment in
  the code that still mentions it is register 27.)
- **Renames and slots:** `parkSyn` is now `watchSyn` (it guards the context `watch`
  variable; rule: change `watch` only inside a `watchSyn` critical section). `dangerSyn` is
  retired; the atomic `parked` counter occupies its former slot in `nthr_nexus_t`, and the
  user updated `CompileSafepoint`'s nexus type to match.
- **New rule (invariant 5):** a thread counted in `parked` has not yet finished leaving
  park; no coordinator may start another stop until the count is zero.

**Evidence.** C harness (`stw.c`, `starve.c`) against the real `nthr`/`nsyn` on x86_64,
2 cores with 6 spinning mutators. *Windows per stop* = park exits divided by stops (1.00 =
every stop was followed by a run window for the thread); the figure in brackets is the most
stops any thread sat out in one park. Run-to-run variance is large; compare variants, not
absolute numbers.

| Scenario | park on `dangerSyn` (publish + restore fixes only) | `safeSyn` alone | `safeSyn` + drain (adopted) |
|---|---|---|---|
| Storm: stops back-to-back | 0.00 (3,820) | 0.24–0.39 (278) | **1.00 (2)** |
| 1 ms collections back-to-back | 0.01–0.02 (1,209) | 0.04–0.06 (1,215) | **1.00 (1)** |
| Three coordinators, short holds | 0.02 (1,261) | 0.14–0.21 (176) | **0.99 (2)** |
| Calm: 2 ms between stops | 0.67–0.77 (8) | 0.79–0.86 (4) | **1.00 (1)** |

The adopted design: 0 mutator-ran-during-stop, 0 stale published chains, 0 stuck and 0
stranded threads across the battery (including a back-to-back second coordinator), and 0
hangs in 120 hunt runs. **The cost:** in a storm, stops fall from tens of thousands per
second to under a hundred on that box, because a new stop waits until every parked thread
has been scheduled and has left park. That is the intended trade. The user's own thread
harness showed a more even distribution than before, with the six generated-code procedures
(nested loops and IFs, run under the new backend in x86_64 mode) keeping it, and the
`LockHeap` nested-lock tests did not regress.

### Phase A addendum 2 (v12) — context layout, exit, join and reap

Applies to the WTHREAD runtime only. Reviewed file by file with the user (`nthr.h`, `nthr.c`,
`nthr_x86_64.c`, `nthr_wasm32.c`, `nthr_sysv.s`, `nthr_wasi.s`, `WThread.i3`, `WThread.m3`);
the user applied every fix.

**Context layout (`nthr_context_t`).** Fields are mirrored in `WThread.i3`; the assembler
files depend on the offsets.

- **x86_64:** `watch` 0, `tid` 4, `outerSyn` 8, `joinSyn` 16, `fn` 24, `fn_arg` 32, `self` 40,
  `stack_size` 48, `stack_addr` 56, **`stack_ptr` 64**, `stack_top` 72, `tls_base` 80,
  `stack_chain` 88, `p` 96, `regs[NREGS]` 104..151 (`NREGS = 6`, 8 bytes each), **`ended` 152**,
  `sizeof` 160.
- **wasm32** (the fields that differ or that the assembler uses): **`stack_top` 40**, `tls_base` 44,
  `stack_chain` 48, `p` 52, `regs[NREGS]` 56..79 (4 bytes each), **`ended` 80**, `sizeof` 84.

The wasm32 build carries `_Static_assert(offsetof(nthr_context_t, ended) == 80, …)`; the first
version of the assembler used 76, which the assert caught.

- **`regs` is `uintptr_t regs[NREGS]`** — the natural pointer width (8 bytes on x86_64, 4 on
  wasm32); the Modula-3 mirror is `ARRAY [0..NREGS-1] OF size_t` with `CONST NREGS = 6`.
  It is zeroed in `nthr_create` and `nthr_default`. The x86_64 assembler fills rbx, rbp, r12–r15
  when it publishes the stack; wasm32 leaves them zero. `ProcessStacks` can therefore scan
  them identically as conservative roots on both targets. **Since v13 `ProcessStacks` passes `regs` to the collector (register 26; Phase C).** The coordinator must call
  `thread_stack32()` on itself before reading its own `regs`.
- **`ended`** is `_Atomic int32_t`, the **last** field, so the assembler offsets (x86_64
  `stack_ptr` 64, `regs` 104..144; wasm32 `stack_top` 40) are unchanged.
- **Layout check.** `thread_match(lockSz, ctxtSz, nexusSz)` in Modula-3 maps to `nthr_match` in C
  and is called first in `WThread.Init`. It checks **sizes only**; field offsets can be
  simulated with `ADR(r.field)` arithmetic, which the user judges good enough for now.

**The join protocol (the Mesa condition rule).** The rule the user adopted for lock/wait
pairs: *whoever makes the condition true must either change it under the lock the waiter
holds, or signal under that lock.* Applied:

1. The joiner holds `joinSyn` (its own `threadSyn`) from **before it reads the target's `watch`**
   until `nsyn_wait` samples `cond_seq`.
2. The exiting thread sets `detached` under `watchSyn`, then does **lock, signal, unlock** on
   `joinSyn` — in both `nthr_func32` and `nthr_start32` — so the signal cannot fall between the
   joiner's test and its wait.
3. `nthr_vigil` **unlocks `joinSyn` around `nthr_arch_reap32`** and relocks afterwards, on all
   paths, and relies on its caller holding `joinSyn` (`Join`, `AlertJoin`, `InitialThread`).
   Without the unlock, the joiner would sit in `pthread_join` (or in the `ended` wait) holding the
   lock the target needs for its final lock/signal/unlock — a deadlock.

   ```c
   if (watch == detached) {
       watch = joined;
       nsyn_unlock(ctxt->joinSyn);
       nthr_arch_reap32(ctxt);
       nsyn_lock(ctxt->joinSyn);
       atomic_store_explicit(&ctxt->watch, joined, memory_order_relaxed);
       nref_free(ctxt->stack_addr, Untraced);
       if (ctxt->tls_base) nref_free(ctxt->tls_base, Untraced);
       ctxt->stack_addr = ctxt->tls_base = NULL;
   }
   ```

**The lost wake-up, for the record.** The first version had the joiner read `watch`, then
`nsyn_wait` read `cond_seq` later, while the target signalled unlocked: a signal landing between
the two was lost and the joiner hung (reproduced). My first fix (the joiner sampling `cond_seq`
first) was rejected as an abstraction break — lock/wait/signal go through `nsyn`, nobody reaches
into `cond_seq` from `vigil`. My second fix (lock around the signal only) deadlocked against
`pthread_join` under the joiner's lock. The final fix is the three-part protocol above.

**Reap (`nthr_arch_reap32`).** Called from one site in `nthr_vigil`, before the stack and TLS are
freed. x86_64: `pthread_join`. wasm32: there is no pthread to join, so it waits on the
context's `ended` flag with `memory.atomic.wait32`
(`__builtin_wasm_memory_atomic_wait32((int32_t *)&ctxt->ended, 0, -1)`), and `wasi_thread_start`
in `nthr_wasi.s`, after `call nthr_start32`, performs `i32.atomic.store` of 1 at offset 80 and
`memory.atomic.notify` (result dropped) on the same address before `end_function`. A dedicated
flag is used, not `p`.

**Safepoint re-checks (decided).**

| | Guard | Store of `watch` | Re-check load | Why |
|---|---|---|---|---|
| `nthr_wait` | `incoming >= vigilant` | `seq_cst` (restore is *not* under `watchSyn`) | `seq_cst` | Dekker pair with the coordinator; the pair provides the ordering, no fence |
| `nthr_vigil` | `incoming >= vigilant` | `release`, under `watchSyn` | `acquire`, after unlock | The `watchSyn` handover with `SuspendOthers` supplies the ordering; no fence, no `seq_cst` |

The park rule is `watch >= vigilant`; `deferred` and `relief` never park. In `nthr_vigil` the
post-wait test is on `incoming`, not `watch` (my review misattributed that test; it was copied
from `nthr_wait` and `incoming` is the correct variable).

**Verification** (trimmed copies of the runtime files; see the revision note). x86_64: 20,000 create/join cycles passed in 6 of 6 runs, quiet and with debug
output. wasm32 under node with real worker threads: 200 cycles once, then 600 cycles twice. The
1,000-cycle wasm run was killed by memory use in node's workers (a harness limit, not a product
bug). WAMR has not run these. Harness issues that were not product bugs: a stale size assert in my
harness (152, should be 160), and the repo's older `nref.c` triggering an `sbrk` abort until I
patched `nref_define`.

**Known remaining edges.**

- `AlertJoin` can leave the target holding a stale `joinSyn` pointer (the joiner's `threadSyn`)
  if the joiner's `T` is freed. A traced `T` fixes it (register 24/28).
- The dangling `nthr_current` after `DISPOSE(self)` is test scaffolding and goes when `T` is traced.

### Phase A addendum 3 (v13) — `nthr_lock`, the watch-transition rules, the heap-lock invariant

Applies to the WTHREAD runtime only. The user wrote all of the code; I reviewed it. The four
invariants, the v11 drain rule and the v12 Mesa rule stand.

**Why `nthr_lock` exists.** A thread blocked in `nsyn_lock` is still `vigilant`, so a stop-the-world
would wait for it forever, and it has published neither a stack nor a chain. `nthr_lock` is the lock
counterpart of `nthr_wait`: the uncontended path is a try-lock and nothing else; the contended path
publishes the stack and chain, goes `deferred`, blocks, and on return restores the state it entered
with and re-checks the safepoint. `no_park` is for the heap lock's recursive mutex (`LockRec` calls
`thread_lock(rm.recmSyn, noPark := TRUE)`): the coordinator holds the heap lock for the whole stop, so
a thread that obtains it must find `safePoint` clear, and a thread that parked while holding it would
deadlock against a coordinator that needs it. In that mode a set `safePoint` is an invariant violation
and the runtime aborts with `NOPARK` and the thread and lock identities; it is a check, not a handler.
The code below is the final reviewed form (the comments are mine).

```c
void nthr_lock(nsyn_lock_t *l, bool no_park) {
    int32_t incoming;
    if (nsyn_trylock(l)) {
        if (no_park && atomic_load_explicit(&nthr_nexus.safePoint, memory_order_seq_cst)) {
            fprintf(stderr, "NOPARK nthr_lock self=%d l=%p\n", nthr_current->tid, l); abort();
        }
        return;
    }
    nthr_arch_stack32();                                  /* publish the stack ... */
    nthr_current->stack_chain = llvm_gc_root_chain;       /* ... and the chain      */
    nsyn_lock(&nthr_nexus.watchSyn);
    incoming = atomic_exchange_explicit(&nthr_current->watch, deferred, memory_order_release);
    nsyn_unlock(&nthr_nexus.watchSyn);
    nsyn_broadcast(&nthr_nexus.watchSyn);                 /* the coordinator may be waiting on this */
    nsyn_lock(l);                                         /* block, as deferred */
    atomic_store_explicit(&nthr_current->watch, incoming, memory_order_seq_cst);
    if (incoming >= vigilant) {
        if (atomic_load_explicit(&nthr_nexus.safePoint, memory_order_seq_cst)) {
            if (no_park) { fprintf(stderr, "NOPARK nthr_lock self=%d l=%p\n", nthr_current->tid, l); abort(); }
            nthr_park();
        }
    }
}
```

**The failure that led to the rules.** The first version took the `deferred` exchange without
`watchSyn` and without a broadcast. `SuspendOthers` waits on `watchSyn` for the vigilant count to
drop; a thread leaving `vigilant` made that condition true without taking the lock the coordinator
waits under and without signalling, so the coordinator slept for good. It hung in the terminal run
and in the file run of `ms4`. A further subtlety: a thread that parks at `nthr_wait` entry still holds
the caller's lock (for example a condition's or a mutex's `Syn`), so threads blocked on that lock are
`deferred` behind it, and only the broadcast tells the coordinator they are safe.

**The rules, stated once.**

| Rule | Statement |
|---|---|
| (a) | `watch` changes only inside a `watchSyn` critical section, followed by a broadcast. Only transitions **out of** `vigilant` need the lock and the broadcast, because those are what the coordinator waits for. |
| (b) | The Mesa rule (v12): whoever makes a condition true must change it under the lock the waiter holds, or signal under that lock. |
| Exception 1 | `nthr_wait` and `nthr_lock` **restore** `watch` without `watchSyn`: a `seq_cst` store, then a `seq_cst` load of `safePoint` (the Dekker pair with the coordinator). |
| Exception 2 | `nthr_wait`'s **entry** exchange is kept outside the lock, because the `safePoint` reload that follows parks (and parking broadcasts). |

**Memory ordering, as it stands.**

| | Entry exchange | Restore store | `safePoint` re-check |
|---|---|---|---|
| `nthr_wait` | `seq_cst` (raised this sprint) | `seq_cst` | `seq_cst`, gated on `incoming >= vigilant` |
| `nthr_lock` | `release`, under `watchSyn`, then unlock and broadcast | `seq_cst`, outside `watchSyn` | `seq_cst`, gated on `incoming >= vigilant` |
| `nthr_vigil` | unchanged from addendum 2 | `release`, under `watchSyn` | `acquire`, after unlock |

A store-then-load handshake with the coordinator's `safePoint` store and `watch` load needs
`seq_cst` on **both** sides. On x86_64 the coordinator's side is covered by the locked
read-modify-write operations that precede the ring walk. A weaker target would also need `seq_cst`
there (register 19).

**The heap-lock invariant.** `SuspendOthers` is called only with the heap lock held: `Collect`,
`StartCollection`, `AllocTraced` and `RTHeapStats` do. The reason is a fresh thread: its allocation
pool starts zeroed, so its first allocation always takes the heap lock. A coordinator that has
stopped the world without the heap lock can therefore watch a new thread reach `LockHeap` under
`no_park` while `safePoint` is set, which is exactly the `NOPARK` abort. The `ms4` driver's
`testColl` called `SuspendOthers` bare; it was a test of `SuspendOthers` from an earlier sprint that
predated the collector, and it was withdrawn. The `After` and `VisitAllRefs` paths are the known
exceptions in the runtime itself (register 34).

**Verification.** `ms4` ran clean in the terminal and twice with piped output, across 14 collections,
with threads spawned and joined throughout. After the hang fix no further hang or `NOPARK` was seen in
the `ms4` or `ms7` runs (13 collections in the last `ms7` run); none was seen in the `ms8` runs either.
**(v15)** ms9 ran up to twelve threads (four of them allocating flat out) through 11 collections per run, in more than twenty runs, with no hang and no
`NOPARK`; the only aborts were the out-of-memory errors of the capped-heap runs (register 41), which are a different failure.

---

## Phase B1 — Safepoint Check Emission (implemented, validated on x86_64)

**Position.** Phase B (wasm32 codegen and garbage collection), step B1 = the safepoint
poll, built over the shadow-stack root scheme. Implemented and validated on the
x86_64 `phb.ll`. Exception handling stays deferred to Phase E; x86_64 stays frozen apart
from LLVM-toolchain modernisation. The next big step for the compiler is producing the wasm32
target, which needs some tweaking first (register items 3, 8) and depends on Phase L
stage 1 for user-space programs.

### B1.1 Function attributes

- `uwtable` carries the **integer value 2**, gated by `NOT self.isWasm`.
- Calling convention is set with `LLVMSetFunctionCallConv`.
- `unsafe-fp-math` and `use-soft-float` dropped.
- x86 target-features gated by `NOT self.isWasm`. **wasm32 attribute cleanup is only
  partially done** (register item).
- The wasm32 invalid-module problem was *not* an attribute problem — see "Target
  descriptions" above.

### B1.2 Why gcroot, and the aggregate-root crash

`llvm.gcroot(ptr alloca, ptr meta)` with LLVM's **shadow-stack** strategy is used
instead of statepoints: statepoints need native stack unwinding, which wasm lacks.
gcroot is also what keeps rooted values alive in memory — a plain alloca would be
eliminated by `mem2reg`, which is why roots must be declared through the intrinsic.
`llvm.gcroot` is **declared without overload types** (no `.p0.p0` suffix).
**(v14)** This is the whole reason gcroot is kept: it is a visibility guarantee (see "Decision (v14)").
Measured effect: with the gcroot calls present, `opt -O2` leaves exactly the rooted slots in memory; with them removed it
promotes every pointer alloca.

**The first argument must be a pointer-typed alloca (v15, register 47).** LLVM 18.1.3's verifier rejects
`llvm.gcroot` whose first argument is not a pointer-typed alloca unless the metadata argument is a non-null constant
(`llvm.gcroot parameter #1 must either be a pointer alloca, or argument #2 must be a non-null constant`). A scalar root must
therefore be a variable whose representation is a pointer. `ClassifyVar` enforces this where the decision is made
(see "`m3t` propagation chain and `ClassifyTrace`" below).

**The LLVM bug.** The shadow-stack lowering inserts a `store [N x i8] null` to
initialise aggregate roots, and instruction selection cannot legalise it — `llc`
segfaults. Reproduced on LLVM 18.1.3 and 20.1.2. Separately, the lowering **drops
alloca alignment** (see B1.6). Both go upstream (register item 6).

**The root-initialisation rule (recorded since v9).** The lowering null-initialises a
root slot **unless it sees a store to that slot in the entry block, before the first
possible safepoint**; such a store is taken as the slot's initialiser and no null-store
is added. Checked on LLVM 18.1.3 with a minimal reproduction (a spilled root and an
unspilled root, followed by a call): the spilled root is left alone, the unspilled one
gets `store ptr null` placed right after the frame is linked, before the first call.
Two consequences, both relied upon:

- **The marker workaround (below) works *because of* this rule:** the one-byte marker
  store makes LLVM treat the aggregate as initialised, so it never emits the
  aggregate null-store that crashes `llc`.
- **A parameter's spill store is the root's initialiser** (see Parameter rooting). The
  slot is valid from the moment it is linked into the chain, with the incoming value.

**The workaround (the "marker" scheme).** A **one-byte zero marker store** is written
into each composite gcroot in the entry basic block, so LLVM treats the aggregate as
already initialised and does not try to initialise it by copying the aggregate. The
actual zeroing of the record is then done by a memset in a *later* block (B1.3).

**Entry-block discipline (hard rule).** The entry block contains **only**:
allocas; `llvm.gcroot` calls; the one-byte marker store for aggregate roots; and
scalar parameter spills. **No memset, memcpy, memmove, other calls, or loads.**
`AllocVar` asserts that the current insert block is the entry block. As emitted, a
rooted parameter appears as `alloca`, then `llvm.gcroot`, then the spill store.

**Pointer-sized roots with no entry-block store get nothing emitted** by the backend
beyond the alloca and the gcroot call: LLVM's own lowering null-initialises them (it is
that same lowering step that breaks on aggregates). Roots that are first assigned in the
body (e.g. a traced local such as `phaseB`'s `t`, `so`, `rc`, `w`) are covered by that
null-store, which lands before the poll.

**Frame layout facts (v14, LLVM 18.1.3, recorded for the dormant composite path; detail in the analysis note).** The lowering
puts metadata-bearing roots **first**, packed contiguously with no alignment padding after a 16-byte header, then the scalar
roots at the next 8-byte boundary. The frame map is `{NumRoots, NumMeta, meta[NumMeta]}` and carries no sizes or offsets.
A walker that strides by pointer size would therefore misread any frame containing an aggregate; this is register 13, parked.

### B1.3 Block structure: `entryBB → prologBB → bodyBB`

- **`entryBB`** — per the discipline above.
- **`prologBB`** — begins with the **memset-zero of every record root**, *then* the
  safepoint poll. Zeroing precedes the poll, so a thread that parks at its first
  safepoint never exposes an uninitialised composite root to the collector.
- **`bodyBB`** — the continuation block *returned by `EmitSafepointCheck`*.

**`LvProc.rootStack`** — a list of root variables, filled as composite roots are
allocated. `end_procedure` consumes it to emit the memsets into `prologBB`.
`end_procedure` also declares the function's GC strategy
(`LLVMSetGC("shadow-stack")`).

**GC-strategy trigger (as implemented).** `LvProc.gcStrategy` is a flag set to `TRUE` by
`AllocVar` whenever the variable classification (`ClassifyVar` since v15) returns anything other than `None`; composite
results are additionally pushed onto `rootStack`. This satisfies the original
requirement — **the strategy trigger must be "any `gcroot` call was issued in the entry
block", not "`rootStack` is non-empty"** — since a function whose roots are all scalar
has an empty `rootStack` but still needs the strategy. In the current `phb.ll`,
`gc "shadow-stack"` appears on exactly the functions that contain a `gcroot` (9 of 11);
`kilo` and `Main_M3` have neither.

**Historical bug, now fixed.** After emitting the poll, the builder was being
repositioned back to `prologBB`, which put the function body *inside* `chkWatch` and
called `nthr_park()` unconditionally. Rule: **never reposition the builder to
`prologBB` after the poll**; the builder continues in the block `EmitSafepointCheck`
returns. Block names `prolog`/`flow` (formerly `second`/`cont`) were validated on
2026-10-07.

### B1.4 Safepoint check emission

**Module-level pieces, compiled into the bitcode** (so the check can reference them):

- `nthr_nexus` — the nexus **struct** (carries the `safepoint` flag).
- `nthr_current` — the thread-context **pointer**, a thread-local global declared `ptr`
  (accessed through `llvm.threadlocal.address`).
- Both are emitted by `CompileSafepoint`, which is **boolean-guarded to do its
  module-level work exactly once**. It also declares the thread-local root chain
  (B1.5), so `begin_procedure` needs no per-function test for that declaration.

**The watch-state enum.** The runtime declares, in this order,

```
typedef enum { deferred, relief, vigilant, detached, joined } recce_t;   (C)
Recce = { deferred, relief, vigilant, detached, joined };                (Modula-3)
```

i.e. ordinals `deferred = 0, relief = 1, vigilant = 2, detached = 3, joined = 4`. The
order was changed so that **parking is a single comparison: park iff
`watch >= vigilant`**. The park set is `{vigilant, detached, joined}`;
`deferred` and `relief` fall through. A running thread is expected to read only
`deferred`, `relief` or `vigilant` from its own context, so `detached` and `joined` in
the set are harmless to the poll.

**The order is load-bearing, and the code generator cannot import the enum.**
`WThread` is runtime, whereas the LLVM generator is code-generation time and does not
invoke the runtime, so `EmitSafepointCheck` declares `CONST Vigilant = 2`. The
declaration in `recce_t` (C) and `Recce` (Modula-3) and this constant must agree. A
comment on the constant naming `recce_t`/`Recce` as its source, and stating that the
order is load-bearing, keeps a later reorder of the runtime enum from desyncing silently.
The user has made a note of this.

**`EmitSafepointCheck`** emits: *if `nexus.safepoint != 0` **and** the thread's watch
state is `>= vigilant`, then call `nthr_park()`*. The shape is two-staged — the global
flag first, so the common path is one load and one branch, then the watch-state test
(`chkWatch`), then the park, then the continuation block (`flow`) that the routine
returns to its caller. As emitted in every polled function of `phb.ll`:

```
prolog:   %safePoint = load atomic i32, ptr @nthr_nexus acquire
          %armed = icmp ne i32 %safePoint, 0
          br i1 %armed, label %chkWatch, label %flow
chkWatch: %tla = call ptr @llvm.threadlocal.address.p0(ptr @nthr_current)
          %cur = load ptr, ptr %tla
          %watch.p = getelementptr inbounds %struct.nthr_context_t, ptr %cur, i32 0, i32 0
          %watch = load atomic i32, ptr %watch.p acquire
          %geVigilant = icmp sge i32 %watch, 2
          br i1 %geVigilant, label %park, label %flow
park:     call void @nthr_park()
          br label %flow
```

The `relief` exemption is Phase A's invariants 3 and 4 as seen from generated code.

### B1.5 Thread safety of the shadow-stack chain — decided 2026-10-08

LLVM's shadow-stack lowering keeps **one global chain head**, which is not
thread-safe. **Decision: make `llvm_gc_root_chain` thread-local**, one chain per
thread.

- The thread module is `nthr.[ch]`: context pointer `nthr_current`, parking via
  `nthr_park`.
- `extern _Thread_local void *llvm_gc_root_chain;` goes in `nthr.h`, with a **single
  definition in `nthr.c`**. The LLVM generator emits the matching thread-local
  declaration in any module that uses gcroots (in `CompileSafepoint`).
- **Assertion added:** whenever a function receives the shadow-stack strategy, the
  global is already declared and is thread-local.
- **The chain head changes on every call, so `nthr_park` copies the thread's head
  into its thread context at park time; the collector reads the published copy.** A
  published head is therefore valid only for a *parked* thread. **(v14)** Nothing reads the
  published chain at present (roots are conservative); it is maintained for the parked parts of the protocol and in case
  precise roots are ever re-opened.
- Validated empirically on **both wasm32 and x86_64** in a separate session.
- A **thread-local intrinsic** was added to the backend's intrinsic set; it is needed
  for atomic accesses to thread-local variables.
- **TLS model.** `GeneralDynamicTLSModel` is set for the nthr variables in the x86_64
  target condition, because the WTHREAD module is also built as a shared library (the
  `LocalExecTLSModel` alternative is commented out; both arms of the `isWasm` test currently set
  the same model). The chain declaration is kept alive against `opt` by a global named
  `llvm.compiler.used` holding `gcchainVar` (built with `LLVMArrayType`/`LLVMConstArray`);
  accepted as an escape hatch. **(v14)** Measured cost of the chain maintenance: about 1.5 ns per call of a function with
  roots on x86_64 with general-dynamic TLS (analysis note); wasm32's TLS access is different and unmeasured.
- **Publication order (v11).** `nthr_park` and `nthr_wait` publish `stack_ptr` and
  `stack_chain` *before* the thread's `watch` becomes `deferred` (a release store), so a
  coordinator that observes `deferred` reads a current chain. `nthr_vigil` does the same
  (closed 2026-10-22, register 21): when it is eligible to wait it calls `nthr_arch_stack32` and
  refreshes `stack_chain` before the exchange; when the target is already detached it only reaps.

### B1.6 Alignment bug (`pop_struct`)

`pop_struct` created temporaries for by-value records with the **whole structure
size as the alignment** (e.g. `align 16` on a 16-byte record) instead of the
alignment operand (pointer alignment). Harmless until the shadow-stack lowering dropped alloca alignment,
at which point a `movaps` on an under-aligned slot **SIGSEGV'd**. Fixed: it now
passes the alignment operand. If the same code exists in `m3llhost` it is latent
there (no shadow-stack lowering on that path) and, per the frozen-baseline
principle, is left alone.

**Observation (low priority — register 15).** The `llvm.memcpy` that `pop_struct`
emits when copying a by-value record into its argument temporary still carries
`align 1` on both operands (e.g. `memcpy ptr align 1 %tmp.145, ptr align 1 %c, i64 16`
in `phaseB`), although the temporary and the source are `align 8`. This is legal, and
harmless under stop-the-world collection (there is no safepoint inside the copy), but
it lets LLVM split the copy into narrower moves. To decide: whether it is intended.
**(v15)** ms9's by-value aggregates (`AggArr`, 72 bytes) exercised this path (`b := a`, the `VALUE` parameter) with correct results.

### B1.7 Debug-info fixes

- `DebugObject` now builds a **real class type** and replaces the placeholder via
  `LLVMMetadataReplaceAllUsesWith`. `DebugRecord` and `DebugProc` already did this.
  The earlier failure was a debug-metadata bug fixed by that **replace-all**.
- `DebugLookupML` now assigns `diType` from each `Debug*` return value **for all
  kinds**, so `r.diType` / `p.diType` are set consistently.
- **Still open:** objects with no supertype leave a **NIL element** in the element
  array, which LLVM 20 rejects (register 5).

### B1.8 LLVM bugs for upstream (reproducers ready)

1. Aggregate gcroot crash in `llc` (shadow-stack's `store [N x i8] null`; LLVM 18.1.3
   and 20.1.2).
2. Shadow-stack lowering drops alloca alignment.

(The root-initialisation rule in B1.2 — no null-store when an entry-block store is
present — is lowering behaviour the project relies on, not a third report.)

### B1.9 Validation record

Reference module `phb.m3`; output checked on `phb.ll`.

- **Through v9:** LLVM 18.1.3 `verify` + `llc` pass, no `movaps`, 10 polled functions.
- **Refreshed snapshot (v10, parameters):** 11 functions, **all 11 polled** (`prolog` /
  `chkWatch` / `park` / `flow`), 9 carrying `gc "shadow-stack"`. The refreshed module was
  built and run on x86_64 by the user (the `takeRef` output is recorded under Parameter
  rooting). A `verify` + `llc` pass on the refreshed `.ll` is not separately recorded here.
- The project's `phb.ast`/`phb.ll`/`phb.m3` copies are reference snapshots.
- **v11:** the emitted poll (function entry and loop back-edges) was exercised through
  generated code: six test procedures with nested loops and IF statements, built with
  `m3llwasm` for x86_64 and applied by threads in the user's WTHREAD thread harness, against
  the revised `nthr`/`WThread`. Fairness held, the `LockHeap` nested-lock tests did not
  regress, all tests passed. No wasm32 run is recorded.
- **v14:** the ms8 build (also `m3llwasm`, x86_64 mode, `llc -O0`) carries 14 and 15 scalar gcroots in its two busiest
  functions and ran 13 collections cleanly; the audit passes on its IR (Decision (v14)).
- **v15:** the ms9 build (twelve subjects, open arrays, views, by-value aggregates, text) verified and linked after the
  `ClassifyVar` fix (register 47) and ran in more than twenty runs; the user's IR for the failing module passed `llc`,
  `llvm-as` and `llvm-dis` once the single offending gcroot was removed, which is what the fix does. **The ms9 IR has not been
  through the audit script** (register 42).

### B1 open items and parked

See the consolidated register. In short: loop-edge polls are done (v11); what remains is wasm32
enablement and cleanup.

**Loop-edge safepoint polls — implemented (closed in v11; recorded 2026-10-08).** The
function-entry poll alone does not bound time-to-safepoint for a call-free loop, so the
user added a poll on every back-edge. Codegen shape: a back-edge jumps to a **label already
placed**, so the poll goes on the **taken side** of the back-edge, and the flow block
returned by `EmitSafepointCheck` is the continuation. Exercised in v11 by six generated
test procedures with nested loops and IFs (B1.9). **(v15)** A reminder from ms9: on the `m3llhost`
build a spin loop `WHILE ms9.stage < s DO INC(spinner) END` has no poll and hung the stop-the-world; the `m3llwasm` build (with
loop-edge polls) completes. The harness spin loops depend on the loop-edge poll.

**Parked — nested procedures on wasm32.** `llc` rejects the `nest` static-link
attribute ("WebAssembly hasn't implemented nest arguments"). The static link is the
**hidden first parameter**, spilled to `__StoredStaticLink` (the first alloca). Nested
procedures remain open and may affect the AST (nested procedures can be deferred and
treated serially, which complicates up-level access). **Deliberately deferred.** The
static link's slot is built by the same `begin_procedure` loop as ordinary parameters and
also receives `memVar.inProc := param.inProc` (kept symmetric with the parameter
slots); it is expected to be reworked when nested procedures are picked up.

---

## Phase B2 — GC Root Registration for Stack-Resident Values

### `m3t` propagation chain, `ClassifyTrace` and `ClassifyVar` — complete

`m3t` is a Modula-3 `TypeUID`: a structural fingerprint, unique and compile-time
only; `NO_UID` = `16_FFFFFFFF` (-1).

Full chain from parser-level type resolution through `ValRec`, `declare_temp`,
`Call_direct`/`Invoke_direct`/`Gen_Call_indirect`/`Invoke_indirect`, and
`declare_procedure`/`import_procedure`'s restored `return_typeid` — verified working
end to end. `ClassifyTrace` returns `None`/`Scalar`/`Composite`, dispatching
`PointerDebug` → `ObjectDebug` → `RecordDebug` (recursive field walk) → else `None`,
with `ObjectDebug` checked *before* `RecordDebug` since it is a subtype. `NO_UID`
short-circuits to `None`. A `debugTable` miss asserts. Object-typed
storage is always pointer-represented (the layout is only resolvable at runtime via
the header typecode), which is why objects classify as `Scalar`, never by walking
`.fields`. Verified correct, including the two-independent-failures lesson (a dispatch
bug and a data-population bug can each hide the other) for any future `Debug`-
hierarchy extension. `QualifyExpr.m3`'s `Class.objField` case reuses
`Type.LoadScalar` identically to `Class.recField` — no extra code needed.

**`ClassifyVar` (v15, register 47, closed).** `ClassifyTrace(self, m3t)` is a pure function of the type UID. A variable is
more than its type UID: the front end sometimes declares a temporary whose UID names one type and whose representation is
another. The case found by ms9 is the dope temporary of an open-array `NEW`: `cmd/m3fe/src/builtinOps/New.m3`, `GenOpenArray`,
declares the 24-byte struct temporary with `m3t := Type.GlobalUID(t)`, the UID of the `REF` type. `ClassifyTrace` therefore answered
`Scalar`, `AllocVar` issued `llvm.gcroot` on a struct alloca, and the LLVM 18.1.3 verifier rejected the module
(`%tmp.412`). The fix is a per-variable wrapper in `cmd/m3be/llvm18wasm/src/LLVM_WASM.m3`, called from `AllocVar` in place of the
direct `ClassifyTrace` call:

```modula3
PROCEDURE ClassifyVar(self: U; v: LvVar): TraceKind =
VAR tk := ClassifyTrace(self, v.m3t);   (* type-only, unchanged *)
BEGIN
  (* A Scalar root is one traced pointer in a pointer-typed slot. *)
  IF tk = TraceKind.Scalar AND v.type # Type.Addr THEN
    RETURN TraceKind.None;
  END;
  RETURN tk;
END ClassifyVar;
```

Why this form and not the alternatives considered: (1) overriding the result after the call in `AllocVar` is the same decision
in the wrong place; (2) changing `ClassifyTrace` would make a pure type function depend on a variable; (3) changing the front end's
`m3t` for that temporary would change the AST both targets read, which the frozen baseline forbids for no gain. The consequence
is that the dope temporary is not a root: it holds a raw data pointer and its holder is the rooted `REF` (the derived-copy rule;
open-array dope temporaries were already on the audit list, see Deferred scope). Evidence: removing that single gcroot let the whole
module pass `llc`, `llvm-as` and `llvm-dis`; the user's ms9 runs worked. A latent front-end inconsistency remains (register 50); it needs no action.

**`Gen_Call_indirect`/`Invoke_indirect` — resolved.** No stack-capture is needed:
`t_m3t` is sourced from `ProcType.Result(p_type)` via `Type.GlobalUID`.

**Remaining `NO_UID`s in `Load_indirect`:** the two exceptional paths (the
"unaligned word-straddling" and "unaligned partial-word" error branches, each
following an `Err`). Left as `NO_UID` deliberately.

**Where `m3t` rides in the AST.** The structure was kept unchanged except where
unavoidable; `return_typeid` on `declare_procedure`/`import_procedure` was restored
across *all* `M3IR_Asm` implementers (see the defaulted-parameter hazard in
Baseline). `call_invoke_direct` in the backend pushes the bare SSA result onto
`exprStack`; whether it becomes a gcroot is decided later, at `declare_temp`.

### Parameter rooting — implemented (closed in v10)

**What was wrong.** `begin_procedure` built the slot for the static link and for every
non-struct parameter with a throwaway `NewVar` call that hard-coded `m3t := UID_ADDR`
and pointer-sized `size`/`align`. Parameters therefore never reached `AllocVar` with
their real type: `REF T` parameters were unrooted (`takeRef`'s `%p1` had no gcroot), and
sub-word parameters got 8-byte slots.

**The fix, as implemented.** In the parameter loop, `NewVar` now receives the
parameter's own values: `size := param.size`, `align := param.align`,
`m3t := param.m3t` (already stored in the `LvVar` by `declare_param`). `type` stays
`Type.Addr` and the variable stays a `VarType.Local`. Then `memVar.inProc := param.inProc`.
**The `inProc` copy is required:** `curLocalOwner := p` is only set after the parameter
loop, so `NewVar` would otherwise see a stale or NIL owner, and `AllocVar` — which
sets `LvProc.gcStrategy` (B1.3) — needs the owning procedure. The static-link `memVar`
receives the same `inProc` for symmetry (its `m3t` is `UID_ADDR`, which classifies as
`None`, so it is not rooted).

**Struct (by-value aggregate) parameters get no slot.** `param.lv := lVal`: the callee
works directly on the caller's `pop_struct` temporary, which carries its `m3t` and
alignment and is itself a composite root (with metadata) in the caller. `valRec` and
`modRec` in `phb.ll` show this: no alloca, no spill. **(v15)** ms9's `aggValProc(ms9, cp: AggArr)`
takes a 72-byte by-value record array; the front end warns "Large parameter passed by value (72 bytes)" and the
copy-in, the callee's copy as sole holder, and the survival of both levels of referents across six collections all behave correctly.

**By-reference formals** (`VAR`/`READONLY` passed by address). Their `m3t` is the
`declare_indirect` UID, `−(referent + 1)`, and the slot holds an address. They classify
as `None` and are not roots. **The sign of a UID cannot be used to recognise them:**
legitimate UIDs can be negative (e.g. `TestB`'s `−814819607`), and the indirect UID of
a negative target is positive. They are handled correctly today because `declare_indirect`
registers a non-tracing entry in `debugTable` (inferred from the fact that
`ClassifyTrace`'s miss-assert never fires for them; confirm if `declare_indirect` is
touched). **(v15)** The miss-assert did not fire in ms9 either, which uses `VAR`, `READONLY`, `VALUE` open-array and `SUBARRAY` formals.

**Root-ownership rules.**

| Storage | Rooted? | Why |
|---|---|---|
| Value parameter slot of a traced type (`REF T`, object, `TEXT`, traced opaque) | **Yes** — scalar root, null meta; the spill initialises it | The slot is the callee's own mutable variable and may hold the only reference to something (it can be reassigned). |
| Value parameter slot of a non-traced type (`INTEGER`, subrange, enum, proctype) | No | Classifies `None`. |
| By-reference parameter slot (`VAR`/`READONLY`) | No | Holds an address, not an object. The referent's owner roots it. |
| By-value record parameter | No slot in the callee | The caller's `pop_struct` temporary is the composite root. |
| Front-end temporary printed `Addr -1` | No | See the derived-copy rule below. |
| Open-array `NEW` dope temporary (a struct declared with the `REF` UID) | No (v15) | `ClassifyVar`: not pointer-represented; the holder of the `REF` spans the call. |
| Open-array VALUE parameter | Exercised in v15; see Deferred scope | The formal is re-pointed at a heap copy; at `-O0` the slot is an alloca in the scanned range. |

**The derived-copy rule (audit rule for unrooted `Addr -1` temporaries).** An unrooted
temporary is safe only if a *rooted* holder of the same object spans every safepoint
over which the temporary is live. The check is made per temporary: find the rooted
holder (a local, a parameter slot, a global, or a field of a rooted object). The rule
also depends on stack-referenced objects being pinned, i.e. on Phase C's pinning
(register 25a). **(v14)** With roots conservative and the optimiser excluded, every front-end temporary is an alloca in
the scanned range, so the rule is satisfied by construction and the audit gate checks it mechanically (it counts any pointer
value that crosses a safepoint in an SSA value without a memory home). It becomes a hard requirement only in Phase O. Audited
so far, at the earlier snapshot: `v.97`,
`v.100`, `v.101` (audited when first found) and `v.118`. `v.118` is the `Stdio.stdout` copy
in `phaseB` (`tmp.134`): it is loaded from the `Stdio` interface's slot, a
`CheckLoadTracedRef` call (a safepoint) follows, and then it is stored to the rooted local `w`.
The `Stdio.stdout` global holds the same object across that call, and `w` holds it afterwards.
The rule relies on module globals being scanned as roots (Phase C).

**Front-end temporary pool.** The front end reuses temporaries (e.g. `tmp.107` in
`GCRoots`, `tmp.123` in `takeRef` across three allocations), which can *mask* an unrooted
slot: a later use of the same temporary overwrites and re-roots. `takeRef` is the test
that defeats the masking for parameters: `p`'s cell is exposed at the third allocation
(`EVAL NEW`), and `p1` is rooted in the generated code.

**Validation (IR inspection of the refreshed `phb.ll`, x86_64).**

- `takeRef(p: REF INTEGER; VAR varref: REF INTEGER; VAR varint: INTEGER)`: `%p1` is
  `alloca`, `gcroot null`, spill. `%varref2` and `%varint3` are plain allocas with a spill
  and no root.
- `otherRoots(s: [0..9]; e: Color; t: TEXT; o: SomeObj; rc: REF composite;
  f: PROCEDURE(): INTEGER; w: Wr.T)` called as `EVAL otherRoots(4, cl, t, so, rc, pp, w)`:
  roots exactly `t3`, `o4`, `rc5`, `w7`. `s1` and `e2` are `i8`/`align 1` allocas (size
  and alignment now come from the parameter). `f6` (the proctype) is not rooted. No
  `ClassifyTrace` assert fired for the subrange, enum, proctype, object, `TEXT`,
  `REF record` or opaque types.
- `w7` is rooted only because `declare_opaque` hard-wires `traced := TRUE` (see Opaque
  types below).
- Runtime: `takeRef(vr, vr, vi)` prints `post takeRef vr/vi(0,55) n=5`, the correct
  `VAR` semantics. (`vi` is an uninitialised `INTEGER` local, which is undefined in
  Modula-3; the varying values printed before the call are stale stack contents, not a
  defect, and not a root.)
- **Runtime evidence (v14, v15):** the ms8 and ms9 runs execute generated code with rooted parameters under the
  collector without failure. Because roots are conservative this does not by itself prove the rooting is complete; the audit
  gate is the check that matters.

### Objects — closed in v10

Objects live only in the heap. Each traced heap allocation carries a header word
immediately before the object pointer; the compiler's own barriers read it at `ptr − 8`
and test flag bits in it (the `shl 41`/`shl 42` then `lshr 63` sequences in
`phb.ll`). The collector reaches an object's reference fields through the header's
typecode and the runtime type map, not through anything the compiler emits. So an
object-typed local, temporary or parameter is a **plain scalar root** (one pointer, null
meta), as `o4` and `so` are. A static answer would not even be possible: a slot
declared `o: SomeObj` may hold any subtype, and the subtype may have more reference
fields than `SomeObj` declares. A bare, standalone object-typed local (`so` in `phaseB`)
is seen rooted in the generated IR.

### Composite `gcroot` metadata — complete (dormant since v14)

**Status (v14).** Built, byte-verified and retained, but **not consumed by anything**: the collector reaches heap records
through the front end's typecell maps, and stack aggregates are seen by the conservative scan with no map. ms8 contains no
composite gcroot at all (no `meta.N` globals). Kept as is; not extended. See "Decision (v14)". **(v15)** Nor did ms9 need it: the
by-value `AggArr` (a local, a parameter and a global) was served by the scan and the heap type maps alone.

**The module: `TypeComp`.** A byte-for-byte-faithful copy of `TipeMap`'s core
encoder (`Op` enum, `ArgBytes`/`CursorUpdate`, `Add`'s skip-insertion and
argument-width logic) — confirmed identical, field by field, against the original.
Legitimate, deliberate differences only: object-based `T` (permits multiple
independent in-flight compilations, unlike `TipeMap`'s single-instance module
globals) and `Finish` returning bytes directly rather than writing to `v.1`.

**The metadata object.** An `internal constant [N x i8]` global named `meta.<N>`, in
`RTTypeMap`'s bytecode format, compiled from `RecordDebug.fields`. The `gcroot`
metadata argument is **the global's `ValueRef` (an address)**, not a `ConstString`
value. State on the backend object `U`: `next_meta := 1`, `metaTable : IntRefTbl.T`
(`<TypeUID, LvMeta>`, where `LvMeta` wraps the global's `ValueRef`), `metaComp :
TypeComp.T`.

**The pipeline, in `AllocVar`:**
- `LLVMBuildAlloca`, then `ClassifyVar(self, v)` (v15; formerly `ClassifyTrace(v.m3t)`) → `None`/`Scalar`/`Composite`.
  `None` → an ordinary alloca, nothing more.
- `FindMeta(tk, m3t)` — `Scalar` → `LLVMConstNull` (null metadata). `Composite` →
  checked against `self.metaTable`; on miss, `GenMeta` builds it once and caches it.
- `CompileMeta(base, rec)` — walks `RecordDebug.fields` recursively. For each field:
  `PointerDebug`/`ObjectDebug` with `.traced` → `TypeComp.Op.Ref` at
  `base + bitOffset`; nested `RecordDebug` → recurse with `base + bitOffset` as the
  new base (a single `Start`/`Finish` bracket spans the *entire* top-level
  compilation — nested calls never re-enter it); anything else (untraced scalar) →
  emit nothing, relying on `Add`'s own auto-skip to bridge the gap. Nested by-value
  records are **flattened inline** this way because `RTTypeMap.Walk` has no
  jump-to-other-type opcode.
- `GenMeta` — `LLVMConstString` (`DontNullTerminate := TRUE`), then
  `LLVMArrayType(i8, N)` + `LLVMAddGlobal`/`LLVMSetInitializer`/
  `LLVMSetGlobalConstant`, **with `LLVMSetLinkage(..., LLVMInternalLinkage)`** (without
  it, `meta.N` names, numbered from 1 per compilation, collide across separately-
  linked modules). Named by a monotonic counter; the name need not encode the
  `TypeUID` because the cache already provides that link.
- Finally `IntrinsicFunc(M3Intrinsic.m3gcroot, 2, AdrAdrTy, AdrTy)` is called with
  `[v.lv, metaVal]` via `LLVMBuildCall2`.

**Confirmed by construction: `PushPtr`/`Return` are irrelevant to this work.** The
only real-`TipeMap.Add` callers in the front end are in `values/Variable.m3`, gated by
`t.indirect`, describing *how a particular global variable happens to be stored* —
never a type's own field layout. No record/object/array mapper touches either opcode;
correctly excluded from `TypeComp` entirely.

**The `refs_only` finding — this is what makes the op vocabulary small.** `GenMap`'s
gate (`IF refs_only AND NOT isTraced THEN RETURN`) means an untraced field is never
even visited. Confirmed via `RefType.m3`'s `InitTypecell`: `RT0.TypeDefn` carries
**two** map fields from the *same* generator — `type_map := GenTypeMap(p, refs_only
:= FALSE)` (every scalar field) and `gc_map := GenTypeMap(p, refs_only := TRUE)`
(traced fields only). `TypeComp`'s output is refs-only by construction, so
**`gc_map`, not `type_map`, is the correct comparison target.** Practical effect: the
only opcodes `TypeComp` ever emits are `Op.Ref` (both `PointerDebug.traced` and
`ObjectDebug.traced`) and `Op.Stop`, plus `Add`'s auto-inserted skips.

**Empirical validation, byte-exact across four cases.** Methodology: `TYPECODE(REF
T)` → `RTType.Get` → `RT0.TypeDefn.gc_map`, compared directly against `TypeComp`'s
output for the equivalent type:
- `composite` (`f1: INTEGER; f2: REF INTEGER`) → `Skip_8, Ref, Stop`.
- `TestA` (traced field preceded by mixed untraced fields) → `SkipF_1(16), Ref, Stop` —
  `Add` prefers a single variable-argument skip over chained fixed skips when the
  target isn't reachable in ≤8 bytes.
- `TestB` (nested-by-value record containing the traced field) → identical to
  `TestA` — confirms the recursive base-offset threading.
- `TestC` (two non-adjacent traced fields, one a user-declared `OBJECT`) →
  `Skip_8, Ref, Skip_8, Ref, Stop` — first exercise of the `ObjectDebug` branch
  against genuinely user-declared data; confirms cursor bookkeeping accounts for an
  already-emitted `Ref`'s width.

**Where each map is used (clarified v14).** Heap records and objects reach the collector through the front end's typecell
maps (`RefType.InitTypecell`; objects likewise); that is the path ms8 exercises and it is the existing, proven one. `TypeComp`
metadata describes **stack-resident aggregates** only (by-value record locals, parameters and temporaries in a gcroot frame),
a case no existing x86_64 mechanism covers, and which the conservative scan covers without a map.

### Builtin type table (`InitUids`) and opaque types

- **`traced` bugs — fixed.** `traced := TRUE` for ROOT/TEXT/REFANY/MUTEX; explicit
  `FALSE` for UNTRACED_ROOT and ADDR. Together with the `ObjectDebug`-before-
  `RecordDebug` dispatch fix, these are the two independent failures noted above.
- **`superType` correction sprint — deferred, own sprint.** `InitUids`'s `superType`
  fields (cross-checked against the Language Report). DWARF-correctness only; no
  effect on gcroot or the collector.
- **Future note — `BuiltinTypes.KindUID`.** The backend should use the front end's
  **computed** builtin TypeUIDs rather than hard-coded `UID_*` constants. Not
  scheduled; removes a drift risk and was the structural cause of the `UID_ADDR`
  parameter issue (now fixed at the use site).
- **Opaque types — `traced` derivation parked (register 12; reminder carried).**
  `declare_opaque` registers an `ObjectDebug` with `traced := TRUE` hard-wired, and
  creates a placeholder super if the super is missing. The deferred fix is to derive
  `traced` from the super's `debugTable` entry through a small helper (`TracedOf`:
  `PointerDebug`/`ObjectDebug` → that entry's `.traced`, else `TRUE`). Limitation: a
  *forward-declared* super would still inherit the `TRUE` placeholder. **Decision
  (user):** opaque types will mostly arrive through imported interfaces with partial
  reveals, so the full reveal is often not visible from the call site; the affected case
  is considered low probability and the fix stays pending. To be reminded at the next
  checkpoint or at the next parameter-kinds milestone.

### Design hazards recorded

- **Never hash on a traced reference's address.** A moving collector can relocate it.
  `Proc` is a traced object, so any table keyed by procedure needs a stable key. (An
  earlier name-keyed-table idea was dropped after the NARROW/`Proc` layering
  correction: the backend must not depend on front-end `Proc`.)
- **Declaration ordering:** `ClassifyTrace` asserts on a `debugTable` miss, forcing an
  ordering violation to surface at compile time rather than miscompile silently. The
  assert detects a *missing* entry, not an entry of the *wrong kind*; the one known
  wrong-kind case is the hard-wired opaque `traced` above.
- **A temporary's `m3t` is not a guarantee about its representation (v15).** The open-array `NEW` dope temporary is the case
  found; `ClassifyVar` guards the root decision. Any future classification that acts on a variable (rather than on a type)
  should go through `ClassifyVar`.
- **Unrooted copies need a rooted holder** (the derived-copy rule above). It is an
  audit made per `Addr -1` temporary, and the front end's temporary reuse can hide a
  violation. **(v14)** The audit gate (register 42) now performs this check mechanically on the IR.

### Still open, narrowly

1. Declaration-ordering assumption (`<*ASSERT FALSE*>` on a `debugTable` miss) — still
   never triggered across an increasingly large and varied test set (ms9 added open arrays of several depths, views, by-value
   aggregates and text); formally unverified.
2. Why `RTTypeMap.WalkRef` consumes `.type_map` rather than `.gc_map` at actual
   collection time, given `.gc_map` is the narrower, purpose-matched field. Doesn't
   block anything (the comparison methodology is valid regardless), but is unexplained.
   **(v14)** No longer needed before any scheduled work (it was a Phase D prerequisite, now parked).

### Deferred scope

**`BITS N FOR T` (packed fields).** Out of scope, and the reasoning bounds the risk
precisely rather than just deferring it: `BITS N FOR T` requires `T` to be ordinal, so
a packed field can never itself be a `REF`. It matters only for a *traced* record that
also contains an unrelated packed field elsewhere — the gap is entirely about
`TypeComp` correctly *stepping over* a packed field's bits when computing subsequent
offsets, never about a packed field being reported as a root. Fix when a real test
case surfaces it; not a correctness risk to anything currently in scope.

**Arrays (updated v15: exercised by ms9).** `ArrayDebug`/`OpenArrayDebug` both carry `elt: TypeUID`, so classification
is structurally easy; *acting* on it differs sharply between fixed arrays
(compile-time-known count; could plausibly reuse `TypeComp`'s `Array_N`-family opcodes
once built) and open arrays (structurally incompatible with `gcroot`'s
one-root-per-alloca model; needs a different mechanism entirely). Open arrays can
nest (`.elt` can itself be an `OpenArrayDebug`), so any future recursive handling must
handle arbitrary depth, and multi-dimensional arrays add more sizes to the dope vector.
Fixed arrays of traced references are **not rooted today** (arrays classify as `None` by decision), as in ms8's
`a[]` owner arrays. Under the current scheme they are visible anyway, because at `-O0` they are allocas in the scanned
range; they would need rooting (address roots with null metadata, see "Decision (v14)") only if an optimiser is ever added.
**Runtime facts established by ms9 (x86_64, `-O0`):** a heap `REF ARRAY OF T` is one object, the dope (an elements pointer at
offset 0, then one size word per open dimension: 8 + 8·d bytes) followed by the data; when the collector moves it, `Move` rewrites
the elements pointer as `np + def.dataSize`. A fixed `REF ARRAY [1..N] OF T` has no dope and points straight at element 1. Open-array
formals are indexed from 0 whatever the actual's bounds were. Verified for depth 1, 2 and 3, bytes and `REF` elements, an open outer
dimension over a fixed inner one, and a three-dimensional by-value copy.

*The open-array VALUE parameter copy (register 11).* In `phb.m3`'s `number`, the
callee copies a VALUE open-array argument: the parameter slot (`oa1`) starts as the
address of the caller's dope vector, `RTHooks.AllocateOpenArray` makes a heap copy, and
the slot is then **re-pointed at the heap copy**. After that the slot is the logical sole
holder, yet the copy is rooted only through `tmp.66`, which the front end's temporary
pool may reuse. It was safe because nothing allocates between the re-point and
`ret`. **(v15, ms9)** The runtime behaviour is now validated for a body that waits through six collections: the front end warns
"Open array passed by value" and `Variable.CopyOpenArray` does `NewTracedArray` plus `Copy_n` over the product of the open sizes and
re-points the formal in `LangInit`; the copy is complete at entry, the callee's writes never reach the source (the source is read back
as 103 and 109 after the callee wrote 100), the source reference may be dropped, and the copy survives at every collection, for a
1-D `SUBARRAY` and for a 6 by 9 by 3 array. What remains is the *wasm32* question: the slot must be in memory the scan covers
for the whole body, which the audit gate and the wasm32 smoke test check (registers 42, 44).
Related: open-array **dope-vector
temporaries** (`Struct -1`, e.g. `tmp.135` in `phaseB`, which holds `{ptr @M_Main+104,
i64 3}`) are unrooted and hold a raw data pointer; for a heap-backed array the holder of
the `REF` must span the call. **(v15)** The open-array `NEW` dope temporary is the same kind of object and is now explicitly not a root (`ClassifyVar`).

---

## Phase C — Stack Root Feeding: conservative pinning (validated), embedded `REF` fields (validated in v14), arrays, views, copies, aggregates and text (validated in v15), chain walk (parked)

`RTThread.ProcessStacks` presents each thread's stack and `regs` to the existing, unmodified
`NoteStackLocations`. This is the whole root mechanism on both targets (Decision (v14)). The `stack_ptr`/`stack_top`
argument-order pitfall is still the thing to get right wherever the loop is touched.

**What B1 adds to this phase's assumptions:** every root slot is either valid or null
by the time any thread can park. Scalar roots with no entry-block store are
null-initialised by LLVM's own lowering; a rooted parameter slot is initialised by its
own spill, which is the incoming value (B1.2); composite roots are zeroed by the prolog
memset, which precedes the poll (B1.3).

**Assumptions the derived-copy rule (Phase B2) places on this phase:** stack-referenced
objects are pinned (via `NoteStackLocations`), and module globals are scanned as roots (precise, through `RTHeapMap.WalkGlobals`).

**Chain-walk pinning (v12 register 25b) — parked in v14.** The v12 position was that `ProcessStacks` should walk each
thread's `llvm_gc_root_chain` and pin the pages the slots point to, with the whole-stack scan kept as a comparator. The
v14 decision makes the whole-stack scan the mechanism, not the comparator, so 25b is not required. If it is ever revived, the
open design questions are recorded in Phase D (parked) and in the analysis note (frame layout facts). The `ProcessStacks` source
still carries the marker `TODO: process this ring's llvm.gcroots on wasm32`; it should be replaced by a comment pointing at the
decision.

### Conservative `ProcessStacks` pinning — implemented and validated (v13)

**Scope: "stage 1".** No type maps and no `REF` fields. This stage proves only what `ProcessStacks`
hands the collector: which pages stay, which move, and why.

**Implementation** (`WThread.m3`, user's code). Threads in the fork ring are visited in ring order,
starting with the coordinator; the coordinator calls `thread_stack32()` on itself first, so its own
`regs` are current. A thread whose `watch` is `detached` or later (finished but not yet joined, or
joined) is skipped.

```modula3
PROCEDURE ProcessStacks (p: PROCEDURE (start, limit: ADDRESS)) =
  VAR me, curr : UNTRACED REF Axis;
  BEGIN
    thread_stack32();
    me := thread_context().axis;
    curr := me;
    REPEAT
      WITH ring = triple[curr.slot] DO
        RTHeapRep.FlushThreadState(curr.heapState);
        IF ring.context.watch < Recce.detached THEN
          <* ASSERT ring.context.stack_ptr # NIL *>
          p(ring.context.stack_ptr, ring.context.stack_top);
          p(ADR(ring.context.regs[0]),
            ADR(ring.context.regs[0]) + BYTESIZE(size_t)*NREGS);
        END;
        (* TODO: process this ring's llvm.gcroots on wasm32 *)
      END;
      curr := curr.next_axis;
    UNTIL curr = me;
  END ProcessStacks;
```

`WThread.GC` is a counter added by the user, incremented here; one `Collect` is exactly one
increment. Allocation-triggered collections also run `ProcessStacks`, so the counter also counts
those (the first explicit `Collect` in the ms7, ms8 and ms9 runs was number 8).

**How the unmodified collector uses it** (read from `RTCollector.m3`, which the user confirms is
unmodified):

- `Collect` is `FinishGC; StartGC; FinishGC`. `StartGC` sets `partialCollectionNext := FALSE` when
  the collector is idle, so **every explicit `Collect` is a major (full) collection** — *under the default (unbounded)
  arenas*. **(v14)** The bounded-heap runs contradict this for a 6 MB cap (register 41), so this reading is incomplete. **(v15)** ms9's
  capped runs fail by out-of-memory rather than by partial collection, and the allocation-triggered collections between explicit ones
  can be incremental and partial; see "Bounded heap" below.
- At the start of a collection every page in the current space becomes `Previous` (the flip). Then
  `ProcessStacks(NoteStackLocations)` runs. `NoteStackLocations` reads every word of each range it
  is given; **any word whose value falls on a `Previous` heap page promotes that whole page in
  place** (note `AmbiguousRoot`). Pinning is therefore **page-granular**: the heap page is 65,536
  bytes (`RTHeapRep.BytesPerPage`), and every object on a pinned page stays, referenced or not.
- A promoted *impure* page is grayed whole (`GrayBetween`), so everything on it is treated as live
  and its referents are traced too (through the objects' typecell maps; this is what makes the referent of a pinned
  owner move and the owner's field follow, see stage 2).
- Objects whose page has `nb > 1` are large objects and are promoted in place, never copied.
- Survivors that are not pinned are copied. `def.kind = TK.Obj` goes to the impure copy pages even
  when `gc_map = NIL`; a non-object record or `REF` with `gc_map = NIL` goes to the pure copy pages.
  All OBJECT-kind survivors share impure copy pages, in root-traversal order (module globals first,
  array elements in index order). Free pages are recycled across collections.
- **Conservative roots are never rewritten.** A stack word holding an object address prints the same
  value whether the object was pinned or moved. Printing a stack copy therefore cannot detect a
  pinning failure; see rule 1 below.
- Module globals are precise roots: `RTHeapMap.WalkGlobals` walks each module's `gc_map` through
  `RTMapOp`. This is how the harness's `ARRAY OF obj` globals are found, and how ms9's global arrays and the global `AggArr` are found.

**The harness (`ms4`, then `ms7`).** `ms4` is the thread driver (`testGov`, `testAttn`, `testBasil`,
`testSybil`, `testHeap`) that first ran `ProcessStacks` and found the two bugs recorded in addendum 3.
`ms7` is the pinning harness. It forks seven subject threads and a logger (`Loque`, a log queue
drained by its own thread), then runs three cycles of two stages each (`pause`, `edge`), six explicit collections in all. Each
stage is a driver-side `Thread.Pause`, a stage change for every subject, a second pause, an explicit
`RTCollector.Collect()`, and a log of every tracked object's address. Subjects:

| Subject | What it keeps on its stack | Role |
|---|---|---|
| `nullTest` | nothing; a spin loop with a counter | spinners; are parked by the inline poll at each stop |
| `intTest`, `recTest`, `objTest` | `REF INTEGER`, `REF` record (no `REF` fields), object (no `REF` fields) locals | stack-held controls: should stay pinned and constant |
| `movTest` | allocates `mov[1..3]` (global `ARRAY OF obj`), then exits | movement: unreferenced objects should move at every `Collect` |
| `ctlTest` | allocates `ctrl[1..4]` (global array) and a scalar global `tail`, then exits | movement controls of a second kind |
| `pageTest` | allocates `Page` objects; in cycle 2 copies `mov[2]` into a stack local | selective pin: only `mov[2]` should stay, and only during cycle 2 |

Tracked objects are recorded as `Word.Not(address)` through the logger; decoding is `~b` masked to
64 bits. The thread ids map to subjects by `Fork` order (the address printed in `Fork` is not the
address the subjects print): main 24576, logger 24577, then null, int, rec, obj, mov, ctl, page. Tid 1
is a context whose stack lies on the process's native stack; it maps to no subject.

**Rules for a valid pinning harness** (each was learned from a flaw in an earlier run):

1. Detect pinning with a **precise global reference to the same object**, observed through a
   disguised address. A stack copy cannot fail, because conservative roots are not rewritten.
2. Give **each tracked object its own page**: `obj` carries `large : ARRAY [1..40000] OF [0..255]`,
   about 40 KB, so only one fits on a 64 KiB page. Page-granular pinning of one object then cannot
   hide or fake another's. (An early version assumed a 4 KiB page; the heap page is 64 KiB.)
3. **Do not let the logger hold the answer.** The logger thread's locals pin the page of the last
   object it printed; `Loque.Apply` nulls its temporaries after printing, and addresses are disguised.
   (v14: the logger's stale stack slot still pinned one referent during the startup collections of ms8, GC 6.)
4. **Scrub stale stack residue** between cycles (`scrubMov`/`scrubStack`): dead frames, uninitialised slots of
   later frames overlaying old ones, and callee-saved registers all hold old pointers. **(v14)** Scrubbing reaches only memory
   *below* the caller's frame; stale values in the caller's own frame (the `-O0` spill slots) need the loops that produce
   them moved into callee procedures (rule 8).
5. **Baseline after the allocators exit.** Take the pre-collection positions only once `movTest` and
   `ctlTest` have finished allocating, and match log lines to collections by `WThread.GC`.
6. **(v14) One variable per experiment.** The fixed-heap run changed two things at once and cost a detour.
7. **(v14) Capture both stdout and stderr.** A log of the heap statistics alone means the capture, not the program, failed.
8. **(v14) Keep loops that handle the tracked references in helper procedures** passed the owners by `VAR`, with a `scrubStack`
   after each call, so that their spill slots die with the callee frame.
9. **(v15) Keep small allocations off the array under test.** A small object sharing a 64 KiB page with an array pins it. After
   allocating the array, allocate small throwaway objects of both kinds (pure and impure) until the allocator leaves that page
   (`burnPage`); a spacer that is itself a large object does not help, because large objects take their own pages and leave the
   small-object page where it was.
10. **(v15) Do not pass the array under test through a long-lived formal.** `triMulti^` as the actual of a `READONLY` open-array
    formal put a dope temporary holding an interior pointer in the caller's frame for the whole test and pinned the array. Pass a
    separate small array (here a stack `ARRAY [0..7],[0..7],[0..7] OF Byte`) to test the formal, and keep the array that must move
    in a module global touched only through short helpers followed by `scrubStack`.
11. **(v15) To see a referent move when its container is pinned, log the referent.** A pinned `impMulti` never changes address;
    logging `impMulti[0][0]` (`impElem`) shows the filler leaf behind it moving.
12. **(v15) Check identity across rows as well as content.** A freed page keeps its old bytes until it is reused, so a stale pointer can
    pass a content check. `impMulti[y][z] = impMulti[0][z]` for every row, and `impMulti[y][z] = impMulti[y][z-K_SIZE]` along a row,
    catch a partially or wholly stale row.
13. **(v15) Pause before closing the logger and before the joins.** `Loque` is asynchronous; when `close` is called with entries still
    queued, the last lines (`joined n=...`, `mainMS9 END`) were lost. A `Thread.Pause(0.5D0)` after the finish advance and another before
    `loque.close()` fixed it. After a crash the log tail is likewise unreliable; use a debugger (`break abort`, `thread apply all bt`).

**Results of ms7** (last run, log `5550bf2a`; collections 8 to 13 are the six explicit ones). `M` moved,
`S` stayed. The positions logged after collection *N* are compared with those after *N − 1*, so the
first comparable collection is 9.

| Object | #9 | #10 | #11 | #12 | #13 |
|---|---|---|---|---|---|
| `mov1`, `mov3`, `ctl1`, `ctl2`, `ctl3` | M | M | M | M | M |
| `mov2` (pinned by design) | M | **S** | **S** | M | M |
| `ctl4` (last array element) | M | M | M | M | S\* |
| `tail` (scalar global) | M | M | S\* | S\* | M |

Of 40 transitions, 2 are designed pins and 38 are unpinned: **35 moved, 3 stayed** (`*`, all
explained below).

- **Movement is conclusive.** Unreferenced objects move at essentially every collection, to a
  different page each time, at the same in-page offset (`+0x18`).
- **Selective pinning is clean.** `mov2` stays exactly while `pageTest` holds it: at #10 the hit is
  `pageTest`'s stack slot, first seen with note `Copied`; at #11 the same slot is hit again; at #12 it
  is gone and the object moves. No other tracked page is pinned by any thread's stack or `regs[]`
  (no `regs[]` hit appeared in this run at all).
- **Finished but unjoined threads are not scanned.** Objects whose allocating thread had exited
  moved (an earlier run); this agrees with the `watch < detached` condition.
- **Compiled-code polls park spinners.** The `nullTest` spinners were parked by the inline
  loop-edge poll at the stops of earlier runs.
- **Arrays of objects as module globals work.** All seven elements of the two global arrays were
  walked and rewritten at every collection; the stays are not a property of array handling (see
  below). `ClassifyTrace` is the compiler's classifier for `llvm.gcroot` registration of locals and
  temporaries; arrays have no branch there yet by decision, and it plays no part in this path.

**The collector pins its own highest page (accepted, register 38).** All three unwanted stays have one
cause. In every collection the coordinator's own stack (main, `me=1`) holds a word that is exactly a
page base (in-page offset `0x0000`), about `0x100` bytes above its `stack_ptr`. Its value never
decreases across the 13 collections: `0x57b0ccXX0000` with XX = b2, b4, bf, c0, cd, d9, e4, ed, ed,
f4, fd, fd, and then `0x57b0cd010000` once the heap had grown. That is what the highest in-use page of
a growing heap does. A tracked object stays exactly when it sits on that page: `tail` at #11 and #12
(`ccfd`) and `ctl4` at #13 (`cd01`). The rule "an object may stay if and only if it was on the highest
in-use page after the previous collection" predicted all five transitions. The earlier runs fit the
same rule: the stay followed whichever object sat on the highest page. It moved from `ctl3` to `ctl4`
when a fourth array element was added; once a scalar followed the array, the stays fell on that
scalar at some collections and on `ctl4` at others (the previous run: `tail` at #10 and #11, `ctl4`
at #12).

- **Probable source (inferred, not proven).** `CollectSomeInStateZero` flips spaces with
  `FOR p := p0 TO p1 - 1 DO … WITH page = PageToRef(p), d = page.desc …` and then calls
  `RTThread.ProcessStacks(NoteStackLocations)` in the same frame. After the loop `page` holds the
  highest in-use page's base address, and the coordinator's own frames are inside the range it scans.
- **Cause class.** Conservative scanning of the collector's own frames. It is not a threading issue:
  `RTCollector.m3` is identical in `pkg/neocore` and `pkg/neosys`, and the PTHREAD `ProcessMe` also
  scans the current thread's live stack, so the same artifact is expected there (not run).
- **Cost.** At most one page (64 KiB) per collection stays, plus whatever that page's contents
  reference (a promoted impure page is grayed whole). At 64 MB of heap that is about 0.1 %; in `ms7`
  (about 79 pages, 5 MB) it is about 1.3 %, which is why it shows at all. The same page stays pinned
  for as long as it remains the highest.
- **Decision (2026-10-29): accept, do not fix.** The collector stays unmodified. If it is ever
  wanted: move the flip loop into its own procedure and rerun; if the page-aligned hit disappears the
  source is confirmed, and if it remains it is stale residue where `ProcessStacks`'s own frame lands
  and needs a short stack scrub.
- **Consequence for the verifier.** The `ms7` pass rule is: every tracked object must move, except
  an object deliberately pinned, and except the object on the highest in-use page after the previous
  collection. (Generalised for ms8 below.)

**The diagnostics used** (the temporary per-hit trace; the user keeps the `WThread.GC` counter, parks
the `ProcessStacks` headers in a comment for reuse, and reverts `RTCollector.m3`). `ProcessStacks`
printed one header per call to `p` (`gc`, `tid`, `me`, `STACK` or `REG`, and the range; for `STACK` the
first printed value is the stack top and the second the stack pointer), and `NoteStackLocations`
printed one line per hit on a `Previous` page: the slot address (`fp`), the word (`fp^`) and the page's
note before promotion (0 Allocated, 1 Copied, 3 AmbiguousRoot). **Only the first (lowest-address) word that hits a page is
printed**, because the page is no longer `Previous` afterwards, and a `REG` range scanned after the same thread's `STACK`
range prints nothing for a page the stack already promoted: "no `REG` lines" means no register-only pin, not that registers
hold nothing. Offsets in the page and the page number come from `fp^` (`MOD 65536` and `DIV 65536`). **(v15)** ms9 added three more
temporary lines in the collector, all since reverted: `GCKIND partial= cycleL= cycleLength= minor= major=` after the counters in
`CollectSomeInStateZero`, `PROMOTE reason= page= nb=` in `PromotePage` for reasons below `AmbiguousPure`, and `COPYFAIL` in the
`np = NIL` branches of `Move` (never printed in any run). `PromoteReason` = {OldClean 0, OldPure 1, OldImpure 2, LargePure 3,
LargeImpure 4, AmbiguousPure 5, AmbiguousImpure 6}; `Note` = {Allocated 0, Copied 1, OlderGeneration 2, AmbiguousRoot 3, Large 4,
Frozen 5}; in the per-hit trace the printed `note` is the page's note *before* promotion in that collection, so 3 means the page was
already pinned by the previous collection.

**Evidence trail of ms7** (logs in the user's runs; the order is the order of discovery):

| Log | Change | What it showed |
|---|---|---|
| `c4e5bb17` | first full `ms7`: three cycles, page allocations, logger, `WThread.GC` | review found the flaws behind rules 1–5 |
| `474d559e` | added the `int`/`rec`/`obj` controls and `ctrl` | `ctrl` shared pages with `mov`, which produced a regular "stay after a move" pattern |
| `1bc52e38` | `obj` gained the 40,000-byte array (one object per page) | the earlier regular "stay after a move" pattern disappeared |
| `52657199` | `logCtrl` order reversed | the stay stayed on the last array element: not caused by the order of logging |
| `b2433f36` | `ctrl` grown to four elements | the stay moved from `ctl3` to `ctl4` |
| `078a9d06` | scalar `tail` added after the array | stays on `tail` and on `ctl4`: not specific to arrays |
| `5550bf2a` | `ProcessStacks` headers and per-hit trace | cause attributed to the coordinator's page-aligned slot |

### Stage 2 — embedded `REF` fields (`ms8`): implemented and validated (v14)

**Scope.** A `REF` field inside a heap record (`REF recR`) and inside an object (`objR`), each with a 40,000-byte `Large` array
(one object per page) and `r : REF Large`. The first test of the type-map path under WTHREAD.

**What ms8 does and does not exercise (clarified v14).** The collector finds `r` by **heap tracing from the owner through the
front end's typecell map** for `REF recR` (and the object's typecell): the owner is copied or, if pinned, its impure page is
grayed whole, and the referent is copied and the field rewritten. The conservative scan finds only the **owner** (and
residue). Evidence: conservative scanning never rewrites a word, and these referents moved and their fields followed. ms8 does
**not** exercise `TypeComp` metadata or the gcroot chain: its IR has no `meta.N` global; all 14 (`recrTest`) and 15 (`objrTest`)
gcroots are scalar temporaries; the owner arrays `a[]` are unrooted.

**Harness.** ms7's driver and subjects plus `recrTest` and `objrTest` (three owners each). Allocation, logging and checking are in
helper procedures taking the owner array by `VAR`, with `scrubStack` after each call. Each referent is seeded with
`(num*16 + n) MOD 256` in `initR` and checked with the same expression, so a swapped or shared referent fails an assertion. Owner
and referent addresses are logged at three sample points (after GC 5, GC 9 and GC 11); `mov`/`ctl` are logged after every
collection; assertions use `corruptR` (a failure produces a crash dump in the debugger — the user confirmed the assertions are
effective). Sizes: unbounded arenas (the default).

**Pass rule (generalised from ms7).** Every stay must be (a) a designed pin, (b) the collector's own highest page (register 38),
(c) on a page in that collection's hit list (stack residue, register 45), or (d) attributable to a documented collector policy
(register 41). An unexplained stay is a finding. Method: for each collection, take the tracked objects' pages after the previous
collection, intersect with that collection's hit list, and compare with observed stays.

**Results (final run, log `0c16fa06`).** Run completed (`mainMS8 END`), no assertion failure, all stage lines present.

- **Stay accounting: 65 of 65 transitions predicted by the hit list**, in both directions. Six stays: four on the collector's
  page-aligned slot (`mov3.r` at GC 9, `mov1.r` at GC 11 and 12, the `ctl2` owner at GC 13) and two designed (`mov2` at GC 10 and
  11, pinned by `pageTest`, released at GC 12). The collector's page-aligned hit rose `5d, 6f, 76, 7f, 7f, 87` (page numbers, low bits of the address) across GC 8 to 13 as the heap grew.
- **Owners** of `recr`/`objr` kept the same address in all three samples (pinned by the `a` array in the subject's frame).
- **Referents:** all 12 observed sample-to-sample transitions moved (6 referents, 2 intervals). Checking each referent against the
  first collection after it was sampled (the only point where its location is known): 17 of 18 had no stack word on their page; the
  one hit was the logger thread's stale slot at GC 6 (rule 3).
- **The pinned `mov2`'s referent moved at every collection while its owner stayed**, with the field following: the cleanest
  demonstration of the heap-tracing path through a pinned impure page.
- **No `REG` hit in any ms8 run.** The `regs[]` item (register 46) is still open.

**Residue pins (register 45), explained.** In the first runs the referents of the *last* loop iteration (n=3) of both `recrTest` and
`objrTest` never moved. The trace located the pinning words at slots whose frame offsets, recomputed from `llc -O0
-frame-pointer=all` machine IR, matched **spill-slot objects** of the subject's own frame exactly (all six lowest-hit slots).
The slot printed moves to lower addresses as the thread runs further, because the printed hit is the lowest word pointing at the page
and later code fills lower slots. A dead-store-elimination hypothesis was refuted (the pipeline has no optimiser; the scrub
loop is present in the `-O0` machine code, and making `scrubStack` observable changed nothing). Moving the loops into helper
procedures made the pins vanish. `llc -O1`+ allocates no spill slots (frame 1000 to 392 bytes), so the class does not arise there
(registers would hold stale values instead).

**Bounded-heap detour (register 41).** A run with fixed arenas (untraced 1 MB, traced 6 MB) changed two things at once but is
still informative: 17 stays at GC 10 and GC 12 had **no** hit on their pages (so the collector itself left them in place), GC 9, 11
and 13 moved everything, and a 5 MB traced cap failed with out of memory. With unbounded arenas none of this appears.
`nref_memstat` prints the cap, the bytes the arena has claimed, and the free bytes inside claimed regions: the 6 MB-capped run
claimed 5,702,880 bytes (87 pages, 9 short of its 96-page cap) against 6,751,552 (103 pages) unbounded, a difference of exactly
16 pages (1 MiB) plus two 48-byte carve-outs. That is consistent with a growth step the capped arena could not take, after which the
collector had to make do (promote in place, collect sooner, or fail). **(v15)** The mechanism for the out-of-memory half is now
identified (see "Bounded heap" under stage 3); the in-place half is consistent with `Move` promoting in place when `AllocCopy`
returns NIL, but was not re-tested.

**Evidence trail of ms8** (logs in the user's runs):

| Log | Change | What it showed |
|---|---|---|
| `992fe780` | first full `ms8` (no trace) | owners pinned, referents of n=1 and n=2 moved, n=3 referents never moved; asserts passed |
| `6bf28579` | `ProcessStacks` headers and per-hit trace restored | 65 of 65 accounted; n=3 referents pinned by stack words of their own subject threads at every collection from GC 6, never by `REG` |
| `5cbac3f3` | `scrubStack` made observable (returns a sum) | pins unchanged: dead-store hypothesis refuted; pipeline is `llc -O0` |
| `a071ee15` | loops moved to helpers; fixed arenas (1 MB, 6 MB) | n=3 pins gone, but 17 stays with no hit at GC 10 and 12 (two variables changed) |
| `48784e39` | unbounded arenas | capture error (heap statistics only) |
| `0c16fa06` | unbounded arenas, helpers, per-element seeds | **65 of 65 accounted; 12 of 12 referent transitions moved; run clean** |

### Stage 3 — arrays, views, copies, aggregates and text (`ms9`): implemented and validated on x86_64 (v15)

**Scope.** Everything the conservative scan and the heap type maps have to get right once the program uses arrays and by-value
aggregates: fixed and open arrays of bytes, integers and `REF`s at depth 1 to 3; interior views from `VAR`, `WITH` and `SUBARRAY`;
`VALUE` open-array parameters; by-value records and fixed arrays holding `REF`s two levels deep as a local, a module global and a
`VALUE` parameter; and a threaded text-heavy workload as a smoke test for corruption. The test is run first in its *movement* form (the
outermost variable is a module global, so the objects can move) and then, where the matrix says so, in a *local* variant (the
outermost variable is a local of the subject, so the stack scan pins it). Only one thing changes between a main run and its variant.

**Harness.** ms8's driver (`mainMS9`: three cycles of two stages, each stage a pause, a stage change for every subject, a pause and an
explicit `RTCollector.Collect()`, logged with `WThread.GC`; the first explicit collection is number 8) and subject structure (one thread
per subject, `ms9.wait`/`ms9.advance` on a per-subject mutex and condition, a spin loop at the edge stage that depends on the loop-edge
poll, `Loque` for logging, owner and referent addresses logged as `Word.Not(address)`, content seeded per element and checked after
every collection, `scrubStack` after each helper call). Allocation, logging and checking live in helper procedures. Each large object is
about 40,000 bytes so that it takes a page of its own. The final configuration runs **twelve subject threads on an 8-core machine**:
`smokeTest` four times, `intTest`, `pageTest`, `aggLocTest`, `aggGlobTest`, `aggValTest`, `valTest`, `multiTest` and `valMultiTest`.
(`oneTest`, `twoTest`, `recrTest`, `objTest`, `aliasTest` and the `mov` test were run in earlier configurations and omitted from the
final one.)

**The case matrix**

| # | Case | Subject(s) | Main run | Variant | Result |
|---|---|---|---|---|---|
| 1 | `REF ARRAY [1..N] OF R`, small (3) and large (20,000) | `oneTest` | global | local `REF`: **not run** | Content and shared-identity checks (`corruptRef`) held at every collection |
| 2 | open `REF ARRAY OF R`, of objects, of record-with-`REF`; sizes 3 and 20,000 | `twoTest`, `objTest`, `recrTest` | global | local `REF`: **not run**; sizes 1 and 100: **not run** | Held at every collection; owners' fields followed their referents |
| 3 | open arrays of bytes and integers | `intTest`, and the byte arrays under cases 4 to 6 | global | local `REF`: **not run** | Held at every collection |
| 4 | interior views, owner reference dropped: `WITH` on one element; `SUBARRAY` of a small array; `SUBARRAY` into the second page of a large array | `aliasTest` | local only | the control (same array in a global, no view) is implicit | The views' asserts held at every collection and no pinned-yet-moved object was found in the instrumented runs. The pathological arrangement (the view as the only reference) was run as asked; whether it is correct Modula-3 was not settled and the test claims nothing about it |
| 5 | `VALUE` open-array parameter copy (register 11) | `valTest` (1-D `SUBARRAY`), `valMultiTest` (6 by 9 by 3) | source global; the copy is a heap object held by the formal | none | Copy-in complete; the callee's writes never reached the source (103 and 109 read back after the callee wrote 100); the source reference could be dropped; the copy survived all collections; the 3-D copy is isolated in both directions |
| 6 | multi-dimensional open arrays | `multiTest`, `valMultiTest` | global | local `REF`: **not run** | `oneMulti` (13,000 by 3 bytes), `twoMulti` (1,666 by 8 by 3), `triMulti` (40 by 40 by 25, all 40,000 elements verified after every move) **moved at both transitions** with contents intact; `impMulti` (100 by 50 `REF`s) pinned in place in the later runs (moved in an earlier one), with its referent moving; a `READONLY` 3-D formal over a stack array and a by-value 3-D copy passed |
| 7 | by-value records and fixed arrays holding `REF`s, two levels deep (`AggArr`: three records, each with a `REF` record field `node` that points at a leaf, and a leaf of its own) | `aggLocTest` (7a), `aggGlobTest` (7b), `aggValTest` (7c) | 7a: local copy; 7b: module global | 7c: `VALUE` parameter (72 bytes, front-end warning). The three differ only in where the aggregate lives, so they ran together | 7a and 7c: the objects the aggregate points at **stayed**, the objects *they* point at **moved at both transitions** and the pointers followed. 7b: all three levels **moved** |
| 8 | text-heavy threaded smoke test | `smokeTest` x 4 | n/a | n/a | About 987,000 allocate-and-store loop iterations over three spin windows, eleven collections (six explicit, five allocation-triggered), `smokeOK` over all 64 slots of every thread after every stage: no corruption |

**Movement at the two transitions in the final configuration** (`M` moved, `S` stayed; the three windows are before the first
collection, after the second and after the fourth):

| Object | Transition 1 | Transition 2 |
|---|---|---|
| `oneMulti`, `twoMulti`, `triMulti` | M | M |
| `impMulti` (the array) | S | S |
| `impElem` (a leaf `impMulti` points at) | S | M |
| `aggGlob` `node`, `leaf` | M | M |
| `aggGlob` `next` | M | S (varies by run) |
| `aggLoc`, `aggVal`: `node`, `leaf` (pinned by the stack copy) | S | S |
| `aggLoc`, `aggVal`: `next` (reached only through the pinned `node`) | M | M |

**Findings**

1. **Open arrays move correctly at every depth tested.** A heap `REF ARRAY OF T` is one object: the dope (an elements pointer at
   offset 0, then one size word per open dimension, 8 + 8·d bytes) followed by the data. `Move` rewrites the elements pointer as `np + def.dataSize`.
   That fix-up is now exercised at depth 1, 2 and 3. A fixed `REF ARRAY [1..N] OF T` has no dope and points at element 1. Open-array
   formals are indexed from 0 whatever the actual's bounds were (the asserts on `a3[...]` and `NUMBER(...)` rely on this).
2. **A pinned multi-dimensional `REF` array is traced through its page.** `impMulti` stayed where it was while `impMulti[0][0]` moved
   (`impElem`, transition 2) and all 5,000 slots read back the right leaf in every row. Because a freed page keeps its old bytes, the
   check compares each row with row 0 and each slot with the slot eight earlier (harness rule 12), not only the content. Why `impMulti`
   itself was pinned in the later runs is not identified (a page-level pin, as in 6 below).
3. **Views pin.** An interior pointer from `VAR`, `WITH` or `SUBARRAY` held only on the stack keeps the whole page of its array in
   place; the collector's own comment says the same. In `valTest` the `VAR` view (`tail`) into the large array was at the same
   address in every window.
4. **`VALUE` open-array formals are independent copies.** The front end warns "Open array passed by value" and emits a heap copy
   (`Variable.CopyOpenArray`: `NewTracedArray` plus `Copy_n` over the product of the open sizes, formal re-pointed in `LangInit`). The
   copy-in, copy-out isolation and survival are as in the matrix. A 72-byte record array by value gives "Large parameter passed by value".
5. **By-value aggregates need no map on the stack.** A local copy or a `VALUE` parameter is found by the whole-stack scan (the direct
   referents are pinned), and the next level is reached by tracing the pinned impure page, so the second level *moves* and the pointer
   in the pinned object follows. A module-global aggregate is a precise root through `WalkGlobals`, and all three levels move.
6. **Stays are layout-determined and reproducible.** Runs of the same source at the same settings repeat the same movement pattern
   object for object (checked on two consecutive runs and again with four extra allocating threads). Changing the layout (adding a
   `burnPage`, removing a spacer, adding a subject) changes which objects stay; in five of the eight runs decoded, one `aggGlob` object
   stayed at the second transition (`node` and `leaf` in one run, `next` in four), and in the other three all of them moved. No stay ever coincided with corruption. The instrumented runs of the
   first six subjects (logs `c8ac0059`, `8e2985ca`, `938ad3dc`) explained every stay by a stack hit, by page sharing or by a large-object
   promotion, with no case of an object that was pinned and moved anyway and no `COPYFAIL`; the impact is memory only (pins retain, they
   cannot corrupt): about 22 to 34 pinned pages per collection, 16 to 25 % of the arena's pages, mostly objects that were live by design, a flat plateau, no growth seen.
   The later subjects were judged on content assertions plus the movement pattern, without re-instrumenting the collector.
7. **Page placement matters to a movement test.** `oneMulti` did not move until `burnPage` kept the MS9 closures (small objects) off its
   page; `triMulti` did not move while the test passed `triMulti^` as a `READONLY` formal (a dope temporary in the caller's frame held an interior pointer). These are harness rules 9
   and 10, not collector behaviour.
8. **Allocation-triggered collections.** With the smoke threads running, the `WThread.GC` counter advances by two per explicit
   collection (8, 10, 12, 14, 16, 18): one extra, allocation-triggered, collection in each gap. The number of extras did not grow when
   the allocating threads went from one to four (584,894 against 987,282 loop iterations in total), so the trigger is not proportional to
   bytes allocated. Whether any of them were partial was not measured (the `GCKIND` line was off in these runs).
9. **Compile-time notes.** `Open array passed by value` (the `VALUE` open-array formals) and `Large parameter passed by value (72
   bytes)` (the by-value `AggArr`) are expected: those are the paths under test.
10. **The `m3llhost` build hangs the harness; the `m3llwasm` build does not.** A spin loop `WHILE ms9.stage < s DO INC(spinner) END` has
    no safepoint poll on `m3llhost`; the loop-edge poll of `m3llwasm` parks it.

**Bounded heap (register 41): mechanism, space bound and experiments.**

*The runs.* The user capped the arenas with `@M3traced=20M @M3untraced=10M` (and 18M, 22M, 32M) on the twelve-subject configuration,
8 cores. Unbounded, the allocator statistics at exit read `Traced 0 20907904:800`, which I read as the footprint of this workload (the same figure as in the capped runs that passed).

| Traced / untraced cap | Collector mode | Result |
|---|---|---|
| unbounded | incremental (default) | passes; 20,907,904 B traced at exit |
| 18M / 10M | incremental | did not run |
| 20M / 10M | incremental | **intermittent**: passes in two logged runs, fails in others (out of memory) |
| 22M / 10M | incremental | failed on the third run |
| 32M | incremental | 10 of 10 pass |
| 20M / 10M | **`@M3noincremental`** | **10 of 10 pass** |

*The error.* The three failures captured (20M twice, 22M once) are the same runtime error: `NEW() was unable to allocate more memory`, `RuntimeError.m3` line 63, then abort.
Each stopped at the same program point: in the third cycle, after the `pauseTre` log lines and before `+GC|n=16`.

*The stack (debugger, 20M, `faf2ed40`).* The thread that failed is `aggLocTest`, inside `aggLog`, doing a text concatenation:
`RTHooks.Concat` to `TextCat.Balance` to `TextCat.Flat` to `RTHooks.AllocateTracedObj(Text8Short)` to `RuntimeError.Raise(OutOfMemory)`. The
failing request is a tiny object, so no page was free at all. The error path then calls `RTProcess.Crash` to `RTHeapRep.Crash`
(`RTCollector.m3` line 1619), which **finishes the collection that was in flight** (`CollectSome`), and that collection fails again:
`CollectSomeInStateTwo` to `PreHandleWeakRefs` (line 1148) to `InitStack` (line 1354), whose `NEW(Stacker)` is a traced allocation
made by the collector itself, raising `OutOfMemory` a second time before `abort`. All four smoke threads were parked in `Wait` and the
driver was in `Thread.Pause` before its `Collect`; only `aggLocTest` and `multiTest` were running. So the heap was full of garbage
from the preceding spin and a collection was part-way through.

*The mechanism (from the sources; the line numbers of the trace match the repo).* The mutator's slow path is `AllocTraced`
(`RTAllocator.m3` line 364): when the pool is exhausted it takes the heap lock, calls `CollectEnough`, then `LongAlloc`. `CollectEnough`
(`RTCollector.m3` line 663) returns at once if a collection is on, and otherwise collects only if `Behind()` (line 689) says the pacing
threshold is exceeded, which is a function of `n_new`, `n_copied`, `gcRatio` and the survivors, **not of free space**. `LongAlloc`
(line 1432) asks `FindFreePages` (line 2325), which asks `GrowHeap` (line 2601); `GrowHeap` refuses to grow past `max_heap` and
returns FALSE; `LongAlloc` returns NIL; `GetTracedObj` returns NIL; `AllocateTracedObj` raises `OutOfMemory`
(`RTAllocator.m3` line 127). There is no "finish the collection, then retry" step. While an incremental collection is in flight its
copies take free pages and the pages of the old space are not released until it completes, so a capped heap can run out
mid-collection. Uncapped, `GrowHeap` simply grows, which is why the unbounded runs pass. In stop-and-copy mode (`@M3noincremental`) a
collection runs to completion inside the allocating call (the `ELSE` branch of `CollectEnough`), so nothing is in flight when `NEW`
fails, and the same cap passed 10 of 10. The copy side is more forgiving: `Move` promotes in place when `AllocCopy` returns NIL.

*The documented bound* (`RTCollectorSRC.i3`, the comment on `incremental`, lines 36 to 48): with `A` pages of accessible objects, the
heap must contain up to **A x (2 + 1/gcRatio)** pages when stop-and-copy and **A x (2 + 2/gcRatio)** when incremental; at the default
`gcRatio` of 1.0 that is **3A** and **4A**. For ms9 A is roughly 5 to 6 MB (a rough, unmeasured estimate: about sixty one-page 40 KB
objects, six two-page `Page` objects, the 20,000-element arrays), so the incremental requirement is about 20 to 24 MB and the stop-and-copy
requirement about 15 to 18 MB. That is exactly where 20M and 22M flaked and where 20M with `@M3noincremental` was reliable. **This is the
design's stated space requirement, not a defect;** below it, running out is expected.

*What it leaves open* (register 48): (a) the allocator gives up without finishing an in-flight collection and retrying; (b) the
collector allocates from the traced heap in state Two (`InitStack`), so a collection can itself fail on a full heap and the crash
handler fails the same way. Both matter only below the bound.

*Consequences for wasm32.* `--max-memory` is mandatory and bounds all of linear memory (static data, stacks, the untraced arena
and the traced arena), so the traced cap is smaller than it. The cap must be chosen from the bound, using the collector mode in force:
whether `m3llwasm` modules carry the incremental and generational flags is register 49. The ms8 observation of v14 (6 MB: 17 objects left in place; 5 MB:
out of memory) is consistent with the same mechanism for ms8's live set; it was not re-run.

**Evidence trail of ms9** (logs in the user's runs; selected):

| Log | Change | What it showed |
|---|---|---|
| `8802817d` | first run after the `ClassifyVar` fix | the open-array module verified; cases 1 to 3 main runs worked |
| `b996bab5`, `01ef320d`, `f520eaf7`, `ecd0edb7`, `14281e01` | case 4 (three views) and case 5 (`VALUE` `SUBARRAY`) built up | views pin; the copy is independent and survives |
| `c8ac0059`, `8e2985ca`, `938ad3dc` | collector diagnostics on (`GCKIND`, per-hit, `PROMOTE`) | every stay explained; no pinned-yet-moved object; no `COPYFAIL` |
| `343207df`, `a4f1d364`, `4c6485f0` | `smValKeep` and the added asserts for `valTest`; first `multiTest` | the original of a `VALUE` copy is unchanged; multi-dim `READONLY` formal works |
| `930d7302` | `valMultiTest` added; `triMulti` as a 3-open-dimension array | `twoMulti` and `impMulti` moved; `oneMulti` and `triMulti` stayed for placement reasons (rules 9, 10) |
| `4f5a814f` | `burnPage`, `triSmall`, `triMulti` as a global | `oneMulti`, `twoMulti`, `triMulti` move at both transitions; `impMulti` pinned |
| `f609791d` | case 7 added | 7a and 7b as predicted; 7c's loop was an unfinished placeholder (found in review) |
| `2a047019` | nine subjects, 7c complete | 7a, 7b, 7c all behave; 9 of 9 joined |
| `6212eeb8` | `impElem` logged | the referent of the pinned `impMulti` moves at transition 2 |
| `6e4a55aa` | row-identity assert added, repeat | identical pattern to the previous run; the 72-byte warning noted |
| `b0138a35`, `dfa25307` | smoke test, one then four threads | eleven collections, `smokeOK` clean; 584,894 then 987,282 iterations |
| `08b73b4b`, `d471889c` | 20M traced / 10M untraced | passes (same movement pattern as unbounded) |
| `308c882b`, `edaa28f5` | 20M, then 22M | out of memory at the same program point |
| `faf2ed40` | the 20M failure under the debugger | the trace above |
| (no logs kept) | 10 runs at 32M, 10 runs at 20M with `@M3noincremental` | all pass |

**Not covered by stage 3** (open, in the order they matter): the local-`REF` variants of cases 1, 2, 3 and 6; sizes 1 and 100 for case
2; a `regs[]` hit; another thread's published stack on wasm32; a real collector on wasm32 (registers 44, 46); exceptions and nested
procedures; `BITS N FOR T` fields. The ms9 IR has not been audited (register 42).

**Status.** Stage 1 (stop-the-world) was validated in v11 by a C harness against the real `nthr`/`nsyn`; v13 added the
conservative pinning validation; v14 added stage 2; v15 adds stage 3. The root mechanism is complete for x86_64 under WTHREAD, and
the heap type maps and the stack scan together cover arrays, views, copies and by-value aggregates. What remains for roots is the
wasm32 confirmation (registers 42, 44).

---

## Phase D — Precise Stack-Root Scanning (PARKED by decision, v14)

**Status (v14, unchanged in v15).** Parked. The v14 decision keeps roots conservative, so none of Phase D (D1–D4) is scheduled. The material below
is preserved so that nothing has to be rediscovered if the re-open conditions in "Decision (v14)" are ever met. The first step
then would **not** be this walker but address roots with null metadata (an optimiser prerequisite). ms9 gave no reason to re-open it.

Structure as before (D1–D4). Notes:

- **`RTTypeMap.i3` needs a small addition before D1 can call it: `Walk`/`DoWalkRef`
  are private to `RTTypeMap.m3`, not exported.** Resolution agreed at the time: add a new
  public entry point (`WalkStack(x, pc: ADDRESS; m: Mask; v: Visitor) RAISES ANY`)
  that calls the still-private `Walk` internally — deliberately *not* `WalkRef`, which
  does two things unsuited to a stack root: a `TYPECODE`/`RTType.Get` lookup that
  doesn't apply to a bare composite (no runtime typecode exists for one), and an
  unconditional `RTHooks.CheckStoreTraced` call — heap-page dirty-tracking machinery,
  category-confused against stack memory, which has no page descriptor or header for
  it to resolve at all. **(v14)** `RTTypeMap` is shared with PTHREAD, so this edit would itself be a variance from the
  baseline; the alternative is a small refs-only interpreter in `WThread` (ops `Ref`, the skips and `Stop`).
- **The `refs_only` finding (Phase B2) is believed sufficient but needs finalizing
  here, not assumed.** `TypeComp`'s output only ever contains `Op.Ref`/`Op.Stop`. That
  likely makes `WalkStack`'s `mask` parameter a non-issue in practice, but this should
  be confirmed explicitly once D1's synthetic-heap test is being built, alongside
  resolving the still-open `type_map`-vs-`gc_map` question from Phase B2.
- **Where the chain head comes from.** Parked threads: read the head
  `nthr_park` published in the thread context. The thread running the collection holds
  `relief` and never parks, so its own chain head is its live thread-local — to be
  confirmed in D1. Also to confirm in D1: threads inside **blocking primitives**
  (Phase A invariant 2) must also have a published head, i.e. that path goes through
  the same publish step as `nthr_park` — `nthr_vigil` now does (register 21, closed).
- **Aggregate root-slot addressing — open design question for D1 (register 13).** The
  walker needs, for each composite root, the *address* of its slot and its metadata. **Verified in v14 on LLVM 18.1.3:**
  the lowered frame entry is a struct `{ {next, map}, <each root in its own type> }`; metadata-bearing roots come **first**,
  packed contiguously with no alignment padding (alloca alignment is dropped, bug 2), then scalar roots at the next 8-byte
  boundary; the frame map is `{i32 NumRoots, i32 NumMeta, ptr meta[NumMeta]}` with no sizes or offsets. A stride-by-pointer
  walk therefore misreads any frame with an aggregate. Options considered (v14): (1) scalar-only frames (`NumMeta = 0`),
  stride 8; (2) put each aggregate's byte size in its metadata and recompute LLVM's layout (fragile: an upstream fix of the
  alignment bug would silently shift offsets); (3) **address roots** — the aggregate stays an ordinary aligned alloca, the
  gcroot slot holds its address, and the metadata describes the pointee (every root is one pointer; retires the marker
  workaround and both LLVM-bug dependencies for this path; scales to arrays; the preferred form if aggregates ever need
  rooting); (4) a precise-root API in the collector (rejected: breaks the principle, unsound with unrooted derived copies).
- **The root walker must tolerate roots that point outside the traced heap
  (register 14).** Such roots already exist: `phaseB`'s `t` is initialised to a static
  text literal in `M_Const`, and an open-array parameter slot holds the caller's dope
  address until its re-point. The walker must recognise and skip non-heap addresses,
  rather than treating every root value as a heap pointer. (Address roots with null metadata would hold stack addresses,
  which are also non-heap.)
- **Registers as roots (v12).** Each stopped thread's `regs` (x86_64 callee-saved registers
  spilled by the assembler when it publishes the stack) are conservative roots; on wasm32 the
  array is zero. See register 26. **v13:** `ProcessStacks` passes them (Phase C).

---

## Phase L — The Core Library on wasm32 (new in v12; before Phase E)

**Status: a new top-level task, decided 2026-10-21.** It sits before Phase E and is independent of
the collector work in the code it touches, so it can be interleaved. It is also
what lets the front end build user-space programs for wasm32 (today it cannot, because the system
dependencies are not built for wasm32), and so unblocks `Target.m3` testing and the attribute
cleanup (register 3, 8). **(v14)** It also produces the library bitcode on which the audit gate must be run (register 42),
and it is reported as getting close. **(v15)** It is now the critical path: every remaining wasm32 step waits on it.

**What the survey found** (m3neos `pkg`: `neosys` is m3core plus the runtime, `neolib` is libm3):

- The C API calls Modula-3 uses and the system calls underneath them are **two cleanly separated
  parts**.
- **Modula-3 file I/O is entirely fd-based** (`Uuio`); there are no `Cstdio` importers. The
  C-side stdio exposure is only `RTIOc.c`, `nthr_debug` and `nref_diag_dump`. RTIO is meant for
  compiler development and for debug output that does not depend on the Modula-3 runtime
  (including garbage collection and front-end parsing). So no stdio/musl vendoring is needed
  for now.
- **Absent from WASI** (by design — sandboxing — and the project targets wasm on the server
  side, where Modula-3 was meant as a systems language; the gaps are expected, not defects):
  fork/exec/wait/pipe; sockets and netdb; signals; pwd/grp; termios; tzset; popen/system/tmpfile;
  and the `UnixC` subset (dup, pipe, umask, chown, mknod, getdtablesize, file locks).
- **Modula-3 modules affected:** `SystemPosix`, `SchedulerPosix`, `LowPerfTool`; `RTPerfTool`
  (via `Uexec`); `SocketPosix` (via `Usocket`, `Unetdb`, `Uin`); `ThreadPosix`, `FloatMode`, `FPU`
  and `ConnectRdWr` (via `Usignal`).
- `m3core.h` needs a wasm32/WASI guard section.

**Stage 1 — use what is in wasi-sdk's libc.** Get `neosys`/`neolib` to compile and link for
wasm32 against wasi-libc as it is. No patched wasi-libc and no vendored musl: those are needed
only if concurrent stdio or locked libc globals turn out to be really required. Deliverables:
the `m3core.h` guard; the module selection per target so the Unix-only modules are not pulled in;
a build of the core libraries for wasm32 using the build flags above.

**Stage 2 — account for the system calls WASI lacks.** Modula-3 must accommodate them: stubs
that fail cleanly (an exception or error result, as the interface allows) or wasm32-specific
replacements, module by module, for the list above. The exact policy per interface (fail,
emulate, omit) is decided as each is reached; `_WASI_EMULATED_SIGNAL` covers a part of the
signal surface where emulation is acceptable.

**Constraints.** Frozen baseline (guard everything; the x86_64 build of `m3core`/`libm3` is
unchanged). The Libc/`Uuio` boundary stays as is. No change to PTHREAD. **(v14)** The wasm32 library is compiled by `m3llwasm`
with `llc` only (no optimiser), and the audit gate runs on its bitcode before the first run under the collector. **(v15)** The
library's memory behaviour on wasm32 also decides the collector mode and the cap (registers 41, 49).

---

## Phase O — Optimiser enablement (future, not scheduled; new in v14)

**Premise.** The pipeline has no optimiser, and the current root scheme is correct only without one (constraints table above).
Optimisation should be driven by measurement of the code that actually dominates a representative program (for instance the
front end compiling a file), and correctness comes first. Measured context, for orientation only (analysis note): `-O0` to
`-O2` is roughly 2 to 4 times on tight scalar loops in one published C++ library and much less on call-bound code; gcroot costs
about 1.5 ns per call of a rooted function on x86_64 and so eats most of the optimiser's gain on pathologically call-dense code
and a few percent or less on code that does real work per call.

**Entry criteria (all required).**

1. Every traced value that is live across a safepoint has a memory home an optimiser cannot remove: scalar traced variables and
   **all traced temporaries** gcroot'd (the derived-copy rule becomes a hard requirement), and aggregates and fixed arrays of
   references rooted by **address roots with null metadata**. **(v15)** The open-array `NEW` dope temporary (not a root since
   `ClassifyVar`) and the open-array VALUE copy slot belong on this list.
2. The audit gate shows zero not-homed pairs on the **optimised** IR, and the wasm32 visibility harness passes at the chosen
   pipeline.
3. The two shadow-stack LLVM bugs are re-checked at the chosen levels (or fixed upstream).
4. ms8/ms9 are rerun at the new pipeline as a one-variable experiment.
5. A measurement shows the optimiser gains enough on representative code to justify the cost of the extra rooting.

---

## Phase E — Exception Handling Parity for wasm32

Unchanged. Deferred until after Phase L (and no longer waits on Phase D, which is parked). `ExceptionDebug.argType`
is the relevant field when this phase is picked up. One design question to carry into this phase:
how exception unwinding restores the thread-local shadow-stack chain head when it skips frames.

**Observation (not investigated further — register 16).** In a minimal reproduction
on LLVM 18.1.3, the shadow-stack lowering rewrote ordinary calls in a `gc "shadow-stack"`
function into `invoke`s whose unwind edge goes to a generated `gc_cleanup` landing pad
(a cleanup that restores the saved chain head and resumes), and gave the function the
personality `__gcc_personality_v0`. The module already declares `__m3_personality_v0`,
which is not yet attached to any function. Two things to settle in this phase: how the
lowering's personality and cleanup pad interact with the project's own personality, and
whether the lowering's cleanup already answers part of the chain-head question above.
(v14: the same lowering output was seen again in the frame-layout experiment: `invoke` of the call, a `gc_cleanup` pad that
restores the saved head, and `resume`.) **(v15)** In the debugger trace the runtime out-of-memory error went through `RTException.Raise`, the default backstop and
`RTProcess.Crash` as designed; that path was not otherwise examined.

---

## Consolidated open-items register

Ordered. "B1" items continue the B1 close-out list; "B2" items are the narrow
`m3t`/metadata leftovers. **Numbering is stable across versions; items 1, 2, 4, 7, 20, 21, 22, 24, 26, 29, 32, 33, 36, 38 and 47 are
closed in place (or accepted), 11–16 date from v10, 17–22 from v11, 23–32 are from v12, 33–40 from v13, 41–46 from v14, and 47–50 are new in v15.**

| # | Item | Phase | Notes |
|---|---|---|---|
| 1 | ✅ **Parameter rooting** — closed in v10 | B1/B2 | `m3t`, size, align and `inProc` now flow from `declare_param`'s `LvVar` into `NewVar` in `begin_procedure`. Verified by IR inspection; v14: the audit shows no parameter value is used across a safepoint |
| 2 | ✅ **Loop-edge safepoint polls** — closed in v11 | B1 | Poll on the taken side of every back-edge; `EmitSafepointCheck`'s flow block is the continuation. Run through six generated test procedures in v11 |
| 3 | **`Target.m3` generic wasm32 system (`WASM32_WASI`)** | B1 | Deterministic 32-bit width (not by name substring); excluded from the 32-bit alignment downgrade for non-C backends so `m3llhost` is unchanged; confirm `phb.ast` shows `Int.32` and a 4-byte `Addr`. User-space programs for wasm32 additionally need Phase L stage 1. **First step of the near-term sequence** |
| 4 | ✅ **`LLVMVerifyModule`** before the output step — closed (a couple of sprints before v12) | B1 | The user invoked it; catches the invalid-module class early. **(v15)** The verifier error behind register 47 (`llvm.gcroot` on a non-pointer alloca) is of this class |
| 5 | **Debug info: NIL element** for objects without a supertype | B1 | LLVM 20 rejects it |
| 6 | **Report two LLVM bugs upstream** | B1 | Aggregate gcroot `llc` crash; shadow-stack lowering drops alloca alignment. Reproducers ready. (v14: a fix of the second would shift the frame layout of the dormant composite path; address roots would be immune) |
| 7 | ✅ **WTHREAD codegen through `m3llwasm` for the x86_64 target** — closed in v11 | B1→D | Six generated test procedures ran under the WTHREAD thread harness on x86_64; fairness held, `LockHeap` nested locks did not regress, all tests passed |
| 8 | Finish the wasm32 function-attribute cleanup | B1 | Only partially done. Waits on Phase L stage 1: the front end cannot compile user-space programs for wasm32 until the system dependencies are built for it (codegen without that yields 8-byte pointers and the `AllocVar` assertion `v.align <= ptrBytes` fires). **Second step of the near-term sequence's prerequisites** |
| 9 | Declaration-ordering assumption; `type_map` vs `gc_map` at collection time | B2 | See "Still open, narrowly". **v14:** the `type_map`/`gc_map` question is no longer a prerequisite for any scheduled work (parked with Phase D). **v15:** the miss-assert still never fired across ms9 |
| 10 | Phase D prerequisites: `WalkStack`; `refs_only`/`mask` finalization; chain-head sourcing for parked, coordinator and blocked threads | D | **Parked in v14** with Phase D. Items 13 and 14 add two more prerequisites |
| 11 | **Open-array VALUE parameter copy** (`number`) and open-array dope-vector temporaries | arrays | **v15: behaviour validated on x86_64** (copy-in complete, writes isolated, survives collections; 1-D `SUBARRAY` and 6 by 9 by 3). The open-array `NEW` dope temporary is explicitly not a root (47). What is left is wasm32: the formal's slot must be in memory the scan covers for the whole body (42, 44) |
| 12 | **Opaque types: derive `traced` from the super's entry** in `declare_opaque` (`TracedOf` helper) | B2 | **Parked by decision; reminder carried.** Forward-declared super still inherits the `TRUE` placeholder; likely to arrive as imported partial reveals |
| 13 | **Aggregate root-slot addressing for a precise walker** | D1 | **Parked in v14.** Layout facts verified on LLVM 18.1.3 (Phase D, parked): metadata roots first, contiguous, scalars after at 8-byte alignment, frame map has no sizes. Preferred form if ever needed: address roots |
| 14 | **Root walker tolerates non-heap roots** (static text literals; caller dope addresses) | D1/C | Skip addresses outside the traced heap; applies to any precise walker. Not needed while roots are conservative (the collector's `NoteStackLocations` already ignores non-heap words) |
| 15 | `pop_struct` copy is `llvm.memcpy ... align 1` although slot and source are `align 8` | B1 | Low priority; legal and harmless under stop-the-world; decide whether intended. v15: the path was exercised by ms9's 72-byte by-value record with correct results |
| 16 | Shadow-stack lowering's invoke rewriting, `gc_cleanup` pad and `__gcc_personality_v0` vs `__m3_personality_v0` | E | Observation only; settle when exception handling is picked up |
| 17 | **Phase C stages 2–3 (v11 numbering):** validate each stopped thread's published chain, then walk it | C→D1 | **Parked in v14** (precise roots not pursued). Note that v13 to v15 reuse the words "stage 1", "stage 2" and "stage 3" for the conservative pinning, ms8 and ms9 harness stages |
| 18 | ✅ **`stack_chain` initialisation** — closed for `nthr_create` | A | `nthr_create` sets `ctxt->stack_chain = NULL`; `nthr_default` also, and both zero `regs` and clear `ended` |
| 19 | **Memory-ordering portability note** — out of scope | A | The `watch`/`safePoint` store-then-load pairing relies on the nsyn lock operations between the coordinator's `safePoint := 1` and its reads of `watch` being full barriers: true on x86_64 (locked read-modify-write) and wasm (atomics are sequentially consistent, so wasm32 on ARM hardware is covered too). Targets are x86_64 and wasm32 only; native ARM would need an explicit fence, and is not planned. The thread-side handshakes (`nthr_wait`, `nthr_lock`) are `seq_cst`; a weaker target would need `seq_cst` on the coordinator's `safePoint` store and `watch` load as well, and a `seq_cst` final `safePoint` load in `nthr_vigil`. The rules are in Phase A addendum 3 |
| 20 | ✅ **Nexus and context layout** — closed 2026-10-22 | A/B1 | `{safePoint, safeSyn, watchSyn, parked, forkList, forkSyn}` agrees with LLVM's layout of `{i32, lock, lock, i32, ptr, lock}`: x86_64 offsets 0/4/16/28/32/40, size 56; wasm32 0/4/16/28/32/36, size 48. `CompileSafepoint` declares the nexus shape and the context type with the appended `regs` (six pointer-sized elements) and `ended` (`i32`) |
| 21 | ✅ **`nthr_vigil` publish and re-check** — closed 2026-10-22 | A | Re-check after the restore is in place (Phase A addendum 2). Publish: `nthr_vigil` calls `nthr_arch_stack32` and refreshes `stack_chain` before the exchange, when it is eligible to wait. When the target is already detached it only reaps. Needed by `InitialThread`, where the default thread sits in the join for the life of the program |
| 22 | ✅ **Startup ordering for the default thread** — closed 2026-10-29 on evidence | A→D | Shape: `WThread.InitialThread` with the `Init`/`Axis` design of 2026-10-24. Evidence: collections run in the main thread before any harness code forks a thread, without failure (also in the ms8 and ms9 runs). The v12 checklist is the place to look if an early collection ever fails |
| 23 | **Phase L: the core library on wasm32** — new in v12 | L (before E) | Stage 1: use wasi-sdk's libc as is, `m3core.h` wasm32/WASI guard, per-target module selection. Stage 2: backfill or stub the system calls WASI lacks. Frozen baseline: guarded, x86_64 unchanged. **Third step of the near-term sequence's prerequisites; reported as getting close** |
| 24 | ✅ **WTHREAD as a native, traced object type** — done in v13 (`beta.17`, `beta.18`) | A→C | `pkg/neocore` builds `Thread.T` on WTHREAD; `ms4`, `ms7`, `ms8` and `ms9` run `Fork`/`Join` with traced allocation under the collector, with an early collection at startup. `WThread.m3` contains no `DISPOSE` statements |
| 25 | **Pinning of LLVM roots** — new in v12; split in v13; **25b parked in v14** | C | **25a ✅ conservative scan, done and validated** (Phase C). **25b (chain walk) parked by the v14 decision**: the whole-stack scan is the mechanism, gcroot slots being in the scanned range (wasm32 harness). Revive only on the re-open conditions in "Decision (v14)" |
| 26 | ✅ **`ProcessStacks` passes `regs` to the collector** — done in v13 | C | `ProcessStacks` calls `p` on `regs` for every non-detached thread, and the coordinator calls `thread_stack32()` on itself first. No `regs[]` hit has appeared in the `ms7`, `ms8` or `ms9` runs, so the path is exercised but a register-held pin is not yet demonstrated (46) |
| 27 | **nref/nthr small items** — new in v12 | A/nref | (a) `nref_define` diagnostic when the `Virtual` size is not a multiple of 64 KiB on wasm32 (otherwise `sbrk` traps with `unreachable`); (b) widen `arg_match` size arithmetic to `size_t`/`unsigned long long` with overflow checks (`long` is 32 bits on wasm32); (c) comment in `nthr_vigil` that the caller holds `joinSyn`; (d) correct the stale fence comment in `nthr_wait`; (e) consider writing each `nthr_debug` line with one `write(1, …)`; (f) bring the m3neos repo's `nref.c` up to the project version; (g) stock wasi-sdk 24 `malloc.h` lacks `struct mallinfo`, so `nref.c`/`nref.h` need a guard or shim. (h, v14 observation) `arg_match` in the project copy of `nref.c` uses `=` where `==` is meant in two places of its suffix tests (`arg[i] = 'k'`, `arg[i] = 'm'`), which assigns and then tests the assigned value; check against the user's tree. **(v15)** The `K`/`M` size options worked in the capped ms9 runs on x86_64 (`@M3traced=20M`, `@M3untraced=10M`), which suggests (h) is not present in the user's tree |
| 28 | **`AlertJoin` stale `joinSyn`** — new in v12 | A | The target may hold a pointer to the joiner's `threadSyn` after the joiner's `T` is freed. With `T` traced (24) this should be closed; recheck on the user's tree |
| 29 | ✅ **Build wiring for the `.s` files** — closed 2026-10-22 | build | Done: the compiler driver scripts were adjusted and the x86_64 instance builds. Policy stays: `-matomics` in the wasm32 script only; link flags per "wasm32 build flags" |
| 30 | **Report WAMR upstream issues** — new in v12 | wasm32 | See `claude/wamr-build-notes.md` for the build-side findings; the `@M3virtual` workaround stays until memory growth works |
| 31 | **Second runtime cross-check** — new in v12 | wasm32 | The wasm32 join/exit results come from node with worker threads; run the same cycles under WAMR (and ideally one more engine). The harness package built against the user's own tree is the vehicle. Extends to the collector smoke test (44) |
| 32 | ~~Update `claude/wasm32-resume-notes.md`~~ — withdrawn 2026-10-22 | docs | The notes file was an interim for an earlier chat; this plan carries everything needed |
| 33 | ✅ **`nthr_lock` safe-region lock and the watch-transition rules** — new and closed in v13 | A | Phase A addendum 3. Review every new blocking primitive against that table |
| 34 | **`SuspendOthers` requires the heap lock** — new in v13 | A/C | Held by `Collect`, `StartCollection`, `AllocTraced` and `RTHeapStats`. The `After` and `VisitAllRefs` paths call it without it; they should take the heap lock first. A bare call aborts with `NOPARK` as soon as a fresh thread allocates |
| 35 | **Library poll policy** — carried forward, recorded in v13 | B1/C | Polls are emitted into user code only; `pkg/neocore` is deliberately not compiled with `m3llwasm` on x86_64 until stop-the-world and pinning are proven and the codegen is shown compatible with the runtime. Before polls are ever enabled in library code, `RTAllocator`, `RTCollector` and `RTHeapRep` must stay poll-free: parking inside `AllocTraced` between reading and updating `pool.next` would corrupt the heap after `FlushThreadState`. The user's preferred mechanism is to skip poll emission per compilation unit for those units (about four, possibly also `WThread`); gating on `heapState.inCritical` is the alternative. (v14: the wasm32 library will be compiled by `m3llwasm`, so this policy and the audit gate (42) are decided together) |
| 36 | ✅ **`nthr_arch_reap32` on wasm32 waits in a loop on `ended`** — new and closed 2026-10-29 | A | Belt and braces: `while (ended == 0) wait32(&ended, 0, -1)` with an acquire load |
| 37 | **Unclaimed-thread reaper and slot-table growth** — new in v13 | A | Unjoined threads go on a low-priority "unclaimed" ring that is reaped as a GC extension (design of 2026-10-24); the slot table behind `Axis.slot` (`triple[…]`) needs growth. Neither is done |
| 38 | ✅ **The collector pins its own highest page** — accepted 2026-10-29 | C | Phase C. The collector stays unmodified; the pass rules account for it; optional confirmation by moving the flip loop into its own procedure. **v14:** reproduced in every ms8 run (the aligned hit page rises with the heap, and plateaus when the heap is capped); four of the six stays in the final run |
| 39 | ✅ **Extend `ms7`: embedded `REF` fields** — **done in v14 as `ms8`** | C | See Phase C, stage 2. The remainder of the old list moved to item 46 |
| 40 | **Diagnostics hygiene before the commit** — the user | C | Revert the per-hit trace in `RTCollector.m3`; keep the `WThread.GC` counter; keep the `ProcessStacks` header prints as a comment. Also replace the `ProcessStacks` TODO about llvm.gcroots with a comment pointing at the v14 decision. **(v15)** The ms9 lines (`GCKIND`, `PROMOTE`, `COPYFAIL`) were reverted by the user; the user has said `RTCollector.m3` is not being modified now. Commit the ms8 and ms9 harnesses (pending since v14) with this plan |
| 41 | **Collector behaviour under a bounded traced heap** — new in v14; **mechanism identified in v15** | C / wasm32 | Failure mode, trace, space bound and experiments are in Phase C, stage 3 ("Bounded heap"). In short: a capped traced heap runs out of pages while an incremental collection is in flight; the allocator's slow path (`CollectEnough` then `LongAlloc`) gives up instead of finishing the collection and retrying; the collector's own `NEW` in `InitStack` can fail too. The collector documents the bound (heap at least A x (2 + 2/gcRatio) pages incremental, A x (2 + 1/gcRatio) stop-and-copy: 4A and 3A at the default ratio). 20M traced was intermittent, 22M failed once, 32M passed 10 of 10, and 20M with `@M3noincremental` passed 10 of 10. **Action:** size `--max-memory` and the traced cap from the bound with the collector mode in force (49); measure A for real wasm32 programs. No corruption was seen in any bounded run. The v14 ms8 observation (6 MB: stays with no hit; 5 MB: out of memory) is consistent with this and was not re-run |
| 42 | **SSA-across-safepoint audit gate** — new in v14 | B1/L | `claude/audit.py` over the generated IR/bitcode; require **zero not-homed pairs**. Clean on ms8 (463 call sites). **Must be run on the `neocore` bitcode produced for wasm32 as soon as we can compile for that target**, on any library bitcode built by `m3llwasm`, and after any change to IR shape. **(v15)** Also run it on an **ms9 build**: it has open-array `NEW` (the first use of `ClassifyVar`), views, `VALUE` open-array copies, by-value aggregates and text, none of which ms8 had. Library Modula-3 (`RTAllocator`, `Thread`, `Text`, …) is unaudited; exceptions and nested procedures are uncovered |
| 43 | **Optimiser enablement criteria (Phase O)** — new in v14 | O | Not scheduled. Entry criteria in the Phase O section. Until then: `llc` -O0..-O3 only, no `opt` |
| 44 | **wasm32 collector smoke test** — new in v14 | wasm32 | The conservative scan with the real collector on wasm32: single thread under node, then multiple threads (the coordinator reading another thread's published `sp`/top), then WAMR (30, 31). The sandbox harness covered only one thread's own stack with a fake heap. Depends on registers 3, 8, 23. **(v15)** Use ms9 as the suite, stack-independent subjects first (`aggGlobTest`, the module-global arrays, `valMultiTest`), then the stack-dependent ones (`aggLocTest`, `aggValTest`, the interior views, the `VALUE` open-array cases) |
| 45 | ✅ **`-O0` spill-slot residue pins** — explained and accepted in v14 | C | Stale pointers in unnamed spill slots of the subject's own frame pin the last-iteration referents; absent at `llc` -O1+ (no spill slots). Remedy for harnesses: helper procedures (Phase C rule 8). An accepted pin class, like register 38 |
| 46 | **ms9: further harness extensions** — new in v14 (supersedes the remainder of 39); **mostly done in v15** | C | **Done on x86_64:** `REF ARRAY` and open arrays (depth 1 to 3, bytes and `REF`s), interior views, `VALUE` open-array copies, by-value records and fixed arrays holding `REF`s (local, global, `VALUE` parameter), text-heavy threaded smoke test (cases 1 to 8, Phase C stage 3). **Left:** the local-`REF` variants of cases 1, 2, 3 and 6 (one edit each), sizes 1 and 100 for case 2, a `regs[]` hit (try `llc -O1`), and the same suite on wasm32 (44). Add the audit and the harness gate to its checklist (done in the near-term sequence) |
| 47 | ✅ **`ClassifyVar`: a Scalar root must be a pointer-represented variable** — new and closed in v15 | B2 | `LLVM_WASM.m3`: `ClassifyVar(self, v)` wraps the pure `ClassifyTrace` and returns `None` for a Scalar result on a variable whose `type` is not `Type.Addr`; `AllocVar` calls it. Cause: `New.m3` `GenOpenArray` declares the 24-byte dope temporary of an open-array `NEW` with the `REF` UID, so it classified `Scalar` and `llvm.gcroot` was issued on a struct alloca (verifier error `%tmp.412`). `m3llhost` and the front end are untouched. Re-run the audit on a build with open-array `NEW` (42) |
| 48 | **Bounded-heap robustness options** — new in v15 | C / wasm32 | Not decisions. (a) The allocator's slow path could finish the in-flight collection (or force a full one) and retry once before raising `OutOfMemory`; it lives in `RTAllocator.m3` and needs only the collector's public entry (`RTCollector.Collect`), but the retry itself must be reasoned about against the heap lock and `SuspendOthers`. (b) The collector's own traced allocation in `InitStack` (state Two) could be made from a reserve or the untraced arena; that is a change to `RTCollector.m3`, which is frozen. (c) Do neither and size the cap from the bound (41). Decide when the wasm32 cap is chosen; (a) is the natural first candidate if programs will run close to their cap |
| 49 | **wasm32 collector mode: incremental, generational, or stop-and-copy?** — new in v15 | wasm32 / C | The mode sets the multiplier in the space bound (4A against 3A). Module `gc_flags` come from `Host.doIncGC` and `Host.doGenGC` (`cmd/m3fe/src/values/Module.m3`, around lines 1275 to 1283: 3 both, 2 incremental, 1 generational, otherwise absent); `RTLinker.AddUnitI` turns incremental or generational collection off, and finishes the current collection, if any linked module lacks the flag. Not yet checked: which flags the `m3llwasm` pipeline passes by default and what the user's wasm32 runs will use. Incremental collection is documented as VM-synchronised in the collector's header comment; whether it is meaningful without `mprotect` on wasm32 is a question to settle with 44 |
| 50 | **Open-array `NEW` dope temporary carries the `REF` UID** — observation, v15 | B2 / front end | `New.m3` `GenOpenArray`. Guarded in the back end by `ClassifyVar` (47). Changing the front end would change an AST both targets read; not worth it unless another consumer needs the temporary's real type. No action |

**Parked:** nested procedures on wasm32 (B1) — `nest` attribute unsupported; static
link is the hidden first parameter spilled to `__StoredStaticLink`, and its slot is
expected to be reworked then. **Parked (v14):** precise stack roots (13, 14, 17, 25b, 10, Phase D).

**Deferred:** `superType` sprint; `BITS N FOR T`; exception handling (Phase E); sysroot problem for `wasm32-unknown-wasi`;
`BuiltinTypes.KindUID` adoption.

---

## Commit Granularity Summary

| Phase | Granularity | Rationale |
|---|---|---|
| Baseline | N/A — already done | Existing, working code |
| A | Complete, tested; parking protocol revised in v11; exit/join/reap and context layout revised and verified in v12; v13: `nthr_lock`, the watch-transition rules and the heap-lock invariant recorded, and WTHREAD wired into `pkg/neocore`. Open: 28, 34, 37 | Four invariants plus the v11 drain rule, the v12 Mesa signal-under-lock rule and the v13 rules table govern everything downstream |
| B1 | Poll, gcroot frame scaffolding, thread-local chain, alignment and debug fixes: done, validated on x86_64. Loop-edge polls: done. Open: `Target.m3`, debug NIL element, attribute cleanup, upstream reports | The block structure and entry-block discipline are load-bearing; loop polls reuse `EmitSafepointCheck` |
| B2 | `m3t` chain + `ClassifyTrace` + `ClassifyVar` + composite metadata: done, verified (metadata dormant since v14). Parameter rooting: done, verified by IR inspection and the audit. Objects closed. Narrow items plus deferred scope (packed fields) and the parked opaque fix | Real `REF` roots are registered for parameters; the derived-copy rule is checked mechanically by the audit gate |
| C | Design captured; conservative pinning (stage 1) validated in v13; embedded `REF` fields (stage 2, ms8) validated in v14; arrays, views, copies, aggregates and text (stage 3, ms9) validated in v15; chain-walk pinning parked | Roots are conservative (Decision (v14)); the accepted pin classes are the collector's highest page (38), designed pins, `-O0` residue (45) and page-level pins of unidentified origin (stage 3, finding 6) |
| C harness (`ms7`, `ms8`, `ms9`) | Per extension | ms9 residue (46): local variants, a `regs[]` hit, then the same suite on wasm32; the pass rule accounts for every stay or records it as an accepted pin |
| D (D1–D4) | **Parked (v14)** | Preserved for the re-open conditions only |
| L | Two stages: (1) wasi-libc as is; (2) backfill the system calls WASI lacks | Independent of the collector work; guarded so x86_64 is unchanged; unblocks user-space programs on wasm32 and produces the library bitcode for the audit gate; the critical path |
| O (new in v14) | Not scheduled | Entry criteria must be met first |
| E | Per milestone | Follows Phase L; includes shadow-stack/unwind interaction and the personality question |

---

## Appendices (separate notes in the project)

- `claude/optimisation-and-visibility-analysis.md` — the wasm32 visibility harness (sources, results), the SSA-across-safepoint audit
  (method, controls, results on ms8 and on optimised IR), the `opt`/`llc` experiments, the gcroot cost measurement, the shadow-stack
  frame layout facts, the spill-slot analysis, the bounded-heap arithmetic, and notes on optimiser benefit.
- `claude/audit.py` — the audit script.
- `claude/dev-plan14.md` — the previous edition, kept for reference.
