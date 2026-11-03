UNSAFE MODULE Main;

IMPORT Thread, RTThread, RTOS;
IMPORT RTIO;
IMPORT M3toC;
IMPORT Word;
IMPORT RT0;

(*----------------------------------------------------------------- Debug ---*)
PROCEDURE Debug(txt : TEXT; addr : ADDRESS; p1 : INTEGER; p2 : INTEGER) =
  BEGIN
    RTIO.PutText(txt & " ");
    IF addr # NIL THEN RTIO.PutAddr(addr); RTIO.PutChar(' '); END;
    IF p1 >= 0 THEN RTIO.PutInt(p1); RTIO.PutChar(' '); END;
    IF p2 >= 0 THEN RTIO.PutInt(p2); RTIO.PutChar(' '); END;
    RTIO.PutText("\n");
    RTIO.Flush();
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
  sinkMutex : Thread.Mutex;

(*---------------------------------------------------------------- Source ---*)
(* Generates append events from source threads, controlled by govMutex/Cond  *)

CONST
  SRC_MAX   = 64;
  SRC_WRITES = 99;

TYPE
  srcctx = Thread.Closure OBJECT
    ctx : Thread.T;
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
        Thread.Pause(0.05D0);

        (* write only when gov is green *)
        Thread.Acquire(govMutex);

        (* wait for correct condition *)
        WHILE NOT gov.green DO
          Thread.Wait(govMutex, govCond);
        END;

        Thread.Acquire(sinkMutex);
        sink.append(t.idx, i);
        Thread.Release(sinkMutex);

        Thread.Release(govMutex);

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
  govctx = Thread.Closure OBJECT
    ctx    : Thread.T;
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
        Thread.Acquire(govMutex);
        t.green  := NOT t.green;
        wasGreen := t.green;
        IF t.green THEN
          (* it became green, unlock it and let sources know *)
          Debug("  gov GREEN", NIL, -1, -1);
          Thread.Release(govMutex);
          Thread.Broadcast(govCond);
        ELSE
          Debug("  gov RED", NIL, -1, -1);
        END;

        (* Leave it green or red for a while *)
        Thread.Pause(0.25D0);

        IF NOT wasGreen THEN
          (* I retained the lock on red, let it go now *)
          Thread.Release(govMutex);
        END;
    UNTIL t.joined >= t.forked;

    Debug("gov end", NIL, -1, -1);
    RETURN LOOPHOLE(t, REFANY);
  END gov_apply;

PROCEDURE GovOpen(g : govctx) =
  VAR f : INTEGER;
  BEGIN
    Thread.Acquire(govMutex);
    INC(g.forked);
    f := g.forked;
    Thread.Release(govMutex);
    Debug("  gov open (forked)", NIL, f, -1);
  END GovOpen;

PROCEDURE GovClose(g : govctx) =
  VAR f : INTEGER;
  BEGIN
    Thread.Acquire(govMutex);
    INC(g.joined);
    f := g.joined;
    Thread.Release(govMutex);
    Debug("  gov close (joined)", NIL, f, -1);
  END GovClose;


VAR
  gov      : govctx;
  govMutex : Thread.Mutex;
  govCond  : Thread.Condition;



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
    sinkMutex := NEW(Thread.Mutex);

    gov := NEW(govctx, green := FALSE); (* flips true immediately *)
    govMutex := NEW(Thread.Mutex);
    govCond  := NEW(Thread.Condition);

    gov.ctx := Thread.Fork(gov);
    Debug("testGov === START ===", NIL, -1, -1);


    FOR i := 0 TO handfull DO
        source[i] := NEW(srcctx, idx := i + 32);
        Debug("  testGov create src (addr, seq)", LOOPHOLE(source[i],ADDRESS), i, -1);

        source[i].ctx := Thread.Fork(source[i]);
        Debug("  testGov fork src (seq)", NIL, i, -1);
    END;

    Debug("  testGov pre Join", NIL, -1, -1);
    r := Thread.Join(gov.ctx);
    Debug("  testGov post Join", NIL, -1, -1);

    FOR i := 0 TO handfull DO
      Debug("  testGov join src (r, i)", LOOPHOLE(r, ADDRESS), i, -1);
        r := Thread.Join(source[i].ctx);
    END;

    Debug("testGov === RESULT ===", NIL, -1, -1);
    FOR i := 0 TO handfull DO
      Debug("  sequence(i, sink)", NIL, i+32, sink.sequence(i+32))
    END;
  END testGov;

(*------------------------------------------------------------------ ping ---*)
TYPE
  pingctx = Thread.Closure OBJECT
    ctx : Thread.T;
    pinging : BOOLEAN;
  OVERRIDES
    apply := ping_apply;
  END;

