# Analysis note: wasm32 visibility, the SSA-across-safepoint audit, and the optimiser constraints

**Companion to plan v14 (2026-10-31).** The plan carries the decision ("roots are conservative; gcroot keeps traced values in memory")
and the constraints on the optimiser and `llc` levels. This note carries the evidence and the method, so that nothing has to be
rediscovered and so that the checks can be rerun on `neocore` wasm32 bitcode once we can compile for that target.

All experiments ran in my sandbox (not on the user's tree): LLVM 18.1.3 (`llc`, `opt`, `clang`, `wasm-ld`), Node 22, x86_64 Linux,
2 cores. The user's build pipeline (confirmed from the command listing) is `m3front`, then `m3llwasm -b -g -t <target>`, then
`llc -frame-pointer=all -mtriple=<target> -filetype=obj -relocation-model=pic -O0`, then a C/C++ link. **There is no optimiser.**

Contents: 1. wasm32 visibility harness; 2. the audit; 3. what an optimiser does to ms8's IR; 4. `llc` codegen levels; 5. the cost of
gcroot; 6. shadow-stack frame layout; 7. the `-O0` spill-slot pins; 8. bounded-heap arithmetic; 9. notes on optimiser benefit;
10. the ms8 stay-accounting script.

---

## 1. wasm32 visibility harness

**Question.** On wasm32, does a conservative scan of the thread's linear-memory stack range (from `__stack_pointer`, the
`nthr_arch_stack32` mechanism, to the stack top) see (1) gcroot slots, aggregates and nested gcroot frames, and (2) ordinary
variables; and does it miss a pointer held only in a wasm local?

**Method.** A freestanding wasm32 module (no libc, single thread). A fake heap of 32 pages of 4 KB; source pointers live in static
data so that nothing on the stack holds them except what each case puts there. Hand-written LLVM IR cases (below) each call
`probe(k)`, which scans every aligned word from its frame address (and, independently, from `__stack_pointer`) up to the entry
function's frame address, records which fake-heap pages were seen, and walks `llvm_gc_root_chain` checking that every frame lies
inside the scanned range. A `scrub()` between cases zeroes 4 KB below the entry frame so stale words cannot leak between cases.
The host (Node) reads the results out of linear memory.

Build and run:

```
clang --target=wasm32 -O0 -ffreestanding -nostdlib -c t.c -o t.o
llc -O0 cases.ll -filetype=obj -o cases.A.o                      # pipeline A: the current pipeline
opt -O2 cases.ll -o cases.B.bc && llc -O2 cases.B.bc -filetype=obj -o cases.B.o   # pipeline B: optimiser added
wasm-ld --no-entry --export=entry --export=found --export=found_sp --export=sp_val \
        --export=chain_n --export=chain_in --export=range_lo --export=range_hi t.o cases.A.o -o A.wasm
node run.mjs A.wasm "label"
```

**Results.**

| Case | `llc` -O0 | `llc` -O1, -O2, -O3 (no `opt`) | `opt -O2` + `llc -O2` |
|---|---|---|---|
| 1. scalar variable, gcroot | found | found | found |
| 2. record with a `REF` word at offset 8, gcroot + metadata | found | found | found |
| 3. ordinary variable (alloca), no gcroot | **found** | **found** | **not found** (promoted) |
| 4. pure SSA value live across the call | **not found** | **not found** | **not found** |
| 5. control (value dead before the call) | not found | not found | not found |
| 6. two nested gcroot frames (pages 6 and 7) | found, chain 2 frames | found | found, chain 1 frame (callee inlined) |

For every case and pipeline: the scan from `__stack_pointer` gave exactly the same result as the scan from the frame address, with
`sp <= frame address`; every gcroot frame on the chain lay inside the scanned range.

**Conclusions.** (1) The conservative scan sees gcroot frames and aggregates in linear memory with no type map. (2) In the current
pipeline ordinary variables are visible without any gcroot, because they are allocas; the hazard is exactly a value with no memory
home (case 4). (3) `llc` codegen levels 0 to 3 do not change visibility for these patterns. (4) An IR-level optimiser promotes
unrooted allocas out of memory (case 3) while the gcroot'd cases stay visible.

