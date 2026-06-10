(* Copyright (C) 1992, Digital Equipment Corporation           *)
(* All rights reserved.                                        *)
(* See the file COPYRIGHT for a full description.              *)

(* File: BuiltinTypes.m3                                       *)
(* Last Modified On Mon Mar  1 17:24:04 PST 1993 By kalsow     *)
(*      Modified On Fri Aug  3 01:38:59 1990 By muller         *)

MODULE BuiltinTypes;

IMPORT Int, LInt, Card, Bool, Reel, LReel, EReel, Charr, Addr;
IMPORT Null, Reff, Textt, Mutex, ErrType, ObjectRef, ObjectAdr;
IMPORT WCharr, LCard, Type, IR;
IMPORT M3IR;
IMPORT IntIntTbl;
IMPORT Fmt, IO, Wr;


VAR kindTable : IntIntTbl.T := NIL;

PROCEDURE Initialize () =
  BEGIN
    (* builtin types *)
    (* NOTE: this list is ordered! *)
    ErrType.Initialize (); SetKind(ErrType.T, Kind.Err);
    Int.Initialize (); SetKind(Int.T, Kind.Int);
    LInt.Initialize (); SetKind(LInt.T, Kind.LInt);
    Card.Initialize (); SetKind(Card.T, Kind.Card);
    LCard.Initialize (); SetKind(LCard.T, Kind.LCard);
    Bool.Initialize (); SetKind(Bool.T, Kind.Bool);
    Reel.Initialize (); SetKind(Reel.T, Kind.Reel);
    LReel.Initialize (); SetKind(LReel.T, Kind.LReel);
    EReel.Initialize (); SetKind(EReel.T, Kind.EReel);
    Charr.Initialize (); SetKind(Charr.T, Kind.Charr);
    Null.Initialize (); SetKind(Null.T, Kind.Null);
    Addr.Initialize (); SetKind(Addr.T, Kind.Addr);
    Reff.Initialize (); SetKind(Reff.T, Kind.Reff);
    ObjectRef.Initialize (); SetKind(ObjectRef.T, Kind.ObjectRef);
    ObjectAdr.Initialize (); SetKind(ObjectAdr.T, Kind.ObjectAdr);
    Textt.Initialize (); SetKind(Textt.T, Kind.Textt);
    Mutex.Initialize (); SetKind(Mutex.T, Kind.Mutex);
    WCharr.Initialize (); SetKind(WCharr.T, Kind.WCharr);
  END Initialize;

PROCEDURE GetKind(ir_typeuid : IR.TypeUID; VAR kind : Kind) : BOOLEAN =
  VAR found := FALSE; a : INTEGER;
  BEGIN
    kind := Kind.Err;
    IF kindTable # NIL THEN
      found := kindTable.get(ir_typeuid, a);
      IF found THEN
        kind  := VAL(a, Kind);
      END;
    END;
    IO.Put("GetKind " & " found=" & Fmt.Bool(found) & " name=" & KindNames[kind] & Wr.EOL);
    RETURN found;
  END GetKind;

PROCEDURE SetKind(t : Type.T; kind : Kind) =
  VAR
    typeid : IR.TypeUID;
  BEGIN
    IF kindTable = NIL THEN
      kindTable := NEW(IntIntTbl.Default).init(sizeHint := 20);
    END;
    KindInfo[kind] := NEW(REF Type.Info);
    typeid := Type.GlobalUID(t);
    EVAL Type.CheckInfo(t, KindInfo[kind]^);
    KindType[kind] := KindInfo[kind].mem_type;
    KindUID[kind]  := typeid;
    EVAL kindTable.put(typeid, ORD(kind));
    IO.Put("Builtin: " & KindNames[kind] & " typeid=" & M3IR.FormatUID(typeid) & Wr.EOL);
  END SetKind;

BEGIN
END BuiltinTypes.
