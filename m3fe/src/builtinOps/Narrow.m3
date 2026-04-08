(* Copyright (C) 1992, Digital Equipment Corporation           *)
(* All rights reserved.                                        *)
(* See the file COPYRIGHT for a full description.              *)

(* File: Narrow.m3                                             *)
(* Last Modified On Wed Jun 29 17:29:43 PDT 1994 By kalsow     *)
(*      Modified On Sat Dec  8 00:54:20 1990 By muller         *)

MODULE Narrow;

IMPORT IR, CallExpr, Expr, ExprRep, Type, Error, TypeExpr;
IMPORT Procedure, ObjectType, Reff, Null, M3RT, RefType;
IMPORT Target, RunTyme, TInt;

VAR Z: CallExpr.MethodList;

PROCEDURE TypeOf (ce: CallExpr.T): Type.T =
  VAR t: Type.T;
  BEGIN
    IF TypeExpr.Split (ce.args[1], t)
      THEN RETURN t;
      ELSE RETURN Expr.TypeOf (ce.args[0]);
    END;
  END TypeOf;

PROCEDURE RepTypeOf (ce: CallExpr.T): Type.T =
  VAR t: Type.T;
  BEGIN
    IF TypeExpr.Split (ce.args[1], t)
      THEN RETURN t;
      ELSE RETURN Expr.RepTypeOf (ce.args[0]);
    END;
  END RepTypeOf;

PROCEDURE Check (ce: CallExpr.T;  <*UNUSED*> VAR cs: Expr.CheckState) =
  VAR dest: Type.T;  src := Expr.TypeOf (ce.args[0]);
  BEGIN
    IF NOT TypeExpr.Split (ce.args[1], dest) THEN
      Error.Msg ("NARROW: second argument must be a type");
      dest := src;
    END;

    IF NOT Type.IsAssignable (dest, src) THEN
      Error.Msg ("NARROW: types must be assignable");
    ELSIF ObjectType.Is (dest) OR Type.IsSubtype (dest, Reff.T) THEN
      (* ok *)
    ELSE (* untraced ref type *)
      Error.Msg ("NARROW: must be a traced reference or object type");
    END;

    ce.type := dest;
  END Check;

PROCEDURE Prep (ce: CallExpr.T) =
  VAR t: Type.T;
  BEGIN
    EVAL TypeExpr.Split (ce.args[1], t);
    Type.Compile (t);
    Expr.Prep (ce.args[0]);
    Expr.Compile (ce.args[0]);
    ce.tmp := EmitCore (t, Expr.TypeOf (ce.args[0]));
    IF (ce.tmp = NIL) THEN
      (* capture the ref value *)
      ce.tmp := IR.Pop_temp ();
    END;
  END Prep;

PROCEDURE Compile (ce: CallExpr.T) =
  BEGIN
    (* all the work was done by Prep *)
    IR.Push (ce.tmp);
    IR.Free (ce.tmp);
    ce.tmp := NIL;
  END Compile;

