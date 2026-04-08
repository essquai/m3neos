(* Copyright (C) 1992, Digital Equipment Corporation           *)
(* All rights reserved.                                        *)
(* See the file COPYRIGHT for a full description.              *)
(*                                                             *)
(* File: Marker.i3                                             *)
(* Last Modified On Wed Oct 25 11:39:40 PDT 1995 by ericv      *)
(*      Modified On Fri May 19 07:41:46 PDT 1995 by kalsow     *)
(*      Modified On Sat Jun 10 18:44:15 PDT 1989 by muller     *)

INTERFACE Marker;

IMPORT IR, Type, Variable, ESet, Expr, M3RT;

CONST
  Return_exception = -1;
  Exit_exception = -2;

PROCEDURE Pop ();
PROCEDURE InvokeSeen () : BOOLEAN;
PROCEDURE Invoked ();
PROCEDURE Excepts() : ESet.EList;

(* pop to top scope. *)

PROCEDURE SaveFrame ();
(* mark and save the top scope so it can be emitted in the
   global table of scopes *)

(* TRY-EXCEPT *)
PROCEDURE PushTry     (l_start, l_stop, l_stopBody: IR.Label;  info: IR.Var;  ex: ESet.T); 
PROCEDURE PushTryElse (l_start, l_stop, l_stopBody: IR.Label;  info: IR.Var);

(* TRY-FINALLY *)
PROCEDURE PushFinally     (l_start, l_stop, l_stopBody: IR.Label;  info: IR.Var);
PROCEDURE PushFinallyProc (l_start, l_stop: IR.Label;  info: IR.Var;
                           handler: IR.Proc;  h_level: INTEGER);
PROCEDURE PopFinally      (VAR(*OUT*) returnSeen, exitSeen: BOOLEAN);

(* LOCK-END *)
PROCEDURE PushLock (l_start, l_stop: IR.Label;  mutex: IR.Var);

(* LOOP-EXIT *)
PROCEDURE PushExit (l_stop: IR.Label);
PROCEDURE ExitOK   (): BOOLEAN;

(* TRY-PASSING (RAISES) *)
PROCEDURE PushRaises (l_start, l_stop: IR.Label;  ex: ESet.T;  info: IR.Var);

(* PROCEDURE-RETURN *)
PROCEDURE PushProcedure (t: Type.T;  v: Variable.T;  cc: IR.CallingConvention);
PROCEDURE ReturnVar     (VAR(*OUT*) t: Type.T;  VAR(*OUT*) v: Variable.T);
PROCEDURE ReturnOK      (): BOOLEAN;

(* code generation *)
PROCEDURE EmitExit ();
PROCEDURE AllocReturnTemp ();
PROCEDURE EmitReturn (expr: Expr.T;  fromFinally: BOOLEAN);
PROCEDURE EmitScopeTable (doEmit : BOOLEAN := FALSE): INTEGER;
PROCEDURE EmitExceptionTest (signature: Type.T;  need_value: BOOLEAN): IR.Val;
PROCEDURE NextHandler (VAR(*OUT*) handler: IR.Label;
                       VAR(*OUT*) handler_body: IR.Label;
                       VAR(*OUT*) info: IR.Var): BOOLEAN;
PROCEDURE PushFrame (frame: IR.Var;  class: M3RT.HandlerClass);
PROCEDURE PopFrame (frame: IR.Var);
(* generate code to link and unlink 'frame' from the global
   stack of exception frames *)

PROCEDURE SetLock (acquire: BOOLEAN;  var: IR.Var;  offset: INTEGER);
(* generate the call to acquire or release a mutex *)

PROCEDURE CaptureState (frame: IR.Var;  jmpbuf: IR.Var;  handler: IR.Label);
(* frame.jmpbuf = jmpbuf
   if (setjmp(jmpbuf)) goto handler
   or
   if (sigsetjmp(jmpbuf, 0)) goto handler
*)

PROCEDURE Reset ();

END Marker.
