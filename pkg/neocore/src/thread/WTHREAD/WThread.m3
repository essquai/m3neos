(* Copyright (C) 2026 Sunil Khare. All righs reserved. *)

UNSAFE MODULE WThread EXPORTS Thread, RTThread, RTOS, Scheduler, RTHooks, WThread;

IMPORT FloatMode, MutexRep, RTHeapRep;
IMPORT RT0, RTLinker;
IMPORT RTError;
IMPORT RTSync;
IMPORT M3toC;
FROM   Cstddef  IMPORT size_t;
FROM   Compiler IMPORT ThisFile, ThisLine;

REVEAL

  Mutex = MutexRep.Public BRANDED "Mutex WThread" OBJECT
    mutxSyn : RTSync.T;
    current : T;
    waiting : INTEGER;
  OVERRIDES
    acquire := Acquire;
    release := Release;
  END;

  Condition = BRANDED "Thread.Condition WThread" OBJECT
    condSyn    : RTSync.T;
    first_wait : T;
  END;

  T = BRANDED "Thread.T WThread" OBJECT
    threadSyn  : RTSync.T;
    context    : Context;
    closure    : Closure;
    result     : REFANY;

    (* alerting status *)
    alerted    : BOOLEAN;
    onalert    : BOOLEAN;

    (* linked lists *)
    next_wait  : T;
    next_fork  : T;
    prev_fork  : T;

    (* RTThread emulation *)
    frame      : ADDRESS;                 (* exception handling support *)
    floatState : FloatMode.ThreadState;   (* per-thread floating point state *)
    heapState  : RTHeapRep.ThreadState;   (* per-thread heap state *)
  END;

TYPE
  (* A "recursive" mutex used to lock the heap *)
  RecMutex = UNTRACED ROOT BRANDED "HeapMutex WThread" OBJECT
    recmSyn     : RTSync.T;
    holder      : T;
    inCritical  : INTEGER;
  METHODS
    lock()      := LockRec;
    unlock()    := UnlockRec;
    wait()      := WaitRec;
    broadcast() := BroadcastRec;
  END;



(*------------------------------------------------------------------ Self ---*)

PROCEDURE Self(): T =
(* Return the handle of the calling thread. *)
  VAR t := thread_self();
  BEGIN
    RETURN t;  
  END Self;

(*------------------------------------------------------------ Fork, Join ---*)
PROCEDURE Fork(cl: Closure): T =
(* Return a handle on a newly-created thread executing "cl.apply()". *)
  VAR
    t     : T := NEW(T);
    stack : size_t := defaultStackSize;
    arg   : ADDRESS;
  BEGIN
    (* determine the stack size of this thread *)
    TYPECASE cl OF
    | SizedClosure (scl) => stack := scl.stackSize;
    ELSE (*skip*)
    END;

    t.closure := cl;
    t.frame   := NIL;
    RTSync.Init(t.threadSyn);
    FloatMode.InitThread(t.floatState);

    Debug("WThread.Fork (cl, t)", LOOPHOLE(cl,ADDRESS), LOOPHOLE(t, INTEGER), -1);

    IF LinkNexus(t) = NIL THEN Die(ThisLine(), "WThread.Fork NIL Nexus") END;
    arg := LOOPHOLE(t,ADDRESS);
    WITH r = thread_create(t.context, t.threadSyn, stack, Exec, arg, arg) DO
      IF r < 0 THEN DieI(ThisLine(), r) END;
    END;

    RETURN t;
  END Fork;

PROCEDURE Exec(self: ADDRESS) =
  VAR
    t := LOOPHOLE(self, T);
    result : REFANY;
  BEGIN
    (*Debug("Exec (cl,t)", LOOPHOLE(t.closure,ADDRESS), LOOPHOLE(self,INTEGER), -1);*)
    result := t.closure.apply();

    RTSync.Lock(t.threadSyn);
    t.result := result;
    RTSync.Unlock(t.threadSyn);
  END Exec;


