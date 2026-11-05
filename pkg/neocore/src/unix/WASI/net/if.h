/* Intentionally empty: wasi-libc has no <net/if.h>.
   Uconstants.c includes it but exports nothing from it on this target.
   Found via the -I for unix/WASI (added because m3core.h lives here). */
