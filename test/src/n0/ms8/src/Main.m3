UNSAFE MODULE Main;

IMPORT Loque;
IMPORT Thread;
IMPORT WThread;
IMPORT RTCollector;
IMPORT Word;

VAR loque : Loque.T;

(* MS8 Test Subject *)
TYPE 
  Stage = {creat, start,
           pause, edge,
           pauseTwo, edgeTwo,
           pauseTre, edgeTre,
           finish};

CONST
  stageName = ARRAY Stage OF TEXT {
    "creat", "start",
    "pause", "edge",
    "pauseTwo", "edgeTwo",
    "pauseTre", "edgeTre",
    "finish"
  };
  NUM_GCS = 3;
  PAGE_SIZE = 65536;
  LARGE_SIZE = 40000;

TYPE
  Routine = PROCEDURE(ms8 : MS8);

  MS8 = Thread.Closure OBJECT
    thread  : Thread.T;
    routine : Routine;
    num     : INTEGER;
    stage   : Stage;
    syn     : MUTEX;
    cond    : Thread.Condition;
  METHODS
    advance(s : Stage) := Advance;
    wait(s : Stage):= Wait;
  OVERRIDES
    apply := Apply;
  END;

  Byte = [0..255];

  Page = RECORD
    data : ARRAY [1..PAGE_SIZE] OF Byte;
  END;
  Large = ARRAY [1..LARGE_SIZE] OF Byte;
  R = REF Large;

VAR ms8Num : INTEGER := 1;

PROCEDURE NewMS8(rtn : Routine) : MS8 =
  VAR ms8 := NEW(MS8);
  BEGIN
    ms8.num := ms8Num; INC(ms8Num);
    ms8.routine := rtn;
    ms8.stage := Stage.creat;
    ms8.syn  := NEW(MUTEX);
    ms8.cond := NEW(Thread.Condition);
    RETURN ms8;
  END NewMS8;

PROCEDURE Apply(ms8: MS8) : REFANY =
  BEGIN
    ms8.routine(ms8);
    RETURN NIL;
  END Apply;

PROCEDURE Advance(ms8: MS8; next : Stage) =
  BEGIN
    <* ASSERT next > ms8.stage *>
    IF next = Stage.start THEN
      ms8.stage := next;
      ms8.thread := Thread.Fork(ms8);
    ELSE
      (* running, actually advance*)
      Thread.Acquire(ms8.syn);
      ms8.stage := next;
      Thread.Release(ms8.syn);
      Thread.Signal(ms8.cond);
    END;
  END Advance;

PROCEDURE Wait(ms8: MS8; next : Stage) =
  BEGIN
    <* ASSERT next >= ms8.stage *>
    Thread.Acquire(ms8.syn);
    WHILE ms8.stage < next DO Thread.Wait(ms8.syn, ms8.cond); END;
    Thread.Release(ms8.syn);
 END Wait;

(* MS8 Test Cases *)
PROCEDURE nullTest(ms8: MS8) =
  VAR spinner : INTEGER := 0; s := Stage.pause;
  BEGIN
    loque.write("    nullTest started", ms8, ms8.num);

    FOR cycle := 1 TO 3 DO
      (* pre-pause action *)

      (* pause cycle*)
      ms8.wait(s);
      loque.write("    nullTest " & stageName[s], NIL, ms8.num);

      (* edge cycle *)
      INC(s);
      ms8.wait(s);
      loque.write("    nullTest " & stageName[s], NIL, ms8.num);

      INC(s);
      WHILE ms8.stage < s DO
       INC(spinner);
      END;

      (* post-edge action *)
      loque.write("    nullTest " & stageName[s], NIL, -1, spinner);

    END;

    ms8.wait(Stage.finish);
    loque.write("    nullTest finish", ms8, ms8.num);
    loque.write("    nullTest exiting", ms8, ms8.num);    
  END nullTest;


PROCEDURE initR(r : R; v : Byte) =
  VAR e : Byte := 255 - v;
  BEGIN
    FOR i := 1 TO 64 DO
      r[i] := v;
    END;
    FOR i := 65 TO LARGE_SIZE DO
      r[i] := e;
    END;
  END initR;

