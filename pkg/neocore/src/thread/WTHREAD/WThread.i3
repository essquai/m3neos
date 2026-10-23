(* Copyright (C) 2026 Sunil Khare. All righs reserved. *)

UNSAFE INTERFACE WThread;

IMPORT Thread;
IMPORT RTSync;
FROM Ctypes  IMPORT void_star, int, const_char_star;
FROM Cstddef IMPORT size_t;

CONST NREGS = 6;

TYPE
  Routine = PROCEDURE(arg: ADDRESS);
  Recce   = { deferred, relief, vigilant, detached, joined };
  Context = RECORD
    watch       : BITS 32 FOR Recce;  (* condition *)
    tid         : int;        (* thread ID         *)
    outerSyn    : void_star;  (* mutex for joinSyn *)
    joinSyn     : void_star;  (* wake here on join *)

    fn          : Routine;    (* thread routine    *)
    fn_arg      : void_star;  (* routine argument  *)
    self        : void_star;  (* parameter         *)
    stack_size  : size_t;     (* parameter         *) 

    stack_addr  : void_star;  (* allocated         *)
    stack_ptr   : void_star;  (* current           *)
    stack_top   : void_star;  (* initial           *)
    tls_base    : void_star;  (* thread-local vars *)
    stack_chain : void_star;  (* llvm gc roots     *)
    p           : size_t;     (* pthread_t         *)
    regs        : ARRAY [0..NREGS-1] OF size_t;
                              (* ^registers        *)
    ended       : int;        (* reap ready        *)
  END;


  (* Thread safepoint coordination is through nexus *)
  Nexus = RECORD
    safePoint    : int;
    safeSyn      : RTSync.T;

    watchSyn     : RTSync.T;
    parked       : int;

    forkList     : Thread.T;
    forkSyn      : RTSync.T;
  END;

<*EXTERNAL "nthr_nexus"*>
VAR nexus : Nexus;

<*EXTERNAL "nthr_create"*>
PROCEDURE thread_create(VAR ctxt : Context; VAR ctxSyn : RTSync.T; stackSize: size_t; routine: Routine; arg: void_star; self : void_star): int;

<*EXTERNAL "nthr_vigil"*>
PROCEDURE thread_vigil(VAR ctxt : Context) : Recce;

<*EXTERNAL "nthr_self"*>
PROCEDURE thread_self() : Thread.T;

<*EXTERNAL "nthr_default"*>
PROCEDURE thread_default(VAR ctxt : Context; VAR ctxSyn : RTSync.T; self : void_star);

<*EXTERNAL "nthr_arch_stack32"*>
PROCEDURE thread_stack32();

<*EXTERNAL "nthr_debug"*>
PROCEDURE thread_print(txt : const_char_star; addr : ADDRESS; p1: INTEGER; p2 : INTEGER);

<*EXTERNAL "nthr_match"*>
PROCEDURE thread_match(lockSz, ctxtSz, nexusSz : size_t);

END WThread.
