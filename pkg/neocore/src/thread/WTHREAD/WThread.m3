(* Copyright (C) 2026 Sunil Khare. All righs reserved. *)

UNSAFE MODULE WThread EXPORTS Thread, RTThread, RTOS, Scheduler, RTHooks, WThread;

IMPORT FloatMode, MutexRep, RTHeapRep;
IMPORT RT0, RTLinker;
IMPORT RTError;
IMPORT RTSync;
IMPORT M3toC;
FROM   Cstddef  IMPORT size_t;
FROM   Compiler IMPORT ThisFile, ThisLine;

TYPE
  Triple = RECORD
    t         : T;
    context   : Context;
    axis      : Axis;

    busy      : BOOLEAN;
    next_free : INTEGER;
  END;


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
    axis       : UNTRACED REF Axis;
    context    : UNTRACED REF Context;

    closure    : Closure;
    result     : REFANY;

    (* alerting status *)
    alerted    : BOOLEAN;
    onalert    : BOOLEAN;

    (* linked lists *)
    next_wait  : T;
  END;

TYPE
  (* A "recursive" mutex used to lock the heap *)
  RecMutex = UNTRACED ROOT BRANDED "HeapMutex WThread" OBJECT
    recmSyn     : RTSync.T;
    holder      : UNTRACED REF Axis;
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
  VAR t := thread_context();
  BEGIN
    RETURN triple[t.axis.slot].t;  
  END Self;

(*------------------------------------------------------------ Fork, Join ---*)
PROCEDURE Fork(cl: Closure): T =
(* Return a handle on a newly-created thread executing "cl.apply()". *)
  VAR
    slot  := AssignTriple();
    t     : T := NEW(T);
    stack : size_t := defaultStackSize;
    arg   : ADDRESS;
  BEGIN
    IF slot < 0 THEN Die(ThisLine(), "thread slots exhausted"); END;

    (* determine the stack size of this thread *)
    TYPECASE cl OF
    | SizedClosure (scl) => stack := scl.stackSize;
    ELSE (*skip*)
    END;

    triple[slot].t := t;
    LinkThread(t, ADR(triple[slot].axis), ADR(triple[slot].context));
    t.closure      := cl;

    Debug("WThread.Fork (cl, t)", LOOPHOLE(cl,ADDRESS), LOOPHOLE(t, INTEGER), -1);

    IF LinkNexus(t.axis) = NIL THEN Die(ThisLine(), "Fork NIL Nexus") END;
    arg := t.axis;
    WITH r = thread_create(t.context, t.axis.threadSyn, stack, Exec, arg, arg) DO
      IF r < 0 THEN DieI(ThisLine(), r) END;
    END;

    RETURN t;
  END Fork;

PROCEDURE Exec(self: ADDRESS) =
  VAR
    axis := LOOPHOLE(self, UNTRACED REF Axis);
    slot := axis.slot;
    result : REFANY;
  BEGIN
    (*Debug("Exec (cl,t)", LOOPHOLE(t.closure,ADDRESS), LOOPHOLE(self,INTEGER), -1);*)
    result := triple[slot].t.closure.apply();

    thread_lock(axis.threadSyn);
    triple[slot].t.result := result;
    RTSync.Unlock(axis.threadSyn);

    (* flush thread heap, make thread eligible for GC *)
    RTHeapRep.FlushThreadState(axis.heapState);
    triple[slot].t := NIL;
  END Exec;


