/* Copyright (C) 2026 Sunil Khare. All rights reserved. 
 *
 * Neos Threads - x86_64 implementation
 *
 */
#if !defined(__x86_64__)
#error "nthr_x86_64.c compiled for a non-x86_64 target"
#endif


#include "nthr.h"
#include "nsyn.h"
#include <stdlib.h>
#include <stdio.h>


/* Required for SysV integration */
extern void *__libc_stack_end;
_Static_assert(offsetof(nthr_context_t, stack_ptr) == 64,  "nthr_sysv.s hard-codes stack_ptr");
_Static_assert(offsetof(nthr_context_t, regs)      == 104, "nthr_sysv.s hard-codes regs");


static void *nthr_func32(void *arg) {
    nthr_context_t *ctxt = arg;
    nthr_nexus_t *nx = &nthr_nexus;
    nsyn_lock_t *joinSyn;
    int32_t watch;
    int32_t safePoint;

    printf("nthr_func tid=%d begin\n", ctxt->tid); fflush(NULL);

    /* establish the context */
    nthr_current = ctxt;
    atomic_store_explicit(&ctxt->watch, vigilant, memory_order_release);

    /* 
     * check whether a safePoint was invoked while this thread spawns
     */
    safePoint = atomic_load_explicit(&nx->safePoint, memory_order_acquire);
    if (safePoint) {
      printf("nthr_func tid=%d nexus park\n", ctxt->tid); fflush(NULL);
      nthr_park();
    } else {
      nsyn_broadcast(&nx->watchSyn);
      printf("nthr_func tid=%d nexus broadcast\n", ctxt->tid); fflush(NULL);
    }


    /* dispatch via saved context */
    printf("nthr_func tid=%d dispatch\n", ctxt->tid); fflush(NULL);
    ctxt->fn(ctxt->fn_arg);
    printf("nthr_func tid=%d exec\n", ctxt->tid); fflush(NULL);

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
    printf("nthr_func end tid=%d join=%p live=%d\n", ctxt->tid, joinSyn, watch); fflush(NULL);
    if (joinSyn) {
        nsyn_lock(joinSyn);
        nsyn_signal(joinSyn);
        nsyn_unlock(joinSyn);
    }

    return(NULL);
}

void nthr_arch_tls32(nthr_context_t *ctxt) {
    ctxt->tls_base = NULL;
}

/*
 * nthr_arch_stack32 migrated to nthr_sysv.s: formulated as assembler to
 * additionally spill x86_64 register set to nthr_context_t for root
 * scanning purposes by garbage collector.
 *
void nthr_arch_stack32() {
    uintptr_t rsp;
    __asm__ volatile("mov %%rsp, %0" : "=r"(rsp));
    nthr_current->stack_ptr = (void *) rsp;
}
 */

void nthr_arch_top32(nthr_context_t *ctxt) {
    ctxt->stack_top = __libc_stack_end;
}


void nthr_arch_reap32(nthr_context_t *ctxt) {
    pthread_join(ctxt->p, NULL);
}


int nthr_arch_spawn32(nthr_context_t *ctxt) {
    int status;
    pthread_attr_t attr;

    status = pthread_attr_init(&attr);
    if (status == 0) {
        status = pthread_attr_setstack(&attr, ctxt->stack_addr, ctxt->stack_size);
        if (status == 0) {
            status = pthread_create(&ctxt->p, &attr, nthr_func32, ctxt);
            if (status != 0) {
                printf("nthr_spawn32 pthread_create failure %d\n", status);
            }
        } else {
            printf("nthr_spawn32 attr setstack failure %d\n", status);
            abort();
        }
    } else {
        printf("nthr_spawn32 attr init failure %d\n", status);
        abort();
    }
    pthread_attr_destroy(&attr);
    //printf("nthr_spawn self=%d tid=%d\n", nthr_current->tid, ctxt->tid); fflush(NULL);
    return(status);
}