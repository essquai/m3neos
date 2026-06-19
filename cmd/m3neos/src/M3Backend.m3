(* Copyright (C) 1994, Digital Equipment Corporation           *)
(* All rights reserved.                                        *)
(* See the file COPYRIGHT for a full description.              *)
(*                                                             *)
(* Last modified on Wed Oct 12 16:12:57 PDT 1994 by kalsow     *)

MODULE M3Backend;

IMPORT M3C;
IMPORT Msg, Utils;
IMPORT M3IR, M3IR_Asm, IRIO_BinWr, IRIO_Tee, M3ID, Target;
IMPORT Text, Thread, Wr;

VAR
  log_wr   : Wr.T        := NIL;
  log_name : TEXT        := NIL;
VAR
  ir_wr    : Wr.T        := NIL;
  ir_name  : TEXT        := NIL;

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
PROCEDURE Open (library (* or program *): TEXT;
                source_base_name (* lacks .m3 or .i3 *): M3ID.T;
                target_wr: Wr.T;
                target_name (* Has suffix. *): TEXT;
                f_ir_name (* Has suffix .ic or .mc *): TEXT;
                backend_mode: Target.M3BackendMode_t
               ): M3IR.T =
  VAR cgen: M3IR_Asm.Public := NIL;
  BEGIN

    (* C backend: *)
    IF backend_mode = Target.M3BackendMode_t.C THEN
      cgen := M3C.New (library, source_base_name, target_wr, target_name);
      (* cg.comment would not appear at the top because
       * earlier passes ignore it
       *)
      TRY
        Wr.PutText(target_wr, "// library:");
        Wr.PutText(target_wr, library);
        Wr.PutText(target_wr, "\n// source_base_name:");
        Wr.PutText(target_wr, M3ID.ToText(source_base_name));
        Wr.PutText(target_wr, "\n// target_name:");
        Wr.PutText(target_wr, target_name);
        Wr.PutText(target_wr, "\n");
        RETURN TeeBinWr (cgen, f_ir_name);
      EXCEPT
      | Wr.Failure (args) =>
          Msg.FatalError (args, "unable to write IR file: ", f_ir_name);
      | Thread.Alerted =>
          Msg.FatalError (NIL, "unable to write IR file: ", f_ir_name);
      END;
    END;

    (* Binaryen backend *)
    IF backend_mode IN Target.BackendBinaryenSet THEN
      IF (Msg.level >= Msg.Level.Verbose) THEN
        log_name := target_name & "log";
        log_wr := Utils.OpenWriter (log_name, fatal := TRUE);
      END;
      RETURN BinWr (target_name);
    END;

    (* Llvm backend *)
    IF backend_mode IN Target.BackendLlvmSet THEN
      IF (Msg.level >= Msg.Level.Verbose) THEN
        log_name := target_name & "log";
        log_wr := Utils.OpenWriter (log_name, fatal := TRUE);
      END;
      RETURN BinWr (target_name);
    END;

    (* There is no default *)
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
