# Needed to compile bootstrap.
add_library(m3C STATIC)
target_link_libraries(m3C PUBLIC m3)
include(sources.lst)
target_sources(m3C PRIVATE ${mm3_SOURCES})
