# Incremental Development Plan: wasm32 Threading, Safepoints, and GC Integration

**Scope:** CM3-derived Modula-3 compiler. The x86_64/Linux target, via the `m3llhost`
backend and the existing PTHREAD runtime module, is an **already-working baseline**.
This plan covers only the **new work required for the wasm32 target**, built through
the new `m3llwasm` backend and a new `WTHREAD` (`WThread`/`nthr`/`nsyn`) runtime
module.

**Revision note (this version):** Phase B2's single largest open item — composite
`gcroot` metadata, previously `null` for every composite root — is now **complete
and empirically validated**. A new backend-owned module, `TypeComp`, compiles
`RecordDebug`-sourced field data into `RTTypeMap`-format bytecode; `AllocVar` wires
it into `gcroot` via a per-`TypeUID` cache. Four test record types (including a
nested-by-value case and a user-declared `OBJECT` field) produced byte-exact,
independently-verified metadata. This revision also elevates a principle that
governed nearly every design decision in this stretch of work to its own standing
section, since it's now been invoked explicitly, by name, several times: **the
x86_64/`m3llhost` baseline is frozen.**

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

Any future decision that would touch `m3llhost`, `TipeMap`, or any other
x86_64-shared machinery — however small — should be checked against this principle
first.

---

| Status | Item |
|---|---|
| ✅ Confirmed reusable | `SuspendOthers` / `ResumeOthers` — unchanged, see Phase A. |
| ✅ Confirmed by build config | Target exclusivity via `TARGET=wasm32`/`M3_BACKEND=Wasm` — unchanged. |
| ✅ Resolved (Phase C) | Shadow-stack root feeding via `RTThread.ProcessStacks` reusing `NoteStackLocations` unmodified — unchanged. |
| ✅ Complete, tested (Phase A) | WTHREAD thread lifecycle, cooperative `SuspendOthers`/`ResumeOthers` — unchanged, see invariants below. |
| ✅ Complete, verified (Phase B2) | `m3t` propagation chain; `ClassifyTrace`'s scalar/composite dispatch; **composite `gcroot` metadata synthesis, now real and byte-verified** (was the last major open item). |
| 🔲 Deferred, own sprint | `InitUids`'s `superType` fields (DWARF-correctness only). |
| 🔲 Deferred, scope | Fixed and open arrays; `BITS N FOR T` packed fields (new this checkpoint — see Phase B2). |

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

---

## Phase A — wasm32 Runtime Scaffolding (complete, tested)

Unchanged. `WThread.i3`/`.m3`, `nthr.c`/`.h`, `nthr_x86_64.c`/`nthr_wasm32.c`,
`RTSync.i3`/`nsyn.c`/`.h`. Four invariants (watch-state serialization under
`parkSyn`; before-and-after safepoint recheck around blocking primitives; `relief`
held for the entire `SuspendOthers`↔`ResumeOthers` bracket; role-based not
module-based safepoint exemption) — unchanged, still required reading for Phase D.

---

## Phase B1 — Safepoint Check Emission

Unchanged.

---

## Phase B2 — GC Root Registration for Stack-Resident Values

### `m3t` propagation chain and `ClassifyTrace` — complete (unchanged from last checkpoint)

