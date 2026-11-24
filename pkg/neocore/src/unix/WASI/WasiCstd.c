/* WasiCstd.c -- placeholders for what wasi-libc lacks, wasm32 only.

   system

   (setjmp/longjmp used to be stubbed here.  They are now real: the build
   passes -mllvm -wasm-enable-sjlj and the link uses -lsetjmp, and
   CsetjmpC.c calls longjmp by that exact name.  A stub named _longjmp here
   would be linked in place of the real thing, so there must not be one.)

   system     aborts if invoked */

#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

__attribute__((weak))
_Noreturn int system(const char *command) {
  static const char msg[] =
    "m3: the system C function was invoked, but it is not yet "
    "implemented on wasm32\n";
  (void) write (2, msg, sizeof msg - 1);
  abort ();
}