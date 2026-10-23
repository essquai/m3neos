/* Copyright (C) 2026 Sunil Khare. All rights reserved. 
 *
 * Neos sync  — portable ticket-lock mutual exclusion for x86_64 and wasm32.
 *
 * Design notes:
 *   - Fair (strict FIFO) locking via a ticket-lock algorithm. No thread can
 *     starve regardless of thread count vs. core count.
 *   - Built entirely on C11 <stdatomic.h> plus two small architecture-specific
 *     "wait / wake" primitives (arch_wait32 / arch_wake32), so the lock logic
 *     itself is identical across targets.
 *   - No dependency on pthreads or any libc threading library. Suitable for
 *     freestanding / minimal-runtime environments (e.g. wasm32-unknown-unknown
 *     with the threads+atomics proposal enabled, run under Wasmer/WAMR).
 *
 * IMPORTANT — Modula-3 / setjmp-longjmp runtime discipline:
 *   The region between nsyn_lock() and nsyn_unlock() MUST NOT be exited
 *   via longjmp/siglongjmp (e.g. as part of a Modula-3 RAISE/unwind). Any
 *   code that can raise an exception (including out-of-memory) must do so
 *   strictly AFTER nsyn_unlock() has been called. Violating this abandons
 *   the lock and permanently blocks every thread queued behind it.
 *
 *   ACTION ITEM (tracked separately): confirm whether the Modula-3 runtime
 *   maps hardware signals (SIGSEGV/SIGFPE/etc.) to language exceptions via
 *   an async signal handler. If so, signals that can trigger such a mapping
 *   must be blocked (pthread_sigmask / sigprocmask) for the duration of any
 *   nsyn-protected critical section, or the same abandonment risk applies
 *   asynchronously even when no code inside the section explicitly raises.
 */

#ifndef NSYN_H
#define NSYN_H

#include <stdint.h>
#include <stdatomic.h>

#ifdef __cplusplus
extern "C" {
#endif

/* A fair, FIFO ticket lock. Zero-initialize (or use NSYN_LOCK_INIT) before use. */
typedef struct {
    _Atomic uint32_t next_ticket;   /* next ticket to hand out */
    _Atomic uint32_t now_serving;   /* ticket currently allowed to proceed */
    _Atomic uint32_t cond_seq;      /* bumped on every signal/broadcast */
} nsyn_lock_t;

#define NSYN_LOCK_INIT { 0, 0, 0 }

/* Initialize a lock at runtime (equivalent to NSYN_LOCK_INIT). */
void nsyn_init(nsyn_lock_t *l);

/* Acquire the lock. Blocks (parks the calling thread) until it is this
 * thread's turn. Fair: tickets are served strictly in issue order. */
void nsyn_lock(nsyn_lock_t *l);

/* Await a lock condition. The lock must have first been acquired. This
 * function will wait until something else signals a change in condition. */
/* Deprecated. Replaced by nthr_wait */
/* void nsyn_wait(nsyn_lock_t *l, double timeout); */

/* Signal a lock condition. Ensure the state has changed and committed.
 * This function informs one observer the lock condition has changed. */
void nsyn_signal(nsyn_lock_t *l);

/* Broadcast a lock condition. Ensure the state has changed and committed.
 * This function informs all observers the lock condition has changed. */
void nsyn_broadcast(nsyn_lock_t *l);

/* Release the lock. Must be called by the same thread that acquired it,
 * and must not be reached via longjmp — see header discipline notes above. */
void nsyn_unlock(nsyn_lock_t *l);

/* Non-blocking attempt to acquire the lock. Returns 1 on success (caller now
 * holds the lock and must eventually call nsyn_unlock), 0 if the lock was
 * already held by someone else. Does not participate in / consume a ticket
 * on failure, so it cannot cause starvation of waiting threads. */
int nsyn_trylock(nsyn_lock_t *l);

/* Block and resume 'hence' seconds from now. No lock is needed, this
   synchronisation is to a specified point in time in the future. */
void nsyn_resume(double hence);


/* ---- Architecture-specific primitives (implemented per target) ---- */

/* Block the calling thread while *addr == expected. May return spuriously;
 * callers must re-check the condition in a loop. timeout_ns < 0 means wait
 * indefinitely. */
void nsyn_arch_wait32(_Atomic uint32_t *addr, uint32_t expected, int64_t timeout_ns);

/* Wake up to `count` threads waiting on *addr. */
void nsyn_arch_wake32(_Atomic uint32_t *addr, uint32_t count);

#ifdef __cplusplus
}
#endif

#endif /* NSYN_H */
