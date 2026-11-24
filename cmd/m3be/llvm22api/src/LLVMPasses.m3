UNSAFE MODULE LLVMPasses;

IMPORT Ctypes AS C;
IMPORT M3toC;
IMPORT LLVM;
IMPORT LLVMPassesRaw AS Raw;

PROCEDURE RunPasses
  (M: LLVM.ModuleRef; Passes: TEXT; VAR OutMessage: TEXT): BOOLEAN =
  VAR
    opts: ADDRESS;
    err : ADDRESS;
    arg : C.char_star;
    cmsg: C.char_star;
  BEGIN
    opts := Raw.CreatePassBuilderOptions();
    arg := M3toC.SharedTtoS(Passes);
    err := Raw.RunPasses(M, arg, NIL, opts);
    M3toC.FreeSharedS(Passes, arg);
    Raw.DisposePassBuilderOptions(opts);
    IF err = NIL THEN RETURN FALSE END;
    cmsg := Raw.GetErrorMessage(err);
    IF cmsg # NIL THEN
      OutMessage := M3toC.CopyStoT(cmsg);
      Raw.DisposeErrorMessage(cmsg);
    ELSE
      OutMessage := "LLVMRunPasses failed";
    END;
    RETURN TRUE;
  END RunPasses;

BEGIN
END LLVMPasses.
