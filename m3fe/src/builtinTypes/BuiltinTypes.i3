(* Copyright (C) 1992, Digital Equipment Corporation           *)
(* All rights reserved.                                        *)
(* See the file COPYRIGHT for a full description.              *)

(* File: BuiltinTypes.i3                                       *)
(* Last Modified On Fri Jun 30 08:29:48 1989 By kalsow         *)

INTERFACE BuiltinTypes;

IMPORT IR, Type;

TYPE
  Kind   = {
    Err, Int, LInt, Card, LCard, Bool,
    Reel, LReel, EReel,
    Charr, WCharr, Textt,
    Null, Addr, Reff, ObjectRef, ObjectAdr,
    Mutex
  };

CONST
  KindNames = ARRAY Kind OF TEXT {
    "_ERROR", "INTEGER", "LONGINT", "CARDINAL", "LONGCARD", "BOOLEAN",
    "REAL", "LONGREAL", "EXTENDED",
    "CHAR", "WIDECHAR", "TEXT",
    "NULL", "ADDRESS", "REFANY", "ROOT", "_UNTRACED_ROOT",
    "MUTEX"
  };

VAR
  KindInfo : ARRAY Kind OF REF Type.Info;
  KindType : ARRAY Kind OF     IR.Type;
  KindUID  : ARRAY Kind OF     IR.TypeUID;

PROCEDURE GetKind(ir_typeuid : IR.TypeUID; VAR kind : Kind) : BOOLEAN;

PROCEDURE Initialize ();

END BuiltinTypes.
