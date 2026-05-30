(*
 * WASM.i3
 * 
 * Modula-3 interface for the Binaryen C API (Release 128)
 * 
 * Binaryen is a compiler and toolchain infrastructure library for WebAssembly.
 * This interface provides bindings to the C API for creating, analyzing,
 * transforming, and optimizing WebAssembly modules.
 *
 * Thread Safety Note:
 * - Expression creation can be parallelized (no global state)
 * - AddFunction is thread-safe
 * - Other operations (imports, exports, etc.) are NOT currently thread-safe
 *)

INTERFACE WASM;

FROM Ctypes IMPORT int, unsigned_int, unsigned_long, float, double, 
                    void_star, char_star;

(* ============================================================================
 * Core Types and References
 * ============================================================================ *)

(* Opaque reference types for Binaryen objects *)
TYPE
  Index = BITS 32 FOR [ 0 .. 16_FFFFFFFF];  (* for indexes and list sizes *)
  Op    = BITS 32 FOR [ 0 .. 16_FFFFFFFF];  (* for opcodes                *)
  Type  = unsigned_long;                    (* WebAssembly types          *)
  Features = BITS 32 FOR [ 0 .. 16_FFFFFFFF]; (* WASM Feature set         *)
  Packed = BITS 32 FOR [ 0 .. 16_FFFFFFFF]; (* for definitions            *)
  BuilderError = BITS 32 FOR [ 0 .. 16_FFFFFFFF]; (* type builder errcode *)

  
  (* Opaque references to Binaryen objects *)
  ModuleRef = void_star;
  FunctionRef = void_star;
  ExpressionRef = void_star;
  LocalRef = void_star;
  ImportRef = void_star;
  ExportRef = void_star;
  GlobalRef = void_star;
  HeapTypeRef = void_star;
  TableRef = void_star;
  BuilderRef = void_star;
  Literal = ARRAY [0..23] OF CHAR;
  WriteResult = RECORD
    binary : ADDRESS;
    binaryBytes : CARDINAL;
    sourceMap : ADDRESS;
  END;



(* ============================================================================
 * Types
 * ============================================================================ *)

VAR
  type_none: Type;
  type_i32: Type;
  type_i64: Type;
  type_f32: Type;
  type_f64: Type;
  type_v128: Type;
  type_funcref: Type;
  type_externref: Type;
  type_anyref: Type;
  type_eqref: Type;
  type_i31ref: Type;
  type_structref: Type;
  type_arrayref: Type;
  type_stringref: Type;
  type_nullref: Type;
  type_nullexternref: Type;
  type_nullfuncref: Type;
  type_unreachable: Type;
  type_auto: Type;

(* Return the none type *)
<*EXTERNAL "BinaryenTypeNone"*> PROCEDURE TypeNone(): Type;

(* Return the i32 type *)
<*EXTERNAL "BinaryenTypeInt32"*> PROCEDURE TypeInt32(): Type;

(* Return the i64 type *)
<*EXTERNAL "BinaryenTypeInt64"*> PROCEDURE TypeInt64(): Type;

(* Return the f32 type *)
<*EXTERNAL "BinaryenTypeFloat32"*> PROCEDURE TypeFloat32(): Type;

(* Return the f64 type *)
<*EXTERNAL "BinaryenTypeFloat64"*> PROCEDURE TypeFloat64(): Type;

(* Return the v128 type *)
<*EXTERNAL "BinaryenTypeVec128"*> PROCEDURE TypeVec128(): Type;

(* Return the funcref type *)
<*EXTERNAL "BinaryenTypeFuncref"*> PROCEDURE TypeFuncref(): Type;

(* Return the externref type *)
<*EXTERNAL "BinaryenTypeExternref"*> PROCEDURE TypeExternref(): Type;

(* Return the anyref type *)
<*EXTERNAL "BinaryenTypeAnyref"*> PROCEDURE TypeAnyref(): Type;

(* Return the eqref type *)
<*EXTERNAL "BinaryenTypeEqref"*> PROCEDURE TypeEqref(): Type;

(* Return the i31ref type *)
<*EXTERNAL "BinaryenTypeI31ref"*> PROCEDURE TypeI31ref(): Type;

(* Return the structref type *)
<*EXTERNAL "BinaryenTypeStructref"*> PROCEDURE TypeStructref() : Type;

(* Return the arrayref type *)
<*EXTERNAL "BinaryenTypeArrayref"*> PROCEDURE TypeArrayref() : Type;

(* Return the stringref type *)
<*EXTERNAL "BinaryenTypeStringref"*> PROCEDURE TypeStringref() : Type;

(* Return the nullref type *)
<*EXTERNAL "BinaryenTypeNullref"*> PROCEDURE TypeNullref() : Type;

(* Return the nullexternref type *)
<*EXTERNAL "BinaryenTypeNullExternref"*> PROCEDURE TypeNullExternref() : Type;

(* Return the nullfuncref type *)
<*EXTERNAL "BinaryenTypeNullFuncref"*> PROCEDURE TypeNullFuncref() : Type;

(* Return the unreachable type *)
<*EXTERNAL "BinaryenTypeUnreachable"*> PROCEDURE TypeUnreachable(): Type;

(* Return the auto type *)
<*EXTERNAL "BinaryenTypeAuto"*> PROCEDURE TypeAuto(): Type;

(* Create a compound type *)
<*EXTERNAL "BinaryenTypeCreate"*> PROCEDURE BinaryenTypeCreate(
    valueTypes: ADDRESS;
    numTypes: Index
): Type;

PROCEDURE TypeCreate(
    valueTypes: REF ARRAY OF Type;
    numTypes: Index
): Type;

(* Translate heap type to type *)
<*EXTERNAL "BinaryenTypeFromHeapType"*> PROCEDURE TypeFromHeap(
    heapType : HeapTypeRef;
    nullable : BOOLEAN) : Type;

(* ============================================================================
 * Module Creation and Management
 * ============================================================================ *)

(* Create a new, empty WebAssembly module *)
<*EXTERNAL "BinaryenModuleCreate"*> PROCEDURE ModuleCreate(): ModuleRef;

(* Add debug info file name to the module *)
<*EXTERNAL "BinaryenModuleAddDebugInfoFileName"*> PROCEDURE ModuleAddDebugFilename(
    module: ModuleRef;
    filename: char_star
): Index;

(* Dispose of a module and free associated memory *)
<*EXTERNAL "BinaryenModuleDispose"*> PROCEDURE ModuleDispose(module: ModuleRef);

<*EXTERNAL "BinaryenModuleSetFeatures"*> PROCEDURE ModuleSetFeatures(
    module: ModuleRef;
    features: Features
);

(* Gets the GC closed world setting *)
<*EXTERNAL "BinaryenGetClosedWorld"*> PROCEDURE ModuleGetWorld() : BOOLEAN;

(* Sets the GC closed world setting *)
<*EXTERNAL "BinaryenSetClosedWorld"*> PROCEDURE ModuleSetWorld(on : BOOLEAN);


(* ============================================================================
 * Module I/O Operations
 * ============================================================================ *)

(* Read a module from binary data *)
<*EXTERNAL "BinaryenModuleRead"*> PROCEDURE ModuleRead(
    input: char_star;
    inputSize: unsigned_long
): ModuleRef;


(* Create a C string representing the Module *)
<*EXTERNAL "BinaryenModuleAllocateAndWriteText"*> PROCEDURE RefWAT(
    module: ModuleRef
) : char_star;

(* Write an object Module and return the Results *)
<*EXTERNAL "BinaryenModuleAllocateAndWrite"*> PROCEDURE RefAllocateAndWrite(
    module : ModuleRef;
    srcMap: char_star
) : WriteResult;

(* Extract the binary field of the WriteResult *)
<*EXTERNAL "RefResultBinary"*> PROCEDURE RefResultBinary(
    VAR result: WriteResult
) : UNTRACED REF ARRAY OF CHAR;