PROCEDURE Join(t: T): REFANY =
(* Wait until "t" has terminated and return its result. It is a
   checked runtime error to call this more than once for any "t". *)
  VAR
    live : Recce := Recce.vigilant;
    self := Self();
    checked := TRUE;
    result : REFANY;
    slot := t.axis.slot;
  BEGIN
    (* setup the syn to wait on*)
    thread_lock(t.axis.threadSyn);
    IF t.context.joinSyn # NIL THEN checked := FALSE ELSE t.context.joinSyn := ADR(self.axis.threadSyn) END;
    IF t.context.watch = Recce.joined THEN checked := FALSE; END;
    RTSync.Unlock(t.axis.threadSyn);

    IF NOT checked THEN
      Die(ThisLine(), "attempt to join thread twice")
    END;

    thread_lock(self.axis.threadSyn);
    WHILE live # Recce.joined DO
      live := thread_vigil(t.context);
    END;
    RTSync.Unlock(self.axis.threadSyn);

    result := t.result;
    SeverNexus(t.axis);
    t.axis := NIL;
    t.context := NIL;
    FreeTriple(slot); (* Release the slot *)
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
    slot := t.axis.slot;
  BEGIN
    (* setup the syn to wait on*)
    thread_lock(t.axis.threadSyn);
    IF t.context.joinSyn # NIL THEN checked := FALSE ELSE t.context.joinSyn := ADR(self.axis.threadSyn) END;
    IF t.context.watch = Recce.joined THEN checked := FALSE; END;
    RTSync.Unlock(t.axis.threadSyn);

    IF NOT checked THEN
      Die(ThisLine(), "attempt to join thread twice")
    END;

    (* wait for thread-expiry or alert *)
    thread_lock(self.axis.threadSyn);
    self.onalert := TRUE;
    WHILE live # Recce.joined AND NOT self.alerted DO
      live := thread_vigil(t.context);
    END;

    (* reset the join syn *)
    thread_lock(t.axis.threadSyn);
    t.context.joinSyn := NIL;
    RTSync.Unlock(t.axis.threadSyn);

    (* finished with alerts *)
    IF live # Recce.joined THEN arise := TRUE; END;
    self.alerted := FALSE;
    self.onalert := FALSE;
    RTSync.Unlock(self.axis.threadSyn);

    IF arise THEN
      RAISE Alerted;
    ELSE
      result := t.result;
      SeverNexus(t.axis);
      t.axis := NIL;
      t.context := NIL;
      FreeTriple(slot); (* Release the slot *)
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
    thread_lock(m.mutxSyn);

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
    thread_lock(m.mutxSyn);
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
    thread_lock(m.mutxSyn);
    <*ASSERT m.current = self*>
    RTSync.Unlock(m.mutxSyn);

    (* I already have the mutex exclusively. Locking cond means I
       will have both the mutex and condition exclusively; no other
       thread will have either of them. *)
    thread_lock(c.condSyn);

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
    thread_lock(m.mutxSyn);
    <*ASSERT m.current = self*>
    RTSync.Unlock(m.mutxSyn);

    thread_lock(self.axis.threadSyn);
    IF self.alerted THEN
      (* I was already marked, no wait needed *)
      self.alerted := FALSE;
      alertMe      := TRUE;
    ELSE
      self.onalert := TRUE;

      (* Not marked, add myself to the condition *)
      (*Debug("Alert Link start (condSyn, tid)", ADR(c.condSyn), self.context.tid, -1);*)
      thread_lock(c.condSyn);
      LinkCond(c, self);
      Release(m);
      RTSync.Unlock(c.condSyn);
      (*Debug("Alert Link end (condSyn, tid)", ADR(c.condSyn), self.context.tid, -1);*)

      (* Wait for someone to tell me the condition arose *)
      (* or to alert me - both happen on my own mutex *)
      (*Debug("AlertWait (axis.threadSyn, tid)", ADR(self.axis.threadSyn), self.context.tid, -1);*)
      RTSync.Wait(self.axis.threadSyn);
      (*Debug("AlertWoken (thdSyn, tid)", ADR(self.axis.threadSyn), self.context.tid, -1);*)

      (* Remove myself from the condition *)
      (*Debug("Alert Unlink start (condSyn, tid)", ADR(c.condSyn), self.context.tid, -1);*)
      thread_lock(c.condSyn);
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
    RTSync.Unlock(self.axis.threadSyn);

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
    thread_lock(c.condSyn);
    cursor := c.first_wait;
    WHILE cursor # NIL DO
      (*
      IF first THEN
        Debug("Broadcast start from (thdSyn, tid)", ADR(cursor.axis.threadSyn), cursor.context.tid, -1);
        first := FALSE;
      ELSIF cursor.next_wait # NIL THEN
        Debug("Broadcast to (axis.threadSyn, tid)", ADR(cursor.axis.threadSyn), cursor.context.tid, -1);
      ELSE
        Debug("Broadcast end at (axis.threadSyn, tid)", ADR(cursor.axis.threadSyn), cursor.context.tid, -1);
      END;
      *)
      waiter := cursor;
      (* next_wait mutex is chained from c.condSyn *)
      cursor := cursor.next_wait;
      RTSync.Signal(waiter.axis.threadSyn);
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
    thread_lock(c.condSyn);
    IF c.first_wait # NIL THEN
      RTSync.Signal(c.first_wait.axis.threadSyn)
    END;
    RTSync.Unlock(c.condSyn);

    (* notify first thread not onalert *)
    RTSync.Signal(c.condSyn);
  END Signal;

