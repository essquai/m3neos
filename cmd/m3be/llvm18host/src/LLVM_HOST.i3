INTERFACE LLVM_HOST;

IMPORT M3IR,Wr;

TYPE
  U <: Public;

  Public = M3IR.T OBJECT
  METHODS
    dumpLLVMIR(BitcodeFileName, AsmFileName: TEXT);
  END;

TYPE m3llvmDebugLevTyp = [ 0 .. 5 ]; (* Just leave some space here. *) 

(* returns a fresh, initialized code generator that writes LLVM IR
   as bitcode to 'wr_bin' and as LLVM assembly to 'wr_char'. 
   Either may be NIL. *)
PROCEDURE New 
  (output: Wr.T; targetTriple,dataRep : TEXT; m3llvmDebugLev: m3llvmDebugLevTyp; genDebug: BOOLEAN)
: M3IR.T; 

END LLVM_HOST.
