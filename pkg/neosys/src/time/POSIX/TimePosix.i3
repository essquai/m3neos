(* Copyright (C) 1989, Digital Equipment Corporation        *)
(* All rights reserved.                                     *)
(* See the file COPYRIGHT for a full description.           *)
(*                                                          *)
(* Last modified on Wed Nov 24 09:44:38 PST 1993 by kalsow  *)
(*      modified on Thu Jan 28 10:00:32 PST 1993 by mjordan *)

INTERFACE TimePosix;
IMPORT Time;

<*EXTERNAL TimePosix__ComputeGrain*> PROCEDURE ComputeGrain(): Time.T;
<*EXTERNAL TimePosix__Now*> PROCEDURE Now(): Time.T;

END TimePosix.
