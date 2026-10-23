SRC      = ../../src/runtime/common
NSOURCES = ntest.c $(SRC)/nref.c $(SRC)/nsyn.c $(SRC)/nsyn_x86_64.c
CFLAGS   = -g -pthread -I $(SRC) -DEMMALLOC_VERBOSE -DEMMALOC_MEMVALIDATE 

all:  ntest

ntest: $(NSOURCES)
	$(CC) -o ntest $(CFLAGS) $(NSOURCES)

