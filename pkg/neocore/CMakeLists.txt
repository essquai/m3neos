# Needed to compile bootstrap.
add_library(neocore STATIC)
target_include_directories(neocore INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}")
include(sources.lst)
target_sources(neocore PRIVATE ${m3neos_SOURCES})