**Limits.** Single thread, scanning its own stack; another thread's stack is the same shared linear memory but the publication of its
`sp`/top at park time on wasm32 is covered only by the earlier node thread harnesses. The heap is a stand-in. The IR is hand-written,
not `m3llwasm` output. Four cases are the patterns that matter, not a proof for all code; the audit (section 2) covers real output.

**Sources.**

`t.c`:

```c
/* wasm32 visibility test: which values does a conservative scan of the
   linear-memory stack range find?  Freestanding, no libc, single thread. */
typedef unsigned u32;
#define HEAPSZ (32*4096)
char heap[HEAPSZ] __attribute__((aligned(4096)));   /* fake "traced heap", 4 KB pages */
void *src[8];            /* source pointers live in static data, NOT on the stack */
void *sink;
u32 found_sp[8], sp_val[8], found[8], chain_n[8], chain_in[8], range_lo[8], range_hi[8];
void *llvm_gc_root_chain;                            /* shadow-stack chain head */
static u32 stack_top;

struct StackEntry { struct StackEntry *next; const void *map; void *roots[]; };

__asm__(".globaltype __stack_pointer, i32\n");
static inline u32 get_sp(void){ u32 sp; __asm__ volatile("global.get __stack_pointer\n\tlocal.set %0" : "=r"(sp)); return sp; }

void probe(int k) {                                  /* stands for "a stop-the-world scan" */
  u32 lo = (u32)__builtin_frame_address(0);
  u32 hi = stack_top, f = 0, n = 0, in = 0;
  range_lo[k] = lo; range_hi[k] = hi;
  for (u32 a = lo & ~3u; a < hi; a += 4) {           /* conservative: every aligned word */
    u32 w = *(volatile u32 *)a;
    if (w >= (u32)heap && w < (u32)heap + HEAPSZ) f |= 1u << ((w - (u32)heap) / 4096);
  }
  found[k] = f;
  { u32 sp = get_sp(), g = 0; sp_val[k] = sp;
    for (u32 a = sp & ~3u; a < hi; a += 4) { u32 w = *(volatile u32 *)a;
      if (w >= (u32)heap && w < (u32)heap + HEAPSZ) g |= 1u << ((w - (u32)heap) / 4096); }
    found_sp[k] = g; }
  for (struct StackEntry *e = llvm_gc_root_chain; e; e = e->next) {   /* chain cross-check */
    n++; if ((u32)e >= lo && (u32)e < hi) in++;
  }
  chain_n[k] = n; chain_in[k] = in;
}

void scrub(void) { volatile char a[4096]; for (int i = 0; i < 4096; i++) a[i] = 0; }
static void init_src(void) { for (int i = 0; i < 8; i++) src[i] = heap + i * 4096 + 24; }

extern void case1(void), case2(void), case3(void), case4(void), case5(void), case6(void);
void entry(void) {
  init_src();
  stack_top = (u32)__builtin_frame_address(0);
  scrub(); case1(); scrub(); case2(); scrub(); case3();
  scrub(); case4(); scrub(); case5(); scrub(); case6();
}
```

`cases.ll`:

