/* unix/WASI/m3core.h -- the wasm32 / WASI / WAMR flavour of m3core.h.

   WHY THIS FILE EXISTS
   --------------------
   The pristine pkg/neocore/src/m3core.h (identical to neosys') is the
   portability header for every host CM3 ever ran on. For wasm32 against
   wasi-libc almost none of its platform branches apply and a good part of
   POSIX is missing. Rather than thread a __wasi__ branch through the
   frozen x86_64 header, wasm32 builds select THIS header instead
   (neocore/src/m3makefile: h_source ("unix/WASI/m3core")).

   WHAT IS SHARED
   --------------
   Everything between "begin shared vocabulary" and "end shared vocabulary"
   is copied from the pristine header: the M3WRAP macros, INTEGER/WORD_T and
   the m3_* idealised types, the per-module extern prototypes and the
   "inhibit m3c type" names. Keep it in step with the pristine file; the
   Modula-3 side (the .i3 files) does not know which header it gets.

   WHAT IS DIFFERENT
   -----------------
   - one include block, wasi-libc only (+ -D_WASI_EMULATED_* checks)
   - shims for POSIX that wasi-libc lacks (below). Stage 1: they fail with
     ENOSYS, or are honest no-ops, so the thin unix/Common wrappers
     compile unchanged. Stage 2 replaces them with real WAMR-backed
     implementations (sockets via the WAMR socket extension, process
     spawn via host natives).
   - no Win32 / Darwin / Solaris / OSF / BSD / Cygwin / Haiku / VMS / DJGPP.
   STAGES
   ------
   Stage 1 (this file): the existing C sources compile and link unchanged.
     What wasi-libc lacks gets an inert stand-in (ENOSYS, NULL, no-op).
     The code builds; the capability does not work.
   Stage 2 (later): each stand-in that matters is replaced by a real,
     WAMR-backed implementation, out of line in unix/WASI (sockets via the
     WAMR socket extension, name lookup, process spawn, pipe/dup). The
     stand-in is then deleted. Users/groups, umask, chown and signals are
     inert by intent.

   PROVENANCE OF THE POSIX SURFACE (read before trusting it)
   ---------------------------------------------------------
   - Which calls/types are "missing" was found by compiling the 37 C files
     of neocore against wasi-sysroot-24.0 and reading the errors. It is the
     subset of POSIX that neocore's C wrappers use, not a complete residual.
     neolib will need more.
   - Declarations that appear under "sockets" below are the standard POSIX
     signatures copied from wasi-libc's own <sys/socket.h> (hidden there
     behind __wasilibc_unmodified_upstream / wasip2). They have NOT been
     checked against WAMR's wasi_socket_ext.h.
   - Every other stand-in (signatures, struct group/passwd/hostent/
     siginfo_t/sigaction layouts, wait-status macros, fallback constants)
     was written from recollection of POSIX/glibc/musl, restricted to what
     the wrappers touch, and verified only by the callers compiling. The
     fallback constants are Linux/musl values and are exported to Modula-3
     by Uconstants.c: treat them as placeholders.
   - Because the stand-ins are static inline, nothing checks them against
     a real implementation. Stage 2 moves them out of line.

   - M3_PERSONALITY_WASI, which wasm32-only sources test so that picking up
     the wrong flavour of m3core.h stops the build instead of mis-linking.

   REQUIRED BUILD FLAGS (etc/wasm32 SYSTEM_CC)
   -------------------------------------------
     --target=wasm32-wasip1-threads --sysroot=... -pthread -matomics
     -mexception-handling
     -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_MMAN
   link:
     -lwasi-emulated-signal -lwasi-emulated-mman -lwasi-emulated-getpid
*/

#ifndef INCLUDED_M3CORE_H
#define INCLUDED_M3CORE_H

#define M3_PERSONALITY_WASI 1

#if !defined(__wasi__) || !defined(__wasm32__)
#error "unix/WASI/m3core.h is the wasm32/WASI flavour; use pkg/neocore/src/m3core.h for other targets."
#endif
#ifndef _WASI_EMULATED_SIGNAL
#error "wasm32 needs -D_WASI_EMULATED_SIGNAL (and -lwasi-emulated-signal)."
#endif
#ifndef _WASI_EMULATED_MMAN
#error "wasm32 needs -D_WASI_EMULATED_MMAN (and -lwasi-emulated-mman)."
#endif
/* getpid() is deprecated-with-warning in wasi-libc unless emulated; ask for it. */
#ifndef _WASI_EMULATED_GETPID
#define _WASI_EMULATED_GETPID
#endif

typedef int BOOL;
#define TRUE 1
#define FALSE 0

#if __GNUC__
#define M3_NO_INLINE __attribute__((noinline))
#else
#define M3_NO_INLINE /* nothing */
#endif

/* wasi-libc hides much behind feature macros. */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE 1
#endif
#ifndef _REENTRANT
#define _REENTRANT
#endif
#ifndef _FILE_OFFSET_BITS
#define _FILE_OFFSET_BITS 64 /* off_t is 64 bits in wasi-libc regardless */
#endif

#define EXTERN_CONST const

/* No calling-convention decoration on wasm. */
#undef __cdecl
#undef __stdcall
#define __cdecl /* nothing */
#define __stdcall /* nothing */

#define __try /* nothing */
#define __finally /* nothing */

#ifdef __cplusplus
#define M3_EXTERN_C         extern "C"
#define M3_EXTERN_C_BEGIN   extern "C" {
#define M3_EXTERN_C_END     }
#define M3EXTERNC_BEGIN     extern "C" {
#define M3_EXTERNC_BEGIN    extern "C" {
#define M3EXTERNC_END       }
#define M3_EXTERNC_END      }
#else
#define M3_EXTERN_C         /* nothing */
#define M3EXTERNC_BEGIN     /* nothing */
#define M3_EXTERN_C_BEGIN   /* nothing */
#define M3_EXTERN_C_END     /* nothing */
#define M3_EXTERNC_BEGIN    /* nothing */
#define M3EXTERNC_END       /* nothing */
#define M3_EXTERNC_END      /* nothing */
#endif

