**Parked (v17):** the chain-head restoration (68) with Phase D. **Parked:** none of the v15 parked items changed; nested procedures on wasm32 were unparked in v16 (B1). **Parked (v14):** precise stack roots (13, 14, 17, 25b, 10, Phase D).
 
**Deferred:** `superType` sprint; `BITS N FOR T`; sysroot problem for `wasm32-unknown-wasi`;
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
| L | Two stages: (1) wasi-libc as is; (2) backfill the system calls WASI lacks | Independent of the collector work; guarded so x86_64 is unchanged; unblocks user-space programs on wasm32 and produces the library bitcode for the audit gate; the critical path **(v16)** Stage 1 is done for `neocore` (builds, ships, runs hello-world); `neolib` and the stage-2 implementations are open; commit by area (register 61). |
| O (new in v14) | Not scheduled | Entry criteria must be met first |
| E | **(v17)** Mechanism done: exceptions run on wasm32 (`ms13`, `ms14`); commit by area (back ends and binding; `Target.m3`, `CsetjmpC.c`, `WasiCstd.c`; tests); remaining items 64 to 68 are small | Shadow-stack/unwind interaction resolved by call-site `nounwind` and the pre-lowering; the personality question closed in practice |
| Collector on wasm32 (new in v17) | Diagnosis done; three-way comparison done (v18); wasm32-only experiments pending (register 65) | Works, slowly; do not tune for the classic interpreter before the engine tier is known |
| `ms9` on wasm32 (new in v18) | Runs and passes (112 of 112); commit the `checkMulti` fix, the `SchedulerPosix` stubs (75) and the patched `audit.py` (73) | The harness is sized to the engine (rule 18); the audit gate passes on its IR |
 
---
 
## Appendices (separate notes in the project)
 
- `claude/optimisation-and-visibility-analysis.md` — the wasm32 visibility harness (sources, results), the SSA-across-safepoint audit
  (method, controls, results on ms8 and on optimised IR), the `opt`/`llc` experiments, the gcroot cost measurement, the shadow-stack
  frame layout facts, the spill-slot analysis, the bounded-heap arithmetic, and notes on optimiser benefit.
- `claude/audit.py` — the audit script. **(v18)** The patched version (by-value aggregate exemption, violation check, parameter parsing; register 73) replaces the project copy at this checkpoint; the repo copy is `test/src/n0/ms8/audit.py`.
- `claude/dev-plan14.md`, `dev-plan15.md` — earlier editions, kept for reference (v16 is not in the project; v17 is in the project and in the repo as `doc/dev-plan17.md`; this v18 carries it forward).
- `claude/wamr-eh-thread-fix.md` — **(v17)** the WAMR 2.4.5 exceptions-in-threads diagnosis, the local patch, and test results.
- `claude/llvm22-migration-checklist.md` — **(v17)** the LLVM 22 gates, the toolchain smoke test and the m3neos-side checklist (the status section dates from 2026-11-12; items there are now mostly done: see "Exceptions on wasm32").
- `claude/wamr-build-notes.md` — the WAMR build-side findings. **(v16)** It does not yet record the diagnostic build options (Debug build, call-stack dump, name section, classic interpreter) or the profiling flags that were then switched off, nor the stale-cache rule for the `-C` file; worth adding.
 