(* Extract the byte count field of the WriteResult *)
<*EXTERNAL "RefResultBytes"*> PROCEDURE RefResultBytes(
    VAR result: WriteResult
) : CARDINAL;

(* Extract the source map field of the WriteResult *)
<*EXTERNAL "RefResultSourceMap"*> PROCEDURE RefResultSourceMap(
    VAR result: WriteResult
) : char_star;

(* Save to a file  *)
<*EXTERNAL "RefSave"*> PROCEDURE RefSave(
    file : char_star;
    buf  : ADDRESS;
    count : CARDINAL
) : Index;


(* Return the module in source(WAT) form *)
PROCEDURE ModuleWAT(
    module: ModuleRef
) : TEXT;

(* Return the module in object(WASM) form *)
PROCEDURE ModuleObject(
    module: ModuleRef;
    VAR output: UNTRACED REF ARRAY OF CHAR;
    VAR sourceMap: TEXT
) : CARDINAL;

(* Validate a module *)
<*EXTERNAL "BinaryenModuleValidate"*> PROCEDURE ModuleValidate(module: ModuleRef): int;


(* ============================================================================
 * Function Management
 * ============================================================================ *)

(* Add a function to a module.
 * 
 * params: Combined type of all parameters (use TypeCreate)
 * results: Combined type of all results (use TypeCreate)
 * varTypes: Array of local variable types
 * numVarTypes: Number of local variables
 * body: Expression representing the function body
 *)
(* Add a function *)
PROCEDURE AddFunction(
    module: ModuleRef;
    name: char_star;
    params: Type;
    results: Type;
    varTypes: REF ARRAY OF Type;
    numVarTypes: Index;
    body: ExpressionRef
): FunctionRef;

(* Linked version *)
<*EXTERNAL "BinaryenAddFunction"*> PROCEDURE BinaryenAddFunction(
    module: ModuleRef;
    name: char_star;
    params: Type;
    results: Type;
    varTypes: ADDRESS;
    numVarTypes: Index;
    body: ExpressionRef
): FunctionRef;

(* Set function var name *)
<*EXTERNAL "BinaryenFunctionSetLocalName"*> PROCEDURE FunctionSetLocalName(
    func: FunctionRef;
    index: Index;
    name: char_star
);

(* Get a function by name *)
<*EXTERNAL "BinaryenGetFunction"*> PROCEDURE GetFunction(
    module: ModuleRef;
    name: char_star
): FunctionRef;

(* Remove a function by name *)
<*EXTERNAL "BinaryenRemoveFunction"*> PROCEDURE RemoveFunction(
    module: ModuleRef;
    name: char_star
);

(* Get the number of functions in a module *)
<*EXTERNAL "BinaryenGetNumFunctions"*> PROCEDURE GetNumFunctions(module: ModuleRef): Index;

(* Define the module start function *)
<*EXTERNAL "BinaryenSetStart"*> PROCEDURE SetStart(
    module: ModuleRef;
    start: FunctionRef
);

(* Function Debug information *)
<*EXTERNAL "BinaryenFunctionSetDebugLocation"*> PROCEDURE FunctionSetDebug(
    func: FunctionRef;
    expr: ExpressionRef;
    fileIndex: Index;
    lineNumber: Index;
    columnNumber: Index
);


(* ============================================================================
 * Import Management
 * ============================================================================ *)

(* Add a function import to a module *)
<*EXTERNAL "BinaryenAddFunctionImport"*> PROCEDURE AddFunctionImport(
    module: ModuleRef;
    internalName: char_star;
    externalModule: char_star;
    externalBase: char_star;
    params: Type;
    results: Type
);

(* Add a global variable import *)
<*EXTERNAL "BinaryenAddGlobalImport"*> PROCEDURE AddGlobalImport(
    module: ModuleRef;
    internalName: char_star;
    externalModule: char_star;
    externalBase: char_star;
    globalType: Type;
    mutable: int
);

(* Add a memory import *)
<*EXTERNAL "BinaryenAddMemoryImport"*> PROCEDURE AddMemoryImport(
    module: ModuleRef;
    internalName: char_star;
    externalModule: char_star;
    externalBase: char_star;
    shared: int
);

(* Add a table import *)
<*EXTERNAL "BinaryenAddTableImport"*> PROCEDURE AddTableImport(
    module: ModuleRef;
    internalName: char_star;
    externalModule: char_star;
    externalBase: char_star
);

(* ============================================================================
 * Export Management
 * ============================================================================ *)

(* Add a function export *)
<*EXTERNAL "BinaryenAddFunctionExport"*> PROCEDURE AddFunctionExport(
    module: ModuleRef;
    internalName: char_star;
    externalName: char_star
): ExportRef;

(* Add a global variable export *)
<*EXTERNAL "BinaryenAddGlobalExport"*> PROCEDURE AddGlobalExport(
    module: ModuleRef;
    internalName: char_star;
    externalName: char_star
): ExportRef;

(* Add a memory export *)
<*EXTERNAL "BinaryenAddMemoryExport"*> PROCEDURE AddMemoryExport(
    module: ModuleRef;
    internalName: char_star;
    externalName: char_star
): ExportRef;

(* set a table *)
<*EXTERNAL "BinaryenTableSet"*> PROCEDURE TableSet(
    module: ModuleRef;
    name: char_star;
    index: ExpressionRef;
    value: ExpressionRef
): ExpressionRef;

(* Add a table export *)
<*EXTERNAL "BinaryenAddTableExport"*> PROCEDURE AddTableExport(
    module: ModuleRef;
    internalName: char_star;
    externalName: char_star
): ExportRef;

(* ============================================================================
 * Global Variable Management
 * ============================================================================ *)

(* Add a global variable to the module *)
<*EXTERNAL "BinaryenAddGlobal"*> PROCEDURE AddGlobal(
    module: ModuleRef;
    name: char_star;
    globalType: Type;
    mutable: int;
    init: ExpressionRef
): GlobalRef;

(* Get a global by name *)
<*EXTERNAL "BinaryenGetGlobal"*> PROCEDURE GetGlobal(
    module: ModuleRef;
    name: char_star
): GlobalRef;

(* ============================================================================
 * Memory and Table Management
 * ============================================================================ *)

(* Create a memory.init instruction *)
<*EXTERNAL "BinaryenMemoryInit"*> PROCEDURE MemoryInit(
    module: ModuleRef;
    segment: unsigned_int;
    dest: ExpressionRef;
    offset: ExpressionRef;
    size: ExpressionRef
) : ExpressionRef;

(* Create a memory.copy instruction *)
<*EXTERNAL "BinaryenMemoryCopy"*> PROCEDURE MemoryCopy(
    module: ModuleRef;
    dest: ExpressionRef;
    source: ExpressionRef;
    size: ExpressionRef
) : ExpressionRef;

(* Create a memory.fill instruction *)
<*EXTERNAL "BinaryenMemoryFill"*> PROCEDURE MemoryFill(
    module: ModuleRef;
    dest: ExpressionRef;
    value: ExpressionRef;
    size: ExpressionRef
) : ExpressionRef;

(* Set the memory configuration *)
<*EXTERNAL "BinaryenSetMemory"*> PROCEDURE SetMemory(
    module: ModuleRef;
    initial: unsigned_int;
    maximum: unsigned_int;
    hasMax: int;
    segments: void_star;
    segmentPassive: UNTRACED REF int;
    segmentOffsets: UNTRACED REF ExpressionRef;
    segmentSizes: UNTRACED REF unsigned_long;
    numSegments: unsigned_int;
    shared: int
);

(* Add a table *)
<*EXTERNAL "BinaryenAddTable"*> PROCEDURE AddTable(
    module: ModuleRef;
    name: char_star;
    initial: Index;
    max: Index;
    tableType: Type
) : TableRef;

(* Set table size *)
<*EXTERNAL "BinaryenTableSetMax"*> PROCEDURE TableSetMax(
    table: TableRef;
    max: Index
);

