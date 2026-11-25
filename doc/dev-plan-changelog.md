# Changelog: revision notes v10-v18, the v18 near-term sequence and the v18 commit-granularity table, verbatim and superseded

*Reflects plan v19, 2026-11-25. Text below is moved verbatim from dev-plan18.md (lines 1-89, 331-347, 2473-2491).*

## Plan v19 (2026-11-25)

The plan was restructured and split into notes (see the document map in `dev-plan19.md`); v18's text is kept verbatim below and in the phase notes.

- **Engine pivot.** Wasmer 7.0.1 (exnref build) is the primary engine, provisional until milestone M6 is proved. `ms10` and `ms13` run to exit 0 under Wasmer; WAMR results are kept in `wamr-record.md`.
- **Audit gate closed: 94 of 94.** `audit.py` was fixed twice: the by-value aggregate exemption (found on `ms9`) and per-edge phi liveness (the `RTLinker` pairs). Registers 62, 66, 67 closed; 49 and the sizing rule for 41 settled by `ms15` to `ms17`.
- **New tests.** `ms15` (uncaught exceptions in main and in a worker), `ms16` (nested procedures and procedure values, with a negative control), `ms17` (heap sizing, sweep and ceiling), recorded in `doc/memory-audits.md`.
- **Link memory ceiling.** `ms17` at a 32 MiB ceiling with 16 MiB live aborts cleanly with `NEW() was unable to allocate more memory`, exit 129 under Wasmer.
- **Register.** Rows 1 to 76 unchanged and sorted into open, parked and closed; 77 to 80 proposed.

<!-- v18 lines 1-89 -->
# Incremental Development Plan: wasm32 Threading, Safepoints, GC Integration, and the Core Library

**Plan v18 — checkpoint 2026-11-24**

**Scope:** CM3-derived Modula-3 compiler. The x86_64/Linux target, via the `m3llhost`
backend and the existing PTHREAD runtime module, is an **already-working baseline**.
This plan covers only the **new work required for the wasm32 target**, built through
the new `m3llwasm` backend and a new `WTHREAD` (`WThread`/`nthr`/`nsyn`) runtime
module, and (since v12) the work to bring the Modula-3 core library up on wasm32. Since v13
the WTHREAD runtime is also wired into m3neos as `pkg/neocore` (an `m3core` built on `WTHREAD`,
x86_64 for now, next to the PTHREAD-based `pkg/neosys`); that build is the vehicle on which
stop-the-world, pinning and the heap-tracing behaviour are tested under the real collector.
**(v16)** The wasm32 target now builds and runs: the core library compiles for `wasm32-wasip1-threads` and a first program has run under WAMR.
**(v17)** Exceptions now work on wasm32 (LLVM 22 sjlj lowering onto legacy wasm EH, WAMR 2.4.5 with a local thread patch), and the collector has run on wasm32 for the first time (slowly: see "Collector cost on wasm32").
**(v18)** `ms9` (twelve threads, arrays, views, copies, by-value aggregates and text) now runs on wasm32 under WAMR and passes in 112 of 112 runs, its IR passes the audit gate, and the collector's cost on wasm32 has been measured against two x86_64 builds (see "ms9 on wasm32 under WAMR (v18)", "Build flavours and the installed library (v18)" and "Collector cost on wasm32").

**Revision note (this version, v18):** v18 is the checkpoint after the **first proving session for garbage collection on wasm32** (2026-11-24, the same day as v17). `ms9` (twelve threads) now runs on wasm32 under WAMR, its IR passes the audit gate, and the collector's cost on wasm32 has been measured against two x86_64 builds. Nothing from v17 is dropped except where marked **superseded**. Two sections are new (**"ms9 on wasm32 under WAMR (v18)"** and **"Build flavours and the installed library (v18)"**, both after the collector-cost section), the collector-cost section's experiment list and the near-term sequence are rewritten, the register gains items **70 to 76** and updates 15, 30, 35, 41, 42, 44, 46, 52, 57, 60, 61 and 65, and working rules **18 to 20** are added.