PROCEDURE Emit (tlhs, trhs: Type.T) =
  VAR tmp := EmitCore (tlhs, trhs);
  BEGIN
    IF (tmp # NIL) THEN
      (* reload the ref value on the stack *)
      IR.Push (tmp);
      IR.Free (tmp);
    END;
  END Emit;

PROCEDURE EmitCore (tlhs, trhs: Type.T): IR.Val =
  VAR
    ok, tagged: IR.Label;
    ref: IR.Val;
    is_object := ObjectType.Is (tlhs);
    target: Type.T;
    align: INTEGER;
    lhs_info, info: Type.Info;
    proc: Procedure.T;
  BEGIN
    tlhs := Type.CheckInfo (tlhs, lhs_info);
    IF is_object THEN
      align := ObjectType.FieldAlignment (tlhs);
      IR.Boost_addr_alignment (align);
    ELSIF RefType.Split (tlhs, target) THEN
      target := Type.CheckInfo (target, info);
      align := info.alignment;
      IR.Boost_addr_alignment (align);
    END;

    (* CT test for the no-check cases... *)
    IF Type.IsSubtype (trhs, tlhs) THEN RETURN NIL; END;
    IF (NOT is_object) AND (NOT lhs_info.isTraced) THEN RETURN NIL; END;

    (* capture the right-hand side *)
    ref := IR.Pop ();
    ok := IR.Next_label ();

    (* RT check for ref = NIL *)
    IR.Push (ref);
    IR.Load_nil ();
    IR.If_compare (IR.Type.Addr, IR.Cmp.EQ, ok, IR.Maybe);

    IF NOT Type.IsEqual (tlhs, Null.T, NIL) THEN
      tagged := IR.Next_label ();

      (* RT check for ref is tagged. *) 
      IR.Push (ref);
      IR.Loophole (IR.Type.Addr, Target.Word.cg_type);
      IR.Load_integer (Target.Word.cg_type, TInt.One);
      IR.And (Target.Word.cg_type);
      IR.If_true (tagged, IR.Maybe);

      (* RT check for TYPECODE(ref) = TYPECODE(type) *)
      IR.Push (ref);
      IR.Ref_to_info (M3RT.RH_typecode_offset, M3RT.RH_typecode_size);
      Type.LoadInfo (tlhs, M3RT.TC_typecode);
      IR.If_compare (Target.Integer.cg_type, IR.Cmp.EQ, ok, IR.Always);

      IF NOT RefType.Is (tlhs) THEN
        (*Note: When T is unrevealed <: REFANY, both ObjectType(T) and 
                RefType.Is(T) return FALSE.  We need to call the runtime in
                in this case. *) 
        (* finally, call the runtime to figure it out... *)
        proc := RunTyme.LookUpProc (RunTyme.Hook.CheckIsType);
        Procedure.StartCall (proc);
        IF Target.DefaultCall.args_left_to_right THEN
          IR.Push (ref);
          IR.Pop_param (IR.Type.Addr);
          Type.LoadInfo (tlhs, -1);
          IR.Pop_param (IR.Type.Addr);
        ELSE
          Type.LoadInfo (tlhs, -1);
          IR.Pop_param (IR.Type.Addr);
          IR.Push (ref);
          IR.Pop_param (IR.Type.Addr);
        END;
        Procedure.EmitCall (proc);
        IR.If_true (ok, IR.Always);
      END;
      IR.Abort (IR.RuntimeError.NarrowFailed);

      IR.Set_label (tagged);
      IR.Load_intt (M3RT.REFANY_typecode);
      Type.LoadInfo (tlhs, M3RT.TC_typecode);
      IR.If_compare (Target.Integer.cg_type, IR.Cmp.EQ, ok, IR.Always);
    END;

    IR.Abort (IR.RuntimeError.NarrowFailed);
    IR.Set_label (ok);

    RETURN ref;
  END EmitCore;

PROCEDURE Fold (ce: CallExpr.T): Expr.T =
  BEGIN
    RETURN Expr.ConstValue (ce.args[0]);
  END Fold;

PROCEDURE NoteWrites (ce: CallExpr.T) =
  BEGIN
    Expr.NoteWrite (ce.args[0]);
  END NoteWrites;

PROCEDURE Initialize () =
  BEGIN
    Z := CallExpr.NewMethodList (2, 2, TRUE, FALSE, TRUE, NIL,
                                 TypeOf,
                                 RepTypeOf,
                                 CallExpr.NotAddressable,
                                 Check,
                                 Prep,
                                 Compile,
                                 CallExpr.NoLValue,
                                 CallExpr.NoLValue,
                                 CallExpr.NotBoolean,
                                 CallExpr.NotBoolean,
                                 Fold,
                                 CallExpr.NoBounds,
                                 CallExpr.IsNever, (* writable *)
                                 CallExpr.IsNever, (* designator *)
                                 NoteWrites);
    Procedure.DefinePredefined ("NARROW", Z, TRUE);
  END Initialize;

BEGIN
END Narrow.

