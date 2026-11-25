# ms9 on wasm32 under WAMR

*Reflects plan v19, 2026-11-25. Text below is moved verbatim from dev-plan18.md (lines 564-628).*

<!-- v18 lines 564-628 -->
## ms9 on wasm32 under WAMR (v18)

**Status: passes. 112 of 112 runs complete (12 + 100), with no assertion, trap or hang; the audit gate passes on its IR.** Register 44 is largely met; register 70 lists what the runs do not cover.

### Setup and how the runs were made

- **Source:** `test/src/n0/ms9/src/Main.m3` and `Loque.m3`; twelve subject threads (`smokeTest` four times, `intTest`, `pageTest`, `aggLocTest`, `aggGlobTest`, `aggValTest`, `valTest`, `multiTest`, `valMultiTest`), the driver (`mainMS9`) and the logger (`Loque`). The driver runs three cycles of two stages (`pause`, `edge`, `pauseTwo`, `edgeTwo`, `pauseTre`, `edgeTre`, `finish`), each stage a `Thread.Pause(0.5D0)`, an advance, a second pause and an explicit `RTCollector.Collect()`.
- **Command:** `m3neos -DTARGET=wasm32` in the test directory, then `iwasm --max-threads=16 wasm32/ms9` (register 71). The `WThread` import and the `+GC` `loque.write` after `Collect` are commented out in the user's tree, because the default x86_64 build has no `WThread`; the wasm32 runs therefore do not log the collection counter.
- **Logs:** the first holds 12 runs; the second (`ms9_io.log`) holds 100 runs (ten outer by ten inner), each headed `outer NN inner N`, and no exit statuses.

### The first failure was the harness (register 72, rule 18)

`Wait` asserts `next >= ms9.stage`: a subject may lag the driver by one stage but not two. On wasm32 the assertion fired. The cause was `multiTest`'s `checkMulti`: for each of 100 rows it called `corruptR` on the elements `z < 8`, and `corruptR` scans 40,000 bytes, about 32 million byte compares per call, which the interpreter did not finish before the driver's fixed 0.5 s timers had advanced two stages. The fix, applied by the user:

```modula3
<* ASSERT impMulti[y][z] = impMulti[0][z] *>
IF y = 0 THEN
  <* ASSERT NOT corruptR(impMulti[0][z], (kp*16 + kp) MOD 256) *>
END;
```

The identity assertion still runs for every row (harness rule 12); the content scan runs on row 0. The next run passed with every stage logged, as the diagnosis predicted. Afterwards, ordering the log lines shows `multiTest` logging each stage before the driver announced the next one in all 600 stage checks (100 runs by six stages): lag 0. That is log order, a coarse measure.

### Results

**Completion.** Every run has 12 subject starts, 12 joins, one `mainMS9 END`, `Loque end`, the three heap-statistics lines and the `proc_exit` call-stack dump; 301 to 305 lines each (the spread is interleaved `printf`s); no `ASSERT`, trap, `unreachable` or out-of-bounds text anywhere. Eleven subjects print an `exiting` line, in every run.

**Footprint.** Virtual 65,536 bytes claimed (44,856 free); Traced 14,614,528 claimed (1,179,200 free, or 1,179,244 in some runs) in all 100 runs; Untraced takes one of two values, 1,245,184 bytes (73 runs) or 1,114,112 (27 runs), 131,072 bytes (two pages) apart. The earlier 12-run log showed the same two values. Cause unidentified (register 70).

**Movement.** `S` stayed, `M` moved, over the two transitions of each object. The canonical pattern, 87 of 100 runs:

| Object | Transitions | Object | Transitions |
|---|---|---|---|
| `aggGlob` `node`, `leaf`, `next` | M M | `oneMulti` | M M |
| `aggLoc` `node`, `leaf` | S S | `twoMulti` | S S |
| `aggLoc` `next` | M M | `impMulti` | S S |
| `aggVal` `node`, `leaf` | S S | `triMulti` | M M |
| `aggVal` `next` | M M | `impElem` | M M |
| `tail` (the `VAR` view of `valTest`) | S S | | |

Against the x86_64 run read in this session the pattern is the same except `twoMulti`, which stays on wasm32. The v15 table in Phase C, stage 3 (an earlier configuration) differs in `twoMulti` and in `impElem`'s first transition; finding 6 there (stays are layout-determined) applies. The `twoMulti` stay is explained, as an inference from the addresses and not from a trace, by its sharing a page with the pinned `impMulti`.

The other 13 runs differ in one or two transitions, always an object that normally moves staying put:

| Deviation | Runs |
|---|---|
| `aggVal` `next`, first transition stays | 4 |
| `aggLoc` `next` and `aggVal` `next`, both first transition | 3 |
| `oneMulti`, first transition | 2 |
| `aggLoc` `next`, second transition | 2 |
| `aggGlob` `next`, second transition | 2 |

No object that the canonical pattern pins ever moved: 7 objects x 2 transitions x 100 runs = 1,400 transitions, all stays. A false stay is a conservative stack word retaining a page, the safe direction; a stack-held object moving would be a real bug. The two `next` fields flipping together in three runs suggests that they share a page and a transient stack word pins it (an inference). The earlier 12 runs showed the same kind of deviation in 4 of 12.

**Statistics and perturbation.** Zero failures in 112 runs bounds the failure rate below about 2.7% at 95% (the rule of three). The 100 runs were made while the machine was doing library compiles in the background. The spin count of the poll-bearing loop in `intTest`, per 0.5 s interval, is a proxy for CPU received: in the 12 runs it ranged 1,547,980 to 1,752,551 (spread 1.13 times, coefficient of variation 3.9%); in the 100 runs 1,479,348 to 1,875,551 (1.27 times, 4.9%), with the medians of the ten blocks within about 7% of each other. So the load added some scheduling jitter and never starved the process, which makes it a modest extra and not a stress test. A controlled perturbation (everything on one core) was not run.

### Audit and loop-poll check on the wasm32 build

Input: `llvm-dis` of the final bitcode, which is already shadow-stack-lowered (module `Main.mb`, 28,443 lines): triple `wasm32-wasi-threads`; datalayout `e-m:e-p:32:32-p10:8:8-p20:8:8-i64:64-i128:128-n32:64-S128-ni:1:10:20` (the LLVM 22 form, with `i128:128`); 62 functions, 50 with `gc "shadow-stack"`, 164 `nthr_park` poll calls, no `llvm.gcroot` calls (lowered), 359 `ptrtoint` to `i32` and none to `i64`, the thread-local `@llvm_gc_root_chain` kept alive by `@llvm.compiler.used`, and call-site `nounwind` on every non-intrinsic call.

- **`loop_poll_check.py`:** passes.
- **`audit.py` (stock):** 1,446 safepoint call sites, 23 live-across pairs, all unhomed, all `%cp` of `Main__aggValProc`: a by-value aggregate parameter (`AggArr`, 36 bytes on wasm32). The one call site, in `aggValTest`, passes `%tmp.693`, a 36-byte `alloca` filled by a `memcpy` from a global, so `%cp` is a stack address and not a heap reference; the references inside the aggregate sit in the caller's frame, which the scan covers. The movement results agree (the `aggVal` `node` and `leaf` stay, `next` moves).
- **`audit.py` (patched, register 73):** `not homed 0  exempt 23  violations 0`.
- **Observation (register 15):** that temporary is `align 32` while the other `%struct.4` allocas are `align 4`, which looks like a leftover of the whole-size alignment bug (B1.6); harmless on wasm32.


