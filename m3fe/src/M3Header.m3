(* Copyright (C) 1994, Digital Equipment Corporation           *)
(* All rights reserved.                                        *)
(* See the file COPYRIGHT for a full description.              *)
(*                                                             *)
(* File: M3Header.m3                                           *)
(* Last modified on Mon Jul 11 11:55:37 PDT 1994 by kalsow     *)

MODULE M3Header;

IMPORT File, M3ID;


TYPE
  State = RECORD
    imports   : IDList  := NIL;
    generic   : File.T  := NIL;
    interface : BOOLEAN := FALSE;
    failed    : BOOLEAN := FALSE;
  END;

PROCEDURE Parse (): IDList =
  VAR
    s  : State;
  BEGIN
    PushID (s, M3ID.Add ("RTHooks")); (* compiler magic *)
    ParseImports (s);
    RETURN s.imports;
  END Parse;



PROCEDURE ParseImports (<* UNUSED *> VAR s: State) =
  BEGIN
  END ParseImports;


PROCEDURE PushID (VAR s: State;  id: M3ID.T) =
  BEGIN
    s.imports := NEW (IDList, interface := id, next := s.imports);
  END PushID;

BEGIN
END M3Header.
