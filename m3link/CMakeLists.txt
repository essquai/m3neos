# Needed to compile bootstrap.
add_library(m3link STATIC)
target_link_libraries(m3link PUBLIC m3)
include(sources.lst)
target_sources(m3link PRIVATE ${mm3_SOURCES})
