INTERFACE IRIO_Tee;

IMPORT M3IR;

PROCEDURE New (child1, child2: M3IR.T): M3IR.T;
(* A new code generator that forwards each operation
   to both child1 and child2. *)

END IRIO_Tee.