```llvm
target datalayout = "e-m:e-p:32:32-p10:8:8-p20:8:8-i64:64-n32:64-S128-ni:1:10:20"
target triple = "wasm32-unknown-unknown"
@llvm_gc_root_chain = external global ptr
@llvm.compiler.used = appending global [1 x ptr] [ptr @llvm_gc_root_chain], section "llvm.metadata"
@src = external global [8 x ptr]
@sink = external global ptr
@meta = internal constant [3 x i8] c"\01\02\03"
declare void @llvm.gcroot(ptr, ptr)
declare void @probe(i32)

define void @case1() gc "shadow-stack" {           ; scalar variable, gcroot'd
entry:
  %p = alloca ptr
  call void @llvm.gcroot(ptr %p, ptr null)
  %sp = getelementptr ptr, ptr @src, i32 1
  %v = load volatile ptr, ptr %sp
  store ptr %v, ptr %p
  call void @probe(i32 1)
  %w = load ptr, ptr %p
  store volatile ptr %w, ptr @sink
  ret void
}
define void @case2() gc "shadow-stack" {           ; aggregate with a reference at offset 8
entry:
  %rec = alloca [16 x i8], align 4
  call void @llvm.gcroot(ptr %rec, ptr @meta)
  store i8 0, ptr %rec
  %sp = getelementptr ptr, ptr @src, i32 2
  %v = load volatile ptr, ptr %sp
  %f = getelementptr i8, ptr %rec, i32 8
  store ptr %v, ptr %f
  call void @probe(i32 2)
  %w = load ptr, ptr %f
  store volatile ptr %w, ptr @sink
  ret void
}
define void @case3() {                             ; ordinary variable, not rooted
entry:
  %q = alloca ptr
  %sp = getelementptr ptr, ptr @src, i32 3
  %v = load volatile ptr, ptr %sp
  store ptr %v, ptr %q
  call void @probe(i32 3)
  %w = load ptr, ptr %q
  store volatile ptr %w, ptr @sink
  ret void
}
define void @case4() {                             ; pure SSA value live across the call
entry:
  %sp = getelementptr ptr, ptr @src, i32 4
  %v = load volatile ptr, ptr %sp
  call void @probe(i32 4)
  store volatile ptr %v, ptr @sink
  ret void
}
define void @case5() {                             ; control: dead before the call
entry:
  %sp = getelementptr ptr, ptr @src, i32 5
  %v = load volatile ptr, ptr %sp
  store volatile ptr %v, ptr @sink
  call void @probe(i32 5)
  ret void
}
define void @case6() gc "shadow-stack" {           ; two nested gcroot frames
entry:
  %p = alloca ptr
  call void @llvm.gcroot(ptr %p, ptr null)
  %sp = getelementptr ptr, ptr @src, i32 6
  %v = load volatile ptr, ptr %sp
  store ptr %v, ptr %p
  call void @case6b()
  %w = load ptr, ptr %p
  store volatile ptr %w, ptr @sink
  ret void
}
define void @case6b() gc "shadow-stack" {
entry:
  %p = alloca ptr
  call void @llvm.gcroot(ptr %p, ptr null)
  %sp = getelementptr ptr, ptr @src, i32 7
  %v = load volatile ptr, ptr %sp
  store ptr %v, ptr %p
  call void @probe(i32 6)
  %w = load ptr, ptr %p
  store volatile ptr %w, ptr @sink
  ret void
}
```

`run.mjs`:

```js
import fs from 'node:fs';
const label = process.argv[3];
const { instance } = await WebAssembly.instantiate(fs.readFileSync(process.argv[2]), {});
const e = instance.exports;
e.entry();
const mem = new Uint32Array(e.memory.buffer);
const rd = g => Array.from(mem.slice(g.value / 4, g.value / 4 + 8));
const found = rd(e.found), fsp = rd(e.found_sp), spv = rd(e.sp_val), cn = rd(e.chain_n), ci = rd(e.chain_in), lo = rd(e.range_lo), hi = rd(e.range_hi);
const what = {1:'scalar variable, gcroot', 2:'record with REF field, gcroot+meta', 3:'plain variable (alloca), no gcroot',
              4:'pure SSA value across call', 5:'control: dead before call', 6:'two nested gcroot frames'};
console.log(`--- ${label}`);
for (let k = 1; k <= 6; k++) {
  const want = k === 6 ? (1<<6)|(1<<7) : (1 << k);
  const got = found[k] & want;
  const res = k === 5 ? (found[k] & want ? 'FOUND (unexpected)' : 'not found (correct)')
                      : (got === want ? 'FOUND' : got ? 'partly found' : 'NOT FOUND');
  console.log(`   from __stack_pointer (the nthr_arch_stack32 mechanism): same result as frame-address scan: ${fsp[k]===found[k] ? 'yes' : 'NO'}  sp=${spv[k]}  [${spv[k]<=lo[k] ? 'sp <= frame address' : 'sp > frame address'}]`);
  console.log(`case ${k}  ${what[k].padEnd(36)} ${res.padEnd(22)} scan range ${hi[k]-lo[k]} bytes, chain frames ${cn[k]} (${ci[k]} inside range)`);
}
```

---

## 2. The SSA-across-safepoint audit (`claude/audit.py`)

