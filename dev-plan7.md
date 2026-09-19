# Incremental Development Plan: wasm32 Threading, Safepoints, and GC Integration

**Scope:** CM3-derived Modula-3 compiler. The x86_64/Linux target, via the `m3llhost`
backend and the existing PTHREAD runtime module, is an **already-working baseline** —
proven card-table/write-barrier/safepoint/stop-the-world GC, in production use today.
This plan covers only the **new work required for the wasm32 target**, built through
the new `m3llwasm` backend and a new `WTHREAD` (`WThread`/`nthr`/`nsyn`) runtime
module.

**Revision note (this version):** Phase B2 is substantially rewritten. Since the
prior checkpoint, the entire `m3t` propagation chain — from source-level type
resolution in the parser, through the `ValRec` stack machine, through every
`declare_temp`/`declare_procedure`/`declare_indirect_call` AST instruction, to
`AllocVar`'s `gcroot` emission — has gone from "designed, partially wired" to
"complete and empirically verified" for scalar and composite locals/temps. A second,
independent bug was found and fixed in the classification step itself
(`ClassifyTrace` never had a branch for `ObjectDebug`, and separately, the bootstrap
registration of `TEXT`/`REFANY`/`ROOT`/`MUTEX` never set `.traced` at all). Both are
now fixed and confirmed via a test program whose `gcroot` coverage went from 8 calls
(partial) to 15 (comprehensive, covering everything not deliberately deferred).

| Status | Item |
|---|---|
| ✅ Confirmed reusable | `SuspendOthers` / `ResumeOthers` — unchanged, see Phase A. |
| ✅ Confirmed by build config | Target exclusivity via `TARGET=wasm32`/`M3_BACKEND=Wasm` — unchanged. |
| ✅ Resolved (Phase C) | Shadow-stack root feeding via `RTThread.ProcessStacks` reusing `NoteStackLocations` unmodified — unchanged. |
| ✅ Complete, tested (Phase A) | WTHREAD thread lifecycle, recursive heap-lock emulation, cooperative `SuspendOthers`/`ResumeOthers` — unchanged, see invariants below. |
| ✅ Complete, verified (Phase B2) | `m3t` propagation chain, end to end, for scalar and composite locals/temps. `ClassifyTrace`'s `ObjectDebug` dispatch bug and the builtin `.traced` bootstrap bug. See Phase B2 for full detail. |
| 🔲 Open (Phase B2) | Composite `gcroot` metadata is still `null` for every composite root — the metadata-synthesis step was always separate from the propagation-chain work and has not been started. |
| 🔲 Deferred, own sprint | `InitUids`'s `superType` fields (DWARF-correctness only, not `gcroot`-relevant) — see Phase B2 closing notes. |

---

## Baseline (no new work) — x86_64 / Linux via `m3llhost` + PTHREAD

Unchanged from prior versions; documented for reference only. **None of this is a
task in this plan.** `m3fe` produces target-invariant in-memory IR. `m3llhost`
(x86_64/Linux-only) emits LLVM bitcode via `M3IR_Asm`; `llc` produces object code.
The existing card-table/write-barrier/safepoint/stop-the-world/conservative-scan
collector is proven and working, via `RTThread.ProcessStacks`/`NoteStackLocations`.
`RTType`/`RTTipe`/`RTTypeMap` are runtime interfaces, linked into and executed by
the compiled *target* program, never imported by the parsing/compiler code —
confirmed, not assumed, several checkpoints back.

---

## Phase A — wasm32 Runtime Scaffolding (complete, tested)

Unchanged. `WThread.i3`/`WThread.m3`, `nthr.c`/`nthr.h`, `nthr_x86_64.c` (test
harness), `nthr_wasm32.c`, `RTSync.i3`/`nsyn.c`/`nsyn.h`. Thread lifecycle,
recursive heap-lock emulation (`RecMutex`), cooperative `SuspendOthers`/
`ResumeOthers` (via `Nexus` + five-state `Recce` watch enum) — all working, both
`SAFE_WAIT` polling timeouts eliminated. Four invariants (watch-state serialization
under `parkSyn`; before-and-after safepoint recheck around every blocking
primitive; `relief` held for the entire `SuspendOthers`↔`ResumeOthers` bracket;
role-based not module-based safepoint exemption) — unchanged, still required
reading for anything touching Phase D.

