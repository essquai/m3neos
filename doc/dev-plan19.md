# Incremental Development Plan — v19 (DRAFT for review)

**Status of this file:** the register and principles text are moved verbatim from `dev-plan18.md`
(frozen source, 2,501 lines); the other notes are alongside it. The overview, milestones, phase summaries and working rules are drafts for the user to review.

---

## 0. Document map

Only the plan carries a version number. Notes are named by topic, edited in place, and
carry one line: `reflects plan vN, date`. Git is the version history.

**Main body**

| File | Holds | v18 source (line ranges) |
|---|---|---|
| `dev-plan19.md` | Overview, milestones, register, principles, working rules, document map | 90–185 (frozen baseline, verbatim); 2381–2472 (register, rows verbatim); 2492–2501 (supplementary-notes list, verbatim) |
| [`phase-a.md`](phase-a.md) | Phase A, baseline | 729–777; 844–1128 |
| [`phase-b.md`](phase-b.md) | Phases B1 and B2 | 1129–1744 |
| [`phase-c.md`](phase-c.md) | Phase C, the roots decision, constraints, audit results | 186–330; 1745–2211 |
| [`phase-e.md`](phase-e.md) | Exceptions (record, flags, calling convention, validation) | 348–471; 2360–2380 |
| [`phase-l.md`](phase-l.md) | Phase L stages 1 and 2, bring-up record | 646–728; 2264–2334 |
| [`phase-o.md`](phase-o.md) | Optimiser enablement (future) | 2335–2359 |

**Appendices** (reference material: worth recording, not part of the narrative; for anyone consulting or evaluating the design)

| File | Holds | v18 source (line ranges) |
|---|---|---|
| [`collector-cost.md`](collector-cost.md) | Collector cost on wasm32 | 472–563 |
| [`build-and-flags.md`](build-and-flags.md) | Build flavours, installed library, target description, wasm32 flags | 629–645; 778–843 |
| [`wamr-record.md`](wamr-record.md) | ms9 under WAMR, and its repeat on Wasmer (the WAMR/wasi-libc facts at 699–716 stay in [`phase-l.md`](phase-l.md) and are cross-referenced here) | 564–628 |
| [`phase-d.md`](phase-d.md) | Precise roots, parked (a future option) | 2212–2263 |
| [`dev-plan-changelog.md`](dev-plan-changelog.md) | Plan v19 entry; revision notes v10–v18, v18 near-term sequence, commit-granularity table (verbatim, superseded) | 1–89 (notes); 331–347; 2473–2491 |

Check after the split: every non-empty line of `dev-plan18.md` must appear verbatim in
exactly one new file, or be listed as a deliberate rewrite (the register heading and the
old "Appendices" heading, both renamed or removed).

---

## 1. Overview

### 1.1 Purpose, scope and snapshot

This plan covers the new work for the wasm32 target of a CM3-derived Modula-3 compiler. The x86_64/Linux target, through the `m3llhost` back end and the PTHREAD runtime, is an already-working baseline and is frozen. For wasm32 the plan covers the `m3llwasm` back end, the `WTHREAD` runtime (`WThread`, `nthr`, `nsyn`), the core library (`pkg/neocore`, which replaces `pkg/neosys`) and, next, `neolib`. The primary engine is Wasmer 7.0.1 (exnref build); it was provisional until milestone M6 was proved, and was confirmed on 2026-11-26 (Cranelift, the backend `wasmer run` picks by default, is the working choice; the LLVM backend also runs; the one failure seen on the way was a startup race in `WThread`, now fixed, register 81). WAMR was the earlier reference, and its results are kept in [`wamr-record.md`](wamr-record.md).

**Snapshot, 2026-11-26.**
- **Done:** phases A, B1, B2, C and E, and L1. The wasm32 runtime, the unmodified collector and exceptions run end to end on Wasmer, in tests from `ms9` to `ms17`. The audit gate is 94 of 94, and the memory sizing rule is written down. Wasmer is proved (2026-11-26): a collection costs about 4 times native, and `ms9` ran 200 of 200 on Cranelift and LLVM. Milestones M1 to M6 are met.
- **Next:** `neolib` for wasm32 (M7). Open beside it: `RTIO` is not flushed at exit (53). A startup race found on the way (81) is fixed.
- **Still to come before the library is useful:** milestones M7 to M9: `neolib`, system services (spawn, UDP/TCP), and a real program.

### 1.2 Phases (a short narrative and a three-bullet status each; the table is the index)

| Phase | Goal | Status (draft) | Note file |
|---|---|---|---|
| A | wasm32 runtime scaffolding: threads, parking, stop-the-world, arenas | Complete. Tested through `ms10` and `ms13` on Wasmer. Open: 28, 34, 37 | [`phase-a.md`](phase-a.md) |
| B1 | Emission of safepoint checks (polls, gcroot scaffolding, loop-edge polls) | Complete, validated. Open: 3, 5, 8, upstream reports (6) | [`phase-b.md`](phase-b.md) |
| B2 | GC root tracking (`m3t`, classification, parameter rooting) | Complete. Narrow open: 9, 12. Composite metadata dormant | [`phase-b.md`](phase-b.md) |
| C | Feeding roots to the existing, unmodified collector (conservative pinning) | Complete, stages 1 to 3. Residue: 46, 70. Chain walk parked | [`phase-c.md`](phase-c.md) |
| E | Exceptions on wasm32 (sjlj lowering, exnref) | Complete on exnref. Leftovers (non-blocking): personality fate, `ExceptionDebug.argType`; 68 parked; 64 is future work | [`phase-e.md`](phase-e.md) |
| L1 | `neocore` replaces `neosys`, builds and runs on wasm32 | Done for `neocore`. More validation possible | [`phase-l.md`](phase-l.md) |
| L2 | `neolib` (libm3) and the missing system services on wasm32 | Not started beyond placeholders (23, 57, 59, 75) | [`phase-l.md`](phase-l.md) |
| O | Optimiser enablement | Future, unscheduled; entry criteria recorded | [`phase-o.md`](phase-o.md) |
| D | Precise roots | Parked by decision (v14); future option | [`phase-d.md`](phase-d.md) |

#### 1.2.1 Phase A: wasm32 runtime scaffolding
*Detail: [`phase-a.md`](phase-a.md). Register: open 19, 27, 28, 34, 37; closed 18, 20, 21, 22, 33, 36.*

Phase A gives a Modula-3 program what it needs from a thread runtime on wasm32, where there are no signals to stop another thread. The `WTHREAD` module (`WThread`, `nthr`, `nsyn`, and a small assembler entry per target) stops the world cooperatively. Every thread has a context whose `watch` field says what the collector may assume about it: `deferred` (blocked or parked, stack published), `relief` (the coordinator itself), `vigilant` (running, must be stopped), `detached` or `joined`. A collection calls `SuspendOthers`, which sets a flag in the shared nexus and waits until every vigilant thread has parked at a poll (Phase B1) or entered a blocking primitive (`nthr_wait`, `nthr_lock`, `nthr_vigil`). A blocking primitive publishes the thread's stack and shadow-stack chain and marks it `deferred`. `ResumeOthers` clears the flag and wakes the parked threads.

Four invariants govern every blocking primitive: `watch` changes only under `watchSyn`; a safepoint re-check surrounds each blocking call; `relief` is held for the whole `SuspendOthers` to `ResumeOthers` bracket; and the exemption from stopping is by role, not by module. Three later rules came from reproduced failures. A `parked` counter makes a new stop wait until every thread from the previous stop has left park, which cured starvation (every stop followed by a run window: 1.00, against 0.00 to 0.39 before). The Mesa rule for join says whoever makes a condition true changes it under the waiter's lock or signals under it. And `nthr_lock` handles contended locks, with a `no_park` mode for the heap lock; `SuspendOthers` is only ever called with the heap lock held.

wasm32 differs from x86_64 in three places. A thread starts through `wasi_thread_start` into `nthr_start32` (`nthr_wasi.s`). There is no pthread to join, so reaping waits on an `ended` flag with `memory.atomic.wait32`. The saved-register block is zero on wasm32 and filled on x86_64, so the conservative scan treats both alike. The context layout is checked by size at start-up and by a `_Static_assert` on `ended`.

**Status.**
- Complete and in use: `ms4` and `ms7` to `ms9` on x86_64 and wasm32 (`ms9`: twelve threads, 112 of 112 runs under WAMR), and `ms10`, `ms13`, `ms15` and `ms17` under Wasmer. On 2026-11-26 a startup race was found and fixed: the original thread's stack was not published before the program's main thread could collect (81).
- Open and small: 28 (stale `joinSyn` in `AlertJoin`), 34 (`After` and `VisitAllRefs` call `SuspendOthers` without the heap lock), 37 (unclaimed-thread reaper, slot-table growth), 27 (nref/nthr clean-ups).
- Out of scope: memory ordering on native ARM (19); targets are x86_64 and wasm32.

#### 1.2.2 Phase B1: emission of safepoint checks
*Detail: [`phase-b.md`](phase-b.md). Register: open 3, 5, 6, 8, 15; closed 2, 4, 7.*

B1 puts the poll into generated code. The back end for wasm32 (`m3llwasm`) emits LLVM IR from the same front-end output as x86_64. At every function entry and on the taken side of every loop back-edge it emits: load the nexus `safePoint` flag; if it is non-zero, load the thread's `watch` state; if that is `>= vigilant` (ordinal 2), call `nthr_park`. The common path is one load and one branch. The enum order is load-bearing, and the generator cannot import the runtime enum, so `Vigilant = 2` is a constant in the generator with a comment naming its source.

