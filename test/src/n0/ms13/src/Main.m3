MODULE Main;

(* Exceptions on wasm32.  EXCEPT and FINALLY, raised in the same procedure and
   across frames, plus a traced REF (a gcroot) that is live in a procedure
   that also contains a TRY inside a loop.  Failures stop in an assertion. *)

EXCEPTION E1;  E2 (INTEGER);

VAR
  trace: INTEGER := 0;               (* counts FINALLY blocks that ran *)
  got, a, b, c, d, f: INTEGER := 0;

PROCEDURE Raise1 () RAISES {E1} =
  BEGIN
    RAISE E1;
  END Raise1;

PROCEDURE Raise2 (n: INTEGER) RAISES {E2} =
  BEGIN
    RAISE E2 (n);
  END Raise2;

(* raised and caught in the same procedure *)
PROCEDURE Same (): INTEGER =
  VAR r := 0;
  BEGIN
    TRY
      Raise1 ();
      r := 1;
    EXCEPT
    | E1 => r := 2;
    END;
    RETURN r;
  END Same;

(* raised one frame down, with an argument *)
PROCEDURE Across (n: INTEGER): INTEGER =
  BEGIN
    TRY
      Raise2 (n);
      RETURN -1;
    EXCEPT
    | E2 (v) => RETURN v;
    END;
  END Across;

(* FINALLY on the normal path and on the exceptional path *)
PROCEDURE Fin (raise: BOOLEAN): INTEGER =
  VAR r := 0;
  BEGIN
    TRY
      TRY
        IF raise THEN Raise1 () END;
        r := 10;
      FINALLY
        INC (trace);
      END;
    EXCEPT
    | E1 => r := 20;
    END;
    RETURN r;
  END Fin;

(* several frames, each with a FINALLY, between the raise and the handler *)
PROCEDURE Deep (depth: INTEGER) RAISES {E2} =
  BEGIN
    IF depth = 0 THEN
      Raise2 (42);
    ELSE
      TRY
        Deep (depth - 1);
      FINALLY
        INC (trace);
      END;
    END;
  END Deep;

(* a traced REF live across a TRY, in a loop, with a raise on some passes *)
PROCEDURE Rooted (n: INTEGER): INTEGER =
  VAR r: REF INTEGER;  s := 0;
  BEGIN
    FOR i := 1 TO n DO
      r := NEW (REF INTEGER);
      r^ := i;
      TRY
        IF i MOD 2 = 0 THEN Raise2 (i) END;
        s := s + r^;
      EXCEPT
      | E2 (v) => s := s + 100 * v;
      END;
    END;
    RETURN s;
  END Rooted;

BEGIN
  a := Same ();
  b := Across (7);
  c := Fin (FALSE);
  d := Fin (TRUE);
  <*ASSERT a = 2 AND b = 7 AND c = 10 AND d = 20 AND trace = 2*>

  trace := 0;
  TRY
    Deep (5);
  EXCEPT
  | E2 (v) => got := v;
  END;
  <*ASSERT got = 42 AND trace = 5*>

  f := Rooted (4);       (* 1, then 200, then 3, then 400 *)
  <*ASSERT f = 604*>
END Main.
