UNSAFE MODULE Main;

(* ms16: up-level access from nested procedures (register 62).

   On wasm32 the static link is an ordinary leading parameter (the back end
   does not implement the "nest" attribute).  Each case below fails by
   stopping in an ASSERT; a pass prints "ms16: ok" and exits 0.

   1  Read and write of the parent's locals from a nested procedure.
   2  A doubly nested procedure writing two levels up.
   3  A nested procedure passed as a procedure value to a callee, and
      through a second callee (the closure path of an indirect call).
   4  A nested procedure that calls itself (its own static link).
   5  A FINALLY handler (compiled with a static link only) that reads and
      writes the parent's local, with and without a raise.
   6  A traced REF held only in the parent's frame and used from a nested
      procedure across collections: is a variable that is accessed up-level
      still a root?

   Negative control: change an expected value in Main's body (e.g. 4123 to
   4124 in the Doubly line); the run must stop with "<*ASSERT*> failed".  *)

IMPORT RTCollector, RTIO;

EXCEPTION E1;

TYPE
  Fn   = PROCEDURE (k: INTEGER): INTEGER;
  Node = REF RECORD v: INTEGER; next: Node END;

(* ---- 1 ------------------------------------------------------------- *)

PROCEDURE ReadWrite (n: INTEGER): INTEGER =
  VAR a := n;  b := 0;
  PROCEDURE Bump () =
    BEGIN
      b := b + a;        (* reads the parent's a, writes the parent's b *)
      INC (a, 3);        (* writes the parent's a *)
    END Bump;
  BEGIN
    Bump ();  Bump ();
    RETURN a * 1000 + b;
  END ReadWrite;

(* ---- 2 ------------------------------------------------------------- *)

PROCEDURE Doubly (n: INTEGER): INTEGER =
  VAR x := n;
  PROCEDURE Mid (): INTEGER =
    VAR y := 10;  p, q: INTEGER;
    PROCEDURE Inner (): INTEGER =
      BEGIN
        x := x + y;      (* x is two levels up, y is one level up *)
        INC (y);
        RETURN x * 100 + y;
      END Inner;
    BEGIN
      p := Inner ();  q := Inner ();
      RETURN p + q;
    END Mid;
  VAR r: INTEGER;
  BEGIN
    r := Mid ();
    <* ASSERT x = 26 *>
    RETURN r;
  END Doubly;

(* ---- 3 ------------------------------------------------------------- *)

PROCEDURE Apply (f: Fn;  k: INTEGER): INTEGER =
  VAR a, b: INTEGER;
  BEGIN
    a := f (k);  b := f (k + 1);
    RETURN a + b;
  END Apply;

PROCEDURE Twice (f: Fn;  k: INTEGER): INTEGER =
  BEGIN
    RETURN Apply (f, k);
  END Twice;

PROCEDURE ByValue (base: INTEGER): INTEGER =
  VAR calls := 0;  r1, r2: INTEGER;
  PROCEDURE Add (k: INTEGER): INTEGER =
    BEGIN
      INC (calls);
      RETURN base + k;
    END Add;
  BEGIN
    r1 := Apply (Add, 10);           (* base+10 + base+11 *)
    r2 := Twice (Add, 20);           (* base+20 + base+21 *)
    <* ASSERT calls = 4 *>
    RETURN r1 * 1000 + r2;
  END ByValue;

(* ---- 4 ------------------------------------------------------------- *)

PROCEDURE Walk (n: INTEGER): INTEGER =
  VAR sum := 0;
  PROCEDURE Visit (k: INTEGER) =
    BEGIN
      IF k > 0 THEN
        sum := sum + k;
        Visit (k - 1);
      END;
    END Visit;
  BEGIN
    Visit (n);
    RETURN sum;
  END Walk;

(* ---- 5 ------------------------------------------------------------- *)

PROCEDURE Fin (raise: BOOLEAN): INTEGER =
  VAR x := 1;
  BEGIN
    TRY
      TRY
        x := x + 1;
        IF raise THEN RAISE E1 END;
        x := x + 10;
      FINALLY
        x := x * 3;          (* the handler reaches x through the static link *)
      END;
    EXCEPT
    | E1 => x := x + 100;
    END;
    RETURN x;
  END Fin;

(* ---- 6 ------------------------------------------------------------- *)

PROCEDURE Make (n: INTEGER): Node =
  VAR head: Node := NIL;
  BEGIN
    FOR i := n TO 1 BY -1 DO head := NEW (Node, v := i, next := head) END;
    RETURN head;
  END Make;

PROCEDURE Sum (l: Node): INTEGER =
  VAR s := 0;
  BEGIN
    WHILE l # NIL DO s := s + l.v;  l := l.next END;
    RETURN s;
  END Sum;

PROCEDURE Rooted (): INTEGER =
  VAR keep: Node;  extra: Node;
  PROCEDURE Churn () =
    BEGIN
      RTCollector.Collect ();
      FOR i := 1 TO 200 DO EVAL Make (20) END;
      RTCollector.Collect ();
    END Churn;
  PROCEDURE Grow () =
    BEGIN
      extra := Make (10);                (* allocated in the nested procedure *)
      extra.next.next := keep;           (* and linked to the parent's list *)
    END Grow;
  BEGIN
    keep := Make (50);                   (* sum 1275 *)
    Churn ();
    <* ASSERT Sum (keep) = 1275 *>
    Grow ();
    Churn ();
    (* extra is 1, 2, then the 50-node list; only the parent's frame and
       the nested procedure Grow ever name it *)
    <* ASSERT Sum (extra) = 3 + 1275 *>
    RETURN Sum (keep) * 1000 + (extra.v + extra.next.v);
  END Rooted;

(* ------------------------------------------------------------------- *)

VAR r: INTEGER;

BEGIN
  (* each call is made outside the assertion, so none depends on assertions
     being compiled in *)
  r := ReadWrite (5);   <* ASSERT r = 11013 *>    (* a: 5 -> 8 -> 11; b: 5, then 13 *)
  r := Doubly (5);      <* ASSERT r = 4123 *>     (* Inner: 1511, then 2612 *)
  r := ByValue (100);   <* ASSERT r = 221241 *>   (* 110+111, then 120+121 *)
  r := Walk (4);        <* ASSERT r = 10 *>
  r := Fin (FALSE);     <* ASSERT r = 36 *>       (* 1 -> 2 -> 12 -> 36 *)
  r := Fin (TRUE);      <* ASSERT r = 106 *>      (* 1 -> 2 -> 6 -> 106 *)
  r := Rooted ();       <* ASSERT r = 1275003 *>
  RTIO.PutText ("ms16: ok\n");
  RTIO.Flush ();
END Main.
