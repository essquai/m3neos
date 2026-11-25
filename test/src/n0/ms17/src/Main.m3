UNSAFE MODULE Main;

(* ms17: the space bound of the collector, with a live set of known size
   (register 41; the mode question is register 49).

   The collector documents that the traced heap must hold at least
   A * (2 + 2/gcRatio) pages while it runs incrementally and
   A * (2 + 1/gcRatio) pages stop-and-copy, A being the accessible live
   data: 4A and 3A at gcRatio 1.  This program holds a live set of a given
   size, A, and then allocates and drops garbage until a given volume has
   passed through the heap, replacing one live chunk in sixteen so that the
   collector has live data to copy and the barriers have work.  Run it with
   the traced arena capped at decreasing sizes: the smallest cap that passes
   is the measured bound for this A.

   Usage:  ms17 [liveKiB [churnMiB]] [v] [@M3traced=NM] [@M3noincremental]
     v         print a progress line after the live set and every 16 MiB of
               churn, flushed, so that a hang or a crash shows where it was
     liveKiB   live set in KiB of 1 KiB chunks, default 4096 (A about 4 MiB)
     churnMiB  garbage volume in MiB, default 64
   Output: one "ms17: ok ..." line and the allocator statistics at exit.
   A failure is a runtime error ("NEW() was unable to allocate more memory"),
   then abort; a corrupted live chunk stops in an ASSERT. *)

IMPORT RTArgs, RTIO, Text;

TYPE
  Chunk = REF RECORD
    id  : INTEGER;
    data: ARRAY [0 .. 1015] OF CHAR;   (* about 1 KiB with the id *)
  END;
  Table = REF ARRAY OF Chunk;

VAR
  liveKiB  := 4096;
  churnMiB := 64;
  verbose  := FALSE;
  live     : Table;
  total, j : INTEGER;

(* the value of an all-digit text, or -1 *)
PROCEDURE Num (t: TEXT): INTEGER =
  VAR n := 0;  c: CHAR;
  BEGIN
    IF Text.Length (t) = 0 THEN RETURN -1 END;
    FOR i := 0 TO Text.Length (t) - 1 DO
      c := Text.GetChar (t, i);
      IF c < '0' OR c > '9' THEN RETURN -1 END;
      n := n * 10 + (ORD (c) - ORD ('0'));
    END;
    RETURN n;
  END Num;

PROCEDURE NewChunk (id: INTEGER): Chunk =
  VAR c := NEW (Chunk);
  BEGIN
    c.id := id;
    c.data[0]        := VAL (id MOD 256, CHAR);
    c.data[LAST (c.data)] := VAL (id MOD 256, CHAR);
    RETURN c;
  END NewChunk;

PROCEDURE Say (what: TEXT;  n: INTEGER) =
  BEGIN
    RTIO.PutText ("ms17: ");  RTIO.PutText (what);
    RTIO.PutInt (n);  RTIO.PutText ("\n");  RTIO.Flush ();
  END Say;

PROCEDURE Parse () =
  VAR k := 0;  v: INTEGER;
  BEGIN
    FOR i := 0 TO RTArgs.ArgC () - 1 DO
      IF Text.Equal (RTArgs.GetArg (i), "v") THEN verbose := TRUE END;
      v := Num (RTArgs.GetArg (i));
      IF v >= 0 THEN
        IF    k = 0 THEN liveKiB  := v
        ELSIF k = 1 THEN churnMiB := v
        END;
        INC (k);
      END;
    END;
  END Parse;

BEGIN
  Parse ();
  <* ASSERT liveKiB > 0 *>

  live := NEW (Table, liveKiB);
  FOR i := 0 TO liveKiB - 1 DO live[i] := NewChunk (i) END;
  IF verbose THEN Say ("live set built, KiB ", liveKiB) END;

  total := churnMiB * 1024;
  FOR i := 1 TO total DO
    EVAL NewChunk (i);                     (* garbage *)
    IF i MOD 16 = 0 THEN                   (* the old chunk becomes garbage *)
      j := (i DIV 16) MOD liveKiB;
      live[j] := NewChunk (j);
    END;
    IF verbose AND i MOD 16384 = 0 THEN Say ("churned MiB ", i DIV 1024) END;
  END;

  FOR i := 0 TO liveKiB - 1 DO
    <* ASSERT live[i].id = i *>
    <* ASSERT live[i].data[0] = VAL (i MOD 256, CHAR) *>
    <* ASSERT live[i].data[LAST (live[i].data)] = VAL (i MOD 256, CHAR) *>
  END;

  RTIO.PutText ("ms17: ok live=");     RTIO.PutInt (liveKiB);
  RTIO.PutText (" KiB churn=");        RTIO.PutInt (churnMiB);
  RTIO.PutText (" MiB\n");
  RTIO.Flush ();
END Main.
