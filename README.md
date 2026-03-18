<h1 align="center">DarwinFUSE</h1>
<p align="center">
  <strong>A complete FUSE implementation for macOS — no kernel extension, no SIP changes, no third-party dependencies.</strong>
</p>

DarwinFUSE is a drop-in replacement for macFUSE that runs entirely in userspace.
It translates FUSE callbacks into NFSv4 operations over a localhost loopback server,
using macOS's built-in `mount_nfs` to mount the filesystem. The result: full FUSE
compatibility without touching the kernel.

> **No kext. No System Extension. No SIP disable. No macFUSE installation.**
>
> Works on every Mac from macOS 12 Monterey onwards, including Apple Silicon,
> with zero system modifications.

## Installation

### GUI Installer (recommended)

Download the latest `.pkg` from the [Releases](https://github.com/marcelcotta/DarwinFUSE/releases) page and open it.

The installer checks for an existing macFUSE installation and will guide you through
removal if needed. After installing DarwinFUSE, existing FUSE programs (sshfs, encfs,
ntfs-3g, ...) work without recompilation.

An uninstaller app is included at `/Applications/DarwinFUSE/Uninstall DarwinFUSE.app`.

### Build from source

```sh
make                        # builds libdarwinfuse.a + libdarwinfuse.2.dylib
sudo make install           # installs to /usr/local with macFUSE-compatible symlinks
make pkg                    # builds a .pkg installer into build/
```

### Command-line installer

```sh
sudo ./installer/install.sh
```

### Uninstall

Either open `/Applications/DarwinFUSE/Uninstall DarwinFUSE.app` or run:

```sh
sudo ./installer/uninstall.sh
```

## How It Works

```
Your FUSE program (sshfs, encfs, ntfs-3g, ...)
    | fuse_operations callbacks
DarwinFUSE (libfuse.2.dylib / libdarwinfuse.a)
    | NFSv4 COMPOUND translation
NFS server on 127.0.0.1:<ephemeral port>
    | mount_nfs (built into macOS)
/your/mount/point
```

When you call `fuse_main()`, DarwinFUSE:

1. Starts a lightweight NFSv4 TCP server on `127.0.0.1` with an ephemeral port
2. Calls `mount_nfs` to mount the server at your chosen mount point
3. Translates incoming NFS operations into your `fuse_operations` callbacks
4. Optionally daemonizes and runs a multi-threaded worker pool

Your FUSE program doesn't need to know or care that NFS is involved — the API
is the same `fuse_main()` / `fuse_get_context()` / `fuse_operations` you'd use
with macFUSE or libfuse on Linux.

## macFUSE Compatibility

DarwinFUSE implements the full libfuse 2.9 API plus macFUSE's Apple-specific
extensions. It installs as `libfuse.2.dylib` with the same install_name and
version numbers as macFUSE, so existing compiled binaries work unchanged.

### What gets installed

| Path | Description |
|------|-------------|
| `/usr/local/lib/libfuse.2.dylib` | Dynamic library (macFUSE-compatible install_name) |
| `/usr/local/lib/libfuse.dylib` | Symlink |
| `/usr/local/lib/libdarwinfuse.a` | Static library |
| `/usr/local/include/fuse/` | macFUSE-compatible headers |
| `/usr/local/include/darwinfuse/` | DarwinFUSE headers |
| `/usr/local/lib/pkgconfig/fuse.pc` | macFUSE-compatible pkg-config |
| `/Applications/DarwinFUSE/` | Uninstaller app |

### FUSE Operations

| Category | Callbacks | Status |
|----------|-----------|--------|
| **File metadata** | `getattr`, `fgetattr`, `access`, `readlink`, `utimens`, `chmod`, `chown`, `truncate`, `ftruncate` | All implemented |
| **File I/O** | `open`, `create`, `read`, `write`, `flush`, `release`, `fsync` | All implemented |
| **Directories** | `mkdir`, `rmdir`, `opendir`, `readdir`, `releasedir`, `fsyncdir` | All implemented |
| **Namespace** | `unlink`, `rename`, `link`, `symlink`, `mknod` | All implemented |
| **Extended attrs** | `setxattr`, `getxattr`, `listxattr`, `removexattr` | All implemented (Apple `position` param supported) |
| **Filesystem** | `statfs`, `init`, `destroy` | All implemented |
| **Locking** | `lock`, `flock` | Declared (passthrough stubs) |
| **Advanced** | `ioctl`, `poll`, `fallocate`, `bmap` | Declared |
| **macFUSE extensions** | `getxtimes`, `setcrtime`, `setbkuptime`, `setchgtime`, `chflags`, `setattr_x`, `fsetattr_x`, `exchange`, `setvolname`, `statfs_x`, `renamex` | All declared; `getxtimes`/`setcrtime`/`setbkuptime` wired through NFSv4 |

### High-Level API

| Function | Status |
|----------|--------|
| `fuse_main` / `fuse_main_real` | Implemented |
| `fuse_mount` / `fuse_unmount` | Implemented |
| `fuse_new` / `fuse_destroy` | Implemented |
| `fuse_loop` / `fuse_loop_mt` | Implemented (thread pool) |
| `fuse_exit` | Implemented |
| `fuse_get_context` | Implemented (uid, gid, pid, private_data, umask) |
| `fuse_get_session` | Implemented |
| `fuse_set_signal_handlers` / `fuse_remove_signal_handlers` | Implemented |
| `fuse_parse_cmdline` | Implemented |
| `fuse_daemonize` | Implemented |
| `fuse_opt_parse` / `fuse_opt_add_arg` / `fuse_opt_free_args` / ... | All implemented |
| `fuse_version` | Implemented (returns 26) |
| `fuse_getgroups` / `fuse_interrupted` | Implemented |

### Capability Flags

All standard and macFUSE capability flags are declared:

```
FUSE_CAP_ASYNC_READ, POSIX_LOCKS, ATOMIC_O_TRUNC, EXPORT_SUPPORT,
BIG_WRITES, DONT_MASK, SPLICE_WRITE/MOVE/READ, FLOCK_LOCKS, IOCTL_DIR
```

macFUSE extensions (advertised in `conn->capable` on macOS):

```
FUSE_CAP_XTIMES, CASE_INSENSITIVE, VOL_RENAME, ALLOCATE, EXCHANGE_DATA
```

Including the `FUSE_ENABLE_XTIMES()` / `FUSE_ENABLE_SETVOLNAME()` / `FUSE_ENABLE_CASE_INSENSITIVE()` convenience macros.

### What's Not Implemented

These features have no NFSv4 equivalent and exist only as struct declarations
for compilation compatibility:

- **`ioctl`** — no mechanism to tunnel arbitrary ioctls over NFS
- **`poll`** — NFS has no file-descriptor polling
- **`write_buf` / `read_buf`** — zero-copy optimization, not applicable over TCP
- **`exchange`** — atomic file data exchange (macFUSE-only, no known users)
- **`renamex`** — `RENAME_SWAP`/`RENAME_EXCL` (macFUSE-only)
- **File locking** — `lock`/`flock` accept and acknowledge requests but don't enforce byte-range locks

None of these are used by sshfs, encfs, or Basalt. ntfs-3g uses `ioctl` for
volume-level operations that don't apply to the DarwinFUSE use case.

## Tested With

| FUSE Client | Callbacks Used | Status |
|-------------|---------------|--------|
| **Basalt** (encryption volumes) | ~12 core ops | Fully working |
| **sshfs** | ~26 ops + fuse_opt | API-complete |
| **encfs** | ~31 ops + xattrs | API-complete |
| **ntfs-3g** | ~33 ops + xtimes | API-complete (minus ioctl) |

## Quick Start

```sh
make examples
mkdir -p /tmp/hello
sudo ./examples/hello /tmp/hello
cat /tmp/hello/volume.dmg    # "Hello from DarwinFUSE!"
umount /tmp/hello
```

## Using in Your Project

Link against `libdarwinfuse.a` (static) or `libfuse.dylib` (dynamic) and include `<fuse.h>`:

```c
#define FUSE_USE_VERSION 26
#include <fuse.h>

static int my_getattr(const char *path, struct stat *stbuf) { /* ... */ }
static int my_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                      off_t offset, struct fuse_file_info *fi) { /* ... */ }
static int my_read(const char *path, char *buf, size_t size, off_t offset,
                   struct fuse_file_info *fi) { /* ... */ }

static struct fuse_operations ops = {
    .getattr = my_getattr,
    .readdir = my_readdir,
    .read    = my_read,
};

int main(int argc, char *argv[]) {
    return fuse_main(argc, argv, &ops, NULL);
}
```

Compile:

```sh
cc -o myfs myfs.c $(pkg-config --cflags --libs fuse)
# or directly:
cc -o myfs myfs.c -I/usr/local/include/fuse -L/usr/local/lib -lfuse
```

### Component API (sshfs-style)

For programs that need separate mount/loop control:

```c
struct fuse_args args = FUSE_ARGS_INIT(argc, argv);
struct fuse_chan *ch = fuse_mount("/mnt/point", &args);
struct fuse *f = fuse_new(ch, &args, &ops, sizeof(ops), NULL);
fuse_loop(f);  /* or fuse_loop_mt(f) */
fuse_destroy(f);
fuse_unmount("/mnt/point", ch);
```

## Architecture

```
include/
    fuse.h              Public API (libfuse 2.9 + macFUSE compatible)
    fuse_opt.h          Option parsing API
    fuse_common.h       Compatibility shim

src/
    darwinfuse.c        fuse_main, component API, signal handling, daemonization
    nfs4_ops.c          NFSv4 COMPOUND dispatcher (40+ operation handlers)
    nfs4_ops.h          NFSv4 constants, state structures
    nfs4_server.c       TCP server, poll loop, thread pool
    nfs4_server.h       Server lifecycle API
    nfs4_xdr.c          XDR encoding/decoding
    nfs4_xdr.h          XDR buffer types
    rpc.c               ONC RPC message framing
    inode_table.c       Dynamic inode table (path <-> inode, FNV-1a hash)
    inode_table.h       Inode table API (incl. xattr virtual inodes)
    fuse_opt.c          fuse_opt_parse implementation
    fuse_context.h      Thread-local context management

installer/
    install.sh          Command-line installer
    uninstall.sh        Command-line uninstaller
    build_pkg.sh        Builds .pkg GUI installer
    Distribution.xml    macOS installer distribution (multilingual)
    uninstall.applescript   Uninstaller app source (multilingual)
    resources/          Localized installer screens (en, de, fr, es, ja, zh-Hans)
```

## Replacing macFUSE

DarwinFUSE is designed as a complete macFUSE replacement. To switch:

1. Uninstall macFUSE using its built-in uninstaller (System Settings > macFUSE > Remove)
2. Optionally re-enable SIP (Recovery Mode > Startup Security Utility > Full Security)
3. Install DarwinFUSE via the `.pkg` installer or `sudo make install`

Existing Homebrew-installed FUSE programs will work without reinstallation because
DarwinFUSE installs `libfuse.2.dylib` with the same install_name and library version
numbers as macFUSE.

## Origins

DarwinFUSE was created for [Basalt](https://github.com/marcelcotta/Basalt),
a TrueCrypt-compatible encryption tool, to mount encrypted volumes on macOS
without requiring macFUSE or kernel extensions. It has since grown into a
general-purpose FUSE implementation suitable for any libfuse 2.x client.

## License

MIT License. Copyright (c) 2026 Marcel Cotta.