**Definition.** For every function, find pointer-typed SSA values (including pointer parameters and `ptrtoint` results, which carry
pointer bits) that are **live across a safepoint**: defined before the call and still needed after it. A **safepoint** is any
`call`/`invoke` except `llvm.*` intrinsics, including the `nthr_park` poll call. A value that crosses a safepoint in an SSA value lives
in a wasm local on wasm32 and is invisible to a conservative scan of linear memory. A pair (value, call) is **homed** if the value was
also stored to stack or static memory (an address rooted at an alloca or a global) by a store that dominates the call; it is
**heap-only** if the only stores are to heap or unknown memory; otherwise **not homed**. Stack addresses, static addresses and the
thread-context pointers of the poll are not reported.

**Method.** A small parser splits the `.ll` into functions, blocks and instructions; liveness is computed by backward dataflow over
the ptr-typed names (phi uses ignored in these inputs); dominators decide whether a store precedes a call on every path. Origins are
classified (slot copy, global load, heap or other load, call result, parameter, interior pointer, phi, `ptrtoint`).

**Validation (known-bad controls).** Six functions (`TOTAL: functions 6  safepoint call sites 7  live-across pairs 6  not homed 5`), all flagged correctly:

| Control | Expected | Result |
|---|---|---|
| (a) SSA value loaded from a global, live across a call | flagged, not homed | flagged, not homed |
| (b) same, but also stored to a stack slot before the call | flagged, homed | flagged, homed |
| (c) stored to the slot only after the call | flagged, not homed | flagged, not homed |
| (d) incoming parameter used after the call | flagged (param) | flagged, not homed |
| (e) allocation result held across a second call | flagged (call result) | flagged, not homed |
| (f) value live around a loop containing a call | flagged | flagged, not homed |

**Results.**

| IR | Functions | Safepoint call sites | Live-across pairs | Not homed |
|---|---|---|---|---|
| ms8, post-change build (`scrubStack` returns a sum), `--main-only` | 18 | 463 | **0** | 0 |
| same, all functions (adds the module body `Main_M3`) | 19 | 469 | **0** | 0 |
| ms8, pre-change build, `--main-only` | 18 | 462 | **0** | 0 |
| same IR after `opt -O2` (gcroot calls kept), `--main-only` | 18 | 483 | 2,781 | 2,702 |

The 2,702 not-homed pairs after `opt -O2` by origin: slot copies 2,015; call results 292; phis 195; heap or other loads 103;
`ptrtoint` 91; parameters 4; interior pointers 2. (A further 77 pairs were homed and 2 heap-only.)

**Reading.** `m3llwasm` is a stack machine over memory: every intermediate goes into a `tmp.N` alloca and is reloaded at once, and call
arguments die at the call, so no pointer value crosses a safepoint in an SSA value. An optimiser removes exactly that property.

**Usage.** `python3 -I audit.py file.ll [--detail] [--main-only]`. By default **every** function in the file is analysed;
`--main-only` restricts to `Main__*` and `Loque*` (the ms8 test program). The last line is a total
(`TOTAL: functions N  safepoint call sites N  live-across pairs N  not homed N`); a gate passes only if `not homed` is 0 **and** at least one
function was analysed (an empty result prints a warning and is not a pass). For `neocore` bitcode: disassemble with `llvm-dis` if it is
`.bc`, run the script on the `.ll`, and require zero not-homed pairs. (The first version of the script filtered to `Main__*` by default,
which would have printed an empty, clean-looking result on library bitcode; fixed before first use on `neocore`.)

**Limits.** The audited IR is the ms8 source from before the helper-procedure restructure (the only bitcode we have); the pattern
comes from the code generator, but rerun on any new `.ll`. Library code, exceptions, open arrays and nested procedures are not
covered. Pointer bits are tracked only at the `ptrtoint` result, not through later integer arithmetic. The tool reasons at the IR
level and relies on `llc` not adding live ranges across calls (section 4 supports that).

---

## 3. What an optimiser does to ms8's IR

`opt -O2` on the ms8 IR (build before the helper-procedure restructure), counting `alloca ptr` slots and `gcroot` calls:

| Function | As emitted | `opt -O2`, gcroot kept | `opt -O2`, gcroot calls removed |
|---|---|---|---|
| `recrTest` | 23 ptr allocas, 14 gcroot calls | 14 ptr allocas, 14 gcroot calls | 0 ptr allocas |
| `objrTest` | 24 ptr allocas, 15 gcroot calls | 15 ptr allocas, 15 gcroot calls | 0 ptr allocas |

