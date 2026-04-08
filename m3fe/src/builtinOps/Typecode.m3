(* Copyright (C) 1992, Digital Equipment Corporation           *)
(* All rights reserved.                                        *)
(* See the file COPYRIGHT for a full description.              *)

(* File: Typecode.m3                                           *)
(* Last Modified On Tue May  3 16:33:20 PDT 1994 By kalsow     *)
(*      Modified On Fri Mar 15 03:50:01 1991 By muller         *)

MODULE Typecode;

IMPORT IR, CallExpr, Expr, ExprRep, Type, Procedure, Card, Error;
IMPORT Reff, TypeExpr, ObjectType, M3RT, Target, TInt;

VAR Z: CallExpr.MethodList;

PROCEDURE Check (ce: CallExpr.T;  <*UNUSED*> VAR cs: Expr.CheckState) =
  VAR t: Type.T;
  BEGIN
    IF TypeExpr.Split (ce.args[0], t) THEN
      IF (ObjectType.Is (t)) THEN
        (* ok *)
      ELSIF (Type.IsEqual (t, Reff.T, NIL)) THEN
        Error.Msg ("TYPECODE: T must be a fixed reference type");
      ELSIF (NOT Type.IsSubtype (t, Reff.T)) THEN
        Error.Msg ("TYPECODE: T must be a traced reference type");
      END;
    ELSE
      t := Expr.TypeOf (ce.args[0]);
      IF NOT Type.IsSubtype (t, Reff.T) AND NOT ObjectType.Is (t) THEN
        Error.Msg ("TYPECODE: r must be a traced reference or object");
      END;
    END;
    ce.type := Card.T;
  END Check;

PROCEDURE Prep (ce: CallExpr.T) =
  VAR e := ce.args[0];  t: Type.T;  nil, tagged: IR.Label;
  BEGIN
    IF TypeExpr.Split (e, t) THEN
      (* get the typecode from the typecell *)
    ELSE
      (* get the typecode from the REF's header *)
      Expr.Prep (e);
      Expr.Compile (e);
      ce.tmp := IR.Pop_temp ();
      tagged := IR.Next_label ();
      nil := IR.Next_label ();

      IR.Push (ce.tmp);
      IR.Load_nil ();
      IR.If_compare (IR.Type.Addr, IR.Cmp.EQ, nil, IR.Never);

      IR.Push (ce.tmp);
      IR.Loophole (IR.Type.Addr, Target.Word.cg_type);
      IR.Load_integer (Target.Word.cg_type, TInt.One);
      IR.And (Target.Word.cg_type);
      IR.If_true (tagged, IR.Maybe);

      IR.Push (ce.tmp);
      IR.Ref_to_info (M3RT.RH_typecode_offset, M3RT.RH_typecode_size);
      IR.Loophole (Target.Integer.cg_type, IR.Type.Addr);
      IR.Store_temp (ce.tmp);
      IR.Jump (nil);

      IR.Set_label (tagged);
      IR.Load_intt (M3RT.REFANY_typecode);
      IR.Loophole (Target.Integer.cg_type, IR.Type.Addr);
      IR.Store_temp (ce.tmp);

      IR.Set_label (nil);
    END;
  END Prep;

PROCEDURE Compile (ce: CallExpr.T) =
  VAR e := ce.args[0];  t: Type.T;
  BEGIN
    IF TypeExpr.Split (e, t) THEN
      (* get the typecode from the typecell *)
      Type.Compile (t);
      Type.LoadInfo (t, M3RT.TC_typecode);
    ELSE
      (* get the typecode from the REF's header *)
      IR.Push (ce.tmp);
      IR.Loophole (IR.Type.Addr, Target.Integer.cg_type);
      IR.Free (ce.tmp);
      ce.tmp := NIL;
    END;
  END Compile;

PROCEDURE Initialize () =
  BEGIN
    Z := CallExpr.NewMethodList (1, 1, TRUE, FALSE, TRUE, Card.T,
                                 NIL, NIL,
                                 CallExpr.NotAddressable,
                                 Check,
                                 Prep,
                                 Compile,
                                 CallExpr.NoLValue,
                                 CallExpr.NoLValue,
                                 CallExpr.NotBoolean,
                                 CallExpr.NotBoolean,
                                 CallExpr.NoValue, (* fold *)
                                 CallExpr.NoBounds,
                                 CallExpr.IsNever, (* writable *)
                                 CallExpr.IsNever, (* designator *)
                                 CallExpr.NotWritable (* noteWriter *));
    Procedure.DefinePredefined ("TYPECODE", Z, TRUE);
  END Initialize;

BEGIN
END Typecode.
