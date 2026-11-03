UNSAFE MODULE Main;

IMPORT Loque;
IMPORT Thread;
IMPORT WThread;
IMPORT RTCollector;
IMPORT Word;

VAR loque : Loque.T;

(* MS7 Test Subject *)
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

TYPE
  Routine = PROCEDURE(ms7 : MS7);

  MS7 = Thread.Closure OBJECT
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

  Page = RECORD
    data : ARRAY [1..PAGE_SIZE] OF [0..255];
  END;

VAR ms7Num : INTEGER := 1;

PROCEDURE NewMS7(rtn : Routine) : MS7 =
  VAR ms7 := NEW(MS7);
  BEGIN
    ms7.num := ms7Num; INC(ms7Num);
    ms7.routine := rtn;
    ms7.stage := Stage.creat;
    ms7.syn  := NEW(MUTEX);
    ms7.cond := NEW(Thread.Condition);
    RETURN ms7;
  END NewMS7;

PROCEDURE Apply(ms7: MS7) : REFANY =
  BEGIN
    ms7.routine(ms7);
    RETURN NIL;
  END Apply;

PROCEDURE Advance(ms7: MS7; next : Stage) =
  BEGIN
    <* ASSERT next > ms7.stage *>
    IF next = Stage.start THEN
      ms7.stage := next;
      ms7.thread := Thread.Fork(ms7);
    ELSE
      (* running, actually advance*)
      Thread.Acquire(ms7.syn);
      ms7.stage := next;
      Thread.Release(ms7.syn);
      Thread.Signal(ms7.cond);
    END;
  END Advance;

PROCEDURE Wait(ms7: MS7; next : Stage) =
  BEGIN
    <* ASSERT next >= ms7.stage *>
    Thread.Acquire(ms7.syn);
    WHILE ms7.stage < next DO Thread.Wait(ms7.syn, ms7.cond); END;
    Thread.Release(ms7.syn);
 END Wait;

(* MS7 Test Cases *)
PROCEDURE nullTest(ms7: MS7) =
  VAR spinner : INTEGER := 0; s := Stage.pause;
  BEGIN
    loque.write("    nullTest started", ms7, ms7.num);

    FOR cycle := 1 TO 3 DO
      (* pre-pause action *)

      (* pause cycle*)
      ms7.wait(s);
      loque.write("    nullTest " & stageName[s], NIL, ms7.num);

      (* edge cycle *)
      INC(s);
      ms7.wait(s);
      loque.write("    nullTest " & stageName[s], NIL, ms7.num);

      INC(s);
      WHILE ms7.stage < s DO
       INC(spinner);
      END;

      (* post-edge action *)
      loque.write("    nullTest " & stageName[s], NIL, -1, spinner);

    END;

    ms7.wait(Stage.finish);
    loque.write("    nullTest finish", ms7, ms7.num);
    loque.write("    nullTest exiting", ms7, ms7.num);    
  END nullTest;

PROCEDURE intTest(ms7: MS7) =
  VAR
    a : ARRAY [1..NUM_GCS] OF REF INTEGER;
  BEGIN
    loque.write("    intTest started", ms7, ms7.num);
    FOR n := 1 TO NUM_GCS DO
      a[n] := NEW(REF INTEGER);
      loque.write("      int", LOOPHOLE(a[n],ROOT), n);
    END;

    ms7.wait(Stage.pause);
    FOR n := 1 TO NUM_GCS DO
      loque.write("      int", LOOPHOLE(a[n],ROOT), n);
    END;

    ms7.wait(Stage.finish);
    loque.write("    intTest finish", ms7, ms7.num);

    loque.write("    intTest exiting", ms7, ms7.num);    
  END intTest;

TYPE
  rec = RECORD
    a : INTEGER;
    b : INTEGER;
    c : INTEGER;
    d : INTEGER;
  END;