Full chain from parser-level type resolution through `ValRec`, `declare_temp`,
`Call_direct`/`Invoke_direct`/`Gen_Call_indirect`/`Invoke_indirect`, and
`declare_procedure`/`import_procedure`'s restored `return_typeid` — verified
working end to end. `ClassifyTrace`'s `PointerDebug`/`ObjectDebug`/`RecordDebug`
dispatch (with `ObjectDebug` checked *before* `RecordDebug`, since it's a subtype)
— verified correct, including the two-independent-failures lesson (dispatch bug and
data-population bug can each hide the other) worth remembering for any future
`Debug`-hierarchy extension. `QualifyExpr.m3`'s `Class.objField` case confirmed to
reuse `Type.LoadScalar` identically to `Class.recField` — no additional code needed,
resolving that item from a prior checkpoint.

### Composite `gcroot` metadata — now complete, not just designed

**The module: `TypeComp`.** A byte-for-byte-faithful copy of `TipeMap`'s core
encoder (`Op` enum, `ArgBytes`/`CursorUpdate`, `Add`'s skip-insertion and
argument-width logic) — confirmed identical, field by field, against the original
during review. Legitimate, deliberate differences only: object-based `T` (permits
multiple independent in-flight compilations, unlike `TipeMap`'s single-instance
module globals) and `Finish` returning bytes directly rather than writing to `v.1`.

**The pipeline, in `AllocVar`:**
- `ClassifyTrace(m3t)` → `None`/`Scalar`/`Composite` (unchanged).
- `FindMeta(tk, m3t)` — `Scalar` → `LLVMConstNull` (unchanged, null metadata).
  `Composite` → checked against `self.metaTable` (a `<TypeUID, ValueRef>` cache);
  on miss, `GenMeta` builds it once and caches the result.
- `CompileMeta(base, rec)` — walks `RecordDebug.fields` recursively. For each
  field: `PointerDebug`/`ObjectDebug` with `.traced` → `TypeComp.Op.Ref` at
  `base + bitOffset`; nested `RecordDebug` → recurse with `base + bitOffset` as the
  new base (single `Start`/`Finish` bracket spans the *entire* top-level
  compilation — nested calls never re-enter `Start`/`Finish`); anything else
  (untraced scalar) → emit nothing, relying on `Add`'s own auto-skip to bridge the
  gap when the next real field arrives.
- `GenMeta` — builds the `[N x i8]` constant via `LLVMConstString`
  (`DontNullTerminate := TRUE`), then `LLVMAddGlobal`/`LLVMSetInitializer`/
  `LLVMSetGlobalConstant`, **with `LLVMSetLinkage(..., LLVMInternalLinkage)`** —
  found missing during review (without it, `meta.N`-named globals, numbered from 1
  per compilation, collide across separately-linked modules) and fixed. Named via
  a monotonic `meta.<N>` counter — no need for the name itself to encode the
  `TypeUID`, since the `<TypeUID, ValueRef>` cache already provides that link
  directly.

**Confirmed by construction, not by assumption: `PushPtr`/`Return` are irrelevant to
this work.** Traced every real-`TipeMap.Add` call site in the front end — the only
callers are in `values/Variable.m3`, gated by `t.indirect`, describing *how a
particular global variable happens to be stored*, never a type's own field layout.
No record/object/array mapper anywhere touches either opcode; correctly excluded
from `TypeComp`'s scope entirely.

**The `refs_only` finding — this is what makes the op vocabulary small.**
`GenMap`'s own gate (`IF refs_only AND NOT isTraced THEN RETURN`) means an untraced
field is never even visited by the mapper — not skipped, *never called*. Confirmed
independently via `RefType.m3`'s `InitTypecell`: `RT0.TypeDefn` carries **two**
separate map fields from the *same* generator — `type_map := GenTypeMap(p, refs_only
:= FALSE)` (the full map, every scalar field) and `gc_map := GenTypeMap(p, refs_only
:= TRUE)` (traced fields only). `TypeComp`'s output is refs-only by construction —
meaning **`gc_map`, not `type_map`, is the correct field to diff our output
against** for verification purposes, despite `RTTypeMap.WalkRef`'s own runtime
consumption reading `.type_map` (a distinct, still-open question — see note below).
Practical effect: the only opcodes `TypeComp` ever needs to emit for anything in
current scope are `Op.Ref` (covers both `PointerDebug.traced` and
`ObjectDebug.traced` — unified, confirmed correct) and `Op.Stop`; everything else
is handled by `Add`'s existing auto-skip.

**Empirical validation, byte-exact across four cases.** Methodology: `TYPECODE(REF
T)` → `RTType.Get` → `RT0.TypeDefn.gc_map`, compared directly against `TypeComp`'s
output for the equivalent type. Verified:
- `composite` (`f1: INTEGER; f2: REF INTEGER`) → `Skip_8, Ref, Stop`.
- `TestA` (traced field preceded by mixed untraced fields) →
  `SkipF_1(16), Ref, Stop` — confirms `Add` prefers a single variable-argument
  skip over chained fixed skips when the target isn't reachable in ≤8 bytes.
- `TestB` (nested-by-value record containing the traced field) → identical output
  to `TestA` (same absolute byte offset via a different, nested path) — confirms
  the recursive base-offset threading computes correct absolute positions.
- `TestC` (two non-adjacent traced fields, one of them a user-declared `OBJECT`) →
  `Skip_8, Ref, Skip_8, Ref, Stop` — first confirmed exercise of the `ObjectDebug`
  branch against genuinely user-declared (non-builtin) data, and confirms the
  compiler's own cursor bookkeeping correctly accounts for an already-emitted
  `Ref`'s width when computing the *next* skip.

This closes the "object-typed local, not yet directly exercised" item from the
prior checkpoint in its field-embedded form; a bare, standalone `VAR x: SomeObject`
local (not embedded in a record) remains technically untested, though the
underlying mechanism is now proven and this is considered low-risk.

**Still open, narrowly:**
1. `Gen_Call_indirect`/`Invoke_indirect` `m3t` sourcing (no static `Proc`) —
   unchanged from prior checkpoint, not yet confirmed implemented.
2. Declaration-ordering assumption (`<*ASSERT FALSE*>` on a `debugTable` miss) —
   still never triggered across an increasingly large and varied test set;
   formally unverified.
3. A bare, non-composite-embedded object-typed local — see above.
4. Why `RTTypeMap.WalkRef` consumes `.type_map` rather than `.gc_map` at actual
   collection time, given `.gc_map` is the narrower, purpose-matched field —
   doesn't block anything (the comparison methodology is valid regardless), but
   unexplained, and worth understanding before Phase D's own walker is built,
   in case it reveals a reason our metadata needs to carry more than refs-only
   content after all.

**New deferred-scope item this checkpoint: `BITS N FOR T` (packed fields).**
Out of scope, and — unlike arrays — the reasoning bounds the risk precisely rather
than just deferring it: `BITS N FOR T` requires `T` to be ordinal, so a packed
field can never itself be a `REF`. The only way it's relevant at all is a *traced*
record that also happens to contain an unrelated packed field elsewhere — meaning
the gap is entirely about `TypeComp` correctly *stepping over* a packed field's
bits when computing subsequent offsets, never about a packed field needing to be
reported as a root. Worth fixing whenever a real test case surfaces it; not
urgent, and not a correctness risk to anything currently in scope.

### Array findings — unchanged from prior checkpoint, still not acted on

`ArrayDebug`/`OpenArrayDebug` both carry `elt: TypeUID` directly, so classification
would be structurally easy; *acting* on it differs sharply between fixed arrays
(compile-time-known count, could plausibly reuse `TypeComp`'s `Array_N`-family
opcodes once built) and open arrays (structurally incompatible with `gcroot`'s
one-root-per-alloca model, needs a different mechanism entirely). Open arrays can
nest (`.elt` can itself be an `OpenArrayDebug`) — any future recursive handling
must account for arbitrary depth.

---

## Phase C — Shadow Stack Root-Feeding: Design (resolved)

Unchanged. `RTThread.ProcessStacks` presents each thread's shadow stack to the
existing, unmodified `NoteStackLocations`. `stack_ptr`/`stack_top` argument-order
pitfall still the thing to get right when Phase D writes the real loop. Composite
roots now have *real* metadata (not a placeholder) to eventually walk precisely,
once Phase D's own walker exists — see the new `WalkStack` note below.

---

## Phase D — Wire Shadow-Stack Scanning Into the Coordinator

Unchanged in structure (D1–D4). Two notes added this checkpoint:

- **`RTTypeMap.i3` needs a small addition before D1 can call it: `Walk`/`DoWalkRef`
  are private to `RTTypeMap.m3`, not exported.** Resolution already agreed: add a
  new public entry point (`WalkStack(x, pc: ADDRESS; m: Mask; v: Visitor) RAISES
  ANY`) that calls the still-private `Walk` internally — deliberately *not*
  `WalkRef`, which does two things unsuited to a stack root: a `TYPECODE`/
  `RTType.Get` lookup that doesn't apply to a bare composite (no runtime typecode
  exists for one), and an unconditional `RTHooks.CheckStoreTraced` call —
  heap-page dirty-tracking machinery, category-confused against stack memory,
  which has no page descriptor or header for it to resolve at all.