- **`ms9` passes on wasm32 under WAMR (register 44, largely met).** Twelve subject threads, three cycles of two stages, an explicit collection after each advance: 112 of 112 runs complete (12 in the first log, 100 in the second), with no assertion, trap or hang, every join, and an identical traced footprint. Stack-held objects never moved (7 objects x 2 transitions x 100 runs = 1,400 transitions, all stays); 13 of the 100 runs show one or two single-transition stays of objects that normally move, always in the memory-retaining direction. The 100 runs ran while the user's machine was doing library compiles in the background, so scheduling was perturbed (spin counts per interval varied 1.27 times, against 1.13 in the earlier 12 runs) but the load was not controlled. Details, and what the runs do not cover, in "ms9 on wasm32 under WAMR (v18)" and register 70.
- **The one failure on the way was the harness, not the collector (rule 18).** A `<*ASSERT*>` in `Wait` (`next >= ms9.stage`) fired because `multiTest` spent its whole run in its first `checkMulti` (about 32 million byte compares per call under the interpreter) and fell more than one stage behind the driver's fixed `Thread.Pause(0.5D0)` timers. The fix (`corruptR` on row 0 only; the identity assertion kept for every row) removed it. Register 72.
- **WAMR's cluster thread limit.** `iwasm --max-threads=N`, default 4; `ms9` is run with `--max-threads=16`. Register 71.
- **The audit gate passes on the wasm32 `ms9` build (registers 42, 73).** Input: `llvm-dis` of the final, lowered bitcode (62 functions, 1,446 safepoint call sites). The stock `audit.py` reported 23 not-homed pairs, all one value: `%cp`, the pointer parameter of `Main__aggValProc` (a by-value aggregate: the callee works on the caller's `pop_struct` temporary, a stack `alloca`). `audit.py` was patched (a marked by-value aggregate parameter is exempt, with a cross-check of every direct call site; violations count against the gate) and reports `not homed 0  exempt 23  violations 0`. `loop_poll_check.py` passes. **Correction:** `audit.py` does not read `llvm.gcroot` (v17 said it did); its homing rule is a dominating store to an alloca or global through a GEP chain, so it works on lowered IR, and controls written in the lowered style confirmed it.
- **Collector cost: the first x86_64 comparison did not isolate the library, and that route is closed.** Timed `ms14` on three builds: default C backend with PTHREAD (Px86); a test program built through `m3llwasm` against a library built `THREAD=W` through the C backend (Wx86); and wasm32 (W32). Px86 and Wx86 agree (about 0.4 to 2.5 ms per collect); wasm32 is 221 to 351 times slower per collect and 79 to 86 times slower on an allocation-only loop. The agreement shows only that the WThread runtime and polls in the test program cost nothing at native speed. The library compiled through `m3llwasm` and `llc -O0`, and polls in library code, were **not** in the x86_64 build, so a statement made earlier in the session that they were "ruled out" is withdrawn. Building the library that way on x86_64 broke the installed tools (`m3llwasm` segfaulted), so the experiments continue on wasm32 only (registers 65, 74).
- **Build flavours (corrected description).** The defaults are the C backend (`m3C`) with PTHREAD and safepoints by `pthread_kill`; `-DM3_BACKEND=Llvm` is `m3llhost` with PTHREAD (bitcode, no cooperative safepoints); `-DM3_BACKEND=Wasm` is `m3llwasm` with WThread and cooperative safepoints, on x86_64 as well as under `-DTARGET=wasm32` (which forces it). An earlier description in this session of `Llvm` as "WThread with cooperative safepoints" was wrong. Only one `neocore` flavour can be installed per target at a time, and the installed tools link it dynamically.
- **Placeholders.** `SchedulerPosix`'s `IOWait`, `IOAlertWait` and `WaitProcess` are stubs that return errors, in `WThread.m3`, exported as `SchedulerPosix` (register 75); the x86_64 WThread build needed the interface.
- **Corrections to earlier statements (v18).** (1) "`audit.py` reads `llvm.gcroot`": wrong (above). (2) "`-DM3_BACKEND=Llvm` builds WThread with cooperative safepoints": wrong (above). (3) "`llc -O0` and polls are ruled out as the cause of the collector cost", said after the first x86_64 comparison: withdrawn the same day (above). (4) The 100-run machine was called unloaded: it was not (background compiles).
- **Working rules added (continuing the numbering).** 18: *a harness with fixed-time stages must size each subject's work per stage to the slowest engine it runs on, and the stage lag must be measured, not assumed.* 19: *a comparison between builds is valid only for the factors the build log shows were switched; confirm with `-commands` that every component (test program and library) went through the intended path before reading the numbers.* 20: *snapshot the installed tree (`cp -a /usr/local/m3neos`) before swapping a library flavour: the installed tools link `libneocore.so` dynamically, so a flavour they cannot use breaks the toolchain.*
- **Housekeeping state at this checkpoint (the user's).** To commit or sync (near-term step 1): the `ms9` `checkMulti` fix, the `SchedulerPosix` stubs in `WThread.m3`, the patched `test/src/n0/ms8/audit.py`, and the text of `doc/optimisation-visibility.md` section 2 (register 73). The v17 list (in the note below) was not re-confirmed in this session.

**Previous revision note (v17, condensed):** v17 closed the **second wasm32 sprint: exceptions** (2026-11-06 to 2026-11-24) and recorded the **move to LLVM 22** that made them possible; the full record is the section "Exceptions on wasm32 (v17)". Exceptions that reach a handler run on wasm32 under WAMR (`ms13`), a collection after a catch runs (`ms14`), and register 51 is closed. The route: keep the `setjmp`/`longjmp` frame scheme exactly as on x86_64 and let LLVM 22 lower it onto legacy wasm EH (`-wasm-enable-sjlj -wasm-use-legacy-eh=true`); no AST, M3CG or front-end change; M3C untouched. LLVM 22.1.2 with the wasi-sdk 33 sysroot (`/opt/wasi-sysroot-33.0`); new back-end packages `llvm22api`, `llvm22host`, `llvm22wasm` (register 63). WAMR 2.4.5 plus a local patch (branch `WAMR-2.4.5-E`) that keeps the in-flight exception marker per thread instead of broadcasting it to the cluster (register 30). The FINALLY-handler convention reverted to the original (the v16 `FinallyProc` change is superseded; one `RTExFrame.m3` serves every back end). Two shadow-stack problems were fixed: a call-site `nounwind` on M3 calls (the lowering's `invoke`s cannot be selected on wasm), and `m3llwasm` running `shadow-stack-gc-lowering` itself before `llc` (the sjlj pass otherwise leaves calls the lowering cannot handle). The collector first ran on wasm32 in `ms14` and was found to cost 230 to 460 ms per collection (register 65). The collector never reads `stack_chain` (register 68). Corrections to earlier statements in this plan's own history, each caught by an experiment: I predicted that no plain calls would remain in a function with both setjmp and a gcroot (wrong: the sjlj pass inserts its own); that `ms14` would probably fail for want of a chain-head restore (wrong: nothing walks the chain); and I described `ms12` as a `TRY`/`EXCEPT` test (it is a quake script exercising the compiler's own exception).

**Working rules added in v17 (continuing the numbering of Phase C's harness rules).** 14: *a change is not "done" until the patch file has been delivered* (a description of a change that the user cannot see is not a change). 15: *a test that is silent on success needs a negative control*: break one assertion once, and see it fail with a nonzero status, before trusting the pass. 16: *each LLVM backend option passed through clang needs its own `-mllvm`; `-mllvm` flags are reported "unused" at the link step and that is harmless.* 17: *temporary diagnostics go in patch files that are reverted before a checkpoint* (as in v13): three were used in the exceptions sprint and none is committed.

**Housekeeping state at the v17 checkpoint (not re-confirmed in v18).** Committed by the user: tags `beta.22` (WAMR-patch regression test `ms11`) and `beta.25` (the FINALLY convention, the LLVM-version refactor of the back-end packages, and `ms12`). **Uncommitted, to commit** (register 61): `llvm22wasm` (call-site `nounwind`, `setjmp` as a `returns_twice` name, pre-lowering), `llvm22api` (`LLVMPasses`, `LLVMPassesRaw`, the `m3makefile` lines), `llvm18wasm` (the `setjmp` name only), `Target.m3`, `CsetjmpC.c`, `WasiCstd.c`, and the tests `ms13` and `ms14`. To revert, not commit: the temporary debug edits in `RTCollector.m3` and `WThread.m3` (stack-range prints, per-state and per-step timing).

**Previous revision note (v16, condensed):** v16 closed the **first wasm32 sprint**. `pkg/neocore` was compiled, archived, installed and linked for
`wasm32-wasip1-threads`, and `ms10` (a hello-world) ran under WAMR 2.4.5, exercising the C entry, `nref` (three arenas), `RTLinker.InitRuntime`,
`WThread.InitialThread`, the main body on a spawned thread, and an orderly exit. Ten problems were found and fixed on the way (the trap-and-fix
table in the bring-up record). Decisions: a dedicated wasm32 `m3core.h` in `pkg/neocore/src/unix/WASI`, selected by the build (and the
placeholders for what wasi-libc lacks in `WasiCstd.c` and `WasiSys.c`: the `_setjmp`/`_longjmp` stubs are **gone in v17**); `MxGen` generates the
wasm32 entry point (two-parameter `main`) by `Target.System_name`; `nref` allocates in 64 KiB units on wasm32; build configuration in `etc/wasm32`
and a hook in `etc/Unix.common`; the `nest` attribute is not used on wasm32 and the static link is an explicit leading `i8*` (the accompanying
`FinallyProc` arity change is **superseded in v17**). Registers 51 to 62 were new.

**Previous revision note (v15, condensed):** v15 closed Phase C stage 3 (`ms9`) on x86_64: fixed and open arrays (depth 1 to 3), interior
views, `VALUE` open-array copies, by-value aggregates two levels deep and a twelve-thread text smoke test all ran under the unmodified
collector and WTHREAD stop-the-world with every content assertion intact (case matrix in Phase C, stage 3); the `ClassifyVar` fix
(register 47) stopped `llvm.gcroot` being issued on a struct alloca (the open-array `NEW` dope temporary); the bounded-heap failure
(register 41) was traced to an allocator that gives up while an incremental collection is in flight, against a documented space bound of
about 4A pages incremental and 3A stop-and-copy (20M traced was intermittent, 32M passed 10 of 10, 20M with `@M3noincremental` passed 10
of 10); harness rules 9 to 13 were added; registers 48 to 50 were new.

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


<!-- v18 lines 331-347 -->
## Near-term sequence (rewritten in v18)

In order. Each step is a prerequisite for, or de-risks, the next. Since v17: the multi-thread collection test (v17 step 2, register 44) is done on wasm32 for `ms9`; the audit gate (v17 step 4) is done for `ms9`'s program module; the collector-cost work (v17 step 3) continues on wasm32 only, because the x86_64 library route is closed.

1. **Housekeeping (the user; small).** (a) The v17 list is still the list: revert the temporary diagnostics in `RTCollector.m3` and `WThread.m3`; commit the keepers (`llvm22api`, `llvm22wasm`, `llvm18wasm` setjmp name, `Target.m3`, `CsetjmpC.c`, `WasiCstd.c`, `ms13`, `ms14` quiet version); remaining v16 items under register 61 (`NTHR_TRACE` 52, `RTIO` flush at exit 53, weak stubs 57, `hand.o`/`Uconstants.o` 56, `GenerateCGEntry` 58). (b) New in v18: commit the `ms9` `checkMulti` fix, the `SchedulerPosix` stubs in `WThread.m3` (register 75) and the patched `test/src/n0/ms8/audit.py`; replace the project copy `claude/audit.py`; update `doc/optimisation-visibility.md` section 2 (usage and TOTAL line, gate rule; register 73). (c) Decide how `ms9` is to log the collection counter on wasm32: the `WThread` import and the `+GC` `loque.write` after `Collect` are commented out so that the PTHREAD x86_64 build compiles.
2. **Collector cost on wasm32 (register 65), wasm32 only.** In order, one variable at a time: a Release `iwasm`; the `nthr_park` symbol check on `libneocore.a`; `llc -O2` for the library; loop counts in `GrayBetween` and `CleanBetween`; the profiling build; optionally the x86_64 `Llvm` flavour, last, with a snapshot of `/usr/local/m3neos` first (rule 20). The list, with commands, is in the collector-cost section. A decision, not a patch, comes first if `RTCollector.m3` would have to differ.
3. **`ms9` on wasm32, what remains (register 70).** Optional: about 20 runs pinned to one core (`taskset -c 0`) as a controlled perturbation; record each run's exit status (`timeout 120`); log the collection counter on wasm32; the local-`REF` variants and a `regs[]` hit (register 46).
4. **Audit gate on the remaining wasm32 bitcode (register 42):** the `neocore` library bitcode, `ms10`, `ms13`, `ms14`. `ms9`'s program module is clean. The audit cannot see the calls that `llc`'s sjlj pass adds; that matters for `ms13` and `ms14`.
5. **The worker-thread uncaught-exception check (register 66)** and the `Target.Jumpbuf_size` check (register 67): two small tests.
6. **Nested-procedure test (register 62)** and, as convenient, the other small items (34, 35, 37, 40).
7. **`neolib` (libm3) for wasm32 (register 59)**, only as far as the next test needs.
8. **`llvm18wasm` parity or retirement (register 64):** decide whether LLVM 18 stays a supported back end; if it does, port the call-site `nounwind` and the pre-lowering.
9. **Bounded heap (registers 41, 48, 49)**: decide the wasm32 collector mode and size `--max-memory` from the documented bound; `ms9`'s unbounded wasm32 footprint is now measured (register 41), and the collector cost makes the mode decision (incremental or not) more pressing.
10. **Phase L stage 2 (registers 23, 57, 75)**, with the WAMR host-side design, then Process and networking.
11. **Phase O (optimiser enablement)** only when measurement says it is worth it and its entry criteria (now including the `setjmp` rule) can be met.
12. **`ms9` residue on x86_64 (register 46), as convenient.**


<!-- v18 lines 2473-2491 -->
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
| L | Two stages: (1) wasi-libc as is; (2) backfill the system calls WASI lacks | Independent of the collector work; guarded so x86_64 is unchanged; unblocks user-space programs on wasm32 and produces the library bitcode for the audit gate; the critical path **(v16)** Stage 1 is done for `neocore` (builds, ships, runs hello-world); `neolib` and the stage-2 implementations are open; commit by area (register 61). |
| O (new in v14) | Not scheduled | Entry criteria must be met first |
| E | **(v17)** Mechanism done: exceptions run on wasm32 (`ms13`, `ms14`); commit by area (back ends and binding; `Target.m3`, `CsetjmpC.c`, `WasiCstd.c`; tests); remaining items 64 to 68 are small | Shadow-stack/unwind interaction resolved by call-site `nounwind` and the pre-lowering; the personality question closed in practice |
| Collector on wasm32 (new in v17) | Diagnosis done; three-way comparison done (v18); wasm32-only experiments pending (register 65) | Works, slowly; do not tune for the classic interpreter before the engine tier is known |
| `ms9` on wasm32 (new in v18) | Runs and passes (112 of 112); commit the `checkMulti` fix, the `SchedulerPosix` stubs (75) and the patched `audit.py` (73) | The harness is sized to the engine (rule 18); the audit gate passes on its IR |

---


