(* Copyright (C) 1992, Digital Equipment Corporation           *)
(* All rights reserved.                                        *)
(* See the file COPYRIGHT for a full description.              *)

(* File: IfStmt.m3                                             *)
(* Last modified on Thu Nov 10 13:30:29 PST 1994 by kalsow     *)
(*      modified on Wed Feb 27 04:00:55 1991 by muller         *)

MODULE IfStmt;

IMPORT IR, Expr, Bool, Type, Error, Token, Stmt, StmtRep, Scanner, ErrType;
FROM Scanner IMPORT Match, GetToken, cur;

TYPE
  P = Stmt.T OBJECT
        clauses  : Clause;
        elseBody : Stmt.T;
      OVERRIDES
        check       := Check;
        compile     := Compile;
        outcomes    := GetOutcome;
      END;

TYPE
  Clause = REF RECORD
             origin : INTEGER;
             next   : Clause;
             cond   : Expr.T;
             body   : Stmt.T;
           END;

PROCEDURE Parse (): Stmt.T =
  TYPE TK = Token.T;
  VAR p := NEW (P);  c, last: Clause;
  BEGIN
    StmtRep.Init (p);

    Match (TK.tIF);
    c := NEW (Clause);
    c.origin := Scanner.offset;
    c.next := NIL;
    c.cond := Expr.Parse ();
    Match (TK.tTHEN);
    c.body := Stmt.Parse ();
    p.clauses := c;
    p.elseBody := NIL;
    last := c;

    WHILE (cur.token = TK.tELSIF) DO
      GetToken (); (* ELSIF *)
      c := NEW (Clause);
      c.origin := Scanner.offset;
      c.next := NIL;
      c.cond := Expr.Parse ();
      Match (TK.tTHEN);
      c.body := Stmt.Parse ();
      last.next := c;
      last := c;
    END;

    IF (cur.token = TK.tELSE) THEN
      GetToken (); (* ELSE *)
      p.elseBody := Stmt.Parse ();
    END;

    Match (TK.tEND);
    RETURN p;
  END Parse;

PROCEDURE Check (p: P;  VAR cs: Stmt.CheckState) =
  VAR c: Clause;  t: Type.T;
  BEGIN
    c := p.clauses;
    WHILE (c # NIL) DO
      Expr.TypeCheck (c.cond, cs);
      t := Expr.TypeOf (c.cond);
      IF (Type.Base (t) # Bool.T) AND (t # ErrType.T) THEN
        Scanner.offset := c.origin;
        Error.Msg ("IF condition must be a BOOLEAN");
      END;
      Stmt.TypeCheck (c.body, cs);
      c := c.next;
    END;
    Stmt.TypeCheck (p.elseBody, cs);
  END Check;

PROCEDURE Compile (p: P): Stmt.Outcomes =
  VAR
    c       : Clause;
    l_end   : IR.Label;
    l_next  : IR.Label;
    l_cond  := IR.No_label;
    elsif   : INTEGER := 0;
    oc, xc  : Stmt.Outcomes;
    gotoEnd := FALSE;
  BEGIN
    l_end := IR.Next_label ();

    c := p.clauses;
    oc := Stmt.Outcomes {};
    WHILE (c # NIL) DO
      l_next := IR.Next_label ();
      IF l_cond = IR.No_label THEN l_cond := l_next; END;
      Scanner.offset := c.origin;
      IR.Gen_location (Scanner.offset);
      Expr.PrepBranch (c.cond, IR.No_label, l_next, IR.Always - IR.Likely);
      Expr.CompileBranch (c.cond, IR.No_label, l_next, IR.Always - IR.Likely);
      IR.Begin_clause(l_next, TRUE);
      xc := Stmt.Compile (c.body);
      IF l_cond # l_next THEN INC(elsif) END;
      oc := oc + xc;
      IF (Stmt.Outcome.FallThrough IN xc)
        AND ((c.next # NIL) OR (p.elseBody # NIL)) THEN
        IR.Jump (l_end);
        gotoEnd := TRUE;
      END;
      IR.Set_label (l_next);
      c := c.next;
    END;

    (* Close any ELSIF clauses *)
    WHILE elsif > 0 DO
      IR.End_clause(l_next);
      DEC(l_next);
      DEC(elsif);
    END;

    IF (p.elseBody = NIL) THEN
      oc := oc + Stmt.Outcomes {Stmt.Outcome.FallThrough};
    ELSE
      IR.Begin_clause(l_cond, FALSE);
      oc := oc + Stmt.Compile (p.elseBody);
    END;
    IR.End_clause(l_cond);

    IF (gotoEnd) THEN IR.Set_label (l_end) END;
    RETURN oc;
  END Compile;

PROCEDURE GetOutcome (p: P): Stmt.Outcomes =
  VAR c: Clause;  oc := Stmt.Outcomes {};
  BEGIN
    c := p.clauses;
    WHILE (c # NIL) DO
      oc := oc + Stmt.GetOutcome (c.body);
      c := c.next;
    END;
    IF (p.elseBody = NIL)
      THEN oc := oc + Stmt.Outcomes {Stmt.Outcome.FallThrough};
      ELSE oc := oc + Stmt.GetOutcome (p.elseBody);
    END;
    RETURN oc;
  END GetOutcome;

BEGIN
END IfStmt.