With gcroot kept, exactly the rooted slots survive (the pointer passed to `llvm.gcroot` escapes, so promotion and dead-store removal
cannot touch them); the other nine allocas of `recrTest` (front-end temporaries without a rooted type) are promoted to SSA values. This is why the derived-copy
rule would become a hard requirement under an optimiser. Note the compiler-used global for the chain (`llvm.compiler.used`) is needed
so that `opt` does not delete the thread-local declaration (the project already does this).

---

## 4. `llc` codegen levels (no `opt`)

`llc -frame-pointer=all -mtriple=x86_64 -relocation-model=pic` on ms8's IR, machine IR after prologue/epilogue insertion:

| Level | `recrTest` frame | spill slots | `objrTest` frame | spill slots |
|---|---|---|---|---|
| -O0 | 1000 bytes | 82 | 984 bytes | 78 |
| -O1, -O2 | 392 bytes | 0 | 392 bytes | 0 |

The named allocas (variables, temporaries, the shadow-stack frame) remain in memory at every level: `llc` has no mem2reg. The
difference is the fast register allocator's permanent spill slots at -O0. The wasm32 harness (section 1) gave identical visibility
results at -O0, -O1, -O2 and -O3. For `llc` levels the permitted range in the plan is therefore -O0 to -O3, with -O0 the validated
level for every runtime result so far.

---

## 5. The cost of gcroot (mutator side)

Worst case: a recursive `fib(35)` (about 29.9 million calls) where every function has one rooted pointer local, compiled with
`llvm_gc_root_chain` as a `thread_local` global exactly as `CompileSafepoint` declares it (general-dynamic TLS under PIC). The "plain"
version is identical without the `gc "shadow-stack"` attribute and the `llvm.gcroot` call.

| Pipeline | Plain | With gcroot | Delta per call |
|---|---|---|---|
| `llc -O0` (the current pipeline) | 0.048–0.050 s | 0.095–0.096 s (one run 0.131) | about 1.6 ns |
| `opt -O2` + `llc -O2` | 0.027–0.031 s | 0.072–0.075 s | about 1.5 ns |

So the push/pop of the chain frame plus the TLS access costs a fixed 1.5 ns per rooted call at either level, whichever way the
collector later reads the roots. Consequences: the optimiser's gain on this call-bound case is about 1.8 times without gcroot and about
1.3 times with it; optimised-plus-gcroot (0.072 s) is slower than unoptimised-plus-no-gcroot (0.048 s). Real functions that allocate,
lock or loop do tens to hundreds of nanoseconds of work, so 1.5 ns is a few percent or less. Caveats: shared 2-core sandbox with noisy
timing; wasm32's TLS access differs (`__tls_base` plus offset) and is unmeasured; the safepoint polls are excluded (they cost per call
under any design).

**Conservative scan cost (estimate, not measured).** In the final ms8 run the stack ranges were 6,792 bytes (main) and about 5.6 KB per
subject thread; with six active threads that is about 4,000 words per collection, at a few nanoseconds per word about 10–30 µs, against
roughly a millisecond for a collection that copies about thirty 40 KB objects. A precise walk would save part of that. Measuring it is
one clock reading around `ProcessStacks` and one around `Collect`.

**Why it matters for the decision.** The cost is paid whether stacks are scanned conservatively or precisely; it is the price of
the optimiser-compatible visibility guarantee, not of precision.

`rooted.ll` (the plain version is the same without the `gc` attribute, the `gcroot` call and the `compiler.used` global):

```llvm
target triple = "x86_64-pc-linux-gnu"
@llvm_gc_root_chain = external thread_local global ptr
@llvm.compiler.used = appending global [1 x ptr] [ptr @llvm_gc_root_chain], section "llvm.metadata"
declare void @llvm.gcroot(ptr, ptr)
define i64 @fib_rooted(i64 %n) gc "shadow-stack" {
entry:
  %p = alloca ptr
  call void @llvm.gcroot(ptr %p, ptr null)
  store ptr null, ptr %p
  %c = icmp slt i64 %n, 2
  br i1 %c, label %base, label %rec
base:
  ret i64 %n
rec:
  %n1 = sub i64 %n, 1
  %a = call i64 @fib_rooted(i64 %n1)
  %n2 = sub i64 %n, 2
  %b = call i64 @fib_rooted(i64 %n2)
  %s = add i64 %a, %b
  ret i64 %s
}
```

