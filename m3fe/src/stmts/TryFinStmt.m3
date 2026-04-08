(* Copyright (C) 1992, Digital Equipment Corporation           *)
(* All rights reserved.                                        *)
(* See the file COPYRIGHT for a full description.              *)
(*                                                             *)
(* File: TryFinStmt.m3                                         *)
(* Last modified on Fri May 19 07:50:09 PDT 1995 by kalsow     *)
(*      modified on Thu Dec  5 17:19:13 PST 1991 by muller     *)

MODULE TryFinStmt;

IMPORT M3ID, IR, Token, Scanner, Stmt, StmtRep, Marker, Target, Type, Addr;
IMPORT RunTyme, Procedure, ProcBody, M3RT, Scope, Fmt, Host, TryStmt, Module;
IMPORT Jmpbufs;
FROM Stmt IMPORT Outcome;

TYPE
  P = Stmt.T OBJECT
        body     : Stmt.T;
        finally  : Stmt.T;
        forigin  : INTEGER;
        viaProc  : BOOLEAN;
        scope    : Scope.T;
        handler  : HandlerProc;
        jmpbufs  : Jmpbufs.Try;
      OVERRIDES
        check       := Check;
        compile     := Compile;
        outcomes    := GetOutcome;
      END;

TYPE
  HandlerProc = ProcBody.T OBJECT
    self: P;
    activation: IR.Var;
    jmpbufs : Jmpbufs.Proc;
  OVERRIDES
    gen_decl := EmitDecl;
    gen_body := EmitBody;
  END;

VAR
  last_name : INTEGER := 0;
  next_uid  : INTEGER := 0;

PROCEDURE Parse (body: Stmt.T;  ): Stmt.T =
  TYPE TK = Token.T;
  VAR p := NEW (P);
  BEGIN
    StmtRep.Init (p);
    p.body := body;
    Scanner.Match (TK.tFINALLY);
    p.forigin := Scanner.offset;
    IF Target.Has_stack_walker THEN
      p.viaProc := FALSE;
      p.scope   := NIL;
      p.finally := Stmt.Parse ();
    ELSE
      p.handler := NEW (HandlerProc, self := p);
      ProcBody.Push (p.handler);
      p.scope := Scope.PushNew (TRUE, M3ID.NoID);
      p.finally := Stmt.Parse ();
      Scope.PopNew ();
      ProcBody.Pop ();
    END;
    Scanner.Match (TK.tEND);
    RETURN p;
  END Parse;

PROCEDURE Check (p: P;  VAR cs: Stmt.CheckState) =
  VAR zz: Scope.T;  oc: Stmt.Outcomes;  name: INTEGER;
  BEGIN
    Jmpbufs.CheckTry (cs.jmpbufs, p.jmpbufs);
    Marker.PushFinally (IR.No_label, IR.No_label, IR.No_label, NIL);
    Stmt.TypeCheck (p.body, cs);
    Marker.Pop ();
    TryStmt.PushHandler (NIL, 0, FALSE);
    IF Target.Has_stack_walker THEN
      Stmt.TypeCheck (p.finally, cs);
    ELSE
      oc := Stmt.GetOutcome (p.finally);
      IF (Stmt.Outcome.Exits IN oc) OR (Stmt.Outcome.Returns IN oc) THEN
        p.viaProc := FALSE;
        Stmt.TypeCheck (p.finally, cs);
      ELSE
        p.viaProc := TRUE;
        name := p.forigin MOD 10000;
        p.handler.name := HandlerName (name);
        IF (name = last_name) THEN
          INC (next_uid);
          p.handler.name := p.handler.name & "_" & Fmt.Int (next_uid);
        ELSE
          last_name := name;
          next_uid := 0;
        END;
        zz := Scope.Push (p.scope);
          p.handler.jmpbufs := Jmpbufs.CheckProcPush (cs.jmpbufs,
                                                      M3ID.Add (p.handler.name));
          Scope.TypeCheck (p.scope, cs);
          Stmt.TypeCheck (p.finally, cs);
          Jmpbufs.CheckProcPop (cs.jmpbufs, p.handler.jmpbufs);
        Scope.Pop (zz);
      END;
    END;
    TryStmt.PopHandler ();
  END Check;

