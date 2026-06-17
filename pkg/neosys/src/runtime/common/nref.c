/* Copyright (C) 2026 Sunil Khare. All rights reserved.  */

/*-----------------------------------------------------------------------------
 *
 * Neos References - allocate memory by reference type
 *
 * The first half are utilities for:
 *   + sbrk functions to expand reference type segments
 *   + lock functions for thread-safety
 *   + diagnostic functions for debugging
 * The second part is:
 *   + emmalloc adapted for multiple references types
 *
 *---------------------------------------------------------------------------*/

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>
#include <unistd.h>
#include <stdatomic.h>
#include <stdalign.h>
#include <stdio.h>
#include <stdarg.h>
#include <time.h>
#include <errno.h>
#include <memory.h>
#include <malloc.h>

#include "nref.h"

/*-------------------------------------------------------- sbrk functions ---*/

typedef struct {
    /* user heap */
    bool       defined;
    intptr_t   heapSize;
    char      *heapAddr;

    /* program break */
    intptr_t   brkCurr;
    char      *brkAddr;
} segment_t; 
#define NREF_SBRK_FAIL ((void *) -1)


/* nref_sbrk_vary()
 *     On error, return -1 and set errno to ENOMEM
 *     On success, return the previous break
 *     bounds check and adjust the break by (signed) numBytes
 */
static void *nref_sbrk_vary(intptr_t numBytes, segment_t *segment) {
    void *prevBrk = NULL;
    intptr_t nextCurr;
    uintptr_t a;

    assert(segment->defined);

    if (segment->heapAddr == NULL) {
        /* heap not predefined --> unleash sbrk! */
        prevBrk = sbrk(numBytes);
        if (prevBrk != NREF_SBRK_FAIL) {
            segment->brkCurr += numBytes;
        }
    } else {
      /* emulate sbrk from pre-defined buffer */
      nextCurr = segment->brkCurr + numBytes;
      if (nextCurr >= 0 && nextCurr <= segment->heapSize) {

        /* Set the new break value */
        prevBrk = (void *) segment->brkAddr;

        segment->brkCurr = nextCurr;
        segment->brkAddr = segment->heapAddr + nextCurr;
        a = (uintptr_t) segment->brkAddr;
        assert( (a & (alignof(max_align_t) -1)) == 0);
      }

      /* It worked? */
      if (prevBrk == NULL) {
          prevBrk = NREF_SBRK_FAIL;
          errno = ENOMEM;
      }
    }
    return prevBrk;
}


/* nref_sbrk_init()
 *     Define the heap Address and Size
 */
static void nref_sbrk_init(void *addr, size_t numBytes, segment_t *segment) {
    uintptr_t a = (uintptr_t) addr;
    size_t max = (size_t) 2 * 1024 * 1024 * 1024;
    assert( numBytes < max );
    assert( (a & (alignof(max_align_t) -1)) == 0 );

    segment->heapSize = numBytes;
    segment->heapAddr = addr;
    segment->brkAddr  = addr;
    segment->brkCurr  = 0;
    segment->defined  = true;
}


/* nref_sbrk_stat()
 *     Return key statistics
 */
void nref_sbrk_stat(intptr_t *heapSize, intptr_t *curr, segment_t *segment) {
    *heapSize = segment->heapSize;
    *curr     = segment->brkCurr;
    return;
}


/*-------------------------------------------------------- lock functions ---*/
typedef struct {
    atomic_flag flag;
    int value;
} nref_lock_t;

// In multithreaded builds, use a simple global spinlock strategy to acquire/release access to the memory allocator.
#define MALLOC_ACQUIRE(ref) nref_lock_grab(&rctx[ref].multithreadingLock)
#define MALLOC_RELEASE(ref) nref_lock_drop(&rctx[ref].multithreadingLock)
// Test code to ensure we have tight malloc acquire/release guards in place.
#define ASSERT_MALLOC_IS_ACQUIRED(ref) nref_lock_assert(&rctx[ref].multithreadingLock)


/* nref_lock_init()
 *     initialise a lock
 */
static void nref_lock_init(nref_lock_t *lock) {
    atomic_flag_clear(&lock->flag);
    lock->value = 0;
}

/* nref_lock_grab()
 *     acquire lock
 */
static void nref_lock_grab(nref_lock_t *lock) {
    while (atomic_flag_test_and_set(&lock->flag)) {
        /* spin */
    }
    lock->value = 1;
}

/* nref_lock_drop()
 *     relinquish lock
 */
static void nref_lock_drop(nref_lock_t *lock) {
    lock->value = 0;
    atomic_flag_clear(&lock->flag);
}

/* nref_lock_assert()
 *     we've got this
 */
static void nref_lock_assert(nref_lock_t *lock) {
    assert(lock->value > 0);
}


/*-------------------------------------------------------- diag functions ---*/

#define NREF_DIAG_CACHE  512
#define NREF_DIAG_TEXT   192

static struct {
    /* user heap */
    double when;
    char   text[NREF_DIAG_TEXT];
} diag_cache[NREF_DIAG_CACHE];

static int         nref_diag_index;
static double      nref_diag_zero;
static nref_lock_t nref_diag_mutex = { ATOMIC_FLAG_INIT, 0};
;

/* nref_diag_when
 *     ersatz timestamp
 */
static double nref_diag_when() {
    double when = 0.0;
    struct timespec ts;
    if (timespec_get(&ts, TIME_UTC)) {
        when = (double) ts.tv_sec + ((double)ts.tv_nsec / 1000000000.0);
    }
    return when;
}

/* nref_diag_init
 *     prepare diag cache for use
 */
static void nref_diag_init() {

    nref_lock_init(&nref_diag_mutex);
    nref_diag_zero  = nref_diag_when();
    nref_diag_index = 0;
    for (int i = 0; i < NREF_DIAG_CACHE; i++) {
        diag_cache[i].when = -1.0;
    }

}

/* nref_diag_stow
 *     timestamp formatted debug text
 */
static void nref_diag_stow(const char *format, ...) {
    int idx;
    va_list args;

    nref_lock_grab(&nref_diag_mutex);
    idx = nref_diag_index++;
    if (nref_diag_index >= NREF_DIAG_CACHE) {
        nref_diag_index = 0;
    }
    nref_lock_drop(&nref_diag_mutex);

    va_start(args, format);
    diag_cache[idx].when = nref_diag_when() - nref_diag_zero;
    vsnprintf(diag_cache[idx].text, NREF_DIAG_TEXT, format, args);
    va_end(args);
}

/* nref_diag_dump
 *     dump diagnostics -> stdout
 */
void nref_diag_dump() {
    int i;
    nref_lock_grab(&nref_diag_mutex);
    for (i = 0; i < NREF_DIAG_CACHE; i++) {
        if (diag_cache[i].when >= 0.0) {
            printf("[%.6lf] %s\n",diag_cache[i].when, diag_cache[i].text);
        }
        diag_cache[i].when = -1.0;
    }
    nref_diag_index = 0;
    nref_lock_drop(&nref_diag_mutex);
}


