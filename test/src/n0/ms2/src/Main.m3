UNSAFE MODULE Main;

IMPORT auxThread, auxRTThread, auxRTOS;
FROM   WThread IMPORT thread_print;
IMPORT M3toC;
IMPORT Word;
IMPORT RT0;

(*----------------------------------------------------------------- Debug ---*)
PROCEDURE Debug(txt : TEXT; addr : ADDRESS; p1 : INTEGER; p2 : INTEGER) =
  BEGIN
    thread_print(M3toC.FlatTtoS(txt), addr, p1, p2);
  END Debug;


(*------------------------------------------------------------------ Sink ---*)
(* Receives append events from source writer threads with sinkMutex locking  *)

CONST SINK_MAX = 64 * 1024;
TYPE
  Sink = UNTRACED ROOT OBJECT
    num : INTEGER;
    content : ARRAY [0..SINK_MAX] OF
                 RECORD
                    id  : INTEGER;
                    seq : INTEGER;
                 END;
  METHODS
    append(idx: INTEGER; seq: INTEGER) := SinkAppend;
    sequence(idx : INTEGER) : INTEGER := SinkSequence;
  END;

PROCEDURE SinkAppend(s : Sink; idx : INTEGER; seq : INTEGER) =
  BEGIN
    s.content[s.num].id := idx;
    s.content[s.num].seq := seq;
    INC(s.num);
  END SinkAppend;

PROCEDURE SinkSequence(s : Sink; idx : INTEGER) : INTEGER =
  VAR seq := 0;
  BEGIN
    FOR i := 0 TO s.num-1 DO
      IF s.content[i].id = idx THEN
        IF seq = s.content[i].seq THEN
          INC(seq);
        ELSE
          seq := -1;
          EXIT;
        END;
      END;
    END;
    RETURN seq;
  END SinkSequence;

VAR
  sink : Sink;
  sinkMutex : auxThread.Mutex;

(*---------------------------------------------------------------- Source ---*)
(* Generates append events from source threads, controlled by govMutex/Cond  *)

CONST
  SRC_MAX   = 64;
  SRC_WRITES = 99;

TYPE
  srcctx = auxThread.Closure OBJECT
    ctx : auxThread.T;
    idx : INTEGER;
  OVERRIDES
    apply := src_apply;
  END;

VAR source : ARRAY [0 .. SRC_MAX] OF srcctx;

PROCEDURE src_apply(t : srcctx) : REFANY =
  BEGIN
    Debug("src start (tidx)", NIL, t.idx, -1);

    gov.open();

    (* make pauses *)
    FOR i := 0 TO SRC_WRITES DO
        auxThread.Pause(0.05D0);

        (* write only when gov is green *)
        auxThread.Acquire(govMutex);

        (* wait for correct condition *)
        WHILE NOT gov.green DO
          auxThread.Wait(govMutex, govCond);
        END;

        auxThread.Acquire(sinkMutex);
        sink.append(t.idx, i);
        auxThread.Release(sinkMutex);

        auxThread.Release(govMutex);

        IF i MOD 16 = 0 THEN
          Debug("  src progress (tidx, write)", NIL, t.idx, i);
        END;
    END;

    Debug("src end (tidx)", NIL, t.idx, -1);

    gov.close();


    RETURN LOOPHOLE(t, REFANY);
  END src_apply;

(*------------------------------------------------------------------- Gov ---*)
(* Alternate the green light until all sources are completed                 *)

TYPE
  govctx = auxThread.Closure OBJECT
    ctx    : auxThread.T;
    green  : BOOLEAN;
    forked : INTEGER;
    joined : INTEGER;
  METHODS
    open()  := GovOpen;
    close() := GovClose;
  OVERRIDES
    apply := gov_apply;
  END;

