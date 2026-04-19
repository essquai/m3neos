(* Copyright (C) 2026 Sunil Khare. All rights reserved. *)

UNSAFE MODULE M3NG_WASM;

IMPORT WASM;

(* m3core imports *)
IMPORT Ctypes;
IMPORT FileWr;
IMPORT FS;
IMPORT Fmt;
IMPORT IntRefTbl;
IMPORT IO; (* debug this module *)
IMPORT M3toC;
IMPORT RefSeq;
IMPORT Text;
IMPORT TextRefTbl;
IMPORT Wr;

(* m3ir imports *)
IMPORT M3IR_Asm;
IMPORT M3ID;
IMPORT Target;
IMPORT TInt;
IMPORT M3IR;
FROM M3IR IMPORT Name, ByteOffset, TypeUID, CallingConvention;
FROM M3IR IMPORT BitSize, ByteSize, Alignment, Frequency;
FROM M3IR IMPORT Var, Proc, Label, Sign, BitOffset;
FROM M3IR IMPORT Type, ZType, AType, RType, IType, MType;
FROM M3IR IMPORT CompareOp, ConvertOp, AtomicOp, RuntimeError;
FROM M3IR IMPORT MemoryOrder;

(* m3fe imports *)
IMPORT M3Front;
IMPORT BuiltinTypes AS M3FEBuiltin;


REVEAL
  T = Public BRANDED "M3NG_WASM128.T" OBJECT
    moduleRef     : WASM.ModuleRef;
    moduleObj     : WaMod := NIL;  (* compiled module        *)
    tracing       : BOOLEAN := FALSE;

    curVar        : WaVar;
    curProc       : WaProc;   (* Procedure whose body we are in. *)
    curParamOwner : WaProc;   (* Most recent signature introducer, either
                                 declare_procedure or import_procedure. *)
    curLocalOwner : WaProc;   (* Most recent procedure, introduced either
                                 by declare_procedure or begin_procedure. *)

    curStruct     : WaStruct; (* Most recent record/object whose ... *)
    next_field    := 0;       (* ... fields are next to gather ... *)
    next_method   := 0;       (* ... and methods *)
  
    curEnum       : WaOrdinal; (* Most recent enum ... *)
    next_element  := 0;       (* .. and its next element*)
    
    curSig        : WaSig;    (* Most recent proctype whose ... *)
    next_formal   := 0;       (* ... formals are next to gather ... *)
    next_raise    := 0;       (* ... and raises *)  

    procStack     : RefSeq.T := NIL;
    modStack      : RefSeq.T := NIL;    (* imported modules *)
    compStack     : RefSeq.T := NIL;    (* track the trash  *)
    defTable      : IntRefTbl.T := NIL; (* type definitions *)

    prolog        : WaProc := NIL; (* unit start procedure  *)
    next_label_id := 1;
    next_var      := 1;
    next_proc     := 1;
    next_scope    := 1;
    next_mod      := 1;
    
    blockLevel    := 0;
    widecharSize  := 16; (* May change to 32. *)
    memoryOrder   : REF MemoryOrder := NIL;

    (* Generating debug output in the code being compiled. *)
    genDebug      := FALSE;
    curFile       := "";
    curLine       := 0;
    debFile       := "";
    debDir        := "";
    debugTable    : IntRefTbl.T := NIL;
    globalTable   : TextRefTbl.T := NIL;
    debugLexStack : RefSeq.T := NIL;

  METHODS
    Trace(a, b, c, d, e, f: TEXT := NIL; eol := TRUE) := Trace;
    Typedef(t : TypeUID) : WaDefn := Typedef;
    Typename(t : TypeUID; name : Name) := Typename;

  OVERRIDES
    next_label := next_label;
    set_error_handler := set_error_handler;
    begin_unit := begin_unit;
    end_unit := end_unit;
    import_unit := import_unit;
    export_unit := export_unit;
    set_source_file := set_source_file;
    set_source_line := set_source_line;
    declare_typename := declare_typename;
    declare_array := declare_array;
    declare_open_array := declare_open_array;
    declare_enum := declare_enum;
    declare_enum_elt := declare_enum_elt;
    declare_packed := declare_packed;
    declare_record := declare_record;
    declare_field := declare_field;
    declare_set := declare_set;
    declare_subrange := declare_subrange;
    declare_pointer := declare_pointer;
    declare_indirect := declare_indirect;
    declare_proctype := declare_proctype;
    declare_formal := declare_formal;
    declare_raises := declare_raises;
    declare_object := declare_object;
    declare_method := declare_method;
    declare_opaque := declare_opaque;
    reveal_opaque := reveal_opaque;
    set_runtime_proc := set_runtime_proc;
    import_global := import_global;
    declare_segment := declare_segment;
    bind_segment := bind_segment;
    declare_global := declare_global;
    declare_constant := declare_constant;
    declare_local := declare_local;
    declare_param := declare_param;
    declare_temp := declare_temp;
    free_temp := free_temp;
    declare_exception := declare_exception;
    widechar_size := widechar_size; 
    begin_init := begin_init;
    end_init := end_init;
    init_int := init_int;
    init_proc := init_proc;
    init_label := init_label;
    init_var := init_var;
    init_offset := init_offset;
    init_chars := init_chars;
    init_float := init_float;
    import_procedure := import_procedure;
    declare_procedure := declare_procedure;
    begin_procedure := begin_procedure;
    end_procedure := end_procedure;
    begin_block := begin_block;
    end_block := end_block;
    note_procedure_origin := note_procedure_origin;
    set_label := set_label;
    jump := jump;
    if_true := if_true;
    if_false := if_false;
    if_compare := if_compare;
    case_jump := case_jump;
    exit_proc := exit_proc;
    load := load;
    store := store;
    load_address := load_address;
    load_indirect := load_indirect;
    store_indirect := store_indirect;
    load_nil := load_nil;
    load_integer := load_integer;
    load_float := load_float;
    compare := compare;
    add := add;
    subtract := subtract;
    multiply := multiply;
    divide := divide;
    div := div;
    mod := mod;
    negate := negate;
    abs := abs;
    max := max;
    min := min;
    cvt_int := cvt_int;
    cvt_float := cvt_float;
    set_union := set_union;
    set_difference := set_difference;
    set_intersection := set_intersection;
    set_sym_difference := set_sym_difference;
    set_member := set_member;
    set_compare := set_compare;
    set_range := set_range;
    set_singleton := set_singleton;
    not := not;
    and := and;
    or := or;
    xor := xor;
    shift := shift;
    shift_left := shift_left;
    shift_right := shift_right;
    rotate := rotate;
    rotate_left := rotate_left;
    rotate_right := rotate_right;
    widen := widen;
    chop := chop;
    extract := extract;
    extract_n := extract_n;
    extract_mn := extract_mn;
    insert := insert;
    insert_n := insert_n;
    insert_mn := insert_mn;
    swap := swap;
    pop := pop;
    copy := copy;
    copy_n := copy_n;
    zero := zero;
    zero_n := zero_n;
    loophole := loophole;
    abort := abort;
    check_nil := check_nil;
    check_lo := check_lo;
    check_hi := check_hi;
    check_range := check_range;
    check_index := check_index;
    check_eq := check_eq;
    add_offset := add_offset;
    index_address := index_address;
    start_call_direct := start_call_direct;
    call_direct := call_direct;
    start_call_indirect := start_call_indirect;
    call_indirect := call_indirect;
    start_try := start_try;
    end_try := end_try;
    invoke_direct := invoke_direct;
    invoke_indirect := invoke_indirect;
    landing_pad := landing_pad;
    pop_param := pop_param;
    pop_struct := pop_struct;
    pop_static_link := pop_static_link;
    load_procedure := load_procedure;
    load_static_link := load_static_link;
    comment := comment;
    store_ordered := store_ordered;
    load_ordered := load_ordered;
    exchange := exchange;
    compare_exchange := compare_exchange;
    fence := fence;
    fetch_and_op := fetch_and_op;
    module_write := module_write;
END;

CONST NOTYPE : INTEGER = 0;

VAR
  WTYPE_none: WASM.Type;
  WTYPE_i32: WASM.Type;
  WTYPE_i64: WASM.Type;
  WTYPE_f32: WASM.Type;
  WTYPE_f64: WASM.Type;
  WTYPE_v128: WASM.Type;
  WTYPE_funcref: WASM.Type;
  WTYPE_externref: WASM.Type;
  WTYPE_anyref: WASM.Type;
  WTYPE_eqref: WASM.Type;
  WTYPE_i31ref: WASM.Type;
  WTYPE_structref: WASM.Type;
  WTYPE_arrayref: WASM.Type;
  WTYPE_stringref: WASM.Type;
  WTYPE_nullref: WASM.Type;
  WTYPE_nullexternref: WASM.Type;
  WTYPE_nullfuncref: WASM.Type;
  WTYPE_unreachable: WASM.Type;
  WTYPE_auto: WASM.Type;

  WPACK_not: WASM.Packed;
  WPACK_int8: WASM.Packed;
  WPACK_int16: WASM.Packed;

  WDEF_Min8   : INTEGER;
  WDEF_Max8   : INTEGER;
  WDEF_Max8U  : INTEGER;
  WDEF_Min16  : INTEGER;
  WDEF_Max16  : INTEGER;
  WDEF_Max16U : INTEGER;
  WDEF_Min32  : INTEGER;
  WDEF_Max32  : INTEGER;
  WDEF_Max32U : INTEGER;
  WDEF_Min64  : INTEGER;
  WDEF_Max64  : INTEGER;
  WDEF_Max64U : INTEGER;

