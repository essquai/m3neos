# Notes, 2026-11-25: ms15, ms16, ms17, the audit fix, and what they settle

Not a plan version. Evidence is from the user's builds and runs (x86_64, and wasm32 under Wasmer 7.0.1 with the
exnref build, `llc` 22, wasi-sysroot-33.0). Where something is an inference, it says so.

## Outcome by register

| Register | Outcome |
|---|---|
| 42 audit gate on wasm32 bitcode | **Passes.** 94 of 94 modules (the `neocore` library, `ms10`, `ms13`, `ms14`): 0 not homed, 0 violations, `poll=ok`. 19 pairs exempt, all by-value aggregates (`DragonInt` 5, `FloatUtils` 13, `WeakRef` 1). Limit unchanged: the audit cannot see calls that `llc`'s sjlj pass adds |
| 49 collector mode on wasm32 | **Incremental and generational by default.** Every module gets `gc_flags = 3` because `Host.doIncGC` and `Host.doGenGC` default to TRUE and nothing in `etc/` passes `-NoIncGC` or `-NoGenGC`; `RTLinker.AddUnitI` clears the mode only if some module lacks the bit. The `ms17` sweeps agree (the two modes have different thresholds) |
| 41 bounded traced heap | **Sizing rule found, see below.** Out-of-memory below the bound is a clean abort. The behaviour at the link ceiling (`--max-memory`, no `@M3traced`) is not measured |
| 62 nested procedures | **Done.** `ms16` passes on x86_64 and wasm32 |
| 66 uncaught exception in a worker | **Done.** `ms15` |
| 67 `jmp_buf` size and alignment | **Done.** 164 bytes, alignment 4 |
| 52 `nthr_func` trace lines | Both are commented out in `nthr_wasm32.c`: the park/broadcast pair near line 50, and the `nthr_func end` line near line 73 in `nthr_start32` (found by the user; it was not in the first place looked at). Gating them behind `NTHR_TRACE` instead is still optional |

## The audit fix (`audit.py`)

The single remaining failure, `RTLinker.mb`, was a bug in the script, not in the generated code. The front end emits two
call sites for the one source call `b(0)` or `imp.binder(0)`: a closure path (word 0 is -1, code at +4, environment at +8,
call `code(env, args)`) and a plain-procedure path (call `b(args)` after a NIL check). A phi merges the two results. The script
counted a phi operand as a use in the phi's own block, so each result looked live along every other path, including the
prologue's `nthr_park` and the other path's call: 2 results x 2 calls = 4 pairs per function, 8 for `AddUnit` and `AddUnitImports`.
A phi operand is live only on the edge from its own predecessor; the script now does that.

The old behaviour could only add pairs, never remove real ones, so earlier passes stand. `phi_ctl.ll` is the control: it expects
exactly 3 pairs (`%r` in `phi_real`, `%x` in `op_across_in_pred`, `%p` in `loop_phi`); the old script reported 13 on it. The earlier
controls and the `ms9` IR have no phis and give identical output before and after.

Files: `test/src/n0/ms8/audit.py` (fixed), `test/src/n0/ms8/phi_ctl.ll` (new), and the earlier `loop_poll_check.py` and
`audit_all.sh`. The project copy `claude/audit.py` needs replacing with the fixed script.

## Register 67: `Target.Jumpbuf_size` is not what matters

`Target.Jumpbuf_size` is 0 and unused, because `Alloca_jmpbuf = TRUE` (in `Target.i3` and in `RTExFrame.m3`). Each `TRY` allocas
`m3_jmpbuf_size` bytes, a constant that `Uconstants.c` defines as `sizeof(jmp_buf)` against the wasi headers; it is built for wasm32
from `unix/Common`. A probe compiled against `/opt/wasi-sysroot-33.0` printed `sizeof(jmp_buf)=164 alignof=4` both with only
`-mllvm -wasm-enable-sjlj` and with the build's full flag set. The `alloca i8` carries no alignment; I expect that to be harmless on wasm
(only atomics need natural alignment), which is reasoning, not a measurement.

## Register 66: `ms15`

A failed assertion in a worker thread goes `AssertFailed` -> `Raise` -> `InvokeBackstop` -> `DefaultBackstop` (twice, the second
pass crashes) -> `Crash` -> `RTProcess.Crash` -> `RTOS.Crash` -> `abort`. It never unwinds through `WThread.Exec`: M3 exceptions are
frame chains kept per thread, so a worker with no handler never produces a wasm exception at its entry.

| Mode | x86_64 | Wasmer |
|---|---|---|
| `ok` (worker returns, `Join` gets 42) | exit 0 | exit 0 |
| `main` (assertion fails on the main thread) | message, abort, exit 134 | message, trap `unreachable`, exit 129 |
| `worker` (assertion fails in the worker) | message, abort, exit 134 | message, trap `unreachable`, exit 129 |