PROCEDURE gov_apply(t : govctx) : REFANY =
  VAR wasGreen : BOOLEAN;
  BEGIN
    Debug("gov start", NIL, -1, -1);

    (* make pauses *)
    REPEAT
        auxThread.Acquire(govMutex);
        t.green  := NOT t.green;
        wasGreen := t.green;
        IF t.green THEN
          (* it became green, unlock it and let sources know *)
          Debug("  gov GREEN", NIL, -1, -1);
          auxThread.Release(govMutex);
          auxThread.Broadcast(govCond);
        ELSE
          Debug("  gov RED", NIL, -1, -1);
        END;

        (* Leave it green or red for a while *)
        auxThread.Pause(0.25D0);

        IF NOT wasGreen THEN
          (* I retained the lock on red, let it go now *)
          auxThread.Release(govMutex);
        END;
    UNTIL t.joined >= t.forked;

    Debug("gov end", NIL, -1, -1);
    RETURN LOOPHOLE(t, REFANY);
  END gov_apply;

PROCEDURE GovOpen(g : govctx) =
  VAR f : INTEGER;
  BEGIN
    auxThread.Acquire(govMutex);
    INC(g.forked);
    f := g.forked;
    auxThread.Release(govMutex);
    Debug("  gov open (forked)", NIL, f, -1);
  END GovOpen;

PROCEDURE GovClose(g : govctx) =
  VAR f : INTEGER;
  BEGIN
    auxThread.Acquire(govMutex);
    INC(g.joined);
    f := g.joined;
    auxThread.Release(govMutex);
    Debug("  gov close (joined)", NIL, f, -1);
  END GovClose;


VAR
  gov      : govctx;
  govMutex : auxThread.Mutex;
  govCond  : auxThread.Condition;



(*--------------------------------------------------------------- testGov ---*)
(* Orchestration:
   * Launch a governor, and all sources
   * join with the governor
   * by then, all sources should be joinable
   * validate the sequences
*)

PROCEDURE testGov() = 
  VAR
    handfull := 4;
    r : REFANY;
  BEGIN
    sink := NEW(Sink);
    sinkMutex := NEW(auxThread.Mutex);

    gov := NEW(govctx, green := FALSE); (* flips true immediately *)
    govMutex := NEW(auxThread.Mutex);
    govCond  := NEW(auxThread.Condition);

    gov.ctx := auxThread.Fork(gov);
    Debug("testGov === START ===", NIL, -1, -1);


    FOR i := 0 TO handfull DO
        source[i] := NEW(srcctx, idx := i + 32);
        Debug("  testGov create src (addr, seq)", source[i], i, -1);

        source[i].ctx := auxThread.Fork(source[i]);
        Debug("  testGov fork src (seq)", NIL, i, -1);
    END;

    Debug("  testGov pre Join", NIL, -1, -1);
    r := auxThread.Join(gov.ctx);
    Debug("  testGov post Join", NIL, -1, -1);

    FOR i := 0 TO handfull DO
      Debug("  testGov join src (r, i)", LOOPHOLE(r, ADDRESS), i, -1);
        r := auxThread.Join(source[i].ctx);
    END;

    Debug("testGov === RESULT ===", NIL, -1, -1);
    FOR i := 0 TO handfull DO
      Debug("  sequence(i, sink)", NIL, i+32, sink.sequence(i+32))
    END;
  END testGov;

(*------------------------------------------------------------------ ping ---*)
TYPE
  pingctx = auxThread.Closure OBJECT
    ctx : auxThread.T;
  OVERRIDES
    apply := ping_apply;
  END;

PROCEDURE ping_apply(t : pingctx) : REFANY =
  BEGIN
    Debug("ping start", NIL, -1, -1);

    (* make pauses *)
    FOR i := 0 TO 7 DO
        auxThread.Pause(0.5D0);

        (* send the alert *)
        auxThread.Alert(t.ctx);
        Debug("  ping send alert (i)", NIL, i, -1);
    END;

    Debug("ping end", NIL, -1, -1);

    RETURN NIL;
  END ping_apply;



