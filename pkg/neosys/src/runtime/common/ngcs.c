/* Copyright (C) 2026 Sunil Khare. All rights reserved. 
 *
 * Neos Garbage Collection State - coordinate the GC world
 *
 * The synchronisation point for GC state is ngcs_global, which is
 * defined here.
 */

#include "ngcs.h"

ngcs_sync_t ngcs_global;

void ngcs_init() {
    ngcs_global.gc_pending = 0;
    ngcs_global.threads_parked = 0;
    nsyn_init(&ngcs_global.gc_mutex);
}

void ngcs_park() {
    int32_t pending;

    /* Mark myself as parked while gc_pending is set */
    nsyn_lock(&ngcs_global.gc_mutex);
    atomic_fetch_add_explicit(&ngcs_global.threads_parked, 1, memory_order_relaxed);
    pending = atomic_load_explicit(&ngcs_global.gc_pending, memory_order_relaxed);

    while (pending == 1) {
        nsyn_wait(&ngcs_global.gc_mutex);
        pending = atomic_load_explicit(&ngcs_global.gc_pending, memory_order_relaxed);
    }

    /* Now GC is no longer pending, mark myself unparked */
    atomic_fetch_add_explicit(&ngcs_global.threads_parked, -1, memory_order_relaxed);
    nsyn_unlock(&ngcs_global.gc_mutex);
}

void ngcs_wait(int32_t current_parked) {
    int32_t parked = -1;

    /* observe state changes until all are parked */
    nsyn_lock(&ngcs_global.gc_mutex);
    while (parked < current_parked) {
        parked = atomic_load_explicit(&ngcs_global.threads_parked, memory_order_relaxed);
        if (parked < current_parked) {
            nsyn_wait(&ngcs_global.gc_mutex);
        }
    }
    nsyn_unlock(&ngcs_global.gc_mutex);
}

void ngcs_wake() {
    nsyn_broadcast(&ngcs_global.gc_mutex);
}

void ngcs_request_stop() {

    /* notify our intent to coordinate a collection */
    nsyn_lock(&ngcs_global.gc_mutex);
    atomic_store_explicit(&ngcs_global.gc_pending, 1, memory_order_relaxed);
    nsyn_unlock(&ngcs_global.gc_mutex);
}

void ngcs_resume() {

    /* the world is no longer "stopped" - tell everyone! */
    nsyn_lock(&ngcs_global.gc_mutex);
    atomic_store_explicit(&ngcs_global.gc_pending, 0, memory_order_relaxed);
    nsyn_unlock(&ngcs_global.gc_mutex);
    nsyn_broadcast(&ngcs_global.gc_mutex); /* awaken ngcs_park waiters */
}
