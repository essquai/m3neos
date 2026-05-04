UNSAFE MODULE WASM;

IMPORT M3toC, Ctypes;
IMPORT IO, Fmt, Wr;


(* Return the module in source(WAT) form *)
PROCEDURE ModuleWAT( module: ModuleRef ) : TEXT =
  VAR s : Ctypes.char_star;
  BEGIN
    s := RefWAT( module );
    RETURN M3toC.CopyStoT(s);
  END ModuleWAT;

(* Return the module in object(WASM) form *)
PROCEDURE ModuleObject( module: ModuleRef; VAR output: UNTRACED REF ARRAY OF CHAR; VAR sourceMap: TEXT ) : CARDINAL =
  VAR
    s       : Ctypes.char_star;
    objLen  : CARDINAL;
    srcMap  := "sourceMapUrl";
    writeRes: WriteResult;
    x       : INTEGER;
  BEGIN
    writeRes  := RefAllocateAndWrite(module, M3toC.FlatTtoS(srcMap));
    x := LOOPHOLE(writeRes.binary, INTEGER);
    IO.Put("ModObject:binary=" & Fmt.Unsigned(x) & Wr.EOL);
    IO.Put("ModObject:binaryBytes=" & Fmt.Int(writeRes.binaryBytes) & Wr.EOL);
    x := LOOPHOLE(writeRes.sourceMap, INTEGER);
    IO.Put("ModObject:sourceMap=" & Fmt.Unsigned(x) & Wr.EOL);
    output    := RefResultBinary(writeRes);
    objLen    := RefResultBytes(writeRes);
    s         := RefResultSourceMap(writeRes);
    sourceMap := M3toC.CopyStoT(s);
    RETURN objLen;
  END ModuleObject;

(* Create a compound type *)
PROCEDURE TypeCreate(valueTypes: REF ARRAY OF Type; numTypes: Index ): Type =
  VAR addrTypes : ADDRESS := NIL;
  BEGIN
    IF numTypes > 0 THEN
      addrTypes := ADR(valueTypes^[0]);
    END;
    RETURN BinaryenTypeCreate(addrTypes, numTypes);
  END TypeCreate;

(* Add a function to the module *)
PROCEDURE AddFunction(module: ModuleRef; name: Ctypes.char_star; params: Type; results: Type;
                      varTypes: REF ARRAY OF Type; numVarTypes: Index;
                      body: ExpressionRef ): FunctionRef =
  VAR addrTypes : ADDRESS := NIL;
  BEGIN
    IF numVarTypes > 0 THEN
      addrTypes := ADR(varTypes^[0]);
    END;
    RETURN BinaryenAddFunction(module, name, params, results, addrTypes, numVarTypes, body);
  END AddFunction;

(* Create a block *)
PROCEDURE Block(module: ModuleRef; label: Ctypes.char_star;
                children: REF ARRAY OF ExpressionRef; numChildren: Index;
                blockType: Type ): ExpressionRef =
  VAR addrChildren : ADDRESS := NIL;
  BEGIN
    IF numChildren > 0 THEN
      addrChildren := ADR(children^[0]);
    END;
    RETURN BinaryenBlock(module, label, addrChildren, numChildren, blockType);
  END Block;

(* Build a structure *)
PROCEDURE BuilderSetStruct(builder : BuilderRef; index : Index; fieldTypes: REF ARRAY OF Type;
                           fieldPacked : REF ARRAY OF Packed;
                           fieldMutable : REF ARRAY OF CHAR; numFields: Index) =
  VAR
    addrField: ADDRESS := NIL;
    addrPacked : ADDRESS := NIL;
    addrMutable : ADDRESS := NIL;
  BEGIN
    IF numFields > 0 THEN
      addrField := ADR(fieldTypes^[0]);
      addrPacked := ADR(fieldPacked^[0]);
      addrMutable := ADR(fieldMutable^[0]);
    END;
    TypeBuilderSetStructType(builder, index, addrField, addrPacked, addrMutable, numFields);
  END BuilderSetStruct;