(*-------------------------------------------------------------- testAttn ---*)
PROCEDURE testAttn() =
  VAR
    joined := FALSE;
    p : pingctx;
    a : BOOLEAN;
    r : REFANY;
    pthr : auxThread.T;
  BEGIN
    Debug("testAttn === START ===", NIL, -1, -1);

    p := NEW(pingctx, ctx := auxThread.Self());
    pthr := auxThread.Fork(p);

    (* catch three alerts *)
    FOR i := 0 TO 2 DO
        auxThread.Pause(0.75D0);
        a := auxThread.TestAlert();
        Debug("  testAttn TestAlert(seq, alert)", NIL, i, ORD(a));
    END;

    (* catch alerts until joined *)
    WHILE NOT joined DO
(*      TRY *)
        a := FALSE;
        r := auxThread.AlertJoin(pthr, a);
        IF NOT a THEN
          joined := TRUE;
          Debug("  testAttn join ping thread", NIL, -1, -1);
        ELSE
          Debug("  testAttn alerted on ping thread", NIL, -1, -1);
        END;
      (*EXCEPT
        auxThread.Alerted =>
          Debug("AlertJoin Alerted\n");
          RTIO.Flush();
      END;*)
    END;

    Debug("testAttn === RESULT ===", NIL, -1, -1);
  END testAttn;

(*------------------------------------------------------------------ ping ---*)
TYPE
  manctx = auxThread.Closure OBJECT
    ctx : auxThread.T;
    idx : INTEGER;
    run : BOOLEAN;
  OVERRIDES
    apply := manuel_apply;
  END;

VAR
  manuelMutex : auxThread.Mutex;
  manuelCond  : auxThread.Condition;
  manuel : ARRAY [1..6] OF manctx;

PROCEDURE manuel_apply(t : manctx) : REFANY =
  VAR waitOnly := TRUE; a : BOOLEAN;
  BEGIN
    Debug("manuel start (idx)", NIL, t.idx, -1);

    (* alternate waits *)
    WHILE t.run DO
      a := FALSE;
      auxThread.Acquire(manuelMutex);
      IF waitOnly THEN
        Debug("  manuel Wait --> (idx)", NIL, t.idx, -1);
        auxThread.Wait(manuelMutex, manuelCond);
      ELSE
        Debug("  manuel Alert --> (idx)", NIL, t.idx, -1);
        auxThread.AlertWait(manuelMutex, manuelCond, a);
      END;
      auxThread.Release(manuelMutex);

      IF a THEN
        Debug("    manuel Alerted <-- (idx)", NIL, t.idx, -1);
      ELSE
        Debug("    manuel Waited <-- (idx)", NIL, t.idx, -1);
      END;
      waitOnly := NOT waitOnly;
    END;

    Debug("manuel end (idx)", NIL, t.idx, -1);

    RETURN NIL;
  END manuel_apply;

(*------------------------------------------------------------- testBasil ---*)
PROCEDURE testBasil() =
  VAR aIdx : INTEGER;
  BEGIN
    Debug("testBasil === START ===", NIL, -1, -1);

    (* spawn 6 waiters called manuel *)
    manuelMutex := NEW(auxThread.Mutex);
    manuelCond := NEW(auxThread.Condition);
    FOR i := 1 TO 6 DO
      manuel[i] := NEW(manctx, idx := i, run := TRUE);
      manuel[i].ctx := auxThread.Fork(manuel[i]);
    END;
    Debug("  testBasil sent manuels", NIL, -1, -1);

    (* send alert/signal pairs, or broadcasts *)
    FOR i := 1 TO 11 DO
        auxThread.Pause(0.25D0);
        IF Word.And(i,1) = 1 THEN
          aIdx := (i + 1) DIV 2;
          auxThread.Alert(manuel[aIdx].ctx);
          auxThread.Signal(manuelCond);
          Debug("  testBasil signal and alert (idx)", NIL, aIdx, -1);
        ELSE
          aIdx := 6 - (i DIV 2);
          auxThread.Alert(manuel[aIdx].ctx);
          auxThread.Broadcast(manuelCond);
          Debug("  testBasil signal and broadcast (idx)", NIL, aIdx, -1);
        END;
    END;

    (* stop running *)
    FOR i := 1 TO 6 DO
      manuel[i].run := FALSE;
    END;
    Debug("  testBasil run set FALSE", NIL, -1, -1);

    auxThread.Pause(0.1D0);
    FOR i := 1 TO 3 DO
      Debug("  testBasil POST pause (num)", NIL, i, -1);
      auxThread.Pause(0.250D0);
      Debug("  testBasil POST alert (num)", NIL, i, -1);
      FOR j := 1 TO 6 DO
          auxThread.Alert(manuel[j].ctx);
      END;
      Debug("  testBasil POST broadcast (num)", NIL, i, -1);
      auxThread.Broadcast(manuelCond);
    END;


    (* Join them back to me *)
    FOR i := 1 TO 6 DO
      Debug("  testBasil join pre (man) ", NIL, i, -1);
      EVAL auxThread.Join(manuel[i].ctx);
      Debug("  testBasil join post (man) ", NIL, i, -1);
    END;

    Debug("testBasil === RESULT ===", NIL, -1, -1);
  END testBasil;

