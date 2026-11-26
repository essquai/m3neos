# Build flavours, installed library, target description, wasm32 flags

*Reflects plan v19, 2026-11-26. The v18 text below is moved verbatim from dev-plan18.md (lines 629-645, 778-843); the link-ceiling table at the end is new.*

<!-- v18 lines 629-645 -->
## Build flavours and the installed library (v18)

**Why this section exists.** An attempt to compare x86_64 with WThread broke the installed toolchain (2026-11-24). The facts below are the user's account, checked against `etc/m3neos.cfg` and `etc/Unix.common`.

| x86_64 flavour | Selected by | Back end | Thread library | Safepoints |
|---|---|---|---|---|
| default | no parameters (`etc/m3neos.cfg`: `M3_BACKEND` defaults to `"C"`, `TARGET` to `x86_64`) | `m3C`, then the C compiler | PTHREAD | signals (`pthread_kill`) |
| `Llvm` | `-DM3_BACKEND=Llvm` | `m3llhost`, then `llc` | PTHREAD | signals |
| `Wasm` on x86_64 | `-DM3_BACKEND=Wasm`, and `THREAD=W` for the library (the config forces `THREAD` only for wasm32; how it is passed on x86_64 is not recorded here) | `m3llwasm -b -g -t x86_64`, then `llc -mtriple=x86_64` | WThread | cooperative polls |
| wasm32 (the one viable flavour) | `-DTARGET=wasm32` (forces `THREAD="W"`, `M3_BACKEND="Wasm"`, `TARGET="wasm32"`) | `m3llwasm -t wasm32`, then `llc -mtriple=wasm32` | WThread | cooperative polls |

- **Build output and install.** Object and executable files go into a directory named for the target (`x86_64`, `wasm32`). Libraries are shipped to `/usr/local/m3neos/pkg/<package>/<TARGET>`; executables built in local source directories link the shipped libraries. So **only one flavour of `neocore` per target is installed and linked at any time**; the flavours cannot coexist. (`hand.o` and `Uconstants.o`, register 56, are another case of one install directory for two targets.)
- **`llc` flags.** `llvm_backend` in `etc/Unix.common` passes `-frame-pointer=all -mtriple=<TARGET> --dwarf-directory=0 -filetype=... <llvmback_pic> [<llvmback_features>]`, then `-O0` unless the driver's optimise flag is on, in which case `llvmback_optimize` (default `-O2`). `m3llwasm` is called as `-b [-g] -t <TARGET>`.
- **The tools link the library.** `ldd /usr/local/m3neos/bin/m3llwasm` lists `libllvm22api.so.5`, `libneoutils.so.5`, `libneo.so.5` and `libneocore.so.5`, the last three from `/usr/local/m3neos/pkg/<package>/x86_64/`, and the system `libLLVM.so.22.1`. The installed x86_64 `neocore` is therefore part of the toolchain. Built with `THREAD=W` and `m3llwasm` and installed, it made `m3llwasm` segfault. The user restored the default flavour and wasm32 by rebuilding; `pkg/neosys` is the insurance copy for the case where the driver itself cannot run.
- **What follows.** (1) Take a snapshot (`cp -a /usr/local/m3neos`) before any flavour swap (rule 20). (2) Use `-realclean` for the package and the test directory when switching (register 69). (3) The flavours that keep the tools working are the PTHREAD ones; the default and `Llvm` swap is possible in principle and untested. (4) An x86_64 WThread comparison would need the older `m3aux` harness (register 74).
- **Baseline wording.** The "baseline" of the frozen-baseline principle is the **default** flavour: the C back end, unmodified, with PTHREAD. The Baseline section's heading, which names `m3llhost`, is read with the clarification added there.


<!-- v18 lines 778-843 -->
## Target descriptions and datalayout (m3llwasm)

Findings recorded so they are not rediscovered:

- **Renames.** `AMD64_LINUX` was renamed `x86_64`; it carries the **proven,
  historical datalayout** (`e-m:e-p:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128`,
  as in the current `phb.ll`). The modern x86_64 datalayout string became `CUR_X86_64`,
  **opt-in only**. The proven string stays the default.
- **wasm32 datalayout:** `e-m:e-p:32:32-p10:8:8-p20:8:8-i64:64-n32:64-S128-ni:1:10:20`.
  It is **identical for `wasm32` and `wasm32-unknown-wasi`**, confirmed independently
  with clang-18 (18.1.3) in a sandbox.
  **(v18)** With LLVM 22 the module `m3llwasm` writes carries triple `wasm32-wasi-threads` and datalayout `e-m:e-p:32:32-p10:8:8-p20:8:8-i64:64-i128:128-n32:64-S128-ni:1:10:20`: the string above plus `i128:128`.
