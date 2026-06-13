# Needed to compile bootstrap.
add_library(neo STATIC)
target_link_libraries(neo PUBLIC neosys)
include(sources.lst)
target_sources(neo PRIVATE ${m3neos_SOURCES})
