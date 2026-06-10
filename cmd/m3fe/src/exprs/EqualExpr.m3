(* Copyright (C) 1992, Digital Equipment Corporation           *)
(* All rights reserved.                                        *)
(* See the file COPYRIGHT for a full description.              *)

(* File: EqualExpr.m3                                          *)
(* Last modified on Thu Jun 29 14:03:25 PDT 1995 by kalsow     *)
(*      modified on Thu Nov 29 03:33:19 1990 by muller         *)

MODULE EqualExpr;

IMPORT M3, M3ID, IR, Expr, ExprRep, Type, Procedure, TargetMap;
IMPORT Bool, Int, Reel, LReel, EReel, SetExpr, Variable;
IMPORT IntegerExpr, ReelExpr, EnumExpr, AddressExpr, UserProc;
IMPORT ProcExpr, ProcType, TextExpr, Error, M3WString;
IMPORT RecordType, ArrayType, Field, Value, M3String, Textt;
IMPORT NamedExpr, QualifyExpr, OpenArrayType, Target, TInt;

CONST
  Max_unroll = 4; (* max # of iterations in an unrolled loop *)

TYPE
  Kind = {SimpleScalar, SimpleStruct, Complex};

TYPE
  Op = [ IR.Cmp.EQ .. IR.Cmp.NE ];

CONST
  OpName = ARRAY Op OF TEXT { "\'=\'", "\'#\'" };

TYPE
  P = ExprRep.Tabc BRANDED "EqualExpr.P" OBJECT
        op     : Op;
        kind   : Kind;
        tmp    : IR.Val;
      OVERRIDES
        typeOf       := ExprRep.NoType;
        repTypeOf    := ExprRep.NoType;
        check        := Check;
        need_addr    := ExprRep.NotAddressable;
        prep         := Prep;
        compile      := Compile;
        prepLV       := ExprRep.NotLValue;
        compileLV    := ExprRep.NotLValueBool;
        prepBR       := PrepBR;
        compileBR    := ExprRep.NoBranch;
        evaluate     := Fold;
        isEqual      := EqCheck;
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

PROCEDURE New (a, b: Expr.T;  op: Op): Expr.T =
  VAR p: P;
  BEGIN
    p := NEW (P);
    ExprRep.Init (p);
    p.a       := a;
    p.b       := b;
    p.op      := op;
    p.type    := Bool.T;
    p.repType := Bool.T;
    p.kind    := Kind.SimpleScalar;
    p.tmp     := NIL;
    RETURN p;
  END New;

PROCEDURE Check (p: P;  VAR cs: Expr.CheckState) =
  VAR ta, tb: Type.T;  str: M3String.T;  wstr: M3WString.T;
  BEGIN
    Expr.TypeCheck (p.a, cs);
    Expr.TypeCheck (p.b, cs);
    ta := Type.Base (Expr.TypeOf (p.a));
    tb := Type.Base (Expr.TypeOf (p.b));
    IF (ta = NIL) OR (tb = NIL)
      OR NOT (Type.IsAssignable (ta, tb) OR Type.IsAssignable (tb, ta)) THEN
      p.type := Expr.BadOperands (OpName[p.op], ta, tb);
    END;
    p.kind := Classify (ta, tb);
    IF (p.kind = Kind.SimpleScalar) AND ((ta = Textt.T) OR (tb = Textt.T)) THEN
      IF TextExpr.Split8 (p.a, str) OR TextExpr.Split32 (p.a, wstr)
      OR TextExpr.Split8 (p.b, str) OR TextExpr.Split32 (p.b, wstr) THEN
        Error.Warn (1,"comparing pointers, use Text.Equal to compare strings");
      END;
    END;
  END Check;

PROCEDURE Classify (ta, tb: Type.T): Kind =
  VAR ia, ib: Type.Info;
  BEGIN
    IF (ta = Int.T) OR (ta = Reel.T) OR (ta = LReel.T) OR (ta = EReel.T) THEN
      RETURN Kind.SimpleScalar;
    END;

    EVAL Type.CheckInfo (ta, ia);

    CASE ia.class OF
    | Type.Class.Error,
      Type.Class.Integer,
      Type.Class.Longint,
      Type.Class.Real,
      Type.Class.Longreal,
      Type.Class.Extended,
      Type.Class.Enum,
      Type.Class.Object,
      Type.Class.Opaque,
      Type.Class.Ref,
      Type.Class.Subrange =>
          RETURN Kind.SimpleScalar;
    | Type.Class.Set =>
          IF (ia.size <= Target.Integer.size) THEN
            RETURN Kind.SimpleScalar;
          END;
    ELSE (* skip *)
    END;
    
    EVAL Type.CheckInfo (tb, ib);

    IF SimpleStructType (ia) AND SimpleStructType (ib) THEN
      RETURN Kind.SimpleStruct;
    END;

    RETURN Kind.Complex;
  END Classify;

PROCEDURE SimpleStructType (READONLY info: Type.Info): BOOLEAN =
  BEGIN
    RETURN (info.isSolid)
       AND (info.class # Type.Class.Procedure)
       AND (info.class # Type.Class.OpenArray)
       AND (info.size >= 0)
       AND (info.size MOD info.alignment = 0)
       AND (info.size DIV info.alignment <= Max_unroll)
       AND (FindCompareType (info.size, info.alignment) # IR.Type.Void);
  END SimpleStructType;

PROCEDURE FindCompareType (size, align: INTEGER): IR.Type =
  CONST Z = ARRAY [0..3] OF IR.Type { IR.Type.Word64, IR.Type.Word32,
                                      IR.Type.Word16, IR.Type.Word8 };
  VAR t: IR.Type;
  BEGIN
    FOR i := FIRST (Z) TO LAST (Z) DO
      t := Z[i];
      IF (align = TargetMap.CG_Align [t])
        AND (size MOD TargetMap.CG_Size [t] = 0)
        AND (Target.Word.size >= TargetMap.CG_Size [t]) THEN
        RETURN t;
      END;
    END;
    RETURN IR.Type.Void;
  END FindCompareType;

PROCEDURE EqCheck (a: P;  e: Expr.T;  x: M3.EqAssumption): BOOLEAN =
  BEGIN
    TYPECASE e OF
    | NULL => RETURN FALSE;
    | P(b) => RETURN (a.op = b.op)
                 AND Expr.IsEqual (a.a, b.a, x)
                 AND Expr.IsEqual (a.b, b.b, x);
    ELSE      RETURN FALSE;
    END;
  END EqCheck;

PROCEDURE Prep (p: P) =
  VAR false: IR.Label;
  BEGIN
    Expr.Prep (p.a);
    Expr.Prep (p.b);
    IF (p.kind = Kind.Complex) THEN
      (* use the branching code to compute a value *)
      false := IR.Next_label (2);
      PrepBR (p, IR.No_label, false, IR.Maybe);
      Value.Load (Bool.True);
      p.tmp := IR.Pop_temp ();
      IR.Jump (false+1);
      IR.Set_label (false);
      Value.Load (Bool.False);
      IR.Store_temp (p.tmp);
      IR.Set_label (false+1);
    END;
  END Prep;

PROCEDURE Compile (p: P; StaticOnly: BOOLEAN) =
  VAR t := p.a.type;
  BEGIN
    <* ASSERT NOT StaticOnly *>
    IF (p.kind = Kind.SimpleScalar) THEN
      Expr.Compile (p.a);
      Expr.Compile (p.b);
      IR.Compare (Type.IRType (t), p.op);
    ELSIF (p.kind = Kind.SimpleStruct) THEN
      CompileSolidUnrolled (p);
    ELSE
      (* used the branching code to compute a value *)
      IR.Push (p.tmp);
      IR.Free (p.tmp);
      p.tmp := NIL;
    END;
  END Compile;

PROCEDURE CompileSolidUnrolled (p: P) =
  VAR
    info       : Type.Info;
    xa, xb     : IR.Val;
    cmp_type   : IR.Type;
    chunk_size : INTEGER;
    n_chunks   : INTEGER;
  BEGIN
    Expr.Compile (p.a);  xa := IR.Pop ();
    Expr.Compile (p.b);  xb := IR.Pop ();
    EVAL Type.CheckInfo (p.a.type, info);

    cmp_type := FindCompareType (info.size, info.alignment);
    <*ASSERT cmp_type # IR.Type.Void*>
    chunk_size := TargetMap.CG_Size [cmp_type];
    n_chunks := info.size DIV chunk_size;

    FOR i := 0 TO n_chunks - 1 DO
      IR.Push (xa);
      IR.Load_indirect (cmp_type, i * chunk_size, chunk_size, info.alignment);
      IR.Push (xb);
      IR.Load_indirect (cmp_type, i * chunk_size, chunk_size, info.alignment);
      IR.Compare (Target.Word.cg_type, p.op);
      IF (i > 0) THEN
        IF (p.op = IR.Cmp.EQ)
          THEN IR.And (Target.Word.cg_type);
          ELSE IR.Or  (Target.Word.cg_type);
        END;
      END;
    END;

    IR.Free (xa);
    IR.Free (xb);
  END CompileSolidUnrolled;

PROCEDURE PrepBR (p: P;  true, false: IR.Label;  freq: IR.Frequency) =
  VAR
    ta := Type.Base (p.a.type);
    tb := Type.Base (p.b.type);

    skip: IR.Label;
    xa, xb: IR.Val;
    info: Type.Info;
  BEGIN
    Expr.Prep (p.a);
    Expr.Prep (p.b);
    ta := Type.CheckInfo (ta, info);
    IF (p.kind = Kind.SimpleScalar) THEN
      Expr.Compile (p.a);
      Expr.Compile (p.b);
      IR.If_then (info.stk_type, p.op, true, false, freq);
      RETURN;
 
    (************ better to generate "If_eq" than  "eq; if_true" 
    ELSIF (p.kind = Kind.SimpleStruct) THEN
      CompileSolidUnrolled (p);
      IF (true # IR.No_label)
        THEN IR.If_true (true, freq);
        ELSE IR.If_false (false, freq);
      END;
      RETURN;
    ***************************************************************)

    ELSIF (info.class = Type.Class.Set) THEN
      Expr.Compile (p.a);
      Expr.Compile (p.b);
      IR.Set_compare (info.size, p.op);
      IF (true = IR.No_label)
        THEN IR.If_false (false, freq);
        ELSE IR.If_true (true, freq);
      END;
      RETURN;

    ELSIF (info.class = Type.Class.Procedure) OR ProcType.Is (tb) THEN
      IF (p.op = IR.Cmp.EQ)
        THEN CompileProcs (p, true, false, freq);
        ELSE CompileProcs (p, false, true, freq);
      END;

    ELSIF (info.class = Type.Class.Record)
       OR (info.class = Type.Class.Array)
       OR (info.class = Type.Class.OpenArray) THEN
      Expr.Compile (p.a);  xa := IR.Pop ();
      Expr.Compile (p.b);  xb := IR.Pop ();
      IF (p.op = IR.Cmp.NE) THEN  (* swap true and false labels *)
        skip := true;  true := false;  false := skip;
      END;
      IF (false = IR.No_label) THEN
        skip := IR.Next_label ();
        CompileTest (xa, xb, ta, tb, skip, IR.Always - freq);
        IR.Jump (true);
        IR.Set_label (skip);
      ELSE
        CompileTest (xa, xb, ta, tb, false, freq);
      END;
      IR.Free (xa);
      IR.Free (xb);

    ELSE 
      (* typechecking removed the other cases. *)
      EVAL Expr.BadOperands (OpName[p.op], ta, tb);
    END;
  END PrepBR;

PROCEDURE CompileProcs (p: P;  true, false: IR.Label;  freq: IR.Frequency) =
  VAR
    procA, procB : Value.T;
    classA, classB: [0..2];
    t1, t2 : IR.Val;
    skip, no_closure, nope: IR.Label;
  BEGIN
    (* first we classify the two arguments:
         class 0: NIL, global proc, or non-formal variable => no frame pointer
         class 1: nested proc => fixed frame pointer
         class 2: formal variable => may be closure => may have frame

       Note: procedures pointers are always aligned!
     *)
    classA := 0;
    IF UserProc.IsProcedureLiteral (p.a, procA)
       AND Procedure.IsNested (procA) THEN      classA := 1;
    ELSIF CanHaveFrame (p.a) THEN               classA := 2;
    END;
    classB := 0;
    IF UserProc.IsProcedureLiteral (p.b, procB)
       AND Procedure.IsNested (procB) THEN      classB := 1;
    ELSIF CanHaveFrame (p.b) THEN               classB := 2;
    END;

    (* normalize the pair so that classA <= classB *)
    IF (classB < classA) THEN
      VAR tmp := classA;  BEGIN classA := classB;  classB := tmp  END;
      VAR tmp := p.a;     BEGIN p.a := p.b;        p.b := tmp     END;
      VAR tmp := procA;   BEGIN procA := procB;    procB := tmp   END;
    END;

    (* finally, we generate the tests, based on the classes *)
    CASE classA * 3 + classB OF

    | 0,   (* 0, 0 *)
      4 => (* 1, 1 *)
           Expr.Compile (p.a);
           Expr.Compile (p.b);
           IR.If_then (IR.Type.Addr, IR.Cmp.EQ, true, false, freq);

    | 1 => (* 0, 1 => never equal *)
           (* constant FALSE *)
           IF (true = IR.No_label)
             THEN IR.Jump (false);
             ELSE (* fall through *)
           END;

    | 2 => (* 0, 2 *)
           skip := IR.Next_label ();
           nope := skip;  IF (true = IR.No_label) THEN nope := false; END;
           Expr.Compile (p.b);
           t1 := IR.Pop ();
           IR.If_closure (t1, nope, IR.No_label, IR.Always - freq);
           Expr.Compile (p.a);
           IR.Push (t1);
           IR.If_then (IR.Type.Addr, IR.Cmp.EQ, true, false, freq);
           IR.Set_label (skip);
           IR.Free (t1);

    | 5 => (* 1, 2 *)
           skip := IR.Next_label ();
           nope := skip;  IF (true = IR.No_label) THEN nope := false; END;
           Expr.Compile (p.b);
           t1 := IR.Pop ();
           IR.If_closure (t1, IR.No_label, nope, freq);
           Expr.Compile (p.a);
           IR.Push (t1);
           IR.Closure_proc ();
           IR.If_compare (IR.Type.Addr, IR.Cmp.NE, nope, freq);
           Procedure.LoadStaticLink (procA);
           IR.Push (t1);
           IR.Closure_frame ();
           IR.If_then (IR.Type.Addr, IR.Cmp.EQ, true, false, freq);
           IR.Set_label (skip);
           IR.Free (t1);

    | 8 => (* 2, 2 *)
           no_closure := IR.Next_label (2);
           skip := no_closure + 1;
           nope := skip;  IF (true = IR.No_label) THEN nope := false; END;

           Expr.Compile (p.a);
           t1 := IR.Pop ();
           Expr.Compile (p.b);
           t2 := IR.Pop ();

           IR.If_closure (t1, IR.No_label, no_closure, IR.Maybe);
           (* A is a closure... *)

           IR.If_closure (t2, nope, IR.No_label, IR.Always - freq);

           (* both A and B are closures *)
           IR.Push (t1);
           IR.Closure_proc ();
           IR.Push (t2);
           IR.Closure_proc ();
           IR.If_compare (IR.Type.Addr, IR.Cmp.NE, nope, IR.Always - freq);
           IR.Push (t1);
           IR.Closure_frame ();
           IR.Push (t2);
           IR.Closure_frame ();
           IR.If_compare (IR.Type.Addr, IR.Cmp.NE, nope, IR.Always - freq);

           (* A is not a closure *)
           IR.Set_label (no_closure);
           IR.If_closure (t2, nope, IR.No_label, IR.Always - freq);

           (* neither A nor B is a closure *)
           IR.Push (t1);
           IR.Push (t2);
           IR.If_then (IR.Type.Addr, IR.Cmp.EQ, true, false, freq);
           IR.Set_label (skip);
           IR.Free (t1);
           IR.Free (t2);

    ELSE <*ASSERT FALSE*>
    END;
  END CompileProcs;

PROCEDURE CanHaveFrame (e: Expr.T): BOOLEAN =
  VAR name: M3ID.T;  obj: Value.T;
  BEGIN
    IF NOT (NamedExpr.Split (e, name, obj) OR QualifyExpr.Split (e, obj)) THEN
      (* non-constant, non-variable => no frame *)
      RETURN FALSE;
    ELSIF (Value.ClassOf (obj) = Value.Class.Procedure) THEN
      (* constant: no frame *)
      RETURN FALSE;
    ELSIF (Value.ClassOf (obj) = Value.Class.Var) AND
          Variable.HasClosure (Value.Base (obj)) THEN
      RETURN TRUE;
    ELSE (* non-formal, non-const => frame = NIL *)
      RETURN FALSE;
    END;
  END CanHaveFrame;

PROCEDURE CompileTest (x1, x2 : IR.Val;
                       t1, t2 : Type.T;
                       false  : IR.Label;
                       freq   : IR.Frequency) =
  VAR
    u1_info, u2_info: Type.Info;
    u1 := Type.Base (t1);  (* strip the BITS FOR *)
    u2 := Type.Base (t2);
  BEGIN
    EVAL Type.CheckInfo (u1, u1_info);
    EVAL Type.CheckInfo (u2, u2_info);
    IF (u1_info.class = Type.Class.Record) THEN
      CompileRecord (x1, x2, u1, false, freq);

    ELSIF (u1_info.class = Type.Class.Array)
       OR (u1_info.class = Type.Class.OpenArray) THEN
      CompileArray (x1, x2, u1, u2, false, freq);

    ELSIF (u1_info.class = Type.Class.Set) THEN
      IR.Push (x1);
      IF (u1_info.size <= Target.Integer.size) THEN
        IR.Load_indirect
          (Target.Word.cg_type, 0, Target.Integer.size, u1_info.alignment);
      END;
      IR.Push (x2);
      IF (u1_info.size <= Target.Integer.size) THEN
        IR.Load_indirect
          (Target.Word.cg_type, 0, Target.Integer.size, u2_info.alignment);
      END;
      IR.Set_compare (u1_info.size, IR.Cmp.EQ);
      IR.If_false (false, freq);

    ELSIF (u1_info.class = Type.Class.Procedure)
       OR (u2_info.class = Type.Class.Procedure) THEN
      (* we're already inside some variable => no frame pointers *)
      IR.Push (x1);
      IR.Load_indirect (IR.Type.Addr, 0, Target.Address.size, IR.ProcAlign ());
      IR.Push (x2);
      IR.Load_indirect (IR.Type.Addr, 0, Target.Address.size, IR.ProcAlign ());
      IR.If_compare (IR.Type.Addr, IR.Cmp.NE, false, freq);

    ELSE (* simple scalars *)
      EVAL Type.CheckInfo (t1, u1_info);  (* can't ignore BITS FOR *)
      EVAL Type.CheckInfo (t2, u2_info);
      IR.Push (x1);
      IR.Boost_addr_alignment (Target.Address.align);
      IR.Load_indirect (u1_info.stk_type, 0, u1_info.size, u1_info.alignment);
      IR.Push (x2);
      IR.Boost_addr_alignment (Target.Address.align);
      IR.Load_indirect (u2_info.stk_type, 0, u2_info.size, u2_info.alignment);
      IR.If_compare (u1_info.stk_type, IR.Cmp.NE, false, freq);
    END;
  END CompileTest;

PROCEDURE CompileArray (p1, p2 : IR.Val;
                        t1, t2 : Type.T;
                        false  : IR.Label;
                        freq   : IR.Frequency) =
  VAR i1, i2, e1, e2: Type.T;
  BEGIN
    IF CompileSolid (p1, p2, t1, t2, false, freq) THEN RETURN END;
    EVAL ArrayType.Split (t1, i1, e1);
    EVAL ArrayType.Split (t2, i2, e2);
    GenShapeCheck (p1, p2, i1, e1, i2, e2, false, freq);
    GenValueCheck (t1, i1, e1, p1, t2, i2, e2, p2, false, freq);
  END CompileArray;

PROCEDURE GenShapeCheck (p1, p2 : IR.Val;
                         i1, e1 : Type.T;
                         i2, e2 : Type.T;
                         false  : IR.Label;
                         freq   : IR.Frequency) =
  VAR n := 0;
  BEGIN
    LOOP
      IF (i1 # NIL) AND (i2 # NIL) THEN RETURN END;

      IF (i1 = NIL) THEN
        IR.Push (p1);
        IR.Open_size (n);
      ELSE
        IR.Load_integer (Target.Integer.cg_type, Type.Number (i1));
      END;
      IF (i2 = NIL) THEN
        IR.Push (p2);
        IR.Open_size (n);
      ELSE
        IR.Load_integer (Target.Integer.cg_type, Type.Number (i2));
      END;
      IR.If_compare (Target.Integer.cg_type, IR.Cmp.NE, false, freq);

      IF NOT ArrayType.Split (e1, i1, e1) THEN RETURN END;
      IF NOT ArrayType.Split (e2, i2, e2) THEN RETURN END;
      n := n + 1;
    END;
  END GenShapeCheck;


PROCEDURE GenValueCheck (t1, i1, e1: Type.T;  p1: IR.Val; 
                         t2, i2, e2: Type.T;  p2: IR.Val;
                         false: IR.Label;
                         freq: IR.Frequency) =
  VAR
    d1 := OpenArrayType.OpenDepth (t1);
    d2 := OpenArrayType.OpenDepth (t2);
    x: IR.Val;
  BEGIN
    IF (d1 > 0) AND (d2 > 0) THEN
      IF (d1 <= d2)
        THEN GenOpenValueCheck (t1, p1, p2, false, freq);
        ELSE GenOpenValueCheck (t2, p1, p2, false, freq);
      END;
    ELSIF (d1 > 0) THEN
      IR.Push (p1);
      IR.Open_elt_ptr (OpenArrayType.EltAlign (t1));
      x := IR.Pop ();
      GenFixedValueCheck (t2, i2, e2, x, p2, false, freq);
      IR.Free (x);
    ELSIF (d2 > 0) THEN
      IR.Push (p2);
      IR.Open_elt_ptr (OpenArrayType.EltAlign (t2));
      x := IR.Pop ();
      GenFixedValueCheck (t1, i1, e1, p1, x, false, freq);
      IR.Free (x);
    ELSE (* d1 = 0 AND d2 = 0 *)
      GenFixedValueCheck (t1, i1, e1, p1, p2, false, freq);
    END;
  END GenValueCheck;

PROCEDURE GenOpenValueCheck (t1: Type.T;  p1, p2: IR.Val; 
                             false: IR.Label;  freq: IR.Frequency) =
  VAR
    d1  := OpenArrayType.OpenDepth (t1);
    elt := OpenArrayType.NonopenEltType (t1);
    cnt       : IR.Val;
    elt_align : INTEGER;
    elt_pack  : INTEGER;
    top       : IR.Label;
    o1, o2    : IR.Val;
    info      : Type.Info;
  BEGIN
    elt := Type.CheckInfo (elt, info);
    elt_align := info.alignment;
    elt_pack  := (info.size + elt_align - 1) DIV elt_align * elt_align;

    (* compute the total number of elements that need to be compared *)
    FOR i := 0 TO d1-1 DO
      IR.Push (p1);
      IR.Open_size (i);
      IF (i # 0) THEN IR.Multiply (Target.Integer.cg_type) END;
    END;
    IR.Load_intt (1);
    IR.Subtract (Target.Integer.cg_type);
    cnt := IR.Pop_temp ();

    top := IR.Next_label (2);
    IR.Jump (top+1); (* test for empty arrays *)

    IR.Set_label (top);

    (* compute the address of the elements *)
    IR.Push (p1);
    IR.Open_elt_ptr (elt_align);
    IR.Push (cnt);
    IR.Index_bytes (elt_pack);
    o1 := IR.Pop ();

    IR.Push (p2);
    IR.Open_elt_ptr (elt_align);
    IR.Push (cnt);
    IR.Index_bytes (elt_pack);
    o2 := IR.Pop ();

    CompileTest (o1, o2, elt, elt, false, freq);

    (* free the element pointers *)
    IR.Free (o1);
    IR.Free (o2);

    (* decrement the count *)
    IR.Push (cnt);
    IR.Load_integer (Target.Integer.cg_type, TInt.One);
    IR.Subtract (Target.Integer.cg_type);
    IR.Store_temp (cnt);

    (* test for completion *)
    IR.Set_label (top+1);
    IR.Push (cnt);
    IR.Load_integer (Target.Integer.cg_type, TInt.Zero);
    IR.If_compare (Target.Integer.cg_type, IR.Cmp.GE, top, IR.Likely);

    IR.Free (cnt);
  END GenOpenValueCheck;

PROCEDURE GenFixedValueCheck (t1, i1, e1: Type.T;  p1, p2: IR.Val; 
                              false: IR.Label;  freq: IR.Frequency) =
  VAR
    cnt       : IR.Val;
    n_elts    : INTEGER;
    b         : BOOLEAN;
    top       : IR.Label;
    o1, o2    : IR.Val;
  BEGIN
    (* compute the total number of elements that need to be compared *)
    b := TInt.ToInt (Type.Number (i1), n_elts); <* ASSERT b *>
    IF (n_elts <= 0) THEN RETURN END;
    IR.Load_intt (n_elts - 1);
    cnt := IR.Pop_temp ();

    top := IR.Next_label (2);
    IR.Set_label (top);

    (* compute the address of the elements *)
    IR.Push (p1);
    IR.Push (cnt);
    ArrayType.GenIndex (t1);
    o1 := IR.Pop ();

    IR.Push (p2);
    IR.Push (cnt);
    ArrayType.GenIndex (t1);
    o2 := IR.Pop ();

    CompileTest (o1, o2, e1, e1, false, freq);

    (* free the element pointers *)
    IR.Free (o1);
    IR.Free (o2);

    (* decrement the count *)
    IR.Push (cnt);
    IR.Load_integer (Target.Integer.cg_type, TInt.One);
    IR.Subtract (Target.Integer.cg_type);
    IR.Store_temp (cnt);

    (* test for completion *)
    IR.Set_label (top+1);
    IR.Push (cnt);
    IR.Load_integer (Target.Integer.cg_type, TInt.Zero);
    IR.If_compare (Target.Integer.cg_type, IR.Cmp.GE, top, IR.Likely);

    IR.Free (cnt);
  END GenFixedValueCheck;

PROCEDURE CompileRecord (p1, p2: IR.Val;  t: Type.T;
                         false: IR.Label;  freq: IR.Frequency) =
  VAR
    v      : Value.T;
    field  : Field.Info;
    o1, o2 : IR.Val;
  BEGIN
    IF CompileSolid (p1, p2, t, t, false, freq) THEN RETURN END;
    EVAL RecordType.Split (t, v);
    WHILE (v # NIL) DO
      Field.Split (v, field);
      IR.Push (p1);
      IR.Add_offset (field.offset);
      o1 := IR.Pop ();
      IR.Push (p2);
      IR.Add_offset (field.offset);
      o2 := IR.Pop ();
      CompileTest (o1, o2, field.type, field.type, false, freq);
      IR.Free (o1);
      IR.Free (o2);
      v := v.next;
    END;
  END CompileRecord;

PROCEDURE CompileSolid (p1, p2: IR.Val;  t1, t2: Type.T;
                         false: IR.Label;  freq: IR.Frequency): BOOLEAN =
  VAR
    info1, info2 : Type.Info;
    cmp_type     : IR.Type;
    chunk_align  : INTEGER;
    chunk_size   : INTEGER;
    n_chunks     : INTEGER;
    cnt          : IR.Val;
    top          : IR.Label;
  BEGIN
    EVAL Type.CheckInfo (t1, info1);
    EVAL Type.CheckInfo (t2, info2);
    IF (NOT info1.isSolid) OR (NOT info2.isSolid) THEN RETURN FALSE END;
    IF (info1.size < 0) OR (info1.size # info2.size) THEN RETURN FALSE END;

    chunk_align := MIN (info1.alignment, info2.alignment);
    cmp_type := FindCompareType (info1.size, chunk_align);
    IF (cmp_type = IR.Type.Void) THEN RETURN FALSE; END;
    chunk_size := TargetMap.CG_Size [cmp_type];
    n_chunks   := info1.size DIV chunk_size;

    IF (n_chunks <= Max_unroll) THEN

      (* unroll the loop of comparisons *)
      FOR i := 0 TO n_chunks - 1 DO
        IR.Push (p1);
        IR.Load_indirect (cmp_type, i * chunk_size, chunk_size, chunk_align);
        IR.Push (p2);
        IR.Load_indirect (cmp_type, i * chunk_size, chunk_size, chunk_align);
        IR.If_compare (Target.Word.cg_type, IR.Cmp.NE, false, freq);
      END;

    ELSE
      (* generate a loop of comparisons *)
      IR.Load_intt (n_chunks - 1);
      cnt := IR.Pop_temp ();

      top := IR.Next_label (2);
      IR.Set_label (top);

      (* compute the address of the elements and load them *)
      IR.Push (p1);
      IR.Push (cnt);
      IR.Index_bytes (chunk_size);
      IR.Load_indirect (cmp_type, 0, chunk_size, chunk_align);

      IR.Push (p2);
      IR.Push (cnt);
      IR.Index_bytes (chunk_size);
      IR.Load_indirect (cmp_type, 0, chunk_size, chunk_align);

      (* do the comparison *)
      IR.If_compare (Target.Word.cg_type, IR.Cmp.NE, false, freq);

      (* decrement the count *)
      IR.Push (cnt);
      IR.Load_integer (Target.Integer.cg_type, TInt.One);
      IR.Subtract (Target.Integer.cg_type);
      IR.Store_temp (cnt);

      (* test for completion *)
      IR.Set_label (top+1);
      IR.Push (cnt);
      IR.Load_integer (Target.Integer.cg_type, TInt.Zero);
      IR.If_compare (Target.Integer.cg_type, IR.Cmp.GE, top, IR.Likely);

      IR.Free (cnt);
    END;

    RETURN TRUE;
  END CompileSolid;

(*************************
PROCEDURE MinFieldAlignment (f: Scope.T): INTEGER =
    (* compute the minimum field alignment that's needed *)
  VAR
    n, min  : INTEGER;
    fields  : Scope.ValueList;
    index   : INTEGER;
    offset  : INTEGER;
    type    : Type.T;
  BEGIN
    Scope.ToList (f, fields, n);
    min := MAX (Target.Address.align, Target.Integer.align);
    FOR i := 0 TO n-1 DO
      Field.Split (fields[i], index, offset, type);
      min := GCD (min, offset);
    END;
    RETURN min;
  END MinFieldAlignment;

PROCEDURE GCD (x, y: INTEGER): INTEGER =
  BEGIN
    IF (x <= 0) OR (y <= 0) THEN RETURN 1 END;
    LOOP
      IF    (x = 0) THEN RETURN y;
      ELSIF (y = 0) THEN RETURN x;
      ELSIF (x < y) THEN y := y MOD x;
      ELSIF (y < x) THEN x := x MOD y;
      ELSE  RETURN x;
      END;
    END;
  END GCD;
********************************)

PROCEDURE Fold (p: P): Expr.T =
  VAR e1, e2: Expr.T;  s: INTEGER;
  BEGIN
    e1 := Expr.ConstValue (p.a);
    IF (e1 = NIL) THEN RETURN NIL END;
    e2 := Expr.ConstValue (p.b);
    IF (e2 = NIL) THEN RETURN NIL END;
    IF   IntegerExpr.Compare (e1, e2, s)
      OR EnumExpr.Compare (e1, e2, s)
      OR ReelExpr.Compare (e1, e2, s)
      OR AddressExpr.Compare (e1, e2, s)
      OR SetExpr.Compare (e1, e2, s)
      OR ProcExpr.Compare (e1, e2, s) THEN
      RETURN Bool.Map[(p.op = IR.Cmp.EQ) = (s = 0)];
    END;
    RETURN NIL;
  END Fold;

BEGIN
END EqualExpr.
