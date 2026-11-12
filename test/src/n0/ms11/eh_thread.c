/* eh_thread.c - wasm exceptions in a spawned thread (WAMR classic interpreter)
 *
 * One worker thread repeatedly "throws" across a function boundary and 
 * catches the exception in its caller. main only waits in pthread_join.
 * Nothing is shared between the threads.
 *
 * The throw is C setjmp/longjmp, which LLVM's wasm sjlj lowering turns into
 * wasm exception handling (throw / try / catch, legacy encoding). Build
 * commands are in README.md.
 *
 * usage: eh_thread [workers [iterations]]     defaults: 1 worker, 200
 * Prints "RESULT: PASS" only if every worker caught every exception.
 */
#include <pthread.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>

static int iterations = 200;

/* longjmp leaves this function, so the wasm throw crosses a function boundary */
__attribute__((noinline)) static void thrower(jmp_buf *jb) { longjmp(*jb, 1); }

static void *worker(void *arg) {
  volatile int caught = 0;
  for (int i = 0; i < iterations; i++) {
    jmp_buf jb;
    if (setjmp(jb) == 0) thrower(&jb);
    else caught++;
  }
  return (void *)(long)caught;
}

int main(int argc, char **argv) {
  int n = argc > 1 ? atoi(argv[1]) : 1;
  if (argc > 2) iterations = atoi(argv[2]);
  if (n < 1 || n > 64) n = 1;
  pthread_t t[64];
  for (int i = 0; i < n; i++)
    if (pthread_create(&t[i], NULL, worker, NULL) != 0) { puts("pthread_create failed"); return 3; }
  int bad = 0;
  for (int i = 0; i < n; i++) {
    void *r;
    pthread_join(t[i], &r);
    if ((long)r != iterations) bad++;
  }
  if (bad) { printf("RESULT: FAIL (%d of %d workers wrong)\n", bad, n); return 1; }
  printf("RESULT: PASS (%d workers x %d exceptions)\n", n, iterations);
  return 0;
}
