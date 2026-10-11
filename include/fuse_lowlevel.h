/*
 * fuse_lowlevel.h -- the part of the low-level API that DarwinFUSE provides
 *
 * Programs written for the high-level API sometimes include this header for a
 * single helper. DarwinFUSE has no low-level API (no fuse_lowlevel_new,
 * fuse_session_*, fuse_reply_*): programs that need those cannot use it.
 */

#ifndef DARWINFUSE_FUSE_LOWLEVEL_H
#define DARWINFUSE_FUSE_LOWLEVEL_H

#include "fuse_common.h"

#ifdef __cplusplus
extern "C" {
#endif

struct fuse_chan;

/*
 * Returns a file descriptor that belongs to the channel (the server's listening
 * socket), or -1. Programs use it to set FD_CLOEXEC; every descriptor of the
 * library is close-on-exec already.
 */
int fuse_chan_fd(struct fuse_chan *ch);

#ifdef __cplusplus
}
#endif

#endif /* DARWINFUSE_FUSE_LOWLEVEL_H */
