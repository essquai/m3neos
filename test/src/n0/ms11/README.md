# WAMR 2.4.5: wasm exceptions raised in a spawned thread break the interpreter (cluster-wide broadcast of the in-flight marker)

Draft issue text for the WAMR repository. One `[fill in]` line remains: paste a typical failing output from the stock build.

## Summary

With the classic interpreter, `WAMR_BUILD_EXCE_HANDLING=1` and wasi-threads, a wasm exception that leaves a
function and is caught by its caller (ordinary try/catch control flow) makes the interpreter signal every
other thread in the cluster. With a single extra thread that is enough to make runs fail or crash
non-deterministically. Single-threaded programs are not affected.

## Environment

- WAMR tag 2.4.5, `product-mini/platforms/linux`, x86_64 Linux
- classic interpreter (`WAMR_BUILD_FAST_INTERP=0`), `WAMR_BUILD_EXCE_HANDLING=1`,
  `WAMR_BUILD_LIB_WASI_THREADS=1`, `WAMR_BUILD_SHARED_MEMORY=1`, thread manager enabled
- toolchain: clang 22.1.2, wasi-sdk 33 sysroot, target `wasm32-wasip1-threads`
- legacy exception encoding (`try`/`catch`), the only one the classic interpreter accepts

## Reproducer

`eh_thread.c` (this directory). One worker thread repeatedly takes a C `longjmp` out of a function and
catches it in the caller; `main` only calls `pthread_join`. LLVM's wasm sjlj lowering turns the
`setjmp`/`longjmp` pair into wasm `throw` and `try`/`catch`.

Build:

```sh
SYSROOT=/opt/wasi-sysroot-33.0
clang-22 --target=wasm32-wasip1-threads --sysroot=$SYSROOT -O0 -pthread \
  -mllvm -wasm-enable-sjlj -mllvm -wasm-use-legacy-eh=true \
  -Wl,--import-memory,--export-memory,--initial-memory=8388608,--max-memory=67108864 \
  -o eh_thread.wasm eh_thread.c -lsetjmp
```

Run each argument set 20 times and count passes (a Perl alarm is used because some `timeout` implementations crash when killing; a passing run takes a fraction of a second):

```sh
# arguments: workers iterations mode   (mode: spin = main keeps running wasm, join = main blocks in pthread_join)
for args in "2 200 spin" "4 1000 spin" "4 1000 join"; do
  p=0
  for i in $(seq 20); do
    out=$(perl -e 'alarm 3; exec @ARGV' iwasm --max-threads=16 eh_thread.wasm $args 2>&1)
    if echo "$out" | grep -q 'RESULT: PASS'; then p=$((p+1)); printf .; else printf x; fi
  done
  echo " $args: pass=$p of 20"
done
```

## Expected

Every run passes: every exception is caught by the caller that set up the handler.

## Actual (stock 2.4.5)

- This reproducer, stock 2.4.5, 20 runs each: `2 200 spin` 0 of 20 pass; `4 1000 spin` 0 of 20; `4 1000 join` 0 of 20.
  With one worker (`1 200`, an earlier version of the program) about 83% of runs passed (165 of 200).
- Typical failing output: `[fill in]`
- Result for a larger version of the same test (a 5-scenario test with deeper recursion): one worker,
  200 rounds of the plain raise-and-catch scenario passed 4 of 40 runs; two workers passed 0 of 40.
- Failures are different on different runs: `Exception: uncaught wasm exception`, exit 0 with a call-stack
  dump of the *main* thread (blocked in `pthread_join`) and no output, `iwasm` exiting with SIGSEGV (139),
  and hangs.
- Controls: the same threads with no exceptions pass 80 of 80; the same exceptions on a single thread
  with no worker are fine.

## Analysis

In `wasm_interp_classic.c`, when a `throw` finds no handler in the current function (`LABEL_TYPE_FUNCTION`
case), it pushes the tag onto the caller's frame and calls

```c
wasm_set_exception(module, "uncaught wasm exception");   /* mark frame as raised exception */
goto return_func;
```

The caller notices the string after the return (`return_func`, and the native-call return path),
clears it with `wasm_set_exception(module, NULL)`, pops the tag and continues the handler search. So the
string is only meant to pass a message between two frames of the same thread.

With the thread manager built in, `wasm_set_exception` (in `wasm_runtime_common.c`) calls
`wasm_cluster_set_exception`, whose `set_exception_visitor` writes `"Exception: ..."` into **every**
thread's module instance and sets the cancel/terminate flag on it. The marker therefore reaches all other
threads, which can be terminated or can run into it. In particular `return_func` treats any pending exception
as an in-flight wasm exception, with no check of the message, and then does `POP_I32()` and indexes
`module->e->tags[]` with whatever it popped.

## Fix that resolves it

1. Export `wasm_set_exception_local` (it was `static` in `wasm_runtime_common.c`) and declare it in
   `wasm_runtime.h`.
2. In `wasm_interp_classic.c`, use it for the EH marker only: the `"uncaught wasm exception"` set in the
   `LABEL_TYPE_FUNCTION` case, and the three clears (`wasm_set_exception(module, NULL)`) in the native-call
   return path (two) and in `return_func`.
3. In `return_func`, only treat the pending exception as in flight when its text contains
   `"uncaught wasm exception"`; otherwise `goto got_exception`:

```c
if (wasm_get_exception(module)) {
    char exc[128] = { 0 };
    wasm_copy_exception(module, exc);
    if (strstr(exc, "uncaught wasm exception")) {
        wasm_set_exception_local(module, NULL);
        exception_tag_index = POP_I32();
        goto find_a_catch_handler;
    }
    goto got_exception;   /* a real trap, e.g. from another thread */
}
```

With this change the reproducer passes 40 of 40 runs in each of those three configurations (and 200 of 200 for
one worker). In the larger test, 1, 2 and 4 workers pass 40 of 40 runs on both a clang-driven build and an
LLVM-bitcode-to-`llc` build, with all five scenarios at 4 workers; 8 and 16 workers pass all scenarios
(3 of 3 runs each) and the exception-only scenario scales to the machine's limit.

## Open point for maintainers

The marker now stays local, so a genuinely uncaught exception that reaches a thread's entry function is no
longer broadcast the way a trap is. The patch has not addressed what should happen there (terminate the
cluster like a trap?), and it has not been tested. The AOT and fast-interpreter paths were not looked at.
