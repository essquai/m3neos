UNSAFE MODULE Loque;

IMPORT Thread;
IMPORT RTIO;

CONST NLOQUE = 255;

REVEAL
  T = Public BRANDED "Log Queue" OBJECT
    ctx : Thread.T;
    mut : MUTEX;
    queued : Thread.Condition;

    first : INTEGER;
    last  : INTEGER;
    msg   : ARRAY [0..NLOQUE] OF RECORD t : TEXT; a : ROOT; n : INTEGER; b : INTEGER; END;
  OVERRIDES
    apply := Apply;
    write := Write;
    close := Close;
  END;

PROCEDURE Open() : T =
  VAR t : T;
  BEGIN
    t := NEW(T);
    t.mut := NEW(MUTEX);
    t.queued := NEW(Thread.Condition);
    t.ctx := Thread.Fork(t);
    RETURN t;
  END Open;

PROCEDURE Write(q : T; t : TEXT; a : ROOT; n : INTEGER; b : INTEGER := 0) = 
  VAR idx : INTEGER;
  BEGIN
    Thread.Acquire(q.mut);
    idx := q.last;
    Next(q.last);
    q.msg[idx].t := t;
    q.msg[idx].a := a;
    q.msg[idx].n := n;
    q.msg[idx].b := b;
    Thread.Release(q.mut);
    Thread.Signal(q.queued);
  END Write;

PROCEDURE Close(q : T) =
  BEGIN
    Thread.Alert(q.ctx);
    EVAL Thread.Join(q.ctx);
  END Close;

PROCEDURE Next(VAR idx : INTEGER) =
  BEGIN
    idx := (idx + 1) MOD NLOQUE;
  END Next;

PROCEDURE Apply(q : T) : REFANY =
  VAR
    alerted := FALSE;
    idx : INTEGER;
    t : TEXT;
    a : ROOT;
    n : INTEGER;
    b : INTEGER;
  BEGIN
    RTIO.PutText("Loque start\n"); RTIO.Flush();
    WHILE NOT alerted DO
      idx := -1;

      (* grab the message *)
      Thread.Acquire(q.mut);
      IF q.first = q.last THEN
        TRY
          Thread.AlertWait(q.mut, q.queued);
        EXCEPT
          Thread.Alerted =>
            RTIO.PutText("Loque.Apply alerted\n"); RTIO.Flush();
            alerted := TRUE;
        END;
      END;
      IF q.first # q.last THEN
        idx := q.first;
        t := q.msg[idx].t; q.msg[idx].t := NIL;
        a := q.msg[idx].a; q.msg[idx].a := NIL;
        n := q.msg[idx].n; q.msg[idx].n := 0;
        b := q.msg[idx].b; q.msg[idx].b := 0;
        Next(q.first);
      END;
      Thread.Release(q.mut);

      (* write the message *)
      IF idx >= 0 THEN
        RTIO.PutText(t);
        IF a # NIL THEN
          RTIO.PutText("|addr="); RTIO.PutAddr(LOOPHOLE(a, ADDRESS));
        END;
        IF n >= 0 THEN
          RTIO.PutText("|n="); RTIO.PutInt(n);
        END;
        IF b # 0 THEN
          RTIO.PutText("|b="); RTIO.PutHex(b);
        END;
        RTIO.PutText("\n");
        RTIO.Flush();
        t := NIL; a := NIL; n := 0; b := 0;
      END;
    END;
    RTIO.PutText("Loque end\n"); RTIO.Flush();
    RETURN NIL;
  END Apply;

BEGIN
END Loque.