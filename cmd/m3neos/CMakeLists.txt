# Needed to compile bootstrap.
add_executable(m3neos)
install(TARGETS m3neos)

target_link_libraries(m3neos PRIVATE
   Threads::Threads
   m3ir
   m3C
   m3fe
   m3link
   m3make
   neoset
   neoutils
)

include(sources.lst)
target_sources(m3neos PRIVATE ${m3neos_SOURCES})
