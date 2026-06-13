# Needed to compile bootstrap.
add_library(m3make STATIC)
target_link_libraries(m3make PUBLIC neo m3ir neoutils)
include(sources.lst)
target_sources(m3make PRIVATE ${m3neos_SOURCES})
