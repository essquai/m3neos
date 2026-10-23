/* Copyright (C) 2026 Sunil Khare. All rights reserved. 
 *
 * Neos Threads - custom concurrency with safepoints
 *
 */

#include "nthr.h"
#include "nref.h"
#include <stdlib.h>
#include <stdbool.h>
#include <stdio.h>

/* Module variables */
static _Atomic int32_t nthr_next_tid = 24 * 1024;
nthr_nexus_t nthr_nexus;
_Thread_local nthr_context_t *nthr_current;
_Thread_local void *llvm_gc_root_chain;
/* make llvm.gcroot thread safe ^*/


int nthr_create(nthr_context_t *ctxt, nsyn_lock_t *ctxSyn, size_t stack, void (*rtn)(void *), void *param, void *self) {
    int pid = -1;

    stack             = (stack >> 4) << 4; /* align on 16 */
    ctxt->watch       = deferred; /* #toPark: defer to arch_spawn to both set and advertise */
    ctxt->tid         = atomic_fetch_add_explicit(&nthr_next_tid, 1, memory_order_relaxed);
    ctxt->outerSyn    = ctxSyn;
    ctxt->joinSyn     = NULL;
    ctxt->fn          = rtn;
    ctxt->fn_arg      = param;
    ctxt->self        = self;
    ctxt->stack_size  = stack;
    ctxt->stack_addr  = nref_malloc(stack, Untraced);
    ctxt->stack_ptr   = ctxt->stack_addr + stack;
    ctxt->stack_top   = ctxt->stack_ptr;
    ctxt->stack_chain = NULL;
    ctxt->ended       = 0;
    for (int i = 0; i < NREGS; i++) {
        ctxt->regs[i] = 0;
    }

    if (ctxt->stack_addr) {
        nthr_arch_tls32(ctxt);
        pid = nthr_arch_spawn32(ctxt);
    } else {
        printf("NOSTACK nthr_create\n");
        abort();
    }
    //printf("nthr_create self=%d tid=%d, pid=%d\n", nthr_current->tid, ctxt->tid, pid); fflush(NULL);
    return(pid);
}

void *nthr_self() {
    return nthr_current->self;
}

void nthr_default(nthr_context_t *ctxt, nsyn_lock_t *ctxSyn, void *self) {
    if (nthr_current) {
        printf("nthr_default invoked a second time - fatal error\n");
        fflush(NULL);
        abort();
    }
    /* setting watch as relief steers nthr_wait out of safepoint parking. */
    ctxt->watch       = relief;
    ctxt->tid         = 1;
    ctxt->outerSyn    = ctxSyn;
    ctxt->joinSyn     = NULL;
    ctxt->self        = self;
    ctxt->tls_base    = NULL;
    ctxt->stack_chain = NULL;
    ctxt->ended       = 0;
    for (int i = 0; i < NREGS; i++) {
        ctxt->regs[i] = 0;
    }
    nthr_arch_top32(ctxt);
    nthr_current      = ctxt;
}


/* classic nsyn_wait, not accounting for nexus */
static void nsyn_wait(nsyn_lock_t *l, double hence) {
    int64_t timeout = (int64_t) (hence * 1e9);
    uint32_t seq = atomic_load_explicit(&l->cond_seq, memory_order_acquire);
    nsyn_unlock(l);
    nsyn_arch_wait32(&l->cond_seq, seq, timeout);   /* returns on change or spuriously */
    nsyn_lock(l);
    /* caller re-checks its predicate in its own loop, Mesa-semantics style */
}

/* thread wait, taking nexus into account */
void nthr_wait(nsyn_lock_t *l, double hence) {
    int32_t safePoint;
    int32_t incoming;

    /* Publish before becoming deferred (see nthr_park). Waiting is parking, so this
     * is a potential park point. */
    nthr_arch_stack32();
    nthr_current->stack_chain = llvm_gc_root_chain;

    /*
     * determine info for nexus decisions
     */
    incoming  = atomic_exchange_explicit(&nthr_current->watch, deferred, memory_order_release);
    safePoint = atomic_load_explicit(&nthr_nexus.safePoint, memory_order_acquire);
    nthr_debug("nthr_wait enter (watch,tid,safePoint)", (void *) ((intptr_t) incoming), nthr_current->tid, safePoint);


    /*
     * do we need to park first, or just wait?
     * relief means this thread will take the next watch, so don't park
     */
    if (safePoint && (incoming >= vigilant)) {
        nthr_park();
    }

    /*
     * Regardless of safepoint, I need to honour the wait
     * NB: acquireSafe waits on safeSyn, with watch=deferred in order
     * to not invoke nthr_park. Restore the incoming watch state, instead
     * of a more obvious vigilant option.
     */
    nthr_debug("nthr_wait nsyn_wait (lock,tid)", l, nthr_current->tid, -1);

    nsyn_wait(l, hence);

    /* safePoint may have been set during this wait.
     * But if I'm not vigilant then do not park */
    if (incoming >= vigilant) {
        if (atomic_load_explicit(&nthr_nexus.safePoint, memory_order_acquire)) {
            nthr_park();
        }
    }
    atomic_store_explicit(&nthr_current->watch, incoming, memory_order_seq_cst);
    /* check that a safepoint was not established while I returned to vigilant
     * Order is ensured by seq_cst, if safepoint needs loading */
    if (incoming >= vigilant) {
        if (atomic_load_explicit(&nthr_nexus.safePoint, memory_order_seq_cst)) {
            nthr_park();
        }
    }
    nthr_debug("nthr_wait exit (lock,tid, watch)", l, nthr_current->tid, incoming);
}


