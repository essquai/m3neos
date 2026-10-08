# Incremental Development Plan: wasm32 Threading, Safepoints, and GC Integration

**Scope:** CM3-derived Modula-3 compiler. The x86_64/Linux target, via the `m3llhost`
backend and the existing PTHREAD runtime module, is an **already-working baseline** —
proven card-table/write-barrier/safepoint/stop-the-world GC, in production use today.
This plan covers only the **new work required for the wasm32 target**, built through
the new `m3llwasm` backend and a new `WTHREAD` (implemented as `WThread`/`nthr`/`nsyn`)
runtime module.

**Revision note (this version):** Phase B2 is substantially rewritten. The original
plan (B2a: validate plain LLVM `alloca` + `__stack_pointer`/`stacksave`) was tested
directly against real compiler output and **refuted** — `mem2reg` would silently
eliminate exactly the allocas that matter (live traced pointers with no escaping
use) the moment optimization is enabled, confirmed concretely via `tmp.19` in the
first test program. The replacement design, `llvm.gcroot`, was investigated,
validated conceptually against LLVM's own documented purpose for it ("a very
portable GC for uncooperative code generators"), and then checked against three
purpose-built test programs compiled through the real `m3llhost`/`llc` pipeline.
That investigation surfaced two more real, load-bearing findings — the
`declare_temp` interface has no channel for source-level type identity at all, and
a record type gets a compiler-emitted type descriptor only when something in the
compilation unit reaches it through a `REF` — both recorded below with their
implications, not just noted as risks.

| Status | Item |
|---|---|
| ✅ Confirmed reusable | `SuspendOthers` / `ResumeOthers` as the safepoint-coordination interface — unchanged, see Phase A. |
| ✅ Confirmed by build config | Target exclusivity via `TARGET=wasm32`/`M3_BACKEND=Wasm` — unchanged. |
| ✅ Resolved (Phase C) | Shadow-stack root feeding via `RTThread.ProcessStacks` reusing `NoteStackLocations` unmodified — unchanged. |
| ✅ Complete, tested (Phase A) | WTHREAD thread lifecycle, recursive heap-lock emulation, cooperative `SuspendOthers`/`ResumeOthers` — unchanged, see invariants below. |
| ❌ Refuted, superseded (Phase B2) | Plain `alloca` relying on LLVM's own `__stack_pointer` lowering for free. Replaced by `llvm.gcroot`. See Phase B2 for the full, current design and its open items. |

---

## Baseline (no new work) — x86_64 / Linux via `m3llhost` + PTHREAD

Unchanged from prior versions; documented for reference only. **None of this is a
task in this plan.**

- `m3fe` produces target-invariant in-memory IR.
- For `M3_BACKEND=Llvm` (or `C`), the driver invokes `m3llhost` (or `m3C`), which is
  x86_64/Linux-only. `m3llhost` emits LLVM bitcode, `llc` produces x86_64 object code.
- Card table, write barrier fast-path, combined safepoint check, `m3_safepoint_cold_park`,
  and the full stop-the-world/conservative-scan/copying-generational collector are
  all implemented and working today against this codegen.
- PTHREAD implements `SuspendOthers`/`StopWorld` via `pthread_kill` + `SignalHandler`,
  gated by `ThreadState.inCritical`. Resume is a two-phase `sem_post`/`sigsuspend`
  handshake.
- `RTThread.ProcessStacks(callback)` is the abstraction point the collector calls to
  obtain root ranges, scanned conservatively and indiscriminately by
  `NoteStackLocations`/`AddressToPage`/`PromotePage`, unchanged for x86_64.
- `RTType`/`RTTipe`/`RTTypeMap` are **runtime interfaces**, linked into and executed
  by the compiled target program — confirmed not imported anywhere in the
  parsing/compiler code (`RTLinker.m3` uses them at program startup, target-side).
  `Target`/`M3IR`/`M3IR_Asm` are the compile-time family, available to `LLVM_WASM.m3`.
  This distinction, clarified mid-investigation, ruled out an earlier design
  (`AllocVar` calling `RTTipe.Get` directly) and redirected the classification
  mechanism to `LLVM_WASM.m3`'s own `debugTable` — see Phase B2.
- Exception handling (`RAISE`, re-throw cascades, root clearance) is implemented and
  working against this same x86_64 codegen and collector.