/*------------------------------------------------------------ emmalloc.c ---*/
/*
 * Copyright 2018 The Emscripten Authors.  All rights reserved.
 * Emscripten is available under two separate licenses, the MIT license and the
 * University of Illinois/NCSA Open Source License.  Both these licenses can be
 * found in the LICENSE file.
 *
 * Simple minimalistic but efficient sbrk()-based malloc/free that works in
 * singlethreaded and multithreaded builds.
 *
 * Assumptions:
 *
 *  - sbrk() is used to claim new memory (sbrk handles geometric/linear
 *  - overallocation growth)
 *  - sbrk() can also be called by other code, not reserved to emmalloc only.
 *  - sbrk() is very fast in most cases (internal wasm call).
 *  - sbrk() returns pointers with an alignment of alignof(max_align_t)
 *
 * Invariants:
 *
 *  - Per-allocation header overhead is 8 bytes, smallest allocated payload
 *    amount is 8 bytes, and a multiple of 4 bytes.
 *  - Acquired memory blocks are subdivided into disjoint regions that lie
 *    next to each other.
 *  - A region is either in use or free.
 *    Used regions may be adjacent, and a used and unused region
 *    may be adjacent, but not two unused ones - they would be
 *    merged.
 *  - Memory allocation takes constant time, unless the alloc needs to sbrk()
 *    or memory is very close to being exhausted.
 *  - Free and used regions are managed inside "root regions", which are slabs
 *    of memory acquired via calls to sbrk().
 *
 * Debugging:
 *
 *  - If not NDEBUG, runtime assert()s are in use.
 *  - If EMMALLOC_MEMVALIDATE is defined, a large amount of extra checks are done.
 *  - If EMMALLOC_VERBOSE is defined, a lot of operations are logged using
 *    `out`, in addition to EMMALLOC_MEMVALIDATE.
 *  - Debugging and logging directly uses `out` and `err` via EM_ASM, not
 *    printf etc., to minimize any risk of debugging or logging depending on
 *    malloc.
 *
 */


// Behavior of right shifting a signed integer is compiler implementation defined.
static_assert((((int32_t)0x80000000U) >> 31) == -1, "This malloc implementation requires that right-shifting a signed integer produces a sign-extending (arithmetic) shift!");

// Configuration: specifies the minimum alignment that malloc()ed memory outputs. Allocation requests with smaller alignment
// than this will yield an allocation with this much alignment.
#define MALLOC_ALIGNMENT alignof(max_align_t)
static_assert(alignof(max_align_t) == 16, "max_align_t must be correct");

#define MIN(x, y) ((x) < (y) ? (x) : (y))
#define MAX(x, y) ((x) > (y) ? (x) : (y))

#define NUM_FREE_BUCKETS 64
#define BUCKET_BITMASK_T uint64_t

// Dynamic memory is subdivided into regions, in the format

// <size:uint32_t> ..... <size:uint32_t> | <size:uint32_t> ..... <size:uint32_t> | <size:uint32_t> ..... <size:uint32_t> | .....

// That is, at the bottom and top end of each memory region, the size of that region is stored. That allows traversing the
// memory regions backwards and forwards. Because each allocation must be at least a multiple of 4 bytes, the lowest two bits of
// each size field is unused. Free regions are distinguished from used regions by having the FREE_REGION_FLAG bit present
// in the size field. I.e. for free regions, the size field is odd, and for used regions, the size field reads even.
#define FREE_REGION_FLAG 0x1u

// Attempts to malloc() more than this many bytes would cause an overflow when calculating the size of a region,
// therefore allocations larger than this are short-circuited immediately on entry.
#define MAX_ALLOC_SIZE 0xFFFFFFC7u

// A free region has the following structure:
// <size:size_t> <prevptr> <nextptr> ... <size:size_t>

typedef struct Region {
  size_t size;
  // Use a circular doubly linked list to represent free region data.
  struct Region *prev, *next;
  // ... N bytes of free data
  size_t _at_the_end_of_this_struct_size; // do not dereference, this is present for convenient struct sizeof() computation only
} Region;

// Each memory block starts with a RootRegion at the beginning.
// The RootRegion specifies the size of the region block, and forms a linked
// list of all RootRegions in the program, starting with `listOfAllRegions`
// below.
typedef struct RootRegion {
  uint32_t size;
  struct RootRegion *next;
  uint8_t* endPtr;
} RootRegion;


#define IS_POWER_OF_2(val) (((val) & ((val)-1)) == 0)
#define ALIGN_UP(ptr, alignment) ((uint8_t*)((((uintptr_t)(ptr)) + ((alignment)-1)) & ~((alignment)-1)))
#define ALIGN_DOWN(ptr, alignment) ((uint8_t*)(((uintptr_t)(ptr)) & ~((alignment)-1)))
#define HAS_ALIGNMENT(ptr, alignment) ((((uintptr_t)(ptr)) & ((alignment)-1)) == 0)

static_assert(IS_POWER_OF_2(MALLOC_ALIGNMENT), "MALLOC_ALIGNMENT must be a power of two value!");
static_assert(MALLOC_ALIGNMENT >= 4, "Smallest possible MALLOC_ALIGNMENT if 4!");

/*
 * Note:  originally emmalloc had these as single statics. In this adaptation
 * there's an instance for each of the trio of ref types.
 */
typedef struct {
// The ref type of this context. Having it permits rctx_t pointers to know
// who they are without referring to the static array.
    nref_t refType;

// Linear memory segment from which references of this type are allocate
// Treated by the nref_sbrk series of functions - see above for details.
    segment_t segment;

// Atomic spin lock for type references to maintain address integrity
// even when invoked from multiple threads
    nref_lock_t multithreadingLock;

// A region that contains as payload a single forward linked list of pointers to
// root regions of each disjoint region blocks.
    RootRegion *listOfAllRegions;

// For each of the buckets, maintain a linked list head node. The head node for each
// free region is a sentinel node that does not actually represent any free space, but
// the sentinel is used to avoid awkward testing against (if node == freeRegionHeadNode)
// when adding and removing elements from the linked list, i.e. we are guaranteed that
// the sentinel node is always fixed and there, and the actual free region list elements
// start at freeRegionBuckets[i].next each.
    Region freeRegionBuckets[NUM_FREE_BUCKETS];

// A bitmask that tracks the population status for each of the 64 distinct memory regions:
// a zero at bit position i means that the free list bucket i is empty. This bitmask is
// used to avoid redundant scanning of the 64 different free region buckets: instead by
// looking at the bitmask we can find in constant time an index to a free region bucket
// that contains free memory of desired size.
    BUCKET_BITMASK_T freeRegionBucketsUsed;
} rctx_t;

// Governing fields for the three reference types
static rctx_t rctx[3];

// Amount of bytes taken up by allocation header data
#define REGION_HEADER_SIZE (2*sizeof(size_t))

// Smallest allocation size that is possible is 2*pointer size, since payload of each region must at least contain space
// to store the free region linked list prev and next pointers. An allocation size smaller than this will be rounded up
// to this size.
#define SMALLEST_ALLOCATION_SIZE (2*sizeof(void*))

