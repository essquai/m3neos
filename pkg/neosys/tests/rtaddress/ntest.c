#include "nref.h"

#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>
#include <stdint.h>
#include <pthread.h>

/* tracking */
static float test = 0.0;
static float pass = 0.0;
bool diagnostic = false;

void record(char *name, bool passed) {
   if (passed) {
     printf("%20s : pass\n", name);
     pass += 1.0;
   } else {
     printf("%20s : fail\n", name);
   }
   test += 1.0;
}

void summary() {
    if (test < 1.0) test = 1.0;
    printf("%16s : %.0f\n",   "**** cases ****", test);
    printf("%16s : %.1f%%\n", "**** score ****", pass*100.0/test );
}

/* test heap */
#define KB 1024
static char heap[2 * KB * KB];

/* allocated memory */
#define SEQ_MAX    128
#define SPAWN_MAX  256
#define ADDR_MAX   4096
static void *addr[ADDR_MAX];

typedef struct {
    int  num;
    int  cycle;
    int  seq;
    int  kilo;
    bool result;
} spawn_param_t;

uint8_t nlist[] = { 2, 8, 16, 32, 48, 56 };

void *spawn(void *a) {
    spawn_param_t *p = a;
    void *addr[SEQ_MAX];
    bool    passed;
    char   name[128];
    int    i, j;
    nref_t ref = Untraced;
    assert (p->seq < SEQ_MAX);

    sprintf(name, "spawn[%d] cyc=%d seq=%d kb=%d", p->num, p->cycle, p->seq, p->kilo);
    passed = true;
    for (j = 0; j < p->cycle && passed; j++) {
        /* alloc */
        for (i = 0; i < p->seq && passed; i++) {
            addr[i] = nref_malloc(p->kilo * KB, ref);
            if (!addr[i]) {
              passed = false;
              printf("%s: malloc failed on %d\n", name, i);
            }
        }

        /* free  */
        for (i = 0; i < p->seq && passed; i++) {
            nref_free(addr[i], ref);
        }
    }
    if (passed) {
        if (nref_validate_memory_regions(ref) != 0) {
          passed = false;
          printf("%s: validate_memory failure\n", name);
        }
    }
    p->result = passed;
    return (a);
}

int main(int argc, char *argv[]) {
    bool    passed;
    char   *name;
    char   dyname[128];
    int     i;
    size_t  statSz, statCurr;
    void    *curBrk;
    spawn_param_t param[SPAWN_MAX];
    spawn_param_t *p;
    pthread_t     thr[SPAWN_MAX];
    int     N;
    int     n;
    nref_t  ref = Untraced;
    

    for (i = 1; i < argc; i++) {
        if (strncmp(argv[i], "-d", 2) == 0) diagnostic = true;
    }

    name = "orbit"; passed = true;
    nref_from_orbit();
    if (nref_validate_memory_regions(Virtual) == 0) passed = true;
    if (diagnostic) nref_dump_memory_regions(Virtual);
    record(name, passed);
    if (diagnostic) nref_diag_dump();

    name = "small heap (traced)"; passed = false;
    nref_define(KB, Traced);
    if (!nref_malloc(KB+sizeof(max_align_t), Traced)) passed = true;
    record(name, passed);

    name = "alloc 16K"; passed = true;
    nref_define(sizeof(heap), ref);
    for (i = 0; i < 16 && passed; i++) {
        addr[i] = nref_malloc(KB, ref);
        if (!addr[i]) passed = false;
    }
    for (i = 0; i < 16 && passed; i++) {
        nref_free(addr[i], ref);
    }
    record(name, passed);

    name = "stats 16K"; passed = false;
    statSz = nref_dynamic_heap_size(ref);
    statCurr = nref_free_dynamic_memory(ref);
    if (statSz >= 16*KB && statCurr > 16*KB) {
        passed = true;
    } else {
        printf("statSz = %ld, statCurr = %ld\n", statSz, statCurr);
    }
    record(name, passed);


    name = "alloc all emm"; passed = false;
    if (nref_malloc(sizeof(heap), ref) == 0) passed = true;
    record(name, passed);
    if (diagnostic) nref_diag_dump();

    name = "alloc 10 128K"; passed = true;
    for (i = 0; i < 10 && passed; i++) {
        addr[i] = nref_malloc(128 * KB, ref);
        if (!addr[i]) {
          passed = false;
          printf("malloc 128K failed on %d\n", i);
        }
    }
    record(name, passed);
    if (diagnostic) nref_diag_dump();

    name = "free 10 128K"; passed = true;
    for (i = 0; i < 10 && passed; i++) {
        nref_free(addr[i], ref);
        if (nref_validate_memory_regions(ref) == 0) {
            if (diagnostic) printf("free 128K valid %d\n", i);
        } else {
          passed = false;
          printf("free 128K failed on %d\n", i);
        }
    }
    nref_dump_memory_regions(ref);
    record(name, passed);
    if (diagnostic) nref_diag_dump();

    name = "reverse 10 128K"; passed = true;
    for (i = 0; i < 10 && passed; i++) {
        addr[i] = nref_malloc(128 * KB, ref);
        if (!addr[i]) {
          passed = false;
          printf("rev alloc 128K failed on %d\n", i);
        }
    }
    if (diagnostic) nref_diag_dump();
    for (i = 9; i >= 0 && passed; i--) {
        nref_free(addr[i], ref);
        if (nref_validate_memory_regions(ref) != 0) {
          passed = false;
          printf("rev free 128K failed on %d\n", i);
        }
    }
    if (diagnostic) nref_diag_dump();
    record(name, passed);
    nref_dump_memory_regions(ref);
    if (diagnostic) nref_diag_dump();


    for (n = 0; n < sizeof(nlist); n++) {
    // for (n = 0; n < 2; n++) {
    N = nlist[n];;
    sprintf(dyname, "N%d:C%d:S%d:%dK", N, 10, 4, 40);
    name = dyname; passed = true;
    for (i = 0; i < N && passed; i++) {
        param[i].num = i;
        param[i].cycle = 10;
        param[i].seq = 4;
        param[i].kilo = 40;
        p = &param[i];
        if (pthread_create(&thr[i], NULL, spawn, p)) {
            printf("%s: thread %d create failure\n", name, i);
            passed = false;
            N = i;
        }
    }
    for (i = 0; i < N; i++) {
        if (!pthread_join(thr[i], (void **) &p)) {
            if (!p->result) {
                passed = false;
                printf("%s: thread %d result failure\n", name, i);
            }
        } else {
            passed = false;
            printf("%s: thread %d join failure\n", name, i);
        }
    }
    if (diagnostic) nref_diag_dump();
    record(name, passed);
    }


    summary();
    return 0;
}
