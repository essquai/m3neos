# Collector cost on wasm32

*Reflects plan v19, 2026-11-25. Text below is moved verbatim from dev-plan18.md (lines 472-563).*

<!-- v18 lines 472-563 -->
## Collector cost on wasm32 (v17 diagnosis)

**Status: diagnosed to the step; cause of the per-step cost not yet confirmed; nothing in the collector was changed (register 65). (v18) Measured against two x86_64 builds, which separated the interpreter from the rest only in part; the experiments below were reordered and are all wasm32-only.** The
collector is unmodified; the diagnostic edits used to find this (three patches against `WThread.m3` and `RTCollector.m3`) are not committed.

### What was found

- **Correctness first.** `ms14` forces collections on wasm32 under WAMR with two threads (the collecting thread, `tid 24576`, and the default thread,
  `tid 1`, parked in `nthr_vigil`), and every assertion holds. Both threads' stacks were handed to the collector (the stack ranges are 1,280 bytes
  for the first and 176 bytes for the second), the stop-the-world took about 60 microseconds, and the list built before a catch survived five passes
  of two collections each. This is the first run of the collector, `ProcessStacks` and `SuspendOthers`/`ResumeOthers` on wasm32, and it partly
  meets register 44 (single thread allocating, one other thread parked; the multi-thread stress is still to do).
- **Cost.** One pass of `ms14` takes about 0.91 s with collection and 0.107 s with `@M3nogc` (`ms13`, no collection, 0.18 s). Per explicit
  `Collect`: 230 to 460 ms on wasm32 under the classic interpreter; 0.4 to 1.1 ms on x86_64 (a ratio of 400 to 1000). The 4,000 small allocations
  of the churn loop cost 32 ms and triggered **no** automatic collection. The first `NEW` of the program triggers one (about 124 ms: the 117 ms
  "cold start" of the first allocation).
- **Where it goes.** All of it is in collector state Zero (`CollectSomeInStateZero`); states One to Five together take about 150 microseconds per
  cycle. Inside state Zero (microseconds, in the order of the steps):

