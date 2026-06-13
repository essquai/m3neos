# Needed to compile bootstrap.
add_library(neoutils STATIC)
include(sources.lst)
target_sources(neoutils PRIVATE ${m3neos_SOURCES})
