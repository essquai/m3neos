# Needed to compile bootstrap.
add_library(m3link STATIC)
target_link_libraries(m3link PUBLIC neo m3ir)
include(sources.lst)
target_sources(m3link PRIVATE ${m3neos_SOURCES})
