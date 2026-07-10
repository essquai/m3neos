(* Copyright (C) 2026 Sunil Khare. All rights reserved. *)

(*
 * RTSync.i3
 *
 * M3 neos synchronisation module.
 * 
 * Design notes:
 *   - Fair (strict FIFO) locking via a ticket-lock algorithm. No thread can
 *     starve regardless of thread count vs. core count.
 *   - Fast path for these locks treat the record as atomic 32-bit unsigneds.
 *   - slower path uses wait32/wake32 depending upon implementation architecture
 *     available primitives; otherwise lock logic is identical
 *   - Avoids other runtime dependenices, making it suitable for freestanding OR
 *     minimal runtime environments (e.g. wasm32-unknown-unknown with the 
 *     threads+atomics proposal enabled, run under Wasmer/WAMR).
 *
 * The ~100 lines of C could feasibly be ported to Modula-3. Further study
 * required.
 *)

INTERFACE RTSync;

TYPE
  uint32_t = BITS 32 FOR [ 0 .. 16_FFFFFFFF ];
  T = RECORD
    next_ticket  : uint32_t;
    next_serving : uint32_t;
  END;


<* EXTERNAL "nsyn_init"*>
PROCEDURE Init(VAR lock: T);
(* Initialise a lock prior to use *)

<*EXTERNAL "nsyn_lock"*>
PROCEDURE Lock(VAR lock: T);
(* Acquire the lock. Blocks (parks the calling thread) until it is this
   threads turn. Fair: tickets are served strictly in issue order. *)


<*EXTERNAL "nsyn_unlock"*>
PROCEDURE Unlock(VAR lock: T);
(* Release the lock. Must be called by the same thread that acquired it,
   and must not be reached via longjmp — see header discipline notes above. *)


<*EXTERNAL "nsyn_trylock"*>
PROCEDURE TryLock(VAR lock: T) : INTEGER;
(* Non-blocking attempt to acquire the lock. Returns 1 on success (caller now
   holds the lock and must eventually call nsyn_unlock), 0 if the lock was
   already held by someone else. Does not participate in / consume a ticket
   on failure, so it cannot cause starvation of waiting threads. *)

END RTSync.