/* Subdivide regions of free space into distinct circular doubly linked lists, where each linked list
represents a range of free space blocks. The following function compute_free_list_bucket() converts
an allocation size to the bucket index that should be looked at. The buckets are grouped as follows:

  Bucket 0: [8, 15], range size=8
  Bucket 1: [16, 23], range size=8
  Bucket 2: [24, 31], range size=8
  Bucket 3: [32, 39], range size=8
  Bucket 4: [40, 47], range size=8
  Bucket 5: [48, 55], range size=8
  Bucket 6: [56, 63], range size=8
  Bucket 7: [64, 71], range size=8
  Bucket 8: [72, 79], range size=8
  Bucket 9: [80, 87], range size=8
  Bucket 10: [88, 95], range size=8
  Bucket 11: [96, 103], range size=8
  Bucket 12: [104, 111], range size=8
  Bucket 13: [112, 119], range size=8
  Bucket 14: [120, 159], range size=40
  Bucket 15: [160, 191], range size=32
  Bucket 16: [192, 223], range size=32
  Bucket 17: [224, 255], range size=32
  Bucket 18: [256, 319], range size=64
  Bucket 19: [320, 383], range size=64
  Bucket 20: [384, 447], range size=64
  Bucket 21: [448, 511], range size=64
  Bucket 22: [512, 639], range size=128
  Bucket 23: [640, 767], range size=128
  Bucket 24: [768, 895], range size=128
  Bucket 25: [896, 1023], range size=128
  Bucket 26: [1024, 1279], range size=256
  Bucket 27: [1280, 1535], range size=256
  Bucket 28: [1536, 1791], range size=256
  Bucket 29: [1792, 2047], range size=256
  Bucket 30: [2048, 2559], range size=512
  Bucket 31: [2560, 3071], range size=512
  Bucket 32: [3072, 3583], range size=512
  Bucket 33: [3584, 6143], range size=2560
  Bucket 34: [6144, 8191], range size=2048
  Bucket 35: [8192, 12287], range size=4096
  Bucket 36: [12288, 16383], range size=4096
  Bucket 37: [16384, 24575], range size=8192
  Bucket 38: [24576, 32767], range size=8192
  Bucket 39: [32768, 49151], range size=16384
  Bucket 40: [49152, 65535], range size=16384
  Bucket 41: [65536, 98303], range size=32768
  Bucket 42: [98304, 131071], range size=32768
  Bucket 43: [131072, 196607], range size=65536
  Bucket 44: [196608, 262143], range size=65536
  Bucket 45: [262144, 393215], range size=131072
  Bucket 46: [393216, 524287], range size=131072
  Bucket 47: [524288, 786431], range size=262144
  Bucket 48: [786432, 1048575], range size=262144
  Bucket 49: [1048576, 1572863], range size=524288
  Bucket 50: [1572864, 2097151], range size=524288
  Bucket 51: [2097152, 3145727], range size=1048576
  Bucket 52: [3145728, 4194303], range size=1048576
  Bucket 53: [4194304, 6291455], range size=2097152
  Bucket 54: [6291456, 8388607], range size=2097152
  Bucket 55: [8388608, 12582911], range size=4194304
  Bucket 56: [12582912, 16777215], range size=4194304
  Bucket 57: [16777216, 25165823], range size=8388608
  Bucket 58: [25165824, 33554431], range size=8388608
  Bucket 59: [33554432, 50331647], range size=16777216
  Bucket 60: [50331648, 67108863], range size=16777216
  Bucket 61: [67108864, 100663295], range size=33554432
  Bucket 62: [100663296, 134217727], range size=33554432
  Bucket 63: 134217728 bytes and larger. */
static_assert(NUM_FREE_BUCKETS == 64, "Following function is tailored specifically for NUM_FREE_BUCKETS == 64 case");
static int compute_free_list_bucket(size_t allocSize) {
  if (allocSize < 128) return (allocSize >> 3) - 1;
  int clz = __builtin_clz(allocSize);
  int bucketIndex =
    (clz > 19)
      ?     110 - (clz<<2) + ((allocSize >> (29-clz)) ^ 4)
      : MIN( 71 - (clz<<1) + ((allocSize >> (30-clz)) ^ 2), NUM_FREE_BUCKETS-1);

  assert(bucketIndex >= 0);
  assert(bucketIndex < NUM_FREE_BUCKETS);
  return bucketIndex;
}

#define DECODE_CEILING_SIZE(size) ((size_t)((size) & ~FREE_REGION_FLAG))

static Region *prev_region(Region *region) {
  size_t prevRegionSize = ((size_t*)region)[-1];
  prevRegionSize = DECODE_CEILING_SIZE(prevRegionSize);
  return (Region*)((uint8_t*)region - prevRegionSize);
}

static Region *next_region(Region *region) {
  return (Region*)((uint8_t*)region + region->size);
}

static size_t region_ceiling_size(Region *region) {
  return ((size_t*)((uint8_t*)region + region->size))[-1];
}

static bool region_is_free(Region *r) {
  return region_ceiling_size(r) & FREE_REGION_FLAG;
}

static bool region_is_in_use(Region *r) {
  return r->size == region_ceiling_size(r);
}

static size_t size_of_region_from_ceiling(Region *r) {
  size_t size = region_ceiling_size(r);
  return DECODE_CEILING_SIZE(size);
}

static bool debug_region_is_consistent(Region *r) {
  assert(r);
  size_t sizeAtBottom = r->size;
  size_t sizeAtCeiling = size_of_region_from_ceiling(r);
  return sizeAtBottom == sizeAtCeiling;
}

static uint8_t *region_payload_start_ptr(Region *region) {
  return (uint8_t*)region + sizeof(size_t);
}

static uint8_t *region_payload_end_ptr(Region *region) {
  return (uint8_t*)region + region->size - sizeof(size_t);
}

static void create_used_region(void *ptr, size_t size) {
  assert(ptr);
  assert(HAS_ALIGNMENT(ptr, sizeof(size_t)));
  assert(HAS_ALIGNMENT(size, sizeof(size_t)));
  assert(size >= sizeof(Region));
  *(size_t*)ptr = size;
  ((size_t*)ptr)[(size/sizeof(size_t))-1] = size;
}

static void create_free_region(void *ptr, size_t size) {
  assert(ptr);
  assert(HAS_ALIGNMENT(ptr, sizeof(size_t)));
  assert(HAS_ALIGNMENT(size, sizeof(size_t)));
  assert(size >= sizeof(Region));
  Region *freeRegion = (Region*)ptr;
  freeRegion->size = size;
  ((size_t*)ptr)[(size/sizeof(size_t))-1] = size | FREE_REGION_FLAG;
}

static void prepend_to_free_list(Region *region, Region *prependTo) {
  assert(region);
  assert(prependTo);
  // N.b. the region we are prepending to is always the sentinel node,
  // which represents a dummy node that is technically not a free node, so
  // region_is_free(prependTo) does not hold.
  assert(region_is_free((Region*)region));
  region->next = prependTo;
  region->prev = prependTo->prev;
  assert(region->prev);
  prependTo->prev = region;
  region->prev->next = region;
}

