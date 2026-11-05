/* WasiCstd.c -- placeholders for what wasi-libc lacks, wasm32 only.

   setjmp/longjmp/system

   The Modula-3 back end emits calls to _setjmp for every TRY ... EXCEPT (and
   for a FINALLY body containing EXIT/RETURN), and CsetjmpC.c calls _longjmp
   to unwind to a handler.  wasi-libc has no implementation of either unless
   the program is compiled and run with the WebAssembly exception-handling
   proposal and "-mllvm -wasm-enable-sjlj".

   Until that is settled:
     _setjmp   saves nothing and returns 0, so a TRY body runs normally;
     _longjmp  is reached only if an exception is actually raised to a
               handler, and then stops the program with a message, instead of
               silently going wrong.
    system     aborts if invoked */

#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

__attribute__((weak))
int _setjmp (jmp_buf env)
{
  (void) env;
  return 0;
}

__attribute__((weak))
_Noreturn void _longjmp (jmp_buf env, int val)
{
  static const char msg[] =
    "m3: an exception was raised to a handler, but setjmp/longjmp are not yet "
    "implemented on wasm32\n";
  (void) env; (void) val;
  (void) write (2, msg, sizeof msg - 1);
  abort ();
}

__attribute__((weak))
_Noreturn int system(const char *command) {
  static const char msg[] =
    "m3: the system C function was invoked, but it is not yet "
    "implemented on wasm32\n";
  (void) write (2, msg, sizeof msg - 1);
  abort ();
}