/* ===== begin shared vocabulary (verbatim from m3core.h) ================ */
#define AGGREGATE_TYPEDEF(aggr, x) aggr x; typedef aggr x x;
#define STRUCT_TYPEDEF(x) AGGREGATE_TYPEDEF (struct, x)
#define UNION_TYPEDEF(x)  AGGREGATE_TYPEDEF (union, x)

STRUCT_TYPEDEF(linger)
STRUCT_TYPEDEF(sockaddr)
STRUCT_TYPEDEF(sockaddr_storage)
STRUCT_TYPEDEF(sockaddr_un)  // unix fifo socket address
STRUCT_TYPEDEF(sockaddr_in)  // internet ipv4 socket address
STRUCT_TYPEDEF(sockaddr_in6) // internet ipv6 socket address
STRUCT_TYPEDEF(in_addr)      // 4 bytes within sockaddr_in
STRUCT_TYPEDEF(in6_addr)     // 16 bytes within sockaddr_in

// Idealized m3 forms.
STRUCT_TYPEDEF(m3_sockaddr_un)  // idealized m3_sockaddr_un, does not necessarily match native
STRUCT_TYPEDEF(m3_sockaddr_in)  // idealized m3_sockaddr_in, does not necessarily match native
STRUCT_TYPEDEF(m3_sockaddr_in6) // idealized m3_sockaddr_in6, does not necessarily match native
STRUCT_TYPEDEF(m3_in_addr)      // idealized m3_in_addr, does not necessarily match native
//STRUCT_TYPEDEF(m3_in6_addr);  // use in6_addr instead

UNION_TYPEDEF(M3SockAddrUnionAll)
UNION_TYPEDEF(NativeSockAddrUnionAll)

/* m3name vs. cname is structured carefully to deal with identifiers
   being #defined in headers, such as on NetBSD. For example, given:
  #define foo bar
  int foo(int);
  M3WRAP1(int, foo, int)

we want:
int Cstdlib__foo (int i) { return bar (i); }
             ^^^                  ^^^
We want the define to affect the body of the wrapper, but not its name.
We want m3name to not undergo further evaluation, but we do want cname to.
This should be achieved by immediate prepending with "__", however even this
can likely fail if __foo is #defined. We take our chances.

__malloc is #defined on OpenBSD, so we can't even do __#name.
It is possible we could win by using just _malloc as the intermediate.
However we selectively don't use token pasting, e.g. in the NO_SWITCHING macros.
Also #undef __foo as needed.
*/

M3EXTERNC_BEGIN
void __cdecl Scheduler__DisableSwitching (void);
void __cdecl Scheduler__EnableSwitching (void);
M3EXTERNC_END

#define M3PASTE_(a, b) a##b
#define M3PASTE(a, b) M3PASTE_(a, b)

#define M3PASTE3_(a, b, c) a##b##c
#define M3PASTE3(a, b, c) M3PASTE3_(a, b, c)

#define M3WRAP(ret, m3name, cname, in, out)                                 \
    M3EXTERNC_BEGIN ret __cdecl M3PASTE(M3MODULE, m3name) in                \
    {                                                                       \
        ret return_value;                                                   \
        return_value = cname out;                                           \
        return return_value;                                                \
    } M3EXTERNC_END

#define M3WRAP_NO_SWITCHING(ret, m3name, cname, in, out) \
    M3EXTERNC_BEGIN ret __cdecl m3name in                \
    {                                                    \
        ret return_value;                                \
        Scheduler__DisableSwitching ();                  \
        return_value = cname out;                        \
        Scheduler__EnableSwitching ();                   \
        return return_value;                             \
    } M3EXTERNC_END

#define M3WRAP_RETURN_VOID(m3name, cname, in, out)       \
    M3EXTERNC_BEGIN void __cdecl m3name in               \
    {                                                    \
        cname out;                                       \
    } M3EXTERNC_END

#define M3WRAP_RETURN_VOID_NO_SWITCHING(m3name, cname, in, out) \
    M3EXTERNC_BEGIN void __cdecl m3name in                      \
    {                                                           \
        Scheduler__DisableSwitching ();                         \
        cname out;                                              \
        Scheduler__EnableSwitching ();                          \
    } M3EXTERNC_END
#define M3WRAP_(ret, m3name, cname, in, out)    M3WRAP(ret, m3name, cname, in, out)

// Parameters a, b, c, etc. are the types of the first, second, third, etc. parameters.
// i, j, k etc. are the first, second, third, etc. parameter values.
#define M3WRAP1_RETURN_VOID(name, a)    M3WRAP_RETURN_VOID(M3PASTE3(M3MODULE, __, name), name, (a i), (i))
#define M3WRAP2_RETURN_VOID(name, a, b) M3WRAP_RETURN_VOID(M3PASTE3(M3MODULE, __, name), name, (a i, b j), (i, j))

#define M3WRAP0(ret, name)             M3WRAP(ret, __##name, name, (void),               ())
#define M3WRAP1(ret, name, a)          M3WRAP(ret, __##name, name, (a i),                (i))
#define M3WRAP2(ret, name, a, b)       M3WRAP(ret, __##name, name, (a i, b j),           (i, j))
#define M3WRAP3(ret, name, a, b, c)    M3WRAP(ret, __##name, name, (a i, b j, c k),      (i, j, k))
#define M3WRAP4(ret, name, a, b, c, d) M3WRAP(ret, __##name, name, (a i, b j, c k, d m), (i, j, k, m))
#define M3WRAP5(ret, name, a, b, c, d, e) M3WRAP(ret, __##name, name, (a i, b j, c k, d m, e n), (i, j, k, m, n))
#define M3WRAP6(ret, name, a, b, c, d, e, f) M3WRAP(ret, __##name, name, (a i, b j, c k, d m, e n, f o), (i, j, k, m, n, o))

