(* Copyright 2025 Sunil Khare. All rights reserved.    *)
(* See file COPYRIGHT-SK for details. *)

MODULE M3Req;

IMPORT M3ID, M3File, M3Path, Dirs, DirStack, Fmt, FSUtils, Pathname;
IMPORT IntRefTbl, Text, TextUtils;
IMPORT Arg, Msg, Utils;

CONST
  scheme = ARRAY Kind OF TEXT {"file:", "fossil:", "git:", "hg:", "?:"};


PROCEDURE exec(cmd: TEXT; a1, a2, a3, a4, a5: TEXT := NIL) : INTEGER =
  VAR args := Arg.NewList();
  BEGIN
    IF (a1 # NIL) THEN Arg.Append(args, a1) END;
    IF (a2 # NIL) THEN Arg.Append(args, a2) END;
    IF (a3 # NIL) THEN Arg.Append(args, a3) END;
    IF (a4 # NIL) THEN Arg.Append(args, a4) END;
    IF (a5 # NIL) THEN Arg.Append(args, a5) END;
    RETURN Utils.Execute(cmd, args, NIL, FALSE);
  END exec;

PROCEDURE New (install: TEXT; cache: IntRefTbl.T; pkg_uri, revision: TEXT): T =
  VAR
    t     :  T;
    k     := Kind.Unknown;
    res   := pkg_uri;
    base  :  TEXT := NIL;
    name  :  TEXT := NIL;
    path  :  TEXT := NIL;
    pkgid := M3ID.NoID;
  BEGIN
    (* Extract the scheme *)
    FOR s := FIRST (Kind) TO LAST (Kind) DO
      IF TextUtils.StartsWith(res, scheme[s], FALSE) THEN
        res := Text.Sub(res, Text.Length(scheme[s]));
        k := s;
        (* And name *)
        IF TextUtils.StartsWith(res, "//") THEN
          name := Text.Sub(res, 2);
        ELSIF (k = Kind.File) THEN
          name := res;
        ELSE
          k := Kind.Unknown;
          Msg.Error (NIL, "require uri \"" & pkg_uri & "\" missing an authority - //");
        END;
        EXIT;
      END;
    END;

    IF (k = Kind.Unknown) THEN
      Msg.Error(NIL, "require uri \"" & pkg_uri & "\" scheme invalid")
    ELSIF (name # NIL AND TextUtils.Contains(name, "/")) THEN
      base := Pathname.Last(name);
      IF (NOT Text.Empty(revision)) THEN
        base := base & "." & revision;
      END;
      pkgid := M3ID.Add(base);
      path  := M3Path.New(install, base);
    ELSE
      k := Kind.Unknown;
      Msg.Error (NIL, "require uri \"" & pkg_uri & "\" missing a path - /");
    END;

    t := NEW (T, pkg_cache := cache, pkg_uri := pkg_uri, pkg := pkgid,
              scheme := k, name := name, pkg_path := path, rev := revision);
    RETURN t;
  END New;

PROCEDURE IsInstalled (t: T): BOOLEAN =
  VAR b := M3File.IsDirectory(t.pkg_path);
  BEGIN
    IF (b) THEN
      (* It's there, let them find it *)
      EVAL t.pkg_cache.put(t.pkg, t.pkg_path);
    END;
    RETURN b;
  END IsInstalled;

PROCEDURE Get(t: T) : BOOLEAN =
  VAR got : BOOLEAN;
  BEGIN
    CASE t.scheme OF
    | Kind.File    =>  got := GetFile(t);
    | Kind.Fossil  =>  got := GetFossil(t);
    | Kind.Git     =>  got := GetGit(t);
    | Kind.Mercury =>  got := GetHg(t);
    ELSE
      got := FALSE;
    END;
    RETURN got;
  END Get;

PROCEDURE GetFile(t: T) : BOOLEAN =
  VAR
    got    := FALSE;
    pkg_nm := M3ID.ToText(t.pkg);
  BEGIN
    (* name is a local directory *)
    IF (NOT Pathname.Absolute(t.name)) THEN
      Msg.Error (NIL, "require package \"" & t.pkg_uri & "\" specifies relative path.");
    ELSIF (NOT M3File.IsDirectory(t.name)) THEN
      Msg.Error (NIL, "require package \"" & t.name & "\" not a directory.");
    ELSE
      IF (M3File.IsDirectory(pkg_nm)) THEN Dirs.RemoveRecursively(pkg_nm) END;
      IF (exec("cp", "-r", t.name, pkg_nm) = 0) THEN
        got := TRUE;
      ELSE
         Msg.Error (NIL, "require package \"" & t.pkg_uri & "\" file get failure.");
      END;
    END;
    RETURN got;
  END GetFile;

PROCEDURE GetFossil(t: T) : BOOLEAN =
  VAR
    got    := FALSE;
    pkg_nm := M3ID.ToText(t.pkg);
    fs     :  INTEGER;
  BEGIN
    TRY 
      IF (M3File.IsDirectory(pkg_nm)) THEN Dirs.RemoveRecursively(pkg_nm) END;
      FSUtils.Mkdir(pkg_nm);
      DirStack.PushDir(pkg_nm);

      fs := exec("fossil", "open", "https://" & t.name);
      Msg.Commands("fossil open ",  "https://" & t.name & " => ", Fmt.Int(fs));

      fs := fs + exec("fossil", "update", t.rev);
      Msg.Commands("fossil update ", t.rev, " => ", Fmt.Int(fs));

      DirStack.PopDir();
      IF (fs = 0) THEN
        got := TRUE;
      ELSE
        Msg.Error (NIL, "require package \"" & t.pkg_uri & "\" fossil fetch failure.");
      END;
    EXCEPT
    | DirStack.Error =>
         Msg.Error (NIL, "require package \"" & t.pkg_uri & "\" get fetch failure.");
    | FSUtils.E =>
         Msg.Error (NIL, "require package \"" & t.pkg_uri & "\" mkdir failure");
    END;
    RETURN got;
  END GetFossil;

PROCEDURE GetGit(t: T) : BOOLEAN =
  VAR
    got    := FALSE;
    pkg_nm := M3ID.ToText(t.pkg);
    gs     := 0;
    co     : TEXT;
  BEGIN
    TRY
      IF (M3File.IsDirectory(pkg_nm)) THEN Dirs.RemoveRecursively(pkg_nm) END;
      FSUtils.Mkdir(pkg_nm);
      DirStack.PushDir(pkg_nm);

      gs := exec("git", "init", ".");
      Msg.Commands("git init . => ", Fmt.Int(gs));

      gs := gs + exec("git", "remote", "add", "origin", "https://" & t.name & ".git");
      Msg.Commands("git remote add origin ", "https://" & t.name & ".git => ", Fmt.Int(gs));

      gs := gs + exec("git", "fetch", "origin");
      Msg.Commands("git fetch origin => ", Fmt.Int(gs));

      IF (Text.Empty(t.rev)) THEN
        co := "master";
      ELSE
        co := "tags/" & t.rev;
      END;
      gs := gs + exec("git", "checkout", co);
      Msg.Commands("git checkout ", co, " => ", Fmt.Int(gs));

      DirStack.PopDir();
      IF (gs = 0) THEN
        got := TRUE;
      ELSE
        Msg.Error (NIL, "require package \"" & t.pkg_uri & "\" git fetch failure.");
      END;
    EXCEPT
    | DirStack.Error =>
         Msg.Error (NIL, "require package \"" & t.pkg_uri & "\" get fetch failure.");
    | FSUtils.E =>
         Msg.Error (NIL, "require package \"" & t.pkg_uri & "\" mkdir failure");
    END;
    RETURN got;
  END GetGit;

PROCEDURE GetHg(t: T) : BOOLEAN =
  VAR
    got    := FALSE;
    pkg_nm := M3ID.ToText(t.pkg);
    hs     :  INTEGER;
    branch :  TEXT;
  BEGIN
    TRY 
      DirStack.PushDir(pkg_nm);
      IF (Text.Empty(t.rev)) THEN
        branch := "default";
      ELSE
        branch := t.rev;
      END;
      hs := exec("hg", "clone", "--branch", branch, "https://" & t.name, ".");
      DirStack.PopDir();
      IF (hs = 0) THEN
        got := TRUE;
      ELSE
        Msg.Error (NIL, "require package \"" & t.pkg_uri & "\" hg fetch failure.");
      END;
    EXCEPT
    | DirStack.Error =>
         Msg.Error (NIL, "require package \"" & t.pkg_uri & "\" get fetch failure.");
    END;
    RETURN got;
  END GetHg;


PROCEDURE Deploy(t: T) =
  VAR
    bld_arg := Arg.NewList();
    shp_arg := Arg.NewList();
    pkg_nm  := M3ID.ToText(t.pkg);
    mm3s    := 0;
  BEGIN
    TRY 
      DirStack.PushDir(pkg_nm);

      Arg.Append(bld_arg, "-build");
      Arg.Append(bld_arg, "-keep");
      Arg.Append(bld_arg, Msg.MapLevel());
      mm3s := Utils.Execute("mm3", bld_arg, "mm3build.log", TRUE);
      Msg.Commands("mm3 -build -keep ", Msg.MapLevel(), " => ", Fmt.Int(mm3s));

      Arg.Append(shp_arg, "-ship");
      Arg.Append(shp_arg, "-keep");
      Arg.Append(shp_arg, Msg.MapLevel());
      mm3s := mm3s + Utils.Execute("mm3", shp_arg, "mm3ship.log", TRUE);
      Msg.Commands("mm3 -ship -keep ", Msg.MapLevel(), " => ", Fmt.Int(mm3s));

      (* pkg is imported and installed - now locate it *)
      EVAL t.pkg_cache.put(t.pkg, t.pkg_path);

      DirStack.PopDir();
    EXCEPT
    | DirStack.Error =>
         Msg.Error (NIL, "require package \"" & t.pkg_uri & "\" instalation failure.");
    END
  END Deploy;

BEGIN
END M3Req.
