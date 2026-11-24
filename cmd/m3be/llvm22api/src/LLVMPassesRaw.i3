(* Hand-written (not SWIG-generated) raw binding of the new-pass-manager entry
   points in llvm-c/Transforms/PassBuilder.h and llvm-c/Error.h.  An
   LLVMErrorRef is NIL on success; a non-NIL one must be consumed with
   GetErrorMessage (which frees it). *)

UNSAFE INTERFACE LLVMPassesRaw;

IMPORT Ctypes AS C;

<* EXTERNAL LLVMCreatePassBuilderOptions *>
PROCEDURE CreatePassBuilderOptions (): ADDRESS;

<* EXTERNAL LLVMDisposePassBuilderOptions *>
PROCEDURE DisposePassBuilderOptions (Options: ADDRESS; );

<* EXTERNAL LLVMRunPasses *>
PROCEDURE RunPasses
  (M: ADDRESS; Passes: C.char_star; TM, Options: ADDRESS; ): ADDRESS;

<* EXTERNAL LLVMGetErrorMessage *>
PROCEDURE GetErrorMessage (Err: ADDRESS; ): C.char_star;

<* EXTERNAL LLVMDisposeErrorMessage *>
PROCEDURE DisposeErrorMessage (ErrMsg: C.char_star; );

END LLVMPassesRaw.
