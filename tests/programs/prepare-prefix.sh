#!/bin/bash
# Lay out the library built from the working tree like an installation, in a scratch prefix.
set -euo pipefail
S="$1"; D="${2:-$(cd "$(dirname "$0")/../.." && pwd)}"; P="$S/dfuse"
rm -rf "$P"; mkdir -p "$P/lib/pkgconfig" "$P/include/fuse"
for h in fuse.h fuse_common.h fuse_opt.h fuse_lowlevel.h fuse_darwin.h; do cp "$D/include/$h" "$P/include/fuse/$h"; done
printf '#include "fuse/fuse.h"\n' > "$P/include/fuse.h"
cp "$D/libdarwinfuse.2.dylib" "$P/lib/libfuse.2.dylib"
ln -s libfuse.2.dylib "$P/lib/libfuse.dylib"
sed -e "s|@PREFIX@|$P|" -e 's|@VERSION@|2.9.9|' "$D/fuse.pc.in" > "$P/lib/pkgconfig/fuse.pc"
echo "prefix ready"
