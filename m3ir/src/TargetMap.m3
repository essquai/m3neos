(* Copyright (C) 1993, Digital Equipment Corporation           *)
(* All rights reserved.                                        *)
(* See the file COPYRIGHT for a full description.              *)
(*                                                             *)
(* File: TargetMap.m3                                          *)
(* Last Modified On Fri Nov 19 09:33:51 PST 1993 By kalsow     *)

MODULE TargetMap;

IMPORT Target;
FROM Target IMPORT IRType;

PROCEDURE Init () =
 BEGIN
    InitI (IRType.Int8,   Target.Int8);
    InitI (IRType.Word8,  Target.Word8);
    InitI (IRType.Int16,  Target.Int16);
    InitI (IRType.Word16, Target.Word16);
    InitI (IRType.Int32,  Target.Int32);
    InitI (IRType.Word32, Target.Word32);
    InitI (IRType.Int64,  Target.Longint);
    InitI (IRType.Word64, Target.Long);
    InitF (IRType.Reel,   Target.Real);
    InitF (IRType.LReel,  Target.Longreal);
    InitF (IRType.XReel,  Target.Extended);
    InitI (IRType.Addr,   Target.Address);
    InitI (IRType.Struct, Target.Void);
    InitI (IRType.Void,   Target.Void);

    Word_types[0] := Target.Word8;
    Word_types[1] := Target.Word16;
    Word_types[2] := Target.Word32;
    Word_types[3] := Target.Word64;

    Integer_types[0] := Target.Int8;
    Integer_types[1] := Target.Int16;
    Integer_types[2] := Target.Int32;
    Integer_types[3] := Target.Int64;
  END Init;

PROCEDURE InitI (type: IRType;  READONLY x: Target.Int_type) =
  BEGIN
    CG_Align [type]       := x.align;
    CG_Align_bytes [type] := x.align DIV Target.Byte;
    CG_Size [type]        := x.size;
    CG_Bytes [type]       := x.bytes;
  END InitI;

PROCEDURE InitF (type: IRType;  READONLY x: Target.Float_type) =
  BEGIN
    CG_Align [type]       := x.align;
    CG_Align_bytes [type] := x.align DIV Target.Byte;
    CG_Size [type]        := x.size;
    CG_Bytes [type]       := x.bytes;
    Float_types[x.pre]    := x;
  END InitF;

BEGIN
END TargetMap.
