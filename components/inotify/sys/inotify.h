#ifndef __BSD_INOTIFY_H__
#define __BSD_INOTIFY_H__

#if defined (__STDC_VERSION__) && (__STDC_VERSION__ >= 199901L)
#include <stdint.h>
#define LIBINOTIFY_FLEXIBLE_ARRAY_MEMBER /**/
#else
#include <inttypes.h>
#define LIBINOTIFY_FLEXIBLE_ARRAY_MEMBER 0
#endif

#ifndef __THROW
  #ifdef __cplusplus
    #define __THROW throw()
  #else
    #define __THROW
  #endif
#endif

#define IN_SOCKBUFSIZE                  0
#define IN_DEF_SOCKBUFSIZE              4096
#define IN_MAX_QUEUED_EVENTS            1
#define IN_DEF_MAX_QUEUED_EVENTS        16384
#define IN_MAX_USER_INSTANCES           2
#define IN_DEF_MAX_USER_INSTANCES       2147483646

#define IN_CLOEXEC      02000000
#define IN_NONBLOCK     00004000
#define IN_DIRECT       0x80000000

__extension__ struct inotify_event
{
    int wd;
    uint32_t mask;
    uint32_t cookie;
    uint32_t len;
    char name[LIBINOTIFY_FLEXIBLE_ARRAY_MEMBER];
};

#define IN_ACCESS        0x00000001
#define IN_MODIFY        0x00000002
#define IN_ATTRIB        0x00000004
#define IN_CLOSE_WRITE   0x00000008
#define IN_CLOSE_NOWRITE 0x00000010
#define IN_CLOSE         (IN_CLOSE_WRITE | IN_CLOSE_NOWRITE)
#define IN_OPEN          0x00000020
#define IN_MOVED_FROM    0x00000040
#define IN_MOVED_TO      0x00000080
#define IN_MOVE          (IN_MOVED_FROM | IN_MOVED_TO)
#define IN_CREATE        0x00000100
#define IN_DELETE        0x00000200
#define IN_DELETE_SELF   0x00000400
#define IN_MOVE_SELF     0x00000800

#define IN_UNMOUNT      0x00002000
#define IN_Q_OVERFLOW   0x00004000
#define IN_IGNORED      0x00008000

#define IN_ONLYDIR      0x01000000
#define IN_DONT_FOLLOW  0x02000000
#define IN_EXCL_UNLINK  0x04000000
#define IN_MASK_ADD     0x20000000
#define IN_ISDIR        0x40000000
#define IN_ONESHOT      0x80000000

#define IN_ALL_EVENTS   (IN_ACCESS | IN_MODIFY | IN_ATTRIB | IN_CLOSE_WRITE | \
                         IN_CLOSE_NOWRITE | IN_OPEN | IN_MOVED_FROM | IN_MOVE_SELF | \
                         IN_MOVED_TO | IN_DELETE | IN_CREATE | IN_DELETE_SELF)

__BEGIN_DECLS

int inotify_init (void) __THROW;
int inotify_init1 (int flags) __THROW;
int inotify_add_watch (int fd, const char *name, uint32_t mask) __THROW;
int inotify_rm_watch (int fd, int wd) __THROW;

int libinotify_set_param (int fd, int param, intptr_t value) __THROW;
#define inotify_set_param(fd, p, v) libinotify_set_param(fd, p, v)

struct iovec;

int libinotify_direct_readv (int fd, struct iovec **events, int size, int no_block);
void libinotify_free_iovec (struct iovec *events);
int libinotify_direct_close (int fd);

__END_DECLS

#endif /* __BSD_INOTIFY_H__ */