PROCEDURE corruptR(r : R; v : Byte) : BOOLEAN =
  VAR e : Byte := 255 - v;
  BEGIN
    FOR i := 1 TO 64 DO
      IF r[i] # v THEN RETURN TRUE; END;
    END;
    FOR i := 65 TO LARGE_SIZE DO
      IF r[i] # e THEN RETURN TRUE; END;
    END;
    RETURN FALSE;
  END corruptR;

PROCEDURE recrInit(VAR a : ARRAY [1..NUM_GCS] OF REF recR; num : INTEGER;) =
  BEGIN
    FOR n := 1 TO NUM_GCS DO
      a[n] := NEW(REF recR);
      a[n].r := NEW(R);
      initR(a[n].r, (num*16 + n) MOD 256);
    END;
  END recrInit;

PROCEDURE recrLog(VAR a : ARRAY [1..NUM_GCS] OF REF recR) =
  BEGIN
    FOR n := 1 TO NUM_GCS DO
      loque.write("      recr", LOOPHOLE(a[n],ROOT), n);
      loque.write("      ++recr", LOOPHOLE(a[n].r,ROOT), n);
    END;
  END recrLog;


PROCEDURE recrCheck(VAR a : ARRAY [1..NUM_GCS] OF REF recR; num : INTEGER) =
  BEGIN
    FOR n := 1 TO NUM_GCS DO
      <* ASSERT NOT corruptR(a[n].r, (num*16 + n) MOD 256) *>
    END;
  END recrCheck;

TYPE
  recR = RECORD
    a : INTEGER;
    b : INTEGER;
    c : INTEGER;
    d : INTEGER;
    large : Large;
    r : R;
  END;
PROCEDURE recrTest(ms8: MS8) =
  VAR
    spinner : INTEGER := 0;
    s := Stage.pause;
    a : ARRAY [1..NUM_GCS] OF REF recR;
  BEGIN
    loque.write("    recrTest started", ms8, ms8.num);
    recrInit(a, ms8.num);
    scrubStack();

    FOR cycle := 1 TO 3 DO
      (* pre-pause action *)
      recrLog(a);
      scrubStack();

      (* pause cycle*)
      ms8.wait(s);
      loque.write("    recrTest " & stageName[s], NIL, ms8.num);
      recrCheck(a, ms8.num);
      scrubStack();

      (* edge cycle *)
      INC(s);
      ms8.wait(s);
      loque.write("    recrTest " & stageName[s], NIL, ms8.num);

      INC(s);
      WHILE ms8.stage < s DO
       INC(spinner);
      END;

      (* post-edge action *)
      loque.write("    recrTest " & stageName[s], NIL, -1, spinner);
      recrCheck(a, ms8.num);
      scrubStack();

    END;


    ms8.wait(Stage.finish);
    loque.write("    recrTest finish", ms8, ms8.num);

    loque.write("    recrTest exiting", ms8, ms8.num);    
  END recrTest;


TYPE
  objR = BRANDED "ms8 object" OBJECT
    a : INTEGER;
    b : INTEGER;
    c : INTEGER;
    d : INTEGER;
    large : Large;
    r : R;
  END;


PROCEDURE objrInit(VAR a : ARRAY [1..NUM_GCS] OF objR; num : INTEGER;) =
  BEGIN
    FOR n := 1 TO NUM_GCS DO
      a[n] := NEW(objR);
      a[n].r := NEW(R);
      initR(a[n].r, (num*16 + n) MOD 256);
    END;
  END objrInit;

PROCEDURE objrLog(VAR a : ARRAY [1..NUM_GCS] OF objR) =
  BEGIN
    FOR n := 1 TO NUM_GCS DO
      loque.write("      objr", LOOPHOLE(a[n],ROOT), n);
      loque.write("      ++objr", LOOPHOLE(a[n].r,ROOT), n);
    END;
  END objrLog;

PROCEDURE objrCheck(VAR a : ARRAY [1..NUM_GCS] OF objR; num : INTEGER) =
  BEGIN
    FOR n := 1 TO NUM_GCS DO
      <* ASSERT NOT corruptR(a[n].r, (num*16 + n) MOD 256) *>
    END;
  END objrCheck;