(*------------------------------------------------------------- testSybil ---*)
PROCEDURE testSybil() =
  BEGIN
    Debug("testSybil === START ===", NIL, -1, -1);

    (* spawn 6 waiters called manuel *)
    manuelMutex := NEW(auxThread.Mutex);
    manuelCond := NEW(auxThread.Condition);
    FOR i := 1 TO 6 DO
      manuel[i] := NEW(manctx, idx := i, run := TRUE);
      manuel[i].ctx := auxThread.Fork(manuel[i]);
    END;
    Debug("  testSybil sent manuels", NIL, -1, -1);

    (* send alert/signal pairs, or broadcasts *)
    FOR i := 1 TO 11 DO
        auxThread.Pause(0.15D0);
        IF Word.And(i,1) = 1 THEN
          auxThread.Signal(manuelCond);
          Debug("  testSybil signal (seq)", NIL, i, -1);
        ELSE
          auxThread.Broadcast(manuelCond);
          Debug("  testSybil broadcast (seq)", NIL, i, -1);
        END;
    END;

    (* stop running *)
    FOR i := 1 TO 6 DO
      manuel[i].run := FALSE;
    END;
    Debug("  testSybil run set FALSE", NIL, -1, -1);

    auxThread.Pause(0.5D0);
    FOR i := 1 TO 3 DO
      Debug("  testSybil POST pause (num)", NIL, i, -1);
      auxThread.Pause(0.25D0);
      Debug("  testSybil POST broadcast (num)", NIL, i, -1);
      auxThread.Broadcast(manuelCond);
    END;


    (* Join them back to me *)
    Debug("  testSybil join entry", NIL, -1, -1);
    FOR i := 1 TO 6 DO
      Debug("  testSybil join pre (man) ", NIL, i, -1);
      EVAL auxThread.Join(manuel[i].ctx);
      Debug("  testSybil join post (man) ", NIL, i, -1);
    END;

    Debug("testSybil === RESULT ===", NIL, -1, -1);
  END testSybil;

(*------------------------------------------------------------------ heap ---*)
TYPE
  heapctx = auxThread.Closure OBJECT
    ctx : auxThread.T;
    idx : INTEGER;
    run : BOOLEAN;
  OVERRIDES
    apply := heap_apply;
  END;

CONST
  heapCount = 3;

VAR
  heap : ARRAY [1..heapCount] OF heapctx;

PROCEDURE heap_apply(t : heapctx) : REFANY =
  BEGIN
    Debug("heap start (idx)", NIL, t.idx, -1);

    (* alternate waits *)
    FOR i := 1 TO 5 DO
      auxRTOS.LockHeap();
      FOR m := 1 TO 3 DO
        Debug("  heap Locked (idx, seq)", LOOPHOLE(t.idx,ADDRESS), i, m);
        auxThread.Pause(0.15D0);
        (*auxRTOS.WaitHeap();*)
      END;
      auxRTOS.UnlockHeap();
    END;

    Debug("heap end (idx)", NIL, t.idx, -1);
    t.run := FALSE;

    RETURN NIL;
  END heap_apply;