| Cycle | suspend | flip | **stacks** | promote | **clean** | globals | resume | state Zero |
|---|---|---|---|---|---|---|---|---|
| 1 (automatic, first `NEW`) | 59 | 26 | 60,185 | 14 | 58,529 | 4,648 | 21 | 123,861 |
| 2 (`Collect` #1, pass 1) | 57 | 27 | 120,531 | 16 | 113,669 | 3,954 | 22 | 238,665 |
| 3 (`Collect` #2, pass 1) | 59 | 29 | 164,080 | 16 | 275,039 | 3,996 | 23 | 443,626 |
| 4 (`Collect` #1, pass 2) | 123 | 55 | 163,246 | 15 | 269,272 | 3,698 | 22 | 436,831 |
| 5 (`Collect` #2, pass 2) | 60 | 37 | 154,795 | 24 | 266,163 | 3,710 | 22 | 425,199 |

  "stacks" is `RTThread.ProcessStacks (NoteStackLocations)`; "clean" is everything between the promote loop and `WalkGlobals`, chiefly the loop
  that calls `CleanPage` on the pages pinned by the stack (it also contains `NEW (Mover)`).

### Why those two steps (read from the code; the per-step rate is a hypothesis)

- `NoteStackLocations` treats every stack word as a possible pointer; a word that lands on a heap page in the previous space **pins the whole 64 KiB
  page** (`PromotePage`, reason `AmbiguousImpure` for an impure page), and that calls `GrayBetween` over **every object slot of the page**. The clean
  loop then calls `CleanPage` on the same pages, which runs `CleanBetween` over the page again, calling `RTHeapMap.WalkRef` on each gray object.
- So the cost is not proportional to the stack size, to the live data or to the number of collections; it is proportional to **the number of heap
  pages that stack words point into**, each walked at least twice. The figures agree: about 118 ms for one pinned page (cycle 1), 233 ms for two
  (cycle 2), then a plateau near 440 ms, which would be the in-use pages all pinned. That is roughly 59 ms per page-walk, whatever the page holds.
- **Hypothesis, not confirmed:** the walk steps through the unused tail of the page in 4-byte steps (about 16,000 per page, at about 3.6
  microseconds a step in this configuration). It needs a count of loop iterations per `GrayBetween` call to confirm or reject.
- The same algorithm costs about 1 ms on x86_64, so the ratio comes from how the code runs: the classic interpreter of this WAMR build (no JIT or AOT
  tier has been checked), the library compiled at `llc -O0` through `m3llwasm`, a safepoint poll on loop edges (register 35: the collector units
  are not supposed to poll), and `<*ASSERT*>` checks inside these loops. None of these has been measured separately.
- **What was ruled out:** thread suspension and resume (60 and 22 microseconds), the page flip and promote loops (30 and 15), `WalkGlobals` (a steady
  4 ms), stack size (tiny), the number of automatic collections (none during the churn), and `@M3heapstats` (it printed nothing extra in this build).

### What the three-way comparison showed (v18)

**The three builds** (timed `ms14`, `test/src/n0/ms14/src/Main_timed.m3`; the checked-in `Main.m3` was identical to it at the time; one run each; microseconds as printed):

- **Px86:** all defaults: the C backend (`m3C`), PTHREAD, library and test program.
- **Wx86:** the test program built with `-DM3_BACKEND=Wasm` (`m3llwasm -b -g -t x86_64`, then `llc -frame-pointer=all -mtriple=x86_64 --dwarf-directory=0 -filetype=obj -relocation-model=pic -O0`, so with polls); the library `neocore` built with `THREAD=W` **but through the C backend** (no `m3llwasm`, no polls in library code). The collector in Wx86 is therefore the same C-compiled code as in Px86.
- **W32:** wasm32; WThread; the library through `m3llwasm` and `llc -O0`; the classic interpreter of a Debug `iwasm`.

| µs | Px86 | Wx86 | W32 | W32 ÷ Wx86 |
|---|---|---|---|---|
| `collect#1`, pass 1 | 367 | 891 | 245,683 | 276 |
| `collect#2`, pass 1 | 2,502 | 2,325 | 513,207 | 221 |
| `collect#1`, pass 2 | 1,528 | 1,507 | 485,249 | 322 |
| `collect#2`, pass 2 | 1,229 | 1,385 | 485,983 | 351 |
| `churn`, pass 1 / pass 2 | 1,346 / 346 | 431 / 455 | 36,874 / 35,814 | 86 / 79 |
| `down+catch+scrub`, pass 1 / pass 2 | 20 / 38 | 25 / 24 | 1,336 / 3,777 | 53 / 157 |
| `make50`, pass 1 | 5 | 620 | 126,328 | 204 |

**Reading it.**

1. **Wx86 equals Px86, and that proves less than it looks.** The collects agree within about 15% in pass 2 (and `churn` in pass 1 differs by 3 times); the first collect of pass 1 differs by 2.4 times; all within the run-to-run noise of single x86 runs. It shows that the WThread runtime (`nthr`, `nsyn`, the cooperative stop-the-world) and polls in the test program add nothing visible at native speed. It says **nothing** about the library compiled through `m3llwasm` and `llc -O0`, or about polls in library code, because Wx86 had neither. A statement made earlier in the session that these were "ruled out" is **withdrawn**. Native speed also hides what polls cost: on x86 an extra load and a well-predicted branch are nearly free, while an interpreter pays about the same for every instruction, so the share of the polls has to be measured on wasm32.
2. **Plain interpreted code is already slow.** The allocation-only `churn` loop is 79 to 86 times slower on wasm32; the collects are 221 to 351 times slower. So the engine (with `-O0` and polls, not separated) accounts for roughly 80 times, and the remaining 3 to 4 times is unexplained. Candidates, none confirmed: the collector walks pages by words, which are 4 bytes on wasm32 and 8 on x86_64 (about twice as many steps); tight scan loops may interpret worse than call-heavy code; the Debug build.
3. **The page model holds on both sides.** The first collect is the cheapest and the later ones plateau at about two to three times that, on x86 and on wasm32, as the page-count account above predicts. Traced memory in use (claimed minus free) is the same 655.5 KB in all three builds (655,632 bytes in Px86 and Wx86, 655,480 in W32); wasm32 simply claims three more, nearly empty, 64 KiB pages (851,968 bytes against 655,648). The `nref_memstat` columns are the name, the cap, the bytes claimed and the free bytes inside the claimed regions (`nref.c`).
4. **Side observations (register 76).** The first `NEW` triggers a collection in the WThread flavours only: `make50` is 620 µs in Wx86 and 126 ms in W32, against 5 µs in Px86. Untraced bytes in use differ (752 in Px86, 688 in Wx86, 272 in W32). Neither has been looked into.
5. **Single runs.** Each figure is one run; the x86 values vary by up to about 2.4 times between runs, which does not touch a 200-fold gap.

### The x86_64 library route is closed (v18)

The comparison that would isolate the library (the whole of `neocore` built on x86_64 through `m3llwasm` with `THREAD=W`) cannot be done with the installed tree: the installed tools link `libneocore.so` dynamically, and with that flavour installed `m3llwasm` itself segfaulted (see "Build flavours and the installed library (v18)"). An x86_64 WThread comparison would need the older harness that imported `WThread` and its thread stubs directly from a tree called `m3aux`; it is not planned. What can still be varied on x86_64 is the default flavour against `Llvm` (both PTHREAD), with a snapshot first.

### Experiments to run, in order (v18; wasm32 only unless stated; none done)

One variable at a time (harness rule 6). Each is timed with the same `ms14` and compared with the W32 column above (485 ms per collect, `churn` about 36 ms).

1. **A Release `iwasm`**, built in a separate directory with the same flags (`WAMR_BUILD_EXCE_HANDLING=1`, `WAMR_BUILD_FAST_INTERP=0`, threads); a second variant without `WAMR_BUILD_DUMP_CALL_STACK` shows that flag's share. First check what the current build has: `iwasm --help` and the CMake cache, for any JIT or AOT tier (AOT/`wamrc` support for exceptions is unverified). This isolates the engine, and it is the largest suspect.
2. **The poll check.** Policy (register 35) says the collector units are poll-free; confirm it on the wasm32 library, for the units the walk loops reach: `RTCollector`, `RTAllocator`, `RTHeapRep`, `RTHeapMap`, `RTTypeMap`, `RTType`. For example `llvm-nm -A -u libneocore.a | grep -E "(RTCollector|RTAllocator|RTHeapRep|RTHeapMap|RTTypeMap|RTType)[^ ]*:.* U nthr_park"` (not run); an empty result closes the poll share. A hit says which unit to count call sites in; a poll-free variant of a collector unit would then be a decision under the frozen-baseline principle, not an experiment.
3. **`llc -O2` for the library**, with the same `iwasm`. In `etc/Unix.common` the `llvm_backend` procedure passes `-O0` unless the driver's optimise flag is on, and then `llvmback_optimize` (default `-O2`). The constraints table allows `llc` -O1 to -O3 with no `opt`; re-run the `ms8` visibility harness and the audit afterwards. This isolates codegen quality.
4. **Count the loop.** A temporary counter in `GrayBetween` and `CleanBetween` (iterations and objects per page; a patch file, reverted before a checkpoint, rule 17). It settles the 4-byte-step hypothesis.
5. **The profiling build.** `WAMR_BUILD_PERF_PROFILING` in a separate diagnostic build (it was removed from the main build in v16 to cut the output): the per-function time during one `Collect` says whether `GrayBetween`, an assertion helper or `nthr_park` owns it. Run it only if 1 to 4 leave a large factor unexplained.
6. **Optionally, last: the x86_64 `Llvm` flavour** (`m3llhost`, PTHREAD, no polls): the whole library through `llc -O0` at native speed. Snapshot `/usr/local/m3neos` first (rule 20); run it only if 1 to 3 leave the `-O0` question open.
7. Then decide whether the remaining cost per pinned page is acceptable for the target (server-side programs on a JIT or AOT engine) and record it.

Dropped options: the **fast interpreter** (the exceptions build requires the classic one; migration checklist 1.3) and a **second engine** (legacy-EH and thread support differ; unexamined).

Not a correctness problem; it decides how large a collection test on wasm32 can be. `ms9` now runs on wasm32 (next section), with the harness sized to the engine (rule 18).


