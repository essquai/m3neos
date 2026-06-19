/* Copyright (C) 2026 Sunil Khare. All rights reserved. 
 *
 * Neos References
 *
 * Allocate memory for three reference types:
 *    + Virtual  - virtual memory from the process
 *    + Untraced - untraced references, manually freed
 *    + Traced   - traced references subject to GC
 *
 * Derived from 2.2.7 of the language definition, but virtual is
 * allocated from the target. The lower levels of the cm3 compiler
 * simply use C stdlib malloc without heed of reference type.
 *
 * The Wasm target only has the underlying sbrk concept and needs
 * shadow stacks for GC root tracing; therefore neos M3 uses separate
 * arenas for traced and untraced mallocs. This also allows for a cleaner
 * runtime initialization.
 *
 * The untraced and traced pool types can have predefined sizes by
 * providing @M3 runtime parameters in kilobytes. Their pre-defined
 & buffers are bootrapped allocations from Virtual.
 *
 * The usual malloc, calloc, and free suspects are provided, but
 * with reference type as an additional function argument. No realloc.
 *
 * Copied from the emscripten malloc implementation and augmented
 * by reference type nref_t.
 */
#include <stddef.h>
#include <stdbool.h>
#include <malloc.h>

typedef enum {
  Virtual,
  Untraced,
  Traced
} nref_t;

/* Module initialisation: either use prologue OR the other two */
void nref_prologue(int argc, char **argv);
void nref_from_orbit();
bool nref_define(size_t numBytes, nref_t ref);

/* Allocation */
void *nref_malloc(size_t size, nref_t ref);
void *nref_calloc(size_t num, size_t size, nref_t ref);
void nref_free(void *ptr, nref_t ref);

/* Meta Information */
void nref_sizes(long *bytes);
struct mallinfo nref_mallinfo(nref_t ref);
int  nref_validate_memory_regions(nref_t ref);
void nref_dump_memory_regions(nref_t ref);
void nref_dump_free_dynamic_memory_fragmentation_map(nref_t ref);
size_t nref_dynamic_heap_size(nref_t ref);
size_t nref_free_dynamic_memory(nref_t ref);
void nref_diag_dump();

