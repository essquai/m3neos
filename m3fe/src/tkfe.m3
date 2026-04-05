MODULE M3Front;

(* The stub generator uses the standard tool framework provided by
   "M3ToolFrame".  
   Each interface given on the command line is processed, and
   stubs are generated for all the network objects it defines
   that cn legitimately be marshalled.
*)

IMPORT IO, Process;
IMPORT Stdio, Wr;
IMPORT AST, ASTWalk, M3ASTDisplay, StdFormat;
IMPORT M3Context, M3Conventions, M3AST_AS, M3CUnit, M3CFETool, 
       M3ToolFrame;
IMPORT M3AST_all;  (* this cannot be omitted; it defines the particular
                     revelations for all the AST nodes *)

PROCEDURE DispNode(<* UNUSED *> cl : ASTWalk.Closure; n: AST.NODE; <* UNUSED *> vm : ASTWalk.VisitMode) RAISES ANY =
  BEGIN
    M3ASTDisplay.Nodes(n, Stdio.stdout);
  END DispNode;

TYPE ContextClosure = M3Context.Closure OBJECT
    wr: Wr.T;
  OVERRIDES callback := VisitUnit;
  END;

PROCEDURE VisitUnit(
    <* UNUSED *> cl: ContextClosure;
    <* UNUSED *> ut: M3CUnit.Type;
    name: TEXT;
    cu: M3AST_AS.Compilation_Unit)
    RAISES {}=
  VAR dcl := NEW(M3ASTDisplay.Closure , callback := DispNode);
  BEGIN
    (* visit all the nodes in the compilation unit *)
    IO.Put("VisitUnit " & name & Wr.EOL);
    StdFormat.Set(cu);
    ASTWalk.VisitNodes(cu, dcl);
  END VisitUnit;

PROCEDURE DoRun(<*UNUSED*> w: M3ToolFrame.Worker; c: M3Context.T;
                <*UNUSED*> compileResult: INTEGER): INTEGER RAISES {}=
  VAR returnCode: INTEGER;
  BEGIN
    M3Context.Apply(c, NEW(ContextClosure, wr := Stdio.stdout),
                          findStandard := FALSE); (* ignore 'standard' unit *)
    RETURN returnCode;
  END DoRun;

  <* FATAL ANY *>
BEGIN
  (*
  Process.Exit(ABS(M3ToolFrame.Startup(
                       NEW(M3ToolFrame.Worker, work := DoRun),
                       compile := TRUE)));
  *)
END M3Front.