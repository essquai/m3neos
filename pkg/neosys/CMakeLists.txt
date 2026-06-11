# Needed to compile bootstrap.
add_library(neocore STATIC)
target_include_directories(neocore INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(neocore PUBLIC m3)
include(sources.lst)
target_sources(neocore PRIVATE ${mm3_SOURCES})
