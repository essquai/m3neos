(* Copyright (C) 1992, Digital Equipment Corporation           *)
(* All rights reserved.                                        *)
(* See the file COPYRIGHT for a full description.              *)

(* File: InExpr.m3                                             *)
(* Last modified on Fri Jul  8 09:48:45 PDT 1994 by kalsow     *)
(*      modified on Thu Nov 29 03:31:28 1990 by muller         *)

MODULE InExpr;

IMPORT IR, Expr, ExprRep, Error, Type, SetType, Bool, SetExpr;
IMPORT Target, TInt, Value;

TYPE
  P = ExprRep.Tab BRANDED "InExpr.P" OBJECT
        tmp: IR.Val;
      OVERRIDES
        typeOf       := ExprRep.NoType;
        repTypeOf    := ExprRep.NoType;
        check        := Check;
        need_addr    := ExprRep.NotAddressable;
        prep         := Prep;
        compile      := Compile;
        prepLV       := ExprRep.NotLValue;
        compileLV    := ExprRep.NotLValueBool;
        prepBR       := ExprRep.PrepNoBranch;
        compileBR    := ExprRep.NoBranch;
        evaluate     := Fold;
        isEqual      := ExprRep.EqCheckAB;
        getBounds    := ExprRep.NoBounds;
        isWritable   := ExprRep.IsNever;
        isDesignator := ExprRep.IsNever;
        isZeroes     := ExprRep.IsNever;
        genFPLiteral := ExprRep.NoFPLiteral;
        prepLiteral  := ExprRep.NoPrepLiteral;
        genLiteral   := ExprRep.NoLiteral;
        note_write   := ExprRep.NotWritable;
        exprAlign    := ExprRep.ExprBoolAlign; 
      END;

PROCEDURE New (a, b: Expr.T): Expr.T =
  VAR p: P;
  BEGIN
    p := NEW (P);
    ExprRep.Init (p);
    p.a       := a;
    p.b       := b;
    p.type    := Bool.T;
    p.repType := Bool.T;
    p.tmp     := NIL;
    RETURN p;
  END New;

PROCEDURE Check (p: P;  VAR cs: Expr.CheckState) =
  VAR ta, tb, tc: Type.T;
  BEGIN
    Expr.TypeCheck (p.a, cs);
    Expr.TypeCheck (p.b, cs);
    ta := Type.Base (Expr.TypeOf (p.a));
    tb := Type.Base (Expr.TypeOf (p.b));
    IF SetType.Split (tb, tc) AND Type.IsSubtype (ta, Type.Base (tc)) THEN
      (*ok *)
    ELSE
      p.type := Expr.BadOperands ("IN", ta, tb);
    END;
  END Check;

PROCEDURE Prep (p: P) =
  VAR
    set, range: Type.T;
    b: BOOLEAN;
    min, max, emin, emax, n_elts: Target.Int;
    skip: IR.Label;
    index: IR.Val;
    info: Type.Info;
    cg_type: IR.Type;
  BEGIN
    set := Type.Base (Type.CheckInfo (Expr.TypeOf (p.b), info));
    b := SetType.Split (set, range);  <*ASSERT b*>
    b := Type.GetBounds (range, min, max);  <*ASSERT b*>
    Expr.GetBounds (p.a, emin, emax);
    cg_type := Type.IRType (range);

    Expr.Prep (p.a);
    Expr.Prep (p.b);

    IF TInt.LT (emin, min) OR TInt.LT (max, emax) THEN
      (* we need to range check a *)
      IF NOT TInt.Subtract (max, min, n_elts)
        OR TInt.LT (Target.Integer.max, n_elts) THEN
        Error.Msg ("set too large");
      END;
      Expr.Compile (p.a);
      IF NOT TInt.EQ (min, TInt.Zero) THEN
        IR.Load_integer (cg_type, min);
        IR.Subtract (cg_type);
      END;
      index := IR.Pop ();
      Value.Load (Bool.False);
      p.tmp := IR.Pop_temp ();
      IR.Push (index);
      IR.Loophole (cg_type, Target.Word.cg_type);
      IR.Load_integer (Target.Word.cg_type, n_elts);
      skip := IR.Next_label ();
      IR.If_compare (Target.Word.cg_type, IR.Cmp.GT, skip, IR.Never);
      Expr.Compile (p.b);
      IR.Push (index);
      IR.Set_member (info.size);
      IR.Store_temp (p.tmp);
      IR.Set_label (skip);
      IR.Free (index);
    END;
  END Prep;

PROCEDURE Compile (p: P; StaticOnly: BOOLEAN) =
  VAR
    set, range: Type.T;
    b: BOOLEAN;
    min, max, emin, emax: Target.Int;
    info: Type.Info;
    cg_type: IR.Type;
  BEGIN
    <* ASSERT NOT StaticOnly *>
    set := Type.Base (Type.CheckInfo (Expr.TypeOf (p.b), info));
    b := SetType.Split (set, range);  <*ASSERT b*>
    b := Type.GetBounds (range, min, max);  <*ASSERT b*>
    Expr.GetBounds (p.a, emin, emax);

    IF TInt.LT (emin, min) OR TInt.LT (max, emax) THEN
      (* we need to range check a *)
      IR.Push (p.tmp);
      IR.Free (p.tmp);
      p.tmp := NIL;
    ELSE
      (* no range checking is needed *)
      Expr.Compile (p.b);
      Expr.Compile (p.a);
      cg_type := Type.IRType (range);
      IF NOT TInt.EQ (min, TInt.Zero) THEN
        IR.Load_integer (cg_type, min);
        IR.Subtract (cg_type);
      END;
      IR.Loophole (cg_type, Target.Integer.cg_type);
      IR.Set_member (info.size);
    END;
  END Compile;

PROCEDURE Fold (p: P): Expr.T =
  VAR e1, e2, e3: Expr.T;
  BEGIN
    e1 := Expr.ConstValue (p.b);
    e2 := Expr.ConstValue (p.a);
    e3 := NIL;
    IF (e1 = NIL) OR (e2 = NIL) THEN
    ELSIF SetExpr.Member (e1, e2, e3) THEN
    END;
    RETURN e3;
  END Fold;

BEGIN
END InExpr.
