# Needed to compile bootstrap.
add_library(m3fe STATIC)
target_link_libraries(m3fe PUBLIC m3)
include(sources.lst)
target_sources(m3fe PRIVATE ${mm3_SOURCES})
