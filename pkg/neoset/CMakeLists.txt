# Needed to compile bootstrap.
add_library(neoset STATIC)
include(sources.lst)
target_sources(neoset PRIVATE ${mm3_SOURCES})
