# Phase D, precise roots (parked)

*Reflects plan v19, 2026-11-25. Text below is moved verbatim from dev-plan18.md (lines 2212-2263).*

<!-- v18 lines 2212-2263 -->
## Phase D — Precise Stack-Root Scanning (PARKED by decision, v14)

**Status (v14, unchanged in v15).** Parked. The v14 decision keeps roots conservative, so none of Phase D (D1–D4) is scheduled. The material below
is preserved so that nothing has to be rediscovered if the re-open conditions in "Decision (v14)" are ever met. The first step
then would **not** be this walker but address roots with null metadata (an optimiser prerequisite). ms9 gave no reason to re-open it.

Structure as before (D1–D4). Notes:

- **`RTTypeMap.i3` needs a small addition before D1 can call it: `Walk`/`DoWalkRef`
  are private to `RTTypeMap.m3`, not exported.** Resolution agreed at the time: add a new
  public entry point (`WalkStack(x, pc: ADDRESS; m: Mask; v: Visitor) RAISES ANY`)
  that calls the still-private `Walk` internally — deliberately *not* `WalkRef`, which
  does two things unsuited to a stack root: a `TYPECODE`/`RTType.Get` lookup that
  doesn't apply to a bare composite (no runtime typecode exists for one), and an
  unconditional `RTHooks.CheckStoreTraced` call — heap-page dirty-tracking machinery,
  category-confused against stack memory, which has no page descriptor or header for
  it to resolve at all. **(v14)** `RTTypeMap` is shared with PTHREAD, so this edit would itself be a variance from the
  baseline; the alternative is a small refs-only interpreter in `WThread` (ops `Ref`, the skips and `Stop`).
- **The `refs_only` finding (Phase B2) is believed sufficient but needs finalizing
  here, not assumed.** `TypeComp`'s output only ever contains `Op.Ref`/`Op.Stop`. That
  likely makes `WalkStack`'s `mask` parameter a non-issue in practice, but this should
  be confirmed explicitly once D1's synthetic-heap test is being built, alongside
  resolving the still-open `type_map`-vs-`gc_map` question from Phase B2.
- **Where the chain head comes from.** Parked threads: read the head
  `nthr_park` published in the thread context. The thread running the collection holds
  `relief` and never parks, so its own chain head is its live thread-local — to be
  confirmed in D1. Also to confirm in D1: threads inside **blocking primitives**
  (Phase A invariant 2) must also have a published head, i.e. that path goes through
  the same publish step as `nthr_park` — `nthr_vigil` now does (register 21, closed).
- **Aggregate root-slot addressing — open design question for D1 (register 13).** The
  walker needs, for each composite root, the *address* of its slot and its metadata. **Verified in v14 on LLVM 18.1.3:**
  the lowered frame entry is a struct `{ {next, map}, <each root in its own type> }`; metadata-bearing roots come **first**,
  packed contiguously with no alignment padding (alloca alignment is dropped, bug 2), then scalar roots at the next 8-byte
  boundary; the frame map is `{i32 NumRoots, i32 NumMeta, ptr meta[NumMeta]}` with no sizes or offsets. A stride-by-pointer
  walk therefore misreads any frame with an aggregate. Options considered (v14): (1) scalar-only frames (`NumMeta = 0`),
  stride 8; (2) put each aggregate's byte size in its metadata and recompute LLVM's layout (fragile: an upstream fix of the
  alignment bug would silently shift offsets); (3) **address roots** — the aggregate stays an ordinary aligned alloca, the
  gcroot slot holds its address, and the metadata describes the pointee (every root is one pointer; retires the marker
  workaround and both LLVM-bug dependencies for this path; scales to arrays; the preferred form if aggregates ever need
  rooting); (4) a precise-root API in the collector (rejected: breaks the principle, unsound with unrooted derived copies).
- **The root walker must tolerate roots that point outside the traced heap
  (register 14).** Such roots already exist: `phaseB`'s `t` is initialised to a static
  text literal in `M_Const`, and an open-array parameter slot holds the caller's dope
  address until its re-point. The walker must recognise and skip non-heap addresses,
  rather than treating every root value as a heap pointer. (Address roots with null metadata would hold stack addresses,
  which are also non-heap.)
- **Registers as roots (v12).** Each stopped thread's `regs` (x86_64 callee-saved registers
  spilled by the assembler when it publishes the stack) are conservative roots; on wasm32 the
  array is zero. See register 26. **v13:** `ProcessStacks` passes them (Phase C).

---


