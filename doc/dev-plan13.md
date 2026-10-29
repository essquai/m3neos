# Incremental Development Plan: wasm32 Threading, Safepoints, GC Integration, and the Core Library

**Plan v13 — checkpoint 2026-10-29**

**Scope:** CM3-derived Modula-3 compiler. The x86_64/Linux target, via the `m3llhost`
backend and the existing PTHREAD runtime module, is an **already-working baseline**.
This plan covers only the **new work required for the wasm32 target**, built through
the new `m3llwasm` backend and a new `WTHREAD` (`WThread`/`nthr`/`nsyn`) runtime
module, and (new in v12) the work to bring the Modula-3 core library up on wasm32. Since v13
the WTHREAD runtime is also wired into m3neos as `pkg/neocore` (an `m3core` built on `WTHREAD`,
x86_64 for now, next to the PTHREAD-based `pkg/neosys`); that build is the vehicle on which
stop-the-world and pinning are tested under the real collector.

**Revision note (this version, v13):** v13 closes the **wiring and pinning sprint**. WTHREAD is
now the thread implementation of a second `m3core` build, `pkg/neocore` (tag `beta.17`, extended
in `beta.18`); real traced programs run on it on x86_64; and `ProcessStacks` pinning has been
validated against the existing, **unmodified** collector. Nothing from v12 is dropped; sections
are updated in place.

- **WTHREAD is wired into m3neos.** `pkg/neocore` is an `m3core` built with the WTHREAD thread
  package integrated with `Mutex`, `Condition`, `Thread.T` and the rest; `pkg/neosys` stays the
  PTHREAD build, and both can be linked side by side, because the thread implementation affects the
  whole `m3core` linkage (stop-the-world, `Mutex`/`LOCK` hooks). The startup shape was settled on
  2026-10-24: the nthr context becomes an untraced ref record, paired with an untraced `Axis`
  record owned by `WThread.m3` (`threadSyn`, fork-ring links, heap and float state, a pointer to
  the `Thread.T`); the pair is allocated in `Init` for the default thread, the `Thread.T` is linked
  at `InitialThread`, and `Fork` allocates the `T`, the context and the `Axis`. `thread_context`
  replaces `thread_self`; `nthr` owns stack and TLS allocation and free. In substance this closes
  registers 22 and 24.
- **`nthr_lock`, a safe-region lock (new "Phase A addendum 3").** A thread that blocks on a lock
  is `deferred` while it waits, so a stop-the-world does not wait for it, and it publishes its
  stack and chain first. A `no_park` mode exists for the heap lock's recursive mutex, which must
  never park.
- **Watch-transition rules restated.** The first version of `nthr_lock` left `vigilant` outside
  `watchSyn` without a broadcast; the coordinator then slept forever (a lost wake-up, reproduced as
  a hang). The rules are now written down in one place (addendum 3) so that every new blocking
  primitive is checked against them.
- **Heap-lock invariant recorded.** `SuspendOthers` is called only with the heap lock held. A driver
  that broke this produced the `NOPARK` abort; that driver was withdrawn. Two known paths
  (`After`, `VisitAllRefs`) still call it without the lock (register 34).
- **`ProcessStacks` implemented and pinning validated (Phase C).** Whole-stack ranges plus the
  `regs` array of every non-detached thread go to the unmodified `NoteStackLocations`. The `ms7`
  harness shows that unreferenced objects move at every collection and that objects referenced from
  a thread stack stay put, at page granularity, and are released when the reference is dropped.
  Stage 1 only: no type maps, no `REF` fields.
- **The collector pins its own highest page.** Found with a per-hit trace and attributed to a
  page-aligned word in the coordinator's own frame. Cost: at most one page per collection. **Accepted
  and left unfixed.**
- **Principle extended.** The collector is part of the frozen baseline: `RTCollector.m3` stays
  unmodified, and is byte-identical in `pkg/neocore` and `pkg/neosys`. See "Standing principle".
- **Evidence this sprint.** All runtime evidence is from the user's runs on x86_64 under
  `pkg/neocore` (the `ms4` driver and the `ms7` harness; the logs are listed in Phase C). My part was
  review and log analysis (scripts that decode the disguised addresses and cross-reference the hit
  traces); I did not build the m3neos tree. wasm32 and WAMR were not exercised this sprint
  (registers 30–31 stand).
- **Road ahead.** Immediate: extend `ms7` with embedded `REF` fields in a record and in an object
  (type maps enter the picture). Then the remaining Phase C work (chain-walk pinning, register 25b),
  the small leftovers (registers 27, 34, 35, 37) and Phase L. See "Near-term sequence".
- **Register:** all earlier numbers are stable. Closed or updated at this checkpoint: 19, 22, 24, 25,
  26, 28. New items are 33–40 (33, 36 and 38 were closed on arrival).

**Previous revision note (v12, condensed):** v12 closed the nthr/nref review sprint: exit, join and
reap were redesigned (the exiting thread signals under `joinSyn`; `nthr_vigil` releases `joinSyn`
around `nthr_arch_reap32`, a new arch hook that is `pthread_join` on x86_64 and a wait on a dedicated
`ended` flag on wasm32); the context layout was settled (`regs` as `uintptr_t regs[NREGS]`, zeroed and
scanned as conservative roots; `ended` last; `thread_match` first in `WThread.Init`); the safepoint
re-check ordering was decided (Phase A addendum 2); `nref` size options accept `K` and `M`; the wasm32
target triple became `wasm32-wasi-threads` and `CompileSafepoint`'s context type gained `regs` and
`ended`; the libc-surface survey produced Phase L (the core library on wasm32, before Phase E); and the
road ahead was re-ordered (traced `WThread.T`, then Phase C pinning). Register items 23–32 were new;
4, 18, 20, 21, 22, 29 and 32 were closed or updated. Evidence was from trimmed copies of `nthr`/`nsyn`
in my harnesses (x86_64: 20,000 create/join cycles in 6 of 6 runs; wasm32 under node with real worker
threads); WAMR had not run them (register 31).

**Previous revision note (v11, condensed):** v11 recorded the stop-the-world and parking work:
publish-order race, missing state restore after a poll-initiated park, lost wake-up (park waited
on an event instead of the condition), tail race in `nthr_wait`, and starvation under a
collection storm. Adopted design: `safeSyn` is both mutex and condition for parking; a `parked`
counter drains the previous stop before the next may begin; `dangerSyn` retired; `parkSyn`
renamed `watchSyn`. Loop-edge polls (register 2) and WTHREAD codegen through `m3llwasm` on
x86_64 (register 7) were closed; Phase C stage 1 was harness-validated; register items 17–22
were added.

