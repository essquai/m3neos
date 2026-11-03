UNSAFE MODULE Main;

IMPORT Loque;
IMPORT Thread;
IMPORT WThread;
IMPORT RTCollector;
IMPORT Word;
IMPORT Text;

VAR loque : Loque.T;

(* MS9 Test Subject *)
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

  LG_SIZE = 20000;
  SM_SIZE = 3;
  K_SIZE  = 8;
  MULTI_SIZE = 1666;
  OM_SIZE = 13000;
  IMP1_SIZE = 100;
  IMP2_SIZE = 50;
  VM1 = 6;
  VM2 = 9;

TYPE
  Routine = PROCEDURE(ms9 : MS9);

  MS9 = Thread.Closure OBJECT
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
  Pad  = REF ARRAY [1..4]  OF R;      (* impure, small *)
  PadB = REF ARRAY [1..32] OF Byte;   (* pure, small *)

  AggNode = REF RECORD
    tag  : INTEGER;
    next : R;                              (* level 2: pure leaf *)
    pad  : ARRAY [1..LARGE_SIZE] OF Byte;  (* roughly one object per page *)
  END;
  AggRec = RECORD
    id   : INTEGER;
    node : AggNode;                        (* level 1, impure *)
    leaf : R;                              (* level 1, pure *)
  END;
  AggArr = ARRAY [0..2] OF AggRec;         (* array of records with REFs *)

VAR ms9Num : INTEGER := 1;

PROCEDURE NewMS9(rtn : Routine) : MS9 =
  VAR ms9 := NEW(MS9);
  BEGIN
    ms9.num := ms9Num; INC(ms9Num);
    ms9.routine := rtn;
    ms9.stage := Stage.creat;
    ms9.syn  := NEW(MUTEX);
    ms9.cond := NEW(Thread.Condition);
    RETURN ms9;
  END NewMS9;

PROCEDURE Apply(ms9: MS9) : REFANY =
  BEGIN
    ms9.routine(ms9);
    RETURN NIL;
  END Apply;

PROCEDURE Advance(ms9: MS9; next : Stage) =
  BEGIN
    <* ASSERT next > ms9.stage *>
    IF next = Stage.start THEN
      ms9.stage := next;
      ms9.thread := Thread.Fork(ms9);
    ELSE
      (* running, actually advance*)
      Thread.Acquire(ms9.syn);
      ms9.stage := next;
      Thread.Release(ms9.syn);
      Thread.Signal(ms9.cond);
    END;
  END Advance;

PROCEDURE Wait(ms9: MS9; next : Stage) =
  BEGIN
    <* ASSERT next >= ms9.stage *>
    Thread.Acquire(ms9.syn);
    WHILE ms9.stage < next DO Thread.Wait(ms9.syn, ms9.cond); END;
    Thread.Release(ms9.syn);
 END Wait;

(* MS9 Test Cases *)
PROCEDURE nullTest(ms9: MS9) =
  VAR spinner : INTEGER := 0; s := Stage.pause;
  BEGIN
    loque.write("    nullTest started", ms9, ms9.num);

    FOR cycle := 1 TO 3 DO
      (* pre-pause action *)

      (* pause cycle*)
      ms9.wait(s);
      loque.write("    nullTest " & stageName[s], NIL, ms9.num);

      (* edge cycle *)
      INC(s);
      ms9.wait(s);
      loque.write("    nullTest " & stageName[s], NIL, ms9.num);

      INC(s);
      WHILE ms9.stage < s DO
       INC(spinner);
      END;

      (* post-edge action *)
      loque.write("    nullTest " & stageName[s], NIL, -1, spinner);

    END;

    ms9.wait(Stage.finish);
    loque.write("    nullTest finish", ms9, ms9.num);
    loque.write("    nullTest exiting", ms9, ms9.num);    
  END nullTest;

VAR
  smInt: REF ARRAY OF INTEGER;
  lgInt: REF ARRAY OF INTEGER;

PROCEDURE initInt() =
  BEGIN
    FOR i := FIRST(smInt^) TO LAST(smInt^) DO
      smInt[i] := i;
    END;
    FOR i := FIRST(lgInt^) TO LAST(lgInt^) DO
      lgInt[i] := 256 + i;
    END;
  END initInt;

PROCEDURE logInt() =
  BEGIN
    FOR i := FIRST(smInt^) TO LAST(smInt^) DO
      IF i <= K_SIZE THEN EXIT END;
      loque.write("      smInt ", NIL, smInt[i]);
    END;
    FOR i := FIRST(lgInt^) TO LAST(lgInt^) DO
      IF i <= K_SIZE THEN EXIT END;
      loque.write("      lgInt ", NIL, lgInt[i]);
    END;
  END logInt;

PROCEDURE checkInt() : BOOLEAN =
  BEGIN
    FOR i := FIRST(smInt^) TO LAST(smInt^) DO
      IF i # smInt[i] THEN RETURN FALSE; END;
    END;
    FOR i := FIRST(lgInt^) TO LAST(lgInt^) DO
      IF i + 256 # lgInt[i] THEN RETURN FALSE; END;
    END;
    RETURN TRUE;
  END checkInt;


PROCEDURE intTest(ms9: MS9) =
  VAR spinner : INTEGER := 0; s := Stage.pause;
  BEGIN
    loque.write("    intTest started", ms9, ms9.num);
    initInt();
    scrubStack();

    FOR cycle := 1 TO 3 DO
      (* pre-pause action *)
      logInt();
      scrubStack();

      (* pause cycle*)
      ms9.wait(s);
      loque.write("    intTest " & stageName[s], NIL, ms9.num);
      <* ASSERT checkInt() *>
      scrubStack();

      (* edge cycle *)
      INC(s);
      ms9.wait(s);
      loque.write("    intTest " & stageName[s], NIL, ms9.num);

      INC(s);
      WHILE ms9.stage < s DO
       INC(spinner);
      END;

      (* post-edge action *)
      loque.write("    intTest " & stageName[s], NIL, -1, spinner);
      <* ASSERT checkInt() *>
      scrubStack();

    END;

    ms9.wait(Stage.finish);
    loque.write("    intTest finish", ms9, ms9.num);
    loque.write("    intTest exiting", ms9, ms9.num);    
  END intTest;


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

