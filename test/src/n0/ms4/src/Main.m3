MODULE Main;

IMPORT RT0;

PROCEDURE lpWhile(n: INTEGER): INTEGER =
  VAR i, s: INTEGER := 0;
  BEGIN WHILE i < n DO s := s + i; INC(i) END; RETURN s END lpWhile;

PROCEDURE lpRepeat(n: INTEGER): INTEGER =
  VAR i: INTEGER := 0;
  BEGIN REPEAT INC(i) UNTIL i >= n; RETURN i END lpRepeat;

PROCEDURE lpLoopExit(n: INTEGER): INTEGER =
  VAR i: INTEGER := 0;
  BEGIN LOOP IF i >= n THEN EXIT END; INC(i) END; RETURN i END lpLoopExit;

PROCEDURE lpForUp(n: INTEGER): INTEGER =
  VAR s: INTEGER := 0;
  BEGIN FOR i := 1 TO n DO s := s + i END; RETURN s END lpForUp;

PROCEDURE lpForDown(n: INTEGER): INTEGER =
  VAR s: INTEGER := 0;
  BEGIN FOR i := n TO 1 BY -1 DO s := s + i END; RETURN s END lpForDown;

PROCEDURE lpNested(n: INTEGER): INTEGER =   (* EXIT leaves only the inner loop *)
  VAR s: INTEGER := 0;
  BEGIN
    FOR i := 1 TO n DO LOOP INC(s); IF s MOD 3 = 0 THEN EXIT END END END;
    RETURN s
  END lpNested;

PROCEDURE lpReturnIn(n: INTEGER): INTEGER =  (* RETURN from inside a loop *)
  BEGIN
    WHILE TRUE DO IF n > 10 THEN RETURN n END; INC(n) END;
    RETURN 0
  END lpReturnIn;

PROCEDURE lpAlloc(n: INTEGER): INTEGER =     (* roots and safepoints inside a loop *)
  VAR r: REF INTEGER; s: INTEGER := 0;
  BEGIN
    FOR i := 1 TO n DO r := NEW(REF INTEGER); r^ := i; s := s + r^ END;
    RETURN s
  END lpAlloc;

PROCEDURE lpForWhile(n: INTEGER): INTEGER =
  VAR s, j: INTEGER := 0;
  BEGIN
    FOR i := 1 TO n DO j := i; WHILE j > 0 DO s := s + j; DEC(j) END END;
    RETURN s
  END lpForWhile;

PROCEDURE lpWhileFor(n: INTEGER): INTEGER =
  VAR s, i: INTEGER := 0;
  BEGIN
    WHILE i < n DO FOR k := 1 TO i DO s := s + k END; INC(i) END;
    RETURN s
  END lpWhileFor;

PROCEDURE lpWhileIf(n: INTEGER): INTEGER =
  VAR s, i: INTEGER := 0;
  BEGIN
    WHILE i < n DO
      IF i MOD 2 = 0 THEN s := s + i ELSE s := s - 1 END;
      INC(i)
    END;
    RETURN s
  END lpWhileIf;

PROCEDURE lpRepeatIf(n: INTEGER): INTEGER =
  VAR s, i: INTEGER := 0;
  BEGIN
    REPEAT IF i MOD 3 = 0 THEN s := s + i END; INC(i) UNTIL i >= n;
    RETURN s
  END lpRepeatIf;

PROCEDURE lpWhileElsif(n: INTEGER): INTEGER =
  VAR s, i: INTEGER := 0;
  BEGIN
    WHILE i < n DO
      IF i MOD 3 = 0 THEN s := s + 1 ELSIF i MOD 3 = 1 THEN s := s + 2 ELSE s := s + 3 END;
      INC(i)
    END;
    RETURN s
  END lpWhileElsif;

PROCEDURE phaseB(<*UNUSED*> mode : INTEGER) : RT0.ModulePtr =
  VAR r : INTEGER; n := 3;
  BEGIN
    r := lpWhile(n);
    r := lpRepeat(n);
    r := lpLoopExit(n);
    r := lpForUp(n);
    r := lpForDown(n);
    r := lpNested(n);
    r := lpReturnIn(n);
    r := lpAlloc(n);
    r := lpForWhile(n);
    r := lpWhileFor(n);
    r := lpWhileIf(n);
    r := lpRepeatIf(n);
    r := lpWhileElsif(n);
    RETURN NIL;
  END phaseB;

BEGIN
  EVAL phaseB(0);
END Main.
