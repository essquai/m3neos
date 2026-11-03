UNSAFE MODULE Main;

IMPORT auxThread;
IMPORT Word;
IMPORT RTIO;

CONST
  THR_MAX = 64;

TYPE
  Wctx = auxThread.Closure OBJECT
    ctx : auxThread.T;
    idx : INTEGER;
  OVERRIDES
    apply := wait_apply;
  END;

  
VAR wctxt : ARRAY [0 .. THR_MAX-1] OF Wctx;

PROCEDURE wait_apply(t : Wctx) : REFANY =
  VAR count := 16;
  BEGIN
    RTIO.PutText("wait_apply start ");
    RTIO.PutInt(t.idx);
    RTIO.PutText(" self=");
    RTIO.PutHex(LOOPHOLE(auxThread.Self(),INTEGER));
    RTIO.PutText(" ctx=");
    RTIO.PutHex(LOOPHOLE(t.ctx,INTEGER));
    RTIO.PutText("\n");
    RTIO.Flush();

    (* make pauses *)
    IF Word.And(t.idx, 1) = 0 THEN count := 10; END;
    FOR i := 0 TO count DO
        auxThread.Pause(0.1D0);

        RTIO.PutText("dot(");
        RTIO.PutInt(t.idx);
        RTIO.PutText(",");
        RTIO.PutInt(i);
        RTIO.PutText(")\n");
        RTIO.Flush();
    END;

    RTIO.PutText("wait_apply end ");
    RTIO.PutInt(t.idx);
    RTIO.PutText("\n");
    RTIO.Flush();
    RETURN t;
  END wait_apply;
 
PROCEDURE main() = 
  VAR
    handfull := 4;
    r : REFANY;
  BEGIN
    FOR i := 0 TO handfull DO
        wctxt[i] := NEW(Wctx, idx := i);
        RTIO.PutText("main ");
        RTIO.PutHex(LOOPHOLE(wctxt[i],INTEGER));
        RTIO.PutText("\n");
        RTIO.Flush();

        wctxt[i].ctx := auxThread.Fork(wctxt[i]);
        RTIO.PutText("Forked ");
        RTIO.PutInt(wctxt[i].idx);
        RTIO.PutText("\n");
        RTIO.Flush();

    END;
    FOR i := 0 TO handfull DO
        RTIO.PutText("Join ");
        RTIO.PutInt(i);
        RTIO.PutText(" r=");
        RTIO.PutHex(LOOPHOLE(r,INTEGER));
        RTIO.PutText("\n");
        RTIO.Flush();
        r := auxThread.Join(wctxt[i].ctx);
    END;
  END main;

BEGIN
  main();
END Main.