PROCEDURE ping_apply(t : pingctx) : REFANY =
  BEGIN
    Debug("ping start", NIL, -1, -1);

    (* make pauses *)
    FOR i := 0 TO 7 DO
        Thread.Pause(0.5D0);

        (* send the alert *)
        Thread.Alert(t.ctx);
        Debug("  ping send alert (i)", NIL, i, -1);
    END;

    t.pinging := FALSE;
    Thread.Pause(0.001D0);
    Debug("ping end", NIL, -1, -1);

    RETURN NIL;
  END ping_apply;



(*-------------------------------------------------------------- testAttn ---*)
PROCEDURE testAttn() =
  VAR
    joined := FALSE;
    p : pingctx;
    r : REFANY;
    pthr : Thread.T;
    a : BOOLEAN;
  BEGIN
    Debug("testAttn === START ===", NIL, -1, -1);

    p := NEW(pingctx, ctx := Thread.Self());
    p.pinging := TRUE;
    pthr := Thread.Fork(p);

    (* catch three alerts *)
    FOR i := 0 TO 2 DO
        Thread.Pause(0.75D0);
        a := Thread.TestAlert();
        Debug("  testAttn TestAlert(seq, alert)", NIL, i, ORD(a));
    END;

    (* catch alerts until joined *)
    WHILE NOT joined AND p.pinging DO
      TRY
        r := Thread.AlertJoin(pthr);
        joined := TRUE;
        Debug("  testAttn join ping thread", NIL, -1, -1);
      EXCEPT
        Thread.Alerted =>
          Debug("AlertJoin Alerted\n", NIL, -1, -1);
      END;
    END;

    Debug("testAttn === RESULT ===", NIL, -1, -1);
  END testAttn;

(*------------------------------------------------------------------ ping ---*)
TYPE
  manctx = Thread.Closure OBJECT
    ctx : Thread.T;
    idx : INTEGER;
    run : BOOLEAN;
  OVERRIDES
    apply := manuel_apply;
  END;

VAR
  manuelMutex : Thread.Mutex;
  manuelCond  : Thread.Condition;
  manuel : ARRAY [1..6] OF manctx;

PROCEDURE manuel_apply(t : manctx) : REFANY =
  VAR waitOnly := TRUE; a : BOOLEAN;
  BEGIN
    Debug("manuel start (idx)", NIL, t.idx, -1);

    (* alternate waits *)
    WHILE t.run DO
      a := FALSE;
      Thread.Acquire(manuelMutex);
      IF waitOnly THEN
        Debug("  manuel Wait --> (idx)", NIL, t.idx, -1);
        Thread.Wait(manuelMutex, manuelCond);
      ELSE
        Debug("  manuel Alert --> (idx)", NIL, t.idx, -1);
        TRY 
          Thread.AlertWait(manuelMutex, manuelCond);
        EXCEPT
          Thread.Alerted => a := TRUE;
        END;
      END;
      Thread.Release(manuelMutex);

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
    manuelMutex := NEW(Thread.Mutex);
    manuelCond := NEW(Thread.Condition);
    FOR i := 1 TO 6 DO
      manuel[i] := NEW(manctx, idx := i, run := TRUE);
      manuel[i].ctx := Thread.Fork(manuel[i]);
    END;
    Debug("  testBasil sent manuels", NIL, -1, -1);

    (* send alert/signal pairs, or broadcasts *)
    FOR i := 1 TO 11 DO
        Thread.Pause(0.25D0);
        IF Word.And(i,1) = 1 THEN
          aIdx := (i + 1) DIV 2;
          Thread.Alert(manuel[aIdx].ctx);
          Thread.Signal(manuelCond);
          Debug("  testBasil signal and alert (idx)", NIL, aIdx, -1);
        ELSE
          aIdx := 6 - (i DIV 2);
          Thread.Alert(manuel[aIdx].ctx);
          Thread.Broadcast(manuelCond);
          Debug("  testBasil signal and broadcast (idx)", NIL, aIdx, -1);
        END;
    END;

    (* stop running *)
    FOR i := 1 TO 6 DO
      manuel[i].run := FALSE;
    END;
    Debug("  testBasil run set FALSE", NIL, -1, -1);

    Thread.Pause(0.1D0);
    FOR i := 1 TO 3 DO
      Debug("  testBasil POST pause (num)", NIL, i, -1);
      Thread.Pause(0.250D0);
      Debug("  testBasil POST alert (num)", NIL, i, -1);
      FOR j := 1 TO 6 DO
          Thread.Alert(manuel[j].ctx);
      END;
      Debug("  testBasil POST broadcast (num)", NIL, i, -1);
      Thread.Broadcast(manuelCond);
    END;


    (* Join them back to me *)
    FOR i := 1 TO 6 DO
      Debug("  testBasil join pre (man) ", NIL, i, -1);
      EVAL Thread.Join(manuel[i].ctx);
      Debug("  testBasil join post (man) ", NIL, i, -1);
    END;

    Debug("testBasil === RESULT ===", NIL, -1, -1);
  END testBasil;

