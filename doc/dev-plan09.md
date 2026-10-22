# Incremental Development Plan: wasm32 Threading, Safepoints, and GC Integration

**Plan v9 — checkpoint 2026-10-08**

**Scope:** CM3-derived Modula-3 compiler. The x86_64/Linux target, via the `m3llhost`
backend and the existing PTHREAD runtime module, is an **already-working baseline**.
This plan covers only the **new work required for the wasm32 target**, built through
the new `m3llwasm` backend and a new `WTHREAD` (`WThread`/`nthr`/`nsyn`) runtime
module.

**Revision note (this version):** v9 merges two lines of work. The v8 lineage closed
Phase B2's composite `gcroot` metadata (`TypeComp`, byte-verified). A parallel session
took **Phase B1 — safepoint check emission** to a validated state on x86_64 and
recorded it in `alt-inc-plan.md`, a narrower interim checkpoint. v9 folds all of that
into the full-context structure and drops nothing from either source:

- **B1 is now implemented and validated on x86_64** (LLVM 18.1.3 `verify` and `llc`
  pass, no `movaps`, 10 polled functions in `phb.ll`). The section below records the
  gcroot-frame scaffolding it depends on (entry/prolog/body blocks, the aggregate-root
  marker workaround, `LvProc.rootStack`), the poll itself, the thread-local
  shadow-stack chain decision, and the alignment, debug-info and function-attribute
  fixes made along the way.
- **Open work is consolidated** into one ordered register (end of document). It leads
  with parameter rooting and loop-edge polls, then the wasm32 `Target` work and the
  remaining B1 close-out items.
- **Nested procedures on wasm32 are parked** (`llc` rejects the `nest` static-link
  attribute), recorded in full so the deferral is deliberate and findable.
- **The frozen-baseline principle gains a scope note:** modernising x86_64 output to
  track the LLVM toolchain is in scope; new functionality targets wasm32.
- **Carried forward unchanged in substance:** `BITS N FOR T` packed fields (deferred),
  the `superType` correction sprint (deferred), the `BuiltinTypes.KindUID` future note,
  the `refs_only`/`gc_map` finding and the Phase D `WalkStack` notes,
  `Gen_Call_indirect`/`Invoke_indirect` `m3t` sourcing (now **resolved**), and the
  target-description rename and datalayout findings.

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
- (New in B1) The `Target.m3` plan for a generic wasm32 system: it must be excluded
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

Any future decision that would touch `m3llhost`, `TipeMap`, or any other
x86_64-shared machinery — however small — should be checked against this principle
first.

---

| Status | Item |
|---|---|
| ✅ Confirmed reusable | `SuspendOthers` / `ResumeOthers` — unchanged, see Phase A. |
| ✅ Confirmed by build config | Target exclusivity via `TARGET=wasm32`/`M3_BACKEND=Wasm` — unchanged. |
| ✅ Resolved (Phase C) | Shadow-stack root feeding via `RTThread.ProcessStacks` reusing `NoteStackLocations` unmodified — unchanged; per-thread chain head now published at park time (see B1.5). |
| ✅ Complete, tested (Phase A) | WTHREAD thread lifecycle, cooperative `SuspendOthers`/`ResumeOthers` — unchanged, see invariants below. |
| ✅ Implemented, validated on x86_64 (Phase B1) | Safepoint check emission; gcroot frame scaffolding (entry → prolog → body); aggregate-root marker workaround; thread-local `llvm_gc_root_chain`. **Not yet validated end to end on wasm32** (blocked on `Target.m3`, below). |
| ✅ Complete, verified (Phase B2) | `m3t` propagation chain; `ClassifyTrace` scalar/composite dispatch; composite `gcroot` metadata, byte-verified. `Gen_Call_indirect`/`Invoke_indirect` sourcing now resolved. |
| 🔶 Open, next (B1/B2 seam) | **Parameter rooting** (`REF T` parameters currently unrooted); **loop-edge polls** (design pending). |
| 🔶 Open (wasm32 enablement) | `Target.m3` generic wasm32 system; `LLVMVerifyModule`; debug-info NIL element; remaining wasm32 attribute cleanup. |
| 🔶 Open (upstream) | Two LLVM bugs to report (reproducers ready). |
| 🅿️ Parked | Nested procedures on wasm32 (`nest` static-link attribute unsupported by the wasm backend). |
| 🔲 Deferred, own sprint | `InitUids`'s `superType` fields (DWARF-correctness only). |
| 🔲 Deferred, scope | Fixed and open arrays; `BITS N FOR T` packed fields; exception handling (Phase E). |
| 🔲 Future note | `BuiltinTypes.KindUID` — backend should consume the front end's computed builtin TypeUIDs instead of hard-coded `UID_*` constants. |

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