PROCEDURE logRef(pfx : TEXT; READONLY a: ARRAY OF R) =
  VAR txt : TEXT; b : INTEGER;
  BEGIN
    txt := "++" & pfx & " log";
    FOR i := FIRST(a) TO LAST(a) DO
      b := Word.Not(LOOPHOLE(a[i], INTEGER));
      loque.write(txt, NIL, i, b);
      IF i > K_SIZE THEN EXIT END;
    END;    
  END logRef;

PROCEDURE corruptRef(READONLY a : ARRAY OF R) : BOOLEAN =
  VAR k : INTEGER := 1;
  BEGIN
    FOR i := FIRST(a) TO LAST(a) DO
      IF k <= K_SIZE THEN
        (* validate the content *)
        IF corruptR(a[i], (k*16 + k) MOD 256) THEN RETURN TRUE; END;
      ELSE
        IF a[i] # a[i-K_SIZE] THEN RETURN TRUE; END;
      END;
      INC(k);
    END;
    RETURN FALSE;    
  END corruptRef;

PROCEDURE setupRef(VAR a : REF ARRAY [1..SM_SIZE] OF R; b : REF ARRAY [1..LG_SIZE] OF R;
                   c, d: REF ARRAY OF R) =
  VAR
    r : ARRAY [0..K_SIZE-1] OF R;
    k : INTEGER;
  BEGIN
    FOR n := 0 TO K_SIZE-1 DO
      r[n] := NEW(R);
      k := n + 1;
      initR(r[n], (k*16 + k) MOD 256);
    END;
    
    k := 0;
    FOR i := FIRST(a^) TO LAST(a^) DO
      a^[i] := r[k];
      k := (k + 1) MOD K_SIZE;
    END;

    k := 0;
    FOR i := FIRST(b^) TO LAST(b^) DO
      b^[i] := r[k];
      k := (k + 1) MOD K_SIZE;
    END;
    
    k := 0;
    FOR i := FIRST(c^) TO LAST(c^) DO
      c[i] := r[k];
      k := (k + 1) MOD K_SIZE;
    END;
    
    k := 0;
    FOR i := FIRST(d^) TO LAST(d^) DO
      d^[i] := r[k];
      k := (k + 1) MOD K_SIZE;
    END;

    
    k := 0;
    FOR i := FIRST(d^) TO LAST(d^) DO
      d^[i] := r[k];
      k := (k + 1) MOD K_SIZE;
    END;

  END setupRef;

PROCEDURE logCont() =
  BEGIN
    loque.write("++smOne addr", NIL, 0, Word.Not(LOOPHOLE(smOne, INTEGER)));
    loque.write("++lgOne addr", NIL, 0, Word.Not(LOOPHOLE(lgOne, INTEGER)));
    loque.write("++smTwo addr", NIL, 0, Word.Not(LOOPHOLE(smTwo, INTEGER)));
    loque.write("++lgTwo addr", NIL, 0, Word.Not(LOOPHOLE(lgTwo, INTEGER)));
  END logCont;

VAR
  smOne : REF ARRAY [1..SM_SIZE] OF R;
  lgOne : REF ARRAY [1..LG_SIZE] OF R;

PROCEDURE oneTest(ms9: MS9) =
  VAR
    spinner : INTEGER := 0;
    s := Stage.pause;
  BEGIN
    loque.write("    oneTest started", ms9, ms9.num);
    scrubStack();

    FOR cycle := 1 TO 3 DO
      logCont();
      scrubStack();
      (* pre-pause action *)
      logRef("smOne", smOne^);
      scrubStack();
      logRef("lgOne", lgOne^);
      scrubStack();

      (* pause cycle*)
      ms9.wait(s);
      loque.write("    oneTest " & stageName[s], NIL, ms9.num);
      <* ASSERT NOT corruptRef(smOne^) *>
      scrubStack();
      <* ASSERT NOT corruptRef(lgOne^) *>
      scrubStack();

      (* edge cycle *)
      INC(s);
      ms9.wait(s);
      loque.write("    oneTest " & stageName[s], NIL, ms9.num);

      INC(s);
      WHILE ms9.stage < s DO
       INC(spinner);
      END;

      (* post-edge action *)
      loque.write("    oneTest " & stageName[s], NIL, -1, spinner);
      <* ASSERT NOT corruptRef(smOne^) *>
      scrubStack();
      <* ASSERT NOT corruptRef(lgOne^) *>
      scrubStack();

    END;


    ms9.wait(Stage.finish);
    loque.write("    oneTest finish", ms9, ms9.num);

    loque.write("    oneTest exiting", ms9, ms9.num);    
  END oneTest;


VAR
  smTwo : REF ARRAY OF R;
  lgTwo : REF ARRAY OF R;
  smObj : REF ARRAY OF obj;
  lgObj : REF ARRAY OF obj;

PROCEDURE twoTest(ms9: MS9) =
  VAR
    spinner : INTEGER := 0;
    s := Stage.pause;
  BEGIN
    loque.write("    twoTest started", ms9, ms9.num);
    scrubStack();

    FOR cycle := 1 TO 3 DO
      (* pre-pause action *)
      logRef("smTwo", smTwo^);
      scrubStack();
      logRef("lgTwo", lgTwo^);
      scrubStack();

      (* pause cycle*)
      ms9.wait(s);
      loque.write("    twoTest " & stageName[s], NIL, ms9.num);
      <* ASSERT NOT corruptRef(smTwo^) *>
      scrubStack();
      <* ASSERT NOT corruptRef(lgTwo^) *>
      scrubStack();

      (* edge cycle *)
      INC(s);
      ms9.wait(s);
      loque.write("    twoTest " & stageName[s], NIL, ms9.num);

      INC(s);
      WHILE ms9.stage < s DO
       INC(spinner);
      END;

      (* post-edge action *)
      loque.write("    twoTest " & stageName[s], NIL, -1, spinner);
      <* ASSERT NOT corruptRef(smTwo^) *>
      scrubStack();
      <* ASSERT NOT corruptRef(lgTwo^) *>
      scrubStack();

    END;


    ms9.wait(Stage.finish);
    loque.write("    twoTest finish", ms9, ms9.num);

    loque.write("    twoTest exiting", ms9, ms9.num);    
  END twoTest;



