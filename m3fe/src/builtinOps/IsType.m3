(* Copyright (C) 1992, Digital Equipment Corporation           *)
(* All rights reserved.                                        *)
(* See the file COPYRIGHT for a full description.              *)

(* File: IsType.m3                                             *)
(* Last Modified On Tue May  3 16:31:06 PDT 1994 By kalsow     *)
(*      Modified On Sat Dec  8 00:54:22 1990 By muller         *)

MODULE IsType;

IMPORT IR, CallExpr, Expr, ExprRep, Type, Error, TypeExpr, Reff, RefType;
IMPORT Procedure, Bool, ObjectType, Null, Value, M3RT, Target, RunTyme;
IMPORT TInt;

VAR Z: CallExpr.MethodList;

PROCEDURE Check (ce: CallExpr.T;  <*UNUSED*> VAR cs: Expr.CheckState) =
  VAR t, u: Type.T;
  BEGIN
    IF  NOT TypeExpr.Split (ce.args[1], t) THEN
      Error.Msg ("ISTYPE: second argument must be a type");
      t := Expr.TypeOf (ce.args[0]);
    END;
    t := Type.Base (t);
    u := Expr.TypeOf (ce.args[0]);

    IF NOT Type.IsAssignable (t, u) THEN
      Error.Msg ("ISTYPE: types must be assignable");
    ELSIF ObjectType.Is (t) OR Type.IsSubtype (t, Reff.T) THEN
      (* ok *)
    ELSE (* untraced ref type *)
      Error.Msg ("ISTYPE: must be a traced reference or object type");
    END;

    ce.type := Bool.T;
  END Check;

PROCEDURE Prep (ce: CallExpr.T) =
  VAR
    e := ce.args[0];
    t, u: Type.T;
    ptr: IR.Val;
    true, false, tagged: IR.Label;
    proc: Procedure.T;
  BEGIN
    IF NOT TypeExpr.Split (ce.args[1], t) THEN
      t := Expr.TypeOf (e);
    END;
    Type.Compile (t);
    t := Type.Base (t);
    u := Expr.TypeOf (e);

    Expr.Prep (ce.args[0]);
    IF Type.IsSubtype (u, t) THEN
      (* the test succeeds statically *)
      Expr.Compile (ce.args[0]);
      IR.Discard (IR.Type.Addr);
      Value.Load (Bool.True);
      ce.tmp := IR.Pop ();

    ELSIF Type.IsEqual (t, Null.T, NIL) THEN
      Expr.Compile (ce.args[0]);
      IR.Load_nil ();
      IR.Compare (IR.Type.Addr, IR.Cmp.EQ);
      ce.tmp := IR.Pop ();

    ELSIF RefType.Is (t) THEN
      Expr.Compile (ce.args[0]);
      tagged := IR.Next_label ();
      false := IR.Next_label ();
      true := IR.Next_label ();
      ptr := IR.Pop ();
      Value.Load (Bool.True);
      IR.ForceStacked (); (* we need a temp *)
      ce.tmp := IR.Pop_temp ();
      IR.Push (ptr);
      IR.Load_nil ();
      IR.If_compare (IR.Type.Addr, IR.Cmp.EQ, true, IR.Maybe);

      IR.Push (ptr);
      IR.Loophole (IR.Type.Addr, Target.Word.cg_type);
      IR.Load_integer (Target.Word.cg_type, TInt.One);
      IR.And (Target.Word.cg_type);
      IR.If_true (tagged, IR.Maybe);

      IR.Push (ptr);
      IR.Ref_to_info (M3RT.RH_typecode_offset, M3RT.RH_typecode_size);
      Type.LoadInfo (t, M3RT.TC_typecode);
      IR.If_compare (Target.Integer.cg_type, IR.Cmp.EQ, true, IR.Always);
      IR.Jump (false);
      
      IR.Set_label (tagged);
      IR.Load_intt (M3RT.REFANY_typecode);
      Type.LoadInfo (t, M3RT.TC_typecode);
      IR.If_compare (Target.Integer.cg_type, IR.Cmp.EQ, true, IR.Always);

      IR.Set_label (false);
      Value.Load (Bool.False);
      IR.Store_temp (ce.tmp);

      IR.Set_label (true);
      IR.Free (ptr);

    ELSE (* general object type *)
      proc := RunTyme.LookUpProc (RunTyme.Hook.CheckIsType);
      Procedure.StartCall (proc);
      IF Target.DefaultCall.args_left_to_right THEN
        Expr.Compile (ce.args[0]);
        IR.Pop_param (IR.Type.Addr);
        Type.LoadInfo (t, -1);
        IR.Pop_param (IR.Type.Addr);
      ELSE
        Type.LoadInfo (t, -1);
        IR.Pop_param (IR.Type.Addr);
        Expr.Compile (ce.args[0]);
        IR.Pop_param (IR.Type.Addr);
      END;
      ce.tmp := Procedure.EmitValueCall (proc);
    END;
  END Prep;