The worker behaves exactly like the main thread; 134 is SIGABRT, 129 is Wasmer's own code for the trap. There is no M3 stack dump on
wasm32 (only Wasmer's backtrace); `RTException.DumpStack` was not read. A wasm exception at a worker entry cannot be produced from M3 source
and is not tested.

## Register 62: `ms16`

Six cases pass on both targets: read and write of the parent's locals, a doubly nested procedure, a nested procedure passed as a
value through two callees (the closure path), a recursive nested procedure, a FINALLY handler that reads and writes the parent's local
(with and without a raise), and a traced `REF` named only from nested procedures surviving four collections. Negative control: changing one
expected value (4123 to 4124) stops both builds with `<*ASSERT*> failed: r = 4124`. The tests run at `llc -O0`, where every local is an
alloca; the Phase O entry criteria should list `ms16` with `ms13` and `ms14`, since `mem2reg` could break the up-level cases.

## Registers 41, 49: `ms17` and the sizing rule

`ms17` holds a live set of known size (A, 1 KiB chunks), then pushes garbage through the heap, replacing one live chunk in sixteen.
Thresholds are the smallest traced cap (`@M3traced=NM`) at which all runs pass.

| Live set, target | Incremental fails / passes | Stop-and-copy fails / passes |
|---|---|---|
| 4 MiB, x86_64 | 18M / 20M | 14M / 16M |
| 4 MiB, Wasmer | 20M / 22M | 14M / 16M |
| 8 MiB, Wasmer | 36M / 40M | 28M (2 of 3 pass) / 32M |

Every point was 3 runs; every cap was 0 of 3 or 3 of 3 except one (8 MiB live set, stop-and-copy, 28M: 2 of 3). Doubling the live set doubled the thresholds. The
documented bound is 4A (incremental) and 3A (stop-and-copy); measured, the default incremental collector needs about 5A and stop-and-copy
about 4A.

**Heuristic for sizing: reserve 6x the live data for the default incremental collector, 5x for stop-and-copy** (a premium of about 20%).
With the 128 MiB link limit (`-DMAX_MEMORY=134217728`) and about 10 MiB for everything that is not traced heap, about 117 MiB remains: room
for roughly 19 MiB of live data (incremental) or 23 MiB (stop-and-copy). The 10 MiB comes from one two-thread program; it grows with more threads
and untraced data.

Facts met along the way:

- `etc/wasm32` sets `MAX_MEMORY = "33554432"` unless defined; override with `m3neos -DTARGET=wasm32 -DMAX_MEMORY=134217728`.
- With `@M3traced=NM` the traced arena is claimed whole at startup, not grown. In `ms17` the arenas start at 0x850000 (8,716,288 bytes);
  a 24M cap needs 25,165,872 more, which does not fit in 32 MiB, so `sbrk` fails and `nref_prologue` aborts. That was a link-limit collision, not
  a collector failure.
- Under Wasmer a cap below the bound ends in `NEW() was unable to allocate more memory`, exit 129, in a fraction of a second.
- An uncapped `ms17` run claimed 24,117,248 bytes of traced heap (1,375,848 free), the same figure as `ms9` under Wasmer. Not investigated.
- In the `ms15` `ok` runs the exit statistics read `Traced 458752:131012` on wasm32 and `327872:16` on x86_64 (claimed bytes, then free bytes).
  Not investigated.

Not measured: more than one object size, more than one thread, the link-ceiling failure, and register 48 (the allocator giving up without finishing
a collection). All are secondary to the rule above.

## Tool notes

- `sweep.sh` (in `test/src/n0/ms17/`): an earlier version hung under Wasmer and could not be stopped with Ctrl-C. The version in use runs each
  program in its own session with stdin from `/dev/null`, uses `timeout -k 5`, and traps Ctrl-C. Three changes were made at once, so which one removed
  the hang is unknown; the explanation (a background process group touching the terminal and being stopped) was never confirmed.
- Wasmer takes program arguments directly after the module: `wasmer wasm32/ms17 4096 64 v @M3traced=12M`. `v` prints progress lines.
- Exit statuses: 129 is a Wasmer trap (`abort`), 134 a native `abort`, 124 a timeout, 137 a SIGKILL after the timeout.

## Open after this

- `ms10` and `ms13` under Wasmer (the exnref build): not confirmed in the logs seen; `ms9`, `ms14`, `ms15`, `ms16` and `ms17` are.
- The link-ceiling case for the heap (one rebuild with a small `-DMAX_MEMORY`, no `@M3traced`).
- Plan v19, when asked: record the Wasmer pivot (primary engine, exnref flavour, WAMR as an optional legacy cross-check, the 128 MiB limit)
  and register the findings above.
- Housekeeping: the project copy `claude/audit.py`; `doc/optimisation-visibility.md` section 2.

## Files from this round

- `test/src/n0/ms15/src/` (`Main.m3`, `m3makefile`)
- `test/src/n0/ms16/src/` (`Main.m3`, `m3makefile`)
- `test/src/n0/ms17/src/` (`Main.m3`, `m3makefile`) and `test/src/n0/ms17/sweep.sh`
- `test/src/n0/ms8/audit.py` (phi fix) and `test/src/n0/ms8/phi_ctl.ll`
