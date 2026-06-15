(* Copyright (C) 2026 Sunil Khare. All rights reserved. *)

(*
 * RTAddress.i3
 *
 * M3 neos manually managed dynamic memory
 * 
 * The neos runtime uses a pre-declared fixe segment for untraced
 * dynamically managed memory. Functional replacement for traditional
 * C malloc/free API. This implementation is thread-safe.
 *
 *)

INTERFACE RTAddress;

<*EXTERNAL "emmalloc_init"*>
PROCEDURE declare(heap: ADDRESS; numBytes: LONGINT);
(* Define the fixed heap this module will manage *)


<*EXTERNAL "emmalloc_malloc"*>
PROCEDURE malloc(size : LONGINT) : ADDRESS;
(* Return a reference to a freshly allocated, uninitialized, untraced
   memory segment of given size.  NIL if not enough available. *)


<*EXTERNAL "emmalloc_calloc"*>
PROCEDURE calloc(num: LONGINT; size: LONGINT) : ADDRESS;
(* Return a reference to a freshly allocated, zeroed, traced
   array of num elements of size bytes each. *)

<*EXTERNAL "emmalloc_free"*>
PROCEDURE free(ptr: ADDRESS);
(* Return memory at ptr to the RTAddress pool. The memory at ptr
   must have been allocated by malloc/calloc and must not ahve
   been freed before, otherwise undefined behaviour ensues *)


END RTAddress.
