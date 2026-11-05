MODULE Main;

IMPORT RTIO;

PROCEDURE mainMS10() =
  BEGIN
    RTIO.PutText("Hello, wasm32\n");
    RTIO.Flush();
  END mainMS10;

BEGIN
  mainMS10();
END Main.