(* Copyright (C) 2026 Sunil Khare. All rights reserved. *)

INTERFACE M3NG_WASM;

(* WASM Code Generation *)

IMPORT M3IR;

TYPE T <: Public;
TYPE Public = M3IR.T OBJECT
  METHODS
    module_write(binFileName, textFileName: TEXT) : INTEGER;
  END;

PROCEDURE New(WasmDebug : BOOLEAN; GenDebug: BOOLEAN) : T; 

END M3NG_WASM.