---

## Target descriptions and datalayout (m3llwasm)

Findings recorded so they are not rediscovered:

- **Renames.** `AMD64_LINUX` was renamed `x86_64`; it carries the **proven,
  historical datalayout**. The modern x86_64 datalayout string became `CUR_X86_64`,
  **opt-in only**. The proven string stays the default.
- **wasm32 datalayout:** `e-m:e-p:32:32-p10:8:8-p20:8:8-i64:64-n32:64-S128-ni:1:10:20`.
  It is **identical for `wasm32` and `wasm32-unknown-wasi`**, confirmed independently
  with clang-18 (18.1.3) in a sandbox.
- **Sysroot problem for `wasm32-unknown-wasi`** in the user's environment: **deferred.**
- **`llvmByval = FALSE` is required for wasm32.**
- **The "invalid wasm32 module" root cause (B1 finding).** The module verified as
  invalid not because of function attributes but because the **front end produced a
  64-bit AST** (`Target.Init`) that was then emitted against the 32-bit wasm32
  datalayout. Fixing this is the `Target.m3` item in the register: add a generic
  wasm32 system (`WASM32_WASI`) that selects 32-bit width **deterministically**
  rather than by a name-substring test; exclude it from the 32-bit alignment
  downgrade for non-C backends (frozen-baseline principle: `m3llhost` unchanged);
  then confirm that `phb.ast` shows `Int.32` and a 4-byte `Addr`.

---

## Phase A — wasm32 Runtime Scaffolding (complete, tested)

Unchanged. `WThread.i3`/`.m3`, `nthr.c`/`.h`, `nthr_x86_64.c`/`nthr_wasm32.c`,
`RTSync.i3`/`nsyn.c`/`.h`. Four invariants (watch-state serialization under
`parkSyn`; before-and-after safepoint recheck around blocking primitives; `relief`
held for the entire `SuspendOthers`↔`ResumeOthers` bracket; role-based not
module-based safepoint exemption) — unchanged, still required reading for Phase D.
B1's emitted check is the compiled-code half of these invariants: its `relief` test
is the `relief` bracket as seen from generated code.

---

## Phase B1 — Safepoint Check Emission (implemented, validated on x86_64)

**Position.** Phase B (wasm32 codegen and garbage collection), step B1 = the safepoint
poll, built over the shadow-stack root scheme. Implemented and validated on the
x86_64 `phb.ll`: LLVM 18.1.3 `verify` and `llc` both pass, no `movaps`, 10 polled
functions. Exception handling stays deferred to Phase E; x86_64 stays frozen apart
from LLVM-toolchain modernisation. The next big step is producing the wasm32 target,
which needs some tweaking first (register items 3–5).

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

**The workaround (the "marker" scheme).** A **one-byte zero marker store** is written
into each composite gcroot in the entry basic block, so LLVM treats the aggregate as
already initialised and does not try to initialise it by copying the aggregate. The
actual zeroing of the record is then done by a memset in a *later* block (B1.3).

**Entry-block discipline (hard rule).** The entry block contains **only**:
allocas; `llvm.gcroot` calls; the one-byte marker store for aggregate roots; and
scalar parameter spills. **No memset, memcpy, memmove, other calls, or loads.**
`AllocVar` asserts that the current insert block is the entry block.

**Pointer-sized roots get nothing emitted** by the backend beyond the alloca and the
gcroot call: LLVM's own lowering null-initialises them (it is that same lowering step
that breaks on aggregates).

### B1.3 Block structure: `entryBB → prologBB → bodyBB`

- **`entryBB`** — per the discipline above.
- **`prologBB`** — begins with the **memset-zero of every record root**, *then* the
  safepoint poll. Zeroing precedes the poll, so a thread that parks at its first
  safepoint never exposes an uninitialised composite root to the collector.
