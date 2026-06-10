(* Copyright (C) 1993, Digital Equipment Corporation           *)
(* All rights reserved.                                        *)
(* See the file COPYRIGHT for a full description.              *)
(*                                                             *)
(* Last modified on Fri Nov 19 09:30:17 PST 1993 by kalsow     *)
(*      modified on Mon Apr 13 09:55:12 PDT 1992 by muller     *)

INTERFACE IRIO_Rd;

IMPORT M3IR, Rd;

PROCEDURE Inhale (rd: Rd.T;  cg: M3IR.T);
(* Parse the M3IR calls from 'rd' and call 'cg' to implement them. *)

END IRIO_Rd.