PROCEDURE HandlerName (uid: INTEGER): TEXT =
  CONST Insert = ARRAY BOOLEAN OF TEXT { "_M3_LINE_", "_I3_LINE_" };
  BEGIN
    RETURN M3ID.ToText (Module.Name (NIL))
           & Insert [Module.IsInterface ()]
           & Fmt.Int (uid);
  END HandlerName;

PROCEDURE Compile (p: P): Stmt.Outcomes =
  BEGIN
    IF Target.Has_stack_walker THEN RETURN Compile1 (p);
    ELSIF p.viaProc            THEN RETURN Compile2 (p);
    ELSE                            RETURN Compile3 (p);
    END;
  END Compile;

PROCEDURE Compile1 (p: P): Stmt.Outcomes =
  VAR
    oc, xc, o: Stmt.Outcomes;
    lab, xx: IR.Label;
    info: IR.Var;
    proc: Procedure.T;
    returnSeen, exitSeen : BOOLEAN;
    catches := ARRAY[0..0] OF IR.TypeUID{0};
  BEGIN
    (* declare and initialize the info record *)
    info := IR.Declare_local (M3ID.NoID, Target.Address.size, Target.Address.align,
                              IR.Type.Addr, 0, in_memory := TRUE,
                              up_level := FALSE, f := IR.Never);
    IR.Load_nil ();
    IR.Store_addr (info, M3RT.EA_exception);

    (* compile the body *)
    lab := IR.Next_label (4);
    IR.Set_label (lab, barrier := TRUE);
    IR.Start_try ();

    Marker.PushFinally (lab, lab+1, lab+2, info);
    Marker.SaveFrame ();
      oc := Stmt.Compile (p.body);
    Marker.PopFinally (returnSeen, exitSeen);

    IR.Jump (lab+2);
    IR.Set_label (lab+1);
    IR.Landing_pad(lab+1, catches);
    IR.Store_addr (info);
    IR.Set_label (lab+2);

    (* set the "Compiler.ThisException()" globals *)
    TryStmt.PushHandler (info, 0, direct := FALSE);

    (* compile the handler *)
    Scanner.offset := p.forigin;
    IR.Gen_location (p.forigin);
      xc := Stmt.Compile (p.finally);

    IF (Outcome.FallThrough IN xc) THEN
      (* exceptional outcome? *)
      IR.Load_addr (info, M3RT.EA_exception, Target.Address.align);
      IR.Load_nil ();
      IR.If_compare (IR.Type.Addr, IR.Cmp.EQ, lab+3, IR.Always);

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
      proc := RunTyme.LookUpProc (RunTyme.Hook.ResumeRaiseEx);
      Procedure.StartCall (proc);
      IR.Load_addr (info, 0, Target.Address.align);
      IR.Pop_param (IR.Type.Addr);
      Procedure.EmitCall (proc);
      IR.Set_label (lab+3, barrier := TRUE);
    END;

    (* restore the "Compiler.ThisException()" globals *)
    TryStmt.PopHandler ();
    IR.End_try ();

    o := Stmt.Outcomes {};
    IF Outcome.FallThrough IN xc THEN o := oc END;
    IF Outcome.Exits IN xc   THEN o := o + Stmt.Outcomes {Outcome.Exits} END;
    IF Outcome.Returns IN xc THEN o := o + Stmt.Outcomes {Outcome.Returns} END;
    RETURN o;
  END Compile1;

