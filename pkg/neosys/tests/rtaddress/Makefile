SRC     = ../../src/runtime/common
SOURCES = test.c $(SRC)/emm.c $(SRC)/emmalloc.c
CFLAGS  = -g -pthread -I $(SRC) -DEMMALLOC_VERBOSE -DEMMALOC_MEMVALIDATE 

all:  test

test: $(SOURCES)
	$(CC) -o test $(CFLAGS) $(SOURCES)

