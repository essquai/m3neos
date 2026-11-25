# Phases B1 and B2

*Reflects plan v19, 2026-11-25. Text below is moved verbatim from dev-plan18.md (lines 1129-1744).*

<!-- v18 lines 1129-1744 -->
## Phase B1 — Safepoint Check Emission (implemented, validated on x86_64)

**Position.** Phase B (wasm32 codegen and garbage collection), step B1 = the safepoint
poll, built over the shadow-stack root scheme. Implemented and validated on the
x86_64 `phb.ll`. Exception handling stays deferred to Phase E; x86_64 stays frozen apart
from LLVM-toolchain modernisation. The next big step for the compiler is producing the wasm32
target, which needs some tweaking first (register items 3, 8) and depends on Phase L
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
**(v14)** This is the whole reason gcroot is kept: it is a visibility guarantee (see "Decision (v14)").
Measured effect: with the gcroot calls present, `opt -O2` leaves exactly the rooted slots in memory; with them removed it
promotes every pointer alloca.

**The first argument must be a pointer-typed alloca (v15, register 47).** LLVM 18.1.3's verifier rejects
`llvm.gcroot` whose first argument is not a pointer-typed alloca unless the metadata argument is a non-null constant
(`llvm.gcroot parameter #1 must either be a pointer alloca, or argument #2 must be a non-null constant`). A scalar root must
therefore be a variable whose representation is a pointer. `ClassifyVar` enforces this where the decision is made
(see "`m3t` propagation chain and `ClassifyTrace`" below).

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

**Frame layout facts (v14, LLVM 18.1.3, recorded for the dormant composite path; detail in the analysis note).** The lowering
puts metadata-bearing roots **first**, packed contiguously with no alignment padding after a 16-byte header, then the scalar
roots at the next 8-byte boundary. The frame map is `{NumRoots, NumMeta, meta[NumMeta]}` and carries no sizes or offsets.
A walker that strides by pointer size would therefore misread any frame containing an aggregate; this is register 13, parked.

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
`AllocVar` whenever the variable classification (`ClassifyVar` since v15) returns anything other than `None`; composite
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
  published head is therefore valid only for a *parked* thread. **(v14)** Nothing reads the
  published chain at present (roots are conservative); it is maintained for the parked parts of the protocol and in case
  precise roots are ever re-opened.
- Validated empirically on **both wasm32 and x86_64** in a separate session.
- A **thread-local intrinsic** was added to the backend's intrinsic set; it is needed
  for atomic accesses to thread-local variables.
- **TLS model.** `GeneralDynamicTLSModel` is set for the nthr variables in the x86_64
  target condition, because the WTHREAD module is also built as a shared library (the
  `LocalExecTLSModel` alternative is commented out; both arms of the `isWasm` test currently set
  the same model). The chain declaration is kept alive against `opt` by a global named
  `llvm.compiler.used` holding `gcchainVar` (built with `LLVMArrayType`/`LLVMConstArray`);
  accepted as an escape hatch. **(v14)** Measured cost of the chain maintenance: about 1.5 ns per call of a function with
  roots on x86_64 with general-dynamic TLS (analysis note); wasm32's TLS access is different and unmeasured.
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
**(v15)** ms9's by-value aggregates (`AggArr`, 72 bytes) exercised this path (`b := a`, the `VALUE` parameter) with correct results.

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
- **v14:** the ms8 build (also `m3llwasm`, x86_64 mode, `llc -O0`) carries 14 and 15 scalar gcroots in its two busiest
  functions and ran 13 collections cleanly; the audit passes on its IR (Decision (v14)).
- **v15:** the ms9 build (twelve subjects, open arrays, views, by-value aggregates, text) verified and linked after the
  `ClassifyVar` fix (register 47) and ran in more than twenty runs; the user's IR for the failing module passed `llc`,
  `llvm-as` and `llvm-dis` once the single offending gcroot was removed, which is what the fix does. **The ms9 IR has not been
  through the audit script** (register 42).

### B1 open items and parked

See the consolidated register. In short: loop-edge polls are done (v11); what remains is wasm32
enablement and cleanup.

**Loop-edge safepoint polls — implemented (closed in v11; recorded 2026-10-08).** The
function-entry poll alone does not bound time-to-safepoint for a call-free loop, so the
user added a poll on every back-edge. Codegen shape: a back-edge jumps to a **label already
placed**, so the poll goes on the **taken side** of the back-edge, and the flow block
returned by `EmitSafepointCheck` is the continuation. Exercised in v11 by six generated
test procedures with nested loops and IFs (B1.9). **(v15)** A reminder from ms9: on the `m3llhost`
build a spin loop `WHILE ms9.stage < s DO INC(spinner) END` has no poll and hung the stop-the-world; the `m3llwasm` build (with
loop-edge polls) completes. The harness spin loops depend on the loop-edge poll.