PROCEDURE Join(t: T): REFANY =
(* Wait until "t" has terminated and return its result. It is a
   checked runtime error to call this more than once for any "t". *)
  VAR
    live : Recce := Recce.vigilant;
    self := Self();
    checked := TRUE;
    result : REFANY;
  BEGIN
    (* setup the syn to wait on*)
    RTSync.Lock(t.threadSyn);
    IF t.context.joinSyn # NIL THEN checked := FALSE ELSE t.context.joinSyn := ADR(self.threadSyn) END;
    IF t.context.watch = Recce.joined THEN checked := FALSE; END;
    RTSync.Unlock(t.threadSyn);

    IF NOT checked THEN
      Die(ThisLine(), "attempt to join thread twice")
    END;

    RTSync.Lock(self.threadSyn);
    WHILE live # Recce.joined DO
      live := thread_vigil(t.context);
    END;
    RTSync.Unlock(self.threadSyn);

    result := t.result;
    SeverNexus(t);
    DISPOSE(t); (* Created on Fork *)
    RETURN result;
  END Join;

PROCEDURE AlertJoin(t: T): REFANY RAISES {Alerted} =
(* Like "Join", but if the thread is marked alerted at the time of
   call or sometime during the wait, raise "Alerted". *)
  VAR
    live    : Recce := Recce.vigilant;
    self    := Self();
    checked := TRUE;
    arise   := FALSE;
    result  : REFANY;
  BEGIN
    (* setup the syn to wait on*)
    RTSync.Lock(t.threadSyn);
    IF t.context.joinSyn # NIL THEN checked := FALSE ELSE t.context.joinSyn := ADR(self.threadSyn) END;
    IF t.context.watch = Recce.joined THEN checked := FALSE; END;
    RTSync.Unlock(t.threadSyn);

    IF NOT checked THEN
      Die(ThisLine(), "attempt to join thread twice")
    END;

    (* wait for thread-expiry or alert *)
    RTSync.Lock(self.threadSyn);
    self.onalert := TRUE;
    WHILE live # Recce.joined AND NOT self.alerted DO
      live := thread_vigil(t.context);
    END;

    (* reset the join syn *)
    RTSync.Lock(t.threadSyn);
    t.context.joinSyn := NIL;
    RTSync.Unlock(t.threadSyn);

    (* finished with alerts *)
    IF live # Recce.joined THEN arise := TRUE; END;
    self.alerted := FALSE;
    self.onalert := FALSE;
    RTSync.Unlock(self.threadSyn);

    IF arise THEN
      RAISE Alerted;
    ELSE
      result := t.result;
      SeverNexus(t);
    END;
    RETURN result;
  END AlertJoin;

(*----------------------------------------------------------------- Mutex ---*)
PROCEDURE Acquire(m: Mutex) =
(* Wait until "m" is unlocked and then lock it. *)
  VAR
    self := Self();
    mine := FALSE;
  BEGIN
    (* Pair the lock/unlock *)
    RTSync.Lock(m.mutxSyn);

    (* Is it already free? *)
    IF m.current = NIL THEN
      m.current := self;
      mine      := TRUE;
    ELSE
      INC(m.waiting);
    END;

    (* wait for condition change *)
    WHILE NOT mine DO
      RTSync.Wait(m.mutxSyn);
      IF m.current = NIL THEN
        m.current := self;
        mine      := TRUE;
        DEC(m.waiting);
      END;
    END;

    (* Pair the lock/unlock *)
    RTSync.Unlock(m.mutxSyn);
  END Acquire;

PROCEDURE Release(m: Mutex) =
(* The calling thread must have "m" locked.  Unlocks "m". *)
  VAR
    self  := Self();
    bcast := FALSE;
  BEGIN
    RTSync.Lock(m.mutxSyn);
    <* ASSERT m.current = self*>
    m.current := NIL;
    bcast := m.waiting > 0;
    RTSync.Unlock(m.mutxSyn);

    (* Notify acquire candidates - if any *)
    IF bcast THEN RTSync.Broadcast(m.mutxSyn); END;
  END Release;

