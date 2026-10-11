# Real programs on DarwinFUSE

These scripts run programs that were built from their own, unmodified sources against the
headers and library of DarwinFUSE and report what works. Run them from a normal Terminal
session (see `tests/run.sh`). `S` is a working directory of your choice:

```
S/dfuse/            prefix laid out like an installation (prepare-prefix.sh S)
S/build/sshfs/      sshfs 2.10, built out of tree
S/build/encfs/      encfs 1.9.5
S/build/ntfs3g/     ntfs-3g 2022.10.3
```

`prepare-prefix.sh S [DARWINFUSE_DIR]` copies the headers and `libdarwinfuse.2.dylib` (as
`libfuse.2.dylib`) of a working tree into `S/dfuse`. To test a release package instead,
copy the payload of the installer there in the same layout.

## Building the programs

Use `PKG_CONFIG_PATH=S/dfuse/lib/pkgconfig`; the programs then find DarwinFUSE exactly as
they would find macFUSE. `DYLD_LIBRARY_PATH=S/dfuse/lib` lets them load `libfuse.2.dylib`
from there (they record `/usr/local/lib/libfuse.2.dylib`).

- **sshfs 2.10** (`sshfs-2.10.tar.gz`, github.com/libfuse/sshfs; 3.x needs libfuse 3):
  `configure --prefix=... ` with
  `CFLAGS="-D_DARWIN_USE_64_BIT_INODE -Wno-implicit-function-declaration -Wno-int-conversion"`,
  then `make`. It needs `glib`.
- **encfs 1.9.5** (`encfs-1.9.5.tar.gz`, github.com/vgough/encfs): CMake with
  `-DFUSE_INCLUDE_DIR=S/dfuse/include/fuse -DFUSE_LIBRARIES=S/dfuse/lib/libfuse.2.dylib`
  (otherwise CMake may pick another FUSE, such as FUSE-T). Current compilers need two
  small changes in the unpacked sources: the old `cmake_minimum_required`/`cmake_policy`
  versions in the vendored `CMakeLists.txt` files raised to 3.5 (and `CMP0063` set to
  `NEW`), and `void operator()(NullKey *&)` in `encfs/NullCipher.cpp` changed to
  `void operator()(NullKey *)`.
- **ntfs-3g 2022.10.3** (tag archive, github.com/tuxera/ntfs-3g): `./autogen.sh` (needs
  `automake`, `libtool`), `configure --with-fuse=external --disable-ldconfig
  --disable-mount-helper`, `make`, then `make -C src ntfs-3g`. The low-level `lowntfs-3g`
  does not build against DarwinFUSE; that is expected. Run `src/.libs/ntfs-3g` directly:
  the libtool wrapper script runs under `/bin/sh`, which drops `DYLD_LIBRARY_PATH`.

## Running

```
test-sshfs.sh S      sshfs through a local sftp-server (fakessh), 18 checks
test-encfs.sh S      encfs, 27 checks including a remount
test-ntfs3g.sh S     ntfs-3g on a mkntfs image, 20 checks and ntfsfix afterwards
```
