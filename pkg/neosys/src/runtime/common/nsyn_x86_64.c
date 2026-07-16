/* Copyright (C) 2026 Sunil Khare. All rights reserved. 
 *
 * Neos Sync — x86_64 (Linux) arch_wait32 / arch_wake32 implementation.
 *
 * Uses the raw futex(2) syscall directly — no dependency on pthreads or
 * any libc threading library, mirroring the wasm32 implementation's
 * independence from wasi-libc's pthread support.
 *
 * NOTE: this file targets Linux specifically (FUTEX_WAIT / FUTEX_WAKE via
 * SYS_futex). Porting to other x86_64 OSes requires a different backend:
 *   - Darwin:  __ulock_wait / __ulock_wake
 *   - Windows: WaitOnAddress / WakeByAddressSingle / WakeByAddressAll
 * Keep those as separate nsyn_<os>.c files following this same shape if
 * additional host OSes are ever needed.
 */

#include "nsyn.h"

#if !defined(__x86_64__)
#error "nsyn_x86_64.c compiled for a non-x86_64 target"
#endif

#include <linux/futex.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>

#include <stdlib.h>
#include <stdio.h>

void nsyn_arch_wait32(_Atomic uint32_t *addr, uint32_t expected, int64_t timeout_ns) {
    long   s;
    struct timespec ts;
    struct timespec *ts_ptr = NULL;

    if (timeout_ns >= 0) {
        ts.tv_sec  = (time_t)(timeout_ns / 1000000000LL);
        ts.tv_nsec = (long)(timeout_ns % 1000000000LL);
        ts_ptr = &ts;
    }

    /* FUTEX_WAIT: block iff *addr still == expected at the moment the
     * kernel checks it. Returns immediately (EAGAIN) if the value already
     * changed — equivalent in effect to the spurious-return case on wasm32.
     * Errors (EINTR, EAGAIN, ETIMEDOUT) are intentionally not distinguished
     * here: callers always re-check their own condition in a loop. */
    s = syscall(SYS_futex, (uint32_t *)addr, FUTEX_WAIT_PRIVATE, expected, ts_ptr, NULL, 0);
    if (s == -1 && errno != EAGAIN && errno != EINTR && errno != ETIMEDOUT) {
        printf("FUTEX_WAIT: %ld %d\n", s, errno);
        abort();
    }
}

void nsyn_arch_wake32(_Atomic uint32_t *addr, uint32_t count) {
    long s;
    s = syscall(SYS_futex, (uint32_t *)addr, FUTEX_WAKE_PRIVATE, count, NULL, NULL, 0);
    if (s < 0) {
        printf("FUTEX_WAKE: %ld %d\n", s, errno);
        abort();
    }
}
