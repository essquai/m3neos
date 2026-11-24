(* Hand-written wrapper over LLVMRunPasses (new pass manager). *)

INTERFACE LLVMPasses;

IMPORT LLVM;

PROCEDURE RunPasses
  (M: LLVM.ModuleRef; Passes: TEXT; VAR OutMessage: TEXT): BOOLEAN;
(* Run the textual pass pipeline Passes (opt's -passes= syntax, e.g.
   "shadow-stack-gc-lowering") over M, with no target machine.  Returns TRUE
   on failure, with the reason in OutMessage; FALSE on success. *)

END LLVMPasses.