static void unlink_from_free_list(Region *region) {
  assert(region);
  assert(region_is_free((Region*)region));
  assert(region->prev);
  assert(region->next);
  region->prev->next = region->next;
  region->next->prev = region->prev;
}

static void link_to_free_list(Region *freeRegion, rctx_t *ctx) {
  assert(freeRegion);
  assert(freeRegion->size >= sizeof(Region));
  int bucketIndex = compute_free_list_bucket(freeRegion->size-REGION_HEADER_SIZE);
  Region *freeListHead = ctx->freeRegionBuckets + bucketIndex;
  freeRegion->prev = freeListHead;
  freeRegion->next = freeListHead->next;
  assert(freeRegion->next);
  freeListHead->next = freeRegion;
  freeRegion->next->prev = freeRegion;
  ctx->freeRegionBucketsUsed |= ((BUCKET_BITMASK_T)1) << bucketIndex;
}

static void dump_memory_regions(rctx_t *ctx) {
  ASSERT_MALLOC_IS_ACQUIRED(ctx->refType);
  RootRegion *root = ctx->listOfAllRegions;
  nref_diag_stow("All memory regions refType %d:", ctx->refType);
  while (root) {
    Region *r = (Region*)root;
    assert(debug_region_is_consistent(r));
    uint8_t *lastRegionEnd = root->endPtr;
    nref_diag_stow("Region block %p - %p (%ld bytes):",
      r, lastRegionEnd, lastRegionEnd-(uint8_t*)r);
    while ((uint8_t*)r < lastRegionEnd) {
      nref_diag_stow("Region %p, size: %zu used/--FREE-- = %d",
        r, r->size, region_ceiling_size(r) == r->size);

      assert(debug_region_is_consistent(r));
      size_t sizeFromCeiling = size_of_region_from_ceiling(r);
      if (sizeFromCeiling != r->size) {
        nref_diag_stow("Corrupt region! Size marker at the end of the region does not match: %zu", sizeFromCeiling);
      }
      if (r->size == 0) {
        break;
      }
      r = next_region(r);
    }
    root = root->next;
    nref_diag_stow(" ");
  }
  nref_diag_stow("Free regions:");
  for (int i = 0; i < NUM_FREE_BUCKETS; ++i) {
    Region *prev = &ctx->freeRegionBuckets[i];
    Region *fr = ctx->freeRegionBuckets[i].next;
    while (fr != &ctx->freeRegionBuckets[i]) {
      nref_diag_stow("In bucket %d, free region %p, size: %zu (size at ceiling: %zu), prev: %p, next: %p)",
        i, fr, fr->size, size_of_region_from_ceiling(fr), fr->prev, fr->next);
      assert(debug_region_is_consistent(fr));
      assert(region_is_free(fr));
      assert(fr->prev == prev);
      prev = fr;
      assert(fr->next != fr);
      assert(fr->prev != fr);
      fr = fr->next;
    }
  }
  nref_diag_stow("Free bucket index map: %d %d", (uint32_t)(ctx->freeRegionBucketsUsed >> 32), (uint32_t)ctx->freeRegionBucketsUsed);
  nref_diag_stow(" ");
}

void nref_dump_memory_regions(nref_t ref) {
  MALLOC_ACQUIRE(ref);
  dump_memory_regions(&rctx[ref]);
  MALLOC_RELEASE(ref);
}

static int validate_memory_regions(rctx_t *ctx) {
  ASSERT_MALLOC_IS_ACQUIRED(ctx->refType);
  RootRegion *root = ctx->listOfAllRegions;
  while (root) {
    Region *r = (Region*)root;
    if (!debug_region_is_consistent(r)) {
      nref_diag_stow("Used region %p, size: %zu used/--FREE-- =%d is corrupt (size markers in the beginning and at the end of the region do not match!)",
        r, r->size, region_ceiling_size(r) == r->size);
      return 1;
    }
    uint8_t *lastRegionEnd = root->endPtr;
    while ((uint8_t*)r < lastRegionEnd) {
      if (!debug_region_is_consistent(r)) {
        nref_diag_stow("Used region %p, size: %zu used/--FREE-- = %d is corrupt (size markers in the beginning and at the end of the region do not match!)",
          r, r->size, region_ceiling_size(r) == r->size);
        return 1;
      }
      if (r->size == 0) {
        break;
      }
      r = next_region(r);
    }
    root = root->next;
  }
  for (int i = 0; i < NUM_FREE_BUCKETS; ++i) {
    Region *prev = &ctx->freeRegionBuckets[i];
    Region *fr = ctx->freeRegionBuckets[i].next;
    while (fr != &ctx->freeRegionBuckets[i]) {
      if (!debug_region_is_consistent(fr) || !region_is_free(fr) || fr->prev != prev || fr->next == fr || fr->prev == fr) {
        nref_diag_stow("In bucket %d, free region %p, size: %zu (size at ceiling: %zu), prev: %p, next: %p is corrupt!",
          i, fr, fr->size, size_of_region_from_ceiling(fr), fr->prev, fr->next);
        return 1;
      }
      prev = fr;
      fr = fr->next;
    }
  }
  return 0;
}

int nref_validate_memory_regions(nref_t ref) {
  MALLOC_ACQUIRE(ref);
  int memoryError = validate_memory_regions(&rctx[ref]);
  MALLOC_RELEASE(ref);
  return memoryError;
}