(* ============================================================================
 * Literal Creation - Constants
 * ============================================================================ *)

(* Create an i32 literal *)
<*EXTERNAL "BinaryenLiteralInt32"*> PROCEDURE LiteralInt32(value: int): Literal;

(* Create an i64 literal *)
<*EXTERNAL "BinaryenLiteralInt64"*> PROCEDURE LiteralInt64(value: unsigned_long): Literal;

(* Create an f32 literal *)
<*EXTERNAL "BinaryenLiteralFloat32"*> PROCEDURE LiteralFloat32(value: float): Literal;

(* Create an f64 literal *)
<*EXTERNAL "BinaryenLiteralFloat64"*> PROCEDURE LiteralFloat64(value: double): Literal;

(* ============================================================================
 * Type Management - Garbage Collection
 * ============================================================================ *)
VAR
  pack_not: Packed;
  pack_int8: Packed;
  pack_int16: Packed;

(* Packed Types *)
<*EXTERNAL "BinaryenPackedTypeNotPacked"*> PROCEDURE PackedNot(): Packed;
<*EXTERNAL "BinaryenPackedTypeInt8"*> PROCEDURE PackedInt8(): Packed;
<*EXTERNAL "BinaryenPackedTypeInt16"*> PROCEDURE PackedInt16(): Packed;

(* Create a builder *)
<*EXTERNAL "TypeBuilderCreate"*> PROCEDURE BuilderCreate(size : Index) : BuilderRef;

(* Define Recursion Group *)
<*EXTERNAL "TypeBuilderCreateRecGroup"*> PROCEDURE BuilderRecGroup(
    builder : BuilderRef;
    index : Index;
    length : Index);

(* Declare a structure *)
<*EXTERNAL "TypeBuilderSetStructType"*> PROCEDURE TypeBuilderSetStructType(
    builder : BuilderRef;
    index : Index;
    fieldTypes: ADDRESS;
    packedPackedTypes : ADDRESS;
    fieldMutables : ADDRESS;
    numFields: Index
);

PROCEDURE BuilderSetStruct(
    builder : BuilderRef;
    index : Index;
    fieldTypes: REF ARRAY OF Type;
    fieldPacked : REF ARRAY OF Packed;
    fieldMutables : REF ARRAY OF CHAR;
    numFields: Index
);

(* Declare an Array *)
<* EXTERNAL "TypeBuilderSetArrayType"*> PROCEDURE BuilderSetArray(
    builder : BuilderRef;
    index : Index;
    elementType : Type;
    elementPackedType : Packed;
    elementMutable : Index);

(* Declare a signature *)
<*EXTERNAL "TypeBuilderSetSignatureType"*> PROCEDURE BuilderSetSignature(
    builder : BuilderRef;
    index : Index;
    paramTypes: Type;
    resultTypes : Type);

(* Get interim heap type *)
<* EXTERNAL "TypeBuilderGetTempHeapType"*> PROCEDURE BuilderGetTempHeapType(
    builder : BuilderRef;
    index : Index) : HeapTypeRef;

(* Get interim ref type *)
<* EXTERNAL "TypeBuilderGetTempRefType"*> PROCEDURE BuilderGetTempRefType(
    builder : BuilderRef;
    heapType : HeapTypeRef;
    nullable : Index) : Type;

(* Get interim tuple type *)
<*EXTERNAL "TypeBuilderGetTempTupleType"*> PROCEDURE TypeBuilderGetTempTupleType(
    builder : BuilderRef;
    types: ADDRESS;
    numTypes: Index
): Type;

PROCEDURE BuilderGetTempTuple(
    builder : BuilderRef;
    types: REF ARRAY OF Type;
    numTypes: Index
): Type;



(* Register the types *)
<* EXTERNAL "TypeBuilderBuildAndDispose"*> PROCEDURE TypeBuilderBuildAndDispose(
    builder : BuilderRef;
    heapTypes : ADDRESS;
    VAR errorIndex : Index;
    VAR errorReason : BuilderError) : BOOLEAN;

PROCEDURE BuilderBuildAndDispose(
    builder : BuilderRef;
    heapTypes : REF ARRAY OF HeapTypeRef;
    VAR errorIndex : Index;
    VAR errorReason : BuilderError) : BOOLEAN;

(* Set names for a type *)
<* EXTERNAL "BinaryenModuleSetTypeName" *> PROCEDURE ModuleSetTypeName(
    module: ModuleRef;
    heapType: HeapTypeRef;
    name: char_star);

(* Set the name for a type field *)
<* EXTERNAL "BinaryenModuleSetFieldName" *> PROCEDURE ModuleSetFieldName(
    module: ModuleRef;
    heapType: HeapTypeRef;
    index: Index;
    name: char_star);

(* ============================================================================
 * Op codes
 * ============================================================================ *)

