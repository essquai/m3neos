(* Copyright (C) 1994, Digital Equipment Corporation           *)
(* All rights reserved.                                        *)
(* See the file COPYRIGHT for a full description.              *)
(*                                                             *)
(* Last modified on Wed Oct 12 16:12:57 PDT 1994 by kalsow     *)

MODULE M3Backend;

IMPORT Msg, Utils;
IMPORT M3IR, M3IR_Asm, IRIO_BinWr, M3ID, Target;
IMPORT Text, Wr;

VAR
  log_wr   : Wr.T        := NIL;
  log_name : TEXT        := NIL;
VAR
  ir_wr    : Wr.T        := NIL;
  ir_name  : TEXT        := NIL;

(*
PROCEDURE TeeBinWr (cg: M3IR_Asm.Public; f_ir_name: TEXT): M3IR_Asm.Public =
  VAR result: M3IR_Asm.Public;
  BEGIN
    ir_name := f_ir_name;
    IF ir_name = NIL THEN RETURN cg END;
    IF Text.Equal (ir_name, "") THEN ir_name := NIL; RETURN cg END;
    ir_wr := Utils.OpenWriter (ir_name, fatal := FALSE);
    IF ir_wr = NIL THEN ir_name := NIL; RETURN cg END;
    result := IRIO_Tee.New (cg, IRIO_BinWr.New (ir_wr));
    RETURN result;
  END TeeBinWr;
*)
PROCEDURE BinWr (f_ir_name: TEXT): M3IR_Asm.Public =
  VAR result: M3IR_Asm.Public;
  BEGIN
    ir_name := f_ir_name;
    IF ir_name = NIL THEN RETURN NIL END;
    IF Text.Equal (ir_name, "") THEN ir_name := NIL; RETURN NIL END;
    ir_wr := Utils.OpenWriter (ir_name, fatal := FALSE);
    IF ir_wr = NIL THEN ir_name := NIL; RETURN NIL END;
    result := IRIO_BinWr.New (ir_wr);
    RETURN result;
  END BinWr;

(* EXPORTED: *)
PROCEDURE Open (<* UNUSED *> library (* or program *): TEXT;
                <* UNUSED *> source_base_name (* lacks .m3 or .i3 *): M3ID.T;
                <* UNUSED *> target_wr: Wr.T;
                target_name (* Has suffix. *): TEXT;
                f_ir_name (* Has suffix .ic or .mc *): TEXT;
                backend_mode: Target.M3BackendMode_t
               ): M3IR.T =
  BEGIN

    (* Binaryen backend *)
    IF backend_mode IN Target.BackendBinaryenSet THEN
      Msg.Info("M3Backend.Open Binaryen f_ir_name", f_ir_name, Wr.EOL);
      IF (Msg.level >= Msg.Level.Verbose) THEN
        log_name := target_name & "log";
        log_wr := Utils.OpenWriter (log_name, fatal := TRUE);
      END;
      RETURN BinWr (target_name);
      (* RETURN TeeBinWr (LLGen.New (log_wr,backend_mode), f_ir_name); *)
    END;

    (* Host backend *)
    IF backend_mode IN Target.BackendHostSet THEN
      Msg.Info("M3Backend.Open Host f_ir_name", f_ir_name, Wr.EOL);
      IF (Msg.level >= Msg.Level.Verbose) THEN
        log_name := target_name & "log";
        log_wr := Utils.OpenWriter (log_name, fatal := TRUE);
      END;
      RETURN BinWr (target_name);
      (* RETURN TeeBinWr (LLGen.New (log_wr,backend_mode), f_ir_name); *)
    END;

    (* default backend? *)
    Msg.Info("M3Backend.Open NIL f_ir_name", f_ir_name, Wr.EOL);
    RETURN NIL;
  END Open;

(* EXPORTED: *)
PROCEDURE Close (<*UNUSED*> cg: M3IR.T) =
  BEGIN
    Utils.CloseWriter (log_wr, log_name);
    log_wr := NIL;
    log_name := NIL;
    Utils.CloseWriter (ir_wr, ir_name);
    ir_wr := NIL;
    ir_name := NIL;
  END Close;

BEGIN
END M3Backend.