---

## Phase A — wasm32 Runtime Scaffolding (complete, tested)

Unchanged from prior version. `WThread.i3`/`WThread.m3`, `nthr.c`/`nthr.h`,
`nthr_x86_64.c` (test harness), `nthr_wasm32.c`, `RTSync.i3`/`nsyn.c`/`nsyn.h`.
Thread lifecycle, recursive heap-lock emulation (`RecMutex`), and
`SuspendOthers`/`ResumeOthers` (via the `Nexus` record and five-state `Recce` watch
enum) all working, both `SAFE_WAIT` polling timeouts eliminated in favor of pure
blocking waits.

### Invariants established in Phase A — still required reading for Phase B/D

1. Every writer of a thread's `watch` state must be serialized under `parkSyn`.
2. Any blocking primitive must recheck the safepoint on both sides of the block.
3. `relief` must be held for the entire bracketed region between `SuspendOthers`
   and `ResumeOthers`, including whatever GC work eventually runs between them.
4. The safepoint-check exemption is role-based (per-thread, via `watch`), never
   location-based (per-module) — `m3llwasm` must emit the identical check
   everywhere, uniformly.

(Full detail unchanged from prior version — not restated here to keep this revision
focused on Phase B2.)

---

## Phase B1 — Safepoint Check Emission

Unchanged. Predicate fixed by Phase A testing:

```c
if (safePoint && atomic_load_explicit(&nthr_current->watch, memory_order_acquire) != relief)
    nthr_park();
```

Emitted uniformly at every function prologue and loop back-edge, no module-based
exceptions (Invariant 4). Forward-looking note for `ThreadState.inCritical`, once
`RTAllocator` is wired to WTHREAD, unchanged: apply Invariant 2's before-and-after
recheck pattern to critical-section exit as well as to blocking waits.

---

## Phase B2 — GC Root Registration for Stack-Resident Values

### The design, as it now stands

Every alloca `m3llwasm` emits for a local, parameter, or temp is classified by its
Modula-3 type, and handled one of three ways:

1. **Untraced (scalar or ordinal, or `UNTRACED REF`)** — ordinary alloca, no
   `gcroot`, freely optimizable.
2. **Scalar traced pointer (`REF T`, or an object-typed variable/field)** —
   `llvm.gcroot(v.lv, null)`. The alloca holds a bare pointer; null metadata is
   sufficient, matching the documented convention for collectors that don't need
   per-root type information at the registration site.
3. **Composite containing a traced field, at any nesting depth (`RECORD`/by-value
   fields)** — `llvm.gcroot(v.lv, meta)`, where `meta` is a **freshly synthesized
   constant** describing the traced field offsets, built by `AllocVar` (or a helper
   it calls) directly from `debugTable`'s `RecordDebug`/`FieldDebug` chain. **Not** a
   pointer into any existing compiler-emitted global — see the type-map finding
   below for why that option is closed.

Arrays (fixed-size and open) of traced elements remain explicitly deferred, per
earlier agreement — `gcroot`'s one-root-per-slot model doesn't fit a
runtime-determined element count, and this needs separate treatment (conservative
range scan, most likely) whenever it's picked back up.

### Why plain `alloca` was refuted, not just risky

Confirmed directly against compiled output, not inferred: `mem2reg` promotes any
alloca whose address never escapes to a call, with no exception for GC relevance.
`tmp.19` (the pointer returned by `RTHooks__AllocateOpenArray`, in the very first
test program) is exactly such a case — accessed only by plain load/store, no
escaping use anywhere — and would be eliminated the moment optimization is enabled,
becoming invisible to any range-based stack scan. LLVM's own `"shadow-stack"` GC
strategy (`llvm.gcroot`) exists specifically for this situation — its own
documentation describes it as built for "uncooperative code generators" — and its
required discipline (store the value into the gcroot'd alloca before every call,
reload after) already matches `m3llhost`'s existing spill pattern, confirmed
directly in every test program reviewed.

### The classification mechanism — resolved, via `debugTable`, not `RTTipe`