---

## Phase B1 — Safepoint Check Emission

Unchanged. Predicate fixed by Phase A testing; emitted uniformly, no per-module
exceptions.

---

## Phase B2 — GC Root Registration for Stack-Resident Values

### The `m3t` propagation chain — complete, verified end to end

Every stage of getting a real `TypeUID` from the point a value is created in the
parser to the point `AllocVar` decides whether to `gcroot` it is now built and
empirically confirmed, not merely designed:

- **`declare_temp`** carries `m3t: TypeUID` in the AST format itself — a genuine
  wire-format break (version-bumped) from the original CM3 interface, which had no
  such parameter.
- **`ClassifyTrace`** (in `AllocVar`) resolves `m3t` against `self.debugTable`,
  returning `None`/`Scalar`/`Composite`. Scalars get `gcroot` with null metadata;
  composites get `gcroot` with (currently still-placeholder) metadata; `None` gets
  an ordinary, freely-optimizable `alloca`.
- **`ValRec`** (the front end's own value-stack record, in `IR.m3`, entirely
  front-end/in-process, never serialized) now has a populated `m3t` field wherever
  it matters:
  - `Load_addr`/`Load_indirect` populate it at the point of origin (confirmed via
    `SimpleIndirectLoad`'s `x.m3t := m3t`, written *after* `FinishLoadIndirect`
    so it survives that call's field resets).
  - `Pop()`'s `VKind.Stacked` branch reads `v.m3t` (was hardcoded `M3IR.NO_UID`).
  - `Pop()`'s `VKind.Pointer` branch was routed through `Declare_addr_temp` — a
    two-line forwarder with exactly one call site and a compiler-confirmed
    "unused" warning once inlined — now inlined directly into `Pop()`, reading
    `v.m3t` the same way the `Stacked` branch does.
  - `Type.LoadScalar` computes `m3t := GlobalUID(t)` and threads it into
    `Load_indirect` for every scalar-producing `Class` (`Ref`, `Object`, `Enum`,
    `Integer`, etc.) except `Class.Set` — confirmed permanently correct to leave
    at `NO_UID`, since a set's domain must be ordinal, never traced, by the
    language's own rules, independent of representation size. The two
    global-variable-type-check-info `Load_indirect` calls in `QualifyExpr.m3`
    (`method.offset`-related) remain deliberately `NO_UID` — non-user-data.
  - **Call results**: `Call_direct`, `Invoke_direct`, `Gen_Call_indirect`,
    `Invoke_indirect` (`IR.m3`'s front-end wrappers, *not* the shared
    `M3IR_Asm.call_direct` AST interface, which was deliberately left untouched)
    now take `m3t` as a direct parameter, threaded into `PushResult`. Sourced
    from the grammar-level call-compiling code's own type-checking results —
    the same information already available at every other propagation site
    traced in this investigation (`ArrayType.GenIndex`'s `t`,
    `QualifyExpr`'s `field.type`). Applied identically to the internal
    procedures generated for `TRY`/`TRY-FINALLY` exception handling.
  - **`declare_procedure`/`import_procedure`**: `return_typeid` — present in the
    signature since the original CM3 interface, but silently dropped by the
    writer, never scanned by the reader, and never forwarded to `cg` — restored
    across all three points. This is the one place a private, `IR.m3`-internal
    lookup table was seriously considered (keyed by `Proc`, mirroring
    `TempWrapper`'s pattern for opaque `Var` handles) and explicitly abandoned:
    `Proc` is an ordinary *traced* object in this compiler's own implementation
    (confirmed), and hashing a table key on a traced reference's current address
    is unsafe under a copying/moving collector — the object can relocate,
    invalidating the bucket the entry was filed under, with no crash and no
    warning, just a silently unreachable entry. (General lesson, not wasm32/
    `gcroot`-specific — applies to the compiler's own implementation under its
    own x86_64 baseline collector. Worth remembering anywhere else in this
    codebase a reference value might be tempting to use as a hash key.) The
    table idea was superseded entirely once it was recognized `Call_direct`'s
    own caller already has the return type in hand from type-checking — no
    `Proc`-opacity workaround needed at all.

**Net result, confirmed empirically:** a test program combining scalar `REF`
locals, a composite with a traced field, an open-array parameter, a by-value
composite parameter (`byval` both on and off), and a direct pass-through
(`UseComposite(record())`, composite never assigned to a named variable) shows
`gcroot` firing correctly and only where it should, including for the
temp-pool-reused case where a composite result is never given a name at all.

### `ClassifyTrace`'s `ObjectDebug` bug — found, fixed, and worth its own pattern note

**The bug:** `ObjectDebug = RecordDebug OBJECT ... traced: BOOLEAN; ... END` — a
subtype. `ClassifyTrace`'s original dispatch checked `ISTYPE(entry, RecordDebug)`
without first checking for the more specific `ObjectDebug`, so every
`ObjectDebug`-classified type (any `OBJECT`, including the builtins `TEXT`,
`REFANY`, `ROOT`, `MUTEX`) fell into the generic record field-walk, found zero
fields (since `ObjectDebug`'s own relevant field is `.traced`, not `.fields`), and
silently resolved to `None`. High-impact — `TEXT` in particular is likely the
single most common traced type in ordinary Modula-3 code.

**The fix:** an explicit `ISTYPE(entry, ObjectDebug)` branch, checked *before* the
`RecordDebug` branch, reading `.traced` directly rather than walking fields —
object-typed storage is always pointer-represented in Modula-3 regardless of the
object's own internal layout, so this is correctly Rule 2 (scalar), never Rule 3.

**A second, independent bug this exposed, in the *data* rather than the
*dispatch*:** `InitUids`'s bootstrap registrations for `TEXT`/`REFANY`/`ROOT`/
`UNTRACED_ROOT`/`ADDR`/`MUTEX` (added, well before this investigation, purely so
lookups on these predeclared types would *succeed* — accuracy of *what* was found
was never the original goal) never set `.traced` at all. An unset `BOOLEAN`
defaults to `FALSE` in Modula-3, so even a correctly-dispatching `ClassifyTrace`
still read `FALSE` for `TEXT`/`REFANY`/`ROOT`/`MUTEX` — wrong for all four; right
only for `UNTRACED_ROOT`/`ADDR` by coincidence of the default matching their
correct value. Fixed: `traced := TRUE` added to `ROOT`/`TEXT`/`REFANY`/`MUTEX`;
`traced := FALSE` made *explicit* (not just left as the default) for
`UNTRACED_ROOT` and `ADDR` — correctness-motivated, not behavior-changing for
either of those two.

**Worth carrying forward as a template, not just a fixed instance:** this was two
independent failures stacked on each other — "the classifier can't reach the
right field" and "the field it reaches was never populated correctly" — and
fixing only one (which is what happened first, this checkpoint) produces no
visible error and no behavior change, silently. Any future extension of
`ClassifyTrace` to a new `Debug`-hierarchy type should be checked for *both*
independently: does the dispatch reach the right branch, *and* does whatever
populates that type's data do so with real values, not defaults standing in for
values nobody has stated yet. Also worth remembering generally: in any `ISTYPE`
dispatch chain, a subtype must be checked before its supertype, or the supertype
branch will silently and incorrectly claim it.

**Confirms and resolves an older open question:** an object-typed variable's own
`m3t` resolves *directly* to an `ObjectDebug` entry in `debugTable`, not through a
wrapping `PointerDebug` via `.target`, as an earlier checkpoint had reasoned (but
flagged as unverified). That reasoning was wrong; the fix above is built on the
confirmed, not assumed, structure.

### Array findings — a priori analysis, not yet acted on, recorded for the future array sprint

- **`ArrayDebug`/`OpenArrayDebug` both carry `elt: TypeUID` directly** — extending
  `ClassifyTrace` to classify either would be structurally identical to the
  `RecordDebug` fix (recurse into `ClassifyTrace(self, arr.elt)`), not a new
  design problem. Neither has a `ClassifyTrace` branch today; both correctly fall
  through the generic `ELSE => None`, indistinguishable from the deliberate
  policy of deferring arrays — worth remembering these are two different reasons
  landing on the same current answer, not one.
- **Fixed-size arrays (`ArrayDebug`) and open arrays are genuinely different
  problems, not two severities of the same one.** Classification is equally easy
  for both (same `elt` field). *Acting* on a positive classification differs
  sharply: a fixed array's element count is compile-time-known, so once (a) the
  `ClassifyTrace` branch above exists and (b) composite metadata synthesis
  (below) is built, a fixed array of traced elements could very plausibly reuse
  that *same* machinery — `RTTypeMap.Walk`'s own op-vocabulary already has an
  `Array_N`-style repeated-pattern op suited to exactly this shape, suggesting no
  bespoke encoding would be needed. Open arrays have no such path: `gcroot`'s
  one-root-per-alloca model cannot express a runtime-determined element count,
  full stop — no amount of metadata-synthesis work changes this; it needs a
  structurally different mechanism (most likely a conservative range scan)
  whenever it's picked back up.
- **Open arrays can nest** — `DebugOpenArray`'s own handling confirms an open
  array's `.elt` can itself be another `OpenArrayDebug` (multi-dimensional open
  arrays). Any future recursive walk (classification or metadata synthesis) must
  handle arbitrary nesting depth, not assume one level.
- **`DebugArray`/`DebugOpenArray`** (the DWARF-metadata consumers of these same
  `Debug` types) are a separate, unrelated consumer from `ClassifyTrace` — no
  code-path overlap, no `gcroot` hazard found there.
- Sets, enums, subranges, packed-of-ordinal: structurally guaranteed to never be
  traced by the language's own rules — permanently correct via the catch-all,
  never need individual attention.
- `IndirectDebug` (sret destinations, open-array formals): confirmed safe via two
  concrete examples (`_result1`, `oa1`), not structurally proven for every
  conceivable use — a lighter-weight assumption than the "structurally
  guaranteed" ones above.
- `ProcDebug` (procedure-type signatures, relevant to indirect-call `m3t`
  sourcing): currently resolves `None` via the catch-all; reasoned to be correct
  (M3 procedure values are code pointers, not heap-allocated closures) but not
  yet empirically tested against a procedure-valued variable directly.
- `ExceptionDebug.argType`: not a current gap, but directly relevant to the
  already-planned Phase E exception-root work — worth remembering the connection
  when that phase is picked up, not something to act on now.

### Still open

1. **Composite `gcroot` metadata synthesis** — every composite root still uses
   `null` metadata. This was always a separate piece of work from the
   propagation-chain fixes above (which only get the *classification* right) and
   has not been started. Design direction from earlier checkpoints stands: build
   the metadata as a fresh constant from `debugTable`'s `RecordDebug`/`FieldDebug`
   chain (confirmed necessary, since a record used purely by value gets no
   compiler-emitted type-map to point at instead — empirically confirmed via
   three controlled test programs), most likely reusing `RTTypeMap`'s own
   type-map encoding so the eventual Phase D/D4 walker needs no bespoke format.
2. **`QualifyExpr.m3`'s `Class.objField` case** — the `Class.recField` path
   (`Type.LoadScalar`) is fixed and verified; `objField` was explicitly deferred
   as "the complete analog" and has not yet been touched.
3. **Declaration-ordering assumption** — does `declare_pointer`/`declare_record`/
   `declare_object`/`declare_proctype` always precede any reference to that
   `TypeUID`? Still formally unverified, though a growing and diverse set of test
   programs has never triggered the `<*ASSERT FALSE*>` safety net on a genuine
   miss (every case investigated turned out to be "found, but misclassified,"
   never "not found at all") — reassuring in practice, not a substitute for
   deliberately testing a genuine forward-reference case.
4. **Object-typed *local* variable, declared directly (not via a temp, not via a
   builtin like `TEXT`)** — the `ObjectDebug` fix is proven correct for `TEXT`/
   `REFANY` reached through calls; a plain `VAR x: SomeObjectType` local has not
   been directly exercised by any test program yet. Expected to work, given the
   mechanism is now proven for the same `ObjectDebug` shape — worth a quick
   confirming test rather than assumed.
5. **Indirect-call `m3t` sourcing** (`Gen_Call_indirect`/`Invoke_indirect`) — no
   static `Proc` to read a return type from parameter-passing worked out for the
   *return type* via the direct-parameter approach above; the earlier-identified
   need to capture the *callable value's own* `m3t` into a local variable before
   it's consumed off the value stack (since it won't still be there once
   `PushResult` runs) has not been confirmed as implemented.

### Deferred to a separate, dedicated sprint (not `gcroot`-relevant — explicitly kept out of this work to avoid regression risk)

- **`InitUids`'s `superType` fields** — cross-checked against Modula-3 Language
  Report §2.2.10–2.2.11 and found wrong in three places: `ROOT` has no
  `superType` set at all (should be `REFANY`, per "`ROOT <: REFANY`");
  `UNTRACED_ROOT` has no `superType` set (should be `ADDR`, per
  "`UNTRACED ROOT <: ADDRESS`"); `REFANY`'s `superType := UID_ROOT` has the
  relationship backwards (should point at nothing — it's the top of this
  branch — with `ROOT` pointing at *it*, not the reverse). `TEXT`
  (`superType := REFANY`) and `MUTEX` (`superType := ROOT`) are already correct.
  `ClassifyTrace` never reads `.superType`, so this has no bearing on `gcroot`
  correctness — purely a DWARF debug-info accuracy question, and CM3 currently
  has minimal native debugger support regardless, so low urgency. Recorded
  precisely so it doesn't need rediscovering later.
- **`BuiltinTypes.KindUID` array vs. `LLVM_WASM.m3`'s hard-coded `UID_*`
  constants** — the compiler's own front end now computes builtin `TypeUID`s
  dynamically at startup (a `KindUID ARRAY`, indexed by builtin-type kind,
  introduced as part of the earlier global-variable/typecode work). `LLVM_WASM.m3`
  still carries a separate, independently hard-coded set of `UID_*` constants for
  the same types (`UID_INTEGER`, `UID_TEXT`, etc.) — some already computed via
  `IntegerToTypeid()`, others literal `CONST`s. Preferred future direction: have
  the backend read from `BuiltinTypes.KindUID` instead of maintaining a
  redundant, hand-maintained, parallel set of constants — unlikely to actually
  drift in practice, but removes a manual-sync hazard for no ongoing cost.
  Not urgent; noted for whenever that area is next touched.

---

## Phase C — Shadow Stack Root-Feeding: Design (resolved)

Unchanged. `RTThread.ProcessStacks` presents each thread's shadow stack as an
ordinary `(start, limit)` range to the existing, unmodified `NoteStackLocations`.
`stack_ptr`/`stack_top` argument-order pitfall (current/low first, base/high
second) still the thing to get right when Phase D writes the real loop. Composite
roots will, once Phase B2's metadata synthesis lands, be walked precisely via that
metadata rather than purely conservatively — reconcile explicitly when Phase D is
reached, not before.

---

## Phase D — Wire Shadow-Stack Scanning Into the Coordinator

Unchanged in structure. D1 (synthetic heap, deterministic scan), D2 (real GC
pressure), D3 (Large Object Space/pinning parity), D4 (deferred, optional precise
roots — now a more natural fit than before, given fixed-array metadata could
plausibly share the same `RTTypeMap.Walk`-style encoding as composites).

---

## Phase E — Exception Handling Parity for wasm32

Unchanged. Deferred until Phase D is stable. `ExceptionDebug.argType` (confirmed
this checkpoint) is the relevant field when this phase is picked up.

---

## Commit Granularity Summary

| Phase | Granularity | Rationale |
|---|---|---|
| Baseline | N/A — already done | x86_64/PTHREAD/m3llhost GC and threading is existing, working code |
| A | Complete, tested | Four invariants govern everything downstream |
| B1 | Done | Check predicate fixed by Phase A |
| B2 | Propagation chain + `ObjectDebug` fix: done, verified. 5 open items + 2 deferred-sprint items: independent, separately-landable | Metadata synthesis is the one big remaining piece; the rest are narrow, well-scoped follow-ups |
| C | Design captured, no code | Resolved; composite-metadata reconciliation noted for when D is reached |
| D (D1–D4) | Per sub-milestone | D1 first exercises Invariant 3 and the B2 design together |
| E | Per milestone | Depends on Phase D being complete and stable |
