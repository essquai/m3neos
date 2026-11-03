#include "nthr.h"
#include "nref.h"
#include "nsyn.h"
#include <stdio.h>
#include <stdlib.h>

/* contexts */
#define STK_MAX 64 *1024
#define THR_MAX 64
typedef struct {
    nthr_context_t ctxt;
    int idx;
} wctxt_t;
static wctxt_t wctxt[THR_MAX];

void wait_thread(void *arg) {
    wctxt_t *w = arg;
    int count = 16;

    printf("wait_thread start %d\n", w->idx);

    /* make pauses */
    if ((w->idx & 1) == 0) count = 10;
    for (int i = 0; i < count; i++) {
        nsyn_resume(0.1);
        printf("dot(%d,%d)\n", w->idx, i);
        fflush(NULL);
    }

    printf("wait_thread end %d\n", w->idx);
    fflush(NULL);
    return;
}
 

int main(int argc, char *argv[]) {
    int handfull = 5;
    int32_t s;
    void *r;

    nref_prologue(argc, argv);
    for (int i = 0; i < handfull; i++) {
        wctxt[i].idx = i;
        s = nthr_create(&wctxt[i].ctxt, STK_MAX, wait_thread, &wctxt[i]);
        printf("nthr_create %d %p\n", s, &wctxt[i]);
        if (s < 0) {
            printf("nthr_create failure \n");
            abort();
        }
    }

    for (int i = 0; i < handfull; i++) {
        nthr_join(&wctxt[i].ctxt);
        printf("nthr_join %d %p\n", wctxt[i].idx, r);
    }

    return 0;
}