PROCEDURE recTest(ms7: MS7) =
  VAR
    a : ARRAY [1..NUM_GCS] OF REF rec;
  BEGIN
    loque.write("    recTest started", ms7, ms7.num);
    FOR n := 1 TO NUM_GCS DO
      a[n] := NEW(REF rec);
      loque.write("      rec", LOOPHOLE(a[n],ROOT), n);
    END;

    ms7.wait(Stage.edge);
    FOR n := 1 TO NUM_GCS DO
      loque.write("      rec", LOOPHOLE(a[n],ROOT), n);
    END;

    ms7.wait(Stage.finish);
    loque.write("    recTest finish", ms7, ms7.num);

    loque.write("    recTest exiting", ms7, ms7.num);    
  END recTest;

TYPE
  obj = BRANDED "ms7 object" OBJECT
    a : INTEGER;
    b : INTEGER;
    c : INTEGER;
    d : INTEGER;
    large : ARRAY [1..40000] OF [0..255];
  END;
PROCEDURE objTest(ms7: MS7) =
  VAR
    a : ARRAY [1..NUM_GCS] OF obj;
  BEGIN
    loque.write("    objTest started", ms7, ms7.num);
    FOR n := 1 TO NUM_GCS DO
      a[n] := NEW(obj);
      loque.write("      obj", a[n], n);
    END;

    ms7.wait(Stage.edgeTwo);
    FOR n := 1 TO NUM_GCS DO
      loque.write("      obj", a[n], n);
    END;


    ms7.wait(Stage.finish);
    loque.write("    objTest finish", ms7, ms7.num);

    loque.write("    objTest exiting", ms7, ms7.num);    
  END objTest;

VAR mov : ARRAY [1..NUM_GCS] OF obj;

PROCEDURE logMov() =
  VAR b : INTEGER;
  BEGIN
    FOR i := 1 TO NUM_GCS DO
      b := Word.Not(LOOPHOLE(mov[i], INTEGER));
      loque.write("++mov", NIL, i, b);
    END;
  END logMov;

PROCEDURE pinMov(VAR p : ARRAY [1..NUM_GCS] OF obj) =
  BEGIN
    FOR i := 1 TO NUM_GCS DO
      IF i = 2 THEN p[i] := mov[i]; END;
    END;
  END pinMov;

PROCEDURE nilMov(VAR p : ARRAY [1..NUM_GCS] OF obj) =
  BEGIN
    FOR i := 1 TO NUM_GCS DO
      p[i] := NIL;
    END;
  END nilMov;

PROCEDURE scrubMov() =
  VAR a : ARRAY [1..384] OF CARDINAL;
  BEGIN
    FOR i := FIRST(a) TO LAST(a) DO
      a[i] := 0;
    END;
  END scrubMov;

PROCEDURE movTest(ms7: MS7) =
  VAR
  BEGIN
    loque.write("    movTest started", ms7, ms7.num);
    FOR n := 1 TO NUM_GCS DO
      mov[n] := NEW(obj);
    END;

    loque.write("    movTest exiting", ms7, ms7.num);
  END movTest;


VAR
  ctrl : ARRAY [1..NUM_GCS+1] OF obj;
  tail : obj;


PROCEDURE logCtrl() =
  VAR b : INTEGER;
  BEGIN
    FOR i := 1 TO NUM_GCS+1 DO
      b := Word.Not(LOOPHOLE(ctrl[i], INTEGER));
      loque.write("++ctl", NIL, i, b);
    END;
    b := Word.Not(LOOPHOLE(tail, INTEGER));
    loque.write("++ctl", NIL, 100, b);
  END logCtrl;

PROCEDURE ctrlTest(ms7: MS7) =
  VAR b : INTEGER;
  BEGIN
    loque.write("    ctlTest started", ms7, ms7.num);
    FOR n := 1 TO NUM_GCS+1 DO
      ctrl[n] := NEW(obj);
      b := Word.Not(LOOPHOLE(ctrl[n], INTEGER));
      loque.write("--ctl", NIL, n, b);
    END;
    tail := NEW(obj);
    b := Word.Not(LOOPHOLE(tail, INTEGER));
    loque.write("--ctl", NIL, 100, b);

    loque.write("    ctlTest exiting", ms7, ms7.num);
  END ctrlTest;