(*---------------------------------------- Condition variables and Alerts ---*)
PROCEDURE Wait(m: Mutex; c: Condition) =
(* The calling thread must have "m" locked. Atomically unlocks "m" and
   waits on "c".  Then relocks "m" and returns. *)
  VAR self := Self();
  BEGIN
    (* Validate that I own the lock *)
    RTSync.Lock(m.mutxSyn);
    <*ASSERT m.current = self*>
    RTSync.Unlock(m.mutxSyn);

    (* I already have the mutex exclusively. Locking cond means I
       will have both the mutex and condition exclusively; no other
       thread will have either of them. *)
    RTSync.Lock(c.condSyn);

    (* I have the condition, and only I can wait on it. *)
    (* Unlock the mutex and wait for cond signal/broadcast. *)
    Release(m);
    RTSync.Wait(c.condSyn);

    (* I was notified of a conditon change - relinquish it *)
    RTSync.Unlock(c.condSyn);

    (* Re-acquire the mutex *)
    Acquire(m);
  END Wait;

PROCEDURE AlertWait(m: Mutex; c: Condition) RAISES {Alerted} =
(* Like "Wait", but if the thread is marked alerted at the time of
   call or sometime during the wait, lock "m" and raise "Alerted". *)
  VAR self := Self(); alertMe := FALSE;
  BEGIN
    (* Validate that I own the lock *)
    RTSync.Lock(m.mutxSyn);
    <*ASSERT m.current = self*>
    RTSync.Unlock(m.mutxSyn);

    RTSync.Lock(self.threadSyn);
    IF self.alerted THEN
      (* I was already marked, no wait needed *)
      self.alerted := FALSE;
      alertMe      := TRUE;
    ELSE
      self.onalert := TRUE;

      (* Not marked, add myself to the condition *)
      (*Debug("Alert Link start (condSyn, tid)", ADR(c.condSyn), self.context.tid, -1);*)
      RTSync.Lock(c.condSyn);
      LinkCond(c, self);
      Release(m);
      RTSync.Unlock(c.condSyn);
      (*Debug("Alert Link end (condSyn, tid)", ADR(c.condSyn), self.context.tid, -1);*)

      (* Wait for someone to tell me the condition arose *)
      (* or to alert me - both happen on my own mutex *)
      (*Debug("AlertWait (threadSyn, tid)", ADR(self.threadSyn), self.context.tid, -1);*)
      RTSync.Wait(self.threadSyn);
      (*Debug("AlertWoken (thdSyn, tid)", ADR(self.threadSyn), self.context.tid, -1);*)

      (* Remove myself from the condition *)
      (*Debug("Alert Unlink start (condSyn, tid)", ADR(c.condSyn), self.context.tid, -1);*)
      RTSync.Lock(c.condSyn);
      SeverCond(c, self);
      RTSync.Unlock(c.condSyn);
      (*Debug("Alert Unlink end (condSyn, tid)", ADR(c.condSyn), self.context.tid, -1);*)

      IF self.alerted THEN
        (* I woke up marked *)
        self.alerted := FALSE;
        self.onalert := FALSE;
        alertMe      := TRUE;
      END;

      (* Re-acquire the mutex *)
      Acquire(m);
    END;
    RTSync.Unlock(self.threadSyn);

    IF alertMe THEN
      RAISE Alerted;
    END;
  END AlertWait;

PROCEDURE LinkCond(c: Condition; self : T) =
(* Enjoin thread 't' in the condition alert list; c locked *)
  BEGIN
    (* new head *)
    (* self.next_wait mutex is chained from c.condSyn *)
    self.next_wait  := c.first_wait;
    c.first_wait    := self;
  END LinkCond;

