# m3neos
The Modula-3 neos compiler builds for native and wasm32 targets using three different backends: C, LLVM native, and LLVM wasm32.
It is derived from [Critical Mass Modula-3](https://github.com/modula3/cm3).

## Status

Pre-release capabilities:
* C native backend originally from SRC
* llvm-c intermediate representation api
* LLVM native backend (m3llhost)
* consolidate config files
* neo packages
* bootstrap generation
* RTAddress runtime (malloc substitute)

Requires investigation
* LLVM native backend only works when compiled with gcc on Ubuntu;
* compilation with clang coredumps

Roadmap items:

* stretch goal: LLVM C aggregate return values
* runtime shadow stack
* runtime wasm32 build
* LLVM wasm32 backend (m3llwasm)
* stretch goal: C wasm32 backend
* stretch goal: binaryen backend
