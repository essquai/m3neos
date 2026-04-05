MODULE MxConfigC;

(* SAFE, limited version *)

PROCEDURE ifdef_win32(): BOOLEAN =
  BEGIN
    RETURN FALSE;
  END ifdef_win32;

PROCEDURE HOST(): TEXT =
  BEGIN
    RETURN "AMD64_LINUX";
  END HOST;

PROCEDURE CaseInsensitive(): BOOLEAN =
  BEGIN
    RETURN FALSE;  
  END CaseInsensitive;

PROCEDURE DeviceSeparator(): CHAR =
  BEGIN
    RETURN VAL(0, CHAR);
  END DeviceSeparator;

PROCEDURE DirectorySeparator(): CHAR =
  BEGIN
    RETURN '/';
  END DirectorySeparator;

BEGIN
END MxConfigC.