(*-------------------------------------------------------------- testHeap ---*)
PROCEDURE testHeap() =
  VAR run := TRUE; green := TRUE;
  BEGIN
    Debug("testHeap === START ===", NIL, -1, -1);

    (* spawn the heaps *)
    FOR i := 1 TO heapCount DO
      heap[i] := NEW(heapctx, idx := i, run := TRUE);
      heap[i].ctx := auxThread.Fork(heap[i]);
    END;
    Debug("  testHeap sent heaps", NIL, -1, -1);

    (* alternate between RED and GREEN *)
    WHILE run DO

      IF green THEN
        Debug("testHeap GREEN", NIL, -1, -1);
        auxThread.Pause(0.5D0);
      ELSE
        auxRTOS.LockHeap();
        Debug("testHeap RED 1", NIL, -1, -1);
        auxThread.Pause(0.1D0);
        auxRTOS.LockHeap();
        Debug("     ... RED 2", NIL, -1, -1);

        auxRTOS.UnlockHeap();
        auxRTOS.UnlockHeap();
        auxRTOS.BroadcastHeap();
      END;

      (* set the conditions for the next go round *)
      green := NOT green;
      run := FALSE;
      FOR i := 1 TO heapCount DO
        IF heap[i].run THEN run := TRUE; END;
      END;
    END;


    (* Join them back to me *)
    Debug("  testHeap join entry", NIL, -1, -1);
    FOR i := 1 TO heapCount DO
      Debug("  testHeap join pre (man) ", NIL, i, -1);
      EVAL auxThread.Join(heap[i].ctx);
      Debug("  testHeap join post (man) ", NIL, i, -1);
    END;

    Debug("testHeap === END ===", NIL, -1, -1);
  END testHeap;

(*------------------------------------------------------------- collector ---*)
TYPE
  collctx = auxThread.Closure OBJECT
    ctx : auxThread.T;
    idx : INTEGER;
  OVERRIDES
    apply := coll_apply;
  END;

CONST
  collCount = 3;

VAR
  coll : ARRAY [1..collCount] OF collctx;

PROCEDURE coll_apply(t : collctx) : REFANY =
  BEGIN
    Debug("coll start (idx)", NIL, t.idx, -1);

    (* get a dozen suspensions *)
    FOR i := 1 TO 12 DO
      Debug("  coll loop (idx,seq)", NIL, t.idx, i);
      auxRTThread.SuspendOthers();
      Debug("  <-- coll suspend (idx,seq)", NIL, t.idx, i);
      auxThread.Pause(0.0001D0);
      Debug("  --> coll resume (idx,seq)", NIL, t.idx, i);
      auxRTThread.ResumeOthers();
    END;

    Debug("coll end (idx)", NIL, t.idx, -1);

    RETURN NIL;
  END coll_apply;

(*---------------------------------------------------------- testRTThread ---*)
PROCEDURE testColl() =
  BEGIN
    Debug("testColl === START ===", NIL, -1, -1);

    (* spawn the mutators *)
    FOR i := 1 TO collCount DO
      coll[i] := NEW(collctx, idx := i);
      coll[i].ctx := auxThread.Fork(coll[i]);
    END;
    Debug("  testColl sent collectorss", NIL, -1, -1);

    (* Join them back to me *)
    Debug("  testColl join entry", NIL, -1, -1);
    FOR i := 1 TO collCount DO
      Debug("  testColl join pre (idx) ", NIL, i, -1);
      EVAL auxThread.Join(coll[i].ctx);
      Debug("  testColl join post (idx) ", NIL, i, -1);
    END;

    Debug("testColl === END ===", NIL, -1, -1);
  END testColl;


PROCEDURE mainMS2(<*UNUSED*> mode : INTEGER) : RT0.ModulePtr =
  BEGIN
    Debug("mainMS2 BEGIN", NIL, -1, -1);

    testGov();
    testAttn();
    testBasil();
    testSybil();
    testHeap();

    testColl();

    Debug("mainMS2 END", NIL, -1, -1);
    RETURN NIL;
  END mainMS2;

BEGIN
  auxRTThread.Init();
  auxRTThread.InitialThread(mainMS2);
END Main.