PROCEDURE Compile2 (p: P): Stmt.Outcomes =
  VAR
    oc, xc, o: Stmt.Outcomes;
    lab: IR.Label;
    frame: IR.Var;
  BEGIN
    <*ASSERT p.viaProc*>

    (* declare and initialize the info record *)
    frame := IR.Declare_local (M3ID.NoID, M3RT.EF2_SIZE, Target.Address.align,
                               IR.Type.Struct, 0, in_memory := TRUE,
                               up_level := FALSE, f := IR.Never);
    IR.Load_procedure (p.handler.cg_proc);
    IR.Store_addr (frame, M3RT.EF2_handler);
    IR.Load_static_link (p.handler.cg_proc);
    IR.Store_addr (frame, M3RT.EF2_frame);

    (* compile the body *)
    lab := IR.Next_label (2);
    IR.Set_label (lab, barrier := TRUE);
    Marker.PushFrame (frame, M3RT.HandlerClass.FinallyProc);
    Marker.PushFinallyProc (lab, lab+1, frame, p.handler.cg_proc, p.handler.level);
      oc := Stmt.Compile (p.body);
    Marker.Pop ();
    IF (Outcome.FallThrough IN oc) THEN
      Marker.PopFrame (frame);
      IR.Start_call_direct (p.handler.cg_proc, p.handler.level, IR.Type.Void);
      (* Shouldn't we pass the activation parameter here?
         What value do we pass? *)
      IR.Call_direct (p.handler.cg_proc, IR.Type.Void);
    END;
    IR.Set_label (lab+1, barrier := TRUE);

    (* set the "Compiler.ThisException()" globals *)
    TryStmt.PushHandler (p.handler.activation, 0, direct := FALSE);

    Scanner.offset := p.forigin;
    IR.Gen_location (p.forigin);
    IF (Host.inline_nested_procs) THEN
      IR.Begin_procedure (p.handler.cg_proc);
      Jmpbufs.CompileProcAllocateJmpbufs (p.handler.jmpbufs);
      xc := Stmt.Compile (p.finally);
      IR.Exit_proc (IR.Type.Void);
      IR.End_procedure (p.handler.cg_proc);
    ELSE
      IR.Note_procedure_origin (p.handler.cg_proc);
      xc := Stmt.GetOutcome (p.finally);
    END;

    (* restore the "Compiler.ThisException()" globals *)
    TryStmt.PopHandler ();

    o := Stmt.Outcomes {};
    IF Outcome.FallThrough IN xc THEN o := oc END;
    IF Outcome.Exits IN xc   THEN o := o + Stmt.Outcomes {Outcome.Exits} END;
    IF Outcome.Returns IN xc THEN o := o + Stmt.Outcomes {Outcome.Returns} END;
    RETURN o;
  END Compile2;