`RTTipe`/`RTType`/`RTTypeMap` were an earlier candidate, ruled out once it was
confirmed they're runtime-only interfaces (see Baseline) — not importable or
callable from `LLVM_WASM.m3` during compilation at all. The actual mechanism is
`self.debugTable` (`IntRefTbl.T`, keyed by `TypeUID`), already built by
`LLVM_WASM.m3` for DWARF debug-info purposes, and confirmed to carry exactly what's
needed: `declare_pointer`/`declare_object` store `traced: BOOLEAN` directly;
`declare_record`/`declare_field` build up `RecordDebug.fields[]`, each field
carrying its own `tUid`. Confirmed populated unconditionally, not gated by
`self.genDebug`.

```
TYPE TraceKind = {None, Scalar, Composite};

PROCEDURE ClassifyTrace(self: U; m3t: TypeUID): TraceKind =
  VAR entry: REFANY; found: BOOLEAN; rec: RecordDebug; i: CARDINAL;
  BEGIN
    found := self.debugTable.get(m3t, (*OUT*)entry);
    IF NOT found THEN
      <*ASSERT FALSE*>  (* forces a declaration-ordering violation to surface
                            immediately at compile time rather than miscompile
                            silently — see the open ordering question below *)
    END;
    IF ISTYPE(entry, PointerDebug) THEN
      RETURN VAL(NARROW(entry,PointerDebug).traced, TraceKind.Scalar, TraceKind.None);
    ELSIF ISTYPE(entry, RecordDebug) THEN
      rec := entry;
      FOR i := 0 TO rec.numFields - 1 DO
        IF ClassifyTrace(self, rec.fields[i].tUid) # TraceKind.None THEN
          RETURN TraceKind.Composite;
        END;
      END;
      RETURN TraceKind.None;
    ELSE
      RETURN TraceKind.None;  (* Array/Enum/Set/Packed/Proc/etc — deferred or N/A *)
    END;
  END ClassifyTrace;
```

An object-typed variable's own `m3t` is expected to resolve to a `PointerDebug`
(whose `.target` points at the `ObjectDebug` describing the instance layout — reached
only after a conceptual dereference), not to an `ObjectDebug` directly — this
matches Modula-3's fixed representation (object variables are always
pointer-represented) and cleanly resolves an earlier ambiguity about whether
`Kind.Object`-shaped results needed null or type metadata. **Reasoned from the
table structure, not yet empirically confirmed** with a real object-typed local —
worth a quick confirming test in the same style as the composite experiments,
when convenient, not urgent.

### The type-map finding — closes one design option, confirms the other is necessary

Confirmed via three controlled test programs, compiled through the real pipeline
and inspected at both the `.ast` and `.ll` level: **a record type gets a
compiler-emitted type-map (in `v.1`, the constant segment) only when something in
the compilation unit reaches it through a `REF`/pointer type.** A record used
purely by value — never pointed at anywhere in the unit — gets no type-map filed
at all, regardless of whether it contains traced fields. Test 2 (a `composite` with
two plain `INTEGER` fields, used only by value) confirmed the absence directly; test
3 (the same shape, with one field changed to `REF INTEGER`, still used only by
value) confirmed the absence holds even when the record genuinely contains a live
traced pointer at runtime.

This **closes** the option of having `gcroot`'s composite metadata point at
existing `v.1` bytes — there is no guarantee such bytes exist for a given
composite type. The metadata **must be synthesized fresh** by the codegen itself,
built from `debugTable`'s already-available field/offset information, per the
design above. Not an open fork anymore — a settled architectural conclusion.

### `declare_temp`'s missing `m3t` — real, general, and now categorized

`declare_temp(self: U; s: ByteSize; a: Alignment; t: Type; in_memory: BOOLEAN;
typeName: Name): Var` has no `TypeUID` parameter at all — `m3t := 0` on every
`LvVar` it produces is structural, not a missed population step. `ClassifyTrace`
therefore cannot classify any temp as written, which affects every scalar
traced-pointer temp seen across all test programs (`tmp.19`, `tmp.28`, `tmp.48`),
not only the composite case that first surfaced it.

Roughly 31 call sites across the front end invoke `declare_temp`. Categorized by
the actual source of each temp's need:

- **Arithmetic/expression-result temps** — scalar only (the "accumulator register"
  pattern). No `m3t` needed at all: `ClassifyTrace`'s `t: Type` fast-path
  (`Word8..XReel`) already filters these for free, before `m3t` is ever consulted.