**Previous revision note (v10, condensed):** v10 closed parameter rooting (real `m3t`, size,
alignment and `inProc` on parameter slots in `begin_procedure`; value parameters of traced types
are scalar roots), corrected B1.4 (park iff `watch >= vigilant`), added the LLVM
root-initialisation rule to B1.2, closed objects (scalar roots; fields reached through the header
typecode), moved the open-array VALUE parameter copy to the arrays sprint, and parked the
opaque-type `traced` fix (register 12, reminder carried). Provenance: v9 merged the v8 lineage
with the interim checkpoint `alt-inc-plan.md` (Phase B1 on x86_64).

Carried forward unchanged in substance: `BITS N FOR T` packed fields (deferred), the
`superType` correction sprint (deferred), the `BuiltinTypes.KindUID` future note, the
`refs_only`/`gc_map` finding and the Phase D `WalkStack` notes, the target-description
rename and datalayout findings, nested procedures on wasm32 (parked), and the
frozen-baseline principle.

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
`NoteStackLocations`) are temporary and are reverted before a checkpoint. The accepted consequence
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

Any future decision that would touch `m3llhost`, `TipeMap`, or any other
x86_64-shared machinery — however small — should be checked against this principle
first.

---

| Status | Item |
|---|---|
| ✅ Reused, revised in v11 | `SuspendOthers` / `ResumeOthers` (WTHREAD only; PTHREAD untouched): same bracket, protocol revised — see the Phase A addendum. |
| ✅ Confirmed by build config | Target exclusivity via `TARGET=wasm32`/`M3_BACKEND=Wasm` — unchanged. |
| ✅ Resolved (Phase C) | Shadow-stack root feeding via `RTThread.ProcessStacks` reusing `NoteStackLocations` unmodified — unchanged; per-thread chain head published at park time (see B1.5). **v12:** pinning of the objects the roots reference is an explicit Phase C deliverable. **v13:** the conservative half (25a) is implemented and validated; the chain-walk half (25b) is not started. |
| ✅ Complete, tested (Phase A) | WTHREAD thread lifecycle, cooperative `SuspendOthers`/`ResumeOthers`. Parking protocol revised in v11. **v12:** exit/join/reap protocol revised and verified in my harnesses (trimmed copies; x86_64 and wasm32 under node) — see the Phase A addendum 2. **v13:** `nthr_lock`, the watch-transition rules and the heap-lock invariant recorded — see the Phase A addendum 3. |
| ✅ Implemented, validated on x86_64 (Phase B1) | Safepoint check emission (park iff `watch >= vigilant`); gcroot frame scaffolding (entry → prolog → body); aggregate-root marker workaround; thread-local `llvm_gc_root_chain`; loop-edge polls. **Not yet validated end to end on wasm32** (blocked on `Target.m3`, below). |
| ✅ Complete, verified (Phase B2) | `m3t` propagation chain; `ClassifyTrace` scalar/composite dispatch; composite `gcroot` metadata, byte-verified. `Gen_Call_indirect`/`Invoke_indirect` sourcing resolved. |
| ✅ Implemented, verified by IR inspection (Phase B2) | Parameter rooting (v10). **No runtime proof yet** — the collector is not wired (Phase D). |
| ✅ Closed (Phase B2) | Objects: scalar root; fields reached through the header typecode and the runtime type map. |
| ✅ Closed (v12) | **nthr/nref review sprint**: `regs`/`ended` layout, `thread_match`, join/reap protocol, safepoint re-check ordering, `nref` K/M suffix. Small leftovers are register 27–28. |
| ✅ Closed (v13) | **Wiring and pinning sprint**: WTHREAD wired into m3neos as `pkg/neocore` (`beta.17`/`beta.18`); startup shape (`Init`, `Axis`, `InitialThread`); `nthr_lock`; watch-transition rules; `ProcessStacks` implemented. Registers 22, 24 and 26 closed, 33 and 36 new and closed. |
| ✅ Validated (v13) | **Conservative `ProcessStacks` pinning, stage 1** (no type maps, no `REF` fields) under the unmodified collector, with the `ms7` harness: movement, selective pinning, release — Phase C. |
| 🅿️ Accepted (v13) | **The collector pins its own highest page** (register 38). At most one page per collection; the collector stays unmodified. |
| 🔶 **Next (v13)** | **Extend `ms7` with embedded `REF` fields in a record and in an object** (register 39); then the chain-walk pinning of LLVM roots, integration-tested against the conservative scan (25b). |
| 🔶 **New, before Phase E (v12)** | **Phase L — core library on wasm32**, two stages: (1) use wasi-sdk's libc as is; (2) backfill the system calls WASI lacks (register 23). |
| 🔶 Open (wasm32 enablement) | `Target.m3` generic wasm32 system; debug-info NIL element; remaining wasm32 attribute cleanup (waits on Phase L stage 1). (`LLVMVerifyModule` is done; the target triple is now `wasm32-wasi-threads`.) |
| 🔶 Open (upstream) | Two LLVM bugs to report (reproducers ready); WAMR issues to report (register 30). |
| 🔶 Open (Phase D prerequisites) | `WalkStack`; aggregate root-slot addressing; non-heap root tolerance (register 10, 13, 14). |
| 🅿️ Parked by decision | Opaque-type `traced` derivation in `declare_opaque` (register 12 — reminder carried). |
| 🅿️ Parked | Nested procedures on wasm32 (`nest` static-link attribute unsupported by the wasm backend). |
| ✅ Closed (2026-10-29) | Startup ordering for the default thread (register 22). Shape `WThread.InitialThread` with the `Init`/`Axis` design; early collections run at startup in the `ms7` runs without failure. |
| 🔲 Deferred, own sprint | `InitUids`'s `superType` fields (DWARF-correctness only). |
| 🔲 Deferred, scope | Fixed and open arrays (including the open-array VALUE parameter copy); `BITS N FOR T` packed fields; exception handling (Phase E). |
| 🔲 Future note | `BuiltinTypes.KindUID` — backend should consume the front end's computed builtin TypeUIDs instead of hard-coded `UID_*` constants. |

