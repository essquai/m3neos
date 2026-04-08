(* Copyright (C) 1992, Digital Equipment Corporation           *)
(* All rights reserved.                                        *)
(* See the file COPYRIGHT for a full description.              *)

GENERIC MODULE Extract (Rep);

IMPORT IR, CallExpr, Expr, ExprRep, Procedure;
IMPORT IntegerExpr, Type, ProcType, Host, Card;
IMPORT Target, TInt, TWord, Value, Formal, CheckExpr, Error;
FROM Rep IMPORT T;
FROM TargetMap IMPORT Word_types;

VAR Z: CallExpr.MethodList;
VAR formals: Value.T;
VAR rep: [FIRST (Word_types) .. LAST (Word_types)];

PROCEDURE Check (ce: CallExpr.T;  VAR cs: Expr.CheckState) =
  BEGIN
    EVAL Formal.CheckArgs (cs, ce.args, formals, ce.proc);
    ce.type := T;
  END Check;

PROCEDURE Compile (ce: CallExpr.T) =
  VAR
    t1, t2: IR.Val;
    max: Target.Int;
    b, x1, x2: BOOLEAN;
    i1, i2: INTEGER;
  BEGIN
    x1 := GetBitIndex (ce.args[1], i1);
    x2 := GetBitIndex (ce.args[2], i2);

    IF x1 AND x2 THEN
      (* we can use the extract_mn operator *)
      IF (i1 + i2 > Word_types[rep].size) THEN
        Error.Warn (2, "Word.Extract: i+n value out of range");
        IR.Load_integer (Target.Integer.cg_type, TInt.One);
        IR.Check_hi (Target.Integer.cg_type, TInt.Zero,
                     IR.RuntimeError.ValueOutOfRange);
      ELSE
        Expr.Compile (ce.args[0]);
        IR.Extract_mn (Word_types[rep].cg_type, FALSE, i1, i2);
      END;

    ELSIF x2 THEN
      (* we can use the extract_n operator *)
      b := TInt.FromInt (Word_types[rep].size - i2, max);  <*ASSERT b*>
      Expr.Compile (ce.args[0]);
      CheckExpr.EmitChecks (ce.args[1], TInt.Zero, max,
                            IR.RuntimeError.ValueOutOfRange);
      IR.Extract_n (Word_types[rep].cg_type, FALSE, i2);

    ELSIF x1 THEN
      (* we need the general purpose extract operator, but can simplify
         the range checking code *)
      b := TInt.FromInt (Word_types[rep].size - i1, max);  <*ASSERT b*>
      Expr.Compile (ce.args[0]);
      IR.ForceStacked ();
      IR.Load_intt (i1);
      CheckExpr.EmitChecks (ce.args[2], TInt.Zero, max,
                            IR.RuntimeError.ValueOutOfRange);
      IR.Extract (Word_types[rep].cg_type, sign := FALSE);

    ELSE
      (* we need the general purpose extract operator *)
      CheckExpr.EmitChecks (ce.args[1], TInt.Zero, Target.Integer.max,
                            IR.RuntimeError.ValueOutOfRange);
      t1 := IR.Pop ();
      CheckExpr.EmitChecks (ce.args[2], TInt.Zero, Target.Integer.max,
                            IR.RuntimeError.ValueOutOfRange);
      t2 := IR.Pop ();
      IF Host.doRangeChk THEN
        b := TInt.FromInt (Word_types[rep].size, max);  <*ASSERT b*>
        IR.Push (t1);
        IR.Push (t2);
        IR.Add (Target.Integer.cg_type);
        IR.Check_hi (Target.Integer.cg_type, max,
                     IR.RuntimeError.ValueOutOfRange);
        IR.Discard (Target.Integer.cg_type);
      END;
      Expr.Compile (ce.args[0]);
      IR.ForceStacked ();
      IR.Push (t1);
      IR.Push (t2);
      IR.Extract (Word_types[rep].cg_type, sign := FALSE);
      IR.Free (t1);
      IR.Free (t2);
    END;
  END Compile;

PROCEDURE GetBitIndex (e: Expr.T;  VAR i: INTEGER): BOOLEAN =
  BEGIN
    e := Expr.ConstValue (e);
    IF (e = NIL) THEN RETURN FALSE END;
    RETURN IntegerExpr.ToInt (e, i)
       AND (0 <= i) AND (i <= Word_types[rep].size);
  END GetBitIndex;

PROCEDURE Fold (ce: CallExpr.T): Expr.T =
  VAR e0: Expr.T;  w0, result: Target.Int;  i1, i2: INTEGER;  t: Type.T;
  BEGIN
    e0 := Expr.ConstValue (ce.args[0]);
    IF   (e0 = NIL)
      OR NOT IntegerExpr.Split (e0, w0, t)
      OR NOT GetBitIndex (ce.args[1], i1)
      OR NOT GetBitIndex (ce.args[2], i2)
      OR i1 + i2 > Word_types[rep].size
      OR NOT TWord.Extract (w0, i1, i2, result) THEN
      RETURN NIL;
    END;
    EVAL TInt.Extend (result, Word_types[rep].bytes, result);
    RETURN IntegerExpr.New (T, result);
  END Fold;

PROCEDURE GetBounds (ce: CallExpr.T;  VAR min, max: Target.Int) =
  VAR min_bits, max_bits: Target.Int;  i: INTEGER;
  BEGIN
    Expr.GetBounds (ce.args[2], min_bits, max_bits);
    IF TInt.ToInt (max_bits, i) AND 0 <= i AND i < Word_types[rep].size THEN
      IF NOT TWord.Extract (TInt.MOne, 0, i, max) THEN
        EVAL Type.GetBounds (T, min, max);
      END;
      min := TInt.Zero;
    ELSE
      (* possible that we'll preserve all bits *)
      Expr.GetBounds (ce.args[0], min, max);
    END;
  END GetBounds;

PROCEDURE Initialize (r: INTEGER) =
  VAR
    f0 := Formal.NewBuiltin ("x", 0, T);
    f1 := Formal.NewBuiltin ("i", 1, Card.T);
    f2 := Formal.NewBuiltin ("n", 2, Card.T);
    t  := ProcType.New (T, f0, f1, f2);
  BEGIN
    rep := r;
    Z := CallExpr.NewMethodList (3, 3, TRUE, TRUE, TRUE, T,
                                 NIL, NIL,
                                 CallExpr.NotAddressable,
                                 Check,
                                 CallExpr.PrepArgs,
                                 Compile,
                                 CallExpr.NoLValue,
                                 CallExpr.NoLValue,
                                 CallExpr.NotBoolean,
                                 CallExpr.NotBoolean,
                                 Fold,
                                 GetBounds,
                                 CallExpr.IsNever, (* writable *)
                                 CallExpr.IsNever, (* designator *)
                                 CallExpr.NotWritable (* noteWriter *));
    Procedure.DefinePredefined ("Extract", Z, FALSE, t, assignable:=TRUE);
    formals := ProcType.Formals (t);
  END Initialize;

BEGIN
END Extract.