void nthr_park() {
    int32_t safePoint;
    nthr_nexus_t *nx = &nthr_nexus;
    recce_t incoming;

    /* Park is entered from a safepoint poll (vigilant), from nthr_wait (deferred, it
     * has just exchanged) and from nthr_func32 (vigilant). Like nthr_wait, hand back
     * the state we were entered with, never a fixed one: other paths set deferred or
     * relief on purpose. */
    incoming = atomic_load_explicit(&nthr_current->watch, memory_order_acquire);

    /* until the final exit below, no new stop may begin */
    atomic_fetch_add_explicit(&nx->parked, 1, memory_order_acq_rel);

    /* Take safeSyn before I park myself. safeSyn protects safePoint and safePoint is
     * the condition waited for below: ResumeOthers clears it under safeSyn and then
     * broadcasts safeSyn. */
    nsyn_lock(&nx->safeSyn);

    /* Publish before advertising: once watch reads deferred a coordinator may read
     * stack_ptr and stack_chain, so they must already be current. */
    nthr_arch_stack32();
    nthr_current->stack_chain = llvm_gc_root_chain;
    nthr_debug("nthr_park safe (tid)", NULL, nthr_current->tid, -1);


    /* (re-)establish myself as deferred */
    /* prevent a race with allSafe using mutex for my context.watch  */
    nsyn_lock(&nx->watchSyn);
    nthr_debug("nthr_park parking (tid)", NULL, nthr_current->tid, -1);
    atomic_store_explicit(&nthr_current->watch, deferred, memory_order_release);
    nsyn_unlock(&nx->watchSyn);


    /* advertise my park state change */
    nsyn_broadcast(&nx->watchSyn);
    nthr_debug("nthr_park parked (tid)", NULL, nthr_current->tid, -1);

    /* Mesa: safeSyn is held (taken above, and re-taken on every return from nsyn_wait);
     * safePoint is the condition */
    while (atomic_load_explicit(&nx->safePoint, memory_order_acquire)) {
        nsyn_wait(&nx->safeSyn, -1.0);
    }
    nsyn_unlock(&nx->safeSyn);

    /* Leave the parked state. A park taken from a poll has no enclosing nthr_wait to
     * restore watch for it, so without this the thread stays deferred: the poll never
     * parks it again (it parks only at watch >= vigilant) and SuspendOthers, which counts
     * vigilant threads, ignores it. Watch changes under watchSyn and is then advertised
     * with a broadcast, as in nthr_vigil. If we were running (not already deferred),
     * re-check the flag: a new SuspendOthers may have counted this thread as safe while
     * it was waking, and it must not run on. */
    nsyn_lock(&nx->watchSyn);
    atomic_store_explicit(&nthr_current->watch, incoming, memory_order_release);
    nsyn_unlock(&nx->watchSyn);
    nsyn_broadcast(&nx->watchSyn);
    /* should be invariant */
    if (incoming != deferred && atomic_load_explicit(&nx->safePoint, memory_order_seq_cst)) {
        printf("nthr_park neither deferred nor safe\n");
        fflush(NULL);
        abort();
    }

    /* Leave. Done last: until here SuspendOthers will not start another stop, so a
     * thread that gets this far has seen the flag clear and is released to run on to
     * its next poll. The last one out wakes a coordinator waiting for the drain; the
     * broadcast is taken under safeSyn so it cannot fall between that coordinator's test
     * and its wait. */
    if (atomic_fetch_sub_explicit(&nx->parked, 1, memory_order_acq_rel) == 1) {
        nsyn_lock(&nx->safeSyn);
        nsyn_broadcast(&nx->safeSyn);
        nsyn_unlock(&nx->safeSyn);
    }


    /* face the danger*/
    nthr_debug("nthr_park end (tid)", NULL, nthr_current->tid, -1);
}


