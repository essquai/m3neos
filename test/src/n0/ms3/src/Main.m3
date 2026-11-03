UNSAFE MODULE Main;

IMPORT auxRTThread;
IMPORT RT0, RTType;
IMPORT Word;
IMPORT Stdio, Wr;

IMPORT IO, Fmt;

TYPE
  composite = RECORD
    f1 : INTEGER;
    f2 : REF INTEGER;
  END;
  Color = {red, green, blue};

PROCEDURE number(oa : ARRAY OF INTEGER) : INTEGER =
  BEGIN
    RETURN NUMBER(oa);
  END number;

PROCEDURE kilo( bytes : INTEGER) : INTEGER =
  VAR kb : INTEGER;
  BEGIN
    kb := bytes * 1024;
    RETURN kb;
  END kilo;

PROCEDURE record() : composite =
  VAR c : composite;
  BEGIN
    c.f1 := 11;
    c.f2 := NEW(REF INTEGER);
    c.f2^ := 12;
    RETURN c;
  END record;

VAR a := ARRAY [1..3] OF INTEGER {1, 2, 3};

(* A: one traced field mixed with untraced ones, non-zero offset *)
TYPE TestA = RECORD
  a : INTEGER;
  b : REAL;
  c : REF INTEGER;
  d : INTEGER;
END;

(* B: nested-by-value record containing a traced field —
   exercises the recursive base-offset threading directly *)
TYPE Inner = RECORD
  x : INTEGER;
  y : REF INTEGER;
END;
TYPE TestB = RECORD
  p : INTEGER;
  q : Inner;
  r : INTEGER;
END;

(* C: two non-adjacent traced fields, plus a user-declared
   OBJECT field — the one open item from the last checkpoint
   (ObjectDebug fix proven for builtin TEXT/REFANY, never yet
   for a genuinely user-declared object) *)
TYPE SomeObj = OBJECT m: INTEGER END;
TYPE TestC = RECORD
  u : INTEGER;
  v : REF INTEGER;
  w : INTEGER;
  x : SomeObj;
END;


PROCEDURE metadump(id: INTEGER; a: ADDRESS) =
  VAR b: REF [0..255];
  BEGIN
    IO.Put("metadump " & Fmt.Int(id) & " [ ");
    REPEAT
      b := LOOPHOLE(a, REF [0..255]);
      IO.Put(Fmt.Unsigned(Word.And(b^,16_ff)) & " ");
      INC(a);
    UNTIL b^ = 0;
  IO.Put("]\n")
  END metadump;


PROCEDURE GCRoots() =
  VAR
    pa: REF TestA; va : TestA;
    pb: REF TestB; vb : TestB;
    pc: REF TestC; vc : TestC;
    tda, tdb, tdc : RT0.TypeDefn;
  BEGIN
    (* Test "A" *)
    pa := NEW(REF TestA);
    pa.c := NEW(REF INTEGER);
    pa.c^ := 100;
    va := pa^;

    (* Test "B" *)
    pb := NEW(REF TestB);
    pb.q.y := NEW(REF INTEGER);
    pb.q.y^ := 101;
    vb := pb^;

    (* Test "C" *)
    pc := NEW(REF TestC);
    pc.v := NEW(REF INTEGER);
    pc.x := NEW(SomeObj, m:= 102);
    pc.v^ := 103;
    vc := pc^;

    (* Validation: use RTType *)
    (* GC type_map bytes start at tdc.gc_map *)
    tda := RTType.Get(TYPECODE(REF TestA));
    tdb := RTType.Get(TYPECODE(REF TestB));
    tdc := RTType.Get(TYPECODE(REF TestC));

    IO.Put("TYPECODE(REF TestA)=" & Fmt.Int(TYPECODE(REF TestA)) & "\n");
    IO.Put("TYPECODE(REF TestB)=" & Fmt.Int(TYPECODE(REF TestB)) & "\n");
    IO.Put("TYPECODE(REF TestC)=" & Fmt.Int(TYPECODE(REF TestC)) & "\n");

    metadump(TYPECODE(REF TestA), tda.gc_map);
    metadump(TYPECODE(REF TestB), tdb.gc_map);
    metadump(TYPECODE(REF TestC), tdc.gc_map);

  END GCRoots;

PROCEDURE valRec(r : composite) : INTEGER =
  BEGIN
    RETURN r.f1 + r.f2^;
  END valRec;

PROCEDURE modRec(r : composite) : INTEGER =
  BEGIN
    r.f1 := 99;
    r.f2 := NEW(REF INTEGER);
    r.f2^ := 7;
    RETURN r.f1 + r.f2^;
  END modRec;

PROCEDURE takeRef(p : REF INTEGER; VAR varref: REF INTEGER; VAR varint: INTEGER) : INTEGER =
  BEGIN
    p := NEW(REF INTEGER);
    varref := NEW(REF INTEGER);
    varint := 55;
    EVAL NEW(REF INTEGER);
    p^ := 5;
    RETURN p^;
  END takeRef;

PROCEDURE otherRoots(s: [0..9]; e: Color; t: TEXT; o: SomeObj; rc: REF composite;
                f: PROCEDURE(): INTEGER; w: Wr.T): INTEGER =
  BEGIN
    RETURN s;
  END otherRoots;

PROCEDURE phaseB(<*UNUSED*> mode : INTEGER) : RT0.ModulePtr =
  VAR  n : INTEGER; t := "TEXT";
    c : composite; r, vr : REF INTEGER; vi: INTEGER;
    so := NEW(SomeObj, m:= 102);
    rc := NEW(REF composite);
    pp : PROCEDURE(): INTEGER := NIL;
    cl := Color.red;
    w := Stdio.stdout;
  BEGIN
    n  := number(a);
    IO.Put("number(a)=" & Fmt.Int(n) & "\n");
    n := kilo(1);
    IO.Put("kilo(1)=" & Fmt.Int(n) & "\n");
    c := record();
    IO.Put("c=composite(" & Fmt.Int(c.f1) & "," & Fmt.Int(c.f2^) & ")\n");
    GCRoots();
    n := valRec(c);
    n := modRec(c);
    vr := NEW(REF INTEGER);
    vr^ := 1234;
    IO.Put("pre takeRef vr/vi(" & Fmt.Int(vr^) & "," & Fmt.Int(vi) & ")\n");
    n := takeRef(vr, vr, vi);
    IO.Put("post takeRef vr/vi(" & Fmt.Int(vr^) & "," & Fmt.Int(vi) & ") n=" & Fmt.Int(n) & "\n");
    EVAL otherRoots(4, cl, t, so, rc, pp, w);
    RETURN NIL;
  END phaseB;

BEGIN
(*
  auxRTThread.Init();
  auxRTThread.InitialThread(phaseB);
*)
  EVAL phaseB(0);
END Main.
