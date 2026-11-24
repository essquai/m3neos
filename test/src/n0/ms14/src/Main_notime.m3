UNSAFE MODULE Main;

(* ms14: the GC chain after a catch.

   Down() builds several frames that each root two traced REFs, then raises at
   the bottom.  The handler is in AfterCatch(), which also roots a list.  The
   longjmp skips the epilogues of the Down frames, so unless the GC root chain
   head is put back, it still points at their dead frames.  Scrub() then
   overwrites that stack area with non-pointer data, and RTCollector.Collect
   walks the chain.  With the chain left dangling the collector reads garbage
   (crash, hang or damaged list); with it restored the list survives intact.
   Failures stop in an assertion or a crash. *)

IMPORT RTCollector;

EXCEPTION E1;

TYPE Node = REF RECORD v: INTEGER; next: Node END;

VAR
  sink: INTEGER := 0;
  total: INTEGER := 0;

PROCEDURE Make (n: INTEGER): Node =
  VAR head: Node := NIL;
  BEGIN
    FOR i := n TO 1 BY -1 DO
      head := NEW (Node, v := i, next := head);
    END;
    RETURN head;
  END Make;

PROCEDURE Sum (l: Node): INTEGER =
  VAR s := 0;
  BEGIN
    WHILE l # NIL DO s := s + l.v; l := l.next END;
    RETURN s;
  END Sum;

(* two rooted refs per frame, live across the recursive call *)
PROCEDURE Down (n: INTEGER) RAISES {E1} =
  VAR a, b: Node;
  BEGIN
    a := NEW (Node, v := n);
    b := NEW (Node, v := n + 1, next := a);
    IF n = 0 THEN RAISE E1 END;
    Down (n - 1);
    sink := sink + a.v + b.v;
  END Down;

(* a big ref-free frame: overwrites the stack the dead Down frames used *)
PROCEDURE Scrub (n: INTEGER): INTEGER =
  VAR buf: ARRAY [0 .. 1023] OF INTEGER;  s := 0;
  BEGIN
    FOR i := 0 TO 1023 DO buf[i] := 16_00200000 + 16 * i + n END;
    FOR i := 0 TO 1023 DO s := s + buf[i] MOD 7 END;
    RETURN s;
  END Scrub;

PROCEDURE AfterCatch (pass: INTEGER): INTEGER =
  VAR keep: Node;  r := 0;
  BEGIN
    keep := Make (50);                    (* sum 1275 *)
    TRY
      Down (20);
    EXCEPT
    | E1 => r := Scrub (pass);
    END;
    RTCollector.Collect ();
    FOR i := 1 TO 200 DO EVAL Make (20) END;   (* churn the heap *)
    RTCollector.Collect ();
    RETURN Sum (keep) + 0 * r;
  END AfterCatch;

BEGIN
  FOR pass := 1 TO 1 DO
    total := AfterCatch (pass);
    <*ASSERT total = 1275*>
  END;
END Main.