PROCEDURE objrTest(ms8: MS8) =
  VAR
    spinner : INTEGER := 0;
    s := Stage.pause;
    a : ARRAY [1..NUM_GCS] OF objR;
  BEGIN
    loque.write("    objrTest started", ms8, ms8.num);
    objrInit(a, ms8.num);
    scrubStack();

    FOR cycle := 1 TO 3 DO
      (* pre-pause action *)
      objrLog(a);
      scrubStack();

      (* pause cycle*)
      ms8.wait(s);
      loque.write("    objrTest " & stageName[s], NIL, ms8.num);
      objrCheck(a, ms8.num);
      scrubStack();

      (* edge cycle *)
      INC(s);
      ms8.wait(s);
      loque.write("    objrTest " & stageName[s], NIL, ms8.num);

      INC(s);
      WHILE ms8.stage < s DO
       INC(spinner);
      END;

      (* post-edge action *)
      loque.write("    objrTest " & stageName[s], NIL, -1, spinner);
      objrCheck(a, ms8.num);
      scrubStack();
    END;

    ms8.wait(Stage.finish);
    loque.write("    objrTest finish", ms8, ms8.num);

    loque.write("    objrTest exiting", ms8, ms8.num);    
  END objrTest;

VAR mov : ARRAY [1..NUM_GCS] OF objR;

PROCEDURE logMov(v : Byte) =
  VAR b : INTEGER;
  BEGIN
    FOR i := 1 TO NUM_GCS DO
      IF mov[i] = NIL THEN RETURN; END;
      b := Word.Not(LOOPHOLE(mov[i], INTEGER));
      loque.write("++mov", NIL, i, b);
      IF mov[i].r = NIL THEN RETURN; END;
      b := Word.Not(LOOPHOLE(mov[i].r, INTEGER));
      loque.write("++++mov", NIL, i, b);
      <* ASSERT NOT corruptR(mov[i].r, v) *>
      scrubStack();
    END;
  END logMov;

PROCEDURE pinMov(VAR p : ARRAY [1..NUM_GCS] OF objR) =
  BEGIN
    FOR i := 1 TO NUM_GCS DO
      IF i = 2 THEN p[i] := mov[i]; END;
    END;
  END pinMov;

PROCEDURE nilMov(VAR p : ARRAY [1..NUM_GCS] OF objR) =
  BEGIN
    FOR i := 1 TO NUM_GCS DO
      p[i] := NIL;
    END;
  END nilMov;

PROCEDURE scrubStack() =
  VAR a : ARRAY [1..4096] OF Byte;
  BEGIN
    FOR i := FIRST(a) TO LAST(a) DO
      a[i] := 0;
    END;
  END scrubStack;

PROCEDURE movTest(ms8: MS8) =
  VAR
  BEGIN
    loque.write("    movTest started", ms8, ms8.num);
    FOR n := 1 TO NUM_GCS DO
      mov[n] := NEW(objR);
      mov[n].r := NEW(R);
      initR(mov[n].r, ms8.num);
      <* ASSERT NOT corruptR(mov[n].r, ms8.num) *>
    END;

    loque.write("    movTest exiting", ms8, ms8.num);
  END movTest;


VAR
  ctrl : ARRAY [1..NUM_GCS] OF objR;
  tail : objR;


PROCEDURE logCtrl(v : Byte) =
  VAR b : INTEGER;
  BEGIN
    FOR i := 1 TO NUM_GCS DO
      IF ctrl[i] = NIL THEN RETURN; END;
      b := Word.Not(LOOPHOLE(ctrl[i], INTEGER));
      loque.write("++ctl", NIL, i, b);
      IF ctrl[i].r = NIL THEN RETURN; END;
      b := Word.Not(LOOPHOLE(ctrl[i].r, INTEGER));
      loque.write("++++ctl", NIL, i, b);
      <* ASSERT NOT corruptR(ctrl[i].r, v) *>
      scrubStack();
    END;
    b := Word.Not(LOOPHOLE(tail, INTEGER));
    loque.write("++ctl", NIL, 100, b);
  END logCtrl;

PROCEDURE ctrlTest(ms8: MS8) =
  VAR b : INTEGER;
  BEGIN
    loque.write("    ctlTest started", ms8, ms8.num);
    FOR n := 1 TO NUM_GCS DO
      ctrl[n] := NEW(objR);
      ctrl[n].r := NEW(R);
      initR(ctrl[n].r, ms8.num);
      scrubStack();
      b := Word.Not(LOOPHOLE(ctrl[n], INTEGER));
      loque.write("--ctl", NIL, n, b);
    END;
    tail := NEW(objR);
    b := Word.Not(LOOPHOLE(tail, INTEGER));
    loque.write("--ctl", NIL, 100, b);

    loque.write("    ctlTest exiting", ms8, ms8.num);
  END ctrlTest;