- **Record-by-value copy temps** — the source record's type is known at the point
  the parser decides to make the copy (that's *why* the copy is being made); `m3t`
  can be transposed directly from it. Low risk, mostly mechanical.
- **Sets** — resolved this session, need **no** `m3t` threading at all, not merely a
  deferred case. Modula-3 requires a `SET OF T` domain to be ordinal; a set can
  never contain traced content regardless of its representation (single word vs.
  multi-word bit array). Unconditionally `TraceKind.None` — a representation
  question, not a tracedness one. Drop from the propagation work entirely.
- **Open arrays** — explicitly deferred, consistent with the broader arrays
  decision. Dimension/bound information isn't available until runtime; needs
  separate study whenever arrays are picked back up.

**Implication for the interface:** `declare_temp` needs a real `TypeUID` parameter
threaded through, matching `declare_local`/`declare_param`. `m3llhost`'s own
override of the same method needs a matching signature update even though it would
ignore the value — Modula-3 method overrides aren't independently defaultable, so
this isn't a zero-touch change for x86_64, though it should be low-risk. The
larger, genuinely mechanical cost is updating the ~25 non-set, non-deferred call
sites to actually supply a value.

### Open items carried forward

1. **`declare_temp` interface change and call-site propagation** — scoped and
   categorized above; not yet implemented.
2. **Composite metadata synthesis** — architecturally decided (synthesize from
   `debugTable`, don't search `v.1`); the actual constant-building code in
   `AllocVar` (or a helper) not yet written.
3. **Declaration-ordering assumption** — does `declare_pointer`/`declare_record`/
   `declare_object` always precede any `declare_local`/`declare_temp` referencing
   that `TypeUID`? Still unverified. Safe regardless of the answer: `ClassifyTrace`
   asserts loudly on a `debugTable` miss rather than silently defaulting to `None`.
4. **Object-typed local classification** — reasoned (resolves via `PointerDebug`,
   not `ObjectDebug`, per above) but not empirically tested.
5. **Arrays (fixed and open) of traced elements** — deferred, both for
   classification and for `gcroot` itself, which doesn't fit a runtime-determined
   element count regardless.

---

## Phase C — Shadow Stack Root-Feeding: Design (resolved)

Unchanged. `RTThread.ProcessStacks` presents each thread's shadow stack (populated
per Phase B2's `gcroot` design) as an ordinary `(start, limit)` range to the
existing, unmodified `NoteStackLocations`. No changes to `RTCollector.m3`.
`thread_stack32()`/`nthr_arch_stack32()` confirmed to capture the correct
per-architecture value; the `stack_ptr`/`stack_top` argument order for Phase D's
`ProcessStacks` implementation remains the noted pitfall (current/low first,
base/high second).

*(Note: Phase C's original design assumed a conservative range scan; Phase B2's
`gcroot` composite metadata means Phase D's eventual scan will, for composite
roots specifically, walk precisely via the synthesized metadata rather than purely
conservatively — worth reconciling explicitly when Phase D is reached, not before.)*

---

## Phase D — Wire Shadow-Stack Scanning Into the Coordinator

Unchanged in structure. D1 (synthetic heap, deterministic scan), D2 (real GC
pressure), D3 (Large Object Space/pinning parity), D4 (deferred, optional precise
roots). D1 is the first point Invariant 3 becomes load-bearing in practice, not
just within `SuspendOthers`/`ResumeOthers` themselves.

---

## Phase E — Exception Handling Parity for wasm32

Unchanged. Deferred until Phase D is stable.

---

## Commit Granularity Summary

| Phase | Granularity | Rationale |
|---|---|---|
| Baseline | N/A — already done | x86_64/PTHREAD/m3llhost GC and threading is existing, working code |
| A | Complete, tested | Four invariants recorded govern everything downstream |
| B1 | Done | Check predicate fixed by Phase A |
| B2 | Per open item (5 listed above) | Design settled; `declare_temp` propagation, metadata synthesis, and the ordering/object-classification confirmations are independent, separately-landable pieces |
| C | Design captured, no code | Resolved; Phase D reconciliation note added |
| D (D1–D4) | Per sub-milestone | D1 first exercises Invariant 3 and the B2 design together |
| E | Per milestone | Depends on Phase D being complete and stable |