- **`bodyBB`** — the continuation block *returned by `EmitSafepointCheck`*.

**`LvProc.rootStack`** — a list of root variables, filled as composite roots are
allocated. `end_procedure` consumes it to emit the memsets into `prologBB`.
`end_procedure` also declares the function's GC strategy
(`LLVMSetGC("shadow-stack")`). **The strategy trigger must be "any `gcroot` call was
issued in the entry block", not "`rootStack` is non-empty"** — a function whose roots
are all scalar has an empty `rootStack` but still needs the strategy.

**Historical bug, now fixed.** After emitting the poll, the builder was being
repositioned back to `prologBB`, which put the function body *inside* `chkWatch` and
called `nthr_park()` unconditionally. Rule: **never reposition the builder to
`prologBB` after the poll**; the builder continues in the block `EmitSafepointCheck`
returns. Block names `prolog`/`flow` (formerly `second`/`cont`) were validated on
2026-10-07.

### B1.4 Safepoint check emission

**Module-level pieces, compiled into the bitcode** (so the check can reference them):

- `nthr_nexus` — the nexus **struct** (carries the `safepoint` flag).
- `nthr_current` — the thread-context **pointer**. It was previously declared with
  the context *struct* type; it is now correctly declared `ptr`.
- Both are emitted by `CompileSafepoint`, which is **boolean-guarded to do its
  module-level work exactly once**. It also declares the thread-local root chain
  (B1.5), so `begin_procedure` needs no per-function test for that declaration.

**`EmitSafepointCheck`** emits: *if `nexus.safepoint != 0` **and** the thread's watch
state is not `relief`, then call `nthr_park()`*. The shape is two-staged — the global
flag first, so the common path is one load and one branch, then the watch-state test
(`chkWatch`), then the park, then the continuation block (`flow`) that the routine
returns to its caller. The `relief` exemption is Phase A's invariants 3 and 4 as seen
from generated code: the thread inside a `SuspendOthers`↔`ResumeOthers` bracket must
not park itself.

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

### B1.6 Alignment bug (`pop_struct`)

`pop_struct` created temporaries for by-value records with the **whole structure
size as the alignment** (e.g. `align 16` on a 16-byte record) instead of the
alignment operand (pointer alignment). Harmless until the shadow-stack lowering dropped alloca alignment,
at which point a `movaps` on an under-aligned slot **SIGSEGV'd**. Fixed: it now
passes the alignment operand. If the same code exists in `m3llhost` it is latent
there (no shadow-stack lowering on that path) and, per the frozen-baseline
principle, is left alone.

### B1.7 Debug-info fixes

- `DebugObject` now builds a **real class type** and replaces the placeholder via
  `LLVMMetadataReplaceAllUsesWith`. `DebugRecord` and `DebugProc` already did this.
  The earlier failure was a debug-metadata bug fixed by that **replace-all**.
- `DebugLookupML` now assigns `diType` from each `Debug*` return value **for all
  kinds**, so `r.diType` / `p.diType` are set consistently.
- **Still open:** objects with no supertype leave a **NIL element** in the element
  array, which LLVM 20 rejects.

### B1.8 LLVM bugs for upstream (reproducers ready)

1. Aggregate gcroot crash in `llc` (shadow-stack's `store [N x i8] null`; LLVM 18.1.3
   and 20.1.2).
2. Shadow-stack lowering drops alloca alignment.

### B1.9 Validation record

Reference module `phb.m3`; output checked on `phb.ll`: LLVM 18.1.3 verify + `llc`
pass, no `movaps`, 10 polled functions. (The project's `phb.ast`/`phb.ll` copies are
reference snapshots; regenerate them after B1 close-out so the project reflects
current output.)

### B1 open items and parked

See the consolidated register. In short: **parameter rooting** (B2 seam) and
**loop-edge polls** are the substantive ones; the rest is wasm32 enablement and
cleanup.

