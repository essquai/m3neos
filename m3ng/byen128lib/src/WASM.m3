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
    
END WASM.