(*--------------------------------------------------------- Parse Objects ---*)
TYPE
  Predeclared = M3FEBuiltin.Kind;

  VarType = {Local,Global,Param,Temp};

  WaVar = Var OBJECT
    tag: INTEGER;
    name : Name;
    size : ByteSize;
    type : Type;
    align : Alignment;
    ofs : INTEGER; (* offset from frame pointer - for stack walker *)
    varType : VarType;
    m3t : TypeUID;
    frequency : Frequency;
    inProc : WaProc;  (* owning procedure *)
    waIndex : WASM.Index;  (* wasm Local/Param number *)
    waType : WASM.Type;
    waGlobal : WASM.GlobalRef; (* pointer to the global *)
    waParam : WASM.Index;
      (* ^For a SSA parameter, the function parameter variable.  Needed? *)
    locDisplayIndex : INTEGER := -1;
    (* ^Index within the display provided by containing proc.  Nonnegative
       only if labelled by front end as up_level. *)
    inits : RefSeq.T;
    isConst : BOOLEAN; (* As of 2017-07-23, set but not used. *)
    in_memory : BOOLEAN;
    up_level : BOOLEAN; (* Maintained but not used. *)
    exported : BOOLEAN;
    inited : BOOLEAN := FALSE;
  METHODS
    set_index(proc : WaProc; idx : WASM.Index) := set_index;
  END;

  procState = {uninit, decld, built, begun, complete};
  (* ^Used to assert some assumptions about the order things occur in CG IR. *)

  WaProc = Proc OBJECT
    tag: INTEGER;
    name : Name;
    state : procState := procState.uninit;
    returnType : Type;
    retUid : TypeUID := 0;
    numParams : CARDINAL;
    localOfs : INTEGER := 0;
    lev : INTEGER;
    cc : CallingConvention;
    exported : BOOLEAN := FALSE;
    i3 : BOOLEAN := FALSE; (* is this a module interface declaration? *)
    procParms : WASM.Type;
    (* ^The combination of procedure parameters gets its own type in WASM.
       This holds for declared and imported prcoedures; the SetParms
       method is invoked to set it *)
    funcRef : WASM.FunctionRef;  (* wasm procedure definition *)
    procTy : WASM.Type;
    parent : WaProc := NIL;
    nextLocal : WASM.Index := 0; (* next declare_local waIndex  *)
    entryBB : WASM.ExpressionRef;
    (* ^For stored static link, params, vars, temps, display construction. *)
    secondBB : WASM.ExpressionRef;
    (* ^For other M3-coded stuff.  There are two separate basic blocks
       here, because we need to be able to intersperse adding things at the
       ends of each.  This seems easier than shuffling insertion points in
       one BB.  secondBB is the unconditional successor of entryBB. *)
    (* NOTE: It is hard to tell from the header files, but apparently, there
             is only one insertion point globally, not one per BB. *)
    saveBB : WASM.ExpressionRef; (* for nested procs save the bb *)
    localStack  : RefSeq.T := NIL;
    paramStack  : RefSeq.T := NIL;
    uplevelRefdStack  : RefSeq.T := NIL;
      (* ^List of params and locals that are uplevel-referenced. *)
    cumUplevelRefdCt : CARDINAL := 0;
      (* ^Between the declare_procedure and begin_procedure, the number of
          params and locals declared so far that are uplevel-referenced.
          After begin_procedure, also includes those of all static ancestor
          procs as well. *)
    staticLinkFormal : WaVar := NIL; (* i8* *)
      (* ^For most procedures, CG emits neither a static link formal nor an
          actual for it in a call.  We provide these, for a nested procedure.
          For an internally-generated FINALLY procedure, CG emits an explicit
          formal for a static link, which we just use, but CG does not emit an
          actual parameter for in it a call, so we provide that too.  CG does,
          however, explicitly pass a SL value to the runtime, when pushing a
          FINALLY frame, and this SL will be passed by the runtime when it calls
          the FINALLY procedure.
          This really would be more consistend as i8**, but CG makes assignments
          between this and things CG types as Addr, that are not easily
          identifiable as static link values. So we have to type static links
          as i8*
      *)
    storedStaticLink : WaVar := NIL; (* i8** *)
      (* ^A memory copy of staticLinkFormal, always stored as 1st alloca of
          a nested procedure, so the debugger can find it. *)
    imported : BOOLEAN := FALSE; (* if this is an import *)
    runtime  : BOOLEAN := FALSE; (* if this is a runtime proc *)
    returnsTwice : BOOLEAN := FALSE; (* if this returns twice ie _setjmp *)
    noReturn : BOOLEAN := FALSE; (* if this never returns ie abort *)
    defined : BOOLEAN := FALSE; (* set when we build the declaration for real *)
    (* displayLty : LLVM.TypeRef := NIL; *) (* i8** *)
      (* ^llvm type for a display, an array of addresses to all up-level-
         referenced variables in this proc and its static ancestors.  If it
         calls a procedure nested one deeper than itself and that wants a
         display, this proc will create it in a local of this type (only once)
         and pass its address as an added static link parameter to the callee. *)
    (* outgoingDisplayLv : LLVM.ValueRef := NIL; *) (* i8** *)
    (* ^Address of the display this proc will pass to one-level deeper nested
        procs.  We store the display itself in the AR, but this pointer to it
        is an llvm SSA variable that we don't explicitly store. *)
    needsDisplay : BOOLEAN := FALSE;
    funcScope : BlockDebug; (* scope for debugging *)
  END;

 WaDefn = OBJECT
    (* ^ Base level definition of a type *)
    typeid : TypeUID;
    name : Name := M3ID.NoID;
    size : BitSize := 0;
    offset : BitOffset := 0;
    type : WASM.Type := NOTYPE;
    pack : WASM.Packed := NOTYPE;
    numFields : INTEGER := 0;
    integral : BOOLEAN := TRUE;
  METHODS
    init(size : BitSize := 0; offset : BitOffset := 0; wtype : WASM.Type := NOTYPE; numFields : INTEGER := 0; pack : WASM.Packed := NOTYPE) : WaDefn := Typeinit;
  END;

  WaOrdinal = WaDefn OBJECT
    (* ^enumerations, subranges, ints *)
    first  : INTEGER  := 0;
    last   : INTEGER  := 0;
    number : CARDINAL := 0;
    elements : REF ARRAY OF WaDefn := NIL; (* enum names *)
  END;

  WaFloat = WaDefn OBJECT
    (* ^floating point *)
    ext : BOOLEAN := FALSE; (* extended precision *)
  END;

  WaRef = WaDefn OBJECT
    (* ^References PLUS mutexes *)
    any      : TypeUID := NOTYPE;
    indirect := FALSE;
  END;

  WaComp = WaDefn OBJECT
    (* ^ Composite structures with reference types *)
    bldGrp : INTEGER;                     (* used by builder    *)
    wType  : WASM.Type        := NOTYPE;  (* for ref recursion  *)
    heap   : WASM.HeapTypeRef := NIL;     (* created by builder *)
  END;

  WaArray = WaComp OBJECT
    (* common properties *)
    element  : WaDefn  := NIL;
    ofComp   : WaComp  := NIL; (* array of composite element *)

    (* array is fixed iff # NIL *)
    fixed : WaOrdinal := NIL;

    (* array is open iff > 0 *)
    open  : CARDINAL   := 0
  END;

  WaField = WaDefn OBJECT
    (* ^Multi-purpose: struct/object fields, object methods, procedure parameters
        As a convenience, parameter referent is NARROWed here *)
    ord  : WaOrdinal := NIL;
    flt  : WaFloat   := NIL;
    ref  : WaRef     := NIL;
    arr  : WaArray   := NIL; (* and comp *)
    str  : WaStruct  := NIL; (* and comp *)
    sig  : WaSig     := NIL; (* and comp *)
    opq  : WaOpaque  := NIL;
    comp : WaComp    := NIL; (*  field is also a composite *)
  END;

  WaStruct = WaComp OBJECT
    (* ^In Modula-3, Objects are accessed by reference. In Wasm, records are 
       accessed by reference since values don't fit on the stack. For
       compiling, records are objects minus methods and supertype.
       Let's call them Struct.
       Both records and objects are subject to WASM Garbage Collection,
       which makes them struct references declared with a type  *)
    fields:  REF ARRAY OF WaField := NIL;
    numMethods : INTEGER := 0;
    methods: REF ARRAY OF WaField := NIL;

    super: WaStruct := NIL;
  END;

  WaOpaque = WaDefn OBJECT
    (* ^supertype relationship *)
    super : TypeUID := NOTYPE;
    def   : WaDefn  := NIL; (* supertype may not be defined yet, either? *)
  END;

  WaSig = WaComp OBJECT
    (* ^ A procedure signature - definition for methods and proctype variables *)
    cc        : CallingConvention;
    result    : TypeUID;

    fields    : REF ARRAY OF WaField := NIL;
    numRaises : INTEGER;
    raises    : REF ARRAY OF Name := NIL;
  END;

  WaMod = OBJECT
    tag: INTEGER;
    name : Name;
    funcStack : RefSeq.T := NIL;
    (* ^imported functions *)
  END;

(*-------------------------------------------------------- CG Procedures  ---*)


<*NOWARN*>PROCEDURE next_label(self: T; n: INTEGER := 1): Label = BEGIN RETURN 0; END next_label;
<*NOWARN*>PROCEDURE import_global(self: T; name: Name; byte_size: ByteSize; alignment: Alignment; type: Type; typeid: TypeUID; typename: Name): Var = BEGIN RETURN NIL; END import_global;
<*NOWARN*>PROCEDURE declare_segment(self: T; name: Name; typeid: TypeUID; is_const: BOOLEAN): Var = BEGIN RETURN NIL; END declare_segment;
<*NOWARN*>PROCEDURE declare_global(self: T; name: Name; byte_size: ByteSize; alignment: Alignment; type: Type; typeid: TypeUID; exported, inited: BOOLEAN; typename: Name): Var = BEGIN RETURN NIL; END declare_global;
<*NOWARN*>PROCEDURE declare_constant(self: T; name: Name; byte_size: ByteSize; alignment: Alignment; type: Type; typeid: TypeUID; exported, inited: BOOLEAN; typename: Name): Var = BEGIN RETURN NIL; END declare_constant;

PROCEDURE declare_local
  (self: T;  n: Name;  s: ByteSize;  a: Alignment; t: Type;  m3t: TypeUID;
    in_memory, up_level: BOOLEAN; f: Frequency; <*UNUSED*>typeName : Name): Var =
  VAR
    v : WaVar := NewVar
          (self,n,s,a,t,isConst:=FALSE,m3t:=m3t,in_memory:=in_memory,
           up_level:=up_level,exported:=FALSE,inited:=FALSE,frequency:=f,
           varType:=VarType.Local);
    proc : WaProc;
  BEGIN
    (* Locals are declared either within a procedure signature, i.e., after
       declare_procedure, or within a body, i.e., within a begin_procedure/
       end_procedure pair.  In the former case, we can't allocate them yet,
       so just save them in localStack, to be allocated in begin_procedure.
       In the latter case,  allocate them now.
       Since begin_procedure implies a begin_block, checking for blockLevel > 0
       is sufficient to allocate now. *)
    proc := self.curLocalOwner;
    (* Local indices increment after parameters *)
    v.set_index(proc, proc.nextLocal + proc.numParams);
    INC(proc.nextLocal);

    IF self.blockLevel = 0 THEN (* We are in a signature. *)
      (* NOTE: If n is "_result", we are in the signature of a function procedure
             with a scalar result, and this is a compiler-generated local to
             hold the result. *)
        (* ^The proc belonging to the most recent declare_procedure. *)
      IF Text.Equal(M3ID.ToText(n),"_result") THEN
        proc.retUid := m3t; (* save for debugging *)
      END;

      PushRev(proc.localStack, v); (* Left-to-right. *)
      (* ^The local will be allocated later, in the proc body. *)
      IF up_level THEN
        v.locDisplayIndex := proc.uplevelRefdStack.size();
        PushRev(proc.uplevelRefdStack, v);
        INC(proc.cumUplevelRefdCt);
      END;

      self.Trace("declare_local signature ", M3ID.ToText(n));
      self.Trace("\ttype=",Fmt.Int(ORD(t))," index=",Fmt.Int(v.waIndex)," wtype=", Fmt.Int(v.waType));
    ELSE (* We are in the body of the procedure. *)
      <* ASSERT proc = self.curProc *>
      (* self.allocVarInEntryBlock(v); *)
        (* ^Which flattens it from an inner block into the locals of
            the containing proc. *)
      (* Could be up-level if M3 decl is in an inner block. *)
      IF up_level THEN
        v.locDisplayIndex := self.curProc.uplevelRefdStack.size();
        PushRev(self.curProc.uplevelRefdStack, v);
        INC(proc.cumUplevelRefdCt);
      END;
      (* Need a debugvar for locals in blocks eg for loop indexes *)
      DebugVar(self, v);

      self.Trace("declare_local body ", M3ID.ToText(n));
      self.Trace("\ttype=" & Fmt.Int(ORD(t))," index=",Fmt.Int(v.waIndex)," wtype=",Fmt.Int(v.waType));
    END;
    RETURN v;
  END declare_local;

PROCEDURE declare_param (self: T;  n: Name;  s: ByteSize;  a: Alignment; t: Type;  m3t: TypeUID;  in_memory, up_level: BOOLEAN; f: Frequency; <*UNUSED*>typeName : Name): Var =
  (* A formal parameter of a procedure, not of a procedure type, (which
     is given by declare_formal). *)
  VAR
    v : WaVar;
    proc : WaProc;
    def : WaDefn;
  BEGIN
    (* This appears after either import_procedure (which can occur inside
       the body of a different procedure, i.e., between begin_procedure and
       end_procedure), or after declare_procedure.  Either way, the WaProc
       this parameter belongs to is self.curParamOwner. *)

    (* NOTE: If n is "_result", we are in the signature of a function procedure
             with a nonscalar result, and this is a compiler-generated VAR
             parameter used to return the result. *)
    proc := self.curParamOwner; (* Get the current proc. *)

    v := NewVar
           (self,n,s,a,t,isConst:=FALSE,m3t:=m3t,in_memory:=in_memory,
            up_level:=up_level,exported:=FALSE,inited:=FALSE,frequency:=f,
            varType:=VarType.Param);

    v.set_index(proc, proc.paramStack.size());
    (* ^Param indices increment from zero *)

    PushRev(proc.paramStack, v); (* Left-to-right. *)
    (* ^Postpone allocating and storing the formal until begin_procedure. *)
    IF up_level THEN
      v.locDisplayIndex := proc.uplevelRefdStack.size();
      PushRev(proc.uplevelRefdStack, v); (* Left-to-right. *)
      INC(proc.cumUplevelRefdCt);
    END;

    IF n # M3ID.NoID THEN
      self.Trace("declare_param ", M3ID.ToText(n), eol := FALSE);
    ELSE
      self.Trace("declare_param NoID", eol := FALSE);
    END;

    def := Typedef(self, m3t);
    TYPECASE def OF
    WaOrdinal        => 
    | WaFloat        => 
    | WaRef (ref)    => 
                        IF (ref.indirect) THEN
                          self.Trace(" indirect", eol := FALSE);
                        END;
    | WaArray        => 
    | WaStruct       => 
    | WaSig          => 
    | WaOpaque       =>
    ELSE
    <* ASSERT FALSE *>
    END;

    self.Trace(" type=",Target.TypeNames[t]," index=", Fmt.Int(v.waIndex), " wtype=", Fmt.Int(v.waType));
    RETURN v;
  END declare_param;


<*NOWARN*>PROCEDURE declare_temp(self: T; byte_size: ByteSize; alignment: Alignment; type: Type; in_memory: BOOLEAN; typename: Name): Var = BEGIN RETURN NIL; END declare_temp;

PROCEDURE import_procedure (self: T;  n: Name;  n_params: INTEGER;
                            return_type: Type;  cc: CallingConvention;
                            <*UNUSED*>returnTypeid : TypeUID;
                            <*UNUSED*>returnTypename : Name): Proc =
  VAR
    p : WaProc := NewProc(self,n,n_params,return_type,-1,cc,FALSE,NIL);
    name : TEXT;
    pfx  : TEXT;
    mod  : WaMod;
  BEGIN
    self.Trace("import_procedure ", M3ID.ToText(n));

    (* Invoked in three instances: <module>_I3 and <module>__<proc>
           AND for "alloca" ... ?
       The first one represents the "interface" procedure, ignore it
       The second occurs after an import_unit, and needs parameters
       The third one is an artifact of the C backend ? *)
    p.imported := TRUE;
    (* Don't need local stack or an up-level since its imported, but need a
       paramstack. *)
    p.paramStack := NEW(RefSeq.T).init();

    (* add proc to any imported unit *)
    name := M3ID.ToText(p.name);
    pfx  := ModPrefix(self, name, p.i3);
    IF name # pfx AND NOT p.i3 THEN
      (* Second instance - the module *should* exist *)
      mod := ModFind(self, pfx);
      <* ASSERT mod # NIL *>
      Push(mod.funcStack, p);
    END;

    p.procTy := WasmType(return_type);
    p.state := procState.decld;
    self.curParamOwner := p;
    (* ^Until further notice, occurences of declare_param belong to p. *)
(* REVIEW: Hopefully, a declare_local can't occur belonging to import_procedure.
   Otherwise, declare_local's ownership is ambiguous, since an
   import_procedure, with its signature items, can occur inside a procedure
   body, with its locals.  This is undocumented and hard to ferret out from CG.
   Sometimes, there are declare_local's interspersed with declar_param's in a
   signature, for certain, after declare_procedure.  Could this happen after an
   import_procedure?  When inside a body, it would be ambiguous which the parameter
   belonged to. *)

    RETURN p;
  END import_procedure;

PROCEDURE declare_procedure (self: T;  n: Name;  n_params: INTEGER;
                             return_type: Type;  lev: INTEGER;
                             cc: CallingConvention;
                             exported: BOOLEAN;  parent: Proc;
                             <*UNUSED*>returnTypeid : TypeUID;
                             <*UNUSED*>returnTypename : M3ID.T): Proc =
  VAR
    p : WaProc := NewProc(self,n,n_params,return_type,lev,cc,exported,parent);
    procName := M3ID.ToText(n);
  BEGIN
    p.imported := FALSE;
    p.localStack := NEW(RefSeq.T).init();
    p.paramStack := NEW(RefSeq.T).init();
    p.uplevelRefdStack := NEW(RefSeq.T).init();
    p.cumUplevelRefdCt := 0; (* This is not cumlative yet. *)
    p.state := procState.decld;
    p.procTy := WasmType(return_type);
    self.curParamOwner := p;
    self.curLocalOwner := p;
    (* ^Until further notice, both occurences of declare_param and of
        declare_local belong to this procedure. *)
    IF self.prolog = NIL THEN
      self.prolog := p;
      (* ^entry point for the interface/module *)
    END;
    self.Trace("declare_procedure ", procName);
    RETURN p;
  END declare_procedure;


<*NOWARN*>PROCEDURE set_error_handler(self: T; p: M3IR_Asm.ErrorHandler) = BEGIN END set_error_handler;
<*NOWARN*>PROCEDURE begin_unit(self: T; optimize: INTEGER) = BEGIN END begin_unit;
<*NOWARN*>PROCEDURE end_unit(self: T) = BEGIN END end_unit;

PROCEDURE import_unit (self: T;  n: Name) =
  VAR m := NewMod(self, n);
  BEGIN
    Push(self.modStack, m);
    self.Trace("import_unit ", M3ID.ToText(n));
  END import_unit;

PROCEDURE export_unit(self: T; name: Name) =
  VAR m := NewMod(self, name); n := M3ID.ToText(name);
  BEGIN
    <*ASSERT self.moduleObj = NIL *>
    self.moduleObj := m;
    self.Trace("export_unit ", n);
  END export_unit;

PROCEDURE set_source_file(self: T; file: TEXT) = 
  BEGIN
    self.Trace("set_source_file ", file);
    self.curFile := file;
  END set_source_file;

PROCEDURE set_source_line(self: T; line: INTEGER) =
  BEGIN
    self.Trace("set_source_line ", Fmt.Int(line));
    self.curLine := line;
  END set_source_line;

PROCEDURE declare_typename(self: T; typeid: TypeUID; name: Name) =
  BEGIN
    self.Trace("declare_typename ", M3IR.FormatUID(typeid), " name=", M3ID.ToText(name));
    IF Typedef(self, typeid) # NIL THEN
      Typename(self, typeid, name);
    END;
  END declare_typename;

PROCEDURE declare_array(self: T; typeid, index_typeid, element_typeid: TypeUID; bit_size: BitSize; <*UNUSED*>element_typename: Name) =
  VAR
    arr := NEW(WaArray, typeid := typeid, type := WTYPE_arrayref, size := bit_size);
    elt : WaDefn;
    ofC : WaComp := NIL;
    idx : WaDefn;
    fix : WaOrdinal;
  BEGIN
    elt := Typedef(self, element_typeid);
    idx := Typedef(self, index_typeid);
    fix := NARROW(idx, WaOrdinal);
    IF ISTYPE(elt, WaComp) THEN
      ofC := NARROW(elt, WaComp);
    END;
    <* ASSERT elt # NIL AND fix # NIL *>

    self.Trace("declare_array type=", M3IR.FormatUID(typeid), " idx=", Typelabel(fix), " elt=", Typelabel(elt), eol := FALSE);
    self.Trace(" numFields=", Fmt.Int(fix.number), " ofArray=", Fmt.Bool(ofC # NIL));

    (* Set the properties of the fixed array *)
    arr.element   := elt;
    arr.ofComp    := ofC;
    arr.fixed     := fix;
    arr.numFields := fix.number;
    Typeadd(self, arr);
    Compadd(self, arr);
  END declare_array;

PROCEDURE declare_open_array(self: T; typeid, element_typeid: TypeUID; bit_size: BitSize; <*UNUSED*>element_typename: Name) =
  VAR
    arr := NEW(WaArray, typeid := typeid, type := WTYPE_arrayref, size := bit_size);
    elt : WaDefn;
    dim : INTEGER;
    ofC : WaComp := NIL;
  BEGIN
    elt := Typedef(self, element_typeid);
    dim := (bit_size - 64) DIV 64;
    IF ISTYPE(elt, WaComp) THEN
      ofC := NARROW(elt, WaComp);
    END;
    <* ASSERT elt # NIL AND dim > 0 *>
    self.Trace("declare_open_array type=", M3IR.FormatUID(typeid), " elt=", Typelabel(elt), eol := FALSE);
    self.Trace(" open=", Fmt.Int(dim), " ofComp=", Fmt.Bool(ofC # NIL));

    (* Set the properties of the open array *)
    arr.element   := elt;
    arr.ofComp   := ofC;
    arr.open      := dim;
    Typeadd(self, arr);
    Compadd(self, arr);
  END declare_open_array;

PROCEDURE declare_enum(self: T; typeid: TypeUID; n_elts: INTEGER; bit_size: BitSize) =
  VAR enum := NEW(WaOrdinal, typeid := typeid, size := bit_size, type := WTYPE_i32, pack := WPACK_not, number := n_elts);
  BEGIN
    self.Trace("declare_enum ", M3IR.FormatUID(typeid), " n_elts=", Fmt.Int(n_elts), " size=", Fmt.Int(bit_size));

    IF n_elts > 0 THEN
      self.curEnum      := enum;
      self.next_element := 0;
      enum.elements     := NEW(REF ARRAY OF WaDefn, n_elts);
      enum.numFields    := n_elts;
      enum.last         := n_elts - 1;
      IF enum.size = 8 THEN  enum.pack := WPACK_int8;
                       ELSIF enum.size = 16 THEN enum.pack := WPACK_int16; END;
    ELSE
      (* empty *)
      Typeadd(self, enum);
    END;
  END declare_enum;

PROCEDURE declare_enum_elt(self: T; name: Name) =
  VAR enum := self.curEnum;
  BEGIN
    self.Trace("declare_enum_elt ", M3ID.ToText(name));
    <* ASSERT enum # NIL AND self.next_element < enum.numFields *>

    enum.elements[self.next_element] := NEW(WaDefn, typeid := enum.typeid, name := name, pack := enum.pack);
    INC(self.next_element);
    IF self.next_element >= enum.numFields THEN
      (* enumeration complete *)
      Typeadd(self, enum);
      self.curEnum := NIL;
    END;
  END declare_enum_elt;


<*NOWARN*>PROCEDURE declare_packed(self: T; typeid: TypeUID; bit_size: BitSize; base: TypeUID; base_typename: Name) = BEGIN END declare_packed;

PROCEDURE declare_record(self: T; typeid: TypeUID; bit_size: BitSize; n_fields: INTEGER) = 
  VAR s := NewStruct (self:=self, typeid := typeid, bit_size := bit_size, numFields := n_fields, numMethods := 0);
  BEGIN
    self.Trace("declare_record ", M3IR.FormatUID(typeid), " n_fields=", Fmt.Int(n_fields));
    IF typeid = M3IR.NO_UID THEN RETURN END;
    self.curStruct   := s;
    self.next_field  := 0;
    self.next_method := 0;
    IF self.next_field >= s.numFields
       AND self.next_method >= s.numMethods THEN
      (* structure complete *)
      Compadd(self, s);
      self.curStruct := NIL;
    END;
  END declare_record;

PROCEDURE declare_field(self: T; name: Name; bit_offset: BitOffset; bit_size: BitSize; typeid: TypeUID; <*UNUSED*> typename: Name) =
  VAR
    fld :  WaField;
    def := Typedef(self, typeid);
    str := self.curStruct;
  BEGIN
    IF str = NIL THEN
      self.Trace("  declare_field - ignore");
      RETURN;
    END;
    fld := NewField(def, typeid := typeid, name := name, type := def.type, size := bit_size, offset := bit_offset, pack := def.pack);
    <* ASSERT str # NIL *>
    <* ASSERT self.next_field < str.numFields *>
    <* ASSERT def # NIL *>
    self.Trace("  declare_field ", M3ID.ToText(name), " num=", Fmt.Int(self.next_field), " type=", Typelabel(def));

    (* duplicate these from the referenced field type definition to param *)
    str.fields[self.next_field] := fld;

    INC(self.next_field);
    IF self.next_field >= str.numFields
       AND self.next_method >= str.numMethods THEN
      (* structure complete *)
      Compadd(self, str);
      self.curStruct := NIL;
    END;
  END declare_field;

<*NOWARN*>PROCEDURE declare_set(self: T; t, domain: TypeUID; bit_size: BitSize; domain_typename: Name) = BEGIN END declare_set;

PROCEDURE declare_subrange(self: T; typeid, domain_typeid: TypeUID; READONLY min, max: Target.Int; bit_size: BitSize; <*UNUSED*> domain_typename: Name) =
  VAR range := NEW(WaOrdinal, typeid := typeid, size := bit_size); converted : BOOLEAN;
  BEGIN
    converted := TInt.ToInt(min, range.first);
    <* ASSERT converted *>
    converted := TInt.ToInt(max, range.last);
    <* ASSERT converted *>
    range.number := range.last + 1 - range.first;
    CASE range.size OF 
    |  8 => range.pack := WPACK_int8;
            range.type := WTYPE_i32;
    | 16 => range.pack := WPACK_int16;
            range.type := WTYPE_i32;
    | 32 => range.pack := WPACK_not;
            range.type := WTYPE_i32;
    | 64 => range.pack := WPACK_not;
            range.type := WTYPE_i64;
    ELSE
      <* ASSERT FALSE *>
    END;
    self.Trace("declare_subrange ", M3IR.FormatUID(typeid), " number=", Fmt.Int(range.number), eol := FALSE);
    self.Trace(" first=", Fmt.Int(range.first), " last=", Fmt.Int(range.last), " bits=", Fmt.Int(range.size), eol :=FALSE);
    self.Trace(" domain=", M3IR.FormatUID(domain_typeid));
    Typeadd(self, range);
  END declare_subrange;

PROCEDURE declare_pointer(self: T; typeid, target_typeid: TypeUID; <*UNUSED*> brand: TEXT; <*UNUSED*>traced: BOOLEAN; <*UNUSED*>target_typename: Name) =
  VAR
    ref := NEW(WaRef, typeid := typeid, type := WTYPE_anyref, size := 64, integral := FALSE, any := target_typeid);
    def := Typedef(self, target_typeid);
  BEGIN
    <* ASSERT def # NIL *>
    self.Trace("declare_pointer from=", M3IR.FormatUID(typeid), " to=", M3IR.FormatUID(target_typeid), " type=", Typelabel(def));
    Typeadd(self, ref);
  END declare_pointer;


PROCEDURE declare_indirect(self: T; typeid, target_typeid: TypeUID; <*UNUSED*>target_typename: Name) =
  VAR
    ref := NEW(WaRef, typeid := typeid, type := WTYPE_anyref, size := 64, integral := FALSE, indirect := TRUE, any := target_typeid);
    def := Typedef(self, target_typeid);
  BEGIN
    <* ASSERT def # NIL *>
    self.Trace("declare_indirect from=", M3IR.FormatUID(typeid), " to=", M3IR.FormatUID(target_typeid), " type=", Typelabel(def));
    Typeadd(self, ref);
  END declare_indirect;

PROCEDURE declare_proctype(self: T; typeid: TypeUID; n_formals: INTEGER; result: TypeUID; n_raises: INTEGER; callingConvention: CallingConvention; <*UNUSED*> result_typename: Name) =
  VAR sig := NewSig(self, typeid := typeid, n_formals := n_formals, result := result, n_raises := n_raises, cc := callingConvention);
  BEGIN
    self.Trace("declare_proctype ", M3IR.FormatUID(typeid), " n_formals=", Fmt.Int(n_formals), " n_raises=", Fmt.Int(n_raises));
    self.curSig       := sig;
    self.next_formal  := 0;
    self.next_raise   := 0;
    IF self.next_formal >= sig.numFields
       AND self.next_raise >= sig.numRaises THEN
      (* proctype complete *)
      Compadd(self, sig);
      self.curSig := NIL;
    END;
  END declare_proctype;

PROCEDURE declare_formal(self: T; name: Name; typeid: TypeUID; <*UNUSED*> typename: Name) =
  VAR
    sig := self.curSig;
    fld :  WaField;
    def := Typedef(self, typeid);
    direct := TRUE;
  BEGIN
    fld := NewField(def, typeid := typeid, name := name, type := def.type, pack := def.pack);
    fld.integral := def.integral;
    IF fld.ref # NIL THEN direct := NOT fld.ref.indirect; END;

    self.Trace("declare_formal typeid=", M3IR.FormatUID(typeid), " name=", M3ID.ToText(name), " num=", Fmt.Int(self.next_formal), eol := FALSE);
    self.Trace(" indirect=", Fmt.Bool(NOT direct));

    sig.fields[self.next_formal] := fld;
    INC(self.next_formal);

    IF self.next_formal >= sig.numFields
       AND self.next_raise >= sig.numRaises THEN
      (* proctype complete *)
      Compadd(self, sig);
      self.curSig := NIL;
    END;
  END declare_formal;

PROCEDURE declare_raises(self: T; name: Name) =
  VAR sig := self.curSig;
  BEGIN
    self.Trace("declare_raises num=", Fmt.Int(self.next_raise), " name=", M3ID.ToText(name));
    sig.raises[self.next_raise] := name;
    INC(self.next_raise);
    IF self.next_formal >= sig.numFields
       AND self.next_raise >= sig.numRaises THEN
      (* proctype complete *)
      Compadd(self, sig);
      self.curSig := NIL;
    END;
  END declare_raises;

PROCEDURE declare_object(self: T; typeid : TypeUID; super_typeid: TypeUID; <*UNUSED*>brand: TEXT; <*UNUSED*>traced: BOOLEAN; n_fields, n_methods: INTEGER; field_size: BitSize; <*UNUSED*>super_typename: Name) =
  VAR
    s := NewStruct (self:=self, typeid := typeid, bit_size := field_size, numFields := n_fields, numMethods := n_methods);
    def := Typedef(self, super_typeid);
  BEGIN
    self.Trace("declare_object ", Fmt.Int(typeid));
    self.curStruct   := s;
    self.next_field  := 0;
    self.next_method := 0;
    IF def # NIL THEN
      s.super := NARROW(def, WaStruct);
    END;
    IF self.next_field >= s.numFields
       AND self.next_method >= s.numMethods THEN
      (* structure complete *)
      Compadd(self, s);
      self.curStruct := NIL;
    END;
  END declare_object;

PROCEDURE declare_method(self: T; name: Name; signature: TypeUID) =
  VAR
    fld :   WaField;
    str := self.curStruct;
    def := Typedef(self, signature);
  BEGIN
    fld := NewField(def, typeid := signature, type := WTYPE_funcref, name := name, pack := def.pack);
    <* ASSERT str # NIL *>
    <* ASSERT self.next_method < str.numMethods *>
    self.Trace("declare_method ", M3ID.ToText(name), " num=", Fmt.Int(self.next_method), " signature=", M3IR.FormatUID(signature));
    fld.integral := def.integral;
    <* ASSERT fld.sig # NIL *>

    str.methods[self.next_method] := fld;
    INC(self.next_method);

    IF self.next_field >= str.numFields
       AND self.next_method >= str.numMethods THEN
      (* structure complete *)
      Compadd(self, str);
      self.curStruct := NIL;
    END;
  END declare_method;

PROCEDURE declare_opaque(self: T; typeid, super_typeid: TypeUID) =
  VAR
    opq := NEW(WaOpaque, typeid := typeid, super := super_typeid, integral := FALSE);
    def := Typedef(self, super_typeid);
  BEGIN
    opq.def := def;
    self.Trace("declare_opaque ", M3IR.FormatUID(typeid), " <: ", M3IR.FormatUID(super_typeid), "def=", Fmt.Bool(def # NIL));
    Typeadd(self, opq);
  END declare_opaque;

<*NOWARN*>PROCEDURE reveal_opaque(self: T; lhs_typeid, rhs_typeid: TypeUID) = BEGIN END reveal_opaque;
<*NOWARN*>PROCEDURE declare_exception(self: T; name: Name; arg_typeid: TypeUID; raise_proc: BOOLEAN; base: Var; offset: INTEGER) = BEGIN END declare_exception;
<*NOWARN*>PROCEDURE widechar_size(self: T; optimize: INTEGER) = BEGIN END widechar_size;
<*NOWARN*>PROCEDURE set_runtime_proc(self: T; name: Name; proc: Proc) = BEGIN END set_runtime_proc;
<*NOWARN*>PROCEDURE bind_segment(self: T; segment: Var; byte_size: ByteSize; alignment: Alignment; type: Type; exported, inited: BOOLEAN) = BEGIN END bind_segment;
<*NOWARN*>PROCEDURE free_temp(self: T; var: Var) = BEGIN END free_temp;
<*NOWARN*>PROCEDURE begin_init(self: T; var: Var) = BEGIN END begin_init;
<*NOWARN*>PROCEDURE end_init(self: T; var: Var) = BEGIN END end_init;
<*NOWARN*>PROCEDURE init_int(self: T; byte_offset: ByteOffset; READONLY value: Target.Int; type: Type) = BEGIN END init_int;
<*NOWARN*>PROCEDURE init_proc(self: T; byte_offset: ByteOffset; value: Proc) = BEGIN END init_proc;
<*NOWARN*>PROCEDURE init_label(self: T; byte_offset: ByteOffset; value: Label) = BEGIN END init_label;
<*NOWARN*>PROCEDURE init_var(self: T; byte_offset: ByteOffset; value: Var; bias: ByteOffset) = BEGIN END init_var;
<*NOWARN*>PROCEDURE init_offset(self: T; byte_offset: ByteOffset; value: Var) = BEGIN END init_offset;
<*NOWARN*>PROCEDURE init_chars(self: T; byte_offset: ByteOffset; value: TEXT) = BEGIN END init_chars;
<*NOWARN*>PROCEDURE init_float(self: T; byte_offset: ByteOffset; READONLY f: Target.Float) = BEGIN END init_float;


PROCEDURE begin_procedure (self: T;  p: Proc) =
(* begin generating code for the body of procedure 'p'.  Sets "current procedure"
   to 'p'.  Implies a begin_block.  *)
  VAR
    local : WaVar;
    proc : WaProc;
    numArgs,numLocals : CARDINAL;
    arg : REFANY;
    localTypes : REF ARRAY OF WASM.Type;
    blkLiteral : REF WASM.Literal := NIL;
    children : REF ARRAY OF WASM.ExpressionRef := NIL;
    numChildren : WASM.Index := 0;
    procName : Ctypes.char_star;
  BEGIN
    (* Declare this procedure and all its locals and parameters.*)
    proc := NARROW(p,WaProc);
    self.Trace("begin_procedure ", M3ID.ToText(proc.name));


    (* create the function *)
    proc.state := procState.built;
    <* ASSERT proc.state = procState.built *>
    self.curProc := proc;

    (* Make proc.cumUplevelRefdCt cumulative. *)
    IF proc.parent # NIL THEN
      <* ASSERT proc.parent.state = procState.complete *>
      INC (proc.cumUplevelRefdCt, proc.parent.cumUplevelRefdCt);
    END;


    proc.saveBB := WASM.Block(self.moduleRef, Cstar("save"), NIL, 0, WTYPE_auto);
    (* begin blocks can be nested so need to keep a stack of procedures so we
       are referring to the current proc for the BB's *)
    Push(self.procStack,proc);
    (* top of procStack is current proc *)


    (* generate debug code for the function *)
    DebugFunc(self,p);
    (* set debug loc to nul here to run over prologue instructions *)
    DebugClearLoc(self);

    (* Create the entry and second basic blocks. *)
    IF proc.procTy = WTYPE_i32 OR proc.procTy = WTYPE_i64 THEN
        blkLiteral := NEW(REF WASM.Literal);
        IF proc.procTy = WTYPE_i32 THEN
          blkLiteral^ := WASM.LiteralInt32(32);
        ELSE
          blkLiteral^ := WASM.LiteralInt64(64);
        END;
        children := NEW(REF ARRAY OF WASM.ExpressionRef, 1);
        numChildren := 1;
        children[0] := WASM.Const(self.moduleRef, blkLiteral);
    END;
    proc.entryBB := WASM.Block(self.moduleRef, Cstar("entry"), children, numChildren, proc.procTy);
    (* ^For stuff we generate: alloca's, display build, etc. *)

    proc.secondBB := WASM.Block(self.moduleRef, Cstar("second"), NIL, 0, WTYPE_auto);
    (* ^For m3-coded operations. *)

    (* Build the procedure's argument list *)
    SetParms(self, proc);

    (* Build the procedure's local variable list *)
    numLocals := proc.localStack.size();
    self.Trace("\tnumLocals=", Fmt.Int(numLocals));
    IF numLocals > 0 THEN
      localTypes := NEW(REF ARRAY OF WASM.Type, numLocals);
      FOR i := 0 TO numLocals - 1 DO
        arg := Get(proc.localStack,i);
        local := NARROW(arg,WaVar);
        self.Trace("\tlocals=" & Fmt.Int(i), " Index=", Fmt.Int(local.waIndex), " type=", Fmt.Int(ORD(local.type)) & " waType=" & Fmt.Int(local.waType) & " name=" & M3ID.ToText(local.name));
        localTypes[i] := local.waType;
      END;
    ELSE
      localTypes := NIL;
    END;

    (* Add function to the module *)
    procName := Cstar(M3ID.ToText(proc.name));
    proc.funcRef := WASM.AddFunction(self.moduleRef, procName, proc.procParms, proc.procTy,
                                     localTypes, numLocals, proc.entryBB);
    <* ASSERT self.moduleObj # NIL *>
    IF self.blockLevel = 0 THEN
      (* top-level procedures added to export list *)
      Push(self.moduleObj.funcStack, p);
      EVAL WASM.AddFunctionExport(self.moduleRef, procName, procName);
    END;
    self.Trace("AddFunction ", M3ID.ToText(proc.name), " type=" & Fmt.Int(proc.procParms));

    self.curLocalOwner := p;
    (* ^Until further notice, occurences of declare_local belong to p. *)

    self.begin_block();

    DebugLine(self); (* resume debugging *)

    (* debug for locals and params here, need the stacks intact *)
    DebugLocalsParams(self,proc);

    proc.state := procState.begun;

    self.Trace("\tnumArgs=", Fmt.Int(numArgs), " numLocals=", Fmt.Int(numLocals));
  END begin_procedure;


PROCEDURE end_procedure (self: T;  p: Proc) =
(* marks the end of the code for procedure 'p'.  Sets "current procedure"
   to NIL.  Implies an end_block.  *)
  VAR
    proc : WaProc;
  BEGIN
    proc := NARROW(p,WaProc);
    <* ASSERT proc = self.curProc *>
    <* ASSERT proc.state = procState.begun *>


    self.curProc.state := procState.complete;
    Pop(self.procStack);
    IF self.procStack.size() > 0 THEN
      self.curProc := Get(self.procStack);
    ELSE
      self.curProc := NIL;
    END;

    self.end_block();
    self.Trace("end_procedure ", M3ID.ToText(proc.name), " level=", Fmt.Int(self.blockLevel));
  END end_procedure;

PROCEDURE begin_block (self: T) =
  BEGIN
    INC(self.blockLevel);
    DebugPushBlock(self);
  END begin_block;

PROCEDURE end_block (self: T) =
  BEGIN
    DEC(self.blockLevel);
    DebugPopBlock(self);
  END end_block;

<*NOWARN*>PROCEDURE note_procedure_origin(self: T; proc: Proc) = BEGIN END note_procedure_origin;
<*NOWARN*>PROCEDURE set_label(self: T; label: Label; barrier: BOOLEAN) = BEGIN END set_label;
<*NOWARN*>PROCEDURE jump(self: T; label: Label) = BEGIN END jump;
<*NOWARN*>PROCEDURE if_true(self: T; type: IType; label: Label; frequency: Frequency) = BEGIN END if_true;
<*NOWARN*>PROCEDURE if_false(self: T; type: IType; label: Label; frequency: Frequency) = BEGIN END if_false;
<*NOWARN*>PROCEDURE if_compare(self: T; type: ZType; op: CompareOp; label: Label; frequency: Frequency) = BEGIN END if_compare;
<*NOWARN*>PROCEDURE case_jump(self: T; type: IType; READONLY labels: ARRAY OF Label) = BEGIN END case_jump;
<*NOWARN*>PROCEDURE exit_proc(self: T; type: Type) = BEGIN END exit_proc;
<*NOWARN*>PROCEDURE load(self: T; var: Var; byte_offset: ByteOffset; mtype: MType; ztype: ZType) = BEGIN END load;
<*NOWARN*>PROCEDURE store(self: T; var: Var; byte_offset: ByteOffset; ztype: ZType; mtype: MType) = BEGIN END store;
<*NOWARN*>PROCEDURE load_address(self: T; var: Var; byte_offset: ByteOffset) = BEGIN END load_address;
<*NOWARN*>PROCEDURE load_indirect(self: T; byte_offset: ByteOffset; mtype: MType; ztype: ZType) = BEGIN END load_indirect;
<*NOWARN*>PROCEDURE store_indirect(self: T; byte_offset: ByteOffset; ztype: ZType; mtype: MType) = BEGIN END store_indirect;
<*NOWARN*>PROCEDURE load_nil(self: T) = BEGIN END load_nil;
<*NOWARN*>PROCEDURE load_integer(self: T; type: IType; READONLY int: Target.Int) = BEGIN END load_integer;
<*NOWARN*>PROCEDURE load_float(self: T; type: RType; READONLY float: Target.Float) = BEGIN END load_float;
<*NOWARN*>PROCEDURE compare(self: T; ztype: ZType; itype: IType; op: CompareOp) = BEGIN END compare;
<*NOWARN*>PROCEDURE add(self: T; type: AType) = BEGIN END add;
<*NOWARN*>PROCEDURE subtract(self: T; type: AType) = BEGIN END subtract;
<*NOWARN*>PROCEDURE multiply(self: T; type: AType) = BEGIN END multiply;
<*NOWARN*>PROCEDURE divide(self: T; type: RType) = BEGIN END divide;
<*NOWARN*>PROCEDURE div(self: T; type: IType; a, b: Sign) = BEGIN END div;
<*NOWARN*>PROCEDURE mod(self: T; type: IType; a, b: Sign) = BEGIN END mod;
<*NOWARN*>PROCEDURE negate(self: T; type: AType) = BEGIN END negate;
<*NOWARN*>PROCEDURE abs(self: T; type: AType) = BEGIN END abs;
<*NOWARN*>PROCEDURE max(self: T; type: ZType) = BEGIN END max;
<*NOWARN*>PROCEDURE min(self: T; type: ZType) = BEGIN END min;
<*NOWARN*>PROCEDURE cvt_int(self: T; rtype: RType; itype: IType; op: ConvertOp) = BEGIN END cvt_int;
<*NOWARN*>PROCEDURE cvt_float(self: T; atype: AType; rtype: RType) = BEGIN END cvt_float;
<*NOWARN*>PROCEDURE set_union(self: T; byte_size: ByteSize) = BEGIN END set_union;
<*NOWARN*>PROCEDURE set_difference(self: T; byte_size: ByteSize) = BEGIN END set_difference;
<*NOWARN*>PROCEDURE set_intersection(self: T; byte_size: ByteSize) = BEGIN END set_intersection;
<*NOWARN*>PROCEDURE set_sym_difference(self: T; byte_size: ByteSize) = BEGIN END set_sym_difference;
<*NOWARN*>PROCEDURE set_member(self: T; byte_size: ByteSize; type: IType) = BEGIN END set_member;
<*NOWARN*>PROCEDURE set_compare(self: T; byte_size: ByteSize; op: CompareOp; type: IType) = BEGIN END set_compare;
<*NOWARN*>PROCEDURE set_range(self: T; byte_size: ByteSize; type: IType) = BEGIN END set_range;
<*NOWARN*>PROCEDURE set_singleton(self: T; byte_size: ByteSize; type: IType) = BEGIN END set_singleton;
<*NOWARN*>PROCEDURE not(self: T; type: IType) = BEGIN END not;
<*NOWARN*>PROCEDURE and(self: T; type: IType) = BEGIN END and;
<*NOWARN*>PROCEDURE or(self: T; type: IType) = BEGIN END or;
<*NOWARN*>PROCEDURE xor(self: T; type: IType) = BEGIN END xor;
<*NOWARN*>PROCEDURE shift(self: T; type: IType) = BEGIN END shift;
<*NOWARN*>PROCEDURE shift_left(self: T; type: IType) = BEGIN END shift_left;
<*NOWARN*>PROCEDURE shift_right(self: T; type: IType) = BEGIN END shift_right;
<*NOWARN*>PROCEDURE rotate(self: T; type: IType) = BEGIN END rotate;
<*NOWARN*>PROCEDURE rotate_left(self: T; type: IType) = BEGIN END rotate_left;
<*NOWARN*>PROCEDURE rotate_right(self: T; type: IType) = BEGIN END rotate_right;
<*NOWARN*>PROCEDURE widen(self: T; sign: BOOLEAN) = BEGIN END widen;
<*NOWARN*>PROCEDURE chop(self: T) = BEGIN END chop;
<*NOWARN*>PROCEDURE extract(self: T; type: IType; sign: BOOLEAN) = BEGIN END extract;
<*NOWARN*>PROCEDURE extract_n(self: T; type: IType; sign: BOOLEAN; n: CARDINAL) = BEGIN END extract_n;
<*NOWARN*>PROCEDURE extract_mn(self: T; type: IType; sign: BOOLEAN; m, n: CARDINAL) = BEGIN END extract_mn;
<*NOWARN*>PROCEDURE insert(self: T; type: IType) = BEGIN END insert;
<*NOWARN*>PROCEDURE insert_n(self: T; type: IType; n: CARDINAL) = BEGIN END insert_n;
<*NOWARN*>PROCEDURE insert_mn(self: T; type: IType; m, n: CARDINAL) = BEGIN END insert_mn;
<*NOWARN*>PROCEDURE swap(self: T; a, b: Type) = BEGIN END swap;
<*NOWARN*>PROCEDURE pop(self: T; type: Type) = BEGIN END pop;
<*NOWARN*>PROCEDURE copy_n(self: T; itype: IType; mtype: MType; overlap: BOOLEAN) = BEGIN END copy_n;
<*NOWARN*>PROCEDURE copy(self: T; n: INTEGER; mtype: MType; overlap: BOOLEAN) = BEGIN END copy;
<*NOWARN*>PROCEDURE zero_n(self: T; itype: IType; mtype: MType) = BEGIN END zero_n;
<*NOWARN*>PROCEDURE zero(self: T; n: INTEGER; type: MType) = BEGIN END zero;
<*NOWARN*>PROCEDURE loophole(self: T; from, to: ZType) = BEGIN END loophole;
<*NOWARN*>PROCEDURE abort(self: T; code: RuntimeError) = BEGIN END abort;
<*NOWARN*>PROCEDURE check_nil(self: T; code: RuntimeError) = BEGIN END check_nil;
<*NOWARN*>PROCEDURE check_lo(self: T; type: IType; READONLY i: Target.Int; code: RuntimeError) = BEGIN END check_lo;
<*NOWARN*>PROCEDURE check_hi(self: T; type: IType; READONLY i: Target.Int; code: RuntimeError) = BEGIN END check_hi;
<*NOWARN*>PROCEDURE check_range(self: T; type: IType; READONLY a, b: Target.Int; code: RuntimeError) = BEGIN END check_range;
<*NOWARN*>PROCEDURE check_index(self: T; type: IType; code: RuntimeError) = BEGIN END check_index;
<*NOWARN*>PROCEDURE check_eq(self: T; type: IType; code: RuntimeError) = BEGIN END check_eq;
<*NOWARN*>PROCEDURE add_offset(self: T; i: INTEGER) = BEGIN END add_offset;
<*NOWARN*>PROCEDURE index_address(self: T; type: IType; size: INTEGER) = BEGIN END index_address;
<*NOWARN*>PROCEDURE start_call_direct(self: T; proc: Proc; level: INTEGER; type: Type) = BEGIN END start_call_direct;
<*NOWARN*>PROCEDURE start_call_indirect(self: T; type: Type; callingConvention: CallingConvention) = BEGIN END start_call_indirect;
<*NOWARN*>PROCEDURE pop_param(self: T; type: MType) = BEGIN END pop_param;
<*NOWARN*>PROCEDURE pop_struct(self: T; typeid: TypeUID; byte_size: ByteSize; alignment: Alignment) = BEGIN END pop_struct;
<*NOWARN*>PROCEDURE pop_static_link(self: T) = BEGIN END pop_static_link;
<*NOWARN*>PROCEDURE call_direct(self: T; proc: Proc; type: Type) = BEGIN END call_direct;
<*NOWARN*>PROCEDURE call_indirect(self: T; type: Type; callingConvention: CallingConvention) = BEGIN END call_indirect;
<*NOWARN*>PROCEDURE start_try(self: T) = BEGIN END start_try;
<*NOWARN*>PROCEDURE end_try(self: T) = BEGIN END end_try;
<*NOWARN*>PROCEDURE invoke_direct(self: T; proc: Proc; type: Type; next,handler : Label) = BEGIN END invoke_direct;
<*NOWARN*>PROCEDURE invoke_indirect(self: T; type: Type; callingConvention: CallingConvention; next,handler : Label) = BEGIN END invoke_indirect;
<*NOWARN*>PROCEDURE landing_pad(self: T; type: ZType; handler: Label; READONLY catches : ARRAY OF TypeUID) = BEGIN END landing_pad;
<*NOWARN*>PROCEDURE load_procedure(self: T; proc: Proc) = BEGIN END load_procedure;
<*NOWARN*>PROCEDURE load_static_link(self: T; proc: Proc) = BEGIN END load_static_link;
<*NOWARN*>PROCEDURE comment(self: T; a, b, c, d: TEXT := NIL) = BEGIN END comment;
<*NOWARN*>PROCEDURE store_ordered(self: T; ztype: ZType; mtype: MType; order: MemoryOrder) = BEGIN END store_ordered;
<*NOWARN*>PROCEDURE load_ordered(self: T; mtype: MType; ztype: ZType; order: MemoryOrder) = BEGIN END load_ordered;
<*NOWARN*>PROCEDURE exchange(self: T; mtype: MType; ztype: ZType; order: MemoryOrder) = BEGIN END exchange;
<*NOWARN*>PROCEDURE compare_exchange(self: T; mtype: MType; ztype: ZType; r: IType; success, failure: MemoryOrder) = BEGIN END compare_exchange;
<*NOWARN*>PROCEDURE fence(self: T; order: MemoryOrder) = BEGIN END fence;
<*NOWARN*>PROCEDURE fetch_and_op(self: T; op: AtomicOp; mtype: MType; ztype: ZType; order: MemoryOrder) = BEGIN END fetch_and_op;


(*----------------------------------------------------- Module Procedures ---*)

PROCEDURE module_write(t: T; binFileName, textFileName: TEXT) : INTEGER =
  VAR
    wat    : TEXT;
    len    : CARDINAL;
    srcMap : TEXT;
    output : UNTRACED REF ARRAY OF CHAR;
    file   : FileWr.T;
    status : INTEGER := 0;
    wrtn   : INTEGER := 0;
  BEGIN
    t.Trace("module_write");

    ModImports(t);
    ModCompos(t);
    IF WASM.ModuleValidate(t.moduleRef) = 1 THEN
      t.Trace("Module validation successful.")
    ELSE
      IO.Put("Module validation failed." & Wr.EOL)
    END;

    IF NOT t.genDebug THEN
      t.Trace("ModuleOptimise");
      WASM.ModuleOptimise(t.moduleRef);
    END;
    IF t.tracing THEN WASM.ModulePrint(t.moduleRef); END;

    IF textFileName # NIL AND NOT Text.Equal(textFileName, "") THEN
      wat := WASM.ModuleWAT(t.moduleRef);
      TRY
        file := FileWr.Open(textFileName);
        Wr.PutText(file, wat);
        Wr.Close(file);
      EXCEPT
      ELSE
        IO.Put("Failed to write WAT\n");
        status := 1
      END;
    END;

    IF binFileName # NIL AND NOT Text.Equal(binFileName, "") THEN
      len := WASM.ModuleObject(t.moduleRef, output, srcMap);
      wrtn := LOOPHOLE(output, INTEGER);
      t.Trace("ModWrite bin: len=", Fmt.Int(len), " output=", Fmt.Unsigned(wrtn));
      status := WASM.RefSave(Cstar(binFileName), output, len);
    END;
    RETURN status;
  END module_write;

PROCEDURE New(WasmDebug : BOOLEAN; GenDebug: BOOLEAN) : T =
  VAR
    t     := NEW(T, tracing := WasmDebug, genDebug := GenDebug);
    def   : WaDefn;
    ord   : WaOrdinal;
    flt   : WaFloat;
    ref   : WaRef;
    str   : WaStruct;
    first : INTEGER;
  BEGIN
    WASM.ModuleSetWorld(TRUE);
    t.moduleRef := WASM.ModuleCreate();
    WASM.ModuleSetFeatures(t.moduleRef, WASM.FeatureAll());
    IF t.genDebug THEN
      WASM.SetDebugInfo(TRUE);
      WASM.SetOptimiseLevel(0);
      WASM.SetShrinkLevel(0);
    ELSE
      WASM.SetOptimiseLevel(3);
      WASM.SetShrinkLevel(1);
    END;
    t.procStack     := NEW(RefSeq.T).init();
    t.modStack      := NEW(RefSeq.T).init();
    t.debugLexStack := NEW(RefSeq.T).init();
    t.compStack     := NEW(RefSeq.T).init();
    t.defTable      := NEW(IntRefTbl.Default).init(sizeHint := 20);

    (* Construct the pre-declared types from the front end *)
    FOR k := FIRST(M3FEBuiltin.Kind) TO LAST (M3FEBuiltin.Kind) DO
      (* the below are attributes of WASM types, not native compiler *)
      first := 0;
      CASE k OF 
      | Predeclared.Err =>
                def := NEW(WaDefn);
      | Predeclared.LInt, Predeclared.LCard =>
                IF k = Predeclared.LInt THEN first := WDEF_Min64; END;
                ord := NEW(WaOrdinal, type := WTYPE_i64, size := 64, first := first, last := WDEF_Max64, number := WDEF_Max64U);
                def := ord;
      | Predeclared.Int, Predeclared.Card =>
                IF k = Predeclared.Int THEN first := WDEF_Min32; END;
                ord := NEW(WaOrdinal, type := WTYPE_i32, size := 32, first := first, last := WDEF_Max32, number := WDEF_Max32U+1);
                def := ord;
      | Predeclared.Bool =>
                ord := NEW(WaOrdinal, type := WTYPE_i32, size := 8, first :=0, last := 1, number := 2, pack := WPACK_int8);
                def := ord;
      | Predeclared.Reel, Predeclared.LReel, Predeclared.EReel =>
                IF k = Predeclared.Reel THEN
                  flt := NEW(WaFloat, type := WTYPE_f32, size := 32);
                ELSE
                  flt := NEW(WaFloat, type := WTYPE_f64, size := 64, ext := TRUE);
                END;
                def := flt;
      | Predeclared.Charr =>
                ord := NEW(WaOrdinal, type := WTYPE_i32, size := 8, first := 0, last := WDEF_Max8U, number := WDEF_Max8U+1, pack := WPACK_int8);
                def := ord;
      | Predeclared.WCharr =>
                ord := NEW(WaOrdinal, type := WTYPE_i32, size := 16, first := 0, last := WDEF_Max16U, number := WDEF_Max16U+1, pack := WPACK_int16);
                def := ord;
      | Predeclared.Addr, Predeclared.Reff =>
                ref := NEW(WaRef, type := WTYPE_anyref, size := 64, integral := FALSE);
                def := ref;
      | Predeclared.ObjectAdr, Predeclared.ObjectRef =>
                str := NewStruct(t, typeid := M3FEBuiltin.KindUID[k], bit_size := 0, numFields := 0, numMethods := 0);
                def := str;
      | Predeclared.Mutex =>
                ref := NEW(WaRef, type := WTYPE_i31ref, size := 32, any := M3FEBuiltin.KindUID[Predeclared.Int]);
                def := ref;
      | Predeclared.Textt =>
                ref := NEW(WaRef, type := WTYPE_stringref, size := 64, integral := FALSE);
                def := ref;
      | Predeclared.Null =>
                ref := NEW(WaRef, type := WTYPE_nullref, size := 64, integral := FALSE);
                def := ref;
      END;
      def.typeid := M3FEBuiltin.KindUID[k];
      Typeadd(t, def);
      Typename(t, def.typeid, M3ID.Add(M3FEBuiltin.KindNames[k]))
    END;
    RETURN t;
  END New;

PROCEDURE ModPrefix(self : T; n : TEXT; VAR i3 : BOOLEAN) : TEXT =
  VAR usi := ModUnderscores(n); pfx := n; len := Text.Length(n);
  BEGIN
    self.Trace("  ModPrefix ", n, eol := FALSE);
    i3 := FALSE;
    IF usi > 0 THEN
      pfx := Text.Sub(n, 0, usi);
    ELSIF len > 3 AND Text.Equal(Text.Sub(n, len-3), "_I3") THEN
      pfx := Text.Sub(n, 0, len-3);
      i3 := TRUE;
    END;
    self.Trace(" prefix=", pfx, " usi=", Fmt.Int(usi));
    RETURN pfx;
  END ModPrefix;

PROCEDURE ModUnderscores(n : TEXT) : INTEGER =
  VAR
    idx : CARDINAL;
    len := Text.Length(n);
    rep := FALSE;
    usi : INTEGER := -1;
  BEGIN
      WHILE usi < 0 AND idx < len DO
        IF Text.GetChar(n, idx) = '_' THEN
          IF rep THEN
            usi := idx-1;
          END;
          rep := TRUE;
        ELSE
          rep := FALSE;
        END;
        INC(idx);
      END;
    RETURN usi;
  END ModUnderscores;

PROCEDURE NewMod(self: T; name : Name): WaMod =
  VAR
    m := NEW(WaMod, tag := self.next_mod, name := name);
  BEGIN
    INC (self.next_mod);
    m.funcStack := NEW(RefSeq.T).init();
    RETURN m;
  END NewMod;

PROCEDURE ModFind(self : T; name : TEXT) : WaMod = 
  VAR
    m : WaMod := NIL;
    i : CARDINAL;
    a : REFANY;
    n := M3ID.Add(name);
    numMods := self.modStack.size();
  BEGIN
    self.Trace("  ModFind ", name, eol := FALSE);
    IF self.moduleObj.name = n THEN
      m := self.moduleObj;
      self.Trace(" moduleObj", eol := FALSE);
    END;
    WHILE m = NIL AND i < numMods DO
      a := Get(self.modStack, i);
      m := NARROW(a,WaMod);
      IF m.name # n THEN
        m := NIL;
      END;
      INC(i);
    END;
    IF m # NIL THEN
      self.Trace(" found");
    ELSE
      self.Trace(" not found");
    END;
    RETURN m;
  END ModFind;

PROCEDURE ModImports(self : T) =
  VAR
    m : WaMod;
    numModules := self.modStack.size();
    modName : TEXT;
    procName : TEXT;
    modStr : Ctypes.char_star;
    procStr : Ctypes.char_star;
    a : REFANY;
    numFuncs : CARDINAL;
    proc : WaProc;
  BEGIN
    FOR i := 0 TO numModules-1 DO
      a := Get(self.modStack, i);
      m := NARROW(a,WaMod);
      modName := M3ID.ToText(m.name);
      modStr  := Cstar(modName);
      self.Trace("ModImports ", modName);
      numFuncs := m.funcStack.size();
      FOR f := 0 TO numFuncs-1 DO
        a := Get(m.funcStack, f);
        proc := NARROW(a,WaProc);
        procName := M3ID.ToText(proc.name);
        procStr := Cstar(procName);
        self.Trace("    proc=", procName);

        (* Build the procedure's argument list *)
        SetParms(self, proc);

        (* Add imported function to the module *)
        WASM.AddFunctionImport(self.moduleRef,procStr,modStr,procStr,
                                     proc.procParms,proc.procTy);
        self.Trace("    type= ", Fmt.Int(proc.procParms));
      END;
    END;
  END ModImports;

TYPE BldGroup = RECORD
  numComps : INTEGER;
  Comp     : REF ARRAY OF WaComp;
  heapType : REF ARRAY OF WASM.HeapTypeRef;
END;

PROCEDURE ModCompos(self : T) =
  VAR
    numComps := self.compStack.size();
    Comp    : REF ARRAY OF WaComp;
    Grouped : REF ARRAY OF BOOLEAN;
    numElem : INTEGER;
    fldMax  : INTEGER := 0;
    fldType : REF ARRAY OF WASM.Type;
    fldPack : REF ARRAY OF WASM.Packed;
    fldMut  : REF ARRAY OF CHAR;
    groups  : INTEGER;
    bldGroup: REF ARRAY OF REF BldGroup;
    all     : BldGroup;

    PROCEDURE countGroups(Comp : REF ARRAY OF WaComp; Grouped : REF ARRAY OF BOOLEAN; numComps : INTEGER) : INTEGER =
      VAR
        old_groups : INTEGER := 0;
        groups     : INTEGER := numComps;
      BEGIN
        WHILE groups # old_groups DO
          old_groups := groups;
          groups     := 0;
          FOR i := 0 TO numComps-1 DO
            Grouped[i] := FALSE;
          END;
          FOR i := 0 TO numComps -1 DO
            TYPECASE Comp[i] OF
            | WaArray (arr)  => 
                IF arr.ofComp # NIL THEN
                  (* same group as the composite's one *)
                  arr.bldGrp := Comp[arr.ofComp.bldGrp].bldGrp;
                  IF NOT Grouped[arr.bldGrp] THEN
                    Grouped[arr.bldGrp] := TRUE;
                    INC(groups);
                  END;
                ELSE
                   Grouped[i] := TRUE;
                   INC(groups);
                END;
            | WaStruct (str) => 
                Grouped[i] := TRUE;
                INC(groups);
            | WaSig (sig)    => 
                Grouped[i] := TRUE;
                INC(groups);
            ELSE
              <* ASSERT FALSE *>
            END;
          END;
        END;
        RETURN groups;
      END countGroups;

    PROCEDURE makeGroup(Comp : REF ARRAY OF WaComp; Grouped : REF ARRAY OF BOOLEAN; numComps : INTEGER) : REF BldGroup =
      VAR
        bldGroup := NEW(REF BldGroup, numComps := 0, Comp := NIL, heapType := NIL);
        g   : INTEGER := -1;
        idx : INTEGER := 0;
      BEGIN
        (* Find a build group *)
        FOR i := 0 TO numComps-1 DO
          IF g < 0 THEN
            (* Find the first member of a group *)
            IF NOT Grouped[i] THEN
              Grouped[i] := TRUE;
              g := Comp[i].bldGrp;
              bldGroup.numComps := 1;
            END;
          ELSIF Comp[i].bldGrp = g THEN
            (* This comp is in the build group, mark it *)
            Grouped[i] := TRUE;
            INC(bldGroup.numComps);
          END;
        END;

        <* ASSERT g >= 0 *>

        (* gather the build group elements *)
        bldGroup.Comp     := NEW(REF ARRAY OF WaComp, bldGroup.numComps);
        FOR i := 0 TO numComps-1 DO
          IF Comp[i].bldGrp = g THEN
            bldGroup.Comp[idx] := Comp[i];
            INC(idx);
          END;
        END;

        RETURN bldGroup;
      END makeGroup;

    PROCEDURE buildAll(VAR group : BldGroup; numGroups : INTEGER; rec : REF ARRAY OF REF BldGroup) =
      VAR
        bld     : WASM.BuilderRef;
        cmpName : TEXT;
        cmpStr  : Ctypes.char_star;
        fld     : WaField;
        fldName : TEXT;
        fldAttr : TEXT;
        fldStr  : Ctypes.char_star;
        bldOK   : BOOLEAN;
        errIdx  : WASM.Index;
        errRsn  : WASM.BuilderError;
        N       : CARDINAL;
        litN    := NEW(REF WASM.Literal);
        sizeN   : WASM.ExpressionRef;
        cmpNew  : WASM.ExpressionRef;
        numElem : INTEGER;
      BEGIN
        self.Trace("ModCompos.buildAll ", Fmt.Int(numGroups));
        bld := WASM.BuilderCreate(group.numComps);
        (* Create the recursive groups *)
        numElem := 0;
        FOR g := 0 TO numGroups-1 DO
          (* Copy the group *)
          FOR i := 0 TO rec[g].numComps-1 DO
            group.Comp[numElem + i] := rec[g].Comp[i];
          END;
          (* Tell the builder about it *)
          WASM.BuilderRecGroup(bld, numElem, rec[g].numComps);
          self.Trace("  RecGroup ", Fmt.Int(g), " start=", Fmt.Int(numElem), " len=", Fmt.Int(rec[g].numComps));
          INC(numElem, rec[g].numComps);
        END;

        FOR i := 0 TO group.numComps-1 DO
          TYPECASE group.Comp[i] OF
          | WaArray (arr)  =>
              (* Build descriptor for array *)
              IF arr.ofComp # NIL THEN
                (* the element is a composite ref - use its interim type *)
                fldType[0] := arr.ofComp.wType;
                fldPack[0] := WPACK_not;
              ELSE
                fldType[0] := arr.element.type;
                fldPack[0] := arr.element.pack;
              END;
              cmpName := Typelabel(arr);
              self.Trace("  Array ", cmpName, " OF ", Typelabel(arr.element), " comp=", Fmt.Bool(arr.ofComp # NIL), eol := FALSE);
              self.Trace(" type=", Fmt.Int(fldType[0]), " pack=", Fmt.Int(fldPack[0]), " idx=", Fmt.Int(i));

              WASM.BuilderSetArray(bld, i, fldType[0], fldPack[0], 1 (*mutable*));

              (* set builder interim types in case needed *)
              arr.heap  := WASM.BuilderGetTempHeapType(bld, i);
              arr.wType := WASM.BuilderGetTempRefType(bld, arr.heap, 1);

          | WaStruct (str) =>
              (* Build descriptor for structure *)
              cmpName := Typelabel(str);
              self.Trace("  Struct ", cmpName, " idx=", Fmt.Int(i));
              numElem := str.numFields;
              FOR f := 0 TO numElem-1 DO
                fld     := str.fields[f];
                fldName := Typelabel(fld);
                fldStr  := Cstar(fldName);
                fldAttr := " size=" & Fmt.Int(fld.size) & " offset="
                         & Fmt.Int(fld.offset) & " typeid=" & M3IR.FormatUID(fld.typeid)
                         & " wtype=" & Fmt.Int(fld.type) & " pack=" & Fmt.Int(fld.pack);
                self.Trace("    field=", fldName, fldAttr);

                IF fld.comp # NIL THEN
                  (* the field is, itself, a composite ref - use its interim type *)
                  fldType[f] := fld.comp.wType;
                  fldPack[f] := WPACK_not;
                ELSE
                  fldType[f] := fld.type;
                  fldPack[f] := fld.pack;
                END;
                fldMut[f]  := VAL(1, CHAR);
              END;

              WASM.BuilderSetStruct(bld, i, fldType, fldPack, fldMut, numElem);

              (* set builder interim types in case needed *)
              str.heap  := WASM.BuilderGetTempHeapType(bld, i);
              str.wType := WASM.BuilderGetTempRefType(bld, str.heap, 1);

          | WaSig (sig)    =>
              cmpName := Typelabel(sig);
              self.Trace("  Sig ", cmpName, " idx=", Fmt.Int(i));
          ELSE
            <* ASSERT FALSE *>
          END;
        END;

        (* Register the composite types *)
        bldOK := WASM.BuilderBuildAndDispose(bld, group.heapType, errIdx, errRsn);
        IF bldOK THEN
            self.Trace("ModCompos build successful.")
        ELSE
          IO.Put("ModCompos failure idx=" & Fmt.Int(errIdx) & " reason=" & Fmt.Int(errRsn) & Wr.EOL)
        END;

        <*ASSERT self.prolog # NIL *>

        FOR i := 0 TO group.numComps-1 DO
          TYPECASE group.Comp[i] OF
          | WaArray (arr)  =>
              (* Array name *)
              cmpName := Typelabel(arr);
              cmpStr  := Cstar(cmpName);
              WASM.ModuleSetTypeName(self.moduleRef, group.heapType[i], cmpStr);

              (* save the built types *)
              arr.heap  := group.heapType[i];
              arr.wType := WASM.TypeFromHeap(arr.heap, TRUE (*nullable*));

              (* reference a new array of this type *)
              IF arr.fixed # NIL THEN N := arr.fixed.number;
                                 ELSE N := 3; (* open, pick any value *)
                                 END;

              self.Trace("ModCompos array/new ", cmpName, " type=", Fmt.Int(arr.wType), " N=", Fmt.Int(N));

              litN^  := WASM.LiteralInt32(N);
              sizeN  := WASM.Const(self.moduleRef, litN);
              cmpNew := WASM.Drop(self.moduleRef, 
                              WASM.ArrayNew(self.moduleRef, arr.heap, sizeN, NIL));
              WASM.BlockInsertChildAt(self.prolog.entryBB, 0, cmpNew);


          | WaStruct (str) =>
              (* Structure names  *)
              cmpName := Typelabel(str);
              cmpStr  := Cstar(cmpName);
              WASM.ModuleSetTypeName(self.moduleRef, group.heapType[i], cmpStr);
              numElem := str.numFields;
              FOR f := 0 TO numElem-1 DO
                fld     := str.fields[f];
                fldName := Typelabel(fld);
                fldStr  := Cstar(fldName);
                WASM.ModuleSetFieldName(self.moduleRef, group.heapType[i], f, fldStr);
               self.Trace("ModCompos name ", cmpName, " -> ", fldName);
              END;

              (* save the built types *)
              str.heap  := group.heapType[i];
              str.wType := WASM.TypeFromHeap(str.heap, TRUE (*nullable*));


              (* In declare_procedure we saved the prolog. Add struct.new_default 
                 expressions to the entry block *)
              cmpNew := WASM.Drop(self.moduleRef, 
                                WASM.StructNew(self.moduleRef, NIL, 0, group.heapType[i]));
              WASM.BlockInsertChildAt(self.prolog.entryBB, 0, cmpNew);

          | WaSig (sig)    =>
              (* Proctype name *)
            cmpName := Typelabel(sig);
            self.Trace("ModCompos sig ", cmpName, " idx=", Fmt.Int(i));
          ELSE
            <* ASSERT FALSE *>
          END;
        END;
     END buildAll;


  BEGIN
    self.Trace("ModCompos ", Fmt.Int(numComps));
    IF numComps > 0 THEN
      Comp    := NEW(REF ARRAY OF WaComp, numComps);
      Grouped := NEW(REF ARRAY OF BOOLEAN, numComps);
    END;

    (* Composite attribute allocation *)
    FOR i := 0 TO numComps-1 DO
      Comp[i] := NARROW(Get(self.compStack, i), WaComp);
      numElem := 0;
      TYPECASE Comp[i] OF
      | WaArray (arr)  => arr.bldGrp := i;
                          numElem    := 1;
      | WaStruct (str) => str.bldGrp := i;
                          numElem    := str.numFields;
      | WaSig (sig)    => sig.bldGrp := i;
      ELSE
        <* ASSERT FALSE *>
      END;
      IF numElem > fldMax THEN
        fldMax := numElem;
      END;
    END;
    fldType := NEW (REF ARRAY OF WASM.Type, fldMax);
    fldPack := NEW (REF ARRAY OF WASM.Packed, fldMax);
    fldMut  := NEW (REF ARRAY OF CHAR, fldMax);

    (* How many groups? *)
    groups := countGroups(Comp, Grouped, numComps);
    self.Trace("  Group count ", Fmt.Int(groups));
    bldGroup := NEW(REF ARRAY OF REF BldGroup, groups);
    FOR i := 0 TO numComps-1 DO
      Grouped[i] := FALSE;
    END;

    (* Gather them up *)
    FOR i := 0 TO groups-1 DO
      bldGroup[i] := makeGroup(Comp, Grouped, numComps);
    END;

    (* Validate that none are missed  *)
    numElem := 0;
    FOR i := 0 TO groups-1 DO
      INC(numElem, bldGroup[i].numComps);
    END;
    <* ASSERT numElem = numComps *>

    (* actually build them *)
    all.numComps := numComps;
    all.Comp     := Comp;
    all.heapType := NEW(REF ARRAY OF WASM.HeapTypeRef, numComps);
    buildAll(all, groups, bldGroup);

  END ModCompos;


(*------------------------------------------------------ Variable Parsing ---*)

PROCEDURE NewVar
  (self: T; name : Name; size : ByteSize; align : Alignment; type : Type;
   isConst : BOOLEAN; m3t : TypeUID; in_memory : BOOLEAN; up_level : BOOLEAN;
   exported : BOOLEAN; inited : BOOLEAN; frequency : Frequency; varType : VarType)
: Var =
  VAR
    v := NEW (WaVar, tag := self.next_var, name := name, size := size, type := type,
              isConst := isConst, align := align, m3t := m3t, in_memory := in_memory,
              up_level := up_level, exported := exported, inited := inited,
              frequency := frequency, varType := varType);
  BEGIN
    INC (self.next_var);
    IF varType = VarType.Global THEN
      v.inits := NEW(RefSeq.T).init();
    END;
    (* DONE: handled structures *)
    v.waType := WasmType(v.type);
    RETURN v;
  END NewVar;

PROCEDURE VName(v : WaVar; debug := FALSE) : TEXT =
  VAR
    name : TEXT;
  BEGIN
    IF v.name = M3ID.NoID THEN
      name := "tmp." & ItoT(v.tag);
    ELSE
      name := M3ID.ToText(v.name);
    END;
    IF v.varType = VarType.Param AND NOT debug THEN
      name := name & ".addr";
    END;
    RETURN name;
  END VName;

PROCEDURE ItoT(int : INTEGER) : TEXT =
  VAR
   x : Target.Int; res : BOOLEAN;
  BEGIN
    res := TInt.FromInt (int, x);
    <*ASSERT res*>
    RETURN TInt.ToText(x);
  END ItoT;

PROCEDURE set_index(v : WaVar; proc : WaProc; index : WASM.Index) = 
  BEGIN
    v.inProc  := proc;
    v.waIndex := index;
  END set_index;


(*----------------------------------------------------- Procedure Parsing ---*)
PROCEDURE NewProc (self: T; name : Name; numParams : INTEGER; returnType : Type; lev : INTEGER; cc : CallingConvention; exported : BOOLEAN; parent : Proc): Proc =
  VAR
    p := NEW (WaProc, tag := self.next_proc, name := name, numParams := numParams, returnType := returnType, lev := lev, cc := cc, exported := exported, parent := parent);
  BEGIN
    INC (self.next_proc);
    RETURN p;
  END NewProc;

PROCEDURE SetParms(self : T; proc : WaProc) = 
  VAR
    numArgs  := proc.numParams;
    argTuple : WASM.Type;
    argTypes : REF ARRAY OF WASM.Type;
    arg      : REFANY;
    param    : WaVar;
  BEGIN
    CASE numArgs OF
    | 0 =>
      argTypes := NIL;
      argTuple := WTYPE_none;
    | 1 =>
      argTypes := NIL;
      arg      := Get(proc.paramStack);
      param    := NARROW(arg,WaVar);
      self.Trace("\tsetParm=0 Index=", Fmt.Int(param.waIndex), " waType=", Fmt.Int(param.waType) & " name=" & M3ID.ToText(param.name));
      argTuple := param.waType;
    ELSE
      argTypes := NEW(REF ARRAY OF WASM.Type, numArgs);
      FOR paramNo := 0 TO numArgs-1 DO
        arg := Get(proc.paramStack,paramNo);
        param := NARROW(arg,WaVar);
        self.Trace("\tsetParm=", Fmt.Int(paramNo), " Index=", Fmt.Int(param.waIndex), " waType=" & Fmt.Int(param.waType) & " name=" & M3ID.ToText(param.name));
        argTypes[paramNo] := param.waType;
      END;
      argTuple := WASM.TypeCreate(argTypes, numArgs);
    END;
    proc.procParms := argTuple;
  END SetParms;

(*---------------------------------------------------------- Type Parsing ---*)

PROCEDURE WasmType(t : Type) : WASM.Type =
  BEGIN
    CASE t OF
    | Type.Int8,Type.Word8   => RETURN WTYPE_i32;
    | Type.Int16,Type.Word16  => RETURN WTYPE_i32;
    | Type.Int32,Type.Word32  => RETURN WTYPE_i32;
    | Type.Int64,Type.Word64  => RETURN WTYPE_i64;
    | Type.Reel   => RETURN WTYPE_f32;
    | Type.LReel  => RETURN WTYPE_f64;
    | Type.XReel  => RETURN WTYPE_f64;
    | Type.Addr   => RETURN WTYPE_i32;
    | Type.Struct => RETURN WTYPE_structref;  (* ref: garbage collected *)
    | Type.Void  => RETURN WTYPE_none;
    END;
  END WasmType;

PROCEDURE Typeinit(self: WaDefn; size : BitSize := 0; offset : BitOffset := 0; wtype : WASM.Type := NOTYPE; numFields : INTEGER := 0; pack : WASM.Packed := NOTYPE) : WaDefn =
  BEGIN
    self.size       := size;
    self.offset     := offset;
    self.type       := wtype;
    self.numFields  := numFields;
    self.pack       := pack;
    RETURN self;
  END Typeinit;

PROCEDURE NewField(def : WaDefn; typeid : TypeUID; name : Name; type : WASM.Type := NOTYPE; size : BitSize := 0; offset : BitOffset := 0; pack : WASM.Packed := NOTYPE): WaField =
  VAR
    fld := NEW(WaField, typeid := typeid, name := name, type := type, size := size, offset := offset, pack := pack, integral := FALSE);
  BEGIN
    TYPECASE def OF
    WaOrdinal (ord)  => fld.ord := ord;
    | WaFloat (flt)  => fld.flt := flt;
    | WaRef (ref)    => fld.ref := ref;
    | WaArray (arr)  => fld.arr := arr; fld.comp := arr; (* and comp ... *)
    | WaStruct (str) => fld.str := str; fld.comp := str;
    | WaSig (sig)    => fld.sig := sig; fld.comp := sig;
    | WaOpaque (opq) => fld.opq := opq;
    ELSE
    <* ASSERT FALSE *>
    END;
    RETURN fld;    
  END NewField;

PROCEDURE NewStruct(self: T; typeid : TypeUID; bit_size: BitSize; numFields, numMethods : INTEGER): WaStruct =
  VAR
    s := NEW (WaStruct, typeid:= typeid, integral := FALSE);
  BEGIN
    EVAL s.init(size := bit_size, offset := 0, wtype := WTYPE_structref, numFields := numFields, pack := WPACK_not);
    IF numFields > 0 THEN
      s.fields := NEW(REF ARRAY OF WaField, numFields);
    END;
    IF numMethods > 0 THEN
      s.numMethods := numMethods;
      s.methods := NEW(REF ARRAY OF WaField, numMethods);
    END;
    Typeadd(self, s);
    RETURN s;
  END NewStruct;

PROCEDURE NewSig(self: T; typeid: TypeUID; n_formals: INTEGER; result: TypeUID; n_raises: INTEGER; cc: CallingConvention) : WaSig =
  VAR
    s := NEW (WaSig, typeid := typeid, type := WTYPE_funcref, numFields := n_formals, result := result, numRaises := n_raises, cc := cc, integral := FALSE);
  BEGIN
    IF n_formals > 0 THEN
      s.fields := NEW(REF ARRAY OF WaField, n_formals);
    END;
    IF n_raises > 0 THEN
      s.raises := NEW(REF ARRAY OF Name, n_raises);
    END;
    Typeadd(self, s);
    RETURN s;
  END NewSig;

PROCEDURE Typelabel(def : WaDefn) : TEXT =
  VAR lbl : TEXT;
  BEGIN
    IF def.name # M3ID.NoID THEN
      lbl := M3ID.ToText(def.name);
    ELSE
      lbl := "T_" & M3IR.FormatUID(def.typeid);
    END;
    RETURN lbl;
  END Typelabel;

PROCEDURE Typename(self: T; typeid : TypeUID; name : Name) =
  VAR def := Typedef(self, typeid);
  BEGIN
    <* ASSERT def # NIL *>
    def.name := name;
  END Typename;

PROCEDURE Typedef(self: T; typeid : TypeUID) : WaDefn =
  VAR a : REFANY; defn : WaDefn := NIL;
  BEGIN
    IF self.defTable.get(typeid, a) THEN
      defn := NARROW(a,WaDefn);
    END;
    RETURN defn;
  END Typedef;

PROCEDURE Typeadd(self: T; def : WaDefn) =
  BEGIN
    EVAL self.defTable.put(def.typeid, def);
  END Typeadd;

PROCEDURE Compadd(self: T; comp : WaComp) =
  VAR compType : TEXT;
  BEGIN
    TYPECASE comp OF
    | WaArray  => compType := "WaArray";
    | WaStruct => compType := "WaStruct";
    | WaSig    => compType := "WaSig";
    ELSE
      <* ASSERT FALSE *>
    END;
    self.Trace("  Composite typeid=", M3IR.FormatUID(comp.typeid), " ", compType);
    PushRev(self.compStack, comp);
  END Compadd;

(*---------------------------------------------------------------- Stacks ---*)
PROCEDURE Pop(stack : RefSeq.T; n: CARDINAL := 1) =
  BEGIN
    FOR i := 1 TO n DO EVAL stack.remlo(); END;
  END Pop;

PROCEDURE Push(stack : RefSeq.T; value : REFANY) =
  BEGIN
    stack.addlo(value);
  END Push;

PROCEDURE PushRev(stack : RefSeq.T; value : REFANY) =
  BEGIN
    stack.addhi(value);
  END PushRev;

PROCEDURE Get(stack : RefSeq.T; n: CARDINAL := 0) : REFANY =
  BEGIN
    RETURN stack.get(n);
  END Get;

(*--------------------------------------------------------- Miscellaneous ---*)

PROCEDURE Trace(self : T; a, b, c, d, e, f: TEXT := NIL; eol := TRUE) =
  BEGIN
    IF NOT self.tracing THEN RETURN; END;
    IF (a # NIL) THEN IO.Put(a) END;
    IF (b # NIL) THEN IO.Put(b) END;
    IF (c # NIL) THEN IO.Put(c) END;
    IF (d # NIL) THEN IO.Put(d) END;
    IF (e # NIL) THEN IO.Put(e) END;
    IF (f # NIL) THEN IO.Put(f) END;
    IF eol THEN IO.Put(Wr.EOL); END;
  END Trace;

(* avoid the m3toc stuff everywhere *)
PROCEDURE Cstar(t : TEXT) : Ctypes.char_star =
  BEGIN
    RETURN M3toC.CopyTtoS(t);
  END Cstar;

TYPE
  Env = M3Front.Environment OBJECT
  OVERRIDES
    note_ast           := Pass0_NoteAST;
  END;

PROCEDURE Pass0_NoteAST (<*UNUSED*>env: Env;  <*UNUSED*>intf: M3ID.T;  <*UNUSED*>ast: REFANY) =
  BEGIN
  END Pass0_NoteAST;

(* Initialise the m3fe with no-op compile *)
PROCEDURE M3FEInit() =
  VAR
    source : M3Front.SourceFile;
    env    := NEW(Env);
  BEGIN
    EVAL Target.Init("AMD64_LINUX");
    source.name     := "/dev/null";
    TRY
      source.contents := FS.OpenFileReadonly(source.name);
    EXCEPT
    ELSE
        IO.Put("failed to open /dev/null" & Wr.EOL);
    END;
    EVAL M3Front.ParseImports(source, env);
    TRY
      source.contents.close();
    EXCEPT
    ELSE
        IO.Put("failed to close /dev/null" & Wr.EOL);
    END;
  END M3FEInit;

(*--------------------------------------------------------- Debug Objects ---*)
TYPE

  (* debug lexical blocks *)
  BlockDebug = OBJECT
  END;


(*------------------------------------------------------ Debug Procedures ---*)

(* debug for locals and params *)
PROCEDURE DebugVar(self : T; v : WaVar; <*UNUSED*> argNum : CARDINAL := 0) =
  VAR
    name : TEXT;
  BEGIN
    IF NOT self.genDebug THEN RETURN; END;

    name := VName(v,TRUE);
    (* Dont debug temps or _result or the static link *)
    (* Review: Actually probably so for static link, and maybe result. *)

    IF v.name = M3ID.NoID OR
       Text.Equal(name,"_result") OR
       Text.Equal(name,"_link") THEN RETURN;
    END;
  END DebugVar;

PROCEDURE DebugFunc(self : T; <*UNUSED*> p : Proc) =
  BEGIN
    IF NOT self.genDebug THEN RETURN END;
  END DebugFunc;

PROCEDURE DebugClearLoc(self : T) =
  BEGIN
    IF self.genDebug THEN
    END;
  END DebugClearLoc;

PROCEDURE DebugLine(self : T; <*UNUSED*> line : INTEGER := 0) =
  BEGIN
    IF NOT self.genDebug THEN RETURN END;
  END DebugLine;

PROCEDURE DebugLocalsParams(self : T; proc : WaProc) =
  VAR
    local,param : WaVar;
    numParams,numLocals : CARDINAL;
    arg : REFANY;
  BEGIN
    IF NOT self.genDebug THEN RETURN; END;
    numParams := proc.numParams;
    FOR i := 0 TO numParams - 1 DO
      arg := Get(proc.paramStack,i);
      param := NARROW(arg,WaVar);
      DebugVar(self, param, i + 1);
    END;
    numLocals := proc.localStack.size();
    FOR i := 0 TO numLocals - 1 DO
      arg := Get(proc.localStack,i);
      local := NARROW(arg,WaVar);
      DebugVar(self, local);
    END;
  END DebugLocalsParams;

PROCEDURE DebugPushBlock(self : T) =
  VAR
    blockRef : BlockDebug;
  BEGIN
    IF NOT self.genDebug THEN RETURN END;
    IF self.debugLexStack.size() = 0 THEN
      blockRef := NEW(BlockDebug);
    ELSE
      blockRef := Get(self.debugLexStack);
      blockRef := NEW(BlockDebug);
    END;
    Push(self.debugLexStack, blockRef);
  END DebugPushBlock;

PROCEDURE DebugPopBlock(self : T) =
  BEGIN
    IF NOT self.genDebug THEN RETURN; END;
    Pop(self.debugLexStack);
  END DebugPopBlock;


(*-------------------------------------------------- Module Initialsation ---*)

BEGIN
  (* WASM Predeclared Types *)
  WTYPE_none        := WASM.TypeNone();
  WTYPE_i32         := WASM.TypeInt32();
  WTYPE_i64         := WASM.TypeInt64();
  WTYPE_f32         := WASM.TypeFloat32();
  WTYPE_f64         := WASM.TypeFloat64();
  WTYPE_v128        := WASM.TypeVec128();
  WTYPE_funcref     := WASM.TypeFuncref();
  WTYPE_externref   := WASM.TypeExternref();
  WTYPE_anyref      := WASM.TypeAnyref();
  WTYPE_eqref       := WASM.TypeEqref();
  WTYPE_i31ref      := WASM.TypeI31ref();
  WTYPE_structref   := WASM.TypeStructref();
  WTYPE_arrayref    := WASM.TypeArrayref();
  WTYPE_stringref   := WASM.TypeStringref();
  WTYPE_nullref     := WASM.TypeNullref();
  WTYPE_nullexternref := WASM.TypeNullExternref();
  WTYPE_nullfuncref := WASM.TypeNullFuncref(); 
  WTYPE_unreachable := WASM.TypeUnreachable();
  WTYPE_auto        := WASM.TypeAuto();

  WPACK_not   := WASM.PackedNot();
  WPACK_int8  := WASM.PackedInt8();
  WPACK_int16 := WASM.PackedInt16();

  IO.Put("WTYPE_none        := " & Fmt.Int(WTYPE_none) & Wr.EOL);
  IO.Put("WTYPE_i32         := " & Fmt.Int(WTYPE_i32) & Wr.EOL);
  IO.Put("WTYPE_i64         := " &  Fmt.Int(WTYPE_i64) & Wr.EOL);
  IO.Put("WTYPE_f32         := " & Fmt.Int(WTYPE_f32) & Wr.EOL);
  IO.Put("WTYPE_f64         := " & Fmt.Int(WTYPE_f64) & Wr.EOL);
  IO.Put("WTYPE_v128        := " & Fmt.Int(WTYPE_v128) & Wr.EOL);
  IO.Put("WTYPE_funcref     := " & Fmt.Int(WTYPE_funcref) & Wr.EOL);
  IO.Put("WTYPE_externref   := " & Fmt.Int(WTYPE_externref) & Wr.EOL);
  IO.Put("WTYPE_anyref      := " & Fmt.Int(WTYPE_anyref) & Wr.EOL);
  IO.Put("WTYPE_eqref       := " & Fmt.Int(WTYPE_eqref) & Wr.EOL);
  IO.Put("WTYPE_i31ref      := " & Fmt.Int(WTYPE_i31ref) & Wr.EOL);
  IO.Put("WTYPE_structref     :=" & Fmt.Int(WTYPE_structref) & Wr.EOL);
  IO.Put("WTYPE_arrayref      :=" & Fmt.Int(WTYPE_arrayref) & Wr.EOL);
  IO.Put("WTYPE_stringref     :=" & Fmt.Int(WTYPE_stringref) & Wr.EOL);
  IO.Put("WTYPE_nullref       :=" & Fmt.Int(WTYPE_nullref) & Wr.EOL);
  IO.Put("WTYPE_nullexternref :=" & Fmt.Int(WTYPE_nullexternref) & Wr.EOL);
  IO.Put("WTYPE_nullfuncref   :=" & Fmt.Int(WTYPE_nullfuncref) & Wr.EOL);
  IO.Put("WTYPE_unreachable := " & Fmt.Int(WTYPE_unreachable) & Wr.EOL);
  IO.Put("WTYPE_auto        := " & Fmt.Int(WTYPE_auto) & Wr.EOL);
  IO.Put("WPACK_not         := " & Fmt.Int(WPACK_not) & Wr.EOL);
  IO.Put("WPACK_int8        := " & Fmt.Int(WPACK_int8) & Wr.EOL);
  IO.Put("WPACK_int16       := " & Fmt.Int(WPACK_int16) & Wr.EOL);

  (* Modula-3 predeclared types, from m3fe *)
  EVAL Target.Init("AMD64_LINUX");
  M3FEInit();

  VAR converted : BOOLEAN;
  BEGIN
    converted := TInt.ToInt(TInt.Min8, WDEF_Min8);
    <* ASSERT converted *>
    converted := TInt.ToInt(TInt.Max8, WDEF_Max8);
    <* ASSERT converted *>
    converted := TInt.ToInt(TInt.Max8U, WDEF_Max8U);
    <* ASSERT converted *>
    converted := TInt.ToInt(TInt.Min16, WDEF_Min16);
    <* ASSERT converted *>
    converted := TInt.ToInt(TInt.Max16, WDEF_Max16);
    <* ASSERT converted *>
    converted := TInt.ToInt(TInt.Max16U, WDEF_Max16U);
    <* ASSERT converted *>
    converted := TInt.ToInt(TInt.Min32, WDEF_Min32);
    <* ASSERT converted *>
    converted := TInt.ToInt(TInt.Max32, WDEF_Max32);
    <* ASSERT converted *>
    converted := TInt.ToInt(TInt.Max32U, WDEF_Max32U);
    <* ASSERT converted *>
    converted := TInt.ToInt(TInt.Min64, WDEF_Min64);
    <* ASSERT converted *>
    converted := TInt.ToInt(TInt.Max64, WDEF_Max64);
    <* ASSERT converted *>
    (* converted := TInt.ToInt(TInt.Max64U, WDEF_Max64U); *)
    (* ASSERT failure *)
    (* not representable on a 64 bit machine - placeholder for now *)
    WDEF_Max64U := WDEF_Max64;
  END;


END M3NG_WASM.
