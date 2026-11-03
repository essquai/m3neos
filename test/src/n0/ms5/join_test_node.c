#include "nthr.h"
#include "nref.h"
#include <stdio.h>
#include <stdlib.h>
static void work(void *a) { (void)a; }
typedef struct { nsyn_lock_t threadSyn; nthr_context_t ctx; } T;
int main(int argc, char **argv) {
    int iters = 600;
    nref_from_orbit();
    if (!nref_define(48u << 20, Virtual)) { fprintf(stderr, "virtual fail\n"); nref_diag_dump(); return 1; }
    if (!nref_define(16u << 20, Untraced)) { fprintf(stderr, "untraced fail\n"); nref_diag_dump(); return 1; }
    nsyn_init(&nthr_nexus.watchSyn); nsyn_init(&nthr_nexus.safeSyn); nsyn_init(&nthr_nexus.forkSyn);
    static T selfT; nsyn_init(&selfT.threadSyn);
    nthr_default(&selfT.ctx, &selfT.threadSyn, &selfT);
    for (int i = 0; i < iters; i++) {
        T *t = nref_calloc(1, sizeof(T), Untraced);
        nsyn_init(&t->threadSyn);
        nthr_create(&t->ctx, &t->threadSyn, 64 * 1024, work, t, t);
        nsyn_lock(&t->threadSyn); t->ctx.joinSyn = &selfT.threadSyn; nsyn_unlock(&t->threadSyn);
        nsyn_lock(&selfT.threadSyn);
        recce_t live = vigilant;
        while (live != joined) live = nthr_vigil(&t->ctx);
        nsyn_unlock(&selfT.threadSyn);
        nref_free(t, Untraced);
        if ((i % 50) == 0) { fprintf(stderr, "i=%d\n", i); }
    }
    fprintf(stderr, "DONE %d\n", iters);
    return 0;
}
