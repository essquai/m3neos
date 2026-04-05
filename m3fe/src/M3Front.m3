(* Copyright (C) 1994, Digital Equipment Corporation           *)
(* All rights reserved.                                        *)
(* See the file COPYRIGHT for a full description.              *)
(*                                                             *)
(* File: M3Front.m3                                            *)
(* Last modified on Tue Dec  6 08:16:20 PST 1994 by kalsow     *)
(*      modified on Sun Jan 21 06:56:46 1990 by muller         *)

MODULE M3Front;

IMPORT Wr, Fmt, Time, TextWr, Thread(** , RTCollector, RTCollectorSRC **);
IMPORT Host, M3Header, Error;
IMPORT Target;


VAR mu         : MUTEX    := NEW (MUTEX);

PROCEDURE ParseImports (READONLY input : SourceFile;
                                 env   : Environment): IDList =
  VAR ids: IDList := NIL;
  BEGIN
    LOCK mu DO
      (* make the arguments globally visible *)
      Host.env      := env;
      Host.source   := input.contents;
      Host.filename := input.name;

      ids := M3Header.Parse ();
      RETURN ids;
    END;
  END ParseImports;

PROCEDURE Compile (READONLY input    : SourceFile;
                            env      : Environment;
                   READONLY options  : ARRAY OF TEXT): BOOLEAN =
  VAR ok: BOOLEAN;  start: Time.T;
  BEGIN
    LOCK mu DO
      start := Time.Now ();

      (* make the arguments globally visible *)
      Host.env      := env;
      Host.source   := input.contents;
      Host.filename := input.name;

      IF NOT Host.Initialize (options) THEN RETURN FALSE; END;

      IF NOT Host.stack_walker THEN
        (* command line override... *)
        Target.Has_stack_walker := FALSE;
      END;

      Reset ();
      DoCompile ();
      ok := Finalize ();

      IF (Host.report_stats) THEN DumpStats (start, Time.Now ()); END;
    END;
    RETURN ok;
  END Compile;

PROCEDURE Initialize () =
  BEGIN
  END Initialize;

PROCEDURE Reset () =
  BEGIN
  END Reset;


PROCEDURE DoCompile () =
  BEGIN


    StartPhase ("parsing");
    (* Drive parsing like in tkfe.m3 *)
    IF Failed () THEN RETURN END;

    StartPhase ("type checking");
    IF Failed () THEN RETURN END;

    StartPhase ("emitting code");
    (* M3IR write *)
    IF Failed () THEN RETURN END;
  END DoCompile;

PROCEDURE StartPhase (tag: TEXT) =
  BEGIN
    IF (Host.verbose) THEN
      Host.env.report_error (NIL, 0, tag & "...");
    END;
  END StartPhase;

PROCEDURE Failed (): BOOLEAN =
  VAR errs, warns: INTEGER;
  BEGIN
    Error.Count (errs, warns);
    RETURN (errs > 0);
  END Failed;

PROCEDURE DumpStats (start, stop: Time.T) =
  <*FATAL Wr.Failure, Thread.Alerted*>
  VAR
    wr      := TextWr.New ();
    elapsed := MAX (stop - start, 1.0d-6);
    lines   : INTEGER := 1000;
    files   : INTEGER := 1;
    speed   := FLOAT (lines, LONGREAL) / elapsed;
  BEGIN
    Wr.PutText (wr, "  ");
    Wr.PutText (wr, Fmt.Int (lines));
    Wr.PutText (wr, " lines (");
    Wr.PutText (wr, Fmt.Int (files));
    Wr.PutText (wr, " files) scanned, ");
    Wr.PutText (wr, Fmt.LongReal (elapsed, Fmt.Style.Fix, 2));
    Wr.PutText (wr, " seconds, ");
    Wr.PutText (wr, Fmt.LongReal (speed, Fmt.Style.Fix, 1));
    Wr.PutText (wr, " lines / second.");
    Host.env.report_error (NIL, 0, TextWr.ToText (wr));
  END DumpStats;

PROCEDURE Finalize (): BOOLEAN =
  <*FATAL Wr.Failure, Thread.Alerted*>
  VAR errs, warns: INTEGER;  wr: TextWr.T;
  BEGIN

    Error.Count (errs, warns);
    IF (errs + warns > 0) THEN
      wr := TextWr.New ();
      IF (errs > 0) THEN
        Wr.PutText (wr, Fmt.Int (errs));
        Wr.PutText (wr, " error");
        IF (errs > 1) THEN Wr.PutText (wr, "s") END;
      END;
      IF (warns > 0) THEN
        IF (errs > 0) THEN Wr.PutText (wr, " and ") END;
        Wr.PutText (wr, Fmt.Int (warns));
        Wr.PutText (wr, " warning");
        IF (warns > 1) THEN Wr.PutText (wr, "s") END;
      END;
      Wr.PutText (wr, " encountered");
      Host.env.report_error (NIL, 0, TextWr.ToText (wr));
    END;

    RETURN (errs <= 0);
  END Finalize;

BEGIN
  Initialize();
END M3Front.