PROCEDURE Alert(t: T) =
(* Mark "t" as an alerted thread. *)
  VAR wake := FALSE;
  BEGIN
    thread_lock(t.axis.threadSyn);
    wake := t.onalert;
    t.alerted := TRUE;
    RTSync.Unlock(t.axis.threadSyn);
    IF wake THEN RTSync.Signal(t.axis.threadSyn); END;
  END Alert;

PROCEDURE TestAlert(): BOOLEAN =
(* If the calling thread has been marked alerted, return "TRUE" and
   unmark it. *)
  VAR t := Self(); a := FALSE;
  BEGIN
    thread_lock(t.axis.threadSyn);
    a := t.alerted;
    IF a THEN
      t.alerted := FALSE;
    END;
    RTSync.Unlock(t.axis.threadSyn);
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
    thread_lock(t.axis.threadSyn);
    t.onalert := TRUE;

     (* Only wait if not already alerted *)
    IF NOT t.alerted THEN
      RTSync.Wait(t.axis.threadSyn, n);
    END;

    (* no longer waiting, no need to signal me now *)
    alertMe   := t.alerted;
    t.alerted := FALSE;
    t.onalert := FALSE;
    RTSync.Unlock(t.axis.threadSyn);

    IF alertMe THEN RAISE Alerted; END;
  END AlertPause;

(*------------------------------------------------------- recursive mutex ---*)
(* These methods implement a (reusable) recursive mutex. Use case: heap lock *)

PROCEDURE LockRec (rm : RecMutex) =
  VAR me := thread_context();
  BEGIN
    (* This thread_lock invocation sets noPark TRUE. SuspendOthers is only
       called with the heap lock held: Colect, StartCollection, AllocTraced,
       and RTHeapStats. This thread_lock is not intended to park, but
       may raise an axceptional circumstance we want to catch. *)
    IF rm.holder # me.axis THEN
      thread_lock(rm.recmSyn, noPark := TRUE);
      rm.holder := me.axis;
    END;
    INC(rm.inCritical);
  END LockRec;

PROCEDURE UnlockRec (rm : RecMutex) =
  VAR me := thread_context();
  BEGIN
    <*ASSERT rm.holder=me.axis*>
    DEC(rm.inCritical);
    IF rm.inCritical = 0 THEN
      rm.holder := NIL;
      RTSync.Unlock(rm.recmSyn);
    END;
  END UnlockRec;

PROCEDURE WaitRec (rm : RecMutex) =
  VAR me := thread_context();
  BEGIN
    <*ASSERT rm.holder=me.axis*>
    DEC(rm.inCritical);
    <*ASSERT rm.inCritical = 0*>
    rm.holder := NIL;
    RTSync.Wait(rm.recmSyn);
    rm.holder := me.axis;
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
PROCEDURE LinkNexus(t : UNTRACED REF Axis) : ADDRESS =
(* Enjoin thread 't' *)
  VAR head, tail: UNTRACED REF Axis;
  BEGIN
    Debug("  LinkNexus begin (tid)", NIL, triple[t.slot].context.tid, -1);

    RTSync.Lock(nexus.forkSyn);
    head := nexus.forkList;

    (* t.next_axis mutex is chained from forkSyn *)
    IF nexus.forkList = NIL THEN
      (* install the first and only *)
      nexus.forkList := t;
      t.next_axis    := t;
      t.prev_axis    := t;
    ELSE
      (* replace current tail with t *)
      tail := head.prev_axis;

      head.prev_axis := t;
      t.next_axis := head;
      t.prev_axis := tail;
      tail.next_axis := t;
    END;

    RTSync.Unlock(nexus.forkSyn);

    Debug("  LinkNexus end (tid)", NIL, triple[t.slot].context.tid, -1);
    RETURN head;
  END LinkNexus;

