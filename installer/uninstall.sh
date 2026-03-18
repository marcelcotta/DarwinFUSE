#!/bin/bash
#
# DarwinFUSE — Command-line uninstaller
#
# Removes all files installed by DarwinFUSE.
# Must be run as root (sudo).
#
# Copyright (c) 2026 Marcel Cotta. All rights reserved.
# Licensed under the MIT License.
#

set -euo pipefail

PREFIX="/usr/local"

# ---- Colors ----

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${BLUE}[DarwinFUSE]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARNING]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }

# ---- Root check ----

if [[ $EUID -ne 0 ]]; then
    err "This uninstaller must be run as root."
    echo "  Usage: sudo $0"
    exit 1
fi

# ---- Check if installed ----

if [[ ! -f "$PREFIX/share/darwinfuse/receipt.json" ]] && \
   [[ ! -f "$PREFIX/lib/libdarwinfuse.a" ]]; then
    warn "DarwinFUSE does not appear to be installed."
    exit 0
fi

# ---- Confirm ----

echo ""
info "This will remove DarwinFUSE from $PREFIX."
echo ""
read -rp "Continue? [y/N] " REPLY
if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    info "Uninstall cancelled."
    exit 0
fi

# ---- Remove files ----

info "Removing DarwinFUSE..."

# Libraries
rm -f  "$PREFIX/lib/libdarwinfuse.a"
rm -f  "$PREFIX/lib/libfuse.2.dylib"
rm -f  "$PREFIX/lib/libfuse.dylib"
rm -f  "$PREFIX/lib/libdarwinfuse.2.dylib"
rm -f  "$PREFIX/lib/libdarwinfuse.dylib"
# Also remove .la if it somehow exists
rm -f  "$PREFIX/lib/libfuse.la"

# Headers
rm -rf "$PREFIX/include/darwinfuse"
rm -rf "$PREFIX/include/fuse"
rm -f  "$PREFIX/include/fuse.h"

# pkg-config
rm -f  "$PREFIX/lib/pkgconfig/darwinfuse.pc"
rm -f  "$PREFIX/lib/pkgconfig/fuse.pc"

# Receipt
rm -rf "$PREFIX/share/darwinfuse"

# Forget pkg receipt (if installed via .pkg)
if pkgutil --pkg-info io.darwinfuse.pkg.core &>/dev/null; then
    pkgutil --forget io.darwinfuse.pkg.core 2>/dev/null || true
fi

echo ""
ok "DarwinFUSE has been removed."
echo ""
echo "  Note: FUSE-based programs (sshfs, ntfs-3g, etc.) will no longer"
echo "  work until you install either DarwinFUSE or macFUSE."