static bool claim_more_memory(size_t numBytes, rctx_t *ctx) {
#ifdef EMMALLOC_VERBOSE
  nref_diag_stow("claim_more_memory(numBytes=%zu, refType=%d)", numBytes, ctx->refType);
#endif

#ifdef EMMALLOC_MEMVALIDATE
  validate_memory_regions(ctx);
#endif

  // Make sure we always send sbrk requests with the same alignment that sbrk()
  // allocates memory at. Otherwise we will not properly interpret returned memory
  // to form a seamlessly contiguous region with earlier root regions, which would
  // lead to inefficiently treating the sbrk()ed region to be a new disjoint root
  // region.
  numBytes = (size_t)ALIGN_UP(numBytes, MALLOC_ALIGNMENT);

  // Claim memory via sbrk
  assert((int64_t)numBytes >= 0);
  uint8_t *startPtr = (uint8_t*)nref_sbrk_vary((intptr_t)numBytes, &ctx->segment);
  if ((intptr_t)startPtr == -1) {
#ifdef EMMALLOC_VERBOSE
    nref_diag_stow("claim_more_memory: sbrk failed!");
#endif
    return false;
  }
#ifdef EMMALLOC_VERBOSE
  nref_diag_stow("claim_more_memory: claimed %p - %p (%zu bytes) via sbrk()", startPtr, startPtr + numBytes, numBytes);
#endif
  assert(HAS_ALIGNMENT(startPtr, alignof(size_t)));
  uint8_t *endPtr = startPtr + numBytes;

  // Create a sentinel region at the end of the new heap block
  Region *endSentinelRegion = (Region*)(endPtr - sizeof(Region));
  create_used_region(endSentinelRegion, sizeof(Region));
#ifdef EMMALLOC_VERBOSE
  nref_diag_stow("claim_more_memory: created a sentinel memory region at address %p", endSentinelRegion);
#endif

  // If we are the sole user of sbrk(), it will feed us continuous/consecutive memory addresses - take advantage
  // of that if so: instead of creating two disjoint memory regions blocks, expand the previous one to a larger size.
  uint8_t *previousSbrkEndAddress = ctx->listOfAllRegions ? ctx->listOfAllRegions->endPtr : 0;
  if (startPtr == previousSbrkEndAddress) {
#ifdef EMMALLOC_VERBOSE
    nref_diag_stow("claim_more_memory: sbrk() returned a region contiguous to last root region, expanding the existing root region");
#endif
    Region *prevEndSentinel = prev_region((Region*)startPtr);
    assert(debug_region_is_consistent(prevEndSentinel));
    assert(region_is_in_use(prevEndSentinel));
    Region *prevRegion = prev_region(prevEndSentinel);
    assert(debug_region_is_consistent(prevRegion));

    ctx->listOfAllRegions->endPtr = endPtr;

    // Two scenarios, either the last region of the previous block was in use, in which case we need to create
    // a new free region in the newly allocated space; or it was free, in which case we can extend that region
    // to cover a larger size.
    if (region_is_free(prevRegion)) {
      size_t newFreeRegionSize = (uint8_t*)endSentinelRegion - (uint8_t*)prevRegion;
      unlink_from_free_list(prevRegion);
      create_free_region(prevRegion, newFreeRegionSize);
      link_to_free_list(prevRegion, ctx);
      return true;
    }
    // else: last region of the previous block was in use. Since we are joining two consecutive sbrk() blocks,
    // we can swallow the end sentinel of the previous block away.
    startPtr -= sizeof(Region);
  } else {
    // Unfortunately some other user has sbrk()ed to acquire a slab of memory for themselves, and now the sbrk()ed
    // memory we got is not contiguous with our previous managed root regions.
    // So create a new root region at the start of the sbrk()ed heap block.
#ifdef EMMALLOC_VERBOSE
    nref_diag_stow("claim_more_memory: sbrk() returned a disjoint region to last root region, some external code must have sbrk()ed outside emmalloc(). Creating a new root region");
#endif
    create_used_region(startPtr, sizeof(Region));

    // Dynamic heap start region:
    RootRegion *newRegionBlock = (RootRegion*)startPtr;
    newRegionBlock->next = ctx->listOfAllRegions; // Pointer to next region block head
    newRegionBlock->endPtr = endPtr; // Pointer to the end address of this region block
    ctx->listOfAllRegions = newRegionBlock;
    startPtr += sizeof(Region);
  }

  // Create a new memory region for the new claimed free space.
  create_free_region(startPtr, (uint8_t*)endSentinelRegion - startPtr);
  link_to_free_list((Region*)startPtr, ctx);
  return true;
}


void nref_from_orbit() {
  nref_t ref;

  nref_diag_init();
  for (ref = Virtual; ref <= Traced; ref++) {
    MALLOC_ACQUIRE(ref);

    rctx[ref].refType = ref;
    
    rctx[ref].segment.defined = false;
    rctx[ref].segment.heapSize = 0;
    rctx[ref].segment.heapAddr = NULL;
    rctx[ref].segment.brkCurr = 0;
    rctx[ref].segment.brkAddr = NULL;

    atomic_flag_clear(&rctx[ref].multithreadingLock.flag);
    rctx[ref].multithreadingLock.value = 0;

    rctx[ref].listOfAllRegions = NULL;
    // Initialize circular doubly linked lists representing free space
    // Never useful to unroll this for loop, just takes up code size.
#pragma clang loop unroll(disable)
    for (int i = 0; i < NUM_FREE_BUCKETS; ++i) {
      rctx[ref].freeRegionBuckets[i].prev = rctx[ref].freeRegionBuckets[i].next = &rctx[ref].freeRegionBuckets[i];
    }
    rctx[ref].freeRegionBucketsUsed = 0;

    MALLOC_RELEASE(ref);
  }

  // the 'Virtual' nref doesn't have a pre-defined size
  // if this assumption wasn't made, it could though. option to consider
  nref_define(0, Virtual);
}

// Pre-allocate a buffer for the given nref type. When numBytes
// is zero, there's no pre-allocation: segment extends via sbrk.
// The 'Virtual' segment must do this.
//
// For segments that can be pre-defined, their buffer is bootstrapped
// from the Virtual segment, or they too fall back to sbrk.
//
int nref_define(size_t numBytes, nref_t ref) {
    void *addr = NULL;
    assert(rctx[ref].segment.defined == false);

    nref_diag_stow("nref_define refType=%d numBytes=%ld", ref, numBytes);

    MALLOC_ACQUIRE(ref);
    if (ref == Virtual) {
        assert(numBytes == 0);
        nref_sbrk_init(addr, numBytes, &rctx[ref].segment);
    } else {
        assert(rctx[Virtual].segment.defined == true);
        if (numBytes) {
            // pull a segment out of virtual memory
            addr = nref_malloc(numBytes, Virtual);
            assert(addr);
        }
        nref_sbrk_init(addr, numBytes, &rctx[ref].segment);
    }

    // Start with a tiny dynamic region.
    claim_more_memory(3*sizeof(Region), &rctx[ref]);
    MALLOC_RELEASE(ref);
}