VAR
  op_ClzInt32 : Op;
  op_CtzInt32 : Op;
  op_PopcntInt32 : Op;
  op_NegFloat32 : Op;
  op_AbsFloat32 : Op;
  op_CeilFloat32 : Op;
  op_FloorFloat32 : Op;
  op_TruncFloat32 : Op;
  op_NearestFloat32 : Op;
  op_SqrtFloat32 : Op;
  op_EqZInt32 : Op;
  op_ClzInt64 : Op;
  op_CtzInt64 : Op;
  op_PopcntInt64 : Op;
  op_NegFloat64 : Op;
  op_AbsFloat64 : Op;
  op_CeilFloat64 : Op;
  op_FloorFloat64 : Op;
  op_TruncFloat64 : Op;
  op_NearestFloat64 : Op;
  op_SqrtFloat64 : Op;
  op_EqZInt64 : Op;
  op_ExtendSInt32 : Op;
  op_ExtendUInt32 : Op;
  op_WrapInt64 : Op;
  op_TruncSFloat32ToInt32 : Op;
  op_TruncSFloat32ToInt64 : Op;
  op_TruncUFloat32ToInt32 : Op;
  op_TruncUFloat32ToInt64 : Op;
  op_TruncSFloat64ToInt32 : Op;
  op_TruncSFloat64ToInt64 : Op;
  op_TruncUFloat64ToInt32 : Op;
  op_TruncUFloat64ToInt64 : Op;
  op_ReinterpretFloat32 : Op;
  op_ReinterpretFloat64 : Op;
  op_ConvertSInt32ToFloat32 : Op;
  op_ConvertSInt32ToFloat64 : Op;
  op_ConvertUInt32ToFloat32 : Op;
  op_ConvertUInt32ToFloat64 : Op;
  op_ConvertSInt64ToFloat32 : Op;
  op_ConvertSInt64ToFloat64 : Op;
  op_ConvertUInt64ToFloat32 : Op;
  op_ConvertUInt64ToFloat64 : Op;
  op_PromoteFloat32 : Op;
  op_DemoteFloat64 : Op;
  op_ReinterpretInt32 : Op;
  op_ReinterpretInt64 : Op;
  op_ExtendS8Int32 : Op;
  op_ExtendS16Int32 : Op;
  op_ExtendS8Int64 : Op;
  op_ExtendS16Int64 : Op;
  op_ExtendS32Int64 : Op;
  op_AddInt32 : Op;
  op_SubInt32 : Op;
  op_MulInt32 : Op;
  op_DivSInt32 : Op;
  op_DivUInt32 : Op;
  op_RemSInt32 : Op;
  op_RemUInt32 : Op;
  op_AndInt32 : Op;
  op_OrInt32 : Op;
  op_XorInt32 : Op;
  op_ShlInt32 : Op;
  op_ShrUInt32 : Op;
  op_ShrSInt32 : Op;
  op_RotLInt32 : Op;
  op_RotRInt32 : Op;
  op_EqInt32 : Op;
  op_NeInt32 : Op;
  op_LtSInt32 : Op;
  op_LtUInt32 : Op;
  op_LeSInt32 : Op;
  op_LeUInt32 : Op;
  op_GtSInt32 : Op;
  op_GtUInt32 : Op;
  op_GeSInt32 : Op;
  op_GeUInt32 : Op;
  op_AddInt64 : Op;
  op_SubInt64 : Op;
  op_MulInt64 : Op;
  op_DivSInt64 : Op;
  op_DivUInt64 : Op;
  op_RemSInt64 : Op;
  op_RemUInt64 : Op;
  op_AndInt64 : Op;
  op_OrInt64 : Op;
  op_XorInt64 : Op;
  op_ShlInt64 : Op;
  op_ShrUInt64 : Op;
  op_ShrSInt64 : Op;
  op_RotLInt64 : Op;
  op_RotRInt64 : Op;
  op_EqInt64 : Op;
  op_NeInt64 : Op;
  op_LtSInt64 : Op;
  op_LtUInt64 : Op;
  op_LeSInt64 : Op;
  op_LeUInt64 : Op;
  op_GtSInt64 : Op;
  op_GtUInt64 : Op;
  op_GeSInt64 : Op;
  op_GeUInt64 : Op;
  op_AddFloat32 : Op;
  op_SubFloat32 : Op;
  op_MulFloat32 : Op;
  op_DivFloat32 : Op;
  op_CopySignFloat32 : Op;
  op_MinFloat32 : Op;
  op_MaxFloat32 : Op;
  op_EqFloat32 : Op;
  op_NeFloat32 : Op;
  op_LtFloat32 : Op;
  op_LeFloat32 : Op;
  op_GtFloat32 : Op;
  op_GeFloat32 : Op;
  op_AddFloat64 : Op;
  op_SubFloat64 : Op;
  op_MulFloat64 : Op;
  op_DivFloat64 : Op;
  op_CopySignFloat64 : Op;
  op_MinFloat64 : Op;
  op_MaxFloat64 : Op;
  op_EqFloat64 : Op;
  op_NeFloat64 : Op;
  op_LtFloat64 : Op;
  op_LeFloat64 : Op;
  op_GtFloat64 : Op;
  op_GeFloat64 : Op;
  op_AtomicRMWAdd : Op;
  op_AtomicRMWSub : Op;
  op_AtomicRMWAnd : Op;
  op_AtomicRMWOr : Op;
  op_AtomicRMWXor : Op;
  op_AtomicRMWXchg : Op;
  op_TruncSatSFloat32ToInt32 : Op;
  op_TruncSatSFloat32ToInt64 : Op;
  op_TruncSatUFloat32ToInt32 : Op;
  op_TruncSatUFloat32ToInt64 : Op;
  op_TruncSatSFloat64ToInt32 : Op;
  op_TruncSatSFloat64ToInt64 : Op;
  op_TruncSatUFloat64ToInt32 : Op;
  op_TruncSatUFloat64ToInt64 : Op;
  op_RefAsNonNull : Op;
  op_RefAsExternInternalize : Op;
  op_RefAsExternExternalize : Op;
  op_RefAsAnyConvertExtern : Op;
  op_RefAsExternConvertAny : Op;
  op_BrOnNull : Op;
  op_BrOnNonNull : Op;
  op_BrOnCast : Op;
  op_BrOnCastFail : Op;
  op_StringNewLossyUTF8Array : Op;
  op_StringNewWTF16Array : Op;
  op_StringNewFromCodePoint : Op;
  op_StringMeasureUTF8 : Op;
  op_StringMeasureWTF16 : Op;
  op_StringEncodeLossyUTF8Array : Op;
  op_StringEncodeWTF16Array : Op;
  op_StringEqEqual : Op;
  op_StringEqCompare : Op;

