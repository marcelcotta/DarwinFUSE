#!/bin/bash
#
# DarwinFUSE — Command-line installer
#
# Installs DarwinFUSE as a drop-in replacement for macFUSE.
# Must be run as root (sudo).
#
# Copyright (c) 2026 Marcel Cotta. All rights reserved.
# Licensed under the MIT License.
#

set -euo pipefail

PREFIX="/usr/local"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

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
    err "This installer must be run as root."
    echo "  Usage: sudo $0"
    exit 1
fi

# ---- macOS version check ----

MACOS_VERSION="$(sw_vers -productVersion)"
MACOS_MAJOR="${MACOS_VERSION%%.*}"

if [[ "$MACOS_MAJOR" -lt 12 ]]; then
    err "DarwinFUSE requires macOS 12 (Monterey) or later."
    err "Detected: macOS $MACOS_VERSION"
    exit 1
fi

info "macOS $MACOS_VERSION detected."

# ---- Check for macFUSE ----

MACFUSE_INSTALLED=0

if [[ -d "/Library/Filesystems/macfuse.fs" ]]; then
    MACFUSE_INSTALLED=1
fi

if [[ -d "/Library/Frameworks/macFUSE.framework" ]]; then
    MACFUSE_INSTALLED=1
fi

if [[ -f "/usr/local/lib/libfuse.2.dylib" ]]; then
    # Check if existing libfuse is from macFUSE (not us)
    EXISTING_ID="$(otool -D /usr/local/lib/libfuse.2.dylib 2>/dev/null | tail -1 || true)"
    if [[ -f "/Library/Filesystems/macfuse.fs/Contents/Info.plist" ]]; then
        MACFUSE_INSTALLED=1
    fi
fi

if [[ "$MACFUSE_INSTALLED" -eq 1 ]]; then
    echo ""
    warn "macFUSE is currently installed on this system."
    echo ""
    echo -e "  ${BOLD}Please uninstall macFUSE first to avoid conflicts:${NC}"
    echo ""
    echo "  1. Open macFUSE Preferences (System Settings > macFUSE)"
    echo "     or run the uninstaller directly:"
    echo -e "     ${BOLD}open /Library/Filesystems/macfuse.fs/Contents/Resources/uninstall_macfuse.app${NC}"
    echo ""
    echo "  2. After uninstalling macFUSE, you can re-enable SIP:"
    echo ""
    echo -e "     ${BOLD}Option A (GUI — no Terminal needed):${NC}"
    echo "     - Restart into Recovery Mode (hold Power button on Apple Silicon)"
    echo "     - Menu: Utilities > Startup Security Utility"
    echo "     - Select your startup disk, enable Full Security"
    echo "     - Restart normally"
    echo ""
    echo -e "     ${BOLD}Option B (Terminal):${NC}"
    echo "     - Restart into Recovery Mode (hold Power button on Apple Silicon)"
    echo "     - Menu: Utilities > Terminal"
    echo -e "     - Run: ${BOLD}csrutil enable${NC}"
    echo "     - Restart normally"
    echo ""
    echo "  3. Then re-run this installer."
    echo ""

    # Allow override for advanced users
    read -rp "Continue anyway? (NOT recommended) [y/N] " REPLY
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        info "Installation cancelled."
        exit 1
    fi
    warn "Proceeding despite macFUSE being installed. Conflicts may occur."
fi

# ---- Check for OSXFUSE (legacy) ----

if [[ -d "/Library/Frameworks/OSXFUSE.framework" ]] || \
   [[ -f "/usr/local/lib/libosxfuse.2.dylib" ]]; then
    warn "Legacy OSXFUSE installation detected."
    echo "  Consider removing it: sudo /Library/Filesystems/osxfuse.fs/Contents/Resources/uninstall_osxfuse.app"
fi

# ---- Build if needed ----

if [[ ! -f "$PROJECT_DIR/libdarwinfuse.a" ]] || \
   [[ ! -f "$PROJECT_DIR/libdarwinfuse.2.dylib" ]]; then
    info "Building DarwinFUSE..."
    (cd "$PROJECT_DIR" && make clean && make all)
