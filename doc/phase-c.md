# Phase C, the v14 roots decision, constraints and audit results

*Reflects plan v19, 2026-11-25. Text below is moved verbatim from dev-plan18.md (lines 186-330, 1745-2211).*

<!-- v18 lines 186-330 -->
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
| Library Modula-3 (`m3core`, `libm3`) compiled by `m3llwasm` | Same rule as user code: `llc` -O0..-O3, no `opt`. | | **Unaudited** (no wasm32 library IR yet). The audit gate applies before the first wasm32 run (register 42). **(v18)** ms9's program module is audited on wasm32 and clean; the library units still are not. |
| Changes to `m3llwasm` or the front end that alter IR shape (for example keeping expression values in SSA instead of temporaries) | Allowed after the gate. | Landing without it. | Any such change must re-run the audit and the harness. |

**Rules that follow**

1. **Audit gate.** `audit.py` must report **zero not-homed pairs** on every `.ll` or bitcode that will run under the collector
   (project doc `claude/audit.py`). It must be run on the **`neocore` bitcode produced for wasm32 as soon as we can compile
   for that target** (registers 3, 8, 23), and again after any `m3llwasm`/front-end change that alters IR shape. A nonzero
   result is a correctness finding, not a warning. **(v15)** The `ClassifyVar` change alters which variables receive a gcroot, so
   the audit is to be re-run on a build that contains open-array `NEW` (the ms9 build) before the wasm32 audit. **(v18)** The gate is now "zero not-homed pairs and zero violations"; the by-value aggregate exemption is described in register 73; ms9's wasm32 build passes.
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

- **(v18) wasm32 `ms9` build:** `audit.py` on the `llvm-dis` output of the final, lowered bitcode (module `Main.mb`, triple `wasm32-wasi-threads`): 62 functions, 1,446 safepoint call sites, 23 live-across pairs, all the by-value aggregate parameter `%cp` of `Main__aggValProc`; with the patched script, `not homed 0  exempt 23  violations 0`. `loop_poll_check.py` passes (every CFG cycle passes a poll gadget). Lowered IR is a valid input: the audit's homing rule does not depend on `llvm.gcroot`, and four lowered-style controls behaved as the unlowered ones had. Library units remain unaudited.

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
| 🔶 **Next (v16)** | Housekeeping and commit; the **audit gate on `neocore` wasm32 bitcode** (42); a **first wasm32 collector test** (44); the **exceptions decision** (51); `neolib` for wasm32; then ms9 as the regression suite; then the bounded-heap work (41, 48, 49). See "Near-term sequence". |
| ✅ **Validated (v18)** | **`ms9` on wasm32 under WAMR**: twelve threads, 112 of 112 runs complete with no assertion, trap or hang; stack-held objects never moved. See "ms9 on wasm32 under WAMR (v18)" (registers 44, 70). |
| ✅ **Passes (v18)** | **Audit gate on the wasm32 `ms9` build**, with the by-value aggregate exemption (registers 42, 73); `loop_poll_check.py` passes. Library bitcode, `ms10`, `ms13`, `ms14` are still unaudited. |
| 🔶 **Next (v18)** | Collector cost on wasm32, wasm32-only experiments in order (register 65); housekeeping (near-term step 1); the small tests 66, 67, 62. |
| ✅ **Done (v16)** | **The first wasm32 executable.** `ms10` (hello-world) built with `m3neos -DTARGET=wasm32`, run with `iwasm`; prints its line once `RTIO.Flush` is called. First run of generated code, `nthr`/`nsyn` and `nref` on wasm32 and of WTHREAD under WAMR. See "wasm32 bring-up record (v16)". |
| ✅ **Decided and done (v16)** | **Dedicated wasm32 `m3core.h` in `unix/WASI`**, with the stage-2 placeholder C sources (`WasiCstd.c`, `WasiSys.c`); one `m3core.h` registered per target; x86_64 header untouched. |
| ✅ **Done (v16)** | **`nref` claims memory from wasi-libc in 64 KiB units** (`sbrk` granularity). |
| ✅ **Done (v16)** | **`MxGen` entry generation for wasm32** (two-parameter `main`, `envp` from `__wasilibc_get_environ`), by target at generation time; the C entry is run-tested, `GenerateCGEntry` is implemented and untried. |
| ✅ **Done (v16)** | **Nested procedures on wasm32** (no `nest` attribute; explicit static link; `FinallyProc`/`CallProc`). Builds and runs; no dedicated test yet (register 62). |
| ✅ **Done (v16)** | **wasm32 build configuration**: static relocation, atomics features on `llc`, no shared object, wasm link line (reference section below). |
| 🔶 Open (mechanism identified, v15) | **Collector behaviour under a bounded traced heap** (register 41): the failure mode and the documented space bound are known; the cap must be chosen from the bound; two robustness gaps are options for later (48). Matters because `--max-memory` is mandatory on wasm32. |
| 🔶 **In progress (v16)** | **Phase L — core library on wasm32**: stage 1 done for `neocore` (builds, ships, links, runs); `neolib` for wasm32 open; stage 2 started with the placeholders in `unix/WASI` (registers 23, 57). |
| 🔶 Open (wasm32 enablement) | Debug-info NIL element (register 5); remaining wasm32 attribute cleanup (8, no longer blocking); the `Target.m3` generic wasm32 system (3) works in practice, confirm the `phb.ast` check. (`LLVMVerifyModule` is done; the target triple is `wasm32-wasi-threads`.) |
| 🔶 Open (upstream) | Two LLVM bugs to report (reproducers ready); WAMR issues to report (register 30). |
| 🅿️ Parked by decision (v14) | **Precise stack roots**: chain-walk pinning (25b), `WalkStack`, aggregate root-slot addressing (13), `type_map` versus `gc_map` for stack walkers (9), Phase D (D1–D4). Re-open conditions in "Decision (v14)". |
| 🅿️ Parked by decision | Opaque-type `traced` derivation in `declare_opaque` (register 12 — reminder carried). |
| 🔲 Future, not scheduled (v14) | **Phase O — optimiser enablement.** Entry criteria in its section. |
| ✅ Closed (2026-10-29) | Startup ordering for the default thread (register 22). |
| 🔲 Deferred, own sprint | `InitUids`'s `superType` fields (DWARF-correctness only). |
| 🔲 Deferred, scope | `BITS N FOR T` packed fields; exception handling (Phase E; its first piece, `setjmp`/`longjmp` on wasm32, is register 51). (Fixed and open arrays, including the open-array VALUE parameter copy, are no longer deferred: exercised by ms9 in v15.) |
| 🔲 Future note | `BuiltinTypes.KindUID` — backend should consume the front end's computed builtin TypeUIDs instead of hard-coded `UID_*` constants. |

---


<!-- v18 lines 1745-2211 -->
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
the heap type maps and the stack scan together cover arrays, views, copies and by-value aggregates. What remains for roots is the wasm32 confirmation (registers 42, 44). **(v18)** Made for `ms9`: it runs on wasm32 under WAMR (112 of 112 runs), its IR passes the audit gate, and stack-held objects stayed pinned in all 1,400 observed transitions; see "ms9 on wasm32 under WAMR (v18)". The local-`REF` variants, a `regs[]` hit and the library bitcode remain.

---


