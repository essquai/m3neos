# Needed to compile bootstrap.
add_library(neosys STATIC)
target_include_directories(neosys INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}")
include(sources.lst)
target_sources(neosys PRIVATE ${m3neos_SOURCES})
