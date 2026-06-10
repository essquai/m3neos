# Needed to compile bootstrap.
add_library(m3make STATIC)
target_link_libraries(m3make PUBLIC m3)
include(sources.lst)
target_sources(m3make PRIVATE ${mm3_SOURCES})