---

## Near-term sequence (rewritten in v13)

In order. Each step is a prerequisite for, or de-risks, the next. Steps 1 and 2 of v12 (the small
sprint leftovers' mechanical part, and the traced `WThread.T`) are done in substance; what remains of
them is in the register (27, 28).

1. **Extend `ms7` with embedded `REF` fields (register 39).** Add a `REF` field to the record and to
   the object. This is the first step that gives the collector a non-NIL `gc_map` to walk, so it is the
   first test of the type-map path under WTHREAD. Pass criteria, proposed: (a) the referent of the
   embedded `REF` is reachable only through the tracked object, moves with it, and the field is
   rewritten, so the graph is intact after every collection; (b) the conservative pins from stage 1
   still hold and are still released; (c) the highest-page rule (Phase C) still predicts every stay.
   Expect copy-page placement to change: records with a non-NIL `gc_map` stop going to the pure copy
   pages, so the page-sharing picture in the logs will differ from stage 1.
2. **Remaining Phase C (register 25b).** Chain-walk pinning of `llvm_gc_root_chain` roots for wasm32
   (the `ProcessStacks` TODO). The stage 1 conservative scan, now validated and instrumented, is the
   comparator: run both and compare the heap pages each pins.
3. **Small items, as convenient:** the heap-lock invariant for `After`/`VisitAllRefs` (34); the
   library poll policy, which must be settled before polls are ever enabled in library code (35); the
   unclaimed-thread reaper and the slot table (37); and the v12 leftovers (27, 28).
4. **Phase L, stage 1, then stage 2 (register 23).** Independent of steps 1–3 in the code it touches
   (core library, not collector), so it can be interleaved. It is what lets the front end build
   user-space programs for wasm32, and so unblocks the `Target.m3` and attribute items (3, 8).
5. **The remaining v11 steps, unchanged:** `Target.m3`, wasm32 attribute cleanup, Phase C stages 2–3,
   Phase D (D1–D4), then Phase E.

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
those printed as `Addr -1` carry no type and classify as `None`.

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

### wasm32 build flags (new in v12; reference)

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
  these. The maximum must be a multiple of 64 KiB and must match the host's memory.
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
module-based safepoint exemption) — unchanged, still required reading for Phase D.
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
the `ms4` or `ms7` runs (13 collections in the last `ms7` run).

---

## Phase B1 — Safepoint Check Emission (implemented, validated on x86_64)

**Position.** Phase B (wasm32 codegen and garbage collection), step B1 = the safepoint
poll, built over the shadow-stack root scheme. Implemented and validated on the
x86_64 `phb.ll`. Exception handling stays deferred to Phase E; x86_64 stays frozen apart
from LLVM-toolchain modernisation. The next big step for the compiler is producing the wasm32
target, which needs some tweaking first (register items 3, 8) and now depends on Phase L
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
`AllocVar` whenever `ClassifyTrace` returns anything other than `None`; composite
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
  published head is therefore valid only for a *parked* thread — see Phase D.
- Validated empirically on **both wasm32 and x86_64** in a separate session.
- A **thread-local intrinsic** was added to the backend's intrinsic set; it is needed
  for atomic accesses to thread-local variables.
- **TLS model.** `GeneralDynamicTLSModel` is set for the nthr variables in the x86_64 target
  condition, because the WTHREAD module is also built as a shared library (the
  `LocalExecTLSModel` alternative is commented out; both arms of the `isWasm` test currently set
  the same model). The chain declaration is kept alive against `opt` by a global named
  `llvm.compiler.used` holding `gcchainVar` (built with `LLVMArrayType`/`LLVMConstArray`);
  accepted as an escape hatch.
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

### B1 open items and parked

See the consolidated register. In short: loop-edge polls are done (v11); what remains is wasm32
enablement and cleanup.

**Loop-edge safepoint polls — implemented (closed in v11; recorded 2026-10-08).** The
function-entry poll alone does not bound time-to-safepoint for a call-free loop, so the
user added a poll on every back-edge. Codegen shape: a back-edge jumps to a **label already
placed**, so the poll goes on the **taken side** of the back-edge, and the flow block
returned by `EmitSafepointCheck` is the continuation. Exercised in v11 by six generated
test procedures with nested loops and IFs (B1.9).

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

### `m3t` propagation chain and `ClassifyTrace` — complete

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
`modRec` in `phb.ll` show this: no alloca, no spill.