<* EXTERNAL "BinaryenClzInt32" *> PROCEDURE ClzInt32() : Op;
<* EXTERNAL "BinaryenCtzInt32" *> PROCEDURE CtzInt32() : Op;
<* EXTERNAL "BinaryenPopcntInt32" *> PROCEDURE PopcntInt32() : Op;
<* EXTERNAL "BinaryenNegFloat32" *> PROCEDURE NegFloat32() : Op;
<* EXTERNAL "BinaryenAbsFloat32" *> PROCEDURE AbsFloat32() : Op;
<* EXTERNAL "BinaryenCeilFloat32" *> PROCEDURE CeilFloat32() : Op;
<* EXTERNAL "BinaryenFloorFloat32" *> PROCEDURE FloorFloat32() : Op;
<* EXTERNAL "BinaryenTruncFloat32" *> PROCEDURE TruncFloat32() : Op;
<* EXTERNAL "BinaryenNearestFloat32" *> PROCEDURE NearestFloat32() : Op;
<* EXTERNAL "BinaryenSqrtFloat32" *> PROCEDURE SqrtFloat32() : Op;
<* EXTERNAL "BinaryenEqZInt32" *> PROCEDURE EqZInt32() : Op;
<* EXTERNAL "BinaryenClzInt64" *> PROCEDURE ClzInt64() : Op;
<* EXTERNAL "BinaryenCtzInt64" *> PROCEDURE CtzInt64() : Op;
<* EXTERNAL "BinaryenPopcntInt64" *> PROCEDURE PopcntInt64() : Op;
<* EXTERNAL "BinaryenNegFloat64" *> PROCEDURE NegFloat64() : Op;
<* EXTERNAL "BinaryenAbsFloat64" *> PROCEDURE AbsFloat64() : Op;
<* EXTERNAL "BinaryenCeilFloat64" *> PROCEDURE CeilFloat64() : Op;
<* EXTERNAL "BinaryenFloorFloat64" *> PROCEDURE FloorFloat64() : Op;
<* EXTERNAL "BinaryenTruncFloat64" *> PROCEDURE TruncFloat64() : Op;
<* EXTERNAL "BinaryenNearestFloat64" *> PROCEDURE NearestFloat64() : Op;
<* EXTERNAL "BinaryenSqrtFloat64" *> PROCEDURE SqrtFloat64() : Op;
<* EXTERNAL "BinaryenEqZInt64" *> PROCEDURE EqZInt64() : Op;
<* EXTERNAL "BinaryenExtendSInt32" *> PROCEDURE ExtendSInt32() : Op;
<* EXTERNAL "BinaryenExtendUInt32" *> PROCEDURE ExtendUInt32() : Op;
<* EXTERNAL "BinaryenWrapInt64" *> PROCEDURE WrapInt64() : Op;
<* EXTERNAL "BinaryenTruncSFloat32ToInt32" *> PROCEDURE TruncSFloat32ToInt32() : Op;
<* EXTERNAL "BinaryenTruncSFloat32ToInt64" *> PROCEDURE TruncSFloat32ToInt64() : Op;
<* EXTERNAL "BinaryenTruncUFloat32ToInt32" *> PROCEDURE TruncUFloat32ToInt32() : Op;
<* EXTERNAL "BinaryenTruncUFloat32ToInt64" *> PROCEDURE TruncUFloat32ToInt64() : Op;
<* EXTERNAL "BinaryenTruncSFloat64ToInt32" *> PROCEDURE TruncSFloat64ToInt32() : Op;
<* EXTERNAL "BinaryenTruncSFloat64ToInt64" *> PROCEDURE TruncSFloat64ToInt64() : Op;
<* EXTERNAL "BinaryenTruncUFloat64ToInt32" *> PROCEDURE TruncUFloat64ToInt32() : Op;
<* EXTERNAL "BinaryenTruncUFloat64ToInt64" *> PROCEDURE TruncUFloat64ToInt64() : Op;
<* EXTERNAL "BinaryenReinterpretFloat32" *> PROCEDURE ReinterpretFloat32() : Op;
<* EXTERNAL "BinaryenReinterpretFloat64" *> PROCEDURE ReinterpretFloat64() : Op;
<* EXTERNAL "BinaryenConvertSInt32ToFloat32" *> PROCEDURE ConvertSInt32ToFloat32() : Op;
<* EXTERNAL "BinaryenConvertSInt32ToFloat64" *> PROCEDURE ConvertSInt32ToFloat64() : Op;
<* EXTERNAL "BinaryenConvertUInt32ToFloat32" *> PROCEDURE ConvertUInt32ToFloat32() : Op;
<* EXTERNAL "BinaryenConvertUInt32ToFloat64" *> PROCEDURE ConvertUInt32ToFloat64() : Op;
<* EXTERNAL "BinaryenConvertSInt64ToFloat32" *> PROCEDURE ConvertSInt64ToFloat32() : Op;
<* EXTERNAL "BinaryenConvertSInt64ToFloat64" *> PROCEDURE ConvertSInt64ToFloat64() : Op;
<* EXTERNAL "BinaryenConvertUInt64ToFloat32" *> PROCEDURE ConvertUInt64ToFloat32() : Op;
<* EXTERNAL "BinaryenConvertUInt64ToFloat64" *> PROCEDURE ConvertUInt64ToFloat64() : Op;
<* EXTERNAL "BinaryenPromoteFloat32" *> PROCEDURE PromoteFloat32() : Op;
<* EXTERNAL "BinaryenDemoteFloat64" *> PROCEDURE DemoteFloat64() : Op;
<* EXTERNAL "BinaryenReinterpretInt32" *> PROCEDURE ReinterpretInt32() : Op;
<* EXTERNAL "BinaryenReinterpretInt64" *> PROCEDURE ReinterpretInt64() : Op;
<* EXTERNAL "BinaryenExtendS8Int32" *> PROCEDURE ExtendS8Int32() : Op;
<* EXTERNAL "BinaryenExtendS16Int32" *> PROCEDURE ExtendS16Int32() : Op;
<* EXTERNAL "BinaryenExtendS8Int64" *> PROCEDURE ExtendS8Int64() : Op;
<* EXTERNAL "BinaryenExtendS16Int64" *> PROCEDURE ExtendS16Int64() : Op;
<* EXTERNAL "BinaryenExtendS32Int64" *> PROCEDURE ExtendS32Int64() : Op;
<* EXTERNAL "BinaryenAddInt32" *> PROCEDURE AddInt32() : Op;
<* EXTERNAL "BinaryenSubInt32" *> PROCEDURE SubInt32() : Op;
<* EXTERNAL "BinaryenMulInt32" *> PROCEDURE MulInt32() : Op;
<* EXTERNAL "BinaryenDivSInt32" *> PROCEDURE DivSInt32() : Op;
<* EXTERNAL "BinaryenDivUInt32" *> PROCEDURE DivUInt32() : Op;
<* EXTERNAL "BinaryenRemSInt32" *> PROCEDURE RemSInt32() : Op;
<* EXTERNAL "BinaryenRemUInt32" *> PROCEDURE RemUInt32() : Op;
<* EXTERNAL "BinaryenAndInt32" *> PROCEDURE AndInt32() : Op;
<* EXTERNAL "BinaryenOrInt32" *> PROCEDURE OrInt32() : Op;
<* EXTERNAL "BinaryenXorInt32" *> PROCEDURE XorInt32() : Op;
<* EXTERNAL "BinaryenShlInt32" *> PROCEDURE ShlInt32() : Op;
<* EXTERNAL "BinaryenShrUInt32" *> PROCEDURE ShrUInt32() : Op;
<* EXTERNAL "BinaryenShrSInt32" *> PROCEDURE ShrSInt32() : Op;
<* EXTERNAL "BinaryenRotLInt32" *> PROCEDURE RotLInt32() : Op;
<* EXTERNAL "BinaryenRotRInt32" *> PROCEDURE RotRInt32() : Op;
<* EXTERNAL "BinaryenEqInt32" *> PROCEDURE EqInt32() : Op;
<* EXTERNAL "BinaryenNeInt32" *> PROCEDURE NeInt32() : Op;
<* EXTERNAL "BinaryenLtSInt32" *> PROCEDURE LtSInt32() : Op;
<* EXTERNAL "BinaryenLtUInt32" *> PROCEDURE LtUInt32() : Op;
<* EXTERNAL "BinaryenLeSInt32" *> PROCEDURE LeSInt32() : Op;
<* EXTERNAL "BinaryenLeUInt32" *> PROCEDURE LeUInt32() : Op;
<* EXTERNAL "BinaryenGtSInt32" *> PROCEDURE GtSInt32() : Op;
<* EXTERNAL "BinaryenGtUInt32" *> PROCEDURE GtUInt32() : Op;
<* EXTERNAL "BinaryenGeSInt32" *> PROCEDURE GeSInt32() : Op;
<* EXTERNAL "BinaryenGeUInt32" *> PROCEDURE GeUInt32() : Op;
<* EXTERNAL "BinaryenAddInt64" *> PROCEDURE AddInt64() : Op;
<* EXTERNAL "BinaryenSubInt64" *> PROCEDURE SubInt64() : Op;
<* EXTERNAL "BinaryenMulInt64" *> PROCEDURE MulInt64() : Op;
<* EXTERNAL "BinaryenDivSInt64" *> PROCEDURE DivSInt64() : Op;
<* EXTERNAL "BinaryenDivUInt64" *> PROCEDURE DivUInt64() : Op;
<* EXTERNAL "BinaryenRemSInt64" *> PROCEDURE RemSInt64() : Op;
<* EXTERNAL "BinaryenRemUInt64" *> PROCEDURE RemUInt64() : Op;
<* EXTERNAL "BinaryenAndInt64" *> PROCEDURE AndInt64() : Op;
<* EXTERNAL "BinaryenOrInt64" *> PROCEDURE OrInt64() : Op;
<* EXTERNAL "BinaryenXorInt64" *> PROCEDURE XorInt64() : Op;
<* EXTERNAL "BinaryenShlInt64" *> PROCEDURE ShlInt64() : Op;
<* EXTERNAL "BinaryenShrUInt64" *> PROCEDURE ShrUInt64() : Op;
<* EXTERNAL "BinaryenShrSInt64" *> PROCEDURE ShrSInt64() : Op;
<* EXTERNAL "BinaryenRotLInt64" *> PROCEDURE RotLInt64() : Op;
<* EXTERNAL "BinaryenRotRInt64" *> PROCEDURE RotRInt64() : Op;
<* EXTERNAL "BinaryenEqInt64" *> PROCEDURE EqInt64() : Op;
<* EXTERNAL "BinaryenNeInt64" *> PROCEDURE NeInt64() : Op;
<* EXTERNAL "BinaryenLtSInt64" *> PROCEDURE LtSInt64() : Op;
<* EXTERNAL "BinaryenLtUInt64" *> PROCEDURE LtUInt64() : Op;
<* EXTERNAL "BinaryenLeSInt64" *> PROCEDURE LeSInt64() : Op;
<* EXTERNAL "BinaryenLeUInt64" *> PROCEDURE LeUInt64() : Op;
<* EXTERNAL "BinaryenGtSInt64" *> PROCEDURE GtSInt64() : Op;
<* EXTERNAL "BinaryenGtUInt64" *> PROCEDURE GtUInt64() : Op;
<* EXTERNAL "BinaryenGeSInt64" *> PROCEDURE GeSInt64() : Op;
<* EXTERNAL "BinaryenGeUInt64" *> PROCEDURE GeUInt64() : Op;
<* EXTERNAL "BinaryenAddFloat32" *> PROCEDURE AddFloat32() : Op;
<* EXTERNAL "BinaryenSubFloat32" *> PROCEDURE SubFloat32() : Op;
<* EXTERNAL "BinaryenMulFloat32" *> PROCEDURE MulFloat32() : Op;
<* EXTERNAL "BinaryenDivFloat32" *> PROCEDURE DivFloat32() : Op;
<* EXTERNAL "BinaryenCopySignFloat32" *> PROCEDURE CopySignFloat32() : Op;
<* EXTERNAL "BinaryenMinFloat32" *> PROCEDURE MinFloat32() : Op;
<* EXTERNAL "BinaryenMaxFloat32" *> PROCEDURE MaxFloat32() : Op;
<* EXTERNAL "BinaryenEqFloat32" *> PROCEDURE EqFloat32() : Op;
<* EXTERNAL "BinaryenNeFloat32" *> PROCEDURE NeFloat32() : Op;
<* EXTERNAL "BinaryenLtFloat32" *> PROCEDURE LtFloat32() : Op;
<* EXTERNAL "BinaryenLeFloat32" *> PROCEDURE LeFloat32() : Op;
<* EXTERNAL "BinaryenGtFloat32" *> PROCEDURE GtFloat32() : Op;
<* EXTERNAL "BinaryenGeFloat32" *> PROCEDURE GeFloat32() : Op;
<* EXTERNAL "BinaryenAddFloat64" *> PROCEDURE AddFloat64() : Op;
<* EXTERNAL "BinaryenSubFloat64" *> PROCEDURE SubFloat64() : Op;
<* EXTERNAL "BinaryenMulFloat64" *> PROCEDURE MulFloat64() : Op;
<* EXTERNAL "BinaryenDivFloat64" *> PROCEDURE DivFloat64() : Op;
<* EXTERNAL "BinaryenCopySignFloat64" *> PROCEDURE CopySignFloat64() : Op;
<* EXTERNAL "BinaryenMinFloat64" *> PROCEDURE MinFloat64() : Op;
<* EXTERNAL "BinaryenMaxFloat64" *> PROCEDURE MaxFloat64() : Op;
<* EXTERNAL "BinaryenEqFloat64" *> PROCEDURE EqFloat64() : Op;
<* EXTERNAL "BinaryenNeFloat64" *> PROCEDURE NeFloat64() : Op;
<* EXTERNAL "BinaryenLtFloat64" *> PROCEDURE LtFloat64() : Op;
<* EXTERNAL "BinaryenLeFloat64" *> PROCEDURE LeFloat64() : Op;
<* EXTERNAL "BinaryenGtFloat64" *> PROCEDURE GtFloat64() : Op;
<* EXTERNAL "BinaryenGeFloat64" *> PROCEDURE GeFloat64() : Op;
<* EXTERNAL "BinaryenAtomicRMWAdd" *> PROCEDURE AtomicRMWAdd() : Op;
<* EXTERNAL "BinaryenAtomicRMWSub" *> PROCEDURE AtomicRMWSub() : Op;
<* EXTERNAL "BinaryenAtomicRMWAnd" *> PROCEDURE AtomicRMWAnd() : Op;
<* EXTERNAL "BinaryenAtomicRMWOr" *> PROCEDURE AtomicRMWOr() : Op;
<* EXTERNAL "BinaryenAtomicRMWXor" *> PROCEDURE AtomicRMWXor() : Op;
<* EXTERNAL "BinaryenAtomicRMWXchg" *> PROCEDURE AtomicRMWXchg() : Op;
<* EXTERNAL "BinaryenTruncSatSFloat32ToInt32" *> PROCEDURE TruncSatSFloat32ToInt32() : Op;
<* EXTERNAL "BinaryenTruncSatSFloat32ToInt64" *> PROCEDURE TruncSatSFloat32ToInt64() : Op;
<* EXTERNAL "BinaryenTruncSatUFloat32ToInt32" *> PROCEDURE TruncSatUFloat32ToInt32() : Op;
<* EXTERNAL "BinaryenTruncSatUFloat32ToInt64" *> PROCEDURE TruncSatUFloat32ToInt64() : Op;
<* EXTERNAL "BinaryenTruncSatSFloat64ToInt32" *> PROCEDURE TruncSatSFloat64ToInt32() : Op;
<* EXTERNAL "BinaryenTruncSatSFloat64ToInt64" *> PROCEDURE TruncSatSFloat64ToInt64() : Op;
<* EXTERNAL "BinaryenTruncSatUFloat64ToInt32" *> PROCEDURE TruncSatUFloat64ToInt32() : Op;
<* EXTERNAL "BinaryenTruncSatUFloat64ToInt64" *> PROCEDURE TruncSatUFloat64ToInt64() : Op;
<* EXTERNAL "BinaryenRefAsNonNull" *> PROCEDURE RefAsNonNull() : Op;
<* EXTERNAL "BinaryenRefAsExternInternalize" *> PROCEDURE RefAsExternInternalize() : Op;
<* EXTERNAL "BinaryenRefAsExternExternalize" *> PROCEDURE RefAsExternExternalize() : Op;
<* EXTERNAL "BinaryenRefAsAnyConvertExtern" *> PROCEDURE RefAsAnyConvertExtern() : Op;
<* EXTERNAL "BinaryenRefAsExternConvertAny" *> PROCEDURE RefAsExternConvertAny() : Op;
<* EXTERNAL "BinaryenBrOnNull" *> PROCEDURE BrOnNull() : Op;
<* EXTERNAL "BinaryenBrOnNonNull" *> PROCEDURE BrOnNonNull() : Op;
<* EXTERNAL "BinaryenBrOnCast" *> PROCEDURE BrOnCast() : Op;
<* EXTERNAL "BinaryenBrOnCastFail" *> PROCEDURE BrOnCastFail() : Op;
<* EXTERNAL "BinaryenStringNewLossyUTF8Array" *> PROCEDURE StringNewLossyUTF8Array() : Op;
<* EXTERNAL "BinaryenStringNewWTF16Array" *> PROCEDURE StringNewWTF16Array() : Op;
<* EXTERNAL "BinaryenStringNewFromCodePoint" *> PROCEDURE StringNewFromCodePoint() : Op;
<* EXTERNAL "BinaryenStringMeasureUTF8" *> PROCEDURE StringMeasureUTF8() : Op;
<* EXTERNAL "BinaryenStringMeasureWTF16" *> PROCEDURE StringMeasureWTF16() : Op;
<* EXTERNAL "BinaryenStringEncodeLossyUTF8Array" *> PROCEDURE StringEncodeLossyUTF8Array() : Op;
<* EXTERNAL "BinaryenStringEncodeWTF16Array" *> PROCEDURE StringEncodeWTF16Array() : Op;
<* EXTERNAL "BinaryenStringEqEqual" *> PROCEDURE StringEqEqual() : Op;
<* EXTERNAL "BinaryenStringEqCompare" *> PROCEDURE StringEqCompare() : Op;


