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
 * Type System Functions
 * ============================================================================ *)

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
