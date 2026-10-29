/* Copyright (C) 2026 Sunil Khare. All rights reserved. 
 *
 * Neos Threads - wasm32 implementation
 *
 */
#include <wasi/api.h>
#include <stdio.h>
#include "nthr.h"
#include "nsyn.h"
#include "nref.h"

#if !defined(__wasm32__)
#error "nthr_wasm32.c compiled for a non-wasm32 target"
#endif


/* Required for wasi integration */
extern char __stack_high;
extern void __wasm_init_tls(void *);
extern void *nthr_wasi_sp(void);
_Static_assert(offsetof(nthr_context_t, stack_top) == 40, "nthr_wasi.s hard-codes stack_top");
_Static_assert(offsetof(nthr_context_t, ended) == 80,     "nthr_wasi.s hard-codes ended");


/* Invoked from neos wasi_thread_start implementation */
/* See companion source nthr_wasi.s commentary block  */
__attribute__((visibility("hidden")))
void nthr_start32(int tid, nthr_context_t *ctxt) {
    nthr_nexus_t *nx = &nthr_nexus;
    nsyn_lock_t *joinSyn;
    recce_t watch;
    int32_t safePoint;


    /* __stack_pointer is a wasm global, set up in wasi_thread_start
       With SP set, this nthr_start32 continues the thread sequence
       Set up thread-local storage first - current thread context */
    __wasm_init_tls(ctxt->tls_base);
    nthr_current = ctxt;


    /* establish the context */
    atomic_store_explicit(&nthr_current->watch, vigilant, memory_order_release);
    safePoint = atomic_load_explicit(&nx->safePoint, memory_order_acquire);

    /* 
     * check whether a safePoint was invoked while this thread spawns
     */
    if (safePoint) {
      printf("nthr_func tid=%d nexus park\n", ctxt->tid); fflush(NULL);
      nthr_park();
    } else {
      nsyn_broadcast(&nx->watchSyn);
      printf("nthr_func tid=%d nexus broadcast\n", ctxt->tid); fflush(NULL);
    }


    /* dispatch via saved context */
    nthr_current->fn(nthr_current->fn_arg);


    /* update and advertise watch state */
    nsyn_lock(&nx->watchSyn);
    watch = detached;
    atomic_store_explicit(&ctxt->watch, detached, memory_order_release);
    nsyn_unlock(&nx->watchSyn);
    nsyn_broadcast(&nx->watchSyn);

    /* update any joiner that is present */
    nsyn_lock(ctxt->outerSyn);
    joinSyn = ctxt->joinSyn;
    nsyn_unlock(ctxt->outerSyn);
    printf("nthr_func end tid=%d join=%p live=%d\n", nthr_current->tid, joinSyn, watch); fflush(NULL);
    if (joinSyn) {
        nsyn_lock(joinSyn);
        nsyn_signal(joinSyn);
        nsyn_unlock(joinSyn);
    }

    return;
}

void nthr_arch_tls32(nthr_context_t *ctxt) {
    ctxt->tls_base = nref_malloc(__builtin_wasm_tls_size(), Untraced);
}

void nthr_arch_stack32() {
    nthr_current->stack_ptr = nthr_wasi_sp();
}

void nthr_arch_top32(nthr_context_t *ctxt) {
    ctxt->stack_top = &__stack_high;
}

void nthr_arch_reap32(nthr_context_t *ctxt) {
    /* awakened by nthr_wasi.s custom thread */
    while (atomic_load_explicit(&ctxt->ended, memory_order_acquire) == 0) {
      __builtin_wasm_memory_atomic_wait32((int32_t *)&ctxt->ended, 0, -1);
    }
}

int nthr_arch_spawn32(nthr_context_t *ctxt) {
    int32_t status = __wasi_thread_spawn(ctxt);
    if (status < 0) {
        __builtin_trap();
    }
    return(status);
}

