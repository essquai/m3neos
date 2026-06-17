SRC      = ../../src/runtime/common
TSOURCES = test.c $(SRC)/emm.c $(SRC)/emmalloc.c
NSOURCES = ntest.c $(SRC)/nref.c
CFLAGS   = -g -pthread -I $(SRC) -DEMMALLOC_VERBOSE -DEMMALOC_MEMVALIDATE 

all:  test ntest

test: $(TSOURCES)
	$(CC) -o test $(CFLAGS) $(SOURCES)

ntest: $(NSOURCES)
	$(CC) -o ntest $(CFLAGS) $(NSOURCES)

