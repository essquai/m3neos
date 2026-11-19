(* Copyright (C) 2026 Sunil Khare. All rights reserved.        *)
(*
 * Neos Type Compiler - for garbage collection metadata
 *
 * The TypeComp object compiles type map bytecode for record
 * types. The original CM3 compiler does this in the front
 * end for objects with a TYPECODE; its use in m3neos is for
 * tracing precise roots in records on the shadow stack. The
 * runtime RTTypeMap module walks the bytecode during garbage
 * collection cycles.
 *
 * TipeMap is a super stable aspect of CM3, so TypeComp is a
 * respectful copy of it so that LLVM codegen may avoid
 * regression when RTTypeMap interprets it at runtime.
 *)

(* Copyright (C) 1992, Digital Equipment Corporation           *)
(* All rights reserved.                                        *)
(* See the file COPYRIGHT for a full description.              *)

(* File: TipeMap.i3                                            *)
(* Last Modified On Tue Jul  5 14:21:29 PDT 1994 by kalsow     *)

INTERFACE TypeComp;

TYPE
  Op = {
 (* 0*) Stop, Mark, PushPtr, Return,
 (* 4*) Ref, UntracedRef, Proc,
 (* 7*) Real, Longreal, Extended,
 (*10*) Int_Field, Word_Field,
 (*12*) Int_1,  Int_2,  Int_4,  Int_8, 
 (*16*) Word_1, Word_2, Word_4, Word_8,
 (*20*) Set_1,  Set_2,  Set_3,  Set_4,
 (*24*) OpenArray_1, OpenArray_2,
 (*26*) Array_1, Array_2, Array_3, Array_4, Array_5, Array_6, Array_7, Array_8,
 (*34*) Skip_1,  Skip_2,  Skip_3,  Skip_4,  Skip_5,  Skip_6,  Skip_7,  Skip_8,
 (*42*) SkipF_1, SkipF_2, SkipF_3, SkipF_4, SkipF_5, SkipF_6, SkipF_7, SkipF_8,
 (*50*) SkipB_1, SkipB_2, SkipB_3, SkipB_4, SkipB_5, SkipB_6, SkipB_7, SkipB_8
   };

  ByteList = REF ARRAY OF [0..255];

TYPE T <: Public;

TYPE
  Public = OBJECT
  METHODS
    start ();
    (* ^begin construction of a new map *)
    finish () : ByteList;
    (* ^finish map and return the compiled bytecode *)
    add (offset: INTEGER;  o: Op;  arg: INTEGER);
    (* ^add '(o, arg)' as the description for the bits at
       'offset' in the map *)
    getCursor (): INTEGER;
    (* ^get the current offset in the current map *)
    setCursor (x: INTEGER);
    (* ^get the current offset in the current map without
       generating Skips *)
  END;

END TypeComp.
