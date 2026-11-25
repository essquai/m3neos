# Phase L and the wasm32 bring-up record (includes the WAMR/wasi-libc/wasm-ld facts at v18 lines 699-716)

*Reflects plan v19, 2026-11-25. Text below is moved verbatim from dev-plan18.md (lines 646-728, 2264-2334).*

<!-- v18 lines 646-728 -->
## wasm32 bring-up record (v16)

Recorded so that none of it has to be rediscovered. Evidence is from the user's builds and runs; my part was reading the logs and
sources and proposing the fixes (the user applied them).

### Setup

- **Toolchain (v17: moved to LLVM 22.1.2 and `wasi-sysroot-33.0`; see "Exceptions on wasm32").** In v16: `wasi-sysroot-24.0` at `/opt/wasi-sysroot-24.0` on the user's machine; WAMR 2.4.5 (`iwasm`); C and assembler for
  `wasm32-wasip1-threads`. The Modula-3 pipeline is `m3front`, then `m3llwasm -b -g -t wasm32`, then `llc` (see "Build pipeline fact").
- **Configuration.** `m3neos.cfg` canonicalises `TARGET` to the lower-case string `wasm32` and sets `THREAD="W"` and `M3_BACKEND="Wasm"`.
  The `Builder` calls `Target.Init (s.target, OS_TYPE, backend_mode)`, so `Target.System_name` (case preserved from the configuration) is
  available in `MxGen` and `m3link`; the entry-point generator tests it against `"wasm32"`.
- **Staleness.** The build decides what to rebuild by comparing object and source modification times only. A configuration change (anything
  in `etc/`) needs `-realclean -DTARGET=wasm32`, a rebuild and `-ship`.
- **Commands.** In a package directory: `m3neos -DTARGET=wasm32 [-commands]`, then `m3neos -DTARGET=wasm32 -ship` for the libraries. `-ship`
  installs libraries and headers under `/usr/local/m3neos/pkg/neocore/wasm32` and `.../src/...`, and `hand.o` and `Uconstants.o` into
  `/usr/local/m3neos/lib` (see register 56). A program is run with `iwasm wasm32/<name>`. **(v18)** A multi-thread program needs the cluster limit raised: `iwasm --max-threads=16 wasm32/ms9` (default 4; register 71).

### The trap-and-fix chain

In the order met. "Fix" is what was applied; the files are the user's tree.