**Loop-edge safepoint polls — design pending.** The function-entry poll alone does
not bound time-to-safepoint for a call-free loop, and `SuspendOthers` would wait on
such a thread indefinitely. Constraint from the codegen shape: a back-edge jumps to a
**label already placed**, so the poll goes on the **taken side** of the back-edge, and
the flow block returned by `EmitSafepointCheck` is the continuation. Next step:
compile a test module of loop constructs (`WHILE`, `REPEAT`, `FOR`, `LOOP`/`EXIT`)
and analyse the resulting CFG before deciding.

**Parked — nested procedures on wasm32.** `llc` rejects the `nest` static-link
attribute ("WebAssembly hasn't implemented nest arguments"). The static link is the
**hidden first parameter**, spilled to `__StoredStaticLink` (the first alloca). Nested
procedures remain open and may affect the AST (nested procedures can be deferred and
treated serially, which complicates up-level access). **Deliberately deferred.**

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
with `ObjectDebug` checked *before* `RecordDebug` since it is a subtype. Object-typed
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

### Parameter rooting — open (found during B1)

`begin_procedure` creates non-struct parameter slots with
`NewVar(... m3t := UID_ADDR ...)`, so **`REF T` parameters are not rooted** (e.g.
`takeRef`'s `%p1` has no gcroot in the generated module). The fix: the parameter's
`m3t` is already carried from `declare_param` in its `LvVar`; **pass that to `NewVar`**
instead of the hard-coded `UID_ADDR`. Interacts with the entry-block rule (parameter
spills are one of the four permitted entry-block contents) and is the first item in
the register. Related future note: the hard-coded `UID_*` constants are the reason
for the `KindUID` item below.

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

A bare, standalone `VAR x: SomeObject` local (not embedded in a record) remains
technically untested, though the mechanism is proven and this is considered low-risk.

### Builtin type table (`InitUids`)

- **`traced` bugs — fixed.** `traced := TRUE` for ROOT/TEXT/REFANY/MUTEX; explicit
  `FALSE` for UNTRACED_ROOT and ADDR. Together with the `ObjectDebug`-before-
  `RecordDebug` dispatch fix, these are the two independent failures noted above.
- **`superType` correction sprint — deferred, own sprint.** `InitUids`'s `superType`
  fields (cross-checked against the Language Report). DWARF-correctness only; no
  effect on gcroot or the collector.
- **Future note — `BuiltinTypes.KindUID`.** The backend should use the front end's
  **computed** builtin TypeUIDs rather than hard-coded `UID_*` constants. Not
  scheduled; removes a drift risk and is the structural fix behind the
  `UID_ADDR` parameter issue above.

### Design hazards recorded

- **Never hash on a traced reference's address.** A moving collector can relocate it.
  `Proc` is a traced object, so any table keyed by procedure needs a stable key. (An
  earlier name-keyed-table idea was dropped after the NARROW/`Proc` layering
  correction: the backend must not depend on front-end `Proc`.)
- **Declaration ordering:** `ClassifyTrace` asserts on a `debugTable` miss, forcing an
  ordering violation to surface at compile time rather than miscompile silently.

### Still open, narrowly

1. **Parameter rooting** (above) — now the first item.
2. Declaration-ordering assumption (`<*ASSERT FALSE*>` on a `debugTable` miss) — still
   never triggered across an increasingly large and varied test set; formally
   unverified.
3. A bare, non-composite-embedded object-typed local.
4. Why `RTTypeMap.WalkRef` consumes `.type_map` rather than `.gc_map` at actual
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
handle arbitrary depth.

---

## Phase C — Shadow Stack Root-Feeding: Design (resolved)

Unchanged. `RTThread.ProcessStacks` presents each thread's shadow stack to the
existing, unmodified `NoteStackLocations`. `stack_ptr`/`stack_top` argument-order
pitfall is still the thing to get right when Phase D writes the real loop. Composite
roots have *real* metadata (not a placeholder) to eventually walk precisely, once
Phase D's own walker exists — see the `WalkStack` note below.

**What B1 adds to this phase's assumptions:** every root slot is either valid or null
by the time any thread can park — scalar roots by LLVM's own null-initialisation,
composite roots by the prolog memset, which precedes the poll (B1.3). The walker can
therefore treat each slot as valid-or-null without a "was this frame initialised yet"
side channel. The per-thread chain head is the **published copy made by `nthr_park`**
(B1.5), not a live global.

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
- **New (from B1.5): where the chain head comes from.** Parked threads: read the head
  `nthr_park` published in the thread context. The thread running the collection holds
  `relief` and never parks, so its own chain head is its live thread-local — to be
  confirmed in D1. Also to confirm in D1: threads inside **blocking primitives**
  (Phase A invariant 2) must also have a published head, i.e. that path goes through
  the same publish step as `nthr_park`.

---

## Phase E — Exception Handling Parity for wasm32

Unchanged. Deferred until Phase D is stable. `ExceptionDebug.argType` is the relevant
field when this phase is picked up. One design question to carry into
this phase (not previously discussed; added at v9): how exception unwinding restores
the thread-local shadow-stack chain head when it skips frames.

---

## Consolidated open-items register

Ordered. "B1" items continue the B1 close-out list; "B2" items are the narrow
`m3t`/metadata leftovers.

| # | Item | Phase | Notes |
|---|---|---|---|
| 1 | **Parameter rooting** — pass the parameter's `m3t` (from `declare_param`'s `LvVar`) to `NewVar` in `begin_procedure` | B1/B2 | `REF T` params are currently unrooted |
| 2 | **Loop-edge safepoint polls** | B1 | Poll on the taken side of the back-edge to the already-placed label; `EmitSafepointCheck`'s flow block is the continuation. Compile a loop-construct test module and analyse the CFG |
| 3 | **`Target.m3` generic wasm32 system (`WASM32_WASI`)** | B1 | Deterministic 32-bit width (not by name substring); excluded from the 32-bit alignment downgrade for non-C backends so `m3llhost` is unchanged; confirm `phb.ast` shows `Int.32` and a 4-byte `Addr` |
| 4 | **`LLVMVerifyModule`** before the output step | B1 | Catches the invalid-module class early |
| 5 | **Debug info: NIL element** for objects without a supertype | B1 | LLVM 20 rejects it |
| 6 | **Report two LLVM bugs upstream** | B1 | Aggregate gcroot `llc` crash; shadow-stack lowering drops alloca alignment. Reproducers ready |
| 7 | **WTHREAD codegen through `m3llwasm` for the x86_64 target**, tested on Ubuntu | B1→D | Afterwards. Uses the `x86_64` target description (proven datalayout), not `CUR_X86_64` |
| 8 | Finish the wasm32 function-attribute cleanup | B1 | Only partially done |
| 9 | Declaration-ordering assumption; bare object-typed local; `type_map` vs `gc_map` at collection time | B2 | See "Still open, narrowly" |
| 10 | Phase D prerequisites: `WalkStack`; `refs_only`/`mask` finalization; chain-head sourcing for parked, coordinator and blocked threads | D | See Phase D |