fi

# ---- Install ----

info "Installing DarwinFUSE to $PREFIX..."

# Create directories
install -d "$PREFIX/lib" "$PREFIX/lib/pkgconfig" \
           "$PREFIX/include/fuse" "$PREFIX/include/darwinfuse"

# Static library
info "  Installing static library..."
install -m 644 "$PROJECT_DIR/libdarwinfuse.a" "$PREFIX/lib/"

# Dynamic library — as libfuse.2.dylib for macFUSE binary compatibility
info "  Installing dynamic library..."
install -m 755 "$PROJECT_DIR/libdarwinfuse.2.dylib" "$PREFIX/lib/libfuse.2.dylib"
ln -sf libfuse.2.dylib "$PREFIX/lib/libfuse.dylib"
ln -sf libfuse.2.dylib "$PREFIX/lib/libdarwinfuse.2.dylib"
ln -sf libfuse.2.dylib "$PREFIX/lib/libdarwinfuse.dylib"

# Headers — fuse/ namespace (macFUSE compatible)
info "  Installing headers..."
install -m 644 "$PROJECT_DIR/include/fuse.h"        "$PREFIX/include/fuse/fuse.h"
install -m 644 "$PROJECT_DIR/include/fuse_opt.h"    "$PREFIX/include/fuse/fuse_opt.h"
install -m 644 "$PROJECT_DIR/include/fuse_common.h" "$PREFIX/include/fuse/fuse_common.h"

# Headers — darwinfuse/ namespace
install -m 644 "$PROJECT_DIR/include/fuse.h"     "$PREFIX/include/darwinfuse/fuse.h"
install -m 644 "$PROJECT_DIR/include/fuse_opt.h" "$PREFIX/include/darwinfuse/fuse_opt.h"

# Top-level fuse.h wrapper
printf '#include "fuse/fuse.h"\n' > "$PREFIX/include/fuse.h"

# pkg-config
info "  Installing pkg-config files..."
sed -e "s|@PREFIX@|$PREFIX|" -e "s|@VERSION@|1.0.0|" \
    "$PROJECT_DIR/darwinfuse.pc.in" > "$PREFIX/lib/pkgconfig/darwinfuse.pc"
sed -e "s|@PREFIX@|$PREFIX|" -e "s|@VERSION@|1.0.0|" \
    "$PROJECT_DIR/fuse.pc.in" > "$PREFIX/lib/pkgconfig/fuse.pc"

# ---- Create receipt marker ----

install -d "$PREFIX/share/darwinfuse"
cat > "$PREFIX/share/darwinfuse/receipt.json" <<RECEIPT
{
  "name": "DarwinFUSE",
  "version": "1.0.0",
  "installed": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "prefix": "$PREFIX"
}
RECEIPT

# ---- Done ----

echo ""
ok "DarwinFUSE installed successfully!"
echo ""
echo -e "  ${BOLD}What was installed:${NC}"
echo "    $PREFIX/lib/libfuse.2.dylib         (dynamic library)"
echo "    $PREFIX/lib/libfuse.dylib           (symlink)"
echo "    $PREFIX/lib/libdarwinfuse.a         (static library)"
echo "    $PREFIX/include/fuse/               (macFUSE-compatible headers)"
echo "    $PREFIX/include/darwinfuse/         (DarwinFUSE headers)"
echo "    $PREFIX/lib/pkgconfig/fuse.pc       (macFUSE-compatible pkg-config)"
echo "    $PREFIX/lib/pkgconfig/darwinfuse.pc (DarwinFUSE pkg-config)"
echo ""
echo -e "  ${BOLD}No kernel extension. No SIP changes. Pure userspace.${NC}"
echo ""
echo "  Existing FUSE programs (sshfs, encfs, ntfs-3g, ...) should"
echo "  work without recompilation."
echo ""
echo "  To uninstall: sudo $(dirname "$0")/uninstall.sh"