PROCEDURE recrInit(VAR a : REF ARRAY OF recR; sz: INTEGER; num : INTEGER;) =
  VAR k : INTEGER := 0; r : ARRAY [0..K_SIZE-1] OF REF INTEGER;
  BEGIN
    FOR i := 0 TO K_SIZE - 1 DO
      r[i] := NEW(REF INTEGER);
      r[i]^ := num + i;
    END;

    a := NEW(REF ARRAY OF recR, sz);
    FOR n := FIRST(a^) TO LAST(a^) DO
      a[n].r := r[k];
      k := (k + 1) MOD K_SIZE;
    END;
  END recrInit;

PROCEDURE recrLog(pfx: TEXT; a : REF ARRAY OF recR) =
  VAR
    txt := "      " & pfx & "recr";
    txtr := "      ++" & pfx & "recr";
  BEGIN
    FOR n := FIRST(a^) TO LAST(a^) DO
      IF n >= K_SIZE THEN EXIT END;
      loque.write(txt, LOOPHOLE(a,ROOT), n);
      loque.write(txtr, LOOPHOLE(a[n].r,ROOT), n);
    END;
  END recrLog;


PROCEDURE recrCheck(a : REF ARRAY OF recR; num : INTEGER) : BOOLEAN =
  VAR k : INTEGER := 0;
  BEGIN
    FOR i := FIRST(a^) TO LAST(a^) DO
      IF k < K_SIZE THEN
        (* validate the content *)
        IF a[i].r^ # (num + k) THEN RETURN FALSE; END;
      ELSE
        IF a[i] # a[i-K_SIZE] THEN RETURN FALSE; END;
      END;
      INC(k);
    END;
    RETURN TRUE;
  END recrCheck;

TYPE
  recR = RECORD
    a : INTEGER;
    r : REF INTEGER;
  END;

VAR
  smRec: REF ARRAY OF recR;
  lgRec: REF ARRAY OF recR;

PROCEDURE recrTest(ms9: MS9) =
  VAR
    spinner : INTEGER := 0;
    s := Stage.pause;
  BEGIN
    loque.write("    recrTest started", ms9, ms9.num);
    recrInit(smRec, SM_SIZE, ms9.num);
    scrubStack();
    recrInit(lgRec, LG_SIZE, ms9.num);
    scrubStack();

    FOR cycle := 1 TO 3 DO
      (* pre-pause action *)
      recrLog("sm", smRec);
      scrubStack();
      recrLog("lg", lgRec);
      scrubStack();

      (* pause cycle*)
      ms9.wait(s);
      loque.write("    recrTest " & stageName[s], NIL, ms9.num);
      <* ASSERT recrCheck(smRec, ms9.num) *>
      scrubStack();
      <* ASSERT recrCheck(lgRec, ms9.num) *>
      scrubStack();

      (* edge cycle *)
      INC(s);
      ms9.wait(s);
      loque.write("    recrTest " & stageName[s], NIL, ms9.num);

      INC(s);
      WHILE ms9.stage < s DO
       INC(spinner);
      END;

      (* post-edge action *)
      loque.write("    recrTest " & stageName[s], NIL, -1, spinner);
      <* ASSERT recrCheck(smRec, ms9.num) *>
      scrubStack();
      <* ASSERT recrCheck(lgRec, ms9.num) *>
      scrubStack();

    END;


    ms9.wait(Stage.finish);
    loque.write("    recrTest finish", ms9, ms9.num);

    loque.write("    recrTest exiting", ms9, ms9.num);    
  END recrTest;


TYPE
  obj = BRANDED "ms9 object" OBJECT
    a : INTEGER;
    b : INTEGER;
    c : INTEGER;
    d : INTEGER;
  END;

PROCEDURE objInit(a : REF ARRAY OF obj; num : INTEGER) =
  BEGIN
    FOR n := FIRST(a^) TO LAST(a^) DO
      a[n] := NEW(obj);
      a[n].a := num * 256;
    END;
  END objInit;

PROCEDURE objLog(pfx : TEXT; a : REF ARRAY OF obj) =
  VAR txt := "      " & pfx & "Obj";
  BEGIN
    FOR n := FIRST(a^) TO LAST(a^) DO
      IF n > K_SIZE THEN EXIT END;
      loque.write(txt, a[n], n);
    END;
  END objLog;

PROCEDURE objCheck(a : REF ARRAY OF obj; num : INTEGER) =
  BEGIN
    FOR n := FIRST(a^) TO LAST(a^) DO
      <* ASSERT a[n].a= 256 * num *>
    END;
  END objCheck;

PROCEDURE objTest(ms9: MS9) =
  VAR
    spinner : INTEGER := 0;
    s := Stage.pause;
  BEGIN
    loque.write("    objrTest started", ms9, ms9.num);
    objInit(smObj, ms9.num);
    scrubStack();
    objInit(lgObj, ms9.num);
    scrubStack();

    FOR cycle := 1 TO 3 DO
      (* pre-pause action *)
      objLog("sm", smObj);
      scrubStack();
      objLog("sm", lgObj);
      scrubStack();

      (* pause cycle*)
      ms9.wait(s);
      loque.write("    objTest " & stageName[s], NIL, ms9.num);
      objCheck(smObj, ms9.num);
      scrubStack();
      objCheck(lgObj, ms9.num);
      scrubStack();

      (* edge cycle *)
      INC(s);
      ms9.wait(s);
      loque.write("    objTest " & stageName[s], NIL, ms9.num);

      INC(s);
      WHILE ms9.stage < s DO
       INC(spinner);
      END;

      (* post-edge action *)
      loque.write("    objTest " & stageName[s], NIL, -1, spinner);
      objCheck(smObj, ms9.num);
      scrubStack();
      objCheck(lgObj, ms9.num);
      scrubStack();
    END;

    ms9.wait(Stage.finish);
    loque.write("    objTest finish", ms9, ms9.num);

    loque.write("    objTest exiting", ms9, ms9.num);    
  END objTest;


PROCEDURE scrubStack() =
  VAR a : ARRAY [1..4096] OF Byte;
  BEGIN
    FOR i := FIRST(a) TO LAST(a) DO
      a[i] := 0;
    END;
  END scrubStack;