- **Sysroot problem for `wasm32-unknown-wasi`** in the user's environment: **deferred.**
  (Note: the C runtime pieces are built for `wasm32-wasip1-threads`; see "wasm32 build
  flags".)
- **Target triple (v12):** `m3llwasm` now uses `wasm32-wasi-threads` (previously
  `wasm32-unknown-threads`). **(v17)** With clang 22 the C parts are built for `wasm32-wasip1-threads`; the `llc` line carries `-mtriple=wasm32`; the triple
  string inside the module that `m3llwasm` writes was not re-checked in this sprint.
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
(`nthr*`, `nsyn`, `nref`, `RTIOc`, …) and, since v16, to the objects `llc` makes from `m3llwasm` output.

- **Compile (`.c`):** `--target=wasm32-wasip1-threads -pthread` (clang then enables
  `+atomics`, `+bulk-memory`, `+mutable-globals`, `+sign-ext`), plus `--sysroot` and
  `-resource-dir`; `-D_WASI_EMULATED_SIGNAL` where needed. **(v16)** Also `-mexception-handling`: the
  sysroot's `setjmp.h` is guarded by `__wasm_exception_handling__`.
- **Assemble (`.s`):** the same command line plus `-matomics`; `-pthread` does nothing for the
  assembler. The m3make driver compiles stand-alone `.s` files with the C compiler using the
  same command line as C files, and the command lines come from per-target scripts, so
  `-matomics` goes **only in the wasm32 script** (never x86_64: it is an error on x86_64 `.c`
  files and unused on x86_64 `.s`).
- **Modula-3 objects (`llc`), v16.** `etc/wasm32` sets `llvmback_pic = "-relocation-model=static"` (the default in `etc/Unix.common`
  stays `-relocation-model=pic`; with `pic` every module references `__memory_base`) and
  `llvmback_features = "-mattr=+atomics,+bulk-memory,+mutable-globals"`; the hook `llvmback_features` (default empty, appended to the `llc`
  arguments only when non-empty) was added to `etc/Unix.common`. Without the features `wasm-ld --shared-memory` rejects the objects.
- **Libraries (`make_lib`), v16.** `AdjustShared` returns FALSE for wasm32 (defined before `include("Unix.common")`), so only the archive is made
  and no shared object, which `wasm-ld` could not link with the generic GNU-ld flags.
- **Link:** `-Wl,--shared-memory,--import-memory,--max-memory=<bytes>`. The driver does not add
  these. The maximum must be a multiple of 64 KiB and must match the host's memory. **(v15)** The maximum is also the
  hard bound the collector will see: see register 41 for how to size it. **(v16)** In `etc/wasm32`:
  `SYSTEM_LD = SYSTEM_CXXXC & LD_PREF & " -Wl,--fatal-warnings" & " -Wl,--shared-memory,--import-memory,--max-memory=" & MAX_MEMORY & WASI_LIBS`
  with `WASI_LIBS = " -lwasi-emulated-signal -lwasi-emulated-mman -lwasi-emulated-getpid"`; no `-rpath`, `--warn-common` or `-z` flags.
- **Platform facts:** `long` is 32 bits on wasm32 (use `size_t`/`unsigned long long` with
  overflow checks for size arithmetic). On wasm32 `sbrk` needs a **multiple of 64 KiB** or wasi-libc traps with `unreachable`; since v16
  `nref.c` rounds every amount it passes to `sbrk` to that granule (`Virtual` arena creation and every `claim_more_memory` in real-`sbrk`
  mode). Stock wasi-sdk 24 `malloc.h` lacks `struct mallinfo`, so `nref.c`/`nref.h` did not compile against it unmodified (register 27);
  they compile for wasm32 now because the `mallinfo` use was dropped from both copies (neocore and neosys).
- **(v17) Exceptions.** C and assembler: add `-mexception-handling -mllvm -wasm-enable-sjlj -mllvm -wasm-use-legacy-eh=true` (each its own `-mllvm`); `llc`: add
  `+exception-handling` to `-mattr` and `-exception-model=wasm -wasm-enable-sjlj -wasm-use-legacy-eh=true`; link: add `-lsetjmp`. Sysroot `/opt/wasi-sysroot-33.0`. Full
  lists in "Exceptions on wasm32 (v17)".
- **Where things live (v16).** Per-target flags and hooks: `etc/wasm32` and `etc/Unix.common`; wasm32 selection of sources: `unix/WASI`
  and the `neocore` makefiles; entry generation: `cmd/m3link/src/MxGen.m3`.

---

## Link ceilings in use (2026-11-26)

The ceiling is set with `-DMAX_MEMORY=<bytes>` on the `m3neos` command line; it feeds `--max-memory` (above). The default is 33,554,432 (32 MiB).

| Program | Ceiling | Note |
|---|---|---|
| `ms10`, `ms13`, `ms14`, `ms15`, `ms16` | default, 32 MiB | |
| `ms17` | varied; 32 MiB for the ceiling run | a clean `NEW()` failure at 16 MiB live |
| `ms9` | **128 MiB** (`-DMAX_MEMORY=134217728`) | at 32 MiB `pageTest` dies with an uncaught runtime error from `NEW`, exit 129 (register 82) |

Rebuilding a program drops its link settings back to the default, so a rebuild of `ms9` needs the flag again.