---

## 6. Shadow-stack frame layout (LLVM 18.1.3)

Experiment: a function with five gcroots in this alloca order: scalar `s1`, aggregate `agg1` (24 bytes, metadata), scalar `s2`, aggregate
`agg2` (12 bytes, metadata), scalar `s3`; each stored a distinct value so that the offsets show in the generated code.

- The lowering turns the allocas into elements of one struct `{ {next, map}, <root types in lowered order> }` (`%gc_stackentry.f`).
- **Metadata-bearing roots come first**, then null-metadata roots in alloca order (order was `agg1, agg2, s1, s2, s3`).
- Aggregates are packed **contiguously with no alignment padding** (requested alignments are dropped; known bug 2): header 16 bytes,
  `agg1` at +16, `agg2` at +40 (immediately after 24 bytes), and the scalars at the next 8-byte boundary after +52, i.e. +56, +64, +72.
- The frame map is `{i32 NumRoots = 5, i32 NumMeta = 2, ptr meta[2]}`, 24 bytes: **no sizes and no offsets**.
- The lowered code also rewrote the call as an `invoke` with a `gc_cleanup` landing pad that restores the saved chain head and resumes.

Consequences recorded for the parked composite path: a walker that strides by pointer size misreads any frame containing an
aggregate; reconstructing the layout needs each aggregate's size and depends on bug 2 not being fixed upstream (a fix would shift the
offsets). **Address roots** (the aggregate stays an ordinary aligned alloca; a gcroot slot holds its address; the metadata, if any,
describes the pointee) make every root one pointer, retire the marker workaround, and need no layout knowledge. They are the
preferred form if aggregates or fixed arrays ever need rooting (the first step of Phase O).

---

## 7. The `-O0` spill-slot pins (ms8 residue)

**Observation.** In ms8 (first runs) the referent of the *last* loop iteration (n=3) of `recrTest` and `objrTest` never moved. The
per-hit trace showed the pinning word in the owning subject's own thread stack, at every collection from GC 6, never a `REG` range. The
printed slot address moved to lower addresses between collections while its value stayed the same.

**Test of the mechanism.** From `llc -O0 -frame-pointer=all -stop-after=prologepilog` machine IR, the frame of each function lists
its stack objects with offsets. The reference address is the owners array `a[1]` (its low bits from the trace) minus the frame
offset of `a`: 0xe00 for both functions. The six lowest-hit slots (three per thread) correspond to frame offsets of **spill-slot objects**:

| Thread | GC 6–7 | GC 8–9 | GC 10–13 |
|---|---|---|---|
| `recrTest`, slot address (frame offset) | 0xb90 (−624) | 0xb28 (−728) | 0xa88 (−888) |
| `objrTest`, slot address (frame offset) | 0xb98 (−616) | 0xb38 (−712) | 0xaa0 (−864) |

All six are `type: spill-slot` objects in frames of 1000 and 984 bytes (82 and 78 spill slots, in addition to 25 named objects).

**Explanation.** The fast register allocator gives every virtual register its own permanent slot and nothing clears it. The last
iteration's pointers stay in spill slots belonging to the code after the loops; the trace prints only the lowest word that hits a page,
so as later code fills lower slots the printed slot moves down. `scrubStack` cannot help because it zeroes memory below the
caller's frame while these slots are inside it. **Falsified alternative:** dead-store elimination of the scrub loop (the pipeline has
no optimiser; the loop is present in the `-O0` machine code; making `scrubStack` observable changed nothing).

**Remedy for harnesses.** Keep the loops that handle tracked references in helper procedures passed the owner array by `VAR`, with
`scrubStack` after each call: the spill slots then belong to callee frames that die. Result: 12 of 12 sampled referent transitions moved.
At `llc` -O1+ there are no spill slots (section 4), so the class does not arise.

---

## 8. Bounded-heap arithmetic