VAR
  withAlias: REF ARRAY OF Byte;
  subAlias: REF ARRAY OF Byte;
  tailAlias: REF ARRAY OF Byte;

PROCEDURE aliasTest(ms9: MS9) =
  BEGIN
    WITH with = withAlias[30000] DO
      aliasTestProc(ms9, with, SUBARRAY(subAlias^, 30000, 10), SUBARRAY(tailAlias^, 77000, 10));
    END;
  END aliasTest;

PROCEDURE aliasTestProc(ms9: MS9; VAR with : Byte; VAR sub: ARRAY OF Byte; VAR tail: ARRAY OF Byte) =
  VAR
    spinner : INTEGER := 0;
    s := Stage.pause;
    a1, a2: INTEGER;
  BEGIN
    loque.write("    aliasTest started", ms9, ms9.num);
    (* pathologically drop references *)
    loque.write("++with NOT NIL", NIL, with, Word.Not(LOOPHOLE(withAlias,INTEGER)));
    loque.write("++sub NOT NIL", NIL, with, Word.Not(LOOPHOLE(subAlias,INTEGER)));
    withAlias := NIL;
    subAlias  := NIL;
    (* hopeful pins *)
    with := 16_A0;
    sub[0] := 16_64; sub[9] := 16_64;
    tail[0] := 16_77; tail[9] := 16_77;

    FOR cycle := 1 TO 3 DO
      (* pre-pause action *)
      loque.write("++with", NIL, with, Word.Not(LOOPHOLE(withAlias,INTEGER)));
      a1 := ORD(sub[0]);
      a2 := ORD(sub[9]);
      loque.write("++sub", NIL, a1, a2);
      a1 := ORD(tail[0]);
      loque.write("++tail", NIL, a1, Word.Not(LOOPHOLE(tailAlias,INTEGER)));
      scrubStack();

      (* pause cycle*)
      ms9.wait(s);
      loque.write("    aliasTest " & stageName[s], NIL, ms9.num);
      <* ASSERT with = 16_A0 *>
      <* ASSERT sub[0] = 16_64 AND sub[9] = 16_64 *>
      <* ASSERT tail[0] = 16_77 AND tail[9] = 16_77 *>

      (* edge cycle *)
      INC(s);
      ms9.wait(s);
      loque.write("    aliasTest " & stageName[s], NIL, ms9.num);

      INC(s);
      WHILE ms9.stage < s DO
       INC(spinner);
      END;

      (* post-edge action *)
      loque.write("    aliasTest " & stageName[s], NIL, -1, spinner);
      <* ASSERT with = 16_A0 *>
      <* ASSERT sub[0] = 16_64 AND sub[9] = 16_64 *>
      <* ASSERT tail[0] = 16_77 AND tail[9] = 16_77 *>

    END;

    ms9.wait(Stage.finish);

    loque.write("    aliasTest finish", ms9, ms9.num);
    loque.write("    aliasTest exiting", ms9, ms9.num);    
  END aliasTestProc;



VAR
  smVal: REF ARRAY OF Byte;
  lgVal: REF ARRAY OF Byte;
  smValKeep : REF ARRAY OF Byte;

PROCEDURE valKeep() =
  BEGIN
      smValKeep[30000] := 103;
      smValKeep[30009] := 109;
  END valKeep;

PROCEDURE valKeep2() =
  BEGIN
      smValKeep[30005] := 55;
  END valKeep2;

PROCEDURE valTest(ms9: MS9) =
  BEGIN
      valKeep();
      scrubStack();
      valTestProc(ms9, SUBARRAY(smVal^, 30000, 10), SUBARRAY(lgVal^, 77000, 10));
      <* ASSERT smValKeep[30000] = 103 AND smValKeep[30009] = 109 *>
      loque.write("++smValKeep", NIL, -1, Word.Not(LOOPHOLE(smValKeep, INTEGER)));
      loque.write("==smValKeep", NIL, ORD(smValKeep[30000]), ORD(smValKeep[30009]));

  END valTest;

PROCEDURE valTestProc(ms9: MS9; sub: ARRAY OF Byte; VAR tail: ARRAY OF Byte) =
  VAR
    spinner : INTEGER := 0;
    s := Stage.pause;
    a1, a2: INTEGER;
  BEGIN
    loque.write("    valTest started", ms9, ms9.num);
    (* pathologically drop references *)
    loque.write("++smVal NOT NIL", NIL, -1, Word.Not(LOOPHOLE(smVal,INTEGER)));
    loque.write("++lgVal NOT NIL", NIL, -1, Word.Not(LOOPHOLE(lgVal,INTEGER)));
    smVal := NIL;
    (* hopeful pins *)
    <* ASSERT sub[0] = 103 AND sub[9] = 109 *>
    sub[0] := 16_64; sub[9] := 16_64;
    tail[0] := 16_77; tail[9] := 16_77;
    valKeep2();
    scrubStack();
    <* ASSERT sub[5] = 0 *>

    FOR cycle := 1 TO 3 DO
      (* pre-pause action *)
      loque.write("++smVal", NIL, -1, Word.Not(LOOPHOLE(smVal,INTEGER)));
      a1 := ORD(sub[0]);
      a2 := ORD(sub[9]);
      loque.write("++++smVal", NIL, a1, a2);
      scrubStack();
      a1 := ORD(tail[0]);
      loque.write("++tail", NIL, a1, Word.Not(LOOPHOLE(lgVal,INTEGER)));
      scrubStack();

      (* pause cycle*)
      ms9.wait(s);
      loque.write("    valTest " & stageName[s], NIL, ms9.num);

      <* ASSERT sub[0] = 16_64 AND sub[9] = 16_64 *>
      <* ASSERT tail[0] = 16_77 AND tail[9] = 16_77 *>

      (* edge cycle *)
      INC(s);
      ms9.wait(s);
      loque.write("    valTest " & stageName[s], NIL, ms9.num);

      INC(s);
      WHILE ms9.stage < s DO
       INC(spinner);
      END;

      (* post-edge action *)
      loque.write("    valTest " & stageName[s], NIL, -1, spinner);

      <* ASSERT sub[0] = 16_64 AND sub[9] = 16_64 *>
      <* ASSERT tail[0] = 16_77 AND tail[9] = 16_77 *>

    END;

    ms9.wait(Stage.finish);

    loque.write("    valTest finish", ms9, ms9.num);
    loque.write("    valTest exiting", ms9, ms9.num);    
  END valTestProc;

