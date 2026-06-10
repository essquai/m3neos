(* Copyright 1996-2000, Critical Mass, Inc.  All rights reserved. *)
(* See file COPYRIGHT-CMASS for details. *)

INTERFACE IRIO_BinRd;

IMPORT M3IR, Rd;

PROCEDURE Inhale (rd: Rd.T;  cg: M3IR.T);
(* Parse the binary intermediate code M3IR calls from 'rd'
   and call 'cg' to implement them. *)

END IRIO_BinRd.
