#
# SYSROOT for wasi-libc
# iwasm built with iwasm.cmake flags: with multi-threading and shared mem
#
SYSROOT=/opt/wasi-sysroot-33.0
clang-22 --target=wasm32-wasip1-threads --sysroot=$SYSROOT -O0 -pthread \
  -mllvm -wasm-enable-sjlj -mllvm -wasm-use-legacy-eh=true \
  -Wl,--import-memory,--export-memory,--initial-memory=8388608,--max-memory=67108864 \
  -o eh_thread.wasm eh_thread.c -lsetjmp