| # | Symptom | Cause | Fix |
|---|---|---|---|
| 1 | `llc`: WebAssembly "hasn't implemented nest arguments" | the wasm backend does not implement LLVM's `nest` attribute, so a static link has to be an ordinary parameter (which also changes how a FINALLY handler is called through a procedure value) | `LLVM_WASM.m3`: the `nest` attribute is no longer added to the static-link formal (`BuildFunc`, with `<* ASSERT i = 0 *>` kept) or to the call site (`InnerCallIndirect`); the link is an explicit leading `i8*`; `call_invoke_indirect` emits with- and without-static-link variants; FINALLY handlers take the static link only. `RTExFrame.m3`: `FinallyProc = PROCEDURE () RAISES ANY`, `CallProc (p: FinallyProc) RAISES ANY = BEGIN p (); END`, and `InvokeFinallyHandler` calls `CallProc (LOOPHOLE (ADR (cl), FinallyProc))` (register 54). **(v17) The `RTExFrame`/`FinallyProc` part is superseded:** the original `p(a)` form is back and the back ends keep the nameless handler formal ("The calling convention of a FINALLY handler"); the static-link part stands |
| 2 | LLVM intrinsic declarations with the wrong overload count (`IntAbs`, `DoRotate`) | the overload count passed to the intrinsic lookup did not match the intrinsic | `llvm-intrinsic-overload.patch` for `LLVM_WASM.m3`, **applied** (without it `llc` reported an error). The same bug is present in `LLVM_HOST.m3` (near lines 3497, 3567, 4037), untouched (register 55) |
| 3 | archiving `libneocore.a` failed: `wasm-ld` rejected `-rpath`, `--warn-common`, `-z now`, `-z origin` | `make_lib` also builds a shared object, and the generic link line carries GNU-ld flags | `AdjustShared` returns FALSE for wasm32 (defined in `etc/wasm32` before `include("Unix.common")`, so the quake "if not defined" pattern picks it up); `SYSTEM_LD` trimmed |
| 4 | every module referenced `__memory_base` | `llc` ran with `-relocation-model=pic`; the link is a static, non-PIE `wasm-ld` link | `llvmback_pic = "-relocation-model=static"` in `etc/wasm32` |
| 5 | `nthr_nexus.1`, a duplicate global with a suffixed name, in the objects | `CompileSafepoint` and `import_global` called `LLVMAddGlobal` for a name that already existed in the module | `LLVMGetNamedGlobal` first, `LLVMAddGlobal` only when it returns NIL (both places) **(v17)** Still open. The LLVM 22 `declare_object`/`DebugObject` decision is deferred with it: CM3's LLVM 22 API adds `field_offset` and `method_offset` to `declare_object` (a different way to extend inheritance), and whether `DebugObject` should use them (and so drop the NIL supertype element) is undecided. |
| 6 | `--shared-memory is disallowed by Main_m.o ... atomics or bulk-memory` | `wasm-ld --shared-memory` requires every object, including `llc`-built ones, to carry atomics and bulk-memory (and mutable-globals for TLS) | `llvmback_features = "-mattr=+atomics,+bulk-memory,+mutable-globals"` in `etc/wasm32`, appended to the `llc` arguments by a new hook in `etc/Unix.common` (empty by default, so x86_64 is unchanged) |
| 7 | `Exception: unreachable` at start-up | wasi-libc calls `__main_argc_argv`; only a two-parameter `main` is renamed to it, so with the three-parameter `main` the linker substituted an `undefined_weak:main` stub, which is `unreachable` | `MxGen` entry generation for wasm32 (two-parameter `main`, `envp` from `__wasilibc_get_environ`) |
| 8 | link errors: `_setjmp`, `_longjmp`, `pthread_atfork` | the generated entry pulled in the runtime, which uses them; wasi-libc defines none of them (the sysroot's `setjmp.h` needs the EH proposal) | placeholders in `WasiCstd.c` and `WasiSys.c` (register 51, 57). **(v17)** The `_setjmp`/`_longjmp` placeholders are deleted: real ones now |
| 9 | `Exception: unreachable` in `nref_sbrk_vary` | `sbrk(48)`: wasi-libc aborts unless the increment is a multiple of 65,536 | 64 KiB granule in `nref.c` |
| 10 | nothing printed although `PutText` ran | `RTIO` only fills a 4,096-byte buffer; `RTIO.Flush` writes it; nothing flushes at exit | `RTIO.Flush ()` in `ms10`; a runtime fix is register 53 |

A symbol survey of `libneocore.a` (2,752 defined, 952 undefined) was used to find the libc stragglers before linking.

### What the `ms10` run shows

- **Control flow.** `_start`, `__main_void`, `main` (generated), `nref_prologue`, `RTLinker.InitRuntime`, `WThread.InitialThread` (`nthr_create`,
  `nthr_arch_tls32`, `nthr_arch_spawn32` and one `thread-spawn`), then `wasi_thread_start`, `nthr_start32` and `Main__mainMS10` on the spawned
  thread, join and reap by the main thread, `RTProcess.Exit`, `exit`, `proc_exit`. The WAMR memory-growth hang that the project recorded earlier
  (and the `WASM_UINT*_IS_ATOMIC` build defines against it) did not appear.
- **Allocator.** Three traced allocations, one untraced object and two untraced open arrays; `RTHeapRep.LongAlloc`, `FindFreePages` and
  `GrowHeap` ran once each: the heap grew. `CollectEnough` and `Behind` were called once, and no collection ran. `nref_memstat` at exit:
  Virtual 65,536 bytes claimed (44,884 free), Untraced 196,608 (196,420 free), Traced 458,752 (131,012 free); the printed cap is 0 because no
  `@M3` size option was given.
- **Time.** `RTLinker.InitRuntime` took about 62 ms under the profiling interpreter; `nref_diag_stow` (28.8 ms over 137 calls) and
  `validate_memory_regions` (11.1 ms over 47 calls) are a large share of it: the allocator's debug checks are on. The profile is a WAMR
  interpreter profile with profiling enabled; read the numbers as proportions.
- **Interleaving.** The main thread's `nref_memstat` lines and WAMR's per-thread profile block went to stdout together and spliced
  (`func __i` then `Virtual ...` then `satty`): two writers, one stream.

### Facts about wasi-libc, `wasm-ld` and WAMR learned on the way

- **Entry.** `_start` calls `__main_void`, which calls the weak `__main_argc_argv (argc, argv)`. Only a `main` with two parameters is
  renamed to it by the compiler. `__wasilibc_get_environ ()` is the accessor that initialises the environment lazily.
- **`sbrk`.** `sbrk (0)` returns the current memory size; any other call aborts unless the increment is a non-negative multiple of 65,536.
  `abort ()` itself is `unreachable`, so an abort in WAMR appears as `Exception: unreachable`.
- **`setjmp.h`** in the sysroot requires `__wasm_exception_handling__` (hence `-mexception-handling` in the C flags). wasi-libc has no
  `_setjmp`/`_longjmp` unless built with the exception-handling proposal and `-mllvm -wasm-enable-sjlj` (register 51).
- **Linker.** `wasm-ld` rejects GNU-ld flags (`-rpath`, `--warn-common`, `-z`); `--shared-memory` demands atomics and bulk-memory on every
  object. A newer `wasm-ld` provides `__stack_high`; whether the user's version does is not verified (register 60).
- **Build system.** `make_lib` builds a shared object unless `AdjustShared` returns FALSE; the `Builder` generates `_m3main.cpp` and compiles it
  with `clang` (C++ by file extension), so declarations in it need `extern "C"`; defining a quake variable in `etc/wasm32` before
  `include("Unix.common")` overrides the "if not defined" defaults.
- **WAMR diagnostics.** The rebuilt `iwasm` is a Debug build with `WAMR_BUILD_DUMP_CALL_STACK`, `WAMR_BUILD_LOAD_CUSTOM_SECTION`,
  `WAMR_BUILD_CUSTOM_NAME_SECTION` and `WAMR_BUILD_FAST_INTERP 0` (the classic interpreter), set in `etc/neoiwasm.cmake`; call stacks with
  function names appear on a trap. `iwasm -v=5` gives verbose loader output (option names from memory, not verified). The `-C` file seeds the
  CMake cache only for a fresh build directory: removing a flag from it does not unset a cached value.

### Debug output in the run, and where each piece comes from

| Output | Source | Switch |
|---|---|---|
| "Performance profiler data" and "Memory consumption summary" blocks, "Spawned thread" banner | `WAMR_BUILD_PERF_PROFILING` and `WAMR_BUILD_MEMORY_PROFILING` in `etc/neoiwasm.cmake` | **done (v16):** both removed; the run went from more than 400 lines to fewer than 20 |
| call-stack dump after `proc_exit` (ten frames, `proc_exit` to `_start`) | believed to be `WAMR_BUILD_DUMP_CALL_STACK` at `proc_exit`; it survived the removal of the profiling flags, which is consistent with that but not a confirmation | keep for trap diagnosis |
| `nthr_func tid=... nexus broadcast / nexus park / end` | `printf`+`fflush` at `nthr_wasm32.c` lines 52, 54 and 73 | proposed `NTHR_LOG` macro behind `NTHR_TRACE` (`-DNTHR_TRACE` re-enables); the x86_64 file has its own copies and is not touched |
| three `Virtual/Untraced/Traced` lines | `nref_memstat ();` emitted by `MxGen` into the generated `main` for every target (C entry, and the IR entry in `GenerateCGEntry`) | leave while bringing up, or make `nref_memstat` quiet unless an environment variable is set (a change inside `nref.c`, not in the generator) |
| (silent) diagnostic text cache in `nref.c` | `nref_diag_stow` writes into a 512-slot cache; `nref_diag_dump` prints it | the cost, not the output, is the issue (above); add a switch before measuring performance |

---


<!-- v18 lines 2264-2334 -->
## Phase L — The Core Library on wasm32 (new in v12; before Phase E)

**Status (v17): unchanged apart from the setjmp/longjmp placeholders, which are gone (real implementations via LLVM 22 sjlj). (v16): stage 1 is done for `neocore`; `neolib` and stage 2 are open.** The library (`pkg/neocore`, the `m3core` built on WTHREAD) now
compiles, archives, installs and links for wasm32 against wasi-libc 24.0 as it is, and a program that uses it has run (see "wasm32 bring-up
record (v16)"). Phase L is still the critical path for everything that needs more than `neocore`: `neolib` (libm3) has not been built for
wasm32, the placeholders below are not real implementations, and exceptions that reach a handler abort (register 51). The phase is
independent of the collector work in the code it touches, so it can be interleaved. It also produced the library bitcode on which the audit
gate must be run (register 42).

**What the survey found** (m3neos `pkg`: `neosys` is m3core plus the runtime, `neolib` is libm3):

- The C API calls Modula-3 uses and the system calls underneath them are **two cleanly separated
  parts**.
- **Modula-3 file I/O is entirely fd-based** (`Uuio`); there are no `Cstdio` importers. The
  C-side stdio exposure is only `RTIOc.c`, `nthr_debug` and `nref_diag_dump`. RTIO is meant for
  compiler development and for debug output that does not depend on the Modula-3 runtime
  (including garbage collection and front-end parsing). So no stdio/musl vendoring is needed
  for now. **(v16)** The hello-world used exactly this path: `RTIO` buffers, and `RTOS.Write` writes the buffer (its text appeared on the
  terminal while stdout was redirected, which is consistent with the error stream; not verified in the source).
- **Absent from WASI** (by design — sandboxing — and the project targets wasm on the server
  side, where Modula-3 was meant as a systems language; the gaps are expected, not defects):
  fork/exec/wait/pipe; sockets and netdb; signals; pwd/grp; termios; tzset; popen/system/tmpfile;
  and the `UnixC` subset (dup, pipe, umask, chown, mknod, getdtablesize, file locks).
- **Modula-3 modules affected:** `SystemPosix`, `SchedulerPosix`, `LowPerfTool`; `RTPerfTool`
  (via `Uexec`); `SocketPosix` (via `Usocket`, `Unetdb`, `Uin`); `ThreadPosix`, `FloatMode`, `FPU`
  and `ConnectRdWr` (via `Usignal`).

**Stage 1 — use what is in wasi-sdk's libc (done for `neocore`).** No patched wasi-libc and no vendored musl; those are needed only if concurrent
stdio or locked libc globals turn out to be really required. What exists now:

- **Module and header selection.** `pkg/neocore/src/unix/WASI` is included by the `unix` makefile under `equal (TARGET, "wasm32")`, after
  `OS_TYPE` and `Common`; its makefile registers `h_source("m3core")` (the dedicated wasm32 header) and the two C sources. The main
  `neocore` makefile registers its own `h_source("m3core")` only when the target is not wasm32, and the `unix/Common/m3unix` header is
  registered for all targets. Exactly one `m3core.h` per target; the x86_64 build is unchanged. (The earlier form,
  `h_source("unix/WASI/m3core")` selected by a condition in the main makefile, is retired.)
- **Build flags and link line:** see "wasm32 build flags (reference)".
- **Libc surface used by the hello-world run** (from the profile): `printf`/`vfprintf`/`vsnprintf`, `fflush`, `malloc`/`calloc`/`dlmalloc`, `sbrk`,
  `sigaction`/`sigemptyset` (the runtime installs its signal handlers), `gettimeofday`, `timespec_get`/`clock_time_get`, and
  `__wasilibc_get_environ`.
- **Still to do in stage 1:** `neolib` for wasm32 (a new `neolib/os/WASI` directory is the intended home for the Process-related pieces),
  following the same pattern: selection by `include_dir` and fenced wasm32 headers.

**Stage 2 — account for the system calls WASI lacks (started).** Placeholders live in two files in `unix/WASI`, split by the standard that
defines the function; each fails cleanly or reports the honest answer, and each is to be made `weak` (register 57) so that a real
implementation takes over without editing the placeholder:

| Function | File | Behaviour now | Needed for |
|---|---|---|---|
| ~~`_setjmp`~~ | `WasiCstd.c` | **(v17) deleted**: the back end now emits `setjmp`, lowered by LLVM | every `TRY ... EXCEPT` and FINALLY with EXIT/RETURN emitted by the back end |
| ~~`_longjmp`~~ | `WasiCstd.c` | **(v17) deleted**: `CsetjmpC.c` calls `longjmp` on wasm32 | an exception raised to a handler (register 51, closed) |
| `system` | `WasiCstd.c` | message and abort (the only function left in the file) | Process |
| `pthread_atfork` | `WasiSys.c` | returns 0 (wasm has no `fork`, the handlers can never run) | `RTProcess.RegisterForkHandlers` |
| `gethostname` | `WasiSys.c` | message and abort | host name queries |
| `getlogin` | not yet written | | expected straggler (not pulled in by the hello-world) |
| `IOWait`, `IOAlertWait`, `WaitProcess` (`SchedulerPosix`) | `WThread.m3` | **(v18)** stubs that return errors; `SchedulerPosix` is exported from `WThread.m3` | the x86_64 WThread build needed the interface; real versions come with Process and networking (register 75) |

The policy per interface (fail, emulate, omit) is decided as each is reached; `_WASI_EMULATED_SIGNAL` and the other `-lwasi-emulated-*` libraries
cover a part of the surface where emulation is acceptable. **Direction (the user's, recorded 2026-11-03):** real, not stubbed, UDP and TCP
networking and process spawning on wasm32 under WAMR, with host-side work in WAMR (leaning to `--native-lib`, possibly with a capability list);
only the Process interface needs honouring (spawn the whole process; `fork` is not needed). The wasm32 personality files are fenced in new
directories (`unix/WASI` now, `neolib/os/WASI` later) rather than guarded by `#if` in shared headers.

**Constraints.** Frozen baseline (guard everything; the x86_64 build of `m3core`/`libm3` is
unchanged). The Libc/`Uuio` boundary stays as is. No change to PTHREAD. **(v14)** The wasm32 library is compiled by `m3llwasm`
with `llc` only (no optimiser), and the audit gate runs on its bitcode before the first collection on wasm32. **(v15)** The
library's memory behaviour on wasm32 also decides the collector mode and the cap (registers 41, 49). **(v16)** A wasm32-only C file needs no
`#if` guard (the build selects it); a file shared with x86_64 would use `__wasi__` for libc and OS questions and `__wasm32__` for architecture
questions (`__wasm__` covers wasm32 and wasm64); the exact macro set is best read from the compiler with `-dM -E`.

---