PROCEDURE pageTest(ms8: MS8) =
  VAR
    spinner : INTEGER := 0;
    s := Stage.pause;
    a : ARRAY [1..NUM_GCS] OF REF Page;
    p : ARRAY [1..NUM_GCS] OF objR;
  BEGIN
    loque.write("    pageTest started", ms8, ms8.num);
    FOR n := 1 TO NUM_GCS DO
      a[n] := NEW(REF Page);
    END;

    FOR cycle := 1 TO 3 DO
      (* pre-pause action *)
      IF cycle = 2 THEN
        pinMov(p);
      END;

      (* pause cycle*)
      ms8.wait(s);
      loque.write("    pageTest " & stageName[s], NIL, ms8.num);
      FOR i := 1 TO NUM_GCS DO
        a[i] := NEW(REF Page)
      END;

      (* edge cycle *)
      INC(s);
      ms8.wait(s);
      loque.write("    pageTest " & stageName[s], NIL, ms8.num);

      INC(s);
      WHILE ms8.stage < s DO
       INC(spinner);
      END;

      (* post-edge action *)
      ms8.wait(s);
      loque.write("    pageTest " & stageName[s], NIL, -1, spinner);
      FOR n := 1 TO NUM_GCS DO
        loque.write("  page", LOOPHOLE(a[n],ROOT), n);
      END;
      FOR i := 1 TO NUM_GCS DO
        a[i] := NEW(REF Page)
      END;
      IF cycle = 2 THEN
        nilMov(p);
        scrubStack();
      END;

    END;


    ms8.wait(Stage.finish);
    loque.write("    pageTest finish", ms8, ms8.num);

    loque.write("    pageTest exiting", ms8, ms8.num);    
  END pageTest;


(* MS8 Test Driver*)
CONST NTEST = 6;
VAR subject : ARRAY [0..NTEST-1] OF MS8;

PROCEDURE mainMS8() =
  VAR s := Stage.pause;
  BEGIN
    loque.write("mainMS8 BEGIN", NIL, -1);

    (* Create *)
    subject[0]:= NewMS8(nullTest);
    subject[1]:= NewMS8(recrTest);
    subject[2]:= NewMS8(objrTest);
    subject[3]:= NewMS8(movTest);
    subject[4]:= NewMS8(pageTest);
    subject[5]:= NewMS8(ctrlTest);
    loque.write("  mainMS8 tests created", NIL, NTEST);

    (* Start *)
    FOR i := 0 TO NTEST-1 DO
      subject[i].advance(Stage.start);
      loque.write("  mainMS8 start", subject[i], i+1);
    END;
    Thread.Pause(0.5D0);
    logMov(subject[3].num);
    logCtrl(subject[5].num);
    scrubStack();

    (* Three cycles of collection pairs *)
    FOR cycle := 1 TO 3 DO
      FOR j := 1 TO 2 DO 
        Thread.Pause(0.5D0);
        loque.write("  mainMS8 " & stageName[s], NIL, -1);
        FOR i := 0 TO NTEST-1 DO
          subject[i].advance(s);
        END;

        Thread.Pause(0.5D0);
        RTCollector.Collect();
        loque.write("+GC", NIL, WThread.GC);
        logMov(subject[3].num);
        logCtrl(subject[5].num);
        scrubStack();
        INC(s);
      END;
    END;

    (* Finish *)
    FOR i := 0 TO NTEST-1 DO
      subject[i].advance(Stage.finish);
      loque.write("  mainMS8 finish", subject[i], i+1);
    END;

    (* Join *)
    FOR i := 0 TO NTEST-1 DO
      EVAL Thread.Join(subject[i].thread);
      loque.write("  mainMS8 joined", subject[i], i+1);
    END;

    loque.write("mainMS8 END", NIL, -1);
  END mainMS8;

BEGIN
  loque := Loque.Open();
  mainMS8();
  loque.close();
END Main.