Roots use LLVM's `llvm.gcroot` with the shadow-stack strategy, not statepoints, because statepoints need native stack unwinding, which wasm lacks. What the strategy is kept for is visibility: a gcroot'd value stays in memory where the conservative scan can see it (Decision v14, see [`phase-c.md`](phase-c.md)). The shadow-stack chain head is made thread-local, and `nthr_park` publishes a copy for the collector. The generator follows fixed rules. The entry block holds only allocas, gcroot calls, a one-byte marker store for aggregate roots and scalar parameter spills. Record roots are zeroed in a prolog block before the first poll. The builder never goes back to the prolog block after the poll. The marker store works around an `llc` crash on aggregate gcroot (LLVM's lowering emits a null store it cannot legalise). That crash and the lowering's loss of alloca alignment are the two upstream reports (6). A `pop_struct` alignment bug the second one exposed is fixed.

Nested procedures needed a wasm32 change: the back end does not implement `nest`, so the static link is an explicit leading parameter (v16), and `ms16` exercised up-level access.

**Status.**
- Complete and validated: the reference module `phb`, six generated procedures with nested loops under the WTHREAD harness on x86_64, `ms8` and `ms9`, and the wasm32 builds under the audit gate.
- Open: 3 (generic wasm32 system in `Target.m3`), 5 (NIL debug element for objects without a supertype), 6 (upstream reports), 8 (attribute clean-up), 15 (`memcpy align 1`).
- Library poll policy is item 35.

#### 1.2.3 Phase B2: GC root tracking
*Detail: [`phase-b.md`](phase-b.md). Register: parked 9, 12; closed 1, 47.*

B2 decides which stack-resident values are roots. The front end tags each declaration with a type fingerprint (`m3t`, a `TypeUID`). The back end's `ClassifyTrace` turns it into none, scalar (one traced pointer) or composite (a record holding traced fields), and `ClassifyVar` guards the case where a temporary's fingerprint does not match its representation (the open-array `NEW` dope temporary, register 47). A scalar root is a pointer-typed alloca registered with `llvm.gcroot` and null metadata.

The rules for what is a root: value parameters of traced types are rooted, with the real type, size and alignment flowing into the slot and the spill acting as the initialiser (closed in v10). Objects are scalar roots, because the collector finds their fields through the header typecode. By-value record parameters get no slot, because the callee works on the caller's temporary. By-reference parameters hold addresses and are not roots. Untyped front-end temporaries are not roots, and are safe only if a rooted holder spans every safepoint (the derived-copy rule). The audit gate (42) checks that mechanically on the IR.

Decision v14 gave the phase its final shape: roots stay conservative. The collector scans whole stacks, so gcroot only has to keep values in memory, and precision is not pursued. Composite gcroot metadata (`TypeComp`, byte-identical to the collector's maps in four test cases) is built, verified and dormant. Fixed arrays of references are not rooted. At `-O0` they are allocas in the scanned range, and they would need address roots with null metadata if an optimiser is ever added (Phase O).

**Status.**
- Complete for the conservative scheme: IR inspection, `ms8`, `ms9` and the audit gate (94 of 94 on the audited set).
- Parked narrowly: 9 (declaration-ordering assert never fired; `type_map` against `gc_map` unexplained) and 12 (deriving `traced` for opaque types).
- Deferred: `BITS N FOR T`, the `superType` sprint, `BuiltinTypes.KindUID`.

#### 1.2.4 Phase C: feeding roots to the existing collector
*Detail: [`phase-c.md`](phase-c.md). Register: open 40, 41, 46, 48, 49, 70; parked 25 (chain walk); closed 26, 38, 39, 45.*

Phase C connects the compiled code to the collector without changing the collector. `RTThread.ProcessStacks` (in `WThread.m3`) hands each non-detached thread's whole stack range and saved registers to the unmodified `NoteStackLocations`. The scan is pin-only: a stack word that points onto a heap page promotes that page in place, so everything on the page stays where it is. Pinning is page-granular (64 KiB pages), and a pin can only retain memory, never corrupt it. Module globals are precise roots (`RTHeapMap.WalkGlobals`), and heap contents are traced through the front end's type maps. The compiler's one obligation is memory residence: every traced value live across a safepoint must have a home in the thread's stack range.

This is the v14 decision, and it was taken on evidence. The scan costs tens of microseconds against about a millisecond for a collection, a false pin retains at most one page, and a precise walker would need collector changes (a break with the frozen baseline). The decision lists four conditions that would re-open it: stack referents that must move, measured false retention in bounded wasm32 heaps, an optimiser that needs aggregates rooted, and a failure of the visibility assumption on the real toolchain.

The phase was proved in three stages. Stage 1 (`ms4`, `ms7`) validated stop-the-world and pinning, and showed that the collector pins its own highest page (accepted, 38). Stage 2 (`ms8`) added `REF` fields inside heap records and objects, with all 65 stay-or-move outcomes explained. Stage 3 (`ms9`) added fixed and open arrays to depth 3, interior views (which pin), `VALUE` open-array copies (independent), by-value aggregates two levels deep and a twelve-thread text workload; every stay was explained by a stack hit, page sharing or a large-object promotion, and none coincided with corruption. The accepted pin classes are the highest page, designed pins, `-O0` spill-slot residue (45) and page-level pins of unidentified origin. The harness rules learned along the way are collected in section 3.2.

On wasm32, `ms9` ran 112 of 112 times under WAMR and stack-held objects never moved in 1,400 observed transitions. A bounded traced heap fails when the allocator gives up while an incremental collection is in flight (41). The documented space bound is about 4A pages incremental and 3A stop-and-copy; `ms17` measured about 5A and 4A, and its sizing rule and the clean abort at the link ceiling are in `doc/memory-audits.md`.

On Wasmer the `ms9` batch was repeated on 2026-11-26: 100 of 100 runs on Cranelift and 100 of 100 on LLVM, each run the same 261 lines, with no assertion or trap. `ms9` needs a link ceiling of 128 MiB (`-DMAX_MEMORY=134217728`); at the default 32 MiB it ends with an uncaught runtime error from `NEW` (82). Details are in [`wamr-record.md`](wamr-record.md).

**Status.**
- Complete under the conservative scheme on x86_64 and wasm32, including the `ms9` batch on Wasmer (milestone M2).
- Open: 46 and 70 (local-`REF` variants, a `regs[]` hit, `ms9` residue), 48 (allocator retry, optional), 49 (collector mode), 40 (diagnostics clean-up).
- Parked: the chain walk (25b) with Phase D.

#### 1.2.5 Phase E: exceptions on wasm32
*Detail: [`phase-e.md`](phase-e.md). Register: closed 16, 51, 62, 66, 67 (the last three this session); parked 68; future 64.*

Modula-3 exceptions stay what they are: a chain of frames (`RTExFrame`), with a raise to a handler ending in `longjmp`. The back end emits a `setjmp` call for every `TRY ... EXCEPT` and for a `FINALLY` body containing `EXIT` or `RETURN`. On wasm32, LLVM 22's `-wasm-enable-sjlj` lowering turns each such function into WebAssembly try/catch code and each `longjmp` into a throw of the `__c_longjmp` tag, with the runtime pieces in the sysroot's `libsetjmp` (`-lsetjmp` at link). Nothing in the AST, M3CG or the C back end changed. The pass recognises only the names `setjmp` and `longjmp` and requires `returns_twice`. Every translation unit that calls either must go through it, and a rename needs a complete rebuild of `neocore` (69).

Two interactions with the shadow-stack (gcroot) lowering were found and fixed. The lowering rewrites calls into `invoke`s with a landing pad that the wasm back end cannot select, so every call to M3 code carries a call-site `nounwind` (sound, because M3 exceptions run no cleanups). In a function with both a gcroot and a `TRY` the two rewrites cannot coexist, so `m3llwasm` runs the shadow-stack lowering itself, before `llc`. The `FINALLY` handler's calling convention was a conscious decision to protect the frozen baseline. M3C compiles a handler with one extra nameless formal (the activation), which the front end never fills. M3C and the shared runtime must not change, so the LLVM back ends conform to M3C: they keep that formal and pass NIL for it. The alternative, a second `RTExFrame` implementation for wasm32, was rejected on the principle that passing a placeholder is better than having two. `RTExFrame.m3` is therefore identical in `neocore` and `neosys` (`beta.25`). A `longjmp` leaves the thread-local chain head stale until the catching function returns. That is harmless, because the collector never reads the chain (68).

The mechanism was built on legacy wasm EH under WAMR 2.4.5 with a local patch for exceptions in spawned threads. The exnref encoding failed there (`invalid local type 0x69`). The project has since moved to exnref on Wasmer 7.0.1: the build lines now carry `-wasm-use-legacy-eh=false`, and `ms13`, `ms15` and `ms16` pass. `ms15` covers an uncaught exception in main and in a worker (a clean abort with a message, as on x86_64), and `ms16` covers nested procedures and procedure values. **Note:** `phase-e.md` still records the legacy-EH flags; the exnref flag change is made in v19 text only.

**Status.**
- Complete on exnref: `ms13`, `ms14`, `ms15`, `ms16` on Wasmer. `ms14` (collection after a catch) was re-run on 2026-11-26: 215 runs on Cranelift, LLVM and the default, one of them failed on the assertion in register 81, a startup race now fixed.
- Closed this session: 62 (nested procedures), 66 (worker-thread uncaught exception), 67 (`jmp_buf`: 164 bytes, alignment 4, matches the target setting).
- Non-blocking leftovers: `__m3_personality_v0` (declared, attached to nothing), `ExceptionDebug.argType`, 64 (`llvm18wasm` parity, future work), 68 (parked). Phase O inherits one criterion: values modified after a `setjmp` must stay memory-resident.

#### 1.2.6 Phase L1: `neocore` on wasm32
*Detail: [`phase-l.md`](phase-l.md), [`build-and-flags.md`](build-and-flags.md). Register: open 52, 53, 56, 57, 58, 60, 61, 69, 74; closed 29.*

Phase L stage 1 brings the core library up on wasm32 with wasi-libc as it is: no patched libc and no vendored musl. `pkg/neocore` (the `m3core` built on `WTHREAD`) compiles, archives, installs and links for `wasm32-wasip1-threads`. The wasm32 personality is fenced rather than guarded: a dedicated `m3core.h` and two placeholder C files live in `unix/WASI`, selected by the build when the target is wasm32, so the x86_64 build is untouched. The build configuration is `etc/wasm32` with a hook in `etc/Unix.common`; `MxGen` generates the two-parameter `main` that wasi-libc expects; and `nref` allocates in 64 KiB units, because wasi-libc's `sbrk` aborts on any other increment.

The first hello-world (`ms10`) took ten problems to fix, recorded as a trap-and-fix table in `phase-l.md`: the missing `nest` attribute, wrong intrinsic overload counts, GNU-ld flags, PIC against a static link, a duplicate global, shared-memory features, the entry point, the libc stragglers, the `sbrk` granule and the unflushed `RTIO` buffer. Since then the toolchain moved to LLVM 22 and wasi-sdk 33, the `setjmp`/`longjmp` placeholders were deleted for real implementations, and every test from `ms9` to `ms17` has run on the library. Two traps for the next person: `RTIO` is not flushed at exit (53), so a program that prints must flush; and the build compares file times only, so a change to a name the back end emits or to `etc/` needs `-realclean` (69).

**Status.**
- Done for `neocore`: it builds, installs and runs everything in the test series. More validation is possible, and no user-space program outside the tests has run yet.
- Open housekeeping: debug-output switches (52), `hand.o`/`Uconstants.o` colliding across targets (56), weak placeholders (57), `GenerateCGEntry` not exercised (58), recorded toolchain versions (60), commits (61), and only one library flavour installed at a time (74).
- Next: stage 2 and `neolib`.

#### 1.2.7 Phase L2: `neolib` and the missing system services
*Detail: [`phase-l.md`](phase-l.md). Register: open 23, 57, 59, 75.*

Stage 2 is not started beyond placeholders. WASI deliberately lacks `fork`/`exec`/`wait`/`pipe`, sockets and `netdb`, signals, `pwd`/`grp`, `termios`, `tzset` and `popen`/`system`/`tmpfile`. That affects `SystemPosix`, `SchedulerPosix`, `LowPerfTool`, `RTPerfTool`, `SocketPosix`, `ThreadPosix`, `FloatMode`, `FPU` and `ConnectRdWr`. Modula-3 file I/O is entirely fd-based (`Uuio`), so no stdio work is needed. The placeholders that exist each fail cleanly or give the honest answer: `system`, `gethostname` (message and abort), `pthread_atfork` (returns 0, since wasm has no `fork`), and `IOWait`, `IOAlertWait` and `WaitProcess` in `WThread.m3` (stubs that return errors, 75). `getlogin` is an expected straggler. The policy for each interface (fail, emulate, omit) is decided when it is reached.

The direction recorded on 2026-11-03 is real UDP and TCP networking and process spawning on wasm32, with host-side work in the engine; only the Process interface needs honouring, and `fork` is not needed. That plan was made for WAMR (leaning to `--native-lib`, possibly with a capability list). With Wasmer as the primary engine, **the host-side route has to be decided again.** `neolib` itself comes first, as far as the next test needs: a new `neolib/os/WASI` directory is the intended home of the Process-related pieces (59).

**Status.**
- Not started beyond placeholders. Milestones M7 (`neolib` runs) and M8 (spawn and network) wait on it.
- Open: 23 (the phase), 57 (weak placeholders), 59 (`neolib`), 75 (`SchedulerPosix` stubs).
- Open decision: the host-side mechanism under Wasmer.

#### 1.2.8 Phase O: optimiser enablement
Future and unscheduled; summarised in section 4 and detailed in [`phase-o.md`](phase-o.md).

#### 1.2.9 Phase D: precise stack roots
*Detail: [`phase-d.md`](phase-d.md). Register: parked 9, 10, 13, 14, 17, 25b, 68.*

Phase D would replace the conservative scan with a walk of each thread's gcroot chain, using the `TypeComp` metadata, to find stack roots precisely. It was parked by the v14 decision: the whole-stack scan is cheap, pin-only and already proven, and a precise walker would bring a new `RTTypeMap` entry point (a variance from the shared baseline), aggregate root-slot addressing, tolerance for non-heap roots and chain-head sourcing for parked and blocked threads. If it is ever reopened, the first step is address roots with null metadata, not the walker. The design is kept in the appendix so nothing has to be rediscovered.

**Status.**
- Parked by decision; no work scheduled.
- Re-open conditions are the four in Phase C.
- Prerequisites are recorded in the appendix.

### 1.3 Completion milestones (draft; the user edits)

| # | Milestone | Status | Evidence / open register items |
|---|---|---|---|
| M1 | The runtime runs on wasm32: threads, parking, arenas, orderly exit | ✅ | `ms10`, `ms13` exit 0 on Wasmer (2026-11-25) |
| M2 | The unmodified collector is correct on wasm32 with threads | ✅ | `ms9` 112/112 on WAMR; 100/100 on Wasmer Cranelift and 100/100 on LLVM (2026-11-26, 128 MiB link, 82). What the runs do not cover is in 70 |
| M3 | Exceptions on the primary engine: raise, catch, finally, worker thread, collection after catch | ✅ | `ms13`, `ms15`, `ms16` on Wasmer (2026-11-25); `ms14` on Wasmer (2026-11-26), with one failure in 215 runs, a startup race now fixed (81) |
| M4 | Memory behaviour is predictable: sizing rule and a clean failure at the ceiling | ✅ | `ms17` sweeps and the 32 MiB ceiling run (clean abort with message). Allocator retry (48) optional |
| M5 | Generated code is checked mechanically: audit gate on all wasm32 bitcode | ✅ | 94/94 across the library, `ms10`, `ms13`, `ms14` and the test programs, after two fixes to `audit.py` (by-value aggregate exemption; per-edge phi liveness, which cleared `RTLinker`). The gate cannot see calls `llc`'s sjlj pass adds (42) |
| M6 | Collector speed is acceptable on the primary engine; the proving-out that confirms or rolls back the Wasmer choice | ✅ | `ms14` on Wasmer: a collect takes about 4 times native on Cranelift and on LLVM, against 221 to 351 times on WAMR (2026-11-26; [`collector-cost.md`](collector-cost.md)). Measured at one heap size only |
| M7 | Core library: `neolib` builds and a program using it runs | ☐ | 59 |
| M8 | System services: process spawn and UDP/TCP through the host | ☐ | 23, 57, 75. Direction recorded 2026-11-03. Host-side design for Wasmer undecided |
| M9 | *Proposed:* a representative real program (for example the front end compiling a file) runs on wasm32 | ☐ | Also the measurement program Phase O waits for |

---

## 2. Register

### 2.1 Next candidates (draft; at most three, dated 2026-11-26)
1. **`neolib` for wasm32 (59),** as far as the next test needs. Starts M7.
2. **`RTIO` is not flushed at exit (53).** A small fix that bites every program that prints.

*Done 2026-11-26 and removed from this list:* proving Wasmer (M2, M3 and M6) and the `ms14` startup race (81); see the changelog.

### 2.2 Open items


Ordered. "B1" items continue the B1 close-out list; "B2" items are the narrow
`m3t`/metadata leftovers. **Numbering is stable across versions; items 1, 2, 4, 7, 16, 20, 21, 22, 24, 26, 29, 32, 33, 36, 38, 47 and 51 are
closed in place (or accepted), 11–16 date from v10, 17–22 from v11, 23–32 are from v12, 33–40 from v13, 41–46 from v14, 47–50 from v15, 51–62 from v16, 63–69 are new in v17, and 70–76 are new in v18.**

| # | Item | Phase | Notes |
|---|---|---|---|
| 3 | **`Target.m3` generic wasm32 system (`WASM32_WASI`)** | B1 | Deterministic 32-bit width (not by name substring); excluded from the 32-bit alignment downgrade for non-C backends so `m3llhost` is unchanged; confirm `phb.ast` shows `Int.32` and a 4-byte `Addr`. User-space programs for wasm32 additionally need Phase L stage 1. **First step of the near-term sequence** **(v16)** `Target.System_name` is `wasm32` and the library builds without tripping the `AllocVar` alignment assertion of item 8; the `phb.ast` check (`Int.32`, 4-byte `Addr`) is not recorded here. Largely done in practice: confirm when convenient. |
| 5 | **Debug info: NIL element** for objects without a supertype | B1 | LLVM 20 rejects it |
| 6 | **Report two LLVM bugs upstream** | B1 | Aggregate gcroot `llc` crash; shadow-stack lowering drops alloca alignment. Reproducers ready. (v14: a fix of the second would shift the frame layout of the dormant composite path; address roots would be immune) |
| 8 | Finish the wasm32 function-attribute cleanup | B1 | Only partially done. Waits on Phase L stage 1: the front end cannot compile user-space programs for wasm32 until the system dependencies are built for it (codegen without that yields 8-byte pointers and the `AllocVar` assertion `v.align <= ptrBytes` fires). **Second step of the near-term sequence's prerequisites** **(v16)** The wasm32 library builds, links and runs with the attribute set as it stands; the item no longer blocks anything. Finish when convenient. |
| 11 | **Open-array VALUE parameter copy** (`number`) and open-array dope-vector temporaries | arrays | **v15: behaviour validated on x86_64** (copy-in complete, writes isolated, survives collections; 1-D `SUBARRAY` and 6 by 9 by 3). The open-array `NEW` dope temporary is explicitly not a root (47). What is left is wasm32: the formal's slot must be in memory the scan covers for the whole body (42, 44) |
| 15 | `pop_struct` copy is `llvm.memcpy ... align 1` although slot and source are `align 8` | B1 | Low priority; legal and harmless under stop-the-world; decide whether intended. v15: the path was exercised by ms9's 72-byte by-value record with correct results **(v18)** In the wasm32 `ms9` build the 36-byte by-value temporary of `aggValTest` is `%tmp.693 = alloca %struct.4, align 32` (the other `%struct.4` allocas are `align 4`), filled by a `memcpy ... align 1`: it looks like a leftover of the whole-size alignment bug of B1.6. Harmless on wasm32. |
| 19 | **Memory-ordering portability note** — out of scope | A | The `watch`/`safePoint` store-then-load pairing relies on the nsyn lock operations between the coordinator's `safePoint := 1` and its reads of `watch` being full barriers: true on x86_64 (locked read-modify-write) and wasm (atomics are sequentially consistent, so wasm32 on ARM hardware is covered too). Targets are x86_64 and wasm32 only; native ARM would need an explicit fence, and is not planned. The thread-side handshakes (`nthr_wait`, `nthr_lock`) are `seq_cst`; a weaker target would need `seq_cst` on the coordinator's `safePoint` store and `watch` load as well, and a `seq_cst` final `safePoint` load in `nthr_vigil`. The rules are in Phase A addendum 3 |
| 23 | **Phase L: the core library on wasm32** — new in v12 | L (before E) | Stage 1: use wasi-sdk's libc as is, `m3core.h` wasm32/WASI guard, per-target module selection. Stage 2: backfill or stub the system calls WASI lacks. Frozen baseline: guarded, x86_64 unchanged. **Third step of the near-term sequence's prerequisites; reported as getting close** **(v16) Stage 1 is done for `neocore`** (builds, ships, links; the hello-world runs); `neolib` for wasm32 is open (register 59); stage 2 has started with the `WasiCstd.c`/`WasiSys.c` placeholders (57). See Phase L. |
| 27 | **nref/nthr small items** — new in v12 | A/nref | (a) `nref_define` diagnostic when the `Virtual` size is not a multiple of 64 KiB on wasm32 (otherwise `sbrk` traps with `unreachable`); (b) widen `arg_match` size arithmetic to `size_t`/`unsigned long long` with overflow checks (`long` is 32 bits on wasm32); (c) comment in `nthr_vigil` that the caller holds `joinSyn`; (d) correct the stale fence comment in `nthr_wait`; (e) consider writing each `nthr_debug` line with one `write(1, …)`; (f) bring the m3neos repo's `nref.c` up to the project version; (g) stock wasi-sdk 24 `malloc.h` lacks `struct mallinfo`, so `nref.c`/`nref.h` need a guard or shim. (h, v14 observation) `arg_match` in the project copy of `nref.c` uses `=` where `==` is meant in two places of its suffix tests (`arg[i] = 'k'`, `arg[i] = 'm'`), which assigns and then tests the assigned value; check against the user's tree. **(v15)** The `K`/`M` size options worked in the capped ms9 runs on x86_64 (`@M3traced=20M`, `@M3untraced=10M`), which suggests (h) is not present in the user's tree **(v16)** (a) was met in a different form: `nref.c` now rounds every `sbrk` request to 64 KiB on wasm32 instead of reporting a bad size. (g) Closed: the `mallinfo` use was dropped from `nref.c`/`nref.h` in both `pkg/neocore` and `pkg/neosys`. (i) Open since the project notes: the unit of the `@M3` size options (the header says KB, the code passes bytes). Check which copies of `nref.c` carry the rounding (the neosys copy is the pristine reference). |
| 28 | **`AlertJoin` stale `joinSyn`** — new in v12 | A | The target may hold a pointer to the joiner's `threadSyn` after the joiner's `T` is freed. With `T` traced (24) this should be closed; recheck on the user's tree |
| 30 | **Report WAMR upstream issues** — new in v12 | wasm32 | See `claude/wamr-build-notes.md` for the build-side findings; the `@M3virtual` workaround stays until memory growth works **(v17)** Added: stock WAMR 2.4.5 broadcasts the in-flight exception marker to every thread of a cluster, so a spawned thread that raises and catches fails; local patch on branch `WAMR-2.4.5-E` (marker kept per thread; `claude/wamr-eh-thread-fix.md`). Upstream report deferred until the project works end to end; draft in `eh_thread_repro.c`/`README-repro.md`. The exnref encoding fails on 2.4.5 (`invalid local type 0x69`). AOT/`wamrc` EH support and the fast interpreter are unexamined. **(v18)** The cluster thread limit: `iwasm --max-threads=N`, default 4 per cluster (`wasm_runtime_set_max_thread_num` in `product-mini/platforms/posix/main.c`, feeding `cluster_max_thread_num`, checked in `thread_manager.c`). The failure mode when the limit is too low (the exact message was not recorded here) is a failed thread spawn. Register 71. |
| 31 | **Second runtime cross-check** — new in v12 | wasm32 | The wasm32 join/exit results come from node with worker threads; run the same cycles under WAMR (and ideally one more engine). The harness package built against the user's own tree is the vehicle. Extends to the collector smoke test (44) **(v16) First WAMR run of WTHREAD:** `thread-spawn`, `wasi_thread_start`, `nthr_start32`, TLS set-up, join and reap through `nsyn_arch_wait32`/`wake32`, and exit worked once in `ms10`. The 200 to 600 cycle loops and the multi-thread stop-the-world have not been run under WAMR. **(v17)** EH in spawned threads now runs under WAMR with the local patch (the `ms11` regression test; `ms13` and `ms14` run their main body on a spawned thread). The 200 to 600 cycle loops and the multi-thread stop-the-world remain unrun under WAMR; `ms14` is the first collection run with two threads. |
| 34 | **`SuspendOthers` requires the heap lock** — new in v13 | A/C | Held by `Collect`, `StartCollection`, `AllocTraced` and `RTHeapStats`. The `After` and `VisitAllRefs` paths call it without it; they should take the heap lock first. A bare call aborts with `NOPARK` as soon as a fresh thread allocates |
| 35 | **Library poll policy** — carried forward, recorded in v13 | B1/C | Polls are emitted into user code only; `pkg/neocore` is deliberately not compiled with `m3llwasm` on x86_64 until stop-the-world and pinning are proven and the codegen is shown compatible with the runtime. Before polls are ever enabled in library code, `RTAllocator`, `RTCollector` and `RTHeapRep` must stay poll-free: parking inside `AllocTraced` between reading and updating `pool.next` would corrupt the heap after `FlushThreadState`. The user's preferred mechanism is to skip poll emission per compilation unit for those units (about four, possibly also `WThread`); gating on `heapState.inCritical` is the alternative. (v14: the wasm32 library will be compiled by `m3llwasm`, so this policy and the audit gate (42) are decided together) **(v18)** Not yet verified for the wasm32 library: run the `nthr_park` symbol check on `libneocore.a` for the collector units and the units their walk loops reach (`RTCollector`, `RTAllocator`, `RTHeapRep`, `RTHeapMap`, `RTTypeMap`, `RTType`); see the collector-cost section, experiment 2. An x86_64 run cannot answer it: native speed hides the cost of polls that an interpreter pays in full. |
| 37 | **Unclaimed-thread reaper and slot-table growth** — new in v13 | A | Unjoined threads go on a low-priority "unclaimed" ring that is reaped as a GC extension (design of 2026-10-24); the slot table behind `Axis.slot` (`triple[…]`) needs growth. Neither is done |
| 40 | **Diagnostics hygiene before the commit** — the user | C | Revert the per-hit trace in `RTCollector.m3`; keep the `WThread.GC` counter; keep the `ProcessStacks` header prints as a comment. Also replace the `ProcessStacks` TODO about llvm.gcroots with a comment pointing at the v14 decision. **(v15)** The ms9 lines (`GCKIND`, `PROMOTE`, `COPYFAIL`) were reverted by the user; the user has said `RTCollector.m3` is not being modified now. Commit the ms8 and ms9 harnesses (pending since v14) with this plan |
| 41 | **Collector behaviour under a bounded traced heap** — new in v14; **mechanism identified in v15** | C / wasm32 | Failure mode, trace, space bound and experiments are in Phase C, stage 3 ("Bounded heap"). In short: a capped traced heap runs out of pages while an incremental collection is in flight; the allocator's slow path (`CollectEnough` then `LongAlloc`) gives up instead of finishing the collection and retrying; the collector's own `NEW` in `InitStack` can fail too. The collector documents the bound (heap at least A x (2 + 2/gcRatio) pages incremental, A x (2 + 1/gcRatio) stop-and-copy: 4A and 3A at the default ratio). 20M traced was intermittent, 22M failed once, 32M passed 10 of 10, and 20M with `@M3noincremental` passed 10 of 10. **Action:** size `--max-memory` and the traced cap from the bound with the collector mode in force (49); measure A for real wasm32 programs. No corruption was seen in any bounded run. The v14 ms8 observation (6 MB: stays with no hit; 5 MB: out of memory) is consistent with this and was not re-run **(v18)** Measured, `ms9` on wasm32 with unbounded arenas (the default): the traced arena claimed 14,614,528 bytes (about 13.9 MiB, 1,179,200 free; 1,179,244 in some runs), the untraced arena 1,114,112 or 1,245,184 bytes, virtual 65,536. That is the workload's unbounded footprint, not the accessible-live figure A of the bound. The link's `--max-memory` for `ms9` is not recorded here (`ms13` and `ms14` use 32 MiB). No capped run was made on wasm32. |
| 42 | **SSA-across-safepoint audit gate** — new in v14 | B1/L | `claude/audit.py` over the generated IR/bitcode; require **zero not-homed pairs**. Clean on ms8 (463 call sites). **Must be run on the `neocore` bitcode produced for wasm32 as soon as we can compile for that target**, on any library bitcode built by `m3llwasm`, and after any change to IR shape. **(v15)** Also run it on an **ms9 build**: it has open-array `NEW` (the first use of `ClassifyVar`), views, `VALUE` open-array copies, by-value aggregates and text, none of which ms8 had. Library Modula-3 (`RTAllocator`, `Thread`, `Text`, …) is unaudited; exceptions and nested procedures are uncovered **(v16)** Now runnable: `neocore` is compiled for wasm32 and `ms10` exists. Run it before any collection is attempted (near-term step 2). How to get the bitcode out of the build (the driver feeds `m3llwasm` output to `llc`) is to be settled. **(v17)** Run it on the `.ll` that `m3llwasm` prints (it still contains `llvm.gcroot`); the `.mb` that `llc` consumes is already lowered. Exceptions are now compiled, so the "exceptions uncovered" limit applies to `ms13`. Whether the gate was run on the wasm32 `neocore` bitcode is not recorded: confirm. **(v18) `ms9` on wasm32: the gate passes.** Input: `llvm-dis` of the final, lowered bitcode; 1,446 safepoint call sites; the stock script reported 23 not-homed pairs, all `%cp` of `Main__aggValProc` (a by-value aggregate parameter, a stack address); the patched script reports `not homed 0  exempt 23  violations 0` (register 73); `loop_poll_check.py` passes. **Correction, superseding the v17 sentence above: `audit.py` does not read `llvm.gcroot`.** Its homing rule is a dominating store to an alloca or global through a GEP chain, so the lowered IR is a valid input (lowered-style controls confirmed it); the audit cannot see calls that `llc`'s sjlj pass adds (matters for `ms13`, `ms14`). Still open: the `neocore` library bitcode and `ms10`, `ms13`, `ms14`; whether the gate was run on the wasm32 `neocore` bitcode in the past is still not recorded. |
| 43 | **Optimiser enablement criteria (Phase O)** — new in v14 | O | Not scheduled. Entry criteria in the Phase O section. Until then: `llc` -O0..-O3 only, no `opt` **(v17)** New entry criterion: values modified after `setjmp` must stay memory-resident (Phase O, criterion 6). |
| 44 | **wasm32 collector smoke test** — new in v14 | wasm32 | The conservative scan with the real collector on wasm32: single thread under node, then multiple threads (the coordinator reading another thread's published `sp`/top), then WAMR (30, 31). The sandbox harness covered only one thread's own stack with a fake heap. Depends on registers 3, 8, 23. **(v15)** Use ms9 as the suite, stack-independent subjects first (`aggGlobTest`, the module-global arrays, `valMultiTest`), then the stack-dependent ones (`aggLocTest`, `aggValTest`, the interior views, the `VALUE` open-array cases) **(v16)** The first wasm32 collector test is a program that needs only `neocore` (near-term step 3); ms9 follows once `neolib` and exceptions allow. `ms10` shows the traced allocator and heap growth working on wasm32 before any collection. **(v17) Partly met:** `ms14` runs `Collect` on wasm32 under WAMR with two threads (one collecting, one parked in `nthr_vigil`) and every assertion holds, at 230 to 460 ms per collection (register 65). Still open: several mutator threads, pinning from each thread's stack, and ms9-style stress on wasm32. **(v18) Largely met for the `ms9` suite.** Twelve subject threads, a driver and a logger under WAMR, three cycles of two stages with explicit collections: 112 of 112 runs complete; stop-the-world with several mutators, pinning from each thread's stack (shown by outcome: 1,400 of 1,400 stack-held transitions stayed) and `Fork`/`Join` under the collector all work; unreferenced objects move as on x86_64 (differences in register 70). Not met: a hit trace on wasm32 (no collector diagnostics were on), the `+GC` counter is not logged, a `regs[]` hit, the local-`REF` variants (46). |
| 46 | **ms9: further harness extensions** — new in v14 (supersedes the remainder of 39); **mostly done in v15** | C | **Done on x86_64:** `REF ARRAY` and open arrays (depth 1 to 3, bytes and `REF`s), interior views, `VALUE` open-array copies, by-value records and fixed arrays holding `REF`s (local, global, `VALUE` parameter), text-heavy threaded smoke test (cases 1 to 8, Phase C stage 3). **Left:** the local-`REF` variants of cases 1, 2, 3 and 6 (one edit each), sizes 1 and 100 for case 2, a `regs[]` hit (try `llc -O1`), and the same suite on wasm32 (44). Add the audit and the harness gate to its checklist (done in the near-term sequence) **(v18)** The `ms9` suite now runs on wasm32 (registers 44, 70). The local-`REF` variants, sizes 1 and 100 and a `regs[]` hit are still open. |
| 48 | **Bounded-heap robustness options** — new in v15 | C / wasm32 | Not decisions. (a) The allocator's slow path could finish the in-flight collection (or force a full one) and retry once before raising `OutOfMemory`; it lives in `RTAllocator.m3` and needs only the collector's public entry (`RTCollector.Collect`), but the retry itself must be reasoned about against the heap lock and `SuspendOthers`. (b) The collector's own traced allocation in `InitStack` (state Two) could be made from a reserve or the untraced arena; that is a change to `RTCollector.m3`, which is frozen. (c) Do neither and size the cap from the bound (41). Decide when the wasm32 cap is chosen; (a) is the natural first candidate if programs will run close to their cap |
| 49 | **wasm32 collector mode: incremental, generational, or stop-and-copy?** — new in v15 | wasm32 / C | The mode sets the multiplier in the space bound (4A against 3A). Module `gc_flags` come from `Host.doIncGC` and `Host.doGenGC` (`cmd/m3fe/src/values/Module.m3`, around lines 1275 to 1283: 3 both, 2 incremental, 1 generational, otherwise absent); `RTLinker.AddUnitI` turns incremental or generational collection off, and finishes the current collection, if any linked module lacks the flag. Not yet checked: which flags the `m3llwasm` pipeline passes by default and what the user's wasm32 runs will use. Incremental collection is documented as VM-synchronised in the collector's header comment; whether it is meaningful without `mprotect` on wasm32 is a question to settle with 44 |
| 50 | **Open-array `NEW` dope temporary carries the `REF` UID** — observation, v15 | B2 / front end | `New.m3` `GenOpenArray`. Guarded in the back end by `ClassifyVar` (47). Changing the front end would change an AST both targets read; not worth it unless another consumer needs the temporary's real type. No action |
| 52 | **Debug-output switches** — new in v16 | build / runtime | Sources and switches are tabulated in the bring-up record: WAMR profiling flags (`WAMR_BUILD_PERF_PROFILING` and `WAMR_BUILD_MEMORY_PROFILING` are removed: **done**); `nthr_func` printfs in `nthr_wasm32.c` behind an `NTHR_TRACE` macro; the `nref_memstat ()` call that `MxGen` emits into every generated `main`; and the cost of `nref`'s diagnostic cache and region validation (about 40 ms of a 62 ms `InitRuntime` under the profiling interpreter), to be switched before any performance measurement. What remains in a hello-world run after the cleanup: the two `nthr_func` lines, the three `nref_memstat` lines and the ten-frame call-stack dump at `proc_exit` (believed to come from `WAMR_BUILD_DUMP_CALL_STACK`, not confirmed). **(v18)** The two `nthr_func` lines per thread (`nexus broadcast`, `end`) still appear in every wasm32 run (they are in the `ms9` and `ms14` logs), and the `proc_exit` call-stack dump follows every exit; neither affects results. |
| 53 | **`RTIO` is not flushed at exit** — new in v16 | runtime | `RTIO.PutText` only fills a 4,096-byte buffer; only `RTIO.Flush` writes it. `RTProcess.Exit` runs the exitors (`InvokeExitors`) but nothing flushes `RTIO`, so text from a program that does not call `Flush` is lost. Probably the same on x86_64 (not checked). Options: register `RTIO.Flush` as an exitor (or the equivalent in `RTProcess`), or flush in `RTProcess.Exit` before the OS exit. A runtime change in shared code: decide under the frozen-baseline principle (neocore only, or both). |
| 54 | **`RTExFrame`: copies, closure marker, `ThisException`** — new in v16 | E / nested | (a) Settled: the `FinallyProc`/`CallProc` patch is applied in `pkg/neocore` only; `pkg/neosys`, the pristine reference copy, is untouched. (b) `CallProc` and `InvokeFinallyHandler` distinguish closures from plain procedure values with a marker test; on wasm32 a plain procedure value is a function-table index (a small integer), so the test must be re-read against that representation and made robust. (c) `Compiler.ThisException ()` inside a FINALLY body reads through the static link (pre-existing behaviour; re-check on wasm32). **(v17)** (a) is **superseded**: the original `p(a)` form is back in `pkg/neocore`, identical to `pkg/neosys`; the back ends keep the nameless formal and pass NIL on direct calls. (b) and (c) stand. |
| 55 | **LLVM intrinsic overload count** — new in v16 | B1 | `llvm-intrinsic-overload.patch` (`IntAbs`, `DoRotate`) is applied to `LLVM_WASM.m3` (`m3llwasm`); without it `llc` reported an error. The same bug is in `LLVM_HOST.m3` (near lines 3497, 3567 and 4037), untouched: a clear-error fix in x86_64-shared code, to be decided under the frozen-baseline principle. |
| 56 | **`hand.o` and `Uconstants.o` collide across targets** — new in v16 | build | The `neocore` makefile exports them with `LibdExport` into one install directory (`/usr/local/m3neos/lib`); shipping wasm32 overwrote the x86_64 copies. Restoring: ship x86_64 first, then wasm32. Permanent fix is the user's call: per-architecture directory, or remove them (the makefile's own comment says they matter mainly for Windows). |
| 57 | **Stage-2 placeholders: weak, stragglers, real implementations** — new in v16 | L | Make every placeholder in `WasiCstd.c` and `WasiSys.c` `__attribute__((weak))`, so a real definition (a newer wasi-libc, a setjmp runtime, a WAMR-backed implementation) wins without editing them; archive members are extracted a whole object at a time, so a symbol defined in two extracted objects is otherwise a duplicate-symbol error. Expected stragglers, not yet pulled in: `getlogin` (no placeholder yet), others to be found as more of the library is linked. Real implementations belong with the WAMR host-side design (register 30: `--native-lib`, capabilities). **(v17)** The `_setjmp` and `_longjmp` placeholders are deleted (real implementations exist); `WasiCstd.c` now holds only `system`. Making the rest weak is still open. **(v18)** Three more placeholders, in `WThread.m3`: `SchedulerPosix`'s `IOWait`, `IOAlertWait` and `WaitProcess` return errors (register 75). |
| 58 | **`GenerateCGEntry` has not been exercised** — new in v16 | build | The IR-API entry generator is implemented for wasm32 (two-parameter `main`, `__wasilibc_get_environ` imported before `main` is declared and called with `start_call_direct`/`call_direct`/`store`, under the `Target.System_name` test) but the hello-world used the C entry. Build one program with it and look for `__wasilibc_get_environ` called once from `main` in the `iwasm` call stack or profile; check the x86_64 entry is unchanged. |
| 59 | **`neolib` (libm3) for wasm32** — new in v16 | L | Stage 1 continued: same pattern as `neocore` (selection by `include_dir`, fenced wasm32 headers); a new `neolib/os/WASI` is the intended home of the Process-related pieces. Build only as far as the next test needs; check which `neolib` modules ms9 imports. |
| 60 | **Toolchain versions are not recorded** — new in v16 | build | The `clang`, `llc` and `wasm-ld` versions on the user's machine are not in this plan (the LLVM 18.1.3 and 20.1.2 figures come from the sandbox). Record them; a newer `wasm-ld` provides `__stack_high`, whether the user's does is unverified. **(v17) Partly recorded:** LLVM 22.1.2 (`clang-22`, `llc-22`, `wasm-ld-22`, distro packages), wasi-sdk 33 sysroot (built with LLVM 22.1.0), WAMR 2.4.5 plus the fork patch. Whether the user's `wasm-ld` provides `__stack_high` is still unverified. The `llc` called by the compiler scripts is the system default, not version-specific (register 63). **(v18)** The wasm32 module `m3llwasm` writes with LLVM 22 has triple `wasm32-wasi-threads` and datalayout `e-m:e-p:32:32-p10:8:8-p20:8:8-i64:64-i128:128-n32:64-S128-ni:1:10:20`: the LLVM 18 string recorded under "Target descriptions" plus `i128:128`. |
| 61 | **Commit the first-executable sprint** — new in v16 | housekeeping | The user's. Suggested grouping: backend and `RTExFrame`; build configuration (`etc/`); `MxGen`; `nref` and `unix/WASI`. Before committing: remove the old `WasiStubs.c` and its object (confirm `llvm-ar t libneocore.a | grep -i wasi` lists only `WasiCstd.o` and `WasiSys.o`, and `_setjmp` is defined once), and keep generated files out (`_m3main.cpp`, logs, `wasm32/` output). The ms8 and ms9 harness commit pending since v14 (item 40) can ride with it. **(v17)** The first-executable sprint is committed (through `beta.22`, `beta.25`). The exceptions sprint is to commit (list in near-term step 1); the temporary diagnostics in `RTCollector.m3` and `WThread.m3` are to be reverted, not committed. **(v18)** Add to the commit list: the `ms9` `checkMulti` fix, the `SchedulerPosix` stubs in `WThread.m3`, and the patched `audit.py` (near-term step 1). |
| 62 | **A nested-procedure test** — new in v16 | B1 | No dedicated test of up-level access has run on wasm32. A small program: a nested procedure that reads and writes its parent's locals; a nested procedure passed as a procedure value and called by a callee; a doubly nested procedure; a nested FINALLY handler. Run on x86_64 as the reference, then wasm32. **(v17) Partly covered:** nested `FINALLY` handlers run on wasm32 (`Fin`, `Deep` in `ms13`). Up-level access from nested procedures and procedure values is still untested. |
| 63 | **LLVM 18 and 22 back ends: linkage, program-name collision, unversioned `llc`, and the AST/IR extension** — new in v17 | build / B1 | `cmd/m3be` holds `llvm18api`/`llvm18host`/`llvm18wasm` and `llvm22api`/`llvm22host`/`llvm22wasm` (the 22 set adapted from CM3's LLVM 22 back end, with the project's own codegen carried over). **Linkage (the user's design):** each back-end package links its own `*api` package; each `*api` package lists its version-specific LLVM libraries in its `m3makefile` and has a `Version.i3`, so a back end cannot be linked against the wrong binding. **Remaining hazards:** (a) `llvm18wasm` and `llvm22wasm` both build `m3llwasm` (and the host pair `m3llhost`), so the last one installed wins: an 18 build installed by mistake produced an `LLVMGetFunctionType` cast crash in `LoadWatch` (check with `ldd`: which `libllvmapi.so` and `libLLVM`); (b) the base `llc` in the compiler scripts is the system default, not tied to the back end's version (it must be 22 for the wasm32 flags of this plan). **AST/IR change (the user's account):** CM3's LLVM 22 API extended the `declare_object` handler of the AST with `field_offset` and `method_offset`, a different way to extend inheritance; the project's `M3IR_Asm` followed it (register 5 for the related debug-info decision). Details beyond that are not recorded here. |
| 64 | **`llvm18wasm` parity** — new in v17 | B1 | `llvm18wasm` has the `setjmp` name and the FINALLY convention, but **not** the call-site `nounwind` and **not** the pre-lowering. `LLVMRunPasses` exists in LLVM 18 (since about 13), so the port is possible; an `opt-18 -passes=shadow-stack-gc-lowering` test earlier changed nothing and was not understood (the pass name may be missing from 18's new pass manager, or the test file was not representative). Decide: port, or retire 18. |
| 65 | **Collector cost on wasm32** — new in v17 | wasm32 / C | 230 to 460 ms per collection under the classic interpreter against about 1 ms on x86_64; all in state Zero, in two walks of every page pinned from the stack (about 59 ms per page-walk). Unmodified collector; cause of the per-step rate unconfirmed (4-byte stepping through free space? `-O0`? polls? asserts? interpreter?). Experiments in order in "Collector cost on wasm32 (v17 diagnosis)". **(v18)** Measured against two x86_64 builds: collects are 221 to 351 times slower than a `m3llwasm`-test x86_64 build and an allocation-only loop 79 to 86 times, so most of the gap is general interpreter cost; the library-on-x86 comparison did not isolate `llc -O0` and library polls (register 74) and that route is closed. The wasm32-only experiments, in order: Release `iwasm`, the `nthr_park` symbol check, `llc -O2`, loop counts, the profiling build, optionally the x86_64 `Llvm` flavour (collector-cost section). |
| 66 | **Uncaught exception in a worker thread** — new in v17 | E / A | After the WAMR patch an exception that reaches a worker's entry function is local to that thread (before, it was broadcast like a trap). Test it, and read what `nthr`'s exit path and `RTException`'s backstop do. |
| 67 | **`Target.Jumpbuf_size` and alignment on wasm32** — new in v17 | E | Must be at least the size and alignment of wasi-libc's `jmp_buf` (migration checklist). The passing tests make a problem unlikely; not verified. |
| 69 | **Stale objects after a naming or flag change** — new in v17 | build | A lingering `_setjmp` reference in `RuntimeError_m.o` survived until `neocore` was rebuilt completely; the build compares file times only. After a change to a name the back end emits, or to `etc/` flags, use `-realclean` for the package (extends the staleness rule in the bring-up record). |
| 70 | **`ms9` on wasm32: residue, and what the runs do not cover** — new in v18 | C / wasm32 | (a) `twoMulti` stays at both transitions on wasm32 where the x86_64 run read in this session moved it; the explanation (it shares a page with the pinned `impMulti`) is an inference from addresses, not a trace. (b) 13 of 100 runs show one or two single-transition stays of objects that normally move (`aggVal` `next` first transition in 7, `aggLoc` `next` in 5, `oneMulti` first in 2, `aggGlob` `next` second in 2), always in the memory-retaining direction; no pinned object ever moved; unexplained until a hit trace exists on wasm32 (needs collector diagnostics, a patch file under rule 17). (c) The untraced arena at exit takes one of two values 131,072 bytes apart (73 and 27 of 100 runs; the same two in the 12-run log); cause unidentified, cosmetic. (d) The `+GC` counter is not logged on wasm32. (e) The 100-run loop recorded no exit statuses; the background load was uncontrolled; no run was pinned to one core (about 20 runs under `taskset -c 0` would add a controlled perturbation). (f) The `multiTest` timing margin is lag 0 in 600 of 600 stage checks by log order, a coarse measure. |
| 71 | **WAMR cluster thread limit** — new in v18 | wasm32 | `iwasm --max-threads=N`; the default is 4 per cluster. `ms9` (twelve subjects, driver, logger and the initial threads) is run with `--max-threads=16`; with the default a spawn beyond the limit fails (the exact message was not recorded here). Convention: every wasm32 multi-thread test is run with a limit at least the number of threads it creates. An embedder can set it with `wasm_runtime_set_max_thread_num`. |
| 72 | **Harness stage timing on a slow engine (rule 18)** — new in v18 | C harness | `ms9`'s `checkMulti` did about 32 million byte compares per call; under the interpreter `multiTest` fell two stages behind the driver's fixed 0.5 s timers and `Wait`'s assertion (`next >= ms9.stage`) fired. Fixed by scanning row 0 only and keeping the identity assertion on every row. Apply the same question to any subject with per-stage work, and to any new test run on wasm32: how long does one stage's work take on the slowest engine, against the stage length? |
| 73 | **`audit.py`: by-value aggregate exemption, parameter parsing, documentation sync** — new in v18 | B1 / L | The patched script (delivered 2026-11-24; the user reproduced the `ms9` result): a pointer parameter carrying `align N` or `byval` is a by-value aggregate (`LLVM_WASM.m3` sets a parameter alignment only for `Type.Struct`; `llvmByval` will never be turned on for wasm, so the `byval` branch is dead code) and is reported `exempt` when every **direct** call site passes an alloca (or a GEP chain on one), a global address, or the caller's own marked parameter; any other call site is a `CONVENTION VIOLATION`, the parameter stays not homed, and violations count against the gate. The TOTAL line is now `... not homed N  exempt N  violations N`. It also fixes a latent gap: a pointer parameter whose attributes contain parentheses (`byval(%T)`, `dereferenceable(8)`) was never tracked. Eleven controls in `byval_ctl.ll` (a heap pointer at a call site, an unmarked parameter forwarded into a by-value slot, an unmarked parameter whose callers all pass allocas, a heap reference loaded from the aggregate and held across a call: all still flagged; a marked parameter with no direct caller: exempt on the marker alone) and the four earlier lowered-style controls behave as expected. **Weakness:** the exemption is only as good as that one line of the back end; if `llvm22wasm` ever put `align` on a non-aggregate pointer parameter it would hide a real miss (the host back end was not checked). **To do:** commit it (`test/src/n0/ms8/audit.py`), keep `claude/audit.py` in step, and update `doc/optimisation-visibility.md` section 2, which quotes the old usage line, the old TOTAL line and the old gate rule. |
| 74 | **Build flavours, the installed library and tool coupling** — new in v18 | build | Only one `neocore` flavour per target is installed; the installed tools (`m3llwasm`, `m3neos`, ...) link `libneocore.so`, `libneo.so` and `libneoutils.so` dynamically, so a WThread `neocore` installed for x86_64 made `m3llwasm` segfault; recovery was a rebuild of the default flavour (`pkg/neosys` is the insurance). The flavour table and rules 19 and 20 are in "Build flavours and the installed library (v18)". An x86_64 WThread comparison needs the older `m3aux` harness (WThread and its thread stubs imported directly from a tree called `m3aux`); not planned. |
| 75 | **`SchedulerPosix` stubs in `WThread.m3`** — new in v18 | L | `SchedulerPosix` has three routines, `IOWait`, `IOAlertWait` and `WaitProcess`. The x86_64 WThread build needed the interface, so the user put stubs that return errors into `WThread.m3` and exports `SchedulerPosix` from it; harmless on wasm32, which gains little. Placeholders and hygiene only: real versions belong to the WASI deficiency set (stage 2, registers 23 and 57) with Process and networking. The source of the stubs was not seen in this session. |
| 76 | **First `NEW` collects in the WThread flavours only; untraced use differs** — new in v18 | C / A | In the timed `ms14`, `make50` takes 620 µs on x86_64 with WThread (Wx86) and 126 ms on wasm32, against 5 µs in the default build: the WThread flavours run a collection at the first allocation (wasm32: the "cold start" of v17). Untraced bytes in use also differ (752 default, 688 Wx86, 272 wasm32). Unexplained and low priority; probably initial heap or threshold differences, not read from the code. |

**Engine:** rows 30, 31, 65, 70 and 71 report WAMR-era results; re-check them on Wasmer (item 77).

### 2.3 Parked items

| # | Item | Phase | Notes |
|---|---|---|---|
| 9 | Declaration-ordering assumption; `type_map` vs `gc_map` at collection time | B2 | See "Still open, narrowly". **v14:** the `type_map`/`gc_map` question is no longer a prerequisite for any scheduled work (parked with Phase D). **v15:** the miss-assert still never fired across ms9 |
| 10 | Phase D prerequisites: `WalkStack`; `refs_only`/`mask` finalization; chain-head sourcing for parked, coordinator and blocked threads | D | **Parked in v14** with Phase D. Items 13 and 14 add two more prerequisites |
| 12 | **Opaque types: derive `traced` from the super's entry** in `declare_opaque` (`TracedOf` helper) | B2 | **Parked by decision; reminder carried.** Forward-declared super still inherits the `TRUE` placeholder; likely to arrive as imported partial reveals |
| 13 | **Aggregate root-slot addressing for a precise walker** | D1 | **Parked in v14.** Layout facts verified on LLVM 18.1.3 (Phase D, parked): metadata roots first, contiguous, scalars after at 8-byte alignment, frame map has no sizes. Preferred form if ever needed: address roots |
| 14 | **Root walker tolerates non-heap roots** (static text literals; caller dope addresses) | D1/C | Skip addresses outside the traced heap; applies to any precise walker. Not needed while roots are conservative (the collector's `NoteStackLocations` already ignores non-heap words) |
| 17 | **Phase C stages 2–3 (v11 numbering):** validate each stopped thread's published chain, then walk it | C→D1 | **Parked in v14** (precise roots not pursued). Note that v13 to v15 reuse the words "stage 1", "stage 2" and "stage 3" for the conservative pinning, ms8 and ms9 harness stages |
| 25 | **Pinning of LLVM roots** — new in v12; split in v13; **25b parked in v14** | C | **25a ✅ conservative scan, done and validated** (Phase C). **25b (chain walk) parked by the v14 decision**: the whole-stack scan is the mechanism, gcroot slots being in the scanned range (wasm32 harness). Revive only on the re-open conditions in "Decision (v14)" |
| 68 | **Chain-head restoration after a longjmp** — new in v17; **parked with Phase D** | E / D | The collector never reads `stack_chain` (conservative range scan), so a stale head is harmless today. Needed only if a precise walker is built: save `llvm_gc_root_chain` in an alloca before each `setjmp`, store it back on a nonzero return, in the LLVM back ends only (M3C untouched). |


**Parked (v17):** the chain-head restoration (68) with Phase D. **Parked:** none of the v15 parked items changed; nested procedures on wasm32 were unparked in v16 (B1). **Parked (v14):** precise stack roots (13, 14, 17, 25b, 10, Phase D).

**Deferred:** `superType` sprint; `BITS N FOR T`; sysroot problem for `wasm32-unknown-wasi`;
`BuiltinTypes.KindUID` adoption.

---


### 2.4 Closed items

| # | Item | Phase | Notes |
|---|---|---|---|
| 1 | ✅ **Parameter rooting** — closed in v10 | B1/B2 | `m3t`, size, align and `inProc` now flow from `declare_param`'s `LvVar` into `NewVar` in `begin_procedure`. Verified by IR inspection; v14: the audit shows no parameter value is used across a safepoint |
| 2 | ✅ **Loop-edge safepoint polls** — closed in v11 | B1 | Poll on the taken side of every back-edge; `EmitSafepointCheck`'s flow block is the continuation. Run through six generated test procedures in v11 |
| 4 | ✅ **`LLVMVerifyModule`** before the output step — closed (a couple of sprints before v12) | B1 | The user invoked it; catches the invalid-module class early. **(v15)** The verifier error behind register 47 (`llvm.gcroot` on a non-pointer alloca) is of this class |
| 7 | ✅ **WTHREAD codegen through `m3llwasm` for the x86_64 target** — closed in v11 | B1→D | Six generated test procedures ran under the WTHREAD thread harness on x86_64; fairness held, `LockHeap` nested locks did not regress, all tests passed |
| 16 | ✅ **Shadow-stack lowering's invoke rewriting, `gc_cleanup` pad and `__gcc_personality_v0`** vs `__m3_personality_v0` — closed in practice in v17 | E | Observation only; settle when exception handling is picked up **(v16)** Now has a practical edge: the sjlj lowering, WAMR's exception-handling support and the unwinding choice are one question (register 51). **(v17) Closed in practice:** call-site `nounwind` on M3 calls removes the `invoke`s; in a function with `setjmp` the lowering is run first, inside `m3llwasm`, before `llc`'s sjlj pass ("Exceptions on wasm32"). The fate of the unattached `__m3_personality_v0` was not examined. |
| 18 | ✅ **`stack_chain` initialisation** — closed for `nthr_create` | A | `nthr_create` sets `ctxt->stack_chain = NULL`; `nthr_default` also, and both zero `regs` and clear `ended` |
| 20 | ✅ **Nexus and context layout** — closed 2026-10-22 | A/B1 | `{safePoint, safeSyn, watchSyn, parked, forkList, forkSyn}` agrees with LLVM's layout of `{i32, lock, lock, i32, ptr, lock}`: x86_64 offsets 0/4/16/28/32/40, size 56; wasm32 0/4/16/28/32/36, size 48. `CompileSafepoint` declares the nexus shape and the context type with the appended `regs` (six pointer-sized elements) and `ended` (`i32`) |
| 21 | ✅ **`nthr_vigil` publish and re-check** — closed 2026-10-22 | A | Re-check after the restore is in place (Phase A addendum 2). Publish: `nthr_vigil` calls `nthr_arch_stack32` and refreshes `stack_chain` before the exchange, when it is eligible to wait. When the target is already detached it only reaps. Needed by `InitialThread`, where the default thread sits in the join for the life of the program |
| 22 | ✅ **Startup ordering for the default thread** — closed 2026-10-29 on evidence | A→D | Shape: `WThread.InitialThread` with the `Init`/`Axis` design of 2026-10-24. Evidence: collections run in the main thread before any harness code forks a thread, without failure (also in the ms8 and ms9 runs). The v12 checklist is the place to look if an early collection ever fails |
| 24 | ✅ **WTHREAD as a native, traced object type** — done in v13 (`beta.17`, `beta.18`) | A→C | `pkg/neocore` builds `Thread.T` on WTHREAD; `ms4`, `ms7`, `ms8` and `ms9` run `Fork`/`Join` with traced allocation under the collector, with an early collection at startup. `WThread.m3` contains no `DISPOSE` statements |
| 26 | ✅ **`ProcessStacks` passes `regs` to the collector** — done in v13 | C | `ProcessStacks` calls `p` on `regs` for every non-detached thread, and the coordinator calls `thread_stack32()` on itself first. No `regs[]` hit has appeared in the `ms7`, `ms8` or `ms9` runs, so the path is exercised but a register-held pin is not yet demonstrated (46) |
| 29 | ✅ **Build wiring for the `.s` files** — closed 2026-10-22 | build | Done: the compiler driver scripts were adjusted and the x86_64 instance builds. Policy stays: `-matomics` in the wasm32 script only; link flags per "wasm32 build flags" **(v16)** The wasm32 assembler file (`nthr_wasi.s`) assembled, linked and ran: `wasi_thread_start` to `nthr_start32` appears in the `ms10` profile. |
| 32 | ~~Update `claude/wasm32-resume-notes.md`~~ — withdrawn 2026-10-22 | docs | The notes file was an interim for an earlier chat; this plan carries everything needed |
| 33 | ✅ **`nthr_lock` safe-region lock and the watch-transition rules** — new and closed in v13 | A | Phase A addendum 3. Review every new blocking primitive against that table |
| 36 | ✅ **`nthr_arch_reap32` on wasm32 waits in a loop on `ended`** — new and closed 2026-10-29 | A | Belt and braces: `while (ended == 0) wait32(&ended, 0, -1)` with an acquire load |
| 38 | ✅ **The collector pins its own highest page** — accepted 2026-10-29 | C | Phase C. The collector stays unmodified; the pass rules account for it; optional confirmation by moving the flip loop into its own procedure. **v14:** reproduced in every ms8 run (the aligned hit page rises with the heap, and plateaus when the heap is capped); four of the six stays in the final run |
| 39 | ✅ **Extend `ms7`: embedded `REF` fields** — **done in v14 as `ms8`** | C | See Phase C, stage 2. The remainder of the old list moved to item 46 |
| 45 | ✅ **`-O0` spill-slot residue pins** — explained and accepted in v14 | C | Stale pointers in unnamed spill slots of the subject's own frame pin the last-iteration referents; absent at `llc` -O1+ (no spill slots). Remedy for harnesses: helper procedures (Phase C rule 8). An accepted pin class, like register 38 |
| 47 | ✅ **`ClassifyVar`: a Scalar root must be a pointer-represented variable** — new and closed in v15 | B2 | `LLVM_WASM.m3`: `ClassifyVar(self, v)` wraps the pure `ClassifyTrace` and returns `None` for a Scalar result on a variable whose `type` is not `Type.Addr`; `AllocVar` calls it. Cause: `New.m3` `GenOpenArray` declares the 24-byte dope temporary of an open-array `NEW` with the `REF` UID, so it classified `Scalar` and `llvm.gcroot` was issued on a struct alloca (verifier error `%tmp.412`). `m3llhost` and the front end are untouched. Re-run the audit on a build with open-array `NEW` (42) |
| 51 | ✅ **Real `setjmp`/`longjmp` on wasm32: exceptions that reach a handler** — new in v16, **closed in v17** | E (pulled forward) | The back end emits `_setjmp` for every `TRY ... EXCEPT` and for a FINALLY body containing EXIT/RETURN, and `CsetjmpC.c` calls `_longjmp` to unwind; an ordinary `TRY ... FINALLY` is a handler frame and uses no `setjmp`. The placeholders (`WasiCstd.c`) make `_setjmp` return 0 and `_longjmp` print a message and abort, so a `TRY` body runs but any exception raised to a handler stops the program. wasi-libc has no implementation unless built for the exception-handling proposal with `-mllvm -wasm-enable-sjlj` (and its `setjmp.h` requires `__wasm_exception_handling__`, hence `-mexception-handling` in the C flags). One `llc` experiment with `-wasm-enable-sjlj -exception-model=wasm` produced Emscripten-style `saveSetjmp`/`testSetjmp` calls, so the lowering expects runtime support behind it. Options, not decisions: (a) EH proposal plus sjlj lowering with a runtime for it, and WAMR built with its exception-handling option (name from memory: `WAMR_BUILD_EXCE_HANDLING`, unverified); (b) native wasm EH generated by `m3llwasm` for `TRY` (belongs with Phase E and register 16); (c) a mechanism without `setjmp`. Needed before library code that raises (for example `Rd.EndOfFile`) is used. **(v17) Closed:** option (a), LLVM 22 `-wasm-enable-sjlj` with legacy wasm EH on WAMR 2.4.5 (with the local thread patch), implemented and validated by `ms13` and `ms14`; names `setjmp`/`longjmp`, `-lsetjmp`, call-site `nounwind` and the pre-lowering are in "Exceptions on wasm32 (v17)". The `WAMR_BUILD_EXCE_HANDLING` option name from v16 was right (the migration checklist uses it). |

### 2.5 Changed and new in v19 (proposed)
- **Closed this session:** 62 (nested procedures, `ms16`), 66 (worker-thread uncaught exception, `ms15`), 67 (`jmp_buf` size and alignment), the sizing rule for 41, and the clean failure at the link ceiling (41, 49); **81** (the startup race above); **65** (collector cost on wasm32: the cost was the WAMR interpreter; about 4 times native on Wasmer, 2026-11-26, one heap size, with the optional experiments in `collector-cost.md` no longer needed); **44** is met on Wasmer too (`ms9` 200 of 200). The rows above are v18 text and are updated here, not in place.
- **77** Wasmer (exnref) is the primary engine; re-check WAMR-era results against it. **(2026-11-26)** Done for `ms9` (200 of 200), `ms14` and the collector cost (65). Not repeated on Wasmer: `ms4`, `ms7` and `ms8` (x86_64 stages) and the other WAMR-era wasm32 probes.
- **78** `RTException.DumpStack` gives no M3 stack dump on wasm32.
- **79** Footprint differs between targets (`Traced 458752:131012` on wasm32 against
  `327872:16` on x86_64 in `ms15 ok`); the second number is free bytes, not investigated.
- **80** `llvm18wasm` parity (64) re-filed as future work: only needed if LLVM 18 stays supported.
- **81** *(new and closed 2026-11-26)* **Startup race: the original thread's stack is not published before the main thread can collect.** `ASSERT ring.context.stack_ptr # NIL` in `WThread.ProcessStacks` (`WThread.m3` line 772 in the user's tree), exit 129. Seen once in 215 Wasmer runs of `ms14` (LLVM 1 of 105; Cranelift 0 of 105; default 0 of 5; `ms9` 0 of 200); the trace ends `nthr_start32`, `RTLinker__AddUnit`, the program's main thread, collecting. **Cause.** The program is not single-threaded: `Init` makes the original thread slot 0 of the ring (`nthr_default`: watch `relief`, `stack_ptr` zero) and `InitialThread` runs the program's main on a second thread while slot 0 waits in `thread_vigil`. A thread publishes `stack_ptr` only when it parks, waits, blocks on a contended lock or enters `thread_vigil` (`nthr.c`: `nthr_wait`, `nthr_lock`, `nthr_park`, `nthr_vigil`), and `SuspendOthers` waits only for `vigilant` threads, so a `relief` thread is neither waited for nor given a stack range. If the main thread's first collection began before slot 0 reached `thread_vigil`, `ProcessStacks` met slot 0 with `stack_ptr` NIL and asserted. A collection racing a raise was considered and rejected: the coordinator's own entry is written by `thread_stack32` immediately before the walk, and a raise touches only the exception chain. **Confirmed** (the user, 2026-11-26) by widening the window: a busy-wait of 50 million iterations in `nthr_create` after the spawn made `ms14` fail 25 of 25 on Wasmer. **Fixed** by one call, `thread_stack32()` in `InitialThread` before `thread_create`, so the original thread publishes its own stack before the child exists (`pkg/neocore` only; patch `InitialThread-publish-stack.patch`). With the delay still in: 30 of 30 pass. With the delay removed: 275 of 275 pass (25 by hand, then 250 in loops). The invariant to keep: every thread in the ring must have a valid published `stack_ptr` from the moment it can be seen by a collector, not only from its first park. This is the case register 22's evidence did not reach (collections before any thread was forked). The `ms14` batch on both backends was not repeated after the fix.
- **82** *(new 2026-11-26)* **`ms9` needs a 128 MiB link ceiling.** Linked with `-DMAX_MEMORY=134217728` it passes; at the default 32 MiB it dies in `pageTest` with an uncaught runtime error from `NEW` (`AllocateTracedRef`), exit 129. This is the bounded-heap behaviour of 41 and 49, not an engine fault; `ms9`'s link maximum was not recorded before (see 41 and 44).
- **83** *(new 2026-11-26)* **The first `NEW` triggers a collection on wasm32 and not on x86_64.** `ms14`'s `make50` takes about 1,000 microseconds on Wasmer (126,328 on WAMR) against 4 on native. Not investigated; harmless at the present collect cost.

---

## 3. Design elements

### 3.1 Principles (heuristics and guidelines; draft list)
1. The x86_64/`m3llhost` baseline is frozen; wasm32 code is fenced (`unix/WASI`, `neolib/os/WASI`), not `#if`-guarded in shared headers.
2. Roots are conservative; `RTCollector.m3` stays unmodified and byte-identical in `neocore` and `neosys` (Decision v14).
3. No IR-level optimiser until Phase O's entry criteria are met.
4. Heuristics before precision: an empirical premium on expected memory is enough; no decimal-place models.
5. One variable per experiment; keep stdout and stderr.
6. Tests that are silent on success get a negative control.

#### 3.1.1 Standing principle: the baseline is frozen (verbatim from v18, lines 90-185)

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
- **(v16)** Entry-point generation for wasm32 is decided **at generation time** by comparing `Target.System_name` with `"wasm32"`; the x86_64
  generated text carries no preprocessor condition and is unchanged. Two alternatives were rejected: a `#if defined(__wasi__)` in the generated
  source (it changes what x86_64 generates), and a test of the back-end mode (`m3llwasm` is also used with an x86_64 target for the WThread tests).
- **(v16)** wasm32-only sources are **selected by the build** (`unix/WASI`, included from the `unix` makefile under `equal (TARGET, "wasm32")`),
  not guarded by `#if` inside shared files; the wasm32 `m3core.h` is a separate file registered only for wasm32.
- **(v17)** **The C back end (M3C) is part of the frozen baseline and the LLVM back ends conform to it.** The FINALLY-handler convention was settled by
  changing all four LLVM back ends (keep the nameless formal, pass a NIL placeholder on direct calls), not M3C and not a second `RTExFrame`.
- **(v17)** wasm-only behaviour in shared files is **selected by the target's name**, never by a change that alters x86_64 output: `Target.Init` takes the
  `setjmp` name from a test on `"WASM"` in the system name (the existing C-backend and Solaris branches are untouched); `CsetjmpC.c` extends its existing
  "no signal mask" branch with `__wasm__`.

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
unchanged. **(v16)** The first wasm32 build followed this: the dedicated header and the C placeholders live in `unix/WASI`; the `neocore`
makefile registers the original `m3core.h` only for non-wasm32 targets.

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
**(v17)** The shared files touched by the exceptions sprint, each a named decision: `Target.m3` (the wasm `setjmp` name), `CsetjmpC.c` (`__wasm__` uses `longjmp`),
`WasiCstd.c` (the `_setjmp`/`_longjmp` placeholders deleted), and `RTExFrame.m3` (**back** to the original; `pkg/neocore` and `pkg/neosys` are identical again).
**(v16)** The shared files touched by the first wasm32 sprint, each a named decision: `RTExFrame.m3` (the `FinallyProc` arity and `CallProc`; applied in `pkg/neocore` only, `pkg/neosys` untouched, register 54), `MxGen.m3` (a wasm32 branch in both entry generators), `etc/Unix.common` (the `llvmback_features` hook, empty by default) and `nref.c` (the 64 KiB `sbrk` granule, meant to take effect on wasm32 only; confirm the guard in the user's tree). The `LLVM_WASM.m3` changes are in the wasm32 backend itself.

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


### 3.2 Working rules (prescriptive; numbered 1 to 20 as in v13 to v18, with the example that produced each)

Rules 1 to 13 come from Phase C's harness work, 14 to 17 from v17, 18 to 20 from v18. Numbering is stable.

| # | Rule | Where it came from |
|---|---|---|
| 1 | Detect pinning with a precise global reference to the same object, seen through a disguised address. | A stack copy cannot fail: conservative roots are never rewritten (`ms7`). |
| 2 | Give each tracked object its own page. | `obj` carries about 40 KB so only one fits on a 64 KiB page; an early version had assumed a 4 KiB page. |
| 3 | Do not let the logger hold the answer. | The logger thread's locals pinned the page of the last object it printed (`ms7`; a stale slot still pinned one referent in `ms8`). |
| 4 | Scrub stale stack residue between cycles. | Dead frames, old slots and callee-saved registers hold old pointers; scrubbing reaches only memory below the caller's frame. |
| 5 | Take the baseline only after the allocators have exited; match log lines to collections by `WThread.GC`. | `ms7` positions were compared before `movTest` and `ctlTest` had finished. |
| 6 | One variable per experiment. | The fixed-heap run changed two things at once and cost a detour (`ms8`, v14). |
| 7 | Capture both stdout and stderr. | A log of the heap statistics alone meant the capture, not the program, had failed. |
| 8 | Keep loops that handle tracked references in helper procedures, passed the owners by `VAR`, with a `scrubStack` after each call. | The `-O0` spill slots of the last iteration pinned the referents (register 45); they now die with the callee frame. |
| 9 | Keep small allocations off the array under test (`burnPage`). | A small object sharing a 64 KiB page with an array pins it (`ms9`). |
| 10 | Do not pass the array under test through a long-lived formal. | `triMulti^` as the actual of a `READONLY` open-array formal left a dope temporary with an interior pointer in the caller's frame (`ms9`). |
| 11 | To see a referent move when its container is pinned, log the referent. | A pinned `impMulti` never changed address; `impElem` showed the filler leaf behind it moving. |
| 12 | Check identity across rows as well as content. | A freed page keeps its old bytes until reused, so a stale pointer can pass a content check. |
| 13 | Pause before closing the logger and before the joins. | `Loque` is asynchronous; the last lines (`joined`, `mainMS9 END`) were lost. |
| 14 | A change is not done until the patch file has been delivered. | A description of a change the user cannot see is not a change (v17). |
| 15 | A test that is silent on success needs a negative control. | Break one assertion once and see it fail with a nonzero status before trusting the pass (`ms13`, and `ms16` with `r = 4124`). |
| 16 | Each LLVM back-end option passed through clang needs its own `-mllvm`. | Without it clang reports `unknown argument`; the unused-argument warning at the link step is harmless. |
| 17 | Temporary diagnostics go in patch files that are reverted before a checkpoint. | Three were used in the exceptions sprint and none is committed (v17; also the `RTCollector.m3` trace). |
| 18 | Size a fixed-time harness's work per stage to the slowest engine it runs on, and measure the stage lag. | `ms9`'s `checkMulti` did about 32 million byte compares per call and fell two stages behind under the WAMR interpreter (register 72). |
| 19 | A comparison between builds is valid only for the factors the build log shows were switched. | Confirm with `-commands` that every component went through the intended path (the first x86_64 collector comparison did not isolate the library). |
| 20 | Snapshot `/usr/local/m3neos` before swapping a library flavour. | The installed tools link `libneocore.so` dynamically; a WThread `neocore` made `m3llwasm` segfault (register 74). |

**Candidate from this session (not yet adopted; the user decides).**
- **21.** A wrapper or sweep script is part of the experiment: run it once on a known-good case before reading anything into its results. (The first `sweep.sh` and the `timeout` runs cost most of a session.)
- **22.** *(proposed 2026-11-26)* Confirm a suspected race by widening its window deterministically before fixing it, then apply the fix with the delay still in. (A busy-wait after the spawn turned a one-in-215 failure into 25 of 25, and the fix passed 30 of 30 under it: register 81.)

### 3.3 Lessons by phase (pointers; chronology is in [`dev-plan-changelog.md`](dev-plan-changelog.md))
- **A:** the watch-transition rules and the memory-ordering table, and why `nthr_lock` exists: [`phase-a.md`](phase-a.md), addendum 3.
- **B:** entry-block discipline, the marker workaround, the thread-local chain and the derived-copy rule: [`phase-b.md`](phase-b.md).
- **C:** the pin classes, the bounded-heap bound, and the harness rules behind 3.2: [`phase-c.md`](phase-c.md).
- **E:** the setjmp names, call-site `nounwind`, the pre-lowering and the FINALLY convention: [`phase-e.md`](phase-e.md).
- **L:** the bring-up trap-and-fix chain and the wasi-libc and `wasm-ld` facts: [`phase-l.md`](phase-l.md).
- **Cost and engines:** [`collector-cost.md`](collector-cost.md) and [`wamr-record.md`](wamr-record.md) (engine-specific; re-check on Wasmer).
- **Build:** flavours, the installed library and the flags: [`build-and-flags.md`](build-and-flags.md).

## 4. Phase O: optimiser enablement (future, unscheduled)
*Detail: [`phase-o.md`](phase-o.md). Register: 43.*

The pipeline has no IR-level optimiser, and the root scheme is correct only without one: `llvm.gcroot` keeps traced values in memory, but nothing else would stop an optimiser promoting them. Enablement is to be driven by measurement of code that dominates a representative program (for instance the front end compiling a file), and correctness comes first. For orientation only: `-O0` to `-O2` is about two to four times on tight scalar loops in one published library and much less on call-bound code, and gcroot costs about 1.5 ns per call of a rooted function on x86_64. Earlier wasm32 timings came from WAMR's interpreter; Wasmer compiles, so the case for optimising needs re-measuring on it before any judgement.

Entry criteria, all required:
1. Every traced value live across a safepoint has a memory home an optimiser cannot remove: scalars and traced temporaries gcroot'd, aggregates and fixed arrays of references rooted by address roots with null metadata (including the open-array `NEW` dope temporary and the `VALUE` copy slot).
2. The audit gate shows zero not-homed pairs on the optimised IR, and the wasm32 visibility harness passes at the chosen pipeline.
3. The two shadow-stack LLVM bugs are re-checked at the chosen levels, or fixed upstream.
4. `ms8` and `ms9` are rerun at the new pipeline as a one-variable experiment.
5. A measurement shows the optimiser gains enough on representative code to justify the extra rooting.
6. Values modified after a `setjmp` and read after the `longjmp` stay memory-resident; re-run `ms13` and `ms14` at the new pipeline.

## 5. Supplementary notes

- `claude/optimisation-and-visibility-analysis.md` — the wasm32 visibility harness (sources, results), the SSA-across-safepoint audit
  (method, controls, results on ms8 and on optimised IR), the `opt`/`llc` experiments, the gcroot cost measurement, the shadow-stack
  frame layout facts, the spill-slot analysis, the bounded-heap arithmetic, and notes on optimiser benefit.
- `claude/audit.py` — the audit script. **(v18)** The patched version (by-value aggregate exemption, violation check, parameter parsing; register 73) replaces the project copy at this checkpoint; the repo copy is `test/src/n0/ms8/audit.py`.
- `claude/dev-plan14.md`, `dev-plan15.md` — earlier editions, kept for reference (v16 is not in the project; v17 is in the project and in the repo as `doc/dev-plan17.md`; this v18 carries it forward).
- `claude/wamr-eh-thread-fix.md` — **(v17)** the WAMR 2.4.5 exceptions-in-threads diagnosis, the local patch, and test results.
- `claude/llvm22-migration-checklist.md` — **(v17)** the LLVM 22 gates, the toolchain smoke test and the m3neos-side checklist (the status section dates from 2026-11-12; items there are now mostly done: see "Exceptions on wasm32").
- `claude/wamr-build-notes.md` — the WAMR build-side findings. **(v16)** It does not yet record the diagnostic build options (Debug build, call-stack dump, name section, classic interpreter) or the profiling flags that were then switched off, nor the stale-cache rule for the `-C` file; worth adding.
