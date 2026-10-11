/*
 * passthrough.c -- test filesystem for DarwinFUSE (libfuse 2.x high-level API)
 *
 * Mirrors the directory named by $PFS_ROOT at the mount point. tests/run.sh
 * mounts it through DarwinFUSE and checks the result against the backing directory.
 */
#define FUSE_USE_VERSION 26
#include <fuse.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <unistd.h>

static char root[PATH_MAX];

static void full(char *out, const char *path) { snprintf(out, PATH_MAX, "%s%s", root, path); }
#define P(var, path) char var[PATH_MAX]; full(var, path)

static int p_getattr(const char *path, struct stat *st) { P(p, path); return lstat(p, st) == -1 ? -errno : 0; }

static int p_readlink(const char *path, char *buf, size_t size)
{
    P(p, path);
    ssize_t n = readlink(p, buf, size - 1);
    if (n == -1) return -errno;
    buf[n] = 0;
    return 0;
}

static int p_readdir(const char *path, void *buf, fuse_fill_dir_t filler, off_t off, struct fuse_file_info *fi)
{
    P(p, path);
    DIR *d = opendir(p);
    if (!d) return -errno;
    struct dirent *de;
    while ((de = readdir(d)) != NULL)
        if (filler(buf, de->d_name, NULL, 0)) break;
    closedir(d);
    return 0;
}

static int p_mknod(const char *path, mode_t mode, dev_t rdev)
{
    P(p, path);
    int r;
    if (S_ISREG(mode)) { r = open(p, O_CREAT | O_EXCL | O_WRONLY, mode); if (r >= 0) r = close(r); }
    else if (S_ISFIFO(mode)) r = mkfifo(p, mode);
    else r = mknod(p, mode, rdev);
    return r == -1 ? -errno : 0;
}

static int p_mkdir(const char *path, mode_t mode) { P(p, path); return mkdir(p, mode) == -1 ? -errno : 0; }
static int p_unlink(const char *path) { P(p, path); return unlink(p) == -1 ? -errno : 0; }
static int p_rmdir(const char *path) { P(p, path); return rmdir(p) == -1 ? -errno : 0; }
static int p_symlink(const char *from, const char *to) { P(t, to); return symlink(from, t) == -1 ? -errno : 0; }
static int p_link(const char *from, const char *to) { P(f, from); P(t, to); return link(f, t) == -1 ? -errno : 0; }
static int p_rename(const char *from, const char *to) { P(f, from); P(t, to); return rename(f, t) == -1 ? -errno : 0; }
static int p_chmod(const char *path, mode_t mode) { P(p, path); return chmod(p, mode) == -1 ? -errno : 0; }
static int p_chown(const char *path, uid_t u, gid_t g) { P(p, path); return lchown(p, u, g) == -1 ? -errno : 0; }
static int p_truncate(const char *path, off_t size) { P(p, path); return truncate(p, size) == -1 ? -errno : 0; }

static int p_utimens(const char *path, const struct timespec ts[2])
{
    P(p, path);
    return utimensat(AT_FDCWD, p, ts, AT_SYMLINK_NOFOLLOW) == -1 ? -errno : 0;
}

static int p_open(const char *path, struct fuse_file_info *fi)
{
    P(p, path);
    int fd = open(p, fi->flags);
    if (fd == -1) return -errno;
    fi->fh = (uint64_t) fd;
    return 0;
}

static int p_read(const char *path, char *buf, size_t size, off_t off, struct fuse_file_info *fi)
{
    ssize_t n = pread((int) fi->fh, buf, size, off);
    return n == -1 ? -errno : (int) n;
}

static int p_write(const char *path, const char *buf, size_t size, off_t off, struct fuse_file_info *fi)
{
    ssize_t n = pwrite((int) fi->fh, buf, size, off);
    return n == -1 ? -errno : (int) n;
}

static int p_statfs(const char *path, struct statvfs *sv) { P(p, path); return statvfs(p, sv) == -1 ? -errno : 0; }
static int p_release(const char *path, struct fuse_file_info *fi) { close((int) fi->fh); return 0; }
static int p_fsync(const char *path, int datasync, struct fuse_file_info *fi) { return fsync((int) fi->fh) == -1 ? -errno : 0; }

static struct fuse_operations ops = {
    .getattr = p_getattr, .readlink = p_readlink, .readdir = p_readdir, .mknod = p_mknod,
    .mkdir = p_mkdir, .unlink = p_unlink, .rmdir = p_rmdir, .symlink = p_symlink,
    .rename = p_rename, .link = p_link, .chmod = p_chmod, .chown = p_chown, .truncate = p_truncate,
    .utimens = p_utimens, .open = p_open, .read = p_read, .write = p_write,
    .statfs = p_statfs, .release = p_release, .fsync = p_fsync,
};

int main(int argc, char *argv[])
{
    const char *r = getenv("PFS_ROOT");
    if (!r) { fprintf(stderr, "PFS_ROOT not set\n"); return 2; }
    snprintf(root, sizeof root, "%s", r);
    return fuse_main(argc, argv, &ops, NULL);
}