// Leading underscore is placed on C name, for Windows, like open vs. _open.
#define M3WRAP0_(ret, name)           M3WRAP_(ret, __##name, name, (void),               ())
#define M3WRAP1_(ret, name, a)        M3WRAP_(ret, __##name, name, (a i),                (i))
#define M3WRAP2_(ret, name, a, b)     M3WRAP_(ret, __##name, name, (a i, b j),           (i, j))
#define M3WRAP3_(ret, name, a, b, c)  M3WRAP_(ret, __##name, name, (a i, b j, c k),      (i, j, k))


/* ===== end of the copied head; platform includes and shims follow ====== */

/* ===== system headers: wasi-libc only ================================== */

#include <sys/types.h>
#include <sys/stat.h>
#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <signal.h>   /* emulated: signal(), raise() only; see the shims below */
#include <math.h>
#include <limits.h>
#include <setjmp.h>

#include <sys/ioctl.h>
#include <sys/mman.h>     /* needs -D_WASI_EMULATED_MMAN */
#include <sys/socket.h>
#include <sys/time.h>
#include <dirent.h>
#include <pthread.h>
#include <unistd.h>
#include <semaphore.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netinet/tcp.h>
#include <sys/select.h>

/* wasi-libc's sockaddr_un has no sun_path ("WASI has no UNIX-domain
   sockets"). Let its declaration go by under another name and supply the
   real layout, so the Usocket.c idealised-vs-native asserts still hold. */
#define sockaddr_un m3_wasi_sockaddr_un_nopath
#include <sys/un.h>
#undef sockaddr_un
struct sockaddr_un
{
    sa_family_t sun_family;
    char        sun_path[108];
};

#define ZeroMemory(a, b) (memset((a), 0, (b)))
#define ZERO_MEMORY(a) (ZeroMemory(&(a), sizeof(a)))

/* ===== POSIX that wasi-libc does not have ============================== */
/*
   Not present in the wasi-libc sysroot: <sys/wait.h> <grp.h> <pwd.h>
   <netdb.h> <ucontext.h> <net/if.h> (the last has an empty stand-in at
   unix/WASI/net/if.h), process creation, job control, dup/pipe,
   users/groups, sigaction, siginfo_t, ucontext_t, DNS.

   Stage 1 (here): inline shims, so the unix/Common wrappers compile and
   link unchanged. Each fails with ENOSYS or reports the single-user,
   no-signal truth of the sandbox. Stage 2 replaces the ones that matter
   (sockets, DNS, spawn, pipe/dup) with WAMR-backed implementations in
   unix/WASI and neolib/os/WASI; delete the shim when its replacement lands.

   Sockets are not shimmed. wasi-libc (wasip1) declares and implements only
   accept, getsockopt, recv, send and shutdown; the rest of the BSD calls
   are declared below and resolve at link time against the WAMR socket
   extension (wasi_socket_ext, TCP/UDP, IPv4/IPv6). Until that library is on
   the link line, an executable using Usocket.o has these as undefined
   symbols; the neocore archive itself builds without them.
*/

#define M3_WASI_ENOSYS(ret) do { errno = ENOSYS; return (ret); } while (0)

/* -- constants wasi-libc hides behind feature macros -------------------- */
#ifndef L_tmpnam
#define L_tmpnam 20
#endif
#ifndef TMP_MAX
#define TMP_MAX 10000
#endif
#ifndef F_GETLK /* no advisory record locks */
#define F_GETLK  5
#define F_SETLK  6
#define F_SETLKW 7
#endif
#ifndef F_DUPFD
#define F_DUPFD 0
#endif
#ifndef EHOSTDOWN
#define EHOSTDOWN 112
#endif
#ifndef SO_REUSEADDR /* Linux/musl values */
#define SO_REUSEADDR 2
#define SO_KEEPALIVE 9
#define SO_LINGER    13
#endif
#ifndef TRY_AGAIN /* <netdb.h> h_errno values */
#define TRY_AGAIN    2
#define NO_RECOVERY  3
#define NO_ADDRESS   4
#endif

/* -- processes ----------------------------------------------------------- */
static inline pid_t fork(void) { M3_WASI_ENOSYS(-1); }
static inline pid_t waitpid(pid_t pid, int* status, int options)
{ (void)pid; (void)status; (void)options; M3_WASI_ENOSYS(-1); }
static inline int execv(const char* p, char* const a[]) { (void)p; (void)a; M3_WASI_ENOSYS(-1); }
static inline int execvp(const char* p, char* const a[]) { (void)p; (void)a; M3_WASI_ENOSYS(-1); }
static inline int execve(const char* p, char* const a[], char* const e[])
{ (void)p; (void)a; (void)e; M3_WASI_ENOSYS(-1); }
static inline int kill(pid_t pid, int sig) { (void)pid; (void)sig; M3_WASI_ENOSYS(-1); }
static inline FILE* popen(const char* c, const char* m) { (void)c; (void)m; M3_WASI_ENOSYS(NULL); }
static inline int pclose(FILE* f) { (void)f; M3_WASI_ENOSYS(-1); }

/* wasi-libc declares tmpfile() but marks it deprecated and does not define it
   ("tmpfile is not defined on WASI"). Redirect later uses of the name (after
   <stdio.h> has been read) to a stand-in, so the CstdioC.c wrapper neither
   warns nor leaves an undefined symbol. Same trick works for any
   declared-but-undefined libc name. */
static inline FILE* m3_wasi_tmpfile(void) { M3_WASI_ENOSYS(NULL); }
#define tmpfile m3_wasi_tmpfile

#ifndef WNOHANG /* <sys/wait.h>, musl encoding */
#define WNOHANG   1
#define WUNTRACED 2
#define WEXITSTATUS(s) (((s) & 0xff00) >> 8)
#define WTERMSIG(s)    ((s) & 0x7f)
#define WSTOPSIG(s)    WEXITSTATUS(s)
#define WIFEXITED(s)   (!WTERMSIG(s))
#define WIFSTOPPED(s)  ((short)((((s) & 0xffff) * 0x10001U) >> 8) > 0x7f00)
#define WIFSIGNALED(s) (((s) & 0xffff) - 1U < 0xffu)
#endif