(* Interim tuple type *)
PROCEDURE BuilderGetTempTuple(builder : BuilderRef; types: REF ARRAY OF Type;
                              numTypes: Index) : Type =
  BEGIN
    RETURN TypeBuilderGetTempTupleType(builder, ADR(types^[0]), numTypes);
  END BuilderGetTempTuple;


(* Register the types *)
PROCEDURE BuilderBuildAndDispose(builder : BuilderRef; heapTypes : REF ARRAY OF HeapTypeRef;
                                 VAR errorIndex : Index; VAR errorReason : BuilderError
                                ) : BOOLEAN =
  VAR
    addrHeaps: ADDRESS := ADR(heapTypes^[0]);
  BEGIN
    RETURN TypeBuilderBuildAndDispose(builder, addrHeaps, errorIndex, errorReason);
  END BuilderBuildAndDispose;

(* New Structure instruction *)
PROCEDURE StructNew(module: ModuleRef; operands: REF ARRAY OF ExpressionRef;
                    numOperands: Index; heapType: HeapTypeRef) : ExpressionRef =
  VAR addrOperands : ADDRESS := NIL;
  BEGIN
    IF numOperands > 0 THEN
      addrOperands := ADR(operands^[0]);
    END;
    RETURN BinaryenStructNew(module, addrOperands, numOperands, heapType);
  END StructNew;


