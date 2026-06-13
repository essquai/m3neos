# Needed to compile bootstrap.
add_library(m3fe STATIC)
target_link_libraries(m3fe PUBLIC neo m3ir)
include(sources.lst)
target_sources(m3fe PRIVATE ${m3neos_SOURCES})
