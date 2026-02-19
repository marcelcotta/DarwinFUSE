/*
 * hello.c — Minimal DarwinFUSE example
 *
 * Mounts a read-only filesystem with a single file containing
 * "Hello from DarwinFUSE!". No kernel extension required.
 *
 * Build:  make examples
 * Usage:  mkdir -p /tmp/hello && sudo ./hello /tmp/hello
 * Check:  cat /tmp/hello/volume.dmg
 * Unmount: umount /tmp/hello
 *
 * NOTE: DarwinFUSE currently uses a fixed virtual filesystem layout
 *       with two entries: "volume.dmg" and "control". A future version
 *       will support arbitrary file/directory trees.
 */

#include <fuse.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>

static const char *hello_content = "Hello from DarwinFUSE!\n";

static int hello_getattr(const char *path, struct stat *st)
{
    memset(st, 0, sizeof(*st));

    if (strcmp(path, "/") == 0) {
        st->st_mode = S_IFDIR | 0755;
        st->st_nlink = 2;
        st->st_uid = getuid();
        st->st_gid = getgid();
        return 0;
    }

    if (strcmp(path, "/volume.dmg") == 0) {
        st->st_mode = S_IFREG | 0444;
        st->st_nlink = 1;
        st->st_size = (off_t)strlen(hello_content);
        st->st_uid = getuid();
        st->st_gid = getgid();
        return 0;
    }

    if (strcmp(path, "/control") == 0) {
        st->st_mode = S_IFREG | 0444;
        st->st_nlink = 1;
        st->st_size = 0;
        st->st_uid = getuid();
        st->st_gid = getgid();
        return 0;
    }

    return -ENOENT;
}

static int hello_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                          off_t offset, struct fuse_file_info *fi)
{
    (void)offset;
    (void)fi;

    if (strcmp(path, "/") != 0)
        return -ENOENT;

    filler(buf, ".", NULL, 0);
    filler(buf, "..", NULL, 0);
    filler(buf, "volume.dmg", NULL, 0);
    filler(buf, "control", NULL, 0);
    return 0;
}

static int hello_open(const char *path, struct fuse_file_info *fi)
{
    if (strcmp(path, "/volume.dmg") != 0 && strcmp(path, "/control") != 0)
        return -ENOENT;
    return 0;
}

static int hello_read(const char *path, char *buf, size_t size, off_t offset,
                       struct fuse_file_info *fi)
{
    (void)fi;

    if (strcmp(path, "/volume.dmg") != 0)
        return 0;

    size_t len = strlen(hello_content);
    if ((size_t)offset >= len)
        return 0;

    size_t avail = len - (size_t)offset;
    if (size > avail)
        size = avail;

    memcpy(buf, hello_content + offset, size);
    return (int)size;
}

static int hello_access(const char *path, int mask)
{
    if (strcmp(path, "/") == 0 ||
        strcmp(path, "/volume.dmg") == 0 ||
        strcmp(path, "/control") == 0)
        return 0;
    return -ENOENT;
}

static struct fuse_operations hello_ops = {
    .getattr = hello_getattr,
    .readdir = hello_readdir,
    .open    = hello_open,
    .read    = hello_read,
    .access  = hello_access,
};

int main(int argc, char *argv[])
{
    return fuse_main(argc, argv, &hello_ops, NULL);
}