BEGIN
  type_none          := TypeNone();
  type_i32           := TypeInt32();
  type_i64           := TypeInt64();
  type_f32           := TypeFloat32();
  type_f64           := TypeFloat64();
  type_v128          := TypeVec128();
  type_funcref       := TypeFuncref();
  type_externref     := TypeExternref();
  type_anyref        := TypeAnyref();
  type_eqref         := TypeEqref();
  type_i31ref        := TypeI31ref();
  type_structref     := TypeStructref();
  type_arrayref      := TypeArrayref();
  type_stringref     := TypeStringref();
  type_nullref       := TypeNullref();
  type_nullexternref := TypeNullExternref();
  type_nullfuncref   := TypeNullFuncref(); 
  type_unreachable   := TypeUnreachable();
  type_auto          := TypeAuto();

  pack_not           := PackedNot();
  pack_int8          := PackedInt8();
  pack_int16         := PackedInt16();

  op_ClzInt32 := ClzInt32();
  op_CtzInt32 := CtzInt32();
  op_PopcntInt32 := PopcntInt32();
  op_NegFloat32 := NegFloat32();
  op_AbsFloat32 := AbsFloat32();
  op_CeilFloat32 := CeilFloat32();
  op_FloorFloat32 := FloorFloat32();
  op_TruncFloat32 := TruncFloat32();
  op_NearestFloat32 := NearestFloat32();
  op_SqrtFloat32 := SqrtFloat32();
  op_EqZInt32 := EqZInt32();
  op_ClzInt64 := ClzInt64();
  op_CtzInt64 := CtzInt64();
  op_PopcntInt64 := PopcntInt64();
  op_NegFloat64 := NegFloat64();
  op_AbsFloat64 := AbsFloat64();
  op_CeilFloat64 := CeilFloat64();
  op_FloorFloat64 := FloorFloat64();
  op_TruncFloat64 := TruncFloat64();
  op_NearestFloat64 := NearestFloat64();
  op_SqrtFloat64 := SqrtFloat64();
  op_EqZInt64 := EqZInt64();
  op_ExtendSInt32 := ExtendSInt32();
  op_ExtendUInt32 := ExtendUInt32();
  op_WrapInt64 := WrapInt64();
  op_TruncSFloat32ToInt32 := TruncSFloat32ToInt32();
  op_TruncSFloat32ToInt64 := TruncSFloat32ToInt64();
  op_TruncUFloat32ToInt32 := TruncUFloat32ToInt32();
  op_TruncUFloat32ToInt64 := TruncUFloat32ToInt64();
  op_TruncSFloat64ToInt32 := TruncSFloat64ToInt32();
  op_TruncSFloat64ToInt64 := TruncSFloat64ToInt64();
  op_TruncUFloat64ToInt32 := TruncUFloat64ToInt32();
  op_TruncUFloat64ToInt64 := TruncUFloat64ToInt64();
  op_ReinterpretFloat32 := ReinterpretFloat32();
  op_ReinterpretFloat64 := ReinterpretFloat64();
  op_ConvertSInt32ToFloat32 := ConvertSInt32ToFloat32();
  op_ConvertSInt32ToFloat64 := ConvertSInt32ToFloat64();
  op_ConvertUInt32ToFloat32 := ConvertUInt32ToFloat32();
  op_ConvertUInt32ToFloat64 := ConvertUInt32ToFloat64();
  op_ConvertSInt64ToFloat32 := ConvertSInt64ToFloat32();
  op_ConvertSInt64ToFloat64 := ConvertSInt64ToFloat64();
  op_ConvertUInt64ToFloat32 := ConvertUInt64ToFloat32();
  op_ConvertUInt64ToFloat64 := ConvertUInt64ToFloat64();
  op_PromoteFloat32 := PromoteFloat32();
  op_DemoteFloat64 := DemoteFloat64();
  op_ReinterpretInt32 := ReinterpretInt32();
  op_ReinterpretInt64 := ReinterpretInt64();
  op_ExtendS8Int32 := ExtendS8Int32();
  op_ExtendS16Int32 := ExtendS16Int32();
  op_ExtendS8Int64 := ExtendS8Int64();
  op_ExtendS16Int64 := ExtendS16Int64();
  op_ExtendS32Int64 := ExtendS32Int64();
  op_AddInt32 := AddInt32();
  op_SubInt32 := SubInt32();
  op_MulInt32 := MulInt32();
  op_DivSInt32 := DivSInt32();
  op_DivUInt32 := DivUInt32();
  op_RemSInt32 := RemSInt32();
  op_RemUInt32 := RemUInt32();
  op_AndInt32 := AndInt32();
  op_OrInt32 := OrInt32();
  op_XorInt32 := XorInt32();
  op_ShlInt32 := ShlInt32();
  op_ShrUInt32 := ShrUInt32();
  op_ShrSInt32 := ShrSInt32();
  op_RotLInt32 := RotLInt32();
  op_RotRInt32 := RotRInt32();
  op_EqInt32 := EqInt32();
  op_NeInt32 := NeInt32();
  op_LtSInt32 := LtSInt32();
  op_LtUInt32 := LtUInt32();
  op_LeSInt32 := LeSInt32();
  op_LeUInt32 := LeUInt32();
  op_GtSInt32 := GtSInt32();
  op_GtUInt32 := GtUInt32();
  op_GeSInt32 := GeSInt32();
  op_GeUInt32 := GeUInt32();
  op_AddInt64 := AddInt64();
  op_SubInt64 := SubInt64();
  op_MulInt64 := MulInt64();
  op_DivSInt64 := DivSInt64();
  op_DivUInt64 := DivUInt64();
  op_RemSInt64 := RemSInt64();
  op_RemUInt64 := RemUInt64();
  op_AndInt64 := AndInt64();
  op_OrInt64 := OrInt64();
  op_XorInt64 := XorInt64();
  op_ShlInt64 := ShlInt64();
  op_ShrUInt64 := ShrUInt64();
  op_ShrSInt64 := ShrSInt64();
  op_RotLInt64 := RotLInt64();
  op_RotRInt64 := RotRInt64();
  op_EqInt64 := EqInt64();
  op_NeInt64 := NeInt64();
  op_LtSInt64 := LtSInt64();
  op_LtUInt64 := LtUInt64();
  op_LeSInt64 := LeSInt64();
  op_LeUInt64 := LeUInt64();
  op_GtSInt64 := GtSInt64();
  op_GtUInt64 := GtUInt64();
  op_GeSInt64 := GeSInt64();
  op_GeUInt64 := GeUInt64();
  op_AddFloat32 := AddFloat32();
  op_SubFloat32 := SubFloat32();
  op_MulFloat32 := MulFloat32();
  op_DivFloat32 := DivFloat32();
  op_CopySignFloat32 := CopySignFloat32();
  op_MinFloat32 := MinFloat32();
  op_MaxFloat32 := MaxFloat32();
  op_EqFloat32 := EqFloat32();
  op_NeFloat32 := NeFloat32();
  op_LtFloat32 := LtFloat32();
  op_LeFloat32 := LeFloat32();
  op_GtFloat32 := GtFloat32();
  op_GeFloat32 := GeFloat32();
  op_AddFloat64 := AddFloat64();
  op_SubFloat64 := SubFloat64();
  op_MulFloat64 := MulFloat64();
  op_DivFloat64 := DivFloat64();
  op_CopySignFloat64 := CopySignFloat64();
  op_MinFloat64 := MinFloat64();
  op_MaxFloat64 := MaxFloat64();
  op_EqFloat64 := EqFloat64();
  op_NeFloat64 := NeFloat64();
  op_LtFloat64 := LtFloat64();
  op_LeFloat64 := LeFloat64();
  op_GtFloat64 := GtFloat64();
  op_GeFloat64 := GeFloat64();
  op_AtomicRMWAdd := AtomicRMWAdd();
  op_AtomicRMWSub := AtomicRMWSub();
  op_AtomicRMWAnd := AtomicRMWAnd();
  op_AtomicRMWOr := AtomicRMWOr();
  op_AtomicRMWXor := AtomicRMWXor();
  op_AtomicRMWXchg := AtomicRMWXchg();
  op_TruncSatSFloat32ToInt32 := TruncSatSFloat32ToInt32();
  op_TruncSatSFloat32ToInt64 := TruncSatSFloat32ToInt64();
  op_TruncSatUFloat32ToInt32 := TruncSatUFloat32ToInt32();
  op_TruncSatUFloat32ToInt64 := TruncSatUFloat32ToInt64();
  op_TruncSatSFloat64ToInt32 := TruncSatSFloat64ToInt32();
  op_TruncSatSFloat64ToInt64 := TruncSatSFloat64ToInt64();
  op_TruncSatUFloat64ToInt32 := TruncSatUFloat64ToInt32();
  op_TruncSatUFloat64ToInt64 := TruncSatUFloat64ToInt64();
  op_RefAsNonNull := RefAsNonNull();
  op_RefAsExternInternalize := RefAsExternInternalize();
  op_RefAsExternExternalize := RefAsExternExternalize();
  op_RefAsAnyConvertExtern := RefAsAnyConvertExtern();
  op_RefAsExternConvertAny := RefAsExternConvertAny();
  op_BrOnNull := BrOnNull();
  op_BrOnNonNull := BrOnNonNull();
  op_BrOnCast := BrOnCast();
  op_BrOnCastFail := BrOnCastFail();
  op_StringNewLossyUTF8Array := StringNewLossyUTF8Array();
  op_StringNewWTF16Array := StringNewWTF16Array();
  op_StringNewFromCodePoint := StringNewFromCodePoint();
  op_StringMeasureUTF8 := StringMeasureUTF8();
  op_StringMeasureWTF16 := StringMeasureWTF16();
  op_StringEncodeLossyUTF8Array := StringEncodeLossyUTF8Array();
  op_StringEncodeWTF16Array := StringEncodeWTF16Array();
  op_StringEqEqual := StringEqEqual();
  op_StringEqCompare := StringEqCompare();

END WASM.
