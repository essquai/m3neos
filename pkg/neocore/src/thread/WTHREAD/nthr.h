/* Copyright (C) 2026 Sunil Khare. All rights reserved. 
 *
 * Neos Threads - architecture blind creation and join
 *
 */

#ifndef NTHR_H
#define NTHR_H

#include <stdint.h>
#include <stddef.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <pthread.h>

#include "nsyn.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum { deferred, relief, vigilant, detached, joined } recce_t;

/* Thread Context */
#define NREGS 6
typedef struct {
    _Atomic recce_t watch; /* condition           */
    int32_t tid;           /* thread ID           */
    nsyn_lock_t *outerSyn; /* mutex for joinSyn   */
    nsyn_lock_t *joinSyn;  /* to wake on join     */

    void (*fn)(void *);    /* thread routine      */
    void *fn_arg;          /* routine's argument  */
    void *axis;            /* parameter           */
    size_t stack_size;     /* parameter           */

    void *stack_addr;      /* allocated           */
    void *stack_ptr;       /* current             */
    void *stack_top;       /* initial             */
    void *tls_base;        /* thread-local vars   */
    void *stack_chain;     /* gc root chain       */

    pthread_t p;           /* x86_64 "custom"     */
    uintptr_t regs[NREGS]; /* x86_64 registers    */
    _Atomic int32_t ended; /* reap ready          */
} nthr_context_t;

/* Thread nexus */
typedef struct {
    _Atomic int32_t safePoint;   /* 0 = run, 1 = Stop-the-world */
    nsyn_lock_t     safeSyn;     /* safePoint mutex             */

    nsyn_lock_t     watchSyn;    /* thread watch mutex          */
    _Atomic int32_t parked;      /* threads inside nthr_park    */
                                 /* tested in SuspendOthers     */

    void            *forkList;   /* list of threads             */
    nsyn_lock_t     forkSyn;     /* fork list mutex             */
} nthr_nexus_t;

extern nthr_nexus_t nthr_nexus;
extern _Thread_local nthr_context_t *nthr_current;
extern _Thread_local void *llvm_gc_root_chain;
/* make llvm.gcroot thread safe ^*/


/* Launch a thread with the given context. Thread invokes fn(arg). */
int32_t nthr_create(nthr_context_t *ctxt, nsyn_lock_t *ctxSyn, size_t stack, void (*fn)(void *), void *param, void *axis);

/* Wait for the death of the target thread, returns 0 on death */
int32_t nthr_vigil(nthr_context_t *ctxt);

/* Return context arg of the thread invoking it. */
void *nthr_self();

/* Set the default context - there can only be one */
void nthr_default(nthr_context_t *ctxt, nsyn_lock_t *ctxSyn, void *axis);

/* park current thread until the nexus.safepoint is clear */
void nthr_park();

/* nsyn_wait substitution optionally parks  */
void nthr_wait(nsyn_lock_t *l, double hence);

/* nsyn_lock substitution optionally parks */
void nthr_lock(nsyn_lock_t *l, bool no_park);


/* tracing */
void nthr_debug(const char *txt, void *addr, intptr_t p1, intptr_t p2);

/* ABI consistency for key structures */
void nthr_match(size_t lockSz, size_t ctxtSz, size_t nexusSz);


/* ---- Architecture-specific primitives (implemented per target) ---- */

/* Assign thread-local storage for the neos thread context in tls_base.
 * Invoked by the target-agnostic nthr_create function immediately
 * before spawning. Establishes tls_base. */
void nthr_arch_tls32(nthr_context_t *ctxt);

/* Spawn the thread for this architecture, set nthr_current, and invoke
 * the context function with its argument. When done, sets up correct
 * conditions for join completion. */
int nthr_arch_spawn32(nthr_context_t *ctxt);

/* save stack pointer and registers to thread context */
void nthr_arch_stack32();

/* for default thread, set the top of stack */
void nthr_arch_top32(nthr_context_t *ctxt);

/* Finalise the thread for this architecture. Invoked by the thread
 * that is joining this target thread */
void nthr_arch_reap32(nthr_context_t *ctxt);


#ifdef __cplusplus
}
#endif

#endif /* NTHR_H */