**Parked:** nested procedures on wasm32 (B1) — `nest` attribute unsupported; static
link is the hidden first parameter spilled to `__StoredStaticLink`.

**Deferred:** `superType` sprint; `BITS N FOR T`; fixed/open arrays; exception
handling (Phase E); sysroot problem for `wasm32-unknown-wasi`; `BuiltinTypes.KindUID`
adoption.

---

## Commit Granularity Summary

| Phase | Granularity | Rationale |
|---|---|---|
| Baseline | N/A — already done | Existing, working code |
| A | Complete, tested | Four invariants govern everything downstream |
| B1 | **Poll, gcroot frame scaffolding, thread-local chain, alignment and debug fixes: done, validated on x86_64.** Open: loop-edge polls, `Target.m3`, `LLVMVerifyModule`, debug NIL element, attribute cleanup, upstream reports | The block structure and entry-block discipline are now load-bearing; loop polls reuse `EmitSafepointCheck` |
| B2 | `m3t` chain + `ClassifyTrace` + composite metadata: done, verified. **Parameter rooting open.** Narrow items plus 2 deferred-scope items (arrays, packed fields) | Parameter rooting is the last piece that leaves real `REF` roots unregistered |
| C | Design captured, no code | Composite roots have real metadata; chain head is a published per-thread copy |
| D (D1–D4) | Per sub-milestone | `WalkStack`, refs-only finalization and chain-head sourcing are D1 prerequisites |
| E | Per milestone | Depends on Phase D being complete and stable; includes shadow-stack/unwind interaction |