PROCEDURE Compile (ce: CallExpr.T) =
  BEGIN
    (* all the work was done by Prep *)
    IR.Push (ce.tmp);
    IR.Free (ce.tmp);
    ce.tmp := NIL;
  END Compile;

PROCEDURE PrepBR (ce: CallExpr.T;  true, false: IR.Label;  freq: IR.Frequency)=
  VAR
    e := ce.args[0];
    t, u: Type.T;
    ptr: IR.Val;
    skip, tagged: IR.Label;
    proc: Procedure.T;
  BEGIN
    IF NOT TypeExpr.Split (ce.args[1], t) THEN
      t := Expr.TypeOf (e);
    END;
    Type.Compile (t);
    t := Type.Base (t);
    u := Expr.TypeOf (e);

    Expr.Prep (ce.args[0]);
    IF Type.IsSubtype (u, t) THEN
      (* the test succeeds statically *)
      Expr.Compile (ce.args[0]);
      IR.Discard (IR.Type.Addr);
      IF (true # IR.No_label)
        THEN IR.Jump (true);
      (*ELSE fall through*)
      END;

    ELSIF Type.IsEqual (t, Null.T, NIL) THEN
      Expr.Compile (ce.args[0]);
      IR.Load_nil ();
      IR.If_then (IR.Type.Addr, IR.Cmp.EQ, true, false, freq);

    ELSIF RefType.Is (t) THEN
      Expr.Compile (ce.args[0]);
      tagged := IR.Next_label ();
      skip := IR.Next_label ();
      ptr := IR.Pop ();
      IR.Push (ptr);
      IR.Load_nil ();
      IF (true # IR.No_label)
        THEN IR.If_compare (IR.Type.Addr, IR.Cmp.EQ, true, IR.Maybe);
        ELSE IR.If_compare (IR.Type.Addr, IR.Cmp.EQ, skip, IR.Maybe);
      END;

      IR.Push (ptr);
      IR.Loophole (IR.Type.Addr, Target.Word.cg_type);
      IR.Load_integer (Target.Word.cg_type, TInt.One);
      IR.And (Target.Word.cg_type);
      IR.If_true (tagged, IR.Maybe);

      IR.Push (ptr);
      IR.Ref_to_info (M3RT.RH_typecode_offset, M3RT.RH_typecode_size);
      Type.LoadInfo (t, M3RT.TC_typecode);
      IR.If_then (Target.Integer.cg_type, IR.Cmp.EQ, true, false, freq);
      IR.Jump (skip);

      IR.Set_label (tagged);
      IR.Load_intt (M3RT.REFANY_typecode);
      Type.LoadInfo (t, M3RT.TC_typecode);
      IR.If_then (Target.Integer.cg_type, IR.Cmp.EQ, true, false, freq);
      IR.Set_label (skip);
      IR.Free (ptr);

    ELSE (* general object type *)
      proc := RunTyme.LookUpProc (RunTyme.Hook.CheckIsType);
      Procedure.StartCall (proc);
      IF Target.DefaultCall.args_left_to_right THEN
        Expr.Compile (ce.args[0]);
        IR.Pop_param (IR.Type.Addr);
        Type.LoadInfo (t, -1);
        IR.Pop_param (IR.Type.Addr);
      ELSE
        Type.LoadInfo (t, -1);
        IR.Pop_param (IR.Type.Addr);
        Expr.Compile (ce.args[0]);
        IR.Pop_param (IR.Type.Addr);
      END;
      Procedure.EmitCall (proc);
      IF (true # IR.No_label)
        THEN IR.If_true (true, IR.Always);
        ELSE IR.If_false (false, IR.Never);
      END;
    END;
  END PrepBR;

PROCEDURE Initialize () =
  BEGIN
    Z := CallExpr.NewMethodList (2, 2, TRUE, FALSE, TRUE, Bool.T,
                                 NIL, NIL,
                                 CallExpr.NotAddressable,
                                 Check,
                                 Prep,
                                 Compile,
                                 CallExpr.NoLValue,
                                 CallExpr.NoLValue,
                                 PrepBR,
                                 CallExpr.NoBranch,
                                 CallExpr.NoValue, (* fold *)
                                 CallExpr.NoBounds,
                                 CallExpr.IsNever, (* writable *)
                                 CallExpr.IsNever, (* designator *)
                                 CallExpr.NotWritable (* noteWriter *));
    Procedure.DefinePredefined ("ISTYPE", Z, TRUE);
  END Initialize;

BEGIN
END IsType.