PROCEDURE SeverNexus(t : UNTRACED REF Axis) =
(* Remove thread 't' *)
  VAR prev, next : UNTRACED REF Axis;
  BEGIN
    <* ASSERT nexus.forkList # NIL*>
    Debug("  SeverNexus begin (tid)", NIL, triple[t.slot].context.tid, -1);
    RTSync.Lock(nexus.forkSyn);

    (* t.next_axis mutex is chained from forkSyn *)
    IF nexus.forkList = t THEN
      <* ASSERT t # t.next_axis*>
      (* set the new head *)
      nexus.forkList := t.next_axis;
    END;

    (* replace the next's and prev's *)
    prev := t.prev_axis;
    next := t.next_axis;
    prev.next_axis := next;
    next.prev_axis := prev;

    RTSync.Unlock(nexus.forkSyn);
    Debug("  SeverNexus end (tid)", NIL, triple[t.slot].context.tid, -1);
  END SeverNexus;

CONST TRIPLES=100;
VAR
  triple   : ARRAY [0..TRIPLES-1] OF Triple;
  tripFree : INTEGER;
  tripSyn  : RTSync.T;

PROCEDURE InitTriples() =
  BEGIN
    (* linked-list assembly *)
    RTSync.Init(tripSyn);
    tripFree := 0;
    FOR i := 0 TO TRIPLES - 2 DO
      triple[i].next_free := i + 1;
    END;
    triple[TRIPLES-1].next_free := -1;
  END InitTriples;

PROCEDURE AssignTriple() : INTEGER =
  VAR slot : INTEGER;
  BEGIN
    (* Assign *)
    RTSync.Lock(tripSyn);
    slot := tripFree;
    IF slot >= 0 THEN
      <* ASSERT NOT triple[slot].busy *>
      triple[slot].busy := TRUE;
      tripFree := triple[slot].next_free;
    END;
    RTSync.Unlock(tripSyn);

    (* Initialise *)
    IF slot >= 0 THEN
      triple[slot].t := NIL; (* redundant *)
      RTSync.Init(triple[slot].axis.threadSyn);
      FloatMode.InitThread(triple[slot].axis.floatState);
      triple[slot].axis.heapState := RTHeapRep.ThreadState {};
      triple[slot].axis.frame := NIL;
      triple[slot].axis.slot := slot;
      triple[slot].axis.next_axis := NIL;
      triple[slot].axis.prev_axis := NIL;
      (* for triple.context init, see thread_create *)
    END;

    RETURN slot;
  END AssignTriple;

PROCEDURE FreeTriple(slot : INTEGER) = 
  BEGIN
    <*ASSERT triple[slot].busy *>
    RTSync.Lock(tripSyn);
    triple[slot].next_free := tripFree;
    triple[slot].busy := FALSE;
    tripFree := slot;
    RTSync.Unlock(tripSyn);
  END FreeTriple;

(*--------------------------------------------- garbage collector support ---*)
PROCEDURE MyHeapState(): UNTRACED REF RTHeapRep.ThreadState =
  VAR me := thread_context();
  BEGIN
    RETURN ADR(me.axis.heapState);
  END MyHeapState;