/* -- descriptors, modes, ownership --------------------------------------- */
static inline int dup(int fd) { (void)fd; M3_WASI_ENOSYS(-1); }
static inline int dup2(int fd, int fd2) { (void)fd; (void)fd2; M3_WASI_ENOSYS(-1); }
static inline int pipe(int fd[2]) { (void)fd; M3_WASI_ENOSYS(-1); }
static inline int getdtablesize(void) { return 1024; }
static inline int mknod(const char* p, mode_t m, dev_t d) { (void)p; (void)m; (void)d; M3_WASI_ENOSYS(-1); }
static inline mode_t umask(mode_t m) { (void)m; return 022; }
static inline int chown(const char* p, uid_t u, gid_t g) { (void)p; (void)u; (void)g; M3_WASI_ENOSYS(-1); }
static inline int fchown(int fd, uid_t u, gid_t g) { (void)fd; (void)u; (void)g; M3_WASI_ENOSYS(-1); }

/* -- identity: one anonymous user ---------------------------------------- */
static inline uid_t geteuid(void) { return 0; }
static inline gid_t getegid(void) { return 0; }
static inline int setreuid(uid_t r, uid_t e) { (void)r; (void)e; M3_WASI_ENOSYS(-1); }
static inline int setregid(gid_t r, gid_t e) { (void)r; (void)e; M3_WASI_ENOSYS(-1); }
static inline int getgroups(int n, gid_t* l) { (void)n; (void)l; return 0; }

struct group  { char* gr_name; char* gr_passwd; gid_t gr_gid; char** gr_mem; };
struct passwd { char* pw_name; char* pw_passwd; uid_t pw_uid; gid_t pw_gid;
                char* pw_gecos; char* pw_dir; char* pw_shell; };
static inline struct group*  getgrent(void) { return NULL; }
static inline struct group*  getgrgid(gid_t g) { (void)g; return NULL; }
static inline struct group*  getgrnam(const char* n) { (void)n; return NULL; }
static inline void setgrent(void) { }
static inline void endgrent(void) { }
static inline struct passwd* getpwuid(uid_t u) { (void)u; return NULL; }
static inline struct passwd* getpwnam(const char* n) { (void)n; return NULL; }

/* -- time zone: UTC only -------------------------------------------------- */
static inline void tzset(void) { }

/* -- names: stage 2 maps these onto getaddrinfo (WAMR --allow-resolve) ---- */
struct hostent
{
    char*  h_name;
    char** h_aliases;
    int    h_addrtype;
    int    h_length;
    char** h_addr_list;
};
static inline struct hostent* gethostbyname(const char* n) { (void)n; return NULL; }
static inline struct hostent* gethostbyaddr(const void* a, socklen_t l, int t)
{ (void)a; (void)l; (void)t; return NULL; }

/* -- signals --------------------------------------------------------------
   With _WASI_EMULATED_SIGNAL wasi-libc gives signal() and raise() and a
   bare sigset_t typedef: no siginfo_t, struct sigaction, sigaction() or
   sigemptyset(). Hard faults on wasm
   are traps, not signals, so there is nothing to install a handler on. The
   shim keeps the RTSignalC/RTDebugC logic compiling and executing; the
   handlers simply never fire. sigaction() reports success and returns
   "default" as the previous action, which is what RTSignalC asserts on. */
typedef struct
{
    int   si_signo;
    int   si_errno;
    int   si_code;
    void* si_addr;
} siginfo_t;

struct sigaction
{
    union
    {
        void (*sa_handler)(int);
        void (*sa_sigaction)(int, siginfo_t*, void*);
    } __sa_handler;
    sigset_t sa_mask;
    int      sa_flags;
};
#define sa_handler   __sa_handler.sa_handler
#define sa_sigaction __sa_handler.sa_sigaction
#define SA_SIGINFO   4
#define SA_RESTART   0x10000000

static inline int sigemptyset(sigset_t* s) { *s = 0; return 0; }
static inline int sigaction(int sig, const struct sigaction* act, struct sigaction* old)
{
    (void)sig; (void)act;
    if (old != NULL)
        memset(old, 0, sizeof(*old));
    return 0;
}

/* -- ucontext: no machine context is ever delivered ---------------------- */
typedef struct { int m3_unused; } ucontext_t;
#define GET_PC(context) ((void)(context), 0)

/* -- sockets: provided by the WAMR socket extension (see above) ----------- */
int socket(int, int, int);
int bind(int, const struct sockaddr*, socklen_t);
int connect(int, const struct sockaddr*, socklen_t);
int listen(int, int);
int getsockname(int, struct sockaddr* __restrict, socklen_t* __restrict);
int getpeername(int, struct sockaddr* __restrict, socklen_t* __restrict);
ssize_t sendto(int, const void*, size_t, int, const struct sockaddr*, socklen_t);
ssize_t recvfrom(int, void* __restrict, size_t, int, struct sockaddr* __restrict, socklen_t* __restrict);
int setsockopt(int, int, int, const void*, socklen_t);

#undef M3_WASI_ENOSYS

/* ===== shared vocabulary continues (verbatim from m3core.h) ============ */

#if UCHAR_MAX == 0x0FFUL
typedef   signed char        INT8; // TODO: C99
typedef unsigned char       UINT8;
#else
#error unable to find 8bit integer
#endif
#if USHRT_MAX == 0x0FFFFUL
typedef          short      INT16;
typedef unsigned short     UINT16;
#else
#error unable to find 16bit integer
#endif
#if UINT_MAX == 0x0FFFFFFFFUL
typedef          int        INT32;
typedef unsigned int       UINT32;
#elif ULONG_MAX == 0x0FFFFFFFFUL
typedef          long       INT32;
typedef unsigned long      UINT32;
#else
#error unable to find 32bit integer
#endif

typedef          long long  INT64;
typedef unsigned long long UINT64;

