# Needed to compile bootstrap.
add_library(m3C STATIC)
target_link_libraries(m3C PUBLIC neosys)
include(sources.lst)
target_sources(m3C PRIVATE ${m3neos_SOURCES})