(*------------------------------------------------------------- testSybil ---*)
PROCEDURE testSybil() =
  BEGIN
    Debug("testSybil === START ===", NIL, -1, -1);

    (* spawn 6 waiters called manuel *)
    manuelMutex := NEW(Thread.Mutex);
    manuelCond := NEW(Thread.Condition);
    FOR i := 1 TO 6 DO
      manuel[i] := NEW(manctx, idx := i, run := TRUE);
      manuel[i].ctx := Thread.Fork(manuel[i]);
    END;
    Debug("  testSybil sent manuels", NIL, -1, -1);

    (* send alert/signal pairs, or broadcasts *)
    FOR i := 1 TO 11 DO
        Thread.Pause(0.15D0);
        IF Word.And(i,1) = 1 THEN
          Thread.Signal(manuelCond);
          Debug("  testSybil signal (seq)", NIL, i, -1);
        ELSE
          Thread.Broadcast(manuelCond);
          Debug("  testSybil broadcast (seq)", NIL, i, -1);
        END;
    END;

    (* stop running *)
    FOR i := 1 TO 6 DO
      manuel[i].run := FALSE;
    END;
    Debug("  testSybil run set FALSE", NIL, -1, -1);

    Thread.Pause(0.5D0);
    FOR i := 1 TO 3 DO
      Debug("  testSybil POST pause (num)", NIL, i, -1);
      Thread.Pause(0.25D0);
      Debug("  testSybil POST broadcast (num)", NIL, i, -1);
      Thread.Broadcast(manuelCond);
    END;


    (* Join them back to me *)
    Debug("  testSybil join entry", NIL, -1, -1);
    FOR i := 1 TO 6 DO
      Debug("  testSybil join pre (man) ", NIL, i, -1);
      EVAL Thread.Join(manuel[i].ctx);
      Debug("  testSybil join post (man) ", NIL, i, -1);
    END;

    Debug("testSybil === RESULT ===", NIL, -1, -1);
  END testSybil;

(*------------------------------------------------------------------ heap ---*)
TYPE
  heapctx = Thread.Closure OBJECT
    ctx : Thread.T;
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
      RTOS.LockHeap();
      FOR m := 1 TO 3 DO
        Debug("  heap Locked (idx, seq)", LOOPHOLE(t.idx,ADDRESS), i, m);
        Thread.Pause(0.15D0);
        (*RTOS.WaitHeap();*)
      END;
      RTOS.UnlockHeap();
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
      heap[i].ctx := Thread.Fork(heap[i]);
    END;
    Debug("  testHeap sent heaps", NIL, -1, -1);

    (* alternate between RED and GREEN *)
    WHILE run DO

      IF green THEN
        Debug("testHeap GREEN", NIL, -1, -1);
        Thread.Pause(0.5D0);
      ELSE
        RTOS.LockHeap();
        Debug("testHeap RED 1", NIL, -1, -1);
        Thread.Pause(0.1D0);
        RTOS.LockHeap();
        Debug("     ... RED 2", NIL, -1, -1);

        RTOS.UnlockHeap();
        RTOS.UnlockHeap();
        RTOS.BroadcastHeap();
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
      EVAL Thread.Join(heap[i].ctx);
      Debug("  testHeap join post (man) ", NIL, i, -1);
    END;

    Debug("testHeap === END ===", NIL, -1, -1);
  END testHeap;

(*------------------------------------------------------------- collector ---*)
TYPE
  collctx = Thread.Closure OBJECT
    ctx : Thread.T;
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
      RTThread.SuspendOthers();
      Debug("  <-- coll suspend (idx,seq)", NIL, t.idx, i);
      Thread.Pause(0.0001D0);
      Debug("  --> coll resume (idx,seq)", NIL, t.idx, i);
      RTThread.ResumeOthers();
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
      coll[i].ctx := Thread.Fork(coll[i]);
    END;
    Debug("  testColl sent collectorss", NIL, -1, -1);

    (* Join them back to me *)
    Debug("  testColl join entry", NIL, -1, -1);
    FOR i := 1 TO collCount DO
      Debug("  testColl join pre (idx) ", NIL, i, -1);
      EVAL Thread.Join(coll[i].ctx);
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

    (* testColl(); *)

    Debug("mainMS2 END", NIL, -1, -1);
    RETURN NIL;
  END mainMS2;

BEGIN
  EVAL mainMS2(0);
END Main.