VAR
  oneMulti: REF ARRAY OF ARRAY [1..SM_SIZE] OF Byte;
  twoMulti: REF ARRAY OF ARRAY OF ARRAY [1..SM_SIZE] OF Byte;
  impMulti: REF ARRAY OF ARRAY OF R;



PROCEDURE initMulti() =
  VAR
    r : ARRAY [0..K_SIZE-1] OF R;
    k : INTEGER;
  BEGIN
    (* fillers *)
    FOR n := 0 TO K_SIZE-1 DO
      r[n] := NEW(R);
      k := n + 10;
      initR(r[n], (k*16 + k) MOD 256);
    END;

    FOR x := 0 TO MULTI_SIZE - 1 DO
      FOR y := 0 TO K_SIZE - 1 DO
        FOR z := 1 TO SM_SIZE DO
          twoMulti[x][y][z] := (x * 8 + y * 5 + z) MOD 256;
        END;
      END;
    END;
    FOR y := 0 TO OM_SIZE - 1 DO
      FOR z := 1 TO SM_SIZE DO
        oneMulti[y][z] := (y * 5 + z) MOD 256;
      END;
    END;

    (* fill the impure multi array *)
    FOR y := 0 TO IMP1_SIZE - 1 DO
      k := 0;
      FOR z := 0 TO IMP2_SIZE - 1 DO
        impMulti[y][z] := r[k];
        k := (k + 1) MOD K_SIZE;
      END;
    END;
    triInit();
  END initMulti;

PROCEDURE logMulti() =
  VAR a1 : INTEGER;
  BEGIN
      a1 := ORD(oneMulti[0][3]);
      loque.write("++oneMulti", NIL, a1, Word.Not(LOOPHOLE(oneMulti,INTEGER)));
      scrubStack();
      a1 := ORD(twoMulti[MULTI_SIZE-1][0][1]);
      loque.write("++twoMulti", NIL, a1, Word.Not(LOOPHOLE(twoMulti,INTEGER)));
      scrubStack();
      a1 := ORD(impMulti[IMP1_SIZE-1][IMP2_SIZE-1][64]);
      loque.write("++impMulti", NIL, a1, Word.Not(LOOPHOLE(impMulti,INTEGER)));
      scrubStack();
      a1 := ORD(triMulti[39][39][24]);
      loque.write("++triMulti", NIL, a1, Word.Not(LOOPHOLE(triMulti,INTEGER)));
      loque.write("++impElem", NIL, 0, Word.Not(LOOPHOLE(impMulti[0][0], INTEGER)));
  END logMulti;

PROCEDURE checkMulti() : BOOLEAN =
  VAR k, kp : INTEGER;
  BEGIN
    FOR x := 0 TO MULTI_SIZE - 1 DO
      FOR y := 0 TO K_SIZE - 1 DO
        FOR z := 1 TO SM_SIZE DO
          IF twoMulti[x][y][z] # (x * 8 + y * 5 + z) MOD 256 THEN RETURN FALSE; END;
        END;
      END;
    END;

    <* ASSERT NUMBER(twoMulti^) = MULTI_SIZE *>
    <* ASSERT NUMBER(twoMulti[0]) = K_SIZE *>
    <* ASSERT NUMBER(twoMulti[0][0]) = SM_SIZE *>

    FOR y := 0 TO OM_SIZE - 1 DO
      FOR z := 1 TO SM_SIZE DO
        IF oneMulti[y][z] # (y * 5 + z) MOD 256 THEN RETURN FALSE END;
      END;
    END;

    FOR y := 0 TO IMP1_SIZE - 1 DO
      k := 0;
      FOR z := 0 TO IMP2_SIZE - 1 DO
        IF z < K_SIZE THEN
          kp := k + 10;
          <* ASSERT impMulti[y][z] = impMulti[0][z]*>
          <* ASSERT NOT corruptR(impMulti[y][z], (kp*16 + kp) MOD 256) *>
          k := k + 1;
        ELSE
          <* ASSERT impMulti[y][z] = impMulti[y][z-K_SIZE] *>
        END;
      END;
    END;
    RETURN TRUE;
  END checkMulti;

VAR
  triMulti : REF ARRAY OF ARRAY OF ARRAY OF Byte;

PROCEDURE triInit() =
  BEGIN
    triMulti := NEW(REF ARRAY OF ARRAY OF ARRAY OF Byte, 40, 40, 25);
    FOR i := 0 TO 39 DO FOR j := 0 TO 39 DO FOR k := 0 TO 24 DO
      triMulti[i][j][k] := valPat(i, j, k);
    END END END;
  END triInit;

PROCEDURE checkTri(): BOOLEAN =
  BEGIN
    <* ASSERT NUMBER(triMulti^) = 40 AND NUMBER(triMulti[0]) = 40
          AND NUMBER(triMulti[0][0]) = 25 *>
    FOR i := 0 TO 39 DO FOR j := 0 TO 39 DO FOR k := 0 TO 24 DO
      <* ASSERT triMulti[i][j][k] = valPat(i, j, k) *>
    END END END;
    RETURN TRUE;
  END checkTri;

PROCEDURE multiTest(ms9: MS9) =
  VAR triSmall : ARRAY [0..7],[0..7],[0..7] OF Byte;
  BEGIN
    (* initialisation *)
    triSmall[2][4][2] := 8;
    triSmall[4][2][2] := 16;
    triSmall[6][0][2] := 24;
    multiTestProc(ms9, triSmall);
    
  END multiTest;

