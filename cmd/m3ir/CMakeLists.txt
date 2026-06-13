# Needed to compile bootstrap.
add_library(m3ir STATIC)
target_link_libraries(m3ir PUBLIC neo neoutils)
include(sources.lst)
target_sources(m3ir PRIVATE ${m3neos_SOURCES})