PROCEDURE SeverCond(c: Condition; self : T) =
(* Remove thread 't' from the condition alert list; c locked *)
  VAR pred : T;
  BEGIN
    <* ASSERT c.first_wait # NIL*>
    IF c.first_wait = self THEN
      (* replace the head *)
      c.first_wait := self.next_wait;
    ELSE
      (* replace my predecessor's next with my next *)
      (* pred.next_wait mutex is chained from c.condSyn *)
      pred := c.first_wait;
      WHILE pred.next_wait # self DO pred := pred.next_wait; <*ASSERT pred # NIL*> END;
      pred.next_wait := self.next_wait;
    END;
  END SeverCond;

PROCEDURE Broadcast(c: Condition) =
(* All threads waiting on "c" become eligible to run. *)
  VAR cursor : T; waiter: T; (*first := TRUE;*)
  BEGIN

    (* notify all alert-waiters *)
    RTSync.Lock(c.condSyn);
    cursor := c.first_wait;
    WHILE cursor # NIL DO
      (*
      IF first THEN
        Debug("Broadcast start from (thdSyn, tid)", ADR(cursor.threadSyn), cursor.context.tid, -1);
        first := FALSE;
      ELSIF cursor.next_wait # NIL THEN
        Debug("Broadcast to (threadSyn, tid)", ADR(cursor.threadSyn), cursor.context.tid, -1);
      ELSE
        Debug("Broadcast end at (threadSyn, tid)", ADR(cursor.threadSyn), cursor.context.tid, -1);
      END;
      *)
      waiter := cursor;
      (* next_wait mutex is chained from c.condSyn *)
      cursor := cursor.next_wait;
      RTSync.Signal(waiter.threadSyn);
    END;
    RTSync.Unlock(c.condSyn);

    (* notify threads not onalert*)
    (* condSyn has been unlocked, now! *)
    RTSync.Broadcast(c.condSyn);

  END Broadcast;

PROCEDURE Signal(c: Condition) =
(* One or more threads waiting on "c" become eligible to run. *)
  BEGIN
    (* notify first alert-waiter *)
    RTSync.Lock(c.condSyn);
    IF c.first_wait # NIL THEN
      RTSync.Signal(c.first_wait.threadSyn)
    END;
    RTSync.Unlock(c.condSyn);

    (* notify first thread not onalert *)
    RTSync.Signal(c.condSyn);
  END Signal;

PROCEDURE Alert(t: T) =
(* Mark "t" as an alerted thread. *)
  VAR wake := FALSE;
  BEGIN
    RTSync.Lock(t.threadSyn);
    wake := t.onalert;
    t.alerted := TRUE;
    RTSync.Unlock(t.threadSyn);
    IF wake THEN RTSync.Signal(t.threadSyn); END;
  END Alert;

PROCEDURE TestAlert(): BOOLEAN =
(* If the calling thread has been marked alerted, return "TRUE" and
   unmark it. *)
  VAR t := Self(); a := FALSE;
  BEGIN
    RTSync.Lock(t.threadSyn);
    a := t.alerted;
    IF a THEN
      t.alerted := FALSE;
    END;
    RTSync.Unlock(t.threadSyn);
    RETURN a;
  END TestAlert;

(*----------------------------------------------------------- timed block ---*)
PROCEDURE Pause(n: LONGREAL) =
(* Wait for "n" seconds to elapse. *)
  BEGIN
    RTSync.Resume(n);
  END Pause;

PROCEDURE AlertPause(n: LONGREAL) RAISES {Alerted} =
(* Like "Pause", but if the thread is marked alerted at the time of
   the call or sometime during the wait, raise "Alerted". *)
  VAR t := Self(); alertMe := FALSE;
  BEGIN
    RTSync.Lock(t.threadSyn);
    t.onalert := TRUE;

     (* Only wait if not already alerted *)
    IF NOT t.alerted THEN
      RTSync.Wait(t.threadSyn, n);
    END;

    (* no longer waiting, no need to signal me now *)
    alertMe   := t.alerted;
    t.alerted := FALSE;
    t.onalert := FALSE;
    RTSync.Unlock(t.threadSyn);

    IF alertMe THEN RAISE Alerted; END;
  END AlertPause;

(*------------------------------------------------------- recursive mutex ---*)
(* These methods implement a (reusable) recursive mutex. Use case: heap lock *)

PROCEDURE LockRec (rm : RecMutex) =
  VAR me := Self();
  BEGIN
    IF rm.holder # me THEN
      RTSync.Lock(rm.recmSyn);
      rm.holder := me;
    END;
    INC(rm.inCritical);
  END LockRec;

PROCEDURE UnlockRec (rm : RecMutex) =
  VAR me := Self();
  BEGIN
    <*ASSERT rm.holder=me*>
    DEC(rm.inCritical);
    IF rm.inCritical = 0 THEN
      rm.holder := NIL;
      RTSync.Unlock(rm.recmSyn);
    END;
  END UnlockRec;

PROCEDURE WaitRec (rm : RecMutex) =
  VAR me := Self();
  BEGIN
    <*ASSERT rm.holder=me*>
    DEC(rm.inCritical);
    <*ASSERT rm.inCritical = 0*>
    rm.holder := NIL;
    RTSync.Wait(rm.recmSyn);
    rm.holder := me;
    <*ASSERT rm.inCritical = 0*>
    INC(rm.inCritical);
  END WaitRec;

PROCEDURE BroadcastRec (rm : RecMutex) =
  BEGIN
    RTSync.Broadcast(rm.recmSyn);
  END BroadcastRec;

(*--------------------------------------------------- Stack size controls ---*)

VAR defaultStackSize := 64 * 1024;

PROCEDURE GetDefaultStackSize (): CARDINAL =
  BEGIN
    RETURN defaultStackSize;
  END GetDefaultStackSize;

PROCEDURE MinDefaultStackSize (size: CARDINAL) =
  BEGIN
    defaultStackSize := MAX(defaultStackSize, size);
  END MinDefaultStackSize;

PROCEDURE IncDefaultStackSize (inc: CARDINAL) =
  BEGIN
    INC(defaultStackSize, inc);
  END IncDefaultStackSize;

(*----------------------------------------------------------------- Nexus ---*)
PROCEDURE LinkNexus(t : T) : T =
(* Enjoin thread 't' *)
  VAR head, tail: T;
  BEGIN
    Debug("  LinkNexus begin (tid)", NIL, t.context.tid, -1);
    RTSync.Lock(nexus.forkSyn);
    head := nexus.forkList;

    Debug("  LinkNexus lock (tid)", NIL, t.context.tid, -1);

    (* t.next_fork mutex is chained from forkSyn *)
    IF nexus.forkList = NIL THEN
      (* install the first and only *)
      nexus.forkList := t;
      t.next_fork    := t;
      t.prev_fork    := t;
    ELSE
      (* replace current tail with t *)
      tail := head.prev_fork;

      head.prev_fork := t;
      t.next_fork := head;
      t.prev_fork := tail;
      tail.next_fork := t;
    END;

    RTSync.Unlock(nexus.forkSyn);
    Debug("  LinkNexus end (tid)", NIL, t.context.tid, -1);
    RETURN head;
  END LinkNexus;

PROCEDURE SeverNexus(t : T) =
(* Remove thread 't' *)
  VAR prev, next : T;
  BEGIN
    <* ASSERT nexus.forkList # NIL*>
    Debug("  SeverNexus begin (tid)", NIL, t.context.tid, -1);
    RTSync.Lock(nexus.forkSyn);

    Debug("  SeverNexus lock (tid)", NIL, t.context.tid, -1);

    (* t.next_fork mutex is chained from forkSyn *)
    IF nexus.forkList = t THEN
      <* ASSERT t # t.next_fork*>
      (* set the new head *)
      nexus.forkList := t.next_fork;
    END;

    (* replace the next's and prev's *)
    prev := t.prev_fork;
    next := t.next_fork;
    prev.next_fork := next;
    next.prev_fork := prev;

    RTSync.Unlock(nexus.forkSyn);
    Debug("  SeverNexus end (tid)", NIL, t.context.tid, -1);
  END SeverNexus;


(*--------------------------------------------- garbage collector support ---*)
PROCEDURE MyHeapState(): UNTRACED REF RTHeapRep.ThreadState =
  VAR me := Self();
  BEGIN
    RETURN ADR(me.heapState);
  END MyHeapState;

PROCEDURE SuspendOthers () =
(* Suspend all threads except the caller's. Always bracketed with
   ResumeOthers. *)
  VAR toPark : INTEGER; self := Self(); next : T;
  BEGIN
    (* notify our intent to coordinate a collection *)
    Debug("SuspendOthers begin (tid)", NIL, self.context.tid, -1);

    (*
     * Establish myself as the safePoint owner
     * virtual PROCEDURE acquireSafe
     *)
    RTSync.Lock(nexus.safeSyn);
    Debug("SuspendOthers acquireSafe enter (tid,safePoint)", NIL, self.context.tid, nexus.safePoint);
    RTSync.Lock(nexus.watchSyn); (* I#3 addition*)
    self.context.watch := Recce.relief;
    RTSync.Unlock(nexus.watchSyn); (* I#3 addition *)
    RTSync.Broadcast(nexus.watchSyn); (*I#3 addition, moved from inside safePoint loop *)

    (* Not while another stop is in progress, and not while threads from the previous stop
       are still leaving nthr_park (parked > 0): each of them gets to run before the next
       stop begins. The last thread out of nthr_park broadcasts safeSyn. *)
    WHILE nexus.safePoint = 1 OR nexus.parked > 0 DO
      Debug("SuspendOthers acquireSafe wait (tid,safePoint)", NIL, self.context.tid, nexus.safePoint);
      (* recheck the safePoint every SAFE_WAIT seconds *)
      RTSync.Wait(nexus.safeSyn, -1.0D0);
    END;
    (* safePoint zero; grab it *)
    nexus.safePoint := 1;
    RTSync.Unlock(nexus.safeSyn);
    Debug("SuspendOthers acquireSafe ESTABLISHED (tid,safePoint)", NIL, self.context.tid, nexus.safePoint);


    (*
     * Wait until safePoint established
     * virtual PROCEDURE allSafe
     *)
    Debug("SuspendOthers allSafe watchSyn pre-lock (tid)", NIL, self.context.tid, -1);
    RTSync.Lock(nexus.watchSyn);
    Debug("SuspendOthers allSafe begin (tid)", NIL, self.context.tid, -1);
    LOOP
      (* Count the vigilant threads *)
      toPark := 0;
      next   := self;
      RTSync.Lock(nexus.forkSyn);
      WHILE next.next_fork # self DO
        next := next.next_fork;
        IF next.context.watch = Recce.vigilant THEN INC(toPark); END;
        Debug("SuspendOthers allSafe (watch,tid,nextTid)", LOOPHOLE(ORD(next.context.watch),ADDRESS), self.context.tid, next.context.tid);
      END;
      RTSync.Unlock(nexus.forkSyn);

      (* Are they all here? *)
      IF toPark = 0 THEN
        Debug("SuspendOthers allSafe SUCCESS! (tid,toPark)", NIL, self.context.tid, toPark);
        EXIT;
      ELSE
        Debug("SuspendOthers allSafe wait (tid,toPark)", NIL, self.context.tid, toPark);
        (* recount vigilance every SAFE_WAIT seconds *)
        RTSync.Wait(nexus.watchSyn, -1.0D0);
      END;
    END;
    Debug("SuspendOthers allSafe watchSyn unlock (tid)", NIL, self.context.tid, -1);
    RTSync.Unlock(nexus.watchSyn);

    Debug("SuspendOthers end (tid)", NIL, self.context.tid, -1);
  END SuspendOthers;

PROCEDURE ResumeOthers () =
(* Resume the threads suspended by "SuspendOthers", which always 
  precedes it. *)
  VAR t := Self();
  BEGIN
    (*
     * Release sfaePoint ownership
     * virtual PROCEDURE releaseSafe
     *)
    Debug("ResumeOthers start (tid)", NIL, t.context.tid, -1);
    RTSync.Lock(nexus.safeSyn);
    <* ASSERT t.context.watch = Recce.relief*>
    <* ASSERT nexus.safePoint = 1*>
    nexus.safePoint := 0;
    t.context.watch := Recce.vigilant;
    RTSync.Unlock(nexus.safeSyn);

    (* tell everyone: SuspendOthers (waiting to become the coordinator) and
       nthr_park (waiting for safePoint = 0) both wait on safeSyn *)
    Debug("ResumeOthers RELEASED safePoint (tid)", NIL, t.context.tid, -1);
    RTSync.Broadcast(nexus.safeSyn);   
  END ResumeOthers;

PROCEDURE ProcessStacks (<*UNUSED*> p: PROCEDURE (start, limit: ADDRESS)) =
(* Apply p to each thread stack, with [start..limit) being the limits
   of the stack.  All other threads must be suspended.  ProcessStacks
   exists solely for the garbage collector.  Only called within 
   {SuspendOthers, ResumeOthers} *)
  BEGIN
    (* save the stack pointer to the thread context. Do not delete.
       It sets a limit for PROCEDURE p *)
    thread_stack32();

  END ProcessStacks;

PROCEDURE ProcessEachStack (<*UNUSED*> p: PROCEDURE (start, limit: ADDRESS)) =
(* Apply p to each thread stack, with [start..limit) being the limits
   of the stack.  Each thread is suspended individually.  ProcessEachStack
   exists solely for the garbage collector.  *)
  BEGIN
    
  END ProcessEachStack;


(*------------------------------------------------ floating point support ---*)

PROCEDURE MyFPState (): UNTRACED REF FloatMode.ThreadState =
  VAR me := Self();
  BEGIN
    RETURN ADR(me.floatState);
  END MyFPState;

(*---------------------------------------------------- exception delivery ---*)

PROCEDURE GetCurrentHandlers(): ADDRESS =
  VAR me := Self();
  BEGIN
    RETURN me.frame;    
  END GetCurrentHandlers;

PROCEDURE SetCurrentHandlers(h: ADDRESS) =
  VAR me := Self();
  BEGIN
    me.frame := h;
  END SetCurrentHandlers;

(*--------------------------------------------------------- initialisation --*)
(* The following RTThread procedures are invoked from the RTLinker.InitRuntime
   and from main() produced by MxGen.GenerateMain, respectively. *)
PROCEDURE Init() =
  BEGIN
    (* ABI sanity check *)
    thread_match(BYTESIZE(RTSync.T), BYTESIZE(Context), BYTESIZE(Nexus));

    (* safepoint coordination nexus *)
    nexus.safePoint  := 0;
    nexus.parked     := 0;
    nexus.forkList   := NIL;
    RTSync.Init(nexus.safeSyn);
    RTSync.Init(nexus.watchSyn);
    RTSync.Init(nexus.forkSyn);

    (* heap and nexus lock are special *)
    heapMutex := NEW(RecMutex);

  END Init;

PROCEDURE InitialThread(binder : RT0.Binder) =
(* This procedure spawns the main process thread. The routine is spawned off
   as an actual thread so as not to be treat memory and stacks differently
   from any actually Forked threads. Return from this procedure occurs upon
   the routine's return. Emulates RTLinker.AddUnit(Main_M3) of the startup.
   This procedure is a condensed Fork/Join. *)
  VAR
    t    : T;
    self : T;
    watch : Recce := Recce.vigilant;
    routine : Routine;
    arg     : ADDRESS;
  BEGIN
    (* the child I am spawning *)
    t       := NEW(T);
    t.frame := NIL;
    RTSync.Init(t.threadSyn);
    FloatMode.InitThread(t.floatState);

    (* to make this work, make myself the default 'thread' *)
    self       := NEW(T);
    self.frame := NIL;
    RTSync.Init(self.threadSyn);
    FloatMode.InitThread(self.floatState);
    thread_default(self.context, self.threadSyn, LOOPHOLE(self, ADDRESS));

    Debug("InitialThread START (self)", LOOPHOLE(self, ADDRESS), -1, -1);

    (* Fork a call to RTLinker.AddUnit(binder) *)
    routine := LOOPHOLE(RTLinker.AddUnit, Routine);
    arg     := LOOPHOLE(binder, ADDRESS);
    IF LinkNexus(t) # NIL THEN Die(ThisLine(), "WThread.InitialThread non-NIL Nexus") END;
    WITH r = thread_create(t.context, t.threadSyn, defaultStackSize, routine, arg, LOOPHOLE(t, ADDRESS)) DO
      IF r < 0 THEN DieI(ThisLine(), r) END;
    END;

    (* Join the child back to my 'self' thread *)
    (* self is not linked to the nexus, it "poses" as a thread in order to
       join back to the program main thread: binder. It doesn't park *)
    RTSync.Lock(t.threadSyn);
    t.context.joinSyn := ADR(self.threadSyn);
    RTSync.Unlock(t.threadSyn);

    RTSync.Lock(self.threadSyn);
    WHILE watch # Recce.joined DO
      watch := thread_vigil(t.context);
    END;
    RTSync.Unlock(self.threadSyn);

    (*Debug("InitialThread STOP (self)", LOOPHOLE(self, ADDRESS), -1, -1);*)

  END InitialThread;

(* RTThread *)
PROCEDURE AtForkPrepareOutsideFork() =
  BEGIN
    (* RTProcess Fork side-effects *)
  END AtForkPrepareOutsideFork;


(*------------------------------------------------------------- collector ---*)
(* These procedures provide synchronization primitives for the allocator
   and collector. *)


VAR heapMutex : RecMutex;

PROCEDURE LockHeap () =
  BEGIN
    heapMutex.lock();
  END LockHeap;

PROCEDURE UnlockHeap () =
  BEGIN
    heapMutex.unlock();
  END UnlockHeap;

PROCEDURE WaitHeap () =
  BEGIN
    heapMutex.wait();
  END WaitHeap;

PROCEDURE BroadcastHeap () =
  BEGIN
    heapMutex.broadcast();
  END BroadcastHeap;

(*------------------------------------------------------------- Scheduler ---*)
PROCEDURE Yield () =
  BEGIN
    (* TODO: invoke thread_park? *)
  END Yield;

PROCEDURE DisableSwitching () =
  BEGIN
    (* no user-level thread switching *)
  END DisableSwitching;

PROCEDURE EnableSwitching () =
  BEGIN
    (* no user-level thread switching *)
  END EnableSwitching;

(*------------------------------------------------------------ Exceptions ---*)
(* Copied from PTHREADS - consider no-op instead *)
(*RTHooks.PushEFrame*)
PROCEDURE PushEFrame (frame: ADDRESS) =
  TYPE Frame = UNTRACED REF RECORD next: ADDRESS END;
  VAR
    me := thread_self();
    f: Frame := frame;
  BEGIN
    f.next := me.frame;
    me.frame := f;
  END PushEFrame;

(*RTHooks.PopEFrame*)
PROCEDURE PopEFrame (frame: ADDRESS) =
  VAR me := thread_self();
  BEGIN
    me.frame := frame;
  END PopEFrame;

(*---------------------------------------------------------------- errors ---*)
PROCEDURE Die (lineno: INTEGER; msg: TEXT) =
  BEGIN
    RTError.Msg (ThisFile(), lineno, "WThread error: ", msg);
  END Die;

PROCEDURE DieI (lineno: INTEGER; i: INTEGER) =
  BEGIN
    RTError.MsgI (ThisFile(), lineno, "WThread error: ", i);
  END DieI;

(*----------------------------------------------------------------- Debug ---*)
PROCEDURE Debug(txt : TEXT; addr : ADDRESS; p1 : INTEGER; p2 : INTEGER) =
  BEGIN
    thread_print(M3toC.FlatTtoS(txt), addr, p1, p2);
  END Debug;

BEGIN
END WThread.
