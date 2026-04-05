INTERFACE MxConfigC;

(* interface that is not UNSAFE *)

PROCEDURE ifdef_win32(): BOOLEAN;
PROCEDURE HOST(): TEXT;
PROCEDURE CaseInsensitive(): BOOLEAN;
PROCEDURE DeviceSeparator(): CHAR;
PROCEDURE DirectorySeparator(): CHAR;

END MxConfigC.
