#include "emm.h"

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
    assert (p->seq < SEQ_MAX);

    sprintf(name, "spawn[%d] cyc=%d seq=%d kb=%d", p->num, p->cycle, p->seq, p->kilo);
    passed = true;
    for (j = 0; j < p->cycle && passed; j++) {
        /* alloc */
        for (i = 0; i < p->seq && passed; i++) {
            addr[i] = emmalloc_malloc(p->kilo * KB);
            if (!addr[i]) {
              passed = false;
              printf("%s: malloc failed on %d\n", name, i);
            }
        }

        /* free  */
        for (i = 0; i < p->seq && passed; i++) {
            emmalloc_free(addr[i]);
        }
    }
    if (passed) {
        if (emmalloc_validate_memory_regions() != 0) {
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
    int64_t statSz, statCurr;
    void    *curBrk;
    spawn_param_t param[SPAWN_MAX];
    spawn_param_t *p;
    pthread_t     thr[SPAWN_MAX];
    int     N;
    int     n;
    

    for (i = 1; i < argc; i++) {
        if (strncmp(argv[i], "-d", 2) == 0) diagnostic = true;
    }

    name = "no heap"; passed = false;
    if (emm_sbrk_vary(100) == EMM_SBRK_FAIL) passed = true;
    record(name, passed);

    name = "small heap"; passed = false;
    emm_sbrk_init(heap, KB);
    if (emm_sbrk_vary(KB+sizeof(max_align_t)) == EMM_SBRK_FAIL) passed = true;
    record(name, passed);

    name = "alloc 16K"; passed = true;
    emm_sbrk_init(heap, sizeof(heap));
    for (i = 0; i < 16 && passed; i++) {
        if (emm_sbrk_vary(KB) == EMM_SBRK_FAIL) passed = false;
    }
    record(name, passed);

    name = "stats 16K"; passed = false;
    emm_sbrk_stat(&statSz, &statCurr);
    if (statSz == sizeof(heap) && statCurr == 16*KB) {
        passed = true;
    }
    record(name, passed);

    name = " sbrk 16K"; passed = false;
    curBrk = emm_sbrk_vary(0);
    if (curBrk == (void *) &heap[16*KB]) {
        passed = true;
    }
    record(name, passed);

    name = "reduce 16K"; passed = false;
    curBrk = emm_sbrk_vary(0-16*KB);
    emm_sbrk_stat(&statSz, &statCurr);
    curBrk = emm_sbrk_vary(0);
    if (statSz == sizeof(heap) && statCurr == 0 && curBrk == (void *) heap) {
        passed = true;
    }
    record(name, passed);

    name = "alloc 2048K"; passed = true;
    for (i = 0; i < 2*KB && passed; i++) {
        if (emm_sbrk_vary(KB) == EMM_SBRK_FAIL) {
          passed = false;
          printf("sbrk(KB) failed on %d\n", i);
        }
    }
    record(name, passed);

    name = "stats 2048K"; passed = false;
    emm_sbrk_stat(&statSz, &statCurr);
    if (statSz == sizeof(heap) && statCurr == 2*KB*KB) {
        passed = true;
    }
    record(name, passed);

    name = "exact 2048K"; passed = false;
    if (emm_sbrk_vary(sizeof(max_align_t)) == EMM_SBRK_FAIL) {
        passed = true;
    }
    record(name, passed);

    name = "reduce 2048K"; passed = false;
    curBrk = emm_sbrk_vary(0-2*KB*KB);
    emm_sbrk_stat(&statSz, &statCurr);
    curBrk = emm_sbrk_vary(0);
    if (statSz == sizeof(heap) && statCurr == 0 && curBrk == (void *) heap) {
        passed = true;
    }
    record(name, passed);

    name = "align"; passed = false;
    if (emm_sbrk_vary(sizeof(max_align_t)) != EMM_SBRK_FAIL) {
        passed = true;
    }
    record(name, passed);

    name = "stats align"; passed = false;
    emm_sbrk_stat(&statSz, &statCurr);
    if (statSz == sizeof(heap) && statCurr == sizeof(max_align_t)) {
        passed = true;
    }
    record(name, passed);

    name = "init emm"; passed = false;
    emm_init(heap, sizeof(heap));
    if (emmalloc_validate_memory_regions() == 0) passed = true;
    if (diagnostic) emmalloc_dump_memory_regions();
    record(name, passed);
    if (diagnostic) emm_diag_dump();


    name = "alloc all emm"; passed = false;
    if (emmalloc_malloc(sizeof(heap)) == 0) passed = true;
    record(name, passed);
    if (diagnostic) emm_diag_dump();

    name = "alloc 10 128K"; passed = true;
    for (i = 0; i < 10 && passed; i++) {
        addr[i] = emmalloc_malloc(128 * KB);
        if (!addr[i]) {
          passed = false;
          printf("malloc 128K failed on %d\n", i);
        }
    }
    record(name, passed);
    if (diagnostic) emm_diag_dump();

    name = "free 10 128K"; passed = true;
    for (i = 0; i < 10 && passed; i++) {
        emmalloc_free(addr[i]);
        if (emmalloc_validate_memory_regions() == 0) {
            if (diagnostic) printf("free 128K valid %d\n", i);
        } else {
          passed = false;
          printf("free 128K failed on %d\n", i);
        }
    }
    emmalloc_dump_memory_regions();
    record(name, passed);
    if (diagnostic) emm_diag_dump();

    name = "reverse 10 128K"; passed = true;
    for (i = 0; i < 10 && passed; i++) {
        addr[i] = emmalloc_malloc(128 * KB);
        if (!addr[i]) {
          passed = false;
          printf("rev alloc 128K failed on %d\n", i);
        }
    }
    if (diagnostic) emm_diag_dump();
    for (i = 9; i >= 0 && passed; i--) {
        emmalloc_free(addr[i]);
        if (emmalloc_validate_memory_regions() != 0) {
          passed = false;
          printf("rev free 128K failed on %d\n", i);
        }
    }
    if (diagnostic) emm_diag_dump();
    record(name, passed);
    emmalloc_dump_memory_regions();
    if (diagnostic) emm_diag_dump();


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
    if (diagnostic) emm_diag_dump();
    record(name, passed);
    }


    summary();
    return 0;
}
