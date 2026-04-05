(* Copyright 2025 Sunil Khare. All rights reserved.    *)
(* See file COPYRIGHT-SK for details. *)

INTERFACE M3Req;

IMPORT M3ID;
IMPORT IntRefTbl;

TYPE
  T = REF RECORD
                                (* Corresponding to M3Build.T          *)
    pkg_cache : IntRefTbl.T;    (* pkg name -> current path to package *)

    pkg_uri   : TEXT;           (* text of require()                   *)
    rev       : TEXT;           (* text of require()                   *)
    scheme    := Kind.Unknown;  (* Derived from pkg_uri                *)
    name      :  TEXT := NIL;   (* of the resource                     *)
    pkg       := M3ID.NoID;
    pkg_path  :  TEXT := NIL;   (* install / "pkg" / pkg               *)
  END;

TYPE
  Kind = { File, Fossil, Git, Mercury, Unknown };

PROCEDURE New (install: TEXT; cache: IntRefTbl.T; pkg_uri, revision: TEXT): T;

PROCEDURE IsInstalled (req: T): BOOLEAN;
PROCEDURE Get(req: T) : BOOLEAN;
PROCEDURE Deploy(req: T);

END M3Req.