`nref_memstat` prints, per arena, `name cap claimed:free`: the configured cap in bytes (0 means unbounded), the bytes of regions the arena
has claimed (`nref_dynamic_heap_size`), and the free bytes inside claimed regions (`nref_free_dynamic_memory`; the collector holds its own free pages, so this
is small at exit in all runs).

| Run | Cap | Claimed | In 64 KB pages |
|---|---|---|---|
| unbounded (default) | none | 6,751,552 | 103 pages + 1,344 bytes |
| traced capped at 6 MiB | 6,291,456 (96 pages) | 5,702,880 | 87 pages + 1,248 bytes |

The capped run stopped 588,576 bytes (about 9 pages) short of its cap and claimed exactly 16 pages (1,048,576 bytes) plus 96 bytes (two
48-byte carve-outs) less than the unbounded run, consistent with one growth step it could not take. A 5 MiB cap (80 pages) fails
with out of memory. The 6 MiB-capped run's explicit collections left objects in place with no stack hit at GC 10 (6 unexplained stays)
and GC 12 (11), while GC 9, 11 and 13 moved everything. No corruption was seen in any bounded run. Mechanism unknown: needs
`RTCollector.m3` (register 41). Predicted test: a 7 MiB (112-page) cap should let the arena reach about 103 pages and remove the
unexplained stays.

---

## 9. Notes on optimiser benefit (orientation only; not our measurements)

- One published C++ library (meshoptimizer) built with LLVM 11: simplification 741 ms at -O0 versus 325 ms at -O2 (2.3 times; 56%
  less time); index decompression 18.9 ms versus 4.6 ms (4.1 times; 76% less). Source: the gist
  "How does clang 2.7 hold up in 2021?" (zeux).
- -O2 versus -O3 is small and sometimes negative: in one Stan benchmark set the geometric mean of the O3/O2 runtime ratio was 1.05
  (https://discourse.mc-stan.org/t/o2-vs-o3-compiler-optimization-level/3714).
- There is no universal figure. For our code the useful number comes from a representative program (for example the front end compiling a
  file), measured with and without an optimiser, and weighed against section 5's per-call cost. The expectation (an inference) is a small
  gain on allocation- and barrier-heavy code, whose calls are external and cannot be inlined, and a large one on tight loops like `initR`.

---

## 10. The ms8 stay-accounting script (`hits.py`)

Reads an ms8 log with the per-hit trace, decodes the disguised addresses (`~b` masked to 64 bits), and for each collection from GC 9 to 13
compares the pages of the tracked `mov`/`ctl` objects after the previous collection with that collection's hit list; a stay with no
hit, or a hit without a stay, is a mismatch.

```python
import re,sys
M=(1<<64)-1
L=open(sys.argv[1]).read().splitlines()
gc=0;hits={};cur=None;snap={};g=7
for l in L:
    m=re.match(r'ProcessStacks gc=(\d+) tid=(\d+) me=\d (STACK|REG)',l)
    if m: cur=(int(m.group(1)),int(m.group(2)),m.group(3)); continue
    m=re.match(r'\s+fp=(0x[0-9a-f]+) fp\^=(0x[0-9a-f]+) note=(\d)',l)
    if m and cur: hits.setdefault(cur[0],[]).append((cur[1],cur[2],int(m.group(1),16),int(m.group(2),16),int(m.group(3)))); continue
    m=re.match(r'^\+GC\|n=(\d+)',l)
    if m: g=int(m.group(1)); continue
    m=re.match(r'^(\+\+|\+\+\+\+)(mov|ctl)\|n=(\d+)\|b=(0x[0-9a-f]+)',l)
    if m and g>=8: snap.setdefault(g,{})[(m.group(1)+m.group(2),int(m.group(3)))]=(~int(m.group(4),16))&M
pg=lambda a:a>>16
bad=tot=0
for gg in range(9,14):
    hp={pg(v) for t,k,fp,v,n in hits[gg]}
    for key,a in sorted(snap[gg-1].items()):
        tot+=1
        pred = pg(a) in hp
        obs = pg(snap[gg][key])==pg(a)
        if pred!=obs: bad+=1; print("MISMATCH",gg,key)
print("checked",tot,"mismatches",bad)
```

The thread ids map to subjects by `Fork` order (main 24576, logger 24577, null 24578, recr 24579, objr 24580, mov 24581, page 24582, ctl 24583;
tid 1 is the process's native stack).