**Nested procedures on wasm32 (parked until v16; addressed in v16).** `llc` rejects the `nest` static-link
attribute ("WebAssembly hasn't implemented nest arguments"). The static link is the
**hidden first parameter**, spilled to `__StoredStaticLink` (the first alloca). Nested
procedures remain open and may affect the AST (nested procedures can be deferred and
treated serially, which complicates up-level access). **Deliberately deferred.** The
static link's slot is built by the same `begin_procedure` loop as ordinary parameters and
also receives `memVar.inProc := param.inProc` (kept symmetric with the parameter
slots); it is expected to be reworked when nested procedures are picked up.

**(v16) Addressed.** The wasm backend does not implement `nest`, so `LLVM_WASM.m3` no longer sets it (on the static-link formal in `BuildFunc`, keeping `<* ASSERT i = 0 *>`, or at the call site in `InnerCallIndirect`). The static link is an explicit leading `i8*` parameter; `call_invoke_indirect` emits a variant with and a variant without the static link; FINALLY handlers take the static link only. In `RTExFrame.m3`, `FinallyProc = PROCEDURE () RAISES ANY`, `CallProc (p: FinallyProc) RAISES ANY = BEGIN p (); END CallProc`, and `InvokeFinallyHandler` calls `CallProc (LOOPHOLE (ADR (cl), FinallyProc))`. The library builds and the hello-world runs with this; **no dedicated test of up-level access has run** (register 62). Hazards recorded: the closure test in `CallProc` against wasm32 procedure values, which are table indices (register 54), and `Compiler.ThisException ()` in a FINALLY body, which reads through the static link (pre-existing).

---

## Phase B2 — GC Root Registration for Stack-Resident Values

### `m3t` propagation chain, `ClassifyTrace` and `ClassifyVar` — complete

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

**`ClassifyVar` (v15, register 47, closed).** `ClassifyTrace(self, m3t)` is a pure function of the type UID. A variable is
more than its type UID: the front end sometimes declares a temporary whose UID names one type and whose representation is
another. The case found by ms9 is the dope temporary of an open-array `NEW`: `cmd/m3fe/src/builtinOps/New.m3`, `GenOpenArray`,
declares the 24-byte struct temporary with `m3t := Type.GlobalUID(t)`, the UID of the `REF` type. `ClassifyTrace` therefore answered
`Scalar`, `AllocVar` issued `llvm.gcroot` on a struct alloca, and the LLVM 18.1.3 verifier rejected the module
(`%tmp.412`). The fix is a per-variable wrapper in `cmd/m3be/llvm18wasm/src/LLVM_WASM.m3`, called from `AllocVar` in place of the
direct `ClassifyTrace` call:

```modula3
PROCEDURE ClassifyVar(self: U; v: LvVar): TraceKind =
VAR tk := ClassifyTrace(self, v.m3t);   (* type-only, unchanged *)
BEGIN
  (* A Scalar root is one traced pointer in a pointer-typed slot. *)
  IF tk = TraceKind.Scalar AND v.type # Type.Addr THEN
    RETURN TraceKind.None;
  END;
  RETURN tk;
END ClassifyVar;
```

Why this form and not the alternatives considered: (1) overriding the result after the call in `AllocVar` is the same decision
in the wrong place; (2) changing `ClassifyTrace` would make a pure type function depend on a variable; (3) changing the front end's
`m3t` for that temporary would change the AST both targets read, which the frozen baseline forbids for no gain. The consequence
is that the dope temporary is not a root: it holds a raw data pointer and its holder is the rooted `REF` (the derived-copy rule;
open-array dope temporaries were already on the audit list, see Deferred scope). Evidence: removing that single gcroot let the whole
module pass `llc`, `llvm-as` and `llvm-dis`; the user's ms9 runs worked. A latent front-end inconsistency remains (register 50); it needs no action.

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
`modRec` in `phb.ll` show this: no alloca, no spill. **(v15)** ms9's `aggValProc(ms9, cp: AggArr)`
takes a 72-byte by-value record array; the front end warns "Large parameter passed by value (72 bytes)" and the
copy-in, the callee's copy as sole holder, and the survival of both levels of referents across six collections all behave correctly.