static void *attempt_allocate(Region *freeRegion, size_t alignment, size_t size, rctx_t *ctx) {
  ASSERT_MALLOC_IS_ACQUIRED(ctx->refType);

#ifdef EMMALLOC_VERBOSE
  nref_diag_stow("attempt_allocate(freeRegion=%p,alignment=%zu, size=%zu, refType=%d", freeRegion, alignment, size, ctx->refType);
#endif

  assert(freeRegion);
  // Look at the next potential free region to allocate into.
  // First, we should check if the free region has enough of payload bytes contained
  // in it to accommodate the new allocation. This check needs to take into account the
  // requested allocation alignment, so the payload memory area needs to be rounded
  // upwards to the desired alignment.
  uint8_t *payloadStartPtr = region_payload_start_ptr(freeRegion);
  uint8_t *payloadStartPtrAligned = ALIGN_UP(payloadStartPtr, alignment);
  uint8_t *payloadEndPtr = region_payload_end_ptr(freeRegion);

  // Do we have enough free space, taking into account alignment?
  if (payloadStartPtrAligned + size > payloadEndPtr) {
    return NULL;
  }

  // We have enough free space, so the memory allocation will be made into this region. Remove this free region
  // from the list of free regions: whatever slop remains will be later added back to the free region pool.
  unlink_from_free_list(freeRegion);

  // Before we proceed further, fix up the boundary between this and the preceding region,
  // so that the boundary between the two regions happens at a right spot for the payload to be aligned.
  if (payloadStartPtr != payloadStartPtrAligned) {
    Region *prevRegion = prev_region((Region*)freeRegion);
    // We never have two free regions adjacent to each other, so the region before this free
    // region should be in use.
    assert(region_is_in_use(prevRegion));
    size_t regionBoundaryBumpAmount = payloadStartPtrAligned - payloadStartPtr;
    size_t newThisRegionSize = freeRegion->size - regionBoundaryBumpAmount;
    create_used_region(prevRegion, prevRegion->size + regionBoundaryBumpAmount);
    freeRegion = (Region *)((uint8_t*)freeRegion + regionBoundaryBumpAmount);
    freeRegion->size = newThisRegionSize;
  }
  // Next, we need to decide whether this region is so large that it should be split into two regions,
  // one representing the newly used memory area, and at the high end a remaining leftover free area.
  // This splitting to two is done always if there is enough space for the high end to fit a region.
  // Carve 'size' bytes of payload off this region. So,
  // [sz prev next sz]
  // becomes
  // [sz payload sz] [sz prev next sz]
  if (sizeof(Region) + REGION_HEADER_SIZE + size <= freeRegion->size) {
    // There is enough space to keep a free region at the end of the carved out block
    // -> construct the new block
    Region *newFreeRegion = (Region *)((uint8_t*)freeRegion + REGION_HEADER_SIZE + size);
    create_free_region(newFreeRegion, freeRegion->size - size - REGION_HEADER_SIZE);
    link_to_free_list(newFreeRegion, ctx);

    // Recreate the resized Region under its new size.
    create_used_region(freeRegion, size + REGION_HEADER_SIZE);
  } else {
    // There is not enough space to split the free memory region into used+free parts, so consume the whole
    // region as used memory, not leaving a free memory region behind.
    // Initialize the free region as used by resetting the ceiling size to the same value as the size at bottom.
    ((size_t*)((uint8_t*)freeRegion + freeRegion->size))[-1] = freeRegion->size;
  }


#ifdef EMMALLOC_VERBOSE
  nref_diag_stow("attempt_allocate - succeeded allocating memory, region ptr=%p, align=%zu, payload size=%zu bytes)", freeRegion, alignment, size);
#endif

  return (uint8_t*)freeRegion + sizeof(size_t);
}

static size_t validate_alloc_alignment(size_t alignment) {
  // Cannot perform allocations that are less than our minimal alignment, because
  // the Region control structures need to be aligned themselves.
  return MAX(alignment, MALLOC_ALIGNMENT);
}

static size_t validate_alloc_size(size_t size) {
  assert(size + REGION_HEADER_SIZE > size);

  // Allocation sizes must be a multiple of pointer sizes, and at least 2*sizeof(pointer).
  size_t validatedSize = size > SMALLEST_ALLOCATION_SIZE ? (size_t)ALIGN_UP(size, sizeof(Region*)) : SMALLEST_ALLOCATION_SIZE;
  assert(validatedSize >= size); // 32-bit wraparound should not occur, too large sizes should be stopped before

  return validatedSize;
}

static void *allocate_memory(size_t alignment, size_t size, rctx_t *ctx) {
  ASSERT_MALLOC_IS_ACQUIRED(ctx->refType);

#ifdef EMMALLOC_VERBOSE
  nref_diag_stow("allocate_memory(align=%zu, size=%zu bytes, refType=%d)", alignment, size, ctx->refType);
#endif

#ifdef EMMALLOC_MEMVALIDATE
  validate_memory_regions(ctx);
#endif

  if (!IS_POWER_OF_2(alignment)) {
#ifdef EMMALLOC_VERBOSE
    nref_diag_stow("Allocation failed: alignment not power of 2!");
#endif
    return 0;
  }

  if (size > MAX_ALLOC_SIZE) {
#ifdef EMMALLOC_VERBOSE
    nref_diag_stow("Allocation failed: attempted allocation size is too large: %zu bytes! (negative integer wraparound?)", size);
#endif
    return 0;
  }

  alignment = validate_alloc_alignment(alignment);
  size = validate_alloc_size(size);

  // Attempt to allocate memory starting from smallest bucket that can contain the required amount of memory.
  // Under normal alignment conditions this should always be the first or second bucket we look at, but if
  // performing an allocation with complex alignment, we may need to look at multiple buckets.
  int bucketIndex = compute_free_list_bucket(size);
  BUCKET_BITMASK_T bucketMask = ctx->freeRegionBucketsUsed >> bucketIndex;

  // Loop through each bucket that has free regions in it, based on bits set in freeRegionBucketsUsed bitmap.
  while (bucketMask) {
    BUCKET_BITMASK_T indexAdd = __builtin_ctzll(bucketMask);
    bucketIndex += indexAdd;
    bucketMask >>= indexAdd;
    assert(bucketIndex >= 0);
    assert(bucketIndex <= NUM_FREE_BUCKETS-1);
    assert(ctx->freeRegionBucketsUsed & (((BUCKET_BITMASK_T)1) << bucketIndex));

    Region *freeRegion = ctx->freeRegionBuckets[bucketIndex].next;
    assert(freeRegion);
    if (freeRegion != &ctx->freeRegionBuckets[bucketIndex]) {
      void *ptr = attempt_allocate(freeRegion, alignment, size, ctx);
      if (ptr) {
        return ptr;
      }

      // We were not able to allocate from the first region found in this bucket, so penalize
      // the region by cycling it to the end of the doubly circular linked list. (constant time)
      // This provides a randomized guarantee that when performing allocations of size k to a
      // bucket of [k-something, k+something] range, we will not always attempt to satisfy the
      // allocation from the same available region at the front of the list, but we try each
      // region in turn.
      unlink_from_free_list(freeRegion);
      prepend_to_free_list(freeRegion, &ctx->freeRegionBuckets[bucketIndex]);
      // But do not stick around to attempt to look at other regions in this bucket - move
      // to search the next populated bucket index if this did not fit. This gives a practical
      // "allocation in constant time" guarantee, since the next higher bucket will only have
      // regions that are all of strictly larger size than the requested allocation. Only if
      // there is a difficult alignment requirement we may fail to perform the allocation from
      // a region in the next bucket, and if so, we keep trying higher buckets until one of them
      // works.
      ++bucketIndex;
      bucketMask >>= 1;
    } else {
      // This bucket was not populated after all with any regions,
      // but we just had a stale bit set to mark a populated bucket.
      // Reset the bit to update latest status so that we do not
      // redundantly look at this bucket again.
      ctx->freeRegionBucketsUsed &= ~(((BUCKET_BITMASK_T)1) << bucketIndex);
      bucketMask ^= 1;
    }
    // Instead of recomputing bucketMask from scratch at the end of each loop, it is updated as we go,
    // to avoid undefined behavior with (x >> 32)/(x >> 64) when bucketIndex reaches 32/64, (the shift would come out as a no-op instead of 0).
    assert((bucketIndex == NUM_FREE_BUCKETS && bucketMask == 0) || (bucketMask == ctx->freeRegionBucketsUsed >> bucketIndex));
  }

  // None of the buckets were able to accommodate an allocation. If this happens we are almost out of memory.
  // The largest bucket might contain some suitable regions, but we only looked at one region in that bucket, so
  // as a last resort, loop through more free regions in the bucket that represents the largest allocations available.
  // But only if the bucket representing largest allocations available is not any of the first thirty buckets,
  // these represent allocatable areas less than <1024 bytes - which could be a lot of scrap.
  // In such case, prefer to sbrk() in more memory right away.
  int largestBucketIndex = NUM_FREE_BUCKETS - 1 - __builtin_clzll(ctx->freeRegionBucketsUsed);
  // freeRegion will be null if there is absolutely no memory left. (all buckets are 100% used)
  Region *freeRegion = ctx->freeRegionBucketsUsed ? ctx->freeRegionBuckets[largestBucketIndex].next : 0;
  // The 30 first free region buckets cover memory blocks < 2048 bytes, so skip looking at those here (too small)
  if (ctx->freeRegionBucketsUsed >> 30) {
    // Look only at a constant number of regions in this bucket max, to avoid bad worst case behavior.
    // If this many regions cannot find free space, we give up and prefer to sbrk() more instead.
    const int maxRegionsToTryBeforeGivingUp = 99;
    int numTriesLeft = maxRegionsToTryBeforeGivingUp;
    while (freeRegion != &ctx->freeRegionBuckets[largestBucketIndex] && numTriesLeft-- > 0) {
      void *ptr = attempt_allocate(freeRegion, alignment, size, ctx);
      if (ptr) {
        return ptr;
      }
      freeRegion = freeRegion->next;
    }
  }

  // We were unable to find a free memory region. Must sbrk() in more memory!
  size_t numBytesToClaim = size+sizeof(Region)*3;
  // Take into account the alignment as well. For typical alignment we don't
  // need to add anything here (so we do nothing if the alignment is equal to
  // MALLOC_ALIGNMENT), but it can matter if the alignment is very high. In that
  // case, not adding the alignment can lead to this sbrk not giving us enough
  // (in which case, the next attempt fails and will sbrk the same amount again,
  // potentially allocating a lot more memory than necessary).
  //
  // Note that this is not necessarily optimal, as the extra allocation size for
  // the alignment might not be needed (if we are lucky and already aligned),
  // and even if it helps us allocate it will not immediately be ready for reuse
  // (as it will be added to the currently-in-use region before us, so it is not
  // in a free list). As a compromise however it seems reasonable in practice as
  // a way to handle large aligned regions to avoid even worse waste.
  if (alignment > MALLOC_ALIGNMENT) {
    numBytesToClaim += alignment;
  }
  assert(numBytesToClaim > size); // 32-bit wraparound should not happen here, allocation size has been validated above!
  bool success = claim_more_memory(numBytesToClaim, ctx);
  if (success) {
    // Recurse back to itself to try again
    return allocate_memory(alignment, size, ctx);
  }

  // also sbrk() failed, we are really really constrained :( As a last resort, go back to looking at the
  // bucket we already looked at above, continuing where the above search left off - perhaps there are
  // regions we overlooked the first time that might be able to satisfy the allocation.
  if (freeRegion) {
    while (freeRegion != &ctx->freeRegionBuckets[largestBucketIndex]) {
      void *ptr = attempt_allocate(freeRegion, alignment, size, ctx);
      if (ptr) {
        return ptr;
      }
      freeRegion = freeRegion->next;
    }
  }

#ifdef EMMALLOC_VERBOSE
  nref_diag_stow("Could not find a free memory block!");
#endif

  return 0;
}

