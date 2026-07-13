/* Copyright (C) 2026 Sunil Khare. All rights reserved. 
 *
 * Neos Sync — target-independent ticket-lock logic.
 *
 * This file contains no architecture-specific code. It relies solely on
 * C11 atomics plus nsyn_arch_wait32 / nsyn_arch_wake32, which are
 * implemented separately per target (see nsyn_wasm32.c, nsyn_x86_64.c).
 */

#include "nsyn.h"

#define NSYN_MAX_THREAD 0x40000000

void nsyn_init(nsyn_lock_t *l) {
    atomic_store_explicit(&l->next_ticket, 0, memory_order_relaxed);
    atomic_store_explicit(&l->now_serving, 0, memory_order_relaxed);
}

void nsyn_lock(nsyn_lock_t *l) {
    uint32_t my_ticket = atomic_fetch_add_explicit(&l->next_ticket, 1,
                                                    memory_order_relaxed);
    uint32_t current;

    for (;;) {
        current = atomic_load_explicit(&l->now_serving, memory_order_acquire);
        if (current == my_ticket) {
            return; /* our turn */
        }
        /* Park until now_serving changes away from the value we just read.
         * nsyn_arch_wait32 may return spuriously, hence the loop. */
        nsyn_arch_wait32(&l->now_serving, current, -1);
    }
}

void nsyn_unlock(nsyn_lock_t *l) {
    /* Advance now_serving; release semantics publish everything done in the
     * critical section to the next lock holder. */
    atomic_fetch_add_explicit(&l->now_serving, 1, memory_order_release);

    /* Wake everyone waiting; each waiter re-checks its own ticket number and
     * re-parks if it still isn't being served. Waking all rather than just
     * one avoids having to know which specific ticket is waiting next. */
    nsyn_arch_wake32(&l->now_serving, NSYN_MAX_THREAD);
}

int nsyn_trylock(nsyn_lock_t *l) {
    uint32_t current = atomic_load_explicit(&l->now_serving, memory_order_acquire);
    uint32_t expected_next = current;

    /* Only succeed if we can claim exactly the next ticket without another
     * thread already being queued in front of us for it, i.e. next_ticket
     * must currently equal now_serving. */
    if (!atomic_compare_exchange_strong_explicit(
            &l->next_ticket, &expected_next, current + 1,
            memory_order_acquire, memory_order_relaxed)) {
        return 0; /* someone else already has or is queued for this ticket */
    }
    return 1; /* we now hold ticket == current == now_serving: lock acquired */
}

void nsyn_wait(nsyn_lock_t *l) {
    uint32_t seq = atomic_load_explicit(&l->cond_seq, memory_order_acquire);
    nsyn_unlock(l);
    nsyn_arch_wait32(&l->cond_seq, seq, -1);   /* returns on change or spuriously */
    nsyn_lock(l);
    /* caller re-checks its predicate in its own loop, Mesa-semantics style */
}

void nsyn_signal(nsyn_lock_t *l) {
    atomic_fetch_add_explicit(&l->cond_seq, 1, memory_order_release);
    nsyn_arch_wake32(&l->cond_seq, 1);
}

void nsyn_broadcast(nsyn_lock_t *l) {
    atomic_fetch_add_explicit(&l->cond_seq, 1, memory_order_release);
    nsyn_arch_wake32(&l->cond_seq, NSYN_MAX_THREAD);  /* wake all, avoiding the UINT32_MAX pitfall */
}