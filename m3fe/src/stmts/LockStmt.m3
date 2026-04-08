(* Copyright (C) 1992, Digital Equipment Corporation           *)
(* All rights reserved.                                        *)
(* See the file COPYRIGHT for a full description.              *)
(*                                                             *)
(* File: LockStmt.m3                                           *)
(* Last modified on Fri Jun 24 15:50:01 PDT 1994 by kalsow     *)
(*      modified on Sun Jan 21 07:49:28 1990 by muller         *)

MODULE LockStmt;

IMPORT M3ID, Expr, Mutex, Error, Type, Stmt, StmtRep, Token, Marker;
IMPORT IR, Target, M3RT, Scanner, Procedure, RunTyme;
FROM Scanner IMPORT Match;

TYPE
  P = Stmt.T OBJECT
        mutex   : Expr.T;
        body    : Stmt.T;
        tail    : INTEGER;
      OVERRIDES
        check       := Check;
        compile     := Compile;
        outcomes    := GetOutcome;
      END;

PROCEDURE Parse (): Stmt.T =
  TYPE TK = Token.T;
  VAR p := NEW (P);
  BEGIN
    StmtRep.Init (p);
    Match (TK.tLOCK);
    p.mutex := Expr.Parse ();
    Match (TK.tDO);
    p.body := Stmt.Parse ();
    p.tail := Scanner.offset;
    Match (TK.tEND);
    RETURN p;
  END Parse;

PROCEDURE Check (p: P;  VAR cs: Stmt.CheckState) =
  VAR t: Type.T;
  BEGIN
    Expr.TypeCheck (p.mutex, cs);
    t := Expr.TypeOf (p.mutex);
    IF NOT Type.IsSubtype (t, Mutex.T) THEN
      Error.Msg ("expression must be a mutex");
    END;
    Marker.PushLock (IR.No_label, IR.No_label, NIL);
    Stmt.TypeCheck (p.body, cs);
    Marker.Pop ();
  END Check;

PROCEDURE Compile (p: P): Stmt.Outcomes =
  BEGIN
    IF Target.Has_stack_walker
      THEN RETURN Compile1 (p);
      ELSE RETURN Compile2 (p);
    END;
  END Compile;

PROCEDURE Compile1 (p: P): Stmt.Outcomes =
  VAR
    oc: Stmt.Outcomes;
    lab, xx: IR.Label;
    info, mu: IR.Var;
    returnSeen, exitSeen : BOOLEAN;
    proc: Procedure.T;
    catches := ARRAY[0..0] OF IR.TypeUID{0};
  BEGIN
    (* declare and initialize the info record *)
    info := IR.Declare_local (M3ID.NoID, Target.Address.size, Target.Address.align,
                              IR.Type.Addr, 0, in_memory := TRUE,
                              up_level := FALSE, f := IR.Never);

    IR.Load_nil ();
    IR.Store_addr (info, M3RT.EA_exception);

    (* capture the mutex expression *)
    Expr.Prep (p.mutex);
    Expr.Compile (p.mutex);
    mu := IR.Declare_local (M3ID.NoID, Target.Address.size,
                            Target.Address.align, IR.Type.Addr,
                            Type.GlobalUID (Mutex.T), in_memory := TRUE,
                            up_level := FALSE, f := IR.Never);
    IR.Store_addr (mu);

    (* acquire the lock *)
    Marker.SetLock (TRUE, mu, 0);
    Expr.NoteWrite (p.mutex);

    (* compile the body *)
    lab := IR.Next_label (4);
    IR.Set_label (lab, barrier := TRUE);
    IR.Start_try ();

    Marker.PushFinally (lab, lab+1, lab+2, info);
    Marker.SaveFrame ();
      oc := Stmt.Compile (p.body);
    Marker.PopFinally (returnSeen, exitSeen);

    (* jump over the exc handler *)
    IR.Jump (lab+2);
    IR.Set_label (lab+1, barrier := TRUE);
    IR.Landing_pad(lab+1, catches);
    IR.Store_addr (info);
    IR.Set_label (lab+2);

    (* release the lock *)
    Marker.SetLock (FALSE, mu, 0);
    Expr.NoteWrite (p.mutex);

    IF (exitSeen) THEN
      xx := IR.Next_label ();
      IR.Load_addr (info, M3RT.EA_exception, Target.Address.align);
      IR.Loophole (IR.Type.Addr, Target.Integer.cg_type );
      IR.Load_intt (Marker.Exit_exception);
      IR.If_compare (Target.Integer.cg_type, IR.Cmp.NE, xx, IR.Always);
      Marker.EmitExit ();
      IR.Set_label (xx);
    END;

    IF (returnSeen) THEN
      xx := IR.Next_label ();
      IR.Load_addr (info, M3RT.EA_exception, Target.Address.align);
      IR.Loophole (IR.Type.Addr, Target.Integer.cg_type );
      IR.Load_intt (Marker.Return_exception);
      IR.If_compare (Target.Integer.cg_type, IR.Cmp.NE, xx, IR.Always);
      Marker.EmitReturn (NIL, fromFinally := TRUE);
      IR.Set_label (xx);
    END;

    (* resume the exception *)
    IR.Load_addr (info, M3RT.EA_exception, Target.Address.align);
    IR.Load_nil ();
    IR.If_compare (IR.Type.Addr, IR.Cmp.EQ, lab+3, IR.Always);
    proc := RunTyme.LookUpProc (RunTyme.Hook.ResumeRaiseEx);
    Procedure.StartCall (proc);
    IR.Load_addr (info, 0, Target.Address.align);
    IR.Pop_param (IR.Type.Addr);
    Procedure.EmitCall (proc);

    IR.Gen_location (p.tail);
    IR.End_try ();
    IR.Set_label (lab+3, barrier := TRUE);
    RETURN oc;
  END Compile1;

PROCEDURE Compile2 (p: P): Stmt.Outcomes =
  VAR oc: Stmt.Outcomes;  frame: IR.Var;  l: IR.Label;
  BEGIN
    (* capture the mutex expression *)
    Expr.Prep (p.mutex);
    Expr.Compile (p.mutex);
    frame := IR.Declare_local (M3ID.NoID, M3RT.EF4_SIZE, Target.Address.align,
                               IR.Type.Struct, 0, in_memory := TRUE,
                               up_level := FALSE, f := IR.Never);
    IR.Store_addr (frame, M3RT.EF4_mutex);

    (* acquire the lock *)
    Marker.SetLock (TRUE, frame, M3RT.EF4_mutex);
    Expr.NoteWrite (p.mutex);

    (* set the barrier and link the frame *)
    l := IR.Next_label (2);
    IR.Set_label (l, barrier := TRUE);
    Marker.PushFrame (frame, M3RT.HandlerClass.Lock);

    (* compile the body *)
    Marker.PushLock (l, l+1, frame);
      oc := Stmt.Compile (p.body);
    Marker.Pop ();

    IR.Gen_location (p.tail);
    IR.Set_label (l+1, barrier := TRUE);

    IF (Stmt.Outcome.FallThrough IN oc) THEN
      (* unlink the frame and release the lock *)
      Marker.PopFrame (frame);
      Marker.SetLock (FALSE, frame, M3RT.EF4_mutex);
      Expr.NoteWrite (p.mutex);
    END;

    RETURN oc;
  END Compile2;

PROCEDURE GetOutcome (p: P): Stmt.Outcomes =
  BEGIN
    RETURN Stmt.GetOutcome (p.body);
  END GetOutcome;

BEGIN
END LockStmt.