PROCEDURE multiTestProc(ms9: MS9; READONLY a3: ARRAY OF ARRAY OF ARRAY OF Byte) =
  VAR
    spinner : INTEGER := 0;
    s := Stage.pause;
  BEGIN
    loque.write("    multiTest started", ms9, ms9.num);
    (* initialisation *)
    initMulti();
    scrubStack();

    FOR cycle := 1 TO 3 DO
      (* pre-pause action *)
      logMulti();
      scrubStack();

      (* pause cycle*)
      ms9.wait(s);
      loque.write("    multiTest " & stageName[s], NIL, ms9.num);
      <* ASSERT checkMulti() *>
      scrubStack();
      <* ASSERT checkTri() *>
      scrubStack();
      <* ASSERT a3[2][4][2] = 8 *>
      scrubStack();

      (* edge cycle *)
      INC(s);
      ms9.wait(s);
      loque.write("    multiTest " & stageName[s], NIL, ms9.num);

      INC(s);
      WHILE ms9.stage < s DO
       INC(spinner);
      END;

      (* post-edge action *)
      loque.write("    multiTest " & stageName[s], NIL, -1, spinner);
      <* ASSERT checkMulti() *>
      scrubStack();
      <* ASSERT checkTri() *>
      scrubStack();
      <* ASSERT a3[4][2][2] = 16 *>
      <* ASSERT a3[6][0][2] = 24 *>
      scrubStack();

    END;

    ms9.wait(Stage.finish);

    loque.write("    multiTest finish", ms9, ms9.num);
    loque.write("    multiTest exiting", ms9, ms9.num);    
  END multiTestProc;

VAR
  valOrig: REF ARRAY OF ARRAY OF ARRAY [1..SM_SIZE] OF Byte;   (* global, never set NIL *)

PROCEDURE valPat(x, y, z: INTEGER): INTEGER =
  BEGIN
    RETURN (x * 31 + y * 7 + z) MOD 256;
  END valPat;

PROCEDURE valMultiInit() =       (* call from initMS9 *)
  BEGIN
    valOrig := NEW(REF ARRAY OF ARRAY OF ARRAY [1..SM_SIZE] OF Byte, VM1, VM2);
    FOR x := 0 TO VM1 - 1 DO
      FOR y := 0 TO VM2 - 1 DO
        FOR z := 1 TO SM_SIZE DO
          valOrig[x][y][z] := valPat(x, y, z);
        END;
      END;
    END;
  END valMultiInit;

