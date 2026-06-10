INTERFACE M3CConv;
IMPORT Ctypes; (* favor Ctypes over Cstdint to work with older m3core *)

TYPE INT32 = Ctypes.int;
(*TYPE UINT32 = Ctypes.unsigned_int;*)

<*EXTERNAL M3CConv__IntToHex*>  PROCEDURE  IntToHex(a: INTEGER): TEXT;
<*EXTERNAL M3CConv__UIntToHex*> PROCEDURE UIntToHex(a: INTEGER): TEXT;
<*EXTERNAL M3CConv__IntToDec*>  PROCEDURE IntToDec(a: INTEGER): TEXT;

END M3CConv.
