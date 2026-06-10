(* Copyright 1996-2000, Critical Mass, Inc.  All rights reserved. *)
(* See file COPYRIGHT-CMASS for details. *)

INTERFACE IRIO_BinWr;

IMPORT M3IR, Wr;

PROCEDURE New (wr: Wr.T): M3IR.T;
(* returns a fresh, initialized code generator that writes its
   calls as binary intermediate code on 'wr'.  See IRIO_Binary
   for the binary format.  *)

END IRIO_BinWr.