void *emmalloc_memalign(size_t alignment, size_t size, nref_t ref) {
  rctx_t *ctx = &rctx[ref];
  assert(ctx->segment.defined);

  MALLOC_ACQUIRE(ref);
  void *ptr = allocate_memory(alignment, size, ctx);
  MALLOC_RELEASE(ref);
  return ptr;
}

void *nref_malloc(size_t size, nref_t ref) {
  return emmalloc_memalign(MALLOC_ALIGNMENT, size, ref);
}

void nref_free(void *ptr, nref_t ref) {
  rctx_t *ctx = &rctx[ref];
  assert(ctx->segment.defined);

#ifdef EMMALLOC_MEMVALIDATE
  nref_validate_memory_regions(ref);
#endif

  if (!ptr) {
    return;
  }

#ifdef EMMALLOC_VERBOSE
  nref_diag_stow("free(ptr=%p,refType=%d)", ptr, ref);
#endif

  uint8_t *regionStartPtr = (uint8_t*)ptr - sizeof(size_t);
  Region *region = (Region*)(regionStartPtr);
  assert(HAS_ALIGNMENT(region, sizeof(size_t)));

  MALLOC_ACQUIRE(ref);

  size_t size = region->size;
#ifdef EMMALLOC_VERBOSE
  if (size < sizeof(Region) || !region_is_in_use(region)) {
    if (debug_region_is_consistent(region)) {
      // LLVM wasm backend bug: cannot use nref_diag_stow() here, that generates internal compiler error
      // Reproducible by running e.g. other.test_alloc_3GB
      nref_diag_stow("Double free at region ptr %p, region->size: %p, region->sizeAtCeiling: %p", region, size, region_ceiling_size(region));
    } else {
      nref_diag_stow("Corrupt region at region ptr %p region->size: %p, region->sizeAtCeiling: %p", region, size, region_ceiling_size(region));
    }
  }
#endif
  assert(size >= sizeof(Region));
  assert(region_is_in_use(region));


  // Check merging with left side
  size_t prevRegionSizeField = ((size_t*)region)[-1];
  size_t prevRegionSize = prevRegionSizeField & ~FREE_REGION_FLAG;
  if (prevRegionSizeField != prevRegionSize) { // Previous region is free?
    Region *prevRegion = (Region*)((uint8_t*)region - prevRegionSize);
    assert(debug_region_is_consistent(prevRegion));
    unlink_from_free_list(prevRegion);
    regionStartPtr = (uint8_t*)prevRegion;
    size += prevRegionSize;
  }

  // Check merging with right side
  Region *nextRegion = next_region(region);
  assert(debug_region_is_consistent(nextRegion));
  size_t sizeAtEnd = *(size_t*)region_payload_end_ptr(nextRegion);
  if (nextRegion->size != sizeAtEnd) {
    unlink_from_free_list(nextRegion);
    size += nextRegion->size;
  }

  create_free_region(regionStartPtr, size);
  link_to_free_list((Region*)regionStartPtr, ctx);

  MALLOC_RELEASE(ref);

#ifdef EMMALLOC_MEMVALIDATE
  nref_validate_memory_regions(ref);
#endif
}

void *nref_calloc(size_t num, size_t size, nref_t ref) {
  size_t bytes = num*size;
  void *ptr = emmalloc_memalign(MALLOC_ALIGNMENT, bytes, ref);
  if (ptr) {
    memset(ptr, 0, bytes);
  }
  return ptr;
}

static int count_linked_list_size(Region *list) {
  int size = 1;
  for (Region *i = list->next; i != list; list = list->next) {
    ++size;
  }
  return size;
}