int32_t nthr_vigil(nthr_context_t *ctxt) {
    nthr_nexus_t *nx = &nthr_nexus;
    recce_t watch;
    recce_t incoming;

    watch = atomic_load_explicit(&ctxt->watch, memory_order_acquire);
    //printf("nthr_vigil self=%d tid=%d enter cur=%d\n", sid, ctxt->tid, watch); fflush(NULL);
    if (watch != detached) {
        /* await notification
         * The following is finely crafted per the folllowing:
         *   a) note the nsyn_wait - waiting on a join will not park
         *   b) joining a thread does not wait on watchSyn or safeSyn
         *   c) result: invoking join blocks only on thread completion
         *   d) self.watch is deferred during nsyn_wait - mirroring nthr_wait
         *   e) watchSyn is broadcast/notified after self.watch changes
         *   f) publish stack and root chain published before going deferred
         */
        nthr_arch_stack32();
        nthr_current->stack_chain = llvm_gc_root_chain;

        nsyn_lock(&nx->watchSyn);
        incoming = atomic_exchange_explicit(&nthr_current->watch, deferred, memory_order_release);
        nsyn_unlock(&nx->watchSyn);
        nsyn_broadcast(&nx->watchSyn);

        nsyn_wait(ctxt->joinSyn, -1.0);

        /* safePoint may have been set during this wait.
         * But if I am the relief then do not park */
        if (incoming >= vigilant) {
            if (atomic_load_explicit(&nthr_nexus.safePoint, memory_order_acquire)) {
                 nthr_park();
            }
        }

        nsyn_lock(&nx->watchSyn);
        atomic_store_explicit(&nthr_current->watch, incoming, memory_order_release);
        nsyn_unlock(&nx->watchSyn);
        nsyn_broadcast(&nx->watchSyn);
        /* check that a safepoint was not established while I returned to vigilant
         * Ordered by the watchSyn mutex, so just have to re-load it */
        if (incoming >= vigilant && atomic_load_explicit(&nx->safePoint, memory_order_acquire)) {
            nthr_park();
        }
        watch = atomic_load_explicit(&ctxt->watch, memory_order_acquire);
        //printf("nthr_vigil self=%d tid=%d waited on %p cur=%d\n", sid, ctxt->tid, ctxt->joinSyn, watch); fflush(NULL);
    }

    if (watch == detached) {
        watch = joined;
        nsyn_unlock(ctxt->joinSyn);
        nthr_arch_reap32(ctxt);
        nsyn_lock(ctxt->joinSyn);
        atomic_store_explicit(&ctxt->watch, joined, memory_order_relaxed);
        nref_free(ctxt->stack_addr, Untraced);
        if (ctxt->tls_base) nref_free(ctxt->tls_base, Untraced);
        ctxt->stack_addr = ctxt->tls_base = NULL;
    }
    //printf("nthr_vigil self=%d tid=%d return %d\n", nthr_current->tid, ctxt->tid, watch); fflush(NULL);
    return watch;
}

void nthr_debug(const char *txt, void *addr, intptr_t p1, intptr_t p2) {
    char dbg[400];
    char a_s[96], p1_s[96], p2_s[96];

    if (addr == NULL) a_s[0] = '\0'; else sprintf(a_s, " %p", addr);
    if (p1 < 0) p1_s[0] = '\0'; else sprintf(p1_s, " %ld", p1);
    if (p2 < 0) p2_s[0] = '\0'; else sprintf(p2_s, " %ld", p2);

    sprintf(dbg, "%s ::%s%s%s\n", txt, a_s, p1_s, p2_s);
    printf("%s", dbg);
    fflush(NULL);
}

void nthr_match(size_t lockSz, size_t ctxtSz, size_t nexusSz) {
    bool abiOK = true;
    size_t lockN = sizeof(nsyn_lock_t);
    size_t ctxtN = sizeof(nthr_context_t);
    size_t nexusN = sizeof(nthr_nexus_t);

    if (lockSz != lockN) {
        abiOK = false;
        printf("nsyn_lock_t size mismatch %ld != %ld\n", lockSz, lockN);
    }
    if (ctxtSz != ctxtN) {
        abiOK = false;
        printf("nthr_context_t size mismatch %ld != %ld\n", ctxtSz, ctxtN);
    }
    if (nexusSz != nexusN) {
        abiOK = false;
        printf("nthr_nexus_t size mismatch %ld != %ld\n", nexusSz, nexusN);
    }
    if (!abiOK) {
        abort();
    }
}

