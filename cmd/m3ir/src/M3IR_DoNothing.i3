INTERFACE M3IR_DoNothing;

(* This does nothing and is a good base for small M3IR passes. *)

IMPORT M3IR;

TYPE T <: Public;
TYPE Public = M3IR.T OBJECT
END;

END M3IR_DoNothing.
