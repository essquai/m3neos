/* Copyright (C) 2026 Sunil Khare. All rights reserved. 
 *
 * Neos Garbage Collection State - coordinate the GC world
 *
 * This API enables the GC coordinator and mutator threads to synchronise with
 * each other to "stop the world" so that the coordinator can free memory 
 * that is no longer being referenced. The synchronisation mechanism is
 * one common nsyn_lock_t, which integrates mutual exclusion in a fair FIFO
 * manner and combines condition signalling. It guards all GC state fields.
 * 
 * The ngcs_mutator_park function should be invoked by mutators to block
 * while the GC world is stopped. The ngcs_collector_wait function is invoked
 * by the GC coordinator to wait on the condition that the given number of
 * threads are parked. And the ngcs_wake function tells interested threads
 * that the GC Collection State has changed.
 * 
 * The nsyn module handles exclusion and conditions for both x86_64/linux
 * and wasm32; therefore this runtime module serves both targets.
 *
 */

#ifndef NGCS_H
#define NGCS_H

#include <stdint.h>
#include <stdatomic.h>
#include "nsyn.h"

#ifdef __cplusplus
extern "C" {
#endif

/* GC synchronisation point. Initialise before use. */
typedef struct {
    _Atomic int32_t gc_pending;     /* 0 = Mutators run, 1 = Stop-the-world */
    _Atomic int32_t threads_parked; /* number of parked threads  */
    nsyn_lock_t     gc_mutex;       /* govern access and condition */
} ngcs_sync_t;

extern ngcs_sync_t ngcs_global;     /* One state for all GC synchronisation */

/* Initialize the synchronisation point */
void ngcs_init();

/* Block the calling mutator thread until the gc_pending condition is lifted */
void ngcs_park();

/* Request a stop-the-world pause by the GC coordinator. Sets gc_pending */
void ngcs_request_stop();

/* Block the calling GC coordinator thread until at least current_parked
 * threads have been parked. */
void ngcs_wait(int32_t current_parked);

/* Resume the world after a collection completes. Resets gc_pending
 and notifies mutators waiting on a clear gc_pending condition. */
void ngcs_resume();

/* Tell observing parties that the ngcs_global state
 * has changed. Usable both by mutators and the collector. */
void ngcs_wake();


#ifdef __cplusplus
}
#endif

#endif /* NGCS_H */