**By-reference formals** (`VAR`/`READONLY` passed by address). Their `m3t` is the
`declare_indirect` UID, `−(referent + 1)`, and the slot holds an address. They classify
as `None` and are not roots. **The sign of a UID cannot be used to recognise them:**
legitimate UIDs can be negative (e.g. `TestB`'s `−814819607`), and the indirect UID of
a negative target is positive. They are handled correctly today because `declare_indirect`
registers a non-tracing entry in `debugTable` (inferred from the fact that
`ClassifyTrace`'s miss-assert never fires for them; confirm if `declare_indirect` is
touched).

**Root-ownership rules.**

| Storage | Rooted? | Why |
|---|---|---|
| Value parameter slot of a traced type (`REF T`, object, `TEXT`, traced opaque) | **Yes** — scalar root, null meta; the spill initialises it | The slot is the callee's own mutable variable and may hold the only reference to something (it can be reassigned). |
| Value parameter slot of a non-traced type (`INTEGER`, subrange, enum, proctype) | No | Classifies `None`. |
| By-reference parameter slot (`VAR`/`READONLY`) | No | Holds an address, not an object. The referent's owner roots it. |
| By-value record parameter | No slot in the callee | The caller's `pop_struct` temporary is the composite root. |
| Front-end temporary printed `Addr -1` | No | See the derived-copy rule below. |
| Open-array VALUE parameter | Deferred to the arrays sprint | See Deferred scope. |

**The derived-copy rule (audit rule for unrooted `Addr -1` temporaries).** An unrooted
temporary is safe only if a *rooted* holder of the same object spans every safepoint
over which the temporary is live. The check is made per temporary: find the rooted
holder (a local, a parameter slot, a global, or a field of a rooted object). The rule
also depends on stack-referenced objects being pinned, i.e. on Phase C's pinning
(register 25). Audited so far, at the current snapshot: `v.97`,
`v.100`, `v.101` (audited when first found) and `v.118`. `v.118` is the `Stdio.stdout` copy
in `phaseB` (`tmp.134`): it is loaded from the `Stdio` interface's slot, a
`CheckLoadTracedRef` call (a safepoint) follows, and then it is stored to the rooted local `w`.
The `Stdio.stdout` global holds the same object across that call, and `w` holds it afterwards.
This relies on module globals being scanned as roots (Phase C).

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
- **No runtime proof of rooting yet:** the collector is not wired, so the evidence is the
  generated IR.

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

### Composite `gcroot` metadata — complete

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
- `LLVMBuildAlloca`, then `ClassifyTrace(v.m3t)` → `None`/`Scalar`/`Composite`.
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
- **Unrooted copies need a rooted holder** (the derived-copy rule above). It is an
  audit made per `Addr -1` temporary, and the front end's temporary reuse can hide a
  violation.

### Still open, narrowly

1. Declaration-ordering assumption (`<*ASSERT FALSE*>` on a `debugTable` miss) — still
   never triggered across an increasingly large and varied test set; formally
   unverified.
2. Why `RTTypeMap.WalkRef` consumes `.type_map` rather than `.gc_map` at actual
   collection time, given `.gc_map` is the narrower, purpose-matched field. Doesn't
   block anything (the comparison methodology is valid regardless), but is unexplained
   and should be understood before Phase D's own walker is built.

### Deferred scope

**`BITS N FOR T` (packed fields).** Out of scope, and the reasoning bounds the risk
precisely rather than just deferring it: `BITS N FOR T` requires `T` to be ordinal, so
a packed field can never itself be a `REF`. It matters only for a *traced* record that
also contains an unrelated packed field elsewhere — the gap is entirely about
`TypeComp` correctly *stepping over* a packed field's bits when computing subsequent
offsets, never about a packed field being reported as a root. Fix when a real test
case surfaces it; not a correctness risk to anything currently in scope.

**Arrays.** `ArrayDebug`/`OpenArrayDebug` both carry `elt: TypeUID`, so classification
is structurally easy; *acting* on it differs sharply between fixed arrays
(compile-time-known count; could plausibly reuse `TypeComp`'s `Array_N`-family opcodes
once built) and open arrays (structurally incompatible with `gcroot`'s
one-root-per-alloca model; needs a different mechanism entirely). Open arrays can
nest (`.elt` can itself be an `OpenArrayDebug`), so any future recursive handling must
handle arbitrary depth, and multi-dimensional arrays add more sizes to the dope vector.

*The open-array VALUE parameter copy.* In `phb.m3`'s `number`, the
callee copies a VALUE open-array argument: the parameter slot (`oa1`) starts as the
address of the caller's dope vector, `RTHooks.AllocateOpenArray` makes a heap copy, and
the slot is then **re-pointed at the heap copy**. After that the slot is the logical sole
holder, yet the copy is rooted only through `tmp.66`, which the front end's temporary
pool may reuse. It is safe today because nothing allocates between the re-point and
`ret`. Because the dope vector gains more sizes in the multi-dimensional case, the copy
size and the re-point code will change anyway, so the fix belongs with the arrays work.
**Constraint to carry:** whatever holds the heap copy after the re-point must be rooted
for the whole body — either the parameter slot (the natural owner; it relies on the root
walker tolerating a non-heap address, since the slot holds the caller's dope address
until the re-point, as already required for static literals — register 14) or a
dedicated rooted temporary the pool cannot reuse. Related: open-array **dope-vector
temporaries** (`Struct -1`, e.g. `tmp.135` in `phaseB`, which holds `{ptr @M_Main+104,
i64 3}`) are unrooted and hold a raw data pointer; for a heap-backed array the holder of
the `REF` must span the call. Audit under the arrays work.

---

## Phase C — Shadow Stack Root-Feeding: Design (resolved), Conservative Pinning (validated in v13), Chain-Walk Pinning (not started)

`RTThread.ProcessStacks` presents each thread's stack to the existing, unmodified
`NoteStackLocations`. `stack_ptr`/`stack_top` argument-order pitfall is still the thing to get right
when Phase D writes the real loop. Composite roots have *real* metadata (not a placeholder) to
eventually walk precisely, once Phase D's own walker exists — see the `WalkStack` note below.

**What B1 adds to this phase's assumptions:** every root slot is either valid or null
by the time any thread can park. Scalar roots with no entry-block store are
null-initialised by LLVM's own lowering; a rooted parameter slot is initialised by its
own spill, which is the incoming value (B1.2); composite roots are zeroed by the prolog
memset, which precedes the poll (B1.3). The walker can therefore treat each slot as
valid-or-null without a "was this frame initialised yet" side channel. The per-thread
chain head is the **published copy made by `nthr_park`** (B1.5), not a live global.

**Assumptions the derived-copy rule (Phase B2) places on this phase:** stack-referenced
objects are pinned (via `NoteStackLocations`), and module globals are scanned as roots.

**Pinning of LLVM roots (v12; register 25), split in v13.** The user's position: `ProcessStacks`
should walk each thread's `llvm_gc_root_chain` and **pin the heap pages the slots point to**, the way
the collector's `NoteStackLocations`/`AddressToPage` path does for the conservative scan, with
diagnostics that account for every traced reference found. Without pinning the collector would
reclaim the pages and corrupt memory. v13 splits this into **25a, the conservative whole-stack scan
(done and validated, below)** and **25b, the chain walk (not started)**. The v12 plan for 25b stands:

- Keep the **whole-stack scan** as the mature reference/comparator: the harness runs both the new
  chain walk and the whole-stack scan and **compares the resulting heap-pointer addresses**. v13
  makes that comparator concrete: the per-hit trace described below already says, for every
  collection, which pages the conservative scan pinned, from which thread and slot.
- Scope for now: **scalar roots first** (records and metadata walking are out of scope for this
  step, consistent with register 17's "frames with `NumMeta = 0` first").
- Each root value may be a non-heap address (static text literal, caller dope address) — the pinning
  pass must skip those (register 14).
- The `ProcessStacks` source carries the marker `TODO: process this ring's llvm.gcroots on wasm32`.
  Whether wasm32 needs a small arch hook to publish a thread's chain (as `nthr_arch_stack32` does for
  the stack) is not established.

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
those (the first explicit `Collect` in the last run was number 8).

**How the unmodified collector uses it** (read from `RTCollector.m3`, which the user confirms is
unmodified):

- `Collect` is `FinishGC; StartGC; FinishGC`. `StartGC` sets `partialCollectionNext := FALSE` when
  the collector is idle, so **every explicit `Collect` is a major (full) collection**.
- At the start of a collection every page in the current space becomes `Previous` (the flip). Then
  `ProcessStacks(NoteStackLocations)` runs. `NoteStackLocations` reads every word of each range it
  is given; **any word whose value falls on a `Previous` heap page promotes that whole page in
  place** (note `AmbiguousRoot`). Pinning is therefore **page-granular**: the heap page is 65,536
  bytes (`RTHeapRep.BytesPerPage`), and every object on a pinned page stays, referenced or not.
- A promoted *impure* page is grayed whole (`GrayBetween`), so everything on it is treated as live
  and its referents are traced too.
- Objects whose page has `nb > 1` are large objects and are promoted in place, never copied.
- Survivors that are not pinned are copied. `def.kind = TK.Obj` goes to the impure copy pages even
  when `gc_map = NIL`; a non-object record or `REF` with `gc_map = NIL` goes to the pure copy pages.
  All OBJECT-kind survivors (`Thread.T`, `Mutex`, `Condition`, closures, the logger's queue and the
  test objects) therefore share impure copy pages, in root-traversal order (module globals first,
  array elements in index order). Free pages are recycled across collections.
- **Conservative roots are never rewritten.** A stack word holding an object address prints the same
  value whether the object was pinned or moved. Printing a stack copy therefore cannot detect a
  pinning failure; see rule 1 below.
- Module globals are precise roots: `RTHeapMap.WalkGlobals` walks each module's `gc_map` through
  `RTMapOp`. This is how the harness's `ARRAY OF obj` globals are found.

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
4. **Scrub stale stack residue** between cycles (`scrubMov`): dead frames, uninitialised slots of
   later frames overlaying old ones, and callee-saved registers all hold old pointers.
5. **Baseline after the allocators exit.** Take the pre-collection positions only once `movTest` and
   `ctlTest` have finished allocating, and match log lines to collections by `WThread.GC`.

**Results** (last run, log `5550bf2a`; collections 8 to 13 are the six explicit ones). `M` moved,
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
  collection.

**The diagnostics used** (the temporary per-hit trace; the user keeps the `WThread.GC` counter, parks
the `ProcessStacks` headers in a comment for reuse, and reverts `RTCollector.m3`). `ProcessStacks`
printed one header per call to `p` (`gc`, `tid`, `me`, `STACK` or `REG`, and the range; for `STACK` the
printed limit was a copy of the start, so offsets were taken from the start), and `NoteStackLocations`
printed one line per hit on a `Previous` page: the slot address (`fp`), the word (`fp^`) and the page's
note before promotion (0 Allocated, 1 Copied, 3 AmbiguousRoot). A first hit with note 3 means the
page was also pinned by the previous collection. Offsets in the page and the page number come from
`fp^` (`MOD 65536` and `DIV 65536`).

**Evidence trail** (logs in the user's runs; the order is the order of discovery):

| Log | Change | What it showed |
|---|---|---|
| `c4e5bb17` | first full `ms7`: three cycles, page allocations, logger, `WThread.GC` | review found the flaws behind rules 1–5 |
| `474d559e` | added the `int`/`rec`/`obj` controls and `ctrl` | `ctrl` shared pages with `mov`, which produced a regular "stay after a move" pattern |
| `1bc52e38` | `obj` gained the 40,000-byte array (one object per page) | the earlier regular "stay after a move" pattern disappeared |
| `52657199` | `logCtrl` order reversed | the stay stayed on the last array element: not caused by the order of logging |
| `b2433f36` | `ctrl` grown to four elements | the stay moved from `ctl3` to `ctl4` |
| `078a9d06` | scalar `tail` added after the array | stays on `tail` and on `ctl4`: not specific to arrays |
| `5550bf2a` | `ProcessStacks` headers and per-hit trace | cause attributed to the coordinator's page-aligned slot |

**Not covered by this stage** (open, in the order they matter): embedded `REF` fields in records and
objects, that is, non-NIL `gc_map` and impure placement (register 39, next); `ARRAY OF REF` on the
stack, `REF ARRAY` and open arrays; large objects (`nb > 1`); interior pointers from `VAR` and `WITH`;
a `regs[]` hit; and the chain walk (25b).

**Status.** Stage 1 of the harness plan — all mutator threads stop and stay stopped — was validated
in v11 by a C harness against the real `nthr`/`nsyn` (no Modula-3 runtime, untraced data): no mutator
ran during a stop, and every stopped thread's published `stack_chain` was current (0 stale reads in
6,000 per run). v13 adds the conservative pinning validation above, under the real collector and a
real Modula-3 program. Stages 2–3 — validate each stopped thread's published chain, then walk it
(frames with `NumMeta = 0` first) — and the chain-walk pinning (25b) are not started (registers 17,
25); D1 stays the real walker.

---

## Phase D — Wire Shadow-Stack Scanning Into the Coordinator

Unchanged in structure (D1–D4). Notes:

- **`RTTypeMap.i3` needs a small addition before D1 can call it: `Walk`/`DoWalkRef`
  are private to `RTTypeMap.m3`, not exported.** Resolution already agreed: add a new
  public entry point (`WalkStack(x, pc: ADDRESS; m: Mask; v: Visitor) RAISES ANY`)
  that calls the still-private `Walk` internally — deliberately *not* `WalkRef`, which
  does two things unsuited to a stack root: a `TYPECODE`/`RTType.Get` lookup that
  doesn't apply to a bare composite (no runtime typecode exists for one), and an
  unconditional `RTHooks.CheckStoreTraced` call — heap-page dirty-tracking machinery,
  category-confused against stack memory, which has no page descriptor or header for
  it to resolve at all.
- **The `refs_only` finding (Phase B2) is believed sufficient but needs finalizing
  here, not assumed.** `TypeComp`'s output only ever contains `Op.Ref`/`Op.Stop`. That
  likely makes `WalkStack`'s `mask` parameter a non-issue in practice, but this should
  be confirmed explicitly once D1's synthetic-heap test is being built, alongside
  resolving the still-open `type_map`-vs-`gc_map` question from Phase B2 — if the
  answer turns out to matter for correctness rather than being cosmetic, it must be
  resolved before, not during, D1.
- **Where the chain head comes from.** Parked threads: read the head
  `nthr_park` published in the thread context. The thread running the collection holds
  `relief` and never parks, so its own chain head is its live thread-local — to be
  confirmed in D1. Also to confirm in D1: threads inside **blocking primitives**
  (Phase A invariant 2) must also have a published head, i.e. that path goes through
  the same publish step as `nthr_park` — `nthr_vigil` now does (register 21, closed).
- **Aggregate root-slot addressing — open design question for D1 (register 13).** The
  walker needs, for each composite root, the *address* of its slot and its metadata. As I
  recall LLVM's shadow-stack contract (from memory, not re-verified), the per-function
  `FrameMap` carries the root count, the metadata count and the metadata pointers, but no
  per-root sizes or offsets, and the frame entry is a concrete struct whose members are the
  allocas' own types, so an aggregate's address depends on the struct layout including padding,
  which the runtime does not see. Pointer-sized roots are simple (consecutive slots), but a
  record root of 16 or 32 bytes between them is not. Verify against the LLVM 18.1.3
  `ShadowStackGC` definitions first, then decide how the walker finds each aggregate slot (for
  example, whether the metadata needs to carry the root's size). Needed before the first
  composite root can be walked precisely.
- **The root walker must tolerate roots that point outside the traced heap
  (register 14).** Such roots already exist: `phaseB`'s `t` is initialised to a static
  text literal in `M_Const`, and an open-array parameter slot holds the caller's dope
  address until its re-point. The walker must recognise and skip non-heap addresses,
  rather than treating every root value as a heap pointer.
- **Registers as roots (v12).** Each stopped thread's `regs` (x86_64 callee-saved registers
  spilled by the assembler when it publishes the stack) are conservative roots; on wasm32 the
  array is zero. See register 26. **v13:** `ProcessStacks` passes them (Phase C).

---

## Phase L — The Core Library on wasm32 (new in v12; before Phase E)

**Status: a new top-level task, decided 2026-10-21.** It sits before Phase E and is independent of
the collector work in the code it touches, so it can be interleaved with Phases C and D. It is also
what lets the front end build user-space programs for wasm32 (today it cannot, because the system
dependencies are not built for wasm32), and so it unblocks `Target.m3` testing and the attribute
cleanup (register 3, 8).

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
unchanged). The Libc/`Uuio` boundary stays as is. No change to PTHREAD.