PROCEDURE pageTest(ms7: MS7) =
  VAR
    spinner : INTEGER := 0;
    s := Stage.pause;
    a : ARRAY [1..NUM_GCS] OF REF Page;
    p : ARRAY [1..NUM_GCS] OF obj;
  BEGIN
    loque.write("    pageTest started", ms7, ms7.num);
    FOR n := 1 TO NUM_GCS DO
      a[n] := NEW(REF Page);
    END;

    FOR cycle := 1 TO 3 DO
      (* pre-pause action *)
      IF cycle = 2 THEN
        pinMov(p);
      END;

      (* pause cycle*)
      ms7.wait(s);
      loque.write("    pageTest " & stageName[s], NIL, ms7.num);
      FOR i := 1 TO NUM_GCS DO
        a[i] := NEW(REF Page)
      END;

      (* edge cycle *)
      INC(s);
      ms7.wait(s);
      loque.write("    pageTest " & stageName[s], NIL, ms7.num);

      INC(s);
      WHILE ms7.stage < s DO
       INC(spinner);
      END;

      (* post-edge action *)
      ms7.wait(s);
      loque.write("    pageTest " & stageName[s], NIL, -1, spinner);
      FOR n := 1 TO NUM_GCS DO
        loque.write("  page", LOOPHOLE(a[n],ROOT), n);
      END;
      FOR i := 1 TO NUM_GCS DO
        a[i] := NEW(REF Page)
      END;
      IF cycle = 2 THEN
        nilMov(p);
        scrubMov();
      END;

    END;


    ms7.wait(Stage.finish);
    loque.write("    pageTest finish", ms7, ms7.num);

    loque.write("    pageTest exiting", ms7, ms7.num);    
  END pageTest;


(* MS7 Test Driver*)
CONST NTEST = 7;
VAR subject : ARRAY [0..NTEST-1] OF MS7;

PROCEDURE mainMS7() =
  VAR s := Stage.pause;
  BEGIN
    loque.write("mainMS7 BEGIN", NIL, -1);

    (* Create *)
    subject[0]:= NewMS7(nullTest);
    subject[1]:= NewMS7(intTest);
    subject[2]:= NewMS7(recTest);
    subject[3]:= NewMS7(objTest);
    subject[4]:= NewMS7(movTest);
    subject[5]:= NewMS7(ctrlTest);
    subject[6]:= NewMS7(pageTest);
    loque.write("  mainMS7 tests created", NIL, NTEST);

    (* Start *)
    FOR i := 0 TO NTEST-1 DO
      subject[i].advance(Stage.start);
      loque.write("  mainMS7 start", subject[i], i+1);
    END;
    Thread.Pause(0.5D0);
    logMov();
    logCtrl();
    scrubMov();

    (* Three cycles of collection pairs *)
    FOR cycle := 1 TO 3 DO
      FOR j := 1 TO 2 DO 
        Thread.Pause(0.5D0);
        loque.write("  mainMS7 " & stageName[s], NIL, -1);
        FOR i := 0 TO NTEST-1 DO
          subject[i].advance(s);
        END;

        Thread.Pause(0.5D0);
        RTCollector.Collect();
        loque.write("+GC", NIL, WThread.GC);
        logMov();
        logCtrl();
        scrubMov();
        INC(s);
      END;
    END;

    (* Finish *)
    FOR i := 0 TO NTEST-1 DO
      subject[i].advance(Stage.finish);
      loque.write("  mainMS7 finish", subject[i], i+1);
    END;

    (* Join *)
    FOR i := 0 TO NTEST-1 DO
      EVAL Thread.Join(subject[i].thread);
      loque.write("  mainMS7 joined", subject[i], i+1);
    END;

    loque.write("mainMS7 END", NIL, -1);
  END mainMS7;

BEGIN
  loque := Loque.Open();
  mainMS7();
  loque.close();
END Main.