PROCEDURE SuspendOthers () =
(* Suspend all threads except the caller's. Always bracketed with
   ResumeOthers. *)
  VAR toPark : INTEGER; ctxt := thread_context(); next : UNTRACED REF Axis;
  BEGIN
    (* notify our intent to coordinate a collection *)
    Debug("SuspendOthers begin (tid)", NIL, ctxt.tid, -1);

    (*
     * Establish myself as the safePoint owner
     * virtual PROCEDURE acquireSafe
     *)
    RTSync.Lock(nexus.safeSyn);
    Debug("SuspendOthers acquireSafe enter (tid,safePoint)", NIL, ctxt.tid, nexus.safePoint);
    RTSync.Lock(nexus.watchSyn); (* I#3 addition*)
    ctxt.watch := Recce.relief;
    RTSync.Unlock(nexus.watchSyn); (* I#3 addition *)
    RTSync.Broadcast(nexus.watchSyn); (*I#3 addition, moved from inside safePoint loop *)

    (* Not while another stop is in progress, and not while threads from the previous stop
       are still leaving nthr_park (parked > 0): each of them gets to run before the next
       stop begins. The last thread out of nthr_park broadcasts safeSyn. *)
    WHILE nexus.safePoint = 1 OR nexus.parked > 0 DO
      Debug("SuspendOthers acquireSafe wait (tid,safePoint)", NIL, ctxt.tid, nexus.safePoint);
      (* recheck the safePoint every SAFE_WAIT seconds *)
      RTSync.Wait(nexus.safeSyn, -1.0D0);
    END;
    (* safePoint zero; grab it *)
    nexus.safePoint := 1;
    RTSync.Unlock(nexus.safeSyn);
    Debug("SuspendOthers acquireSafe ESTABLISHED (tid,safePoint)", NIL, ctxt.tid, nexus.safePoint);


    (*
     * Wait until safePoint established
     * virtual PROCEDURE allSafe
     *)
    Debug("SuspendOthers allSafe watchSyn pre-lock (tid)", NIL, ctxt.tid, -1);
    RTSync.Lock(nexus.watchSyn);
    Debug("SuspendOthers allSafe begin (tid)", NIL, ctxt.tid, -1);
    LOOP
      (* Count the vigilant threads *)
      toPark := 0;
      next   := ctxt.axis;
      RTSync.Lock(nexus.forkSyn);
      WHILE next.next_axis # ctxt.axis DO
        next := next.next_axis;
        IF triple[next.slot].context.watch = Recce.vigilant THEN INC(toPark); END;
        Debug("SuspendOthers allSafe (watch,tid,nextTid)", LOOPHOLE(ORD(triple[next.slot].context.watch),ADDRESS), ctxt.tid, triple[next.slot].context.tid);
      END;
      RTSync.Unlock(nexus.forkSyn);

      (* Are they all here? *)
      IF toPark = 0 THEN
        Debug("SuspendOthers allSafe SUCCESS! (tid,toPark)", NIL, ctxt.tid, toPark);
        EXIT;
      ELSE
        Debug("SuspendOthers allSafe wait (tid,toPark)", NIL, ctxt.tid, toPark);
        (* recount vigilance every SAFE_WAIT seconds *)
        RTSync.Wait(nexus.watchSyn, -1.0D0);
      END;
    END;
    Debug("SuspendOthers allSafe watchSyn unlock (tid)", NIL, ctxt.tid, -1);
    RTSync.Unlock(nexus.watchSyn);

    Debug("SuspendOthers end (tid)", NIL, ctxt.tid, -1);
  END SuspendOthers;

PROCEDURE ResumeOthers () =
(* Resume the threads suspended by "SuspendOthers", which always 
  precedes it. *)
  VAR ctxt := thread_context();
  BEGIN
    (*
     * Release sfaePoint ownership
     * virtual PROCEDURE releaseSafe
     *)
    Debug("ResumeOthers start (tid)", NIL, ctxt.tid, -1);
    RTSync.Lock(nexus.safeSyn);
    <* ASSERT ctxt.watch = Recce.relief*>
    <* ASSERT nexus.safePoint = 1*>
    nexus.safePoint := 0;
    ctxt.watch := Recce.vigilant;
    RTSync.Unlock(nexus.safeSyn);

    (* tell everyone: SuspendOthers (waiting to become the coordinator) and
       nthr_park (waiting for safePoint = 0) both wait on safeSyn *)
    Debug("ResumeOthers RELEASED safePoint (tid)", NIL, ctxt.tid, -1);
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
  VAR me := thread_context();
  BEGIN
    RETURN ADR(me.axis.floatState);
  END MyFPState;

(*---------------------------------------------------- exception delivery ---*)

PROCEDURE GetCurrentHandlers(): ADDRESS =
  VAR me := thread_context();
  BEGIN
    RETURN me.axis.frame;    
  END GetCurrentHandlers;

PROCEDURE SetCurrentHandlers(h: ADDRESS) =
  VAR me := thread_context();
  BEGIN
    me.axis.frame := h;
  END SetCurrentHandlers;

(*--------------------------------------------------------- initialisation --*)
(* The following RTThread procedures are invoked from the RTLinker.InitRuntime
   and from main() produced by MxGen.GenerateMain, respectively. *)
VAR defaultT : T := NIL;

PROCEDURE Init() =
  VAR
    slot : INTEGER;
    ctxt : UNTRACED REF Context;
    axis : UNTRACED REF Axis;
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

    (* Establish triples *)
    InitTriples();
    slot := AssignTriple();
    IF slot # 0 THEN Die(ThisLine(), "initial slot not 0!\n"); END;
    ctxt := ADR(triple[0].context);
    axis := ADR(triple[0].axis);
    IF LinkNexus(axis) # NIL THEN Die(ThisLine(), "Init non-NIL Nexus") END;


    (* make the default thread - thread_default MUST come first! *)
    (* NEW invokes GC *)
    thread_default(ctxt, axis.threadSyn, axis);
    defaultT := NEW(T);
    LinkThread(defaultT, axis, ctxt);
    triple[0].t := defaultT;

  END Init;

PROCEDURE InitialThread(binder : RT0.Binder) =
(* This procedure spawns the main process thread. The routine is spawned off
   as an actual thread so as not to be treat memory and stacks differently
   from any actually Forked threads. Return from this procedure occurs upon
   the routine's return. Emulates RTLinker.AddUnit(Main_M3) of the startup.
   This procedure is a condensed Fork/Join. *)
  VAR
    self    : INTEGER := 0; (* alias for default slot index *)
    watch   : Recce := Recce.vigilant;
    routine : Routine;
    arg     : ADDRESS;
    t       : T;
    slot    := AssignTriple(); (* for spawned main thread *)
    ctxt    : UNTRACED REF Context;
    axis    : UNTRACED REF Axis;
  BEGIN
    IF slot < 0 THEN Die(ThisLine(), "initial thread slot exhausted"); END;

    (* the child I am spawning *)
    ctxt := ADR(triple[slot].context);
    axis := ADR(triple[slot].axis);
    t    := NEW(T);
    triple[slot].t := t;
    LinkThread(t, axis, ctxt);


    Debug("InitialThread START (self)", LOOPHOLE(self, ADDRESS), -1, -1);

    (* Fork a call to RTLinker.AddUnit(binder) *)
    routine := LOOPHOLE(RTLinker.AddUnit, Routine);
    arg     := LOOPHOLE(binder, ADDRESS);
    IF LinkNexus(t.axis) = NIL THEN Die(ThisLine(), "WThread.InitialThread NIL Nexus") END;
    WITH r = thread_create(t.context, t.axis.threadSyn, defaultStackSize, routine, arg, t.axis) DO
      IF r < 0 THEN DieI(ThisLine(), r) END;
    END;

    (* Join the child back to my 'self' thread *)
    (* self is a true thread now, created in Init() *)
    thread_lock(t.axis.threadSyn);
    t.context.joinSyn := ADR(triple[self].t.axis.threadSyn);
    RTSync.Unlock(t.axis.threadSyn);

    thread_lock(triple[self].t.axis.threadSyn);
    WHILE watch # Recce.joined DO
      watch := thread_vigil(t.context);
    END;
    RTSync.Unlock(triple[self].t.axis.threadSyn);

    (*Debug("InitialThread STOP (self)", LOOPHOLE(self, ADDRESS), -1, -1);*)

  END InitialThread;

PROCEDURE LinkThread(t : T; axis: UNTRACED REF Axis; ctxt: UNTRACED REF Context) =
  BEGIN
    t.axis := axis;
    t.context := ctxt;
    t.closure := NIL;
    t.result := NIL;
    t.alerted := FALSE;
    t.onalert := FALSE;
    t.next_wait := NIL;
  END LinkThread;

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
    me := thread_context();
    f: Frame := frame;
  BEGIN
    f.next := me.axis.frame;
    me.axis.frame := f;
  END PushEFrame;

(*RTHooks.PopEFrame*)
PROCEDURE PopEFrame (frame: ADDRESS) =
  VAR me := thread_context();
  BEGIN
    me.axis.frame := frame;
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
