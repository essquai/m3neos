/* Copyright (C) 2026 Sunil Khare. All rights reserved. 
 *
 * Explicit memory manager - malloc with a user-supplied heap
 *    + init: prepare for use with heap memory given
 *    + malloc: uninitialised memory
 *    + realloc: resize and preserve allocated segment
 *    + calloc: zero-initialised
 *    + free: give back
 *    + validate: zero is valid
 *    + dump: diagostic info
 *
 */
#include <stdint.h>
#include <stddef.h>
#include <stdatomic.h>
#include <errno.h>

/* Module Public Access */
void emm_init(void *heap, size_t numBytes);
void *emmalloc_malloc(size_t size);
void *emmalloc_realloc(void *ptr, size_t size);
void *emmalloc_calloc(size_t num, size_t size);
void emmalloc_free(void *ptr);
int  emmalloc_validate_memory_regions();
void emmalloc_dump_memory_regions();


/* Private functions */

/*
 * heap access
 *    + init: supply the heap segment
 *    + vary: change heap size, return previous break
 *    + stat: capacity and current use of the heap
 */
void emm_sbrk_init(void *heap, size_t numBytes);
void *emm_sbrk_vary(int64_t numBytes);
void emm_sbrk_stat(int64_t *max, int64_t *cur);
#define EMM_SBRK_FAIL ((void *) -1)


/*
 * diagnostics
 *     + stow: save diagnostic info
 *     + dump: dump it out
 */
void emm_diag_init();
void emm_diag_stow(const char *format, ...);
void emm_diag_dump();


 /*
  * locks
  *    + init: initialize before use
  *    + grab: acquire a lock
  *    + drop: relinquish a lock
  */
typedef struct { atomic_flag flag; int value; } emm_lock_t;

void emm_lock_init(emm_lock_t *lock);
void emm_lock_grab(emm_lock_t *lock);
void emm_lock_drop(emm_lock_t *lock);
void emm_lock_assert(emm_lock_t *lock);

/*
 * emmalloc
 *    + orbit: prepare for use
 */
void emmalloc_blank_slate_from_orbit();

