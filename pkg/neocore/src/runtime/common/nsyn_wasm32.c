/* Copyright (C) 2026 Sunil Khare. All rights reserved. 
 *
 * Neos Sync — wasm32 arch_wait32 / arch_wake32 implementation.
 *
 * Requires the wasm threads + atomics proposal:
 *   clang flags: -matomics -mbulk-memory -pthread-less (no -pthread!)
 *   linker flags: -Wl,--shared-memory
 *                 -Wl,--initial-memory=<N> -Wl,--max-memory=<N>
 *
 * Run under a runtime built with threads support enabled
 * (Wasmer / WAMR with the threads / wasi-threads feature on).
 *
 * No dependency on wasi-libc or any pthread implementation: this talks
 * directly to the wasm memory.atomic.wait32 / memory.atomic.notify
 * instructions via clang builtins.
 */

#include "nsyn.h"

#if !defined(__wasm32__)
#error "nsyn_wasm32.c compiled for a non-wasm32 target"
#endif

void nsyn_arch_wait32(_Atomic uint32_t *addr, uint32_t expected, int64_t timeout_ns) {
    /* __builtin_wasm_memory_atomic_wait32 takes an int32_t* — the incoming
     * type is _Atomic uint32_t*, which has the same object representation. */
    __builtin_wasm_memory_atomic_wait32((int32_t *)addr, (int32_t)expected, timeout_ns);
    /* Return value (0 = woken by notify, 1 = value mismatch, 2 = timed out)
     * is intentionally ignored: nsyn_lock()/nsyn_trylock() callers
     * always re-check the condition themselves in a loop, so any of these
     * outcomes is handled uniformly by looping back around. */
}

void nsyn_arch_wake32(_Atomic uint32_t *addr, uint32_t count) {
    __builtin_wasm_memory_atomic_notify((int32_t *)addr, count);
}