(* ============================================================================
 * Expression Creation - Basic Operations
 * ============================================================================ *)

(* Create a block *)
<*EXTERNAL "BinaryenBlock"*> PROCEDURE BinaryenBlock(
    module: ModuleRef;
    label: char_star;
    children: ADDRESS;
    numChildren: Index;
    blockType: Type
): ExpressionRef;

PROCEDURE Block(
    module: ModuleRef;
    label: char_star;
    children: REF ARRAY OF ExpressionRef;
    numChildren: Index;
    blockType: Type
): ExpressionRef;

(* Append an expression to a block *)
<*EXTERNAL "BinaryenBlockAppendChild"*> PROCEDURE BlockAppendChild(
    expr: ExpressionRef;
    child: ExpressionRef
): Index;

(* Insert child into block *)
<*EXTERNAL "BinaryenBlockInsertChildAt"*> PROCEDURE BlockInsertChildAt(
    expr: ExpressionRef;
    index: Index;
    child: ExpressionRef
);

(* Create a loop *)
<*EXTERNAL "BinaryenLoop"*> PROCEDURE Loop(
    module: ModuleRef;
    label: char_star;
    body: ExpressionRef
): ExpressionRef;

(* Create an if statement *)
<*EXTERNAL "BinaryenIf"*> PROCEDURE If(
    module: ModuleRef;
    condition: ExpressionRef;
    ifTrue: ExpressionRef;
    ifFalse: ExpressionRef
): ExpressionRef;

(* Create a Break instruction *)
<*EXTERNAL "BinaryenBreak"*> PROCEDURE Break(
    module: ModuleRef;
    name: char_star;
    condition: ExpressionRef;
    value: ExpressionRef
): ExpressionRef;

