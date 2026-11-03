join_harness - create/join cycle test for the WTHREAD runtime

Files
  join_test.c   the test (the only new C file; builds against your tree unchanged)
  mi.h          struct mallinfo shim for stock wasi-sdk 24 (see below)
  run_w.js      node runner with worker threads (what I used for the wasm32 runs)

Build (adjust paths; SRC = your tree).  Sources needed from your tree:
  nthr.c nref.c nsyn.c  nthr_<arch>.c  nsyn_<arch>.c  nthr_<arch>.s
  where <arch> = x86_64 (the .s is nthr_sysv.s) or wasm32 (the .s is nthr_wasi.s)

x86_64:
  clang -O1 -I$SRC -pthread join_test.c $SRC/nthr.c $SRC/nsyn.c $SRC/nref.c \
        $SRC/nthr_x86_64.c $SRC/nsyn_x86_64.c $SRC/nthr_sysv.s -o join_x86
  ./join_x86 20000

wasm32 (wasi-sdk 24; $W = wasi-sdk root):
  $W/bin/clang --target=wasm32-wasip1-threads -pthread -matomics -O1 \
        --sysroot=$W/share/wasi-sysroot -I$SRC -include mi.h \
        join_test.c $SRC/nthr.c $SRC/nsyn.c $SRC/nref.c \
        $SRC/nthr_wasm32.c $SRC/nsyn_wasm32.c $SRC/nthr_wasi.s \
        -Wl,--shared-memory,--import-memory,--max-memory=83886080 -o join.wasm
  -include mi.h is only needed if your malloc.h lacks struct mallinfo.
  --max-memory must be a multiple of 64K and must match the memory the host gives.
  Run under WAMR with the sizes on the command line, e.g.
     iwasm ... join.wasm 600 @M3virtual=48M @M3untraced=16M @M3traced=4M
  (with --max-memory=83886080 the three sizes must fit inside it.)

Node (what I used for the wasm32 runs): run_w.js does not forward argv, so under node use
  join_test_node.c instead of join_test.c (same test, sizes compiled in: 48M/16M):
     node run_w.js join_node.wasm
  run_w.js supplies a shared memory of 300..1280 pages and wasi 'thread-spawn'.

Expected: stderr shows i=0, i=1000, ... then "DONE <n>".  A hang means a join/exit
handshake problem; "nthr_park neither deferred nor safe" or an abort means a real bug.