PROCEDURE valMultiTest(ms9: MS9) =
  BEGIN
    valMultiProc(ms9, valOrig^);
    <* ASSERT valOrig[2][4][2] = valPat(2, 4, 2) *>   (* callee's write to its copy did not reach the original *)
    <* ASSERT valOrig[3][1][1] = 77 *>                (* the callee's write to the original did land *)
  END valMultiTest;

PROCEDURE valMultiProc(ms9: MS9;
                       a: ARRAY OF ARRAY OF ARRAY [1..SM_SIZE] OF Byte) =
  VAR spinner : INTEGER := 0; s := Stage.pause;
  BEGIN
    <* ASSERT NUMBER(a) = VM1 AND NUMBER(a[0]) = VM2 *>
    <* ASSERT a[VM1-1][VM2-1][SM_SIZE] = valPat(VM1-1, VM2-1, SM_SIZE) *>  (* last element: full-size copy *)
    a[2][4][2] := 99;                                  (* write the copy *)
    valOrig[3][1][1] := 77;                            (* write the original *)
    <* ASSERT a[3][1][1] = valPat(3, 1, 1) *>          (* the copy does not see it *)

    FOR cycle := 1 TO 3 DO
      scrubStack();
      ms9.wait(s);
      loque.write("    valMulti " & stageName[s], NIL, ms9.num);
      <* ASSERT a[2][4][2] = 99 *>
      <* ASSERT a[VM1-1][VM2-1][SM_SIZE] = valPat(VM1-1, VM2-1, SM_SIZE) *>

      INC(s);
      ms9.wait(s);
      INC(s);
      WHILE ms9.stage < s DO INC(spinner); END;

      <* ASSERT a[2][4][2] = 99 *>
      <* ASSERT a[3][1][1] = valPat(3, 1, 1) *>
    END;

    ms9.wait(Stage.finish);
  END valMultiProc;

VAR mov : ARRAY [1..NUM_GCS] OF obj;


PROCEDURE logMov(<*UNUSED*>v : Byte) =
  VAR b : INTEGER;
  BEGIN
    FOR i := 1 TO NUM_GCS DO
      IF mov[i] = NIL THEN RETURN; END;
      b := Word.Not(LOOPHOLE(mov[i], INTEGER));
      loque.write("++mov", NIL, i, b);
      scrubStack();
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


PROCEDURE pageTest(ms9: MS9) =
  VAR
    spinner : INTEGER := 0;
    s := Stage.pause;
    a : ARRAY [1..NUM_GCS] OF REF Page;
    p : ARRAY [1..NUM_GCS] OF obj;
  BEGIN
    loque.write("    pageTest started", ms9, ms9.num);
    FOR n := 1 TO NUM_GCS DO
      mov[n] := NEW(obj);
    END;
    FOR n := 1 TO NUM_GCS DO
      a[n] := NEW(REF Page);
    END;

    FOR cycle := 1 TO 3 DO
      (* pre-pause action *)
      IF cycle = 2 THEN
        pinMov(p);
      END;

      (* pause cycle*)
      ms9.wait(s);
      loque.write("    pageTest " & stageName[s], NIL, ms9.num);
      FOR i := 1 TO NUM_GCS DO
        a[i] := NEW(REF Page)
      END;

      (* edge cycle *)
      INC(s);
      ms9.wait(s);
      loque.write("    pageTest " & stageName[s], NIL, ms9.num);

      INC(s);
      WHILE ms9.stage < s DO
       INC(spinner);
      END;

      (* post-edge action *)
      ms9.wait(s);
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


    ms9.wait(Stage.finish);
    loque.write("    pageTest finish", ms9, ms9.num);

    loque.write("    pageTest exiting", ms9, ms9.num);    
  END pageTest;

PROCEDURE aggInit(VAR a: AggArr; base: INTEGER) =
  BEGIN
    FOR i := 0 TO LAST(a) DO
      a[i].id   := base + i;
      a[i].leaf := NEW(R);  initR(a[i].leaf, (base + 2*i) MOD 256);
      a[i].node := NEW(AggNode);
      a[i].node.tag  := base * 256 + i;
      a[i].node.next := NEW(R);  initR(a[i].node.next, (base + 2*i + 1) MOD 256);
    END;
  END aggInit;

PROCEDURE aggClear(VAR a: AggArr) =
  BEGIN
    FOR i := 0 TO LAST(a) DO a[i].node := NIL; a[i].leaf := NIL; END;
  END aggClear;

PROCEDURE aggCheck(READONLY a: AggArr; base: INTEGER): BOOLEAN =
  BEGIN
    FOR i := 0 TO LAST(a) DO
      IF a[i].id # base + i THEN RETURN FALSE END;
      IF corruptR(a[i].leaf, (base + 2*i) MOD 256) THEN RETURN FALSE END;
      IF a[i].node.tag # base * 256 + i THEN RETURN FALSE END;
      IF corruptR(a[i].node.next, (base + 2*i + 1) MOD 256) THEN RETURN FALSE END;
    END;
    RETURN TRUE;
  END aggCheck;

PROCEDURE aggLog(pfx: TEXT; READONLY a: AggArr) =   (* element 1 only: ring budget *)
  BEGIN
    loque.write("++" & pfx & " node", NIL, 1, Word.Not(LOOPHOLE(a[1].node, INTEGER)));
    loque.write("++" & pfx & " leaf", NIL, 1, Word.Not(LOOPHOLE(a[1].leaf, INTEGER)));
    loque.write("++" & pfx & " next", NIL, 1, Word.Not(LOOPHOLE(a[1].node.next, INTEGER)));
  END aggLog;

PROCEDURE aggLocTest(ms9: MS9) =
  VAR a, b: AggArr; spinner := 0; s := Stage.pause;
  BEGIN
    loque.write("    aggLocTest started", ms9, ms9.num);
    aggInit(a, 100);
    b := a;              (* by-value copy duplicates the REFs *)
    aggClear(a);         (* b is now the only holder *)
    scrubStack();
    FOR cycle := 1 TO 3 DO
      aggLog("aggLoc", b); scrubStack();
      ms9.wait(s);
      loque.write("    aggLocTest " & stageName[s], NIL, ms9.num);
      <* ASSERT aggCheck(b, 100) *>  scrubStack();
      INC(s); ms9.wait(s);
      INC(s); WHILE ms9.stage < s DO INC(spinner) END;
      <* ASSERT aggCheck(b, 100) *>  scrubStack();
    END;
    ms9.wait(Stage.finish);
    loque.write("    aggLocTest finish", ms9, ms9.num);
    loque.write("    aggLocTest exiting", ms9, ms9.num);
  END aggLocTest;

VAR gAgg: AggArr;

PROCEDURE aggGlobTest(ms9: MS9) =
  VAR spinner := 0; s := Stage.pause;
  BEGIN
    loque.write("    aggGlobTest started", ms9, ms9.num);
    FOR cycle := 1 TO 3 DO
      aggLog("aggGlob", gAgg); scrubStack();
      ms9.wait(s);
      loque.write("    aggGlobTest " & stageName[s], NIL, ms9.num);
      <* ASSERT aggCheck(gAgg, 200) *>  scrubStack();
      INC(s); ms9.wait(s);
      INC(s); WHILE ms9.stage < s DO INC(spinner) END;
      <* ASSERT aggCheck(gAgg, 200) *>  scrubStack();
    END;
    ms9.wait(Stage.finish);
    loque.write("    aggGlobTest finish", ms9, ms9.num);
    loque.write("    aggGlobTest exiting", ms9, ms9.num);
  END aggGlobTest;

VAR gSrc: AggArr;

PROCEDURE aggValTest(ms9: MS9) =
  BEGIN
    aggValProc(ms9, gSrc);
  END aggValTest;

PROCEDURE aggValProc(ms9: MS9; cp: AggArr) =
  VAR spinner := 0; s := Stage.pause;
  BEGIN
    loque.write("    aggValTest started", ms9, ms9.num);
    <* ASSERT aggCheck(cp, 300) *>   (* copy-in is complete *)
    aggClear(gSrc);                  (* the global holds nothing: cp is the only holder *)
    scrubStack();
    FOR cycle := 1 TO 3 DO
      aggLog("aggVal", cp); scrubStack();
      ms9.wait(s);
      loque.write("    aggValTest " & stageName[s], NIL, ms9.num);
      <* ASSERT aggCheck(cp, 300) *>  scrubStack();
      INC(s); ms9.wait(s);
      INC(s); WHILE ms9.stage < s DO INC(spinner) END;
      <* ASSERT aggCheck(cp, 300) *>  scrubStack();
    END;
    ms9.wait(Stage.finish);
    loque.write("    aggValTest finish", ms9, ms9.num);
    loque.write("    aggValTest exiting", ms9, ms9.num);
  END aggValProc;

CONST d = ARRAY [0..9] OF TEXT {"0", "1", "2", "3", "4", "5", "6", "7", "8", "9" };

PROCEDURE Digits(i: INTEGER) : TEXT =
  VAR d1, d2 : INTEGER;
  BEGIN
    d1 := i MOD 10;
    d2 := (i DIV 10) MOD 10;
    RETURN d[d2] & d[d1];
  END Digits;

TYPE Smoke = ARRAY [1..64] OF TEXT;

PROCEDURE smokeOK(READONLY a: Smoke): BOOLEAN =
  BEGIN
    FOR i := FIRST(a) TO LAST(a) DO
      IF NOT Text.Equal(a[i], "smokeloop " & Digits(i)) THEN RETURN FALSE END;
    END;
    RETURN TRUE;
  END smokeOK;

PROCEDURE smokeTest(ms9: MS9) =
  VAR
    spinner : INTEGER := 0;
    s := Stage.pause;
    smoke : REF Smoke;
    idx : INTEGER;
  BEGIN
    loque.write("    smokeTest started", ms9, ms9.num);
    smoke := NEW(REF Smoke);
    FOR i := FIRST(smoke^) TO LAST(smoke^) DO
      smoke[i] := "smokeloop " & Digits(i);
    END;
    loque.write(smoke[64], NIL, 64);

    FOR cycle := 1 TO 3 DO
      (* pre-pause action *)
      FOR i := FIRST(smoke^) TO LAST(smoke^) DO
        smoke[i] := "smokeloop " & Digits(i);
      END;
      loque.write(smoke[64], NIL, 64);

      (* pause cycle*)
      ms9.wait(s);
      loque.write("    smokeTest " & stageName[s], NIL, ms9.num);
      <*ASSERT smokeOK(smoke^) *>

      (* edge cycle *)
      INC(s);
      ms9.wait(s);
      loque.write("    smokeTest " & stageName[s], NIL, ms9.num);
      <*ASSERT smokeOK(smoke^) *>

      INC(s);
      idx := 0;
      WHILE ms9.stage < s DO
        INC(spinner);
        INC(idx);
        IF idx > 64 THEN idx := 1; END;
        smoke[idx] := "smokeloop " & Digits(idx);
      END;

      (* post-edge action *)
      loque.write("    smokeTest " & stageName[s], NIL, -1, spinner);
      loque.write(smoke[idx], NIL, idx);
      <*ASSERT smokeOK(smoke^) *>

    END;

    ms9.wait(Stage.finish);
    loque.write("    smokeTest finish", ms9, ms9.num);
    loque.write("    smokeTest exiting", ms9, ms9.num);    
  END smokeTest;


(* MS9 Test Driver*)
CONST NTEST = 12;
VAR subject : ARRAY [0..NTEST-1] OF MS9;

PROCEDURE mainMS9() =
  VAR s := Stage.pause;
  BEGIN
    loque.write("mainMS9 BEGIN", NIL, -1);

    (* Create *)
    subject[0]:= NewMS9(smokeTest);
    subject[1]:= NewMS9(intTest);
    subject[2]:= NewMS9(pageTest);
    subject[3]:= NewMS9(aggLocTest);
    subject[4]:= NewMS9(aggGlobTest);
    subject[5]:= NewMS9(aggValTest);
    subject[6]:= NewMS9(valTest);
    subject[7]:= NewMS9(multiTest);
    subject[8]:= NewMS9(valMultiTest);
    subject[9]:= NewMS9(smokeTest);
    subject[10]:= NewMS9(smokeTest);
    subject[11]:= NewMS9(smokeTest);
    loque.write("  mainMS9 tests created", NIL, NTEST);

    (* Start *)
    FOR i := 0 TO NTEST-1 DO
      subject[i].advance(Stage.start);
      loque.write("  mainMS9 start", subject[i], i+1);
    END;
    Thread.Pause(0.5D0);
(*    logMov(subject[7].num); *)
    scrubStack();

    (* Three cycles of collection pairs *)
    FOR cycle := 1 TO 3 DO
      FOR j := 1 TO 2 DO 
        Thread.Pause(0.5D0);
        loque.write("  mainMS9 " & stageName[s], NIL, -1);
        FOR i := 0 TO NTEST-1 DO
          subject[i].advance(s);
        END;

        Thread.Pause(0.5D0);
        RTCollector.Collect();
        loque.write("+GC", NIL, WThread.GC);
(*        logMov(subject[7].num); *)
        scrubStack();
        INC(s);
      END;
    END;

    (* Finish *)
    FOR i := 0 TO NTEST-1 DO
      subject[i].advance(Stage.finish);
      loque.write("  mainMS9 finish", subject[i], i+1);
    END;
    Thread.Pause(0.5D0);

    (* Join *)
    FOR i := 0 TO NTEST-1 DO
      EVAL Thread.Join(subject[i].thread);
      loque.write("  mainMS9 joined", subject[i], i+1);
    END;

    loque.write("mainMS9 END", NIL, -1);
  END mainMS9;

PROCEDURE burnPage(p: INTEGER) =
  VAR pg := Word.RightShift(p, 16); x: Pad; y: PadB; n := 0;
  BEGIN
    REPEAT
      x := NEW(Pad); y := NEW(PadB); INC(n);
    UNTIL (Word.RightShift(LOOPHOLE(x, INTEGER), 16) # pg
       AND Word.RightShift(LOOPHOLE(y, INTEGER), 16) # pg) OR n > 5000;
  END burnPage;

PROCEDURE initMS9() =
  BEGIN
    smOne := NEW(REF ARRAY [1..SM_SIZE] OF R);
    lgOne := NEW(REF ARRAY [1..LG_SIZE] OF R);
    smTwo := NEW(REF ARRAY OF R, SM_SIZE);
    lgTwo := NEW(REF ARRAY OF R, LG_SIZE);
    smObj := NEW(REF ARRAY OF obj, SM_SIZE);
    lgObj := NEW(REF ARRAY OF obj, LG_SIZE);
    smRec := NEW(REF ARRAY OF recR, SM_SIZE);
    lgRec := NEW(REF ARRAY OF recR, LG_SIZE);
    smInt := NEW(REF ARRAY OF INTEGER, SM_SIZE);
    lgInt := NEW(REF ARRAY OF INTEGER, LG_SIZE);
    withAlias := NEW(REF ARRAY OF Byte, 40000);
    subAlias  := NEW(REF ARRAY OF Byte, 40000);
    tailAlias := NEW(REF ARRAY OF Byte, 80000);
    smVal := NEW(REF ARRAY OF Byte, 40000);
    smValKeep := smVal;
    loque.write("++smValKeep", NIL, -1, Word.Not(LOOPHOLE(smValKeep, INTEGER)));
    lgVal := NEW(REF ARRAY OF Byte, 80000);
    oneMulti := NEW(REF ARRAY OF ARRAY [1..SM_SIZE] OF Byte, OM_SIZE);
    burnPage(LOOPHOLE(oneMulti,INTEGER));
    twoMulti := NEW(REF ARRAY OF ARRAY OF ARRAY [1..SM_SIZE] OF Byte, MULTI_SIZE, K_SIZE);
    impMulti := NEW(REF ARRAY OF ARRAY OF R, IMP1_SIZE, IMP2_SIZE);
    valMultiInit();
    aggInit(gAgg, 200);
    burnPage(LOOPHOLE(gAgg[2].node.next,INTEGER));
    aggInit(gSrc, 300);
    setupRef(smOne, lgOne, smTwo, lgTwo);
  END initMS9;

BEGIN
  loque := Loque.Open();
  initMS9();
  scrubStack();
  mainMS9();
  Thread.Pause(0.5D0);
  loque.close();
END Main.