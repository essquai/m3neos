/* Copyright (C) 2026 Sunil Khare. All rights reserved. 
 *
 * explicit memory manager deals memory from a pre-declared fixed segment
 *     + sbrk routines work the pre-declared heap
 *     + diag routines cache debug text
 *     + lock routines are mutexes
 */

#include "emm.h"
#include <assert.h>
#include <stdalign.h>
#include <stdio.h>
#include <stdarg.h>
#include <time.h>

/* emm_init()
 *     prepare the explicit memory manager for running
 */
void emm_init(void *heap, size_t numBytes) {
    emm_sbrk_init(heap, numBytes);
    emm_diag_init();
    emmalloc_blank_slate_from_orbit();
}


static struct {
    /* user heap */
    int64_t  heapSize;
    char    *heapAddr;

    /* program break */
    int64_t  brkCurr;
    char    *brkAddr;
} segment = {0, NULL, 0, NULL};


/* emm_sbrk_vary()
 *     On error, return -1 and set errno to ENOMEM
 *     On success, return the previous break
 *     bounds check and adjust the break by (signed) numBytes
 */
void *emm_sbrk_vary(int64_t numBytes) {
    void *prevBrk = NULL;
    int64_t nextCurr;
    uintptr_t a;

    /* segment initialisation required */
    if (segment.heapAddr != NULL) {
      /* Check the bounds */
      nextCurr = segment.brkCurr + numBytes;
      if (nextCurr >= 0 && nextCurr <= segment.heapSize) {
        /* Adjust the break */
        prevBrk = (void *) segment.brkAddr;

        segment.brkCurr = nextCurr;
        segment.brkAddr = segment.heapAddr + nextCurr;
        a = (uintptr_t) segment.brkAddr;
        assert( (a & (alignof(max_align_t) -1)) == 0);
      }
    }

    /* All is well? */
    if (prevBrk == NULL) {
        prevBrk = EMM_SBRK_FAIL;
        errno = ENOMEM;
    }
    return prevBrk;
}


/* emm_sbrk_init()
 *     Define the heap Address and Size
 */
void emm_sbrk_init(void *addr, size_t numBytes) {
    uintptr_t a = (uintptr_t) addr;
    size_t max = (size_t) 2 * 1024 * 1024 * 1024;
    assert( numBytes < max );
    assert( (a & (alignof(max_align_t) -1)) == 0 );

    segment.heapSize = numBytes;
    segment.heapAddr = addr;
    segment.brkAddr  = addr;
    segment.brkCurr  = 0;
}


/* emm_sbrk_stat()
 *     Return key statistics
 */
void emm_sbrk_stat(int64_t *heapSize, int64_t *curr) {
    *heapSize = segment.heapSize;
    *curr = segment.brkCurr;
    return;
}


#define EMM_DIAG_CACHE  512
#define EMM_DIAG_TEXT   192

static struct {
    /* user heap */
    double when;
    char   text[EMM_DIAG_TEXT];
} diag_cache[EMM_DIAG_CACHE];

static int        emm_diag_index;
static double     emm_diag_zero;
static emm_lock_t emm_diag_mutex;

/* emm_diag_when
 *     ersatz timestamp
 */
static double emm_diag_when() {
    double when = 0.0;
    struct timespec ts;
    if (timespec_get(&ts, TIME_UTC)) {
        when = (double) ts.tv_sec + ((double)ts.tv_nsec / 1000000000.0);
    }
    return when;
}

/* emm_diag_init
 *     prepare diag cache for use
 */
void emm_diag_init() {
    int i;

    emm_lock_init(&emm_diag_mutex);
    emm_diag_zero  = emm_diag_when();
    emm_diag_index = 0;
    for (i = 0; i < EMM_DIAG_CACHE; i++) {
        diag_cache[i].when = -1.0;
    }

}

/* emm_diag_stow
 *     timestamp formatted debug text
 */
void emm_diag_stow(const char *format, ...) {
    int idx;
    va_list args;

    emm_lock_grab(&emm_diag_mutex);
    idx = emm_diag_index++;
    if (emm_diag_index >= EMM_DIAG_CACHE) {
        emm_diag_index = 0;
    }
    emm_lock_drop(&emm_diag_mutex);

    va_start(args, format);
    diag_cache[idx].when = emm_diag_when() - emm_diag_zero;
    vsnprintf(diag_cache[idx].text, EMM_DIAG_TEXT, format, args);
    va_end(args);
}

/* emm_diag_dump
 *     dump diagnostics -> stdout
 */
void emm_diag_dump() {
    int i;
    emm_lock_grab(&emm_diag_mutex);
    for (i = 0; i < EMM_DIAG_CACHE; i++) {
        if (diag_cache[i].when >= 0.0) {
            printf("[%.6lf] %s\n",diag_cache[i].when, diag_cache[i].text);
        }
        diag_cache[i].when = -1.0;
    }
    emm_diag_index = 0;
    emm_lock_drop(&emm_diag_mutex);
}

/* emm_lock_init()
 *     initialise a lock
 */
void emm_lock_init(emm_lock_t *lock) {
    atomic_flag_clear(&lock->flag);
    lock->value = 0;
}

/* emm_lock_grab()
 *     acquire lock
 */
void emm_lock_grab(emm_lock_t *lock) {
    while (atomic_flag_test_and_set(&lock->flag)) {
        /* spin */
    }
    lock->value = 1;

}

/* emm_lock_drop()
 *     relinquish lock
 */
void emm_lock_drop(emm_lock_t *lock) {
    lock->value = 0;
    atomic_flag_clear(&lock->flag);
}

/* emm_lock_assert()
 *     we've got this
 */
void emm_lock_assert(emm_lock_t *lock) {
    assert(lock->value > 0);
}
