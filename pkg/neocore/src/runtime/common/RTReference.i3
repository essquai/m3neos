(* Copyright (C) 2026 Sunil Khare. All rights reserved. *)

(*
 * RTReference.i3
 *
 * M3 neos traced & untraced REF memory runtime module.
 * 
 * Per section 2.2.7 of the language definition, Modula-3 REF types
 * may either be traced or untraced. This module provides for the
 * allocation of both types of references with a distinct pool for
 * each type.
 *
 * As a key element of the runtime it also allows for allocation
 * from the pool of virtual memory - conventional malloc limited only
 * by system call limits. The traced and untraced heaps can be
 * pre-defined to fixed and pre-allocated sizes using @M3 runtime parms.
 *
 * RTReference provides a better structure for memory management for
 * the wasm32 target; the cm3 compiler used C stdlib allocator for
 * M3toC, for untraced, and for traced allocations. This runtime module
 * makes allocation more clear, and provides explicit control of wasm32
 * linear memory to enable runtime garbage collection.
 *)

INTERFACE RTReference;

FROM Cstddef IMPORT size_t;

TYPE RefType = { Virtual, Untraced, Traced };
(* Not intended for application code. The neos M3 compiler will generate
   runtime allocation code from the correct pool. The Traced REF type
   is garbage collected, and Untraced is for NEW/DISPOSE explicitly
   application invoked. Virtual is used internally by the runtime
   startup and to pre-allocate heaps for Untraced and Traced types. *)

VAR Params : ARRAY RefType OF size_t;
(* Sizes defined for each RefType pool *)

<* EXTERNAL "nref_sizes"*>
PROCEDURE sizes(params: ADDRESS);
(* Intended for RTLinker to pull the Params set by prologue *)

<*EXTERNAL "nref_malloc"*>
PROCEDURE malloc(size : size_t; type: RefType := RefType.Virtual) : ADDRESS;
(* Allocate memory from the given REF type. The resulting address
   must only be returned to the pool of the same RefType or undefined
   runtime behaviour will occur. Returns NIL upon pool exhaustion. *)


<*EXTERNAL "nref_calloc"*>
PROCEDURE calloc(num: size_t; size: size_t; type: RefType := RefType.Virtual) : ADDRESS;
(* Identicial to malloc with the memory initialised to zero. *)


<*EXTERNAL "nref_free"*>
PROCEDURE free(ptr: ADDRESS; type: RefType := RefType.Virtual);
(* Return memory at ptr to the RTReference pool. The ptr address
   must have been allocated from the same REF type pool or
   undefined runtime behaviour will occur. *)

END RTReference.