static size_t count_linked_list_space(Region *list) {
  size_t space = 0;
  for (Region *i = list->next; i != list; list = list->next) {
    space += region_payload_end_ptr(i) - region_payload_start_ptr(i);
  }
  return space;
}

struct mallinfo nref_mallinfo(nref_t ref) {
  int64_t max, cur;
  rctx_t *ctx = &rctx[ref];

  MALLOC_ACQUIRE(ref);

  struct mallinfo info;
  // Non-mmapped space allocated (bytes): For emmalloc,
  // let's define this as the difference between heap size and dynamic top end.
  nref_sbrk_stat(&max, &cur, &ctx->segment);
  info.arena = max - cur;
  // info.arena = emscripten_get_heap_size() - (size_t)nref_sbrk_vary(0);
  // Number of "ordinary" blocks. Let's define this as the number of highest
  // size blocks. (subtract one from each, since there is a sentinel node in each list)
  info.ordblks = count_linked_list_size(&ctx->freeRegionBuckets[NUM_FREE_BUCKETS-1])-1;
  // Number of free "fastbin" blocks. For emmalloc, define this as the number
  // of blocks that are not in the largest pristine block.
  info.smblks = 0;
  // The total number of bytes in free "fastbin" blocks.
  info.fsmblks = 0;
  for (int i = 0; i < NUM_FREE_BUCKETS-1; ++i) {
    info.smblks += count_linked_list_size(&ctx->freeRegionBuckets[i])-1;
    info.fsmblks += count_linked_list_space(&ctx->freeRegionBuckets[i]);
  }

  info.hblks = 0; // Number of mmapped regions: always 0. (no mmap support)
  info.hblkhd = 0; // Amount of bytes in mmapped regions: always 0. (no mmap support)

  // Walk through all the heap blocks to report the following data:
  // The "highwater mark" for allocated space—that is, the maximum amount of
  // space that was ever allocated. Emmalloc does not want to pay code to
  // track this, so this is only reported from current allocation data, and
  // may not be accurate.
  info.usmblks = 0;
  info.uordblks = 0; // The total number of bytes used by in-use allocations.
  info.fordblks = 0; // The total number of bytes in free blocks.
  // The total amount of releasable free space at the top of the heap.
  // This is the maximum number of bytes that could ideally be released by malloc_trim(3).
  Region *lastActualRegion = prev_region((Region*)(ctx->listOfAllRegions->endPtr - sizeof(Region)));
  info.keepcost = region_is_free(lastActualRegion) ? lastActualRegion->size : 0;

  RootRegion *root = ctx->listOfAllRegions;
  while (root) {
    Region *r = (Region*)root;
    assert(debug_region_is_consistent(r));
    uint8_t *lastRegionEnd = root->endPtr;
    while ((uint8_t*)r < lastRegionEnd) {
      assert(debug_region_is_consistent(r));

      if (region_is_free(r)) {
        // Count only the payload of the free block towards free memory.
        info.fordblks += region_payload_end_ptr(r) - region_payload_start_ptr(r);
        // But the header data of the free block goes towards used memory.
        info.uordblks += REGION_HEADER_SIZE;
      } else {
        info.uordblks += r->size;
      }
      // Update approximate watermark data
      info.usmblks = MAX(info.usmblks, (intptr_t)r + r->size);

      if (r->size == 0) {
        break;
      }
      r = next_region(r);
    }
    root = root->next;
  }

  MALLOC_RELEASE(ref);
  return info;
}


size_t nref_dynamic_heap_size(nref_t ref) {
  rctx_t *ctx = &rctx[ref];
  size_t dynamicHeapSize = 0;

  MALLOC_ACQUIRE(ref);
  RootRegion *root = ctx->listOfAllRegions;
  while (root) {
    dynamicHeapSize += root->endPtr - (uint8_t*)root;
    root = root->next;
  }
  MALLOC_RELEASE(ref);
  return dynamicHeapSize;
}

size_t nref_free_dynamic_memory(nref_t ref) {
  rctx_t *ctx = &rctx[ref];
  size_t freeDynamicMemory = 0;

  int bucketIndex = 0;

  MALLOC_ACQUIRE(ref);
  BUCKET_BITMASK_T bucketMask = ctx->freeRegionBucketsUsed;

  // Loop through each bucket that has free regions in it, based on bits set in freeRegionBucketsUsed bitmap.
  while (bucketMask) {
    BUCKET_BITMASK_T indexAdd = __builtin_ctzll(bucketMask);
    bucketIndex += indexAdd;
    bucketMask >>= indexAdd;
    for (Region *freeRegion = ctx->freeRegionBuckets[bucketIndex].next;
         freeRegion != &ctx->freeRegionBuckets[bucketIndex];
         freeRegion = freeRegion->next) {
      freeDynamicMemory += freeRegion->size - REGION_HEADER_SIZE;
    }
    ++bucketIndex;
    bucketMask >>= 1;
  }
  MALLOC_RELEASE(ref);
  return freeDynamicMemory;
}

size_t emmalloc_compute_free_dynamic_memory_fragmentation_map(size_t freeMemorySizeMap[32], rctx_t *ctx) {
  memset((void*)freeMemorySizeMap, 0, sizeof(freeMemorySizeMap[0])*32);

  size_t numFreeMemoryRegions = 0;
  int bucketIndex = 0;
  MALLOC_ACQUIRE(ctx->refType);
  BUCKET_BITMASK_T bucketMask = ctx->freeRegionBucketsUsed;

  // Loop through each bucket that has free regions in it, based on bits set in freeRegionBucketsUsed bitmap.
  while (bucketMask) {
    BUCKET_BITMASK_T indexAdd = __builtin_ctzll(bucketMask);
    bucketIndex += indexAdd;
    bucketMask >>= indexAdd;
    for (Region *freeRegion = ctx->freeRegionBuckets[bucketIndex].next;
         freeRegion != &ctx->freeRegionBuckets[bucketIndex];
         freeRegion = freeRegion->next) {
      ++numFreeMemoryRegions;
      size_t freeDynamicMemory = freeRegion->size - REGION_HEADER_SIZE;
      if (freeDynamicMemory > 0) {
        ++freeMemorySizeMap[31-__builtin_clz(freeDynamicMemory)];
      } else {
        ++freeMemorySizeMap[0];
      }
    }
    ++bucketIndex;
    bucketMask >>= 1;
  }
  MALLOC_RELEASE(ctx->refType);
  return numFreeMemoryRegions;
}

void nref_dump_free_dynamic_memory_fragmentation_map(nref_t ref) {
  rctx_t *ctx = &rctx[ref];
  size_t freeMemorySizeMap[32];
  size_t numFreeMemoryRegions = emmalloc_compute_free_dynamic_memory_fragmentation_map(freeMemorySizeMap, ctx);
  nref_diag_stow("numFreeMemoryRegions: %zu, refType=%d", numFreeMemoryRegions, ref);
  for (int i = 0; i < 32; ++i) {
    nref_diag_stow("Free memory regions of size [%llu,%llu[ bytes: %zu regions", 1ull<<i, 1ull<<(i+1), freeMemorySizeMap[i]);
  }
}
