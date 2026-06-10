(* Copyright (C) 1992, Digital Equipment Corporation           *)
(* All rights reserved.                                        *)
(* See the file COPYRIGHT for a full description.              *)

(* File: Inc.m3                                                *)
(* Last Modified On Tue May 23 15:31:58 PDT 1995 By kalsow     *)
(*      Modified On Tue Apr  2 03:47:06 1991 By muller         *)

MODULE Inc;

IMPORT IR, CallExpr, Expr, Type, Procedure, Dec, Target, TInt;
IMPORT IntegerExpr, Host, Int, LInt;

VAR Z: CallExpr.MethodList;

PROCEDURE Check (ce: CallExpr.T;  VAR cs: Expr.CheckState) =
  BEGIN
    Dec.DoCheck ("INC", ce, cs);
  END Check;

PROCEDURE Prep (ce: CallExpr.T) =
  BEGIN
    Expr.PrepLValue (ce.args[0], traced := FALSE);
    IF (NUMBER (ce.args^) > 1) THEN Expr.Prep (ce.args[1]); END;
  END Prep;

PROCEDURE Compile (ce: CallExpr.T) =
  VAR
    lhs    := ce.args[0];
    tlhs   := Expr.TypeOf (lhs);
    info   : Type.Info;
    inc    : Expr.T;
    check  : [0..3] := 0;
    lvalue : IR.Val;
    bmin, bmax: Target.Int;
    cg_type: IR.Type;
  BEGIN
    tlhs := Type.CheckInfo (tlhs, info);
    IF Type.IsSubtype (tlhs, LInt.T)
      THEN tlhs := LInt.T; cg_type := Target.Longint.cg_type;
      ELSE tlhs := Int.T;  cg_type := Target.Integer.cg_type;
    END;
    IF (NUMBER (ce.args^) > 1)
      THEN inc := ce.args[1];
    ELSIF tlhs = LInt.T
      THEN inc := IntegerExpr.New (LInt.T, TInt.One);  Expr.Prep (inc);
      ELSE inc := IntegerExpr.New (Int.T,  TInt.One);  Expr.Prep (inc);
    END;
    Expr.GetBounds (lhs, bmin, bmax);

    IF Host.doRangeChk THEN
      IF tlhs = LInt.T THEN
        IF TInt.LT (Target.Longint.min, bmin) THEN INC (check) END;
        IF TInt.LT (bmax, Target.Longint.max) THEN INC (check, 2) END;
      ELSE
        IF TInt.LT (Target.Integer.min, bmin) THEN INC (check) END;
        IF TInt.LT (bmax, Target.Integer.max) THEN INC (check, 2) END;
      END;
    END;

    Expr.CompileLValue (lhs, traced := FALSE);
    lvalue := IR.Pop ();
    IR.Push (lvalue);

    IR.Push (lvalue);
    IR.Load_indirect (info.stk_type, 0, info.size, info.alignment);
    Expr.Compile (inc);

    IF (info.stk_type = IR.Type.Addr)
      THEN IR.Index_bytes (Target.Byte);  check := 0;
      ELSE IR.Add (cg_type);
    END;

    CASE check OF
    | 0 => (* no range checking *)
    | 1 => IR.Check_lo (cg_type, bmin, IR.RuntimeError.ValueOutOfRange);
    | 2 => IR.Check_hi (cg_type, bmax, IR.RuntimeError.ValueOutOfRange);
    | 3 => IR.Check_range (cg_type, bmin, bmax,
                           IR.RuntimeError.ValueOutOfRange);
    END;

    IR.Store_indirect (info.stk_type, 0, info.size);
    IR.Free (lvalue);
    Expr.NoteWrite (lhs);
  END Compile;

PROCEDURE Initialize () =
  BEGIN
    Z := CallExpr.NewMethodList (1, 2, FALSE, FALSE, TRUE, NIL,
                                 NIL, NIL,
                                 CallExpr.NotAddressable,
                                 Check,
                                 Prep,
                                 Compile,
                                 CallExpr.NoLValue,
                                 CallExpr.NoLValue,
                                 CallExpr.NotBoolean,
                                 CallExpr.NotBoolean,
                                 CallExpr.NoValue,
                                 CallExpr.NoBounds,
                                 CallExpr.IsNever, (* writable *)
                                 CallExpr.IsNever, (* designator *)
                                 CallExpr.NotWritable (* noteWriter *));
    Procedure.DefinePredefined ("INC", Z, TRUE);
  END Initialize;

BEGIN
END Inc.