**By-reference formals** (`VAR`/`READONLY` passed by address). Their `m3t` is the
`declare_indirect` UID, `−(referent + 1)`, and the slot holds an address. They classify
as `None` and are not roots. **The sign of a UID cannot be used to recognise them:**
legitimate UIDs can be negative (e.g. `TestB`'s `−814819607`), and the indirect UID of
a negative target is positive. They are handled correctly today because `declare_indirect`
registers a non-tracing entry in `debugTable` (inferred from the fact that
`ClassifyTrace`'s miss-assert never fires for them; confirm if `declare_indirect` is
touched). **(v15)** The miss-assert did not fire in ms9 either, which uses `VAR`, `READONLY`, `VALUE` open-array and `SUBARRAY` formals.

**Root-ownership rules.**

| Storage | Rooted? | Why |
|---|---|---|
| Value parameter slot of a traced type (`REF T`, object, `TEXT`, traced opaque) | **Yes** — scalar root, null meta; the spill initialises it | The slot is the callee's own mutable variable and may hold the only reference to something (it can be reassigned). |
| Value parameter slot of a non-traced type (`INTEGER`, subrange, enum, proctype) | No | Classifies `None`. |
| By-reference parameter slot (`VAR`/`READONLY`) | No | Holds an address, not an object. The referent's owner roots it. |
| By-value record parameter | No slot in the callee | The caller's `pop_struct` temporary is the composite root. |
| Front-end temporary printed `Addr -1` | No | See the derived-copy rule below. |
| Open-array `NEW` dope temporary (a struct declared with the `REF` UID) | No (v15) | `ClassifyVar`: not pointer-represented; the holder of the `REF` spans the call. |
| Open-array VALUE parameter | Exercised in v15; see Deferred scope | The formal is re-pointed at a heap copy; at `-O0` the slot is an alloca in the scanned range. |

**The derived-copy rule (audit rule for unrooted `Addr -1` temporaries).** An unrooted
temporary is safe only if a *rooted* holder of the same object spans every safepoint
over which the temporary is live. The check is made per temporary: find the rooted
holder (a local, a parameter slot, a global, or a field of a rooted object). The rule
also depends on stack-referenced objects being pinned, i.e. on Phase C's pinning
(register 25a). **(v14)** With roots conservative and the optimiser excluded, every front-end temporary is an alloca in
the scanned range, so the rule is satisfied by construction and the audit gate checks it mechanically (it counts any pointer
value that crosses a safepoint in an SSA value without a memory home). It becomes a hard requirement only in Phase O. Audited
so far, at the earlier snapshot: `v.97`,
`v.100`, `v.101` (audited when first found) and `v.118`. `v.118` is the `Stdio.stdout` copy
in `phaseB` (`tmp.134`): it is loaded from the `Stdio` interface's slot, a
`CheckLoadTracedRef` call (a safepoint) follows, and then it is stored to the rooted local `w`.
The `Stdio.stdout` global holds the same object across that call, and `w` holds it afterwards.
The rule relies on module globals being scanned as roots (Phase C).

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
- **Runtime evidence (v14, v15):** the ms8 and ms9 runs execute generated code with rooted parameters under the
  collector without failure. Because roots are conservative this does not by itself prove the rooting is complete; the audit
  gate is the check that matters.

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

### Composite `gcroot` metadata — complete (dormant since v14)

**Status (v14).** Built, byte-verified and retained, but **not consumed by anything**: the collector reaches heap records
through the front end's typecell maps, and stack aggregates are seen by the conservative scan with no map. ms8 contains no
composite gcroot at all (no `meta.N` globals). Kept as is; not extended. See "Decision (v14)". **(v15)** Nor did ms9 need it: the
by-value `AggArr` (a local, a parameter and a global) was served by the scan and the heap type maps alone.

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
- `LLVMBuildAlloca`, then `ClassifyVar(self, v)` (v15; formerly `ClassifyTrace(v.m3t)`) → `None`/`Scalar`/`Composite`.
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

**Where each map is used (clarified v14).** Heap records and objects reach the collector through the front end's typecell
maps (`RefType.InitTypecell`; objects likewise); that is the path ms8 exercises and it is the existing, proven one. `TypeComp`
metadata describes **stack-resident aggregates** only (by-value record locals, parameters and temporaries in a gcroot frame),
a case no existing x86_64 mechanism covers, and which the conservative scan covers without a map.

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
- **A temporary's `m3t` is not a guarantee about its representation (v15).** The open-array `NEW` dope temporary is the case
  found; `ClassifyVar` guards the root decision. Any future classification that acts on a variable (rather than on a type)
  should go through `ClassifyVar`.
- **Unrooted copies need a rooted holder** (the derived-copy rule above). It is an
  audit made per `Addr -1` temporary, and the front end's temporary reuse can hide a
  violation. **(v14)** The audit gate (register 42) now performs this check mechanically on the IR.

### Still open, narrowly

1. Declaration-ordering assumption (`<*ASSERT FALSE*>` on a `debugTable` miss) — still
   never triggered across an increasingly large and varied test set (ms9 added open arrays of several depths, views, by-value
   aggregates and text); formally unverified.
2. Why `RTTypeMap.WalkRef` consumes `.type_map` rather than `.gc_map` at actual
   collection time, given `.gc_map` is the narrower, purpose-matched field. Doesn't
   block anything (the comparison methodology is valid regardless), but is unexplained.
   **(v14)** No longer needed before any scheduled work (it was a Phase D prerequisite, now parked).

### Deferred scope

**`BITS N FOR T` (packed fields).** Out of scope, and the reasoning bounds the risk
precisely rather than just deferring it: `BITS N FOR T` requires `T` to be ordinal, so
a packed field can never itself be a `REF`. It matters only for a *traced* record that
also contains an unrelated packed field elsewhere — the gap is entirely about
`TypeComp` correctly *stepping over* a packed field's bits when computing subsequent
offsets, never about a packed field being reported as a root. Fix when a real test
case surfaces it; not a correctness risk to anything currently in scope.

**Arrays (updated v15: exercised by ms9).** `ArrayDebug`/`OpenArrayDebug` both carry `elt: TypeUID`, so classification
is structurally easy; *acting* on it differs sharply between fixed arrays
(compile-time-known count; could plausibly reuse `TypeComp`'s `Array_N`-family opcodes
once built) and open arrays (structurally incompatible with `gcroot`'s
one-root-per-alloca model; needs a different mechanism entirely). Open arrays can
nest (`.elt` can itself be an `OpenArrayDebug`), so any future recursive handling must
handle arbitrary depth, and multi-dimensional arrays add more sizes to the dope vector.
Fixed arrays of traced references are **not rooted today** (arrays classify as `None` by decision), as in ms8's
`a[]` owner arrays. Under the current scheme they are visible anyway, because at `-O0` they are allocas in the scanned
range; they would need rooting (address roots with null metadata, see "Decision (v14)") only if an optimiser is ever added.
**Runtime facts established by ms9 (x86_64, `-O0`):** a heap `REF ARRAY OF T` is one object, the dope (an elements pointer at
offset 0, then one size word per open dimension: 8 + 8·d bytes) followed by the data; when the collector moves it, `Move` rewrites
the elements pointer as `np + def.dataSize`. A fixed `REF ARRAY [1..N] OF T` has no dope and points straight at element 1. Open-array
formals are indexed from 0 whatever the actual's bounds were. Verified for depth 1, 2 and 3, bytes and `REF` elements, an open outer
dimension over a fixed inner one, and a three-dimensional by-value copy.

*The open-array VALUE parameter copy (register 11).* In `phb.m3`'s `number`, the
callee copies a VALUE open-array argument: the parameter slot (`oa1`) starts as the
address of the caller's dope vector, `RTHooks.AllocateOpenArray` makes a heap copy, and
the slot is then **re-pointed at the heap copy**. After that the slot is the logical sole
holder, yet the copy is rooted only through `tmp.66`, which the front end's temporary
pool may reuse. It was safe because nothing allocates between the re-point and
`ret`. **(v15, ms9)** The runtime behaviour is now validated for a body that waits through six collections: the front end warns
"Open array passed by value" and `Variable.CopyOpenArray` does `NewTracedArray` plus `Copy_n` over the product of the open sizes and
re-points the formal in `LangInit`; the copy is complete at entry, the callee's writes never reach the source (the source is read back
as 103 and 109 after the callee wrote 100), the source reference may be dropped, and the copy survives at every collection, for a
1-D `SUBARRAY` and for a 6 by 9 by 3 array. What remains is the *wasm32* question: the slot must be in memory the scan covers
for the whole body, which the audit gate and the wasm32 smoke test check (registers 42, 44).
Related: open-array **dope-vector
temporaries** (`Struct -1`, e.g. `tmp.135` in `phaseB`, which holds `{ptr @M_Main+104,
i64 3}`) are unrooted and hold a raw data pointer; for a heap-backed array the holder of
the `REF` must span the call. **(v15)** The open-array `NEW` dope temporary is the same kind of object and is now explicitly not a root (`ClassifyVar`).

---


