#include <binaryen-c.h>

#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>

void refDump(char *v, long len) {
  int i;
  char c;
  for (i = 0; i < len; i++) {
    c = v[i] & 0xFF;
    printf(" %02x", c & 0xFF);
  }
  printf("\n");
}

int RefSave(const char *file, void *buf, size_t count) {
    int fd;
    int status = 1;

    fd = creat(file, 0664);
    if (fd > 0) {
        if (write(fd, buf, count) == count) {
            status = 0;
        }
        close(fd);
    }
    return(status);
}

void *RefConst(void *moduleRef, struct BinaryenLiteral *value) {
    void *r;
    /* printf("RefConst ");
    refDump((char *) value, sizeof(struct BinaryenLiteral)); */
    r = BinaryenConst(moduleRef, *value);
}

/* Extract the binary field of the WriteResult */
char *RefResultBinary(struct BinaryenModuleAllocateAndWriteResult *result) {
    refDump((char *) result, sizeof(result));
    printf("\tresult.binary=%p\n", result->binary);
    return(result->binary);
}

/* Extract the byte count field of the WriteResult */
unsigned long RefResultBytes(struct BinaryenModuleAllocateAndWriteResult *result) {
    refDump((char *) result, sizeof(result));
    printf("\tresult.binaryBytes=%lx\n", result->binaryBytes);
    return(result->binaryBytes);
}

/* Extract the source map field of the WriteResult */
char *RefResultSourceMap(struct BinaryenModuleAllocateAndWriteResult *result) {
    refDump((char *) result, sizeof(result));
    printf("\tresult.sourceMap=%p\n", result->sourceMap);
    return(result->sourceMap);
}

