# Baseline and Phase A

*Reflects plan v19, 2026-11-25. Text below is moved verbatim from dev-plan18.md (lines 729-777, 844-1128).*

<!-- v18 lines 729-777 -->
## Baseline (no new work) — x86_64 / Linux via `m3llhost` + PTHREAD

**Clarification (v18): three x86_64 flavours.** In practice the baseline is the **default build**: the C back end (`m3C`, never modified, so by definition unchanged) with PTHREAD and signal-based thread stopping. `-DM3_BACKEND=Llvm` builds the same runtime through `m3llhost` to LLVM bitcode (still PTHREAD, no cooperative safepoints). `-DM3_BACKEND=Wasm` builds through `m3llwasm` with WThread and cooperative polls, on x86_64 as well as wasm32. Only one flavour can be installed at a time ("Build flavours and the installed library (v18)"). Where this section says `m3llhost`, read it as the LLVM variant of the baseline.

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
those printed as `Addr -1` carry no type and classify as `None`. **(v15)** A temporary's
`m3t` is not always the type of its *representation*: the dope temporary of an open-array `NEW` (`New.m3`, `GenOpenArray`)
is declared with the `REF` type's UID but is a 24-byte struct; `ClassifyVar` (register 47) is the guard.

**Build pipeline fact (v14).** The `m3neos` driver compiles each unit with `m3front`, then `m3llwasm -b -g -t <target>`, then
`llc -frame-pointer=all -mtriple=<target> --dwarf-directory=0 -filetype=obj -relocation-model=<llvmback_pic> [<llvmback_features>] -O0`
(v16: `llvmback_pic` is `pic` by default and `static` for wasm32; `llvmback_features` is empty except for wasm32, where it is
`-mattr=+atomics,+bulk-memory,+mutable-globals`). **There is no optimiser in the pipeline**
(confirmed by the user from the full command listing). This is the premise of the optimiser constraints above. **(v17)** The `llc` line now also carries
`+exception-handling -exception-model=wasm -wasm-enable-sjlj -wasm-use-legacy-eh=true` on wasm32, and `m3llwasm` itself runs LLVM's `shadow-stack-gc-lowering`
over the module just before it writes the bitcode (a lowering, not an optimiser; the `.ll` it prints is the unlowered form). Each back-end package links its own version of the LLVM FFI: `llvm18host` and `llvm18wasm` import `llvm18api`, `llvm22host` and `llvm22wasm` import
`llvm22api`, and each `*api` package names its version-specific LLVM libraries in its `m3makefile` and carries a `Version.i3`. Both `llvm18wasm` and
`llvm22wasm` build a program named `m3llwasm` (and the two host packages one named `m3llhost`): the one built and installed last is the one that runs.
The `llc` that the compiler scripts call is **not** version-specific: it is whatever `llc` is configured as the default (`update-alternatives`), so the
back end and `llc` can disagree about the LLVM version (register 63).

**Runtime parameters used by the harnesses (v15, reference).** `@M3traced=<n>[K|M]` and `@M3untraced=<n>[K|M]` cap the traced and
untraced arenas (a plain number is bytes); `@M3virtual=<n>` is retained as the temporary WAMR workaround; `@M3noincremental`
selects stop-and-copy collection (`RTCollector.Init` checks `noincremental`; `nogenerational`, `nogc`, `heapstats` and
`paranoidgc` exist as well). Capture both stdout and stderr (`2>&1 | tee`).

---


<!-- v18 lines 844-1128 -->
## Phase A — wasm32 Runtime Scaffolding (complete, tested; parking revised in v11; join/reap revised in v12; `nthr_lock` and the lock rules in v13)

The parking protocol was revised in v11, the exit/join/reap protocol in v12, and the lock path
and the watch-transition rules were recorded in v13 (see the three addenda at the end of this
section); the four invariants stand. Files: `WThread.i3`/`.m3`,
`nthr.c`/`.h`, `nthr_x86_64.c`/`nthr_wasm32.c`, `nthr_sysv.s`/`nthr_wasi.s`,
`RTSync.i3`/`nsyn.c`/`.h`. Four invariants (watch-state serialization under
`watchSyn`, formerly `parkSyn`; before-and-after safepoint recheck around blocking primitives;
`relief` held for the entire `SuspendOthers`↔`ResumeOthers` bracket; role-based not
module-based safepoint exemption) — unchanged. (Phase D is parked as of v14, but these invariants remain required for
every blocking primitive.)
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
the `ms4` or `ms7` runs (13 collections in the last `ms7` run); none was seen in the `ms8` runs either.
**(v15)** ms9 ran up to twelve threads (four of them allocating flat out) through 11 collections per run, in more than twenty runs, with no hang and no
`NOPARK`; the only aborts were the out-of-memory errors of the capped-heap runs (register 41), which are a different failure.

---


