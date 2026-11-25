UNSAFE MODULE Main;

(* ms15: an exception that nothing handles, in a worker thread (register 66).

   M3 exceptions are frame chains (RTExFrame), one chain per thread
   (RTThread.GetCurrentHandlers).  With no handler frame on the worker's
   chain, a failed ASSERT goes Raise -> InvokeBackstop -> Crash, the same
   route as the negative control of ms13 on the main thread, and never
   unwinds through WThread.Exec.  This program checks that on the worker the
   process really ends there.

   Usage (one mode word on the command line; default "worker"):
     ms15 ok      the worker returns normally; Join returns its result
                  (control for Fork and Join).  Exit status 0.
     ms15 main    the main thread fails the assertion (baseline, as ms13's
                  negative control).  Exit status non-zero.
     ms15 worker  the worker fails the assertion.  Expected: the message
                  "<*ASSERT*> failed: f = 605", a stack dump, a non-zero
                  exit status, and NO line "join returned" (the process must
                  not outlive the failure, and must not hang in Join).
                  If "UNEXPECTED" is printed, the crash did not end the
                  process.
   Run it under a timeout, and record the exit status of each mode. *)

IMPORT RTArgs, RTIO, Text, Thread;

TYPE Mode = {Ok, Worker, Main};

VAR mode := Mode.Worker;

PROCEDURE Say (t: TEXT) =
  BEGIN
    RTIO.PutText (t);
    RTIO.PutText ("\n");
    RTIO.Flush ();
  END Say;

(* f is 604; the assertion fails.  f is computed so that nothing folds it *)
PROCEDURE Check () =
  VAR f := 0;
  BEGIN
    FOR i := 1 TO 4 DO f := f + 151 END;
    <* ASSERT f = 605 *>
  END Check;

TYPE
  W = Thread.Closure OBJECT
  OVERRIDES
    apply := Apply;
  END;

PROCEDURE Apply (<* UNUSED *> self: W): REFANY =
  VAR r := NEW (REF INTEGER);
  BEGIN
    Say ("ms15: worker running");
    IF mode = Mode.Worker THEN Check () END;
    Say ("ms15: worker returning");
    r^ := 42;
    RETURN r;
  END Apply;

VAR
  t   : Thread.T;
  res : REFANY;

BEGIN
  FOR i := 0 TO RTArgs.ArgC () - 1 DO
    WITH a = RTArgs.GetArg (i) DO
      IF    Text.Equal (a, "ok")   THEN mode := Mode.Ok
      ELSIF Text.Equal (a, "main") THEN mode := Mode.Main
      ELSIF Text.Equal (a, "worker") THEN mode := Mode.Worker
      END;
    END;
  END;

  CASE mode OF
  | Mode.Ok     => Say ("ms15: mode ok")
  | Mode.Worker => Say ("ms15: mode worker")
  | Mode.Main   => Say ("ms15: mode main")
  END;

  IF mode = Mode.Main THEN Check () END;

  t   := Thread.Fork (NEW (W));
  res := Thread.Join (t);
  Say ("ms15: join returned");

  IF mode = Mode.Worker THEN
    Say ("ms15: UNEXPECTED: the process survived the worker's failed assertion");
  ELSE
    <* ASSERT res # NIL AND NARROW (res, REF INTEGER)^ = 42 *>
    Say ("ms15: ok");
  END;
END Main.
