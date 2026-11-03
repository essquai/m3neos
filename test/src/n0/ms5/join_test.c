/* join_test.c - create/join cycle test for nthr (x86_64 and wasm32).
 *
 * Mirrors WThread.Fork / WThread.Join: the joiner owns a "threadSyn", records it
 * as the child's joinSyn under the child's own syn, then loops on nthr_vigil
 * (holding its own syn) until the child is 'joined'.  The thread routine does
 * nothing, so the whole cost is create -> exit -> signal -> reap -> free.
 *
 * Uses the project's nthr.c / nthr_<arch>.c / nthr_<arch>.s / nsyn* / nref.c
 * UNCHANGED.  Only this file is new.
 *
 * usage:  join_test [iterations] [@M3virtual=N[K|M]] [@M3untraced=N[K|M]] [@M3traced=N[K|M]]
 * On x86_64 the sizes may be omitted (sbrk).  On wasm32 under WAMR give them, e.g.
 *     join_test 600 @M3virtual=48M @M3untraced=16M @M3traced=4M
 * (Virtual must be a multiple of 64K on wasm32.)
 */
#include "nthr.h"
#include "nref.h"
#include <stdio.h>
#include <stdlib.h>

static void work(void *a) { (void)a; }

typedef struct { nsyn_lock_t threadSyn; nthr_context_t ctx; } T;

int main(int argc, char **argv) {
    int iters = 20000;
    if (argc > 1) { int n = atoi(argv[1]); if (n > 0) iters = n; }

    nref_prologue(argc, argv);       /* non-matching args (e.g. the count) are ignored */

    nsyn_init(&nthr_nexus.watchSyn);
    nsyn_init(&nthr_nexus.safeSyn);
    nsyn_init(&nthr_nexus.forkSyn);

    static T selfT;
    nsyn_init(&selfT.threadSyn);
    nthr_default(&selfT.ctx, &selfT.threadSyn, &selfT);

    for (int i = 0; i < iters; i++) {
        T *t = nref_calloc(1, sizeof(T), Untraced);
        nsyn_init(&t->threadSyn);
        nthr_create(&t->ctx, &t->threadSyn, 64 * 1024, work, t, t);

        nsyn_lock(&t->threadSyn);
        t->ctx.joinSyn = &selfT.threadSyn;
        nsyn_unlock(&t->threadSyn);

        nsyn_lock(&selfT.threadSyn);
        recce_t live = vigilant;
        while (live != joined) live = nthr_vigil(&t->ctx);
        nsyn_unlock(&selfT.threadSyn);

        nref_free(t, Untraced);
        if ((i % 1000) == 0) { fprintf(stderr, "i=%d\n", i); }
    }
    fprintf(stderr, "DONE %d\n", iters);
    return 0;
}
