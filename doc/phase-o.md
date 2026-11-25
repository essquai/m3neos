# Phase O, optimiser enablement (future)

*Reflects plan v19, 2026-11-25. Text below is moved verbatim from dev-plan18.md (lines 2335-2359).*

<!-- v18 lines 2335-2359 -->
## Phase O — Optimiser enablement (future, not scheduled; new in v14)

**Premise.** The pipeline has no optimiser, and the current root scheme is correct only without one (constraints table above).
Optimisation should be driven by measurement of the code that actually dominates a representative program (for instance the
front end compiling a file), and correctness comes first. Measured context, for orientation only (analysis note): `-O0` to
`-O2` is roughly 2 to 4 times on tight scalar loops in one published C++ library and much less on call-bound code; gcroot costs
about 1.5 ns per call of a rooted function on x86_64 and so eats most of the optimiser's gain on pathologically call-dense code
and a few percent or less on code that does real work per call.

**Entry criteria (all required).**

1. Every traced value that is live across a safepoint has a memory home an optimiser cannot remove: scalar traced variables and
   **all traced temporaries** gcroot'd (the derived-copy rule becomes a hard requirement), and aggregates and fixed arrays of
   references rooted by **address roots with null metadata**. **(v15)** The open-array `NEW` dope temporary (not a root since
   `ClassifyVar`) and the open-array VALUE copy slot belong on this list.
2. The audit gate shows zero not-homed pairs on the **optimised** IR, and the wasm32 visibility harness passes at the chosen
   pipeline.
3. The two shadow-stack LLVM bugs are re-checked at the chosen levels (or fixed upstream).
4. ms8/ms9 are rerun at the new pipeline as a one-variable experiment.
5. A measurement shows the optimiser gains enough on representative code to justify the cost of the extra rooting.
6. **(v17)** Exceptions: a value modified after a `setjmp` and read after the `longjmp` must be memory-resident (volatile semantics); at `llc -O0` every M3 variable
   is an alloca, so `ms13`'s `Rooted` is correct today, but `mem2reg` and later passes could break it. Re-run `ms13` and `ms14` at the new pipeline.

---