typedef unsigned char BOOLEAN;
typedef float REAL;
typedef double LONGREAL;
typedef double EXTENDED;
#if defined(__cplusplus) || __STDC__
//Match m3c, so all the files can be concatenated.
// TODO change m3c to cast to char* and not depend on ADDRESS being either.
// Maybe caddr_t.
//typedef void* ADDRESS;
typedef char* ADDRESS;
#else
typedef char* ADDRESS;
#endif
typedef ADDRESS TEXT;
#define MUTEX MUTEX
typedef ADDRESS MUTEX;

#ifdef __cplusplus
extern "C" {
#endif

// wasm32: size_t == ptrdiff_t == intptr_t == void*, all 32 bits.
typedef ptrdiff_t INTEGER;
typedef size_t WORD_T;

#define const_INTEGER const_INTEGER /* inhibit m3c type that lacks const */
typedef const INTEGER const_INTEGER;

// Something (m3front?) is indecisive as to if Word__T is INTEGER or INT64.
// Or rather, if functions like Word__Divide, traffic in INTEGER or
// Word__T. This could be m3front vs. Word.ig. This combines poorly
// with Word__T sometimes being INT64. They do not match. As well,
// between INT64 and INTEGER, INTEGER is preferred for portability.
// But having actual unsigned types might be good too.
//typedef INTEGER WORD_T;
typedef INTEGER Word__T;
// TODO replace WORD_T with Word__T

#define INTEGER INTEGER /* Support concatenation with m3c output. */
#define WORD_T  WORD_T  /* Support concatenation with m3c output. */
#define Word__T Word__T /* Support concatenation with m3c output. */

/* LONGINT is always signed and exactly 64 bits. */
typedef INT64 LONGINT;

/* see Utypes.i3; we assert that these are large enough, they don't have
be exactly correctly sizes, and often are not */
typedef LONGINT m3_dev_t;
typedef INTEGER m3_gid_t;
typedef LONGINT m3_ino_t;
typedef INTEGER m3_mode_t;
typedef LONGINT m3_nlink_t;
typedef INTEGER m3_pid_t;
typedef ADDRESS m3_pthread_t;
typedef LONGINT m3_off_t;
typedef INTEGER m3_uid_t;

// These typenames allow for concatenating the hand written
// .h/.c files with the m3c output so it can all be compiled at once.
//
// The m3c output uses ifndef to guard its own definitions, which
// can vary subtly. For example "int" is a 32bit signed integer type, possibly long.
// "long" is signed and the same size as long, but can on some platforms be int instead,
// if int and long are the same size.
// Presently const is meaningless in Modula-3 and m3c, so const is ommited there,
// and could be ommited here as well.
//
// The names should match the .i3 files, assuming full qualification and replacing "." with "__".
#define Cstddef__ptrdiff_t          Cstddef__ptrdiff_t          /* inhibit m3c type */
#define Cstddef__size_t             Cstddef__size_t             /* inhibit m3c type */
#define Cstddef__ssize_t            Cstddef__ssize_t            /* inhibit m3c type */
#define Cstdio__FILE_star           Cstdio__FILE_star           /* inhibit m3c type */
#define Ctypes__char                Ctypes__char                /* inhibit m3c type */
#define Ctypes__char_star           Ctypes__char_star           /* inhibit m3c type */
#define Ctypes__char_star_star      Ctypes__char_star_star      /* inhibit m3c type */
#define Ctypes__const_char_star     Ctypes__const_char_star     /* inhibit m3c type */
#define Ctypes__const_int           Ctypes__const_int           /* inhibit m3c type */
#define Ctypes__const_void_star     Ctypes__const_void_star     /* inhibit m3c type */
#define Ctypes__int                 Ctypes__int                 /* inhibit m3c type */
#define Ctypes__int_star            Ctypes__int_star            /* inhibit m3c type */
#define Ctypes__long                Ctypes__long                /* inhibit m3c type */
#define Ctypes__size_t              Ctypes__size_t              /* inhibit m3c type */
#define Ctypes__unsigned_char_star  Ctypes__unsigned_char_star  /* inhibit m3c type */
#define Ctypes__unsigned            Ctypes__unsigned            /* inhibit m3c type */
#define Ctypes__unsigned_int        Ctypes__unsigned_int        /* inhibit m3c type */
#define Ctypes__unsigned_long       Ctypes__unsigned_long       /* inhibit m3c type */
#define Ctypes__unsigned_long_int   Ctypes__unsigned_long_int   /* inhibit m3c type */
#define Ctypes__void_star           Ctypes__void_star           /* inhibit m3c type */
#define OSConfigPosix__const_char_star OSConfigPosix__const_char_star /* inhibit m3c type */
#define ThreadPThread__pthread_t    ThreadPThread__pthread_t    /* inhibit m3c type */
#define Utypes__dev_t               Utypes__dev_t               /* inhibit m3c type */
#define Utypes__gid_t               Utypes__gid_t               /* inhibit m3c type */
#define Utypes__ino_t               Utypes__ino_t               /* inhibit m3c type */
#define Utypes__mode_t              Utypes__mode_t              /* inhibit m3c type */
#define Utypes__nlink_t             Utypes__nlink_t             /* inhibit m3c type */
#define Utypes__pid_t               Utypes__pid_t               /* inhibit m3c type */
#define Utypes__off_t               Utypes__off_t               /* inhibit m3c type */
#define Utypes__size_t              Utypes__size_t              /* inhibit m3c type */
#define Utypes__uid_t               Utypes__uid_t               /* inhibit m3c type */

typedef size_t        Cstddef__size_t;
typedef ssize_t       Cstddef__ssize_t; /* provided above for msc */
typedef ptrdiff_t     Cstddef__ptrdiff_t;
typedef FILE*         Cstdio__FILE_star;
typedef char          Ctypes__char;
typedef char*         Ctypes__char_star;
typedef char**        Ctypes__char_star_star;
typedef const char*   Ctypes__const_char_star;
typedef const char*   OSConfigPosix__const_char_star; // TODO remove redundancy
typedef const int     Ctypes__const_int;
typedef const void*   Ctypes__const_void_star;
typedef int           Ctypes__int;
typedef int*          Ctypes__int_star;
typedef long          Ctypes__long;
typedef unsigned char* Ctypes__unsigned_char_star;
typedef unsigned      Ctypes__unsigned;
typedef unsigned      Ctypes__unsigned_int;
typedef unsigned long Ctypes__unsigned_long;
typedef unsigned long Ctypes__unsigned_long_int;
typedef void*         Ctypes__void_star;
typedef m3_dev_t      Utypes__dev_t;
typedef m3_gid_t      Utypes__gid_t;
typedef m3_ino_t      Utypes__ino_t;
typedef m3_mode_t     Utypes__mode_t;
typedef m3_nlink_t    Utypes__nlink_t;
typedef m3_pid_t      Utypes__pid_t;
typedef m3_pthread_t  ThreadPThread__pthread_t;
typedef m3_off_t      Utypes__off_t;
typedef size_t        Utypes__size_t;             // redundant
typedef m3_uid_t      Utypes__uid_t;

#define Csignal__Handler Csignal__Handler            /* inhibit m3c type */
typedef void (__cdecl*   Csignal__Handler)(int s);

#define Csetjmp__jmp_buf            Csetjmp__jmp_buf            /* inhibit m3c type */
typedef jmp_buf*      Csetjmp__jmp_buf;

#define ContextC__T                    ContextC__T                    /* inhibit m3c type */
#define CoroutineUcontext__Arg         CoroutineUcontext__Arg         /* inhibit m3c type */
#define CoroutineUcontext__Entry       CoroutineUcontext__Entry       /* inhibit m3c type */
#define ContextC__untraced_ref_integer ContextC__untraced_ref_integer /* inhibit m3c type */

// CoroutineUcontext__Arg is a pointer to a struct (CoroutineUcontext.Arg) however,
// the C code does not derefernce it and the Modula-3 code defines a different name
// for it (hashed), then casts its address to this. Therefore, the struct
// does not need to be defined.
typedef void* CoroutineUcontext__Arg;
typedef void (__cdecl*CoroutineUcontext__Entry)(CoroutineUcontext__Arg);
struct ContextC__TValue;
typedef struct ContextC__TValue ContextC__TValue;
typedef        ContextC__TValue* ContextC__T;
typedef INTEGER* ContextC__untraced_ref_integer;

/*
 m3_pthread_t is void*.
 pthread_t might be any of: size_t, ptrdiff_t, int, void*, another pointer.
 pthread_t will not be larger than a pointer/size_t. (see Unix__Assertions)
 Only convert integers to/from integers, and pointer-sized integers to/from pointers.
 That is, for example, do NOT convert int <=> pointer.
 */
#define PTHREAD_TO_M3(x)   ((m3_pthread_t)(WORD_T)(x))
#define PTHREAD_FROM_M3(x) ((pthread_t)(WORD_T)(x))


struct m3_stat_t;
typedef struct m3_stat_t m3_stat_t;

#define Ustat__struct_stat_star Ustat__struct_stat_star /* inhibit m3c type */
typedef m3_stat_t* Ustat__struct_stat_star;

int __cdecl Ustat__fstat(int fd, m3_stat_t* m3st);
int __cdecl Ustat__lstat(const char* path, m3_stat_t* m3st);
int __cdecl Ustat__stat(const char* path, m3_stat_t* m3st);

// wasi-libc declares socklen_t (unsigned 32 bit); m3_socklen_t is the idealised form.
typedef WORD_T m3_socklen_t;
#define m3c_socklen_t socklen_t

#define Usocket__socklen_t Usocket__socklen_t /* inhibit m3c type */
typedef m3_socklen_t Usocket__socklen_t;

typedef struct {
/* verified to exactly match struct linger in UnixC.c, except for Cygwin */
    int onoff;
    int linger;
} m3_linger_t;

// This is very unusual. Maybe it should be changed.
// The C functions take a union. The .i3 files claim
// a pointer to one specific variant.
//
// Alternatively the C functions could also take the member
// and cast it back to the union.
//
// More alternatively, there should be separate C functions for each union
// variant and Modula-3 should chose.
#define       Usocket__struct_sockaddr_in_star Usocket__struct_sockaddr_in_star       /* inhibit m3c type */
#define Usocket__const_struct_sockaddr_in_star Usocket__const_struct_sockaddr_in_star /* inhibit m3c type */
#define Usocket__socklen_t_star                Usocket__socklen_t_star                /* inhibit m3c type */
#define Usocket__socklen_t                     Usocket__socklen_t                     /* inhibit m3c type */
typedef       M3SockAddrUnionAll*              Usocket__struct_sockaddr_in_star;
typedef const M3SockAddrUnionAll*              Usocket__const_struct_sockaddr_in_star;
typedef m3_socklen_t                           Usocket__socklen_t;
typedef m3_socklen_t*                          Usocket__socklen_t_star;

int __cdecl Usocket__listen(int s, int backlog);
int __cdecl Usocket__shutdown(int s, int how);
int __cdecl Usocket__socket(int af, int type, int protocol);
int __cdecl Usocket__bind(int s, const M3SockAddrUnionAll*, m3_socklen_t);
int __cdecl Usocket__connect(int s, const M3SockAddrUnionAll*, m3_socklen_t);
ssize_t __cdecl Usocket__sendto(int s, const void* msg, size_t length, int flags, const M3SockAddrUnionAll*, m3_socklen_t);
int __cdecl Usocket__setsockopt(int s, int level, int optname, const void* optval, m3_socklen_t len);
int __cdecl Usocket__getpeername(int s, M3SockAddrUnionAll*, m3_socklen_t*);
int __cdecl Usocket__getsockname(int s, M3SockAddrUnionAll*, m3_socklen_t*);
int __cdecl Usocket__accept(int s, M3SockAddrUnionAll*, m3_socklen_t*);
int __cdecl Usocket__getsockopt(int s, int level, int optname, void* optval, m3_socklen_t*);
ssize_t __cdecl Usocket__recvfrom(int s, void* buf, size_t len, int flags, M3SockAddrUnionAll*, m3_socklen_t*);

DIR* __cdecl Udir__opendir(const char* a);
#define Udir__DIR_star Udir__DIR_star /* inhibit m3c type */
typedef DIR*           Udir__DIR_star;
#define Udir__struct_dirent_star Udir__struct_dirent_star /* inhibit m3c type */
STRUCT_TYPEDEF(dirent)
typedef dirent* Udir__struct_dirent_star;

// char* (caddr_t) instead of void* for default Solaris
typedef char* caddr_t;
typedef caddr_t Umman__caddr_t;
#define Umman__caddr_t Umman__caddr_t /* inhibit m3c type */
int __cdecl Umman__mprotect(caddr_t addr, size_t len, int prot);
void* __cdecl Umman__mmap(caddr_t addr, size_t len, int prot, int flags, int fd, m3_off_t off);
int __cdecl Umman__munmap(caddr_t addr, size_t len);

ssize_t __cdecl Uuio__read(int, void*, size_t);
ssize_t __cdecl Uuio__write(int, const void*, size_t);

typedef INT64 m3_time64_t;

#define Utime__time_t Utime__time_t /* inhibit m3c type */
typedef /*const*/ m3_time64_t Utime__time_t; /* TODO READONLY should imply const */

m3_time64_t __cdecl Utime__time(m3_time64_t* tloc);
char* __cdecl Utime__ctime(/*TODO const*/ m3_time64_t* m);
void __cdecl Utime__tzset(void);

#if 1 /* Some compilers don't like this, will adjust as needed. e.g. old SGI */
#if __GNUC__ /* gcc 4.8 warns about unused local typedefs. */
#define GCC_ATTRIBUTE_UNUSED __attribute__ ((unused))
#else
#define GCC_ATTRIBUTE_UNUSED /* nothing */
#endif
#define M3_STATIC_ASSERT(expr) GCC_ATTRIBUTE_UNUSED typedef char M3PASTE(m3_static_assert, __LINE__)[(expr)?1:-1]
#else
#define M3_STATIC_ASSERT(expr) assert(expr)
#endif

#define M3_FIELD_SIZE(type, field) (sizeof((type*)0)->field)
#define M3_SIZE_THROUGH_FIELD(type, field) (offsetof(type, field) + M3_FIELD_SIZE(type, field))

void __cdecl Unix__Assertions(void);
void __cdecl Usocket__Assertions(void);

int __cdecl Unix__open(const char* path, int flags, m3_mode_t mode);
int __cdecl Unix__mkdir(const char* path, m3_mode_t mode);
int __cdecl Unix__ftruncate(int fd, m3_off_t length);
m3_off_t __cdecl Unix__lseek(int fd, m3_off_t offset, int whence);
m3_off_t __cdecl Unix__tell(int fd);
int __cdecl Unix__fcntl(int fd, INTEGER request, INTEGER arg);
int __cdecl Unix__ioctl(int fd, INTEGER request, ADDRESS argp);
int __cdecl Unix__mknod(const char* path, m3_mode_t mode, m3_dev_t dev);
m3_mode_t __cdecl Unix__umask(m3_mode_t newmask);

STRUCT_TYPEDEF(m3_hostent_t)

#define Unetdb__struct_hostent_star Unetdb__struct_hostent_star /* inhibit m3c type */
typedef m3_hostent_t* Unetdb__struct_hostent_star;

m3_hostent_t* __cdecl Unetdb__gethostbyname(const char* name, m3_hostent_t* m3);
m3_hostent_t* __cdecl Unetdb__gethostbyaddr(const char* addr, int len, int type, m3_hostent_t* m3);

STRUCT_TYPEDEF(m3_group_t)

#define Ugrp__struct_group_star Ugrp__struct_group_star /* inhibit m3c type */
typedef m3_group_t* Ugrp__struct_group_star;

m3_group_t* __cdecl Ugrp__getgrent(m3_group_t* m3group);
m3_group_t* __cdecl Ugrp__getgrgid(m3_group_t* m3group, m3_gid_t gid);
m3_group_t* __cdecl Ugrp__getgrnam(m3_group_t* m3group, const char* name);
void __cdecl Ugrp__setgrent(void);
void __cdecl Ugrp__endgrent(void);

int __cdecl Unix__link(const char* name1, const char* name2);
int __cdecl Unix__chmod(const char* path, m3_mode_t mode);
int __cdecl Unix__fchmod(int fd, m3_mode_t mode);
int __cdecl Unix__chown(const char* path, m3_uid_t owner, m3_gid_t group);
int __cdecl Unix__fchown(int fd, m3_uid_t owner, m3_gid_t group);
int __cdecl Unix__creat(const char* path, m3_mode_t mode);
int __cdecl Unix__dup(int oldd);

// TODO widen to INTEGER
UINT32 __cdecl Uin__ntohl(UINT32 x);
UINT16 __cdecl Uin__ntohs(UINT16 x);
UINT32 __cdecl Uin__htonl(UINT32 x);
UINT16 __cdecl Uin__htons(UINT16 x);

// TODO C should not use TEXT, i.e. for precise compacting GC.
const char*
__cdecl
M3toC__SharedTtoS(TEXT);

void
__cdecl
M3toC__FreeSharedS(TEXT, const char*);

TEXT
__cdecl
M3toC__CopyStoT(const char*);

TEXT
__cdecl
M3toC__StoT(const char*);

/* This MUST match DatePosix.i3.T.
 * The fields are ordered by size and alphabetically.
 */
#define DatePosix__T DatePosix__T /* inhibit m3c type */

typedef struct {
    const char* zone;
    int day;
    int gmt;     // boolean
    int hour;
    int minute;
    int month;
    int offset;
    int second;
    int unknown; // boolean
    int weekDay;
    int year;
} DatePosix__T;

void
__cdecl
DatePosix__FromTime(double t, INTEGER zone, DatePosix__T* date);

double
__cdecl
DatePosix__ToTime(/*const*/ DatePosix__T* date);

void
__cdecl
DatePosix__TypeCheck(/*const*/ DatePosix__T* d, INTEGER sizeof_DateT);

void
__cdecl
Scheduler__DisableScheduling(void);

void
__cdecl
Scheduler__EnableScheduling(void);

void
__cdecl
Process__RegisterExitor(void (__cdecl*)(void));

// GET_PC (used by RTSignalC) is provided by the shims above: no machine
// context is ever delivered to a wasm program.

typedef time_t m3_time_t;

// Is this portable?
STRUCT_TYPEDEF(passwd)

#define Upwd__struct_passwd_star Upwd__struct_passwd_star /* inhibit m3c type */
typedef passwd* Upwd__struct_passwd_star;

passwd* __cdecl Upwd__getpwuid(m3_uid_t);
passwd* __cdecl Upwd__getpwnam(char*);

m3_pid_t __cdecl Uprocess__getpid (void);

#if 0 // This would be nice, but structural type equivalence gets
      // in the way. There are other equivalent types
      // and the names clash.
#define Unix__PipeArray Unix__PipeArray /* inhibit m3c type */
STRUCT_TYPEDEF(Unix__PipeArray)
struct Unix__PipeArray
{
    int files [2];
};

int __cdecl Unix__pipe (Unix__PipeArray* files);

#else

int __cdecl UnixC__pipe (int* files);

#endif

// See RTMachine.i3, RTStack.i3, RTStackC.c
// TYPE Frame = RECORD pc, sp: ADDRESS END;
#define RTStack__Frame RTStack__Frame /* inhibit m3c type */
STRUCT_TYPEDEF(RTStack__Frame)
struct RTStack__Frame
{
  ADDRESS pc; // program counter, instruction pointer, etc.
  ADDRESS sp; // stack pointer
};


#define ThreadPThread_pthread_mutex_t  ThreadPThread_pthread_mutex_t  /* inhibit m3c type */
#define ThreadPThread_pthread_cond_t   ThreadPThread_pthread_cond_t   /* inhibit m3c type */
#define ThreadPThread__pthread_mutex_t ThreadPThread__pthread_mutex_t /* inhibit m3c type */
#define ThreadPThread__pthread_cond_t  ThreadPThread__pthread_cond_t  /* inhibit m3c type */
#define ThreadPThread__const_pthread_mutex_t ThreadPThread__const_pthread_mutex_t /* inhibit m3c type */
#define ThreadPThread__const_pthread_cond_t  ThreadPThread__const_pthread_cond_t  /* inhibit m3c type */
typedef               pthread_mutex_t* ThreadPThread_pthread_mutex_t;
typedef               pthread_cond_t*  ThreadPThread_pthread_cond_t;
typedef               pthread_mutex_t* ThreadPThread__pthread_mutex_t;
typedef               pthread_cond_t*  ThreadPThread__pthread_cond_t;
typedef               pthread_mutex_t* const ThreadPThread__const_pthread_mutex_t;
typedef               pthread_cond_t*  const ThreadPThread__const_pthread_cond_t;

#define ThreadInternal__FDSet ThreadInternal__FDSet /* inhibit m3c type */
typedef                fd_set ThreadInternal__FDSet;

#define ThreadPThread__siginfo_t ThreadPThread__siginfo_t /* inhibit m3c type */
typedef siginfo_t ThreadPThread__siginfo_t;

#define ThreadPThread__Activation ThreadPThread__Activation /* inhibit m3c type */
typedef void* ThreadPThread__Activation;

#define ThreadPThread__start_routine_t ThreadPThread__start_routine_t /* inhibit m3c type */
typedef void* (__cdecl*ThreadPThread__start_routine_t)(void*);

#define ThreadPThread__ProcessThreadStack ThreadPThread__ProcessThreadStack
typedef void (__cdecl*ThreadPThread__ProcessThreadStack)(void* start, void* limit);

#define RT0__Binder RT0__Binder /* inhibit m3c type */
// The correct type for RT0__Binder is:
// typedef RT0__Module* (__cdecl*RT0__Binder)(INTEGER mode);
// but we cannot use that due to type collision hashes,
// until/unless significant m3c changes.
// This works:
typedef void (__cdecl*M3PROC)(void); // from MxGen.m3
typedef M3PROC RT0__Binder;
// The actual use and pass casts and so getting the type correct here does
// not really matter. What matters is that it is the same in all function
// declarations/definitions.


typedef union m3core_trace_t
{
    int all;
    struct
    {
        unsigned chdir : 1;
        unsigned close : 1;
        unsigned creat : 1;
        unsigned fstat : 1;
        unsigned open : 1;
        unsigned readdir : 1;
        unsigned stat : 1;
        unsigned write : 1;
    } s;
} m3core_trace_t;

extern m3core_trace_t m3core_trace;

#ifdef __cplusplus
} /* extern "C" */
#endif

// from m3c: alloca
#ifndef alloca
#define alloca __builtin_alloca
#endif

// ===== wasm32 / Target agreement ==========================================
// The Modula-3 side is compiled for wasm32 (32 bit INTEGER, ADDRESS, WORD).
// If any of these fail, the wrong target or sysroot is in effect.
M3_STATIC_ASSERT(sizeof(void*)     == 4);
M3_STATIC_ASSERT(sizeof(long)      == 4);
M3_STATIC_ASSERT(sizeof(INTEGER)   == 4);
M3_STATIC_ASSERT(sizeof(WORD_T)    == 4);
M3_STATIC_ASSERT(sizeof(ADDRESS)   == 4);
M3_STATIC_ASSERT(sizeof(INT32)     == 4);
M3_STATIC_ASSERT(sizeof(LONGINT)   == 8);
M3_STATIC_ASSERT(sizeof(m3_off_t)  == 8);
M3_STATIC_ASSERT(sizeof(m3_time64_t) == 8);
M3_STATIC_ASSERT(sizeof(socklen_t) <= sizeof(m3_socklen_t));

#endif