PROCEDURE EmitDecl (x: HandlerProc) =
  VAR p := x.self;  par: IR.Proc := NIL;
  BEGIN
    IF (p.viaProc) THEN
      IF (x.parent # NIL) THEN par := x.parent.cg_proc; END;
      x.cg_proc := IR.Declare_procedure (M3ID.Add (x.name), 1, IR.Type.Void,
                                         x.level, Target.DefaultCall,
                                         exported := FALSE, parent := par);
      x.activation := IR.Declare_param (M3ID.NoID, Target.Address.size,
                                        Target.Address.align, IR.Type.Addr,
                                        Type.GlobalUID (Addr.T),
                                        in_memory := FALSE, up_level := FALSE,
                                        f := IR.Always);
    END;
  END EmitDecl;

PROCEDURE EmitBody (x: HandlerProc) =
  VAR p := x.self;
  BEGIN
    IF (p.viaProc) AND (NOT Host.inline_nested_procs) THEN

      (* set the "Compiler.ThisException()" globals *)
      TryStmt.PushHandler (x.activation, 0, direct := FALSE);

      (* generate the actual procedure *)
      Scanner.offset := p.forigin;
      IR.Gen_location (p.forigin);
      IR.Begin_procedure (x.cg_proc);
      Jmpbufs.CompileProcAllocateJmpbufs (x.jmpbufs);
      EVAL Stmt.Compile (p.finally);
      IR.Exit_proc (IR.Type.Void);
      IR.End_procedure (x.cg_proc);

      (* restore the "Compiler.ThisException()" globals *)
      TryStmt.PopHandler ();

    END;
  END EmitBody;

PROCEDURE Compile3 (p: P): Stmt.Outcomes =
  VAR
    oc, xc, o: Stmt.Outcomes;
    lab, xx: IR.Label;
    frame: IR.Var;
    returnSeen, exitSeen: BOOLEAN;
    proc: Procedure.T;
  BEGIN
    <* ASSERT NOT p.viaProc *>

    (* declare and initialize the info record *)
    frame := IR.Declare_local (M3ID.NoID, M3RT.EF1_SIZE, Target.Address.align,
                               IR.Type.Struct, 0, in_memory := TRUE,
                               up_level := FALSE, f := IR.Never);
    IR.Load_nil ();
    IR.Store_addr (frame, M3RT.EF1_info + M3RT.EA_exception);

    lab := IR.Next_label (3);
    IR.Set_label (lab, barrier := TRUE);
    Marker.PushFrame (frame, M3RT.HandlerClass.Finally);
    Marker.CaptureState (frame, Jmpbufs.CompileTryGetJmpbuf (p.jmpbufs), lab+1);

    (* compile the body *)
    Marker.PushFinally (lab, lab+1, IR.No_label, frame);
      oc := Stmt.Compile (p.body);
    Marker.PopFinally (returnSeen, exitSeen);
    IF (Outcome.FallThrough IN oc) THEN
      Marker.PopFrame (frame);
    END;
    IR.Set_label (lab+1, barrier := TRUE);

    (* set the "Compiler.ThisException()" globals *)
    TryStmt.PushHandler (frame, M3RT.EF1_info, direct := TRUE);

    (* compile the handler *)
    Scanner.offset := p.forigin;
    IR.Gen_location (p.forigin);
    xc := Stmt.Compile (p.finally);

    IF (Outcome.FallThrough IN xc) THEN
      (* generate the bizzare end-tests *)

      (* exceptional outcome? *)
      IR.Load_addr
        (frame, M3RT.EF1_info + M3RT.EA_exception, Target.Address.align);
      IR.Load_nil ();
      IR.If_compare (IR.Type.Addr, IR.Cmp.EQ, lab+2, IR.Always);

      IF (exitSeen) THEN
        xx := IR.Next_label ();
        IR.Load_int (Target.Integer.cg_type,
                     frame, M3RT.EF1_info + M3RT.EA_exception);
        IR.Load_intt (Marker.Exit_exception);
        IR.If_compare (Target.Integer.cg_type, IR.Cmp.NE, xx, IR.Always);
        Marker.EmitExit ();
        IR.Set_label (xx);
      END;

      IF (returnSeen) THEN
        xx := IR.Next_label ();
        IR.Load_int (Target.Integer.cg_type,
                     frame, M3RT.EF1_info + M3RT.EA_exception);
        IR.Load_intt (Marker.Return_exception);
        IR.If_compare (Target.Integer.cg_type, IR.Cmp.NE, xx, IR.Always);
        Marker.EmitReturn (NIL, fromFinally := TRUE);
        IR.Set_label (xx);
      END;

      (* ELSE, a real exception is being raised => resume it *)
      proc := RunTyme.LookUpProc (RunTyme.Hook.ResumeRaiseEx);
      Procedure.StartCall (proc);
      IR.Load_addr_of (frame, M3RT.EF1_info, Target.Address.align);
      IR.Pop_param (IR.Type.Addr);
      Procedure.EmitCall (proc);

      IR.Set_label (lab+2, barrier := TRUE);
    END;

    (* restore the "Compiler.ThisException()" globals *)
    TryStmt.PopHandler ();

    o := Stmt.Outcomes {};
    IF Outcome.FallThrough IN xc THEN o := oc END;
    IF Outcome.Exits IN xc   THEN o := o + Stmt.Outcomes {Outcome.Exits} END;
    IF Outcome.Returns IN xc THEN o := o + Stmt.Outcomes {Outcome.Returns} END;
    RETURN o;
  END Compile3;

PROCEDURE GetOutcome (p: P): Stmt.Outcomes =
  VAR oc, xc, o: Stmt.Outcomes;
  BEGIN
    oc := Stmt.GetOutcome (p.body);
    xc := Stmt.GetOutcome (p.finally);
    o := Stmt.Outcomes {};
    IF Outcome.FallThrough IN xc THEN o := oc END;
    IF Outcome.Exits IN xc THEN o := o + Stmt.Outcomes {Outcome.Exits} END;
    IF Outcome.Returns IN xc THEN o := o + Stmt.Outcomes {Outcome.Returns} END;
    RETURN o;
  END GetOutcome;

BEGIN
END TryFinStmt.
