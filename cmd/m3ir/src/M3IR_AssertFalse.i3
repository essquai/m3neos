INTERFACE M3IR_AssertFalse;

(* This asserts false in every function
 * and is a good basis for M3IR passes that must
 * override every method. *)

IMPORT M3IR;

TYPE T <: Public;
TYPE Public = M3IR.T OBJECT
END;

END M3IR_AssertFalse.