---

## Phase E — Exception Handling Parity for wasm32

Unchanged. Deferred until Phase D is stable, and now **after Phase L**. `ExceptionDebug.argType`
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

---

## Consolidated open-items register

Ordered. "B1" items continue the B1 close-out list; "B2" items are the narrow
`m3t`/metadata leftovers. **Numbering is stable across versions; items 1, 2, 4, 7, 20, 21, 22, 24, 26, 29, 32, 33, 36 and 38 are
closed in place (or accepted), 11–16 date from v10, 17–22 from v11, 23–32 are new in v12, and 33–40
are new in v13.**

| # | Item | Phase | Notes |
|---|---|---|---|
| 1 | ✅ **Parameter rooting** — closed in v10 | B1/B2 | `m3t`, size, align and `inProc` now flow from `declare_param`'s `LvVar` into `NewVar` in `begin_procedure`. Verified by IR inspection; no runtime proof until the collector is wired |
| 2 | ✅ **Loop-edge safepoint polls** — closed in v11 | B1 | Poll on the taken side of every back-edge; `EmitSafepointCheck`'s flow block is the continuation. Run through six generated test procedures in v11 |
| 3 | **`Target.m3` generic wasm32 system (`WASM32_WASI`)** | B1 | Deterministic 32-bit width (not by name substring); excluded from the 32-bit alignment downgrade for non-C backends so `m3llhost` is unchanged; confirm `phb.ast` shows `Int.32` and a 4-byte `Addr`. User-space programs for wasm32 additionally need Phase L stage 1 |
| 4 | ✅ **`LLVMVerifyModule`** before the output step — closed (a couple of sprints before v12) | B1 | The user invoked it; catches the invalid-module class early |
| 5 | **Debug info: NIL element** for objects without a supertype | B1 | LLVM 20 rejects it |
| 6 | **Report two LLVM bugs upstream** | B1 | Aggregate gcroot `llc` crash; shadow-stack lowering drops alloca alignment. Reproducers ready |
| 7 | ✅ **WTHREAD codegen through `m3llwasm` for the x86_64 target** — closed in v11 | B1→D | Six generated test procedures ran under the WTHREAD thread harness on x86_64; fairness held, `LockHeap` nested locks did not regress, all tests passed. Collector still not wired (Phase D) |
| 8 | Finish the wasm32 function-attribute cleanup | B1 | Only partially done. Waits on Phase L stage 1: the front end cannot compile user-space programs for wasm32 until the system dependencies are built for it (codegen without that yields 8-byte pointers and the `AllocVar` assertion `v.align <= ptrBytes` fires) |
| 9 | Declaration-ordering assumption; `type_map` vs `gc_map` at collection time | B2 | See "Still open, narrowly" |
| 10 | Phase D prerequisites: `WalkStack`; `refs_only`/`mask` finalization; chain-head sourcing for parked, coordinator and blocked threads | D | Items 13 and 14 add two more D1 prerequisites |
| 11 | **Open-array VALUE parameter copy** (`number`) and open-array dope-vector temporaries | arrays | Constraint: the holder of the heap copy after the re-point must be rooted for the whole body |
| 12 | **Opaque types: derive `traced` from the super's entry** in `declare_opaque` (`TracedOf` helper) | B2 | **Parked by decision; reminder carried.** Forward-declared super still inherits the `TRUE` placeholder; likely to arrive as imported partial reveals |
| 13 | **Aggregate root-slot addressing for the D1 walker** | D1 | `FrameMap` carries no per-root size/offset (from memory — verify in LLVM 18.1.3 first) |
| 14 | **Root walker tolerates non-heap roots** (static text literals; caller dope addresses) | D1/C | Skip addresses outside the traced heap; applies equally to the pinning pass (25) |
| 15 | `pop_struct` copy is `llvm.memcpy ... align 1` although slot and source are `align 8` | B1 | Low priority; legal and harmless under stop-the-world; decide whether intended |
| 16 | Shadow-stack lowering's invoke rewriting, `gc_cleanup` pad and `__gcc_personality_v0` vs `__m3_personality_v0` | E | Observation only; settle when exception handling is picked up |
| 17 | **Phase C stages 2–3:** validate each stopped thread's published chain, then walk it (frames with `NumMeta = 0` first), with generated-code mutators in the stop-the-world harness | C→D1 | Stage 1 validated in v11; D1 stays the real walker. Records/metadata walking out of scope for now |
| 18 | ✅ **`stack_chain` initialisation** — closed for `nthr_create` | A | `nthr_create` sets `ctxt->stack_chain = NULL`. v12: `nthr_default` also sets `stack_chain = NULL` and, like `nthr_create`, zeroes `regs` and clears `ended` (confirmed in the project copy of `nthr.c`) |
| 19 | **Memory-ordering portability note** — out of scope | A | The `watch`/`safePoint` store-then-load pairing relies on the nsyn lock operations between the coordinator's `safePoint := 1` and its reads of `watch` being full barriers: true on x86_64 (locked read-modify-write) and wasm (atomics are sequentially consistent, so wasm32 on ARM hardware is covered too). Targets are x86_64 and wasm32 only; native ARM would need an explicit fence, and is not planned. v12: the per-function ordering decisions for `nthr_wait` and `nthr_vigil` are recorded in Phase A addendum 2. **v13:** the store-then-load handshakes (`nthr_wait`, `nthr_lock`) are `seq_cst` on the thread side; on x86_64 the coordinator side is covered by the locked read-modify-write operations before the ring walk; a weaker target would need `seq_cst` on the coordinator's `safePoint` store and `watch` load as well, and a `seq_cst` final `safePoint` load in `nthr_vigil`. The rules are in Phase A addendum 3 |
| 20 | ✅ **Nexus and context layout** — closed 2026-10-22 | A/B1 | `{safePoint, safeSyn, watchSyn, parked, forkList, forkSyn}` agrees with LLVM's layout of `{i32, lock, lock, i32, ptr, lock}`: x86_64 offsets 0/4/16/28/32/40, size 56; wasm32 0/4/16/28/32/36, size 48. v12: the arch files reviewed this sprint (`nthr_x86_64.c`, `nthr_wasm32.c`) build against the current `nthr.h` in my harnesses, so the `watchSyn` rename and `dangerSyn` removal have reached them. **Closed:** the user confirmed `CompileSafepoint` declares the nexus shape and, as of this sprint, the context type with the appended `regs` (six pointer-sized elements) and `ended` (`i32`) |
| 21 | ✅ **`nthr_vigil` publish and re-check** — closed 2026-10-22 | A | Re-check after the restore is in place (Phase A addendum 2). Publish: `nthr_vigil` calls `nthr_arch_stack32` (x86_64 assembler saves `%rsp` and the six registers into the `nthr_current` context) and refreshes `stack_chain` before the exchange, when it is eligible to wait. When the target is already detached it only reaps and no publish is needed (the joiner stays `vigilant`). Needed by `InitialThread`, where the default thread sits in the join for the life of the program |
| 22 | ✅ **Startup ordering for the default thread** — closed 2026-10-29 on evidence | A→D | Shape: `WThread.InitialThread` with the `Init`/`Axis` design of 2026-10-24. Evidence: in the `ms7` runs a collection runs in the main thread before any harness code forks a thread (`WThread.GC` = 1), and six more run before the first explicit `Collect` of the last run, without failure. The v12 checklist (a registered `T`, the fork ring and an initialised nexus before the first collection; `LockHeap`'s `RecMutex` owner comparison tolerating a NIL `Self()`) is the place to look if an early collection ever fails |
| 23 | **Phase L: the core library on wasm32** — new in v12 | L (before E) | Stage 1: use wasi-sdk's libc as is, `m3core.h` wasm32/WASI guard, per-target module selection. Stage 2: backfill or stub the system calls WASI lacks (list in Phase L). Frozen baseline: guarded, x86_64 unchanged |
| 24 | ✅ **WTHREAD as a native, traced object type** — done in v13 (`beta.17`, `beta.18`) | A→C | `pkg/neocore` builds `Thread.T` on WTHREAD; `ms4` and `ms7` run `Fork`/`Join` with traced allocation under the collector, with an early collection at startup. Startup shape: `Init` allocates the default thread's context and `Axis`, and `InitialThread` links the `Thread.T`. **Confirmed 2026-10-29:** `WThread.m3` contains no `DISPOSE` statements, so the test-only scaffolding and the dangling `nthr_current` are gone |
| 25 | **Phase C pinning of LLVM roots** — new in v12; split in v13 | C | **25a ✅ conservative scan, done and validated** (Phase C): `ProcessStacks` feeds each non-detached thread's stack and `regs` to the unmodified `NoteStackLocations`. **25b, open:** walk each thread's `llvm_gc_root_chain` and pin the pages the slots reference (the `ProcessStacks` TODO for wasm32), integration-tested against the 25a scan as comparator (compare the pages each pins); scalar roots first; skip non-heap roots (14). Whether wasm32 needs a chain-publication hook is not established |
| 26 | ✅ **`ProcessStacks` passes `regs` to the collector** — done in v13 | C | `ProcessStacks` calls `p` on `regs` for every non-detached thread, and the coordinator calls `thread_stack32()` on itself first. No `regs[]` hit has appeared in the `ms7` runs, so the path is exercised but a register-held pin is not yet demonstrated (39) |
| 27 | **nref/nthr small items** — new in v12 | A/nref | (a) `nref_define` diagnostic when the `Virtual` size is not a multiple of 64 KiB on wasm32 (otherwise `sbrk` traps with `unreachable`); (b) widen `arg_match` size arithmetic to `size_t`/`unsigned long long` with overflow checks (`long` is 32 bits on wasm32); (c) comment in `nthr_vigil` that the caller holds `joinSyn`; (d) correct the stale fence comment in `nthr_wait`; (e) consider writing each `nthr_debug` line with one `write(1, …)`; (f) bring the m3neos repo's `nref.c` up to the project version; (g) stock wasi-sdk 24 `malloc.h` lacks `struct mallinfo`, so `nref.c`/`nref.h` need a guard or shim |
| 28 | **`AlertJoin` stale `joinSyn`** — new in v12 | A | The target may hold a pointer to the joiner's `threadSyn` after the joiner's `T` is freed. With `T` traced (24) this should be closed; recheck on the user's tree |
| 29 | ✅ **Build wiring for the `.s` files** — closed 2026-10-22 | build | Done: the compiler driver scripts were adjusted and the x86_64 instance builds. Policy stays: `-matomics` in the wasm32 script only; link flags per "wasm32 build flags" |
| 30 | **Report WAMR upstream issues** — new in v12 | wasm32 | See `claude/wamr-build-notes.md` for the build-side findings; the `@M3virtual` workaround stays until memory growth works |
| 31 | **Second runtime cross-check** — new in v12 | wasm32 | The wasm32 join/exit results come from node with worker threads; run the same cycles under WAMR (and ideally one more engine). The harness package built against the user's own tree is the vehicle |
| 32 | ~~Update `claude/wasm32-resume-notes.md`~~ — withdrawn 2026-10-22 | docs | The notes file was an interim for an earlier chat; this plan carries everything needed (Phase L facts, join/reap protocol, build flags) |
| 33 | ✅ **`nthr_lock` safe-region lock and the watch-transition rules** — new and closed in v13 | A | Phase A addendum 3. The lost wake-up (`vigilant` left outside `watchSyn` with no broadcast) is fixed; rules (a) and (b) and the two documented exceptions are stated once. Review every new blocking primitive against that table |
| 34 | **`SuspendOthers` requires the heap lock** — new in v13 | A/C | Held by `Collect`, `StartCollection`, `AllocTraced` and `RTHeapStats`. The `After` and `VisitAllRefs` paths call it without it; they should take the heap lock first. A bare call aborts with `NOPARK` as soon as a fresh thread allocates |
| 35 | **Library poll policy** — carried forward, recorded in v13 | B1/C | Polls are emitted into user code only; `pkg/neocore` is deliberately not compiled with `m3llwasm` on x86_64 until stop-the-world and pinning are proven and the codegen is shown compatible with the runtime. Before polls are ever enabled in library code, `RTAllocator`, `RTCollector` and `RTHeapRep` must stay poll-free: parking inside `AllocTraced` between reading and updating `pool.next` would corrupt the heap after `FlushThreadState`. The user's preferred mechanism is to skip poll emission per compilation unit for those units (about four, possibly also `WThread`, which exports `RTThread`/`RTOS`/`Scheduler`/`RTHooks` entries); gating on `heapState.inCritical` is the alternative |
| 36 | ✅ **`nthr_arch_reap32` on wasm32 waits in a loop on `ended`** — new and closed 2026-10-29 | A | Done as belt and braces: `while (ended == 0) wait32(&ended, 0, -1)` with an acquire load. A single wait was probably already enough (the wake comes from the store and notify in `wasi_thread_start`, and a `wait32` on a changed value returns at once), so the loop costs nothing and removes the question |
| 37 | **Unclaimed-thread reaper and slot-table growth** — new in v13 | A | Unjoined threads go on a low-priority "unclaimed" ring that is reaped as a GC extension (design of 2026-10-24); the slot table behind `Axis.slot` (`triple[…]`) needs growth. Neither is done |
| 38 | ✅ **The collector pins its own highest page** — accepted 2026-10-29 | C | Phase C. The collector stays unmodified; the `ms7` pass rule accounts for it; optional confirmation by moving the flip loop into its own procedure |
| 39 | **Extend `ms7`: embedded `REF` fields** — *next* | C | A `REF` field in the record and in the object (first non-NIL `gc_map` under WTHREAD); then `ARRAY OF REF` on the stack, `REF ARRAY` and open arrays, large objects, interior pointers (`VAR`/`WITH`), and a `regs[]` hit |
| 40 | **Diagnostics hygiene before the commit** — the user | C | Revert the per-hit trace in `RTCollector.m3`; keep the `WThread.GC` counter; keep the `ProcessStacks` header prints as a comment |

**Parked:** nested procedures on wasm32 (B1) — `nest` attribute unsupported; static
link is the hidden first parameter spilled to `__StoredStaticLink`, and its slot is
expected to be reworked then.

**Deferred:** `superType` sprint; `BITS N FOR T`; fixed/open arrays (including item 11);
exception handling (Phase E); sysroot problem for `wasm32-unknown-wasi`;
`BuiltinTypes.KindUID` adoption.

---

## Commit Granularity Summary

| Phase | Granularity | Rationale |
|---|---|---|
| Baseline | N/A — already done | Existing, working code |
| A | Complete, tested; parking protocol revised in v11; exit/join/reap and context layout revised and verified in v12; **v13: `nthr_lock`, the watch-transition rules and the heap-lock invariant recorded, and WTHREAD wired into `pkg/neocore`.** Open: 28, 34, 37 | Four invariants plus the v11 drain rule, the v12 Mesa signal-under-lock rule and the v13 rules table govern everything downstream |
| B1 | Poll, gcroot frame scaffolding, thread-local chain, alignment and debug fixes: done, validated on x86_64. Loop-edge polls: done. Open: `Target.m3`, debug NIL element, attribute cleanup, upstream reports | The block structure and entry-block discipline are load-bearing; loop polls reuse `EmitSafepointCheck` |
| B2 | `m3t` chain + `ClassifyTrace` + composite metadata: done, verified. Parameter rooting: done, verified by IR inspection. Objects closed. Narrow items plus deferred scope (arrays, packed fields) and the parked opaque fix | Real `REF` roots are registered for parameters; runtime proof waits on Phase D |
| C | Design captured; stage 1 (stop-the-world) harness-validated in v11; **v13: conservative pinning (25a) implemented and validated with `ms7` under the unmodified collector**; chain-walk pinning (25b) and stages 2–3 not started | Composite roots have real metadata; chain head is a published per-thread copy; relies on pinning and on globals being roots. The collector self-pin is accepted (38) |
| C harness (`ms7`) | Per extension | Embedded `REF` fields next (39), then arrays of `REF`, large objects, interior pointers; the highest-page rule is part of the pass criteria |
| D (D1–D4) | Per sub-milestone | `WalkStack`, refs-only finalization, chain-head sourcing, aggregate root-slot addressing and non-heap root tolerance are D1 prerequisites |
| **L (new)** | Two stages: (1) wasi-libc as is; (2) backfill the system calls WASI lacks | Independent of the collector work; guarded so x86_64 is unchanged; unblocks user-space programs on wasm32 |
| E | Per milestone | Depends on Phase D being complete and stable, and follows Phase L; includes shadow-stack/unwind interaction and the personality question |