(* Create a Switch instruction *)
<*EXTERNAL "BinaryenSwitch"*> PROCEDURE Switch(
    module: ModuleRef;
    names: REF ARRAY OF char_star;
    numNames: Index;
    defaultName: char_star;
    condition: ExpressionRef;
    value: ExpressionRef
): ExpressionRef;

(* Create a return statement *)
<*EXTERNAL "BinaryenReturn"*> PROCEDURE Return(
    module: ModuleRef;
    value: ExpressionRef
): ExpressionRef;

(* Pop *)
<* EXTERNAL "BinaryenPop"*> PROCEDURE Pop(
    module: ModuleRef;
    type: Type
): ExpressionRef;

(* No-op *)
<* EXTERNAL "BinaryenNop"*> PROCEDURE Noop(
    module: ModuleRef
): ExpressionRef;

(* Unreachable *)
<* EXTERNAL "BinaryenUnreachable"*> PROCEDURE Unreachable(
    module: ModuleRef
): ExpressionRef;

(* ============================================================================
 * Expression Creation - Calls
 * ============================================================================ *)

(* Create a direct function call *)
<*EXTERNAL "BinaryenCall"*> PROCEDURE Call(
    module: ModuleRef;
    target: char_star;
    operands: UNTRACED REF ExpressionRef;
    numOperands: Index;
    returnType: Type
): ExpressionRef;

(* Create an indirect function call *)
<*EXTERNAL "BinaryenCallIndirect"*> PROCEDURE CallIndirect(
    module: ModuleRef;
    target: ExpressionRef;
    operands: UNTRACED REF ExpressionRef;
    numOperands: Index;
    params: Type;
    results: Type
): ExpressionRef;


(* Create a direct return function call *)
<*EXTERNAL "BinaryenReturnCall"*> PROCEDURE ReturnCall(
    module: ModuleRef;
    target: char_star;
    operands: UNTRACED REF ExpressionRef;
    numOperands: Index;
    returnType: Type
): ExpressionRef;

(* Create an indirect return function call *)
<*EXTERNAL "BinaryenReturnCallIndirect"*> PROCEDURE ReturnCallIndirect(
    module: ModuleRef;
    table: char_star;
    target: ExpressionRef;
    operands: UNTRACED REF ExpressionRef;
    numOperands: Index;
    params: Type;
    results: Type
): ExpressionRef;


(* ============================================================================
 * Expression Creation - Variables
 * ============================================================================ *)

(* Create a local.get instruction *)
<*EXTERNAL "BinaryenLocalGet"*> PROCEDURE LocalGet(
    module: ModuleRef;
    index: Index;
    type_: Type
): ExpressionRef;

(* Create a local.set instruction *)
<*EXTERNAL "BinaryenLocalSet"*> PROCEDURE LocalSet(
    module: ModuleRef;
    index: Index;
    value: ExpressionRef
): ExpressionRef;

(* Create a local.tee instruction *)
<*EXTERNAL "BinaryenLocalTee"*> PROCEDURE LocalTee(
    module: ModuleRef;
    index: Index;
    value: ExpressionRef;
    type_: Type
): ExpressionRef;

(* Create a global.get instruction *)
<*EXTERNAL "BinaryenGlobalGet"*> PROCEDURE GlobalGet(
    module: ModuleRef;
    name: char_star;
    type_: Type
): ExpressionRef;

(* Create a global.set instruction *)
<*EXTERNAL "BinaryenGlobalSet"*> PROCEDURE GlobalSet(
    module: ModuleRef;
    name: char_star;
    value: ExpressionRef
): ExpressionRef;


(* ============================================================================
 * Expression Creation - References
 * ============================================================================ *)

(* Null *)
<*EXTERNAL "BinaryenRefNull"*> PROCEDURE RefNull(
    module: ModuleRef;
    type: Type
): ExpressionRef;


(* ============================================================================
 * Expression Creation - Memory Operations
 * ============================================================================ *)

(* Create a memory.load instruction *)
<*EXTERNAL "BinaryenLoad"*> PROCEDURE Load(
    module: ModuleRef;
    bytes: unsigned_int;
    signed: int;
    offset: unsigned_int;
    align: unsigned_int;
    type_: Type;
    ptr: ExpressionRef
): ExpressionRef;

(* Create a memory.store instruction *)
<*EXTERNAL "BinaryenStore"*> PROCEDURE Store(
    module: ModuleRef;
    bytes: unsigned_int;
    offset: unsigned_int;
    align: unsigned_int;
    ptr: ExpressionRef;
    value: ExpressionRef;
    type_: Type
): ExpressionRef;

(* Create a memory.size instruction *)
<*EXTERNAL "BinaryenMemorySize"*> PROCEDURE MemorySize(module: ModuleRef): ExpressionRef;

(* Create a memory.grow instruction *)
<*EXTERNAL "BinaryenMemoryGrow"*> PROCEDURE MemoryGrow(
    module: ModuleRef;
    delta: ExpressionRef
): ExpressionRef;

(* ============================================================================
 * Expression Creation - Numeric Operations
 * ============================================================================ *)

(* Create a binary instruction *)
<*EXTERNAL "BinaryenBinary"*> PROCEDURE Binary(
    module: ModuleRef;
    op: int;  (* BinaryOp enum value *)
    left: ExpressionRef;
    right: ExpressionRef
): ExpressionRef;

(* Create a unary instruction *)
<*EXTERNAL "BinaryenUnary"*> PROCEDURE Unary(
    module: ModuleRef;
    op: int;  (* UnaryOp enum value *)
    value: ExpressionRef
): ExpressionRef;

(* Constant Expression *)
<*EXTERNAL "RefConst"*> PROCEDURE Const(
    module: ModuleRef;
    value: REF Literal
): ExpressionRef;

(* Drop Expression *)
<*EXTERNAL "BinaryenDrop"*> PROCEDURE Drop(
    module: ModuleRef;
    value: ExpressionRef
): ExpressionRef;

(* ============================================================================
 * Expression Creation - Comparison and Logic
 * ============================================================================ *)

(* Create a comparison instruction *)
<*EXTERNAL "BinaryenCompare"*> PROCEDURE Compare(
    module: ModuleRef;
    op: int;  (* RelOp enum value *)
    left: ExpressionRef;
    right: ExpressionRef
): ExpressionRef;

(* Create a select (ternary) instruction *)
<*EXTERNAL "BinaryenSelect"*> PROCEDURE Select(
    module: ModuleRef;
    condition: ExpressionRef;
    ifTrue: ExpressionRef;
    ifFalse: ExpressionRef;
    type_: Type
): ExpressionRef;


(* ============================================================================
 * Atomic Expression - Shared Memory Operations
 * ============================================================================ *)

(* Create a atomic.load instruction *)
<*EXTERNAL "BinaryenAtomicLoad"*> PROCEDURE AtomicLoad(
    module: ModuleRef;
    bytes: unsigned_int;
    offset: unsigned_int;
    type_: Type;
    ptr: ExpressionRef
): ExpressionRef;

(* Create a atomic.store instruction *)
<*EXTERNAL "BinaryenAtomicStore"*> PROCEDURE AtomicStore(
    module: ModuleRef;
    bytes: unsigned_int;
    offset: unsigned_int;
    ptr: ExpressionRef;
    value: ExpressionRef;
    type_: Type
): ExpressionRef;

(* Create a atomic read-modiy-write operation *)
<*EXTERNAL "BinaryenAtomicRMW"*> PROCEDURE AtomicRMW(
    module: ModuleRef;
    op: Op;
    bytes: unsigned_int;
    offset: unsigned_int;
    ptr: ExpressionRef;
    value: ExpressionRef;
    type_: Type
): ExpressionRef;

