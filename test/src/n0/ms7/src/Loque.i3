(* 
 * Log Queue
 *
 * Queue log messages for serial writing
 *)

INTERFACE Loque;

IMPORT Thread;

TYPE

  T <: Public;
  Public = Thread.Closure OBJECT
  METHODS
    write(t : TEXT; a : ROOT; n : INTEGER; b : INTEGER := 0);
    close();
  END;

PROCEDURE Open() : T;

END Loque.