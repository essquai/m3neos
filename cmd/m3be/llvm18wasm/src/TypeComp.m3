(* Copyright (C) 2026 Sunil Khare. All rights reserved.        *)
(* Copyright (C) 1992, Digital Equipment Corporation           *)
(* All rights reserved.                                        *)
(* See the file COPYRIGHT for a full description.              *)

(* File: TipeMap.m3                                            *)
(* Last Modified On Tue Jul  5 15:33:54 PDT 1994 by kalsow     *)

MODULE TypeComp;

IMPORT Target, Word;

CONST (* # of bytes of operand in the map *)
  ArgBytes = ARRAY Op OF [0..8] {
    0,            (* Stop *)
    0,            (* Mark *)
    0,            (* PushPtr *)
    0,            (* Return *)
    0,            (* Ref *)
    0,            (* UntracedRef *)
    0,            (* Proc *)
    0,            (* Real *)
    0,            (* Longreal *)
    0,            (* Extended *)
    2,            (* Int_Field      - bit offset, bit size *)
    2,            (* Word_Field     - bit offset, bit size *)
    0,            (* Int_1 *)
    0,            (* Int_2 *)
    0,            (* Int_4 *)
    0,            (* Int_8 *)
    0,            (* Word_1 *)
    0,            (* Word_2 *)
    0,            (* Word_4 *)
    0,            (* Word_8 *)
    1,            (* Set_1         - n = number of bytes *)
    2,            (* Set_2 *)
    3,            (* Set_3 *)
    4,            (* Set_4 *)
    1,            (* OpenArray_1   - n = number of open dimensions *)
    2,            (* OpenArray_2 *)
    1,            (* Array_1       - n = number of elements *)
    2,            (* Array_2 *)
    3,            (* Array_3 *)
    4,            (* Array_4 *)
    5,            (* Array_5 *)
    6,            (* Array_6 *)
    7,            (* Array_7 *)
    8,            (* Array_8 *)
    0,            (* Skip_1 *)
    0,            (* Skip_2 *)
    0,            (* Skip_3 *)
    0,            (* Skip_4 *)
    0,            (* Skip_5 *)
    0,            (* Skip_6 *)
    0,            (* Skip_7 *)
    0,            (* Skip_8 *)
    1,            (* SkipF_1       - n = number of bytes to skip forward *)
    2,            (* SkipF_2 *)
    3,            (* SkipF_3 *)
    4,            (* SkipF_4 *)
    5,            (* SkipF_5 *)
    6,            (* SkipF_6 *)
    7,            (* SkipF_7 *)
    8,            (* SkipF_8 *)
    1,            (* SkipB_1       - n = number of bytes to skip backward *)
    2,            (* SkipB_2 *)
    3,            (* SkipB_3 *)
    4,            (* SkipB_4 *)
    5,            (* SkipB_5 *)
    6,            (* SkipB_6 *)
    7,            (* SkipB_7 *)
    8             (* SkipB_8 *)
  };

CONST
  CursorUpdate = ARRAY Op OF INTEGER {
    0,                    (* Stop *)
    0,                    (* Mark *)
    -4,                   (* PushPtr *)
    -5,                   (* Return *)
    -8,                   (* Ref *)
    -8,                   (* UntracedRef *)
    -8,                   (* Proc *)
    -9,                   (* Real *)
    -10,                  (* Longreal *)
    -11,                  (* Extended *)
    0,                    (* Int_Field *)
    0,                    (* Word_Field *)
    1 * Target.Byte,      (* Int_1 *)
    2 * Target.Byte,      (* Int_2 *)
    4 * Target.Byte,      (* Int_4 *)
    8 * Target.Byte,      (* Int_8 *)
    1 * Target.Byte,      (* Word_1 *)
    2 * Target.Byte,      (* Word_2 *)
    4 * Target.Byte,      (* Word_4 *)
    8 * Target.Byte,      (* Word_8 *)
    -3,                   (* Set_1 *)
    -3,                   (* Set_2 *)
    -3,                   (* Set_3 *)
    -3,                   (* Set_4 *)
    -2,                   (* OpenArray_1 *)
    -2,                   (* OpenArray_2 *)
    -1,                   (* Array_1 *)
    -1,                   (* Array_2 *)
    -1,                   (* Array_3 *)
    -1,                   (* Array_4 *)
    -1,                   (* Array_5 *)
    -1,                   (* Array_6 *)
    -1,                   (* Array_7 *)
    -1,                   (* Array_8 *)
    1 * Target.Byte,      (* Skip_1 *)
    2 * Target.Byte,      (* Skip_2 *)
    3 * Target.Byte,      (* Skip_3 *)
    4 * Target.Byte,      (* Skip_4 *)
    5 * Target.Byte,      (* Skip_5 *)
    6 * Target.Byte,      (* Skip_6 *)
    7 * Target.Byte,      (* Skip_7 *)
    8 * Target.Byte,      (* Skip_8 *)
    -6,                   (* SkipF_1 *)
    -6,                   (* SkipF_2 *)
    -6,                   (* SkipF_3 *)
    -6,                   (* SkipF_4 *)
    -6,                   (* SkipF_5 *)
    -6,                   (* SkipF_6 *)
    -6,                   (* SkipF_7 *)
    -6,                   (* SkipF_8 *)
    -7,                   (* SkipB_1 *)
    -7,                   (* SkipB_2 *)
    -7,                   (* SkipB_3 *)
    -7,                   (* SkipB_4 *)
    -7,                   (* SkipB_5 *)
    -7,                   (* SkipB_6 *)
    -7,                   (* SkipB_7 *)
    -7                    (* SkipB_8 *)
  };

REVEAL
  T = Public BRANDED "TypeComp.T" OBJECT
    busy    : BOOLEAN  := FALSE;
    bytes   : ByteList := NIL;
    n_bytes : INTEGER  := 0;
    cursor  : INTEGER  := 0;
  METHODS
  OVERRIDES
    start := Start;
    finish := Finish;
    add := Add;
    getCursor := GetCursor;
    setCursor := SetCursor;
  END;


PROCEDURE Start (t: T) =
  BEGIN
    <*ASSERT NOT t.busy*>
    t.busy := TRUE;
    IF (t.bytes = NIL) THEN t.bytes := NEW (ByteList, 100) END;
    t.n_bytes := 0;
    t.cursor  := 0;
  END Start;

PROCEDURE Finish (t: T): ByteList =
  VAR result : ByteList;
  BEGIN
    <*ASSERT t.busy*>

    Add (t, t.cursor, Op.Stop, 0);

    (* allocate space *)
    result := NEW(ByteList, t.n_bytes);

    (* copy the bytecode *)
    result^ := SUBARRAY(t.bytes^, 0, t.n_bytes);

    t.busy := FALSE;
    RETURN result;
  END Finish;

PROCEDURE Add (t: T; offset: INTEGER;  o: Op;  arg: INTEGER) =
  VAR x, y, z, n: INTEGER;
  BEGIN
    <*ASSERT t.busy*>

    x := offset DIV Target.Byte;
    y := t.cursor DIV Target.Byte;
    z := x - y;
    IF (z # 0) THEN
      (* we need to insert a skip *)
      IF (1 <= z) AND (z <= 8) THEN
        Add (t, t.cursor, VAL (ORD (Op.Skip_1) + z - 1, Op), 0);
      ELSIF (z >= 0) THEN
        n := IntSize (z);
        Add (t, t.cursor, VAL (ORD (Op.SkipF_1) + n - 1, Op), z);
      ELSE (* z < 0 *)
        z := - z;
        n := IntSize (z);
        Add (t, t.cursor, VAL (ORD (Op.SkipB_1) + n - 1, Op), z);
      END;
    END;

    (* fix the opcode to match the size of the argument *)
    x := ArgBytes [o];
    IF (x > 0) THEN
      n := IntSize (arg);
      IF (n > x) THEN
        o := VAL (ORD (o) + n - 1, Op);
        <*ASSERT ArgBytes[o] = n*>
      END;
    END;

    (* stuff the opcode *)
    IF (t.n_bytes >= NUMBER (t.bytes^)) THEN ExpandBytes (t) END;
    t.bytes[t.n_bytes] := ORD (o);  INC (t.n_bytes);

    (* stuff the operand *)
    z := arg;
    x := ArgBytes [o];
    IF (t.n_bytes+x >= NUMBER (t.bytes^)) THEN ExpandBytes (t) END;
    WHILE (x > 0) DO
      t.bytes[t.n_bytes] := Word.And (z, 16_ff);  INC (t.n_bytes);
      z := Word.RightShift (z, 8);
      DEC (x);
    END;

    (* update the cursor *)
    x := CursorUpdate [o];
    CASE x OF
    | -1 => (* Op.Array_N *)     (* must do an explicit set cursor *)
    | -2 => (* Op.OpenArray_N *) INC (t.cursor, Target.Address.size
                                            + arg * Target.Integer.size);
    | -3 => (* Op.Set_N *)       INC (t.cursor, arg * Target.Byte);
    | -4 => (* Op.PushPtr *)     t.cursor := 0;
    | -5 => (* Op.Return *)      (* must do an explicit set cursor *)
    | -6 => (* Op.SkipF_N *)     INC (t.cursor, arg * Target.Byte);
    | -7 => (* Op.SkipB_N *)     INC (t.cursor, arg * Target.Byte);
    | -8 =>                      INC (t.cursor, Target.Address.size)
    | -9 =>                      INC (t.cursor, Target.Real.size)
    | -10 =>                     INC (t.cursor, Target.Longreal.size)
    | -11 =>                     INC (t.cursor, Target.Extended.size)
    ELSE    (* fixed update *)   INC (t.cursor, x);
    END;
  END Add;

PROCEDURE IntSize (i: INTEGER): CARDINAL =
  VAR n : CARDINAL := 0;
  BEGIN
    REPEAT
      INC (n);
      i := Word.RightShift (i, 8);
    UNTIL (i = 0);
    RETURN n;
  END IntSize;

PROCEDURE GetCursor (t: T): INTEGER =
  BEGIN
    RETURN t.cursor;
  END GetCursor;

PROCEDURE SetCursor (t: T; x: INTEGER) =
  BEGIN
    t.cursor := x;
  END SetCursor;

PROCEDURE ExpandBytes (t: T) =
  VAR new := NEW (ByteList, 2 * NUMBER (t.bytes^));
  BEGIN
    SUBARRAY (new^, 0, NUMBER(t.bytes^)) := t.bytes^;
    t.bytes := new;
  END ExpandBytes;

BEGIN
END TypeComp.