- **The `refs_only` finding (Phase B2) is believed sufficient for Phase D's
  purposes but needs finalizing here, not assumed.** `TypeComp`'s output only ever
  contains `Op.Ref`/`Op.Stop` — no other `Kind` can appear. That likely makes
  `WalkStack`'s `mask` parameter a non-issue in practice (there's nothing else in
  the stream for a mask to filter), but this should be confirmed explicitly once
  D1's synthetic-heap test is being built, alongside resolving the still-open
  `type_map`-vs-`gc_map` runtime-consumption question from Phase B2 — if that
  question's answer turns out to matter for correctness rather than being
  cosmetic, it needs to be resolved before, not during, D1.

---

## Phase E — Exception Handling Parity for wasm32

Unchanged. Deferred until Phase D is stable. `ExceptionDebug.argType` is the
relevant field when this phase is picked up.

---

## Commit Granularity Summary

| Phase | Granularity | Rationale |
|---|---|---|
| Baseline | N/A — already done | Existing, working code |
| A | Complete, tested | Four invariants govern everything downstream |
| B1 | Done | — |
| B2 | `m3t` chain + `ClassifyTrace` + **composite metadata: all done, verified**. 4 narrow open items + 2 deferred-scope items (arrays, packed fields) | The one large remaining piece from prior checkpoints is now closed; what's left is genuinely narrow |
| C | Design captured, no code | Composite roots now have real metadata to walk once D exists |
| D (D1–D4) | Per sub-milestone | `WalkStack` addition and refs-only finalization now explicitly noted as D1 prerequisites |
| E | Per milestone | Depends on Phase D being complete and stable |
