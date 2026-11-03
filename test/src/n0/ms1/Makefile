SRC      = /home/essquai/Code/m3neos/pkg/neosys/src/runtime/common
WSRC     = ../neoaux/src/WTHREAD
WSOURCES = $(WSRC)/nthr.c $(WSRC)/nthr_x86_64.c
NSOURCES = test.c $(SRC)/nref.c $(SRC)/nsyn.c $(SRC)/nsyn_x86_64.c
CFLAGS   = -g -I $(SRC) -I $(WSRC) -DEMMALLOC_VERBOSE -DEMMALOC_MEMVALIDATE 

all:  test

test: $(NSOURCES) $(WSOURCES)
	$(CC) -o test $(CFLAGS) $(NSOURCES) $(WSOURCES)