(* Create a atomic compare-exchange instruction *)
<*EXTERNAL "BinaryenAtomicCmpxchg"*> PROCEDURE AtomicCmpxchg(
    module: ModuleRef;
    bytes: unsigned_int;
    offset: unsigned_int;
    ptr: ExpressionRef;
    expected: ExpressionRef;
    replacement: ExpressionRef;
    type_: Type
): ExpressionRef;

(* ============================================================================
 * Atomic Semaphore Operations
 * ============================================================================ *)

(* Create a atomic.wait instruction *)
<*EXTERNAL "BinaryenAtomicWait"*> PROCEDURE AtomicWait(
    module: ModuleRef;
    ptr: ExpressionRef;
    expected: ExpressionRef;
    timeout: ExpressionRef;
    type_: Type
): ExpressionRef;

(* Create a atomic.notify instruction *)
<*EXTERNAL "BinaryenAtomicNotify"*> PROCEDURE AtomicNotify(
    module: ModuleRef;
    ptr: ExpressionRef;
    notifyCount: ExpressionRef
): ExpressionRef;


(* ============================================================================
 * Struct Expression Operations
 * ============================================================================ *)

(* Struct.new *)
<*EXTERNAL "BinaryenStructNew"*> PROCEDURE BinaryenStructNew(
    module: ModuleRef;
    operands: ADDRESS;
    numOperands: Index;
    heapType: HeapTypeRef
): ExpressionRef;

PROCEDURE StructNew(
    module: ModuleRef;
    operands: REF ARRAY OF ExpressionRef;
    numOperands: Index;
    heapType: HeapTypeRef
): ExpressionRef;

(* Struct.get *)
<*EXTERNAL "BinaryenStructGet"*> PROCEDURE StructGet(
    module: ModuleRef;
    index: Index;
    ref: ExpressionRef;
    type: Type;
    signed_ : BOOLEAN
): ExpressionRef;

(* Struct.set *)
<*EXTERNAL "BinaryenStructGet"*> PROCEDURE StructSet(
    module: ModuleRef;
    index: Index;
    ref: ExpressionRef;
    value: ExpressionRef
): ExpressionRef;


(* ============================================================================
 * Array Expression Operations
 * ============================================================================ *)

(* Array.new *)
<*EXTERNAL "BinaryenArrayNew"*> PROCEDURE ArrayNew(
    module: ModuleRef;
    heapType : HeapTypeRef;
    size: ExpressionRef;
    init: ExpressionRef
): ExpressionRef;


(* ============================================================================
 * Exception Handling
 * ============================================================================ *)

(* Create a try instruction *)
<*EXTERNAL "BinaryenTry"*> PROCEDURE Try(
    module: ModuleRef;
    name: char_star;
    body: ExpressionRef;
    catchTags: REF ARRAY OF char_star;
    numCatchTags: Index;
    catchBodies: REF ARRAY OF ExpressionRef;
    numCatchBodies: Index;
    delegateTarget: char_star
): ExpressionRef;

(* Create a throw instruction *)
<*EXTERNAL "BinaryenThrow"*> PROCEDURE Throw(
    module: ModuleRef;
    tag: char_star;
    operands: REF ARRAY OF ExpressionRef;
    numOperands: Index
): ExpressionRef;

(* Create a re-throw instruction *)
<*EXTERNAL "BinaryenRethrow"*> PROCEDURE Rethrow(
    module: ModuleRef;
    target: char_star
): ExpressionRef;


(* ============================================================================
 * Module Optimization and Analysis
 * ============================================================================ *)

(* Enable debug *)
<*EXTERNAL "BinaryenSetDebugInfo"*> PROCEDURE SetDebugInfo(on: BOOLEAN);

(* Set optimisation parameter *)
<*EXTERNAL "BinaryenSetOptimizeLevel"*> PROCEDURE SetOptimiseLevel(level: int);

(* Set shrink parameter *)
<*EXTERNAL "BinaryenSetShrinkLevel"*> PROCEDURE SetShrinkLevel(level: int);

(* Optimize a module *)
<*EXTERNAL "BinaryenModuleOptimize"*> PROCEDURE ModuleOptimise(module: ModuleRef);

(* Run a specific optimization pass *)
<*EXTERNAL "BinaryenModuleRunPasses"*> PROCEDURE ModuleRunPasses(
    module: ModuleRef;
    passes: UNTRACED REF char_star;
    numPasses: Index
);

(* ============================================================================
 * Features
 * ============================================================================ *)

<*EXTERNAL "BinaryenFeatureMVP"*> PROCEDURE FeatureMVP() : Features;
<*EXTERNAL "BinaryenFeatureAtomics"*> PROCEDURE FeatureAtomics() : Features;
<*EXTERNAL "BinaryenFeatureGlobals"*> PROCEDURE FeatureMutableGlobals() : Features;
<*EXTERNAL "BinaryenFeatureNontrappingFPToInt"*> PROCEDURE FeatureNontrappingFPToInt() : Features;
<*EXTERNAL "BinaryenFeatureSIMD128"*> PROCEDURE FeatureSIMD128() : Features;
<*EXTERNAL "BinaryenFeatureBulkMemory"*> PROCEDURE FeatureBulkMemory() : Features;
<*EXTERNAL "BinaryenFeatureSignExt"*> PROCEDURE FeatureSignExt() : Features;
<*EXTERNAL "BinaryenFeatureExceptionHandling"*> PROCEDURE FeatureExceptionHandling() : Features;
<*EXTERNAL "BinaryenFeatureTailCall"*> PROCEDURE FeatureTailCall() : Features;
<*EXTERNAL "BinaryenFeatureReferenceTypes"*> PROCEDURE FeatureReferenceTypes() : Features;
<*EXTERNAL "BinaryenFeatureMultivalue"*> PROCEDURE FeatureMultivalue() : Features;
<*EXTERNAL "BinaryenFeatureGC"*> PROCEDURE FeatureGC() : Features;
<*EXTERNAL "BinaryenFeaturememory64"*> PROCEDURE FeatureMemory64() : Features;
<*EXTERNAL "BinaryenFeatureRelaxedSIMD"*> PROCEDURE FeatureRelaxedSIMD() : Features;
<*EXTERNAL "BinaryenFeatureExtendedConst"*> PROCEDURE FeatureExtendedConst() : Features;
<*EXTERNAL "BinaryenFeatureStrings"*> PROCEDURE FeatureStrings() : Features;
<*EXTERNAL "BinaryenFeatureMultiMemory"*> PROCEDURE FeatureMultiMemory() : Features;
<*EXTERNAL "BinaryenFeatureStackSwitching"*> PROCEDURE FeatureStackSwitching() : Features;
<*EXTERNAL "BinaryenFeatureSharedEverything"*> PROCEDURE FeatureSharedEverything() : Features;
<*EXTERNAL "BinaryenFeatureFP16"*> PROCEDURE FeatureFP16() : Features;
<*EXTERNAL "BinaryenFeatureBulkMemoryOpt"*> PROCEDURE FeatureBulkMemoryOpt() : Features;
<*EXTERNAL "BinaryenFeatureCallInirectOverlong"*> PROCEDURE FeatureCallIndirectOverlong() : Features;
<*EXTERNAL "BinaryenFeatureRelaxedAtomics"*> PROCEDURE FeatureRelaxedAtomics() : Features;
<*EXTERNAL "BinaryenFeatureAll"*> PROCEDURE FeatureAll() : Features;

(* ============================================================================
 * Module Querying and Printing
 * ============================================================================ *)

(* Print a module to stdout *)
<*EXTERNAL "BinaryenModulePrint"*> PROCEDURE ModulePrint(module: ModuleRef);

(* Get the auto-generated name of the start function *)
<*EXTERNAL "BinaryenGetFunctionName"*> PROCEDURE GetFunctionName(
    module: ModuleRef;
    index: Index
): char_star;

(* Get the expression type *)
<*EXTERNAL "BinaryenExpressionGetType"*> PROCEDURE ExpressionGetType(expr: ExpressionRef): Type;

END WASM.
