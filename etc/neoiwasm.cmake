# Compilers
set(CMAKE_C_COMPILER   clang-18   CACHE STRING "")
set(CMAKE_CXX_COMPILER clang++-18 CACHE STRING "")

# WAMR features
set(WAMR_BUILD_LIBC_WASI        1 CACHE STRING "")
set(WAMR_BUILD_LIB_PTHREAD      1 CACHE STRING "")
set(WAMR_BUILD_LIB_WASI_THREADS 1 CACHE STRING "")
set(WAMR_BUILD_SHARED_MEMORY    1 CACHE STRING "")


# --- Debug / diagnostics (initial wasm bring-up) ---
set(CMAKE_BUILD_TYPE Debug CACHE STRING "")

# Print a wasm call stack when a trap occurs ("Exception: unreachable" etc.)
set(WAMR_BUILD_DUMP_CALL_STACK     1 CACHE STRING "")
# Load the wasm "name" section so the dump shows function names, not indices
set(WAMR_BUILD_LOAD_CUSTOM_SECTION 1 CACHE STRING "")
set(WAMR_BUILD_CUSTOM_NAME_SECTION 1 CACHE STRING "")

# Classic interpreter: slower, but simpler and easier to follow than the
# default fast interpreter (the call-stack dump may be less precise there)
set(WAMR_BUILD_FAST_INTERP         0 CACHE STRING "")


# Work around bh_atomic.h mis-detecting atomics under clang+glibc
set(NEOS_ATOMIC_DEFS "-DWASM_UINT64_IS_ATOMIC=1 -DWASM_UINT32_IS_ATOMIC=1 -DWASM_UINT16_IS_ATOMIC=1")
set(CMAKE_C_FLAGS   "-g ${NEOS_ATOMIC_DEFS}" CACHE STRING "")
set(CMAKE_CXX_FLAGS "-g ${NEOS_ATOMIC_DEFS}" CACHE STRING "")

