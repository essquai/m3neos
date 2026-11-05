/* WasiSys.c -- stage-2 placeholders for what wasi-libc lacks, wasm32 only.

   The Modula-3 runtime includes some system calls that wasi-libc does not
   implement. The plan is to incorporate them in WAMR.

   Until that is settled:
     pthread_atfork   wasm has no fork(), so handlers registered here can
                      never run.  Declared by wasi-libc's pthread.h but not
                      defined.  Reporting success is the honest answer for
                      RTProcess.RegisterForkHandlers.
     gethostname      aborts, until we decide what to do with it. */

                      
#include <pthread.h>
#include <unistd.h>
#include <stdlib.h>

__attribute__((weak))
int pthread_atfork (void (*prepare) (void), void (*parent) (void),
                    void (*child) (void))
{
  (void) prepare; (void) parent; (void) child;
  return 0;
}

__attribute__((weak))
_Noreturn int gethostname(char *name, size_t len) {
  static const char msg[] =
    "m3: the gethostname function was invoked, but it is not yet "
    "implemented on wasm32\n";
  (void) write (2, msg, sizeof msg - 1);
  abort ();
}

