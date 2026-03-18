#!/bin/bash
#
# DarwinFUSE — .pkg installer builder
#
# Builds a macOS .pkg installer using pkgbuild + productbuild.
# Can be run standalone or via `make pkg`.
#
# Usage: ./build_pkg.sh [version]
#
# Copyright (c) 2026 Marcel Cotta. All rights reserved.
# Licensed under the MIT License.
#

set -euo pipefail

VERSION="${1:-1.0.0}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/pkg"
STAGE_DIR="$BUILD_DIR/stage"
OUTPUT_DIR="$PROJECT_DIR/build"

echo "=== DarwinFUSE .pkg builder ==="
echo "    Version: $VERSION"
echo ""

# ---- Build libraries if needed ----

if [[ ! -f "$PROJECT_DIR/libdarwinfuse.a" ]] || \
   [[ ! -f "$PROJECT_DIR/libdarwinfuse.2.dylib" ]]; then
    echo "Building DarwinFUSE..."
    (cd "$PROJECT_DIR" && make all)
fi

# ---- Clean previous build ----

rm -rf "$BUILD_DIR"
mkdir -p "$STAGE_DIR" "$OUTPUT_DIR"

# ---- Create staging directory ----

echo "Creating staging directory..."

PREFIX="$STAGE_DIR/usr/local"
mkdir -p "$PREFIX/lib/pkgconfig"
mkdir -p "$PREFIX/include/fuse"
mkdir -p "$PREFIX/include/darwinfuse"
mkdir -p "$PREFIX/share/darwinfuse"

# Static library
cp "$PROJECT_DIR/libdarwinfuse.a" "$PREFIX/lib/"
chmod 644 "$PREFIX/lib/libdarwinfuse.a"

# Dynamic library
cp "$PROJECT_DIR/libdarwinfuse.2.dylib" "$PREFIX/lib/libfuse.2.dylib"
chmod 755 "$PREFIX/lib/libfuse.2.dylib"

# Headers — fuse/ namespace
cp "$PROJECT_DIR/include/fuse.h"        "$PREFIX/include/fuse/fuse.h"
cp "$PROJECT_DIR/include/fuse_opt.h"    "$PREFIX/include/fuse/fuse_opt.h"
cp "$PROJECT_DIR/include/fuse_common.h" "$PREFIX/include/fuse/fuse_common.h"
chmod 644 "$PREFIX/include/fuse/"*

# Headers — darwinfuse/ namespace
cp "$PROJECT_DIR/include/fuse.h"     "$PREFIX/include/darwinfuse/fuse.h"
cp "$PROJECT_DIR/include/fuse_opt.h" "$PREFIX/include/darwinfuse/fuse_opt.h"
chmod 644 "$PREFIX/include/darwinfuse/"*

# pkg-config — fuse.pc (macFUSE compatible)
sed -e 's|@PREFIX@|/usr/local|' -e "s|@VERSION@|$VERSION|" \
    "$PROJECT_DIR/fuse.pc.in" > "$PREFIX/lib/pkgconfig/fuse.pc"

# pkg-config — darwinfuse.pc
sed -e 's|@PREFIX@|/usr/local|' -e "s|@VERSION@|$VERSION|" \
    "$PROJECT_DIR/darwinfuse.pc.in" > "$PREFIX/lib/pkgconfig/darwinfuse.pc"

# Uninstall script (for CLI use)
cp "$SCRIPT_DIR/uninstall.sh" "$PREFIX/share/darwinfuse/uninstall.sh"
chmod 755 "$PREFIX/share/darwinfuse/uninstall.sh"

# Uninstaller app (GUI)
echo "Compiling uninstaller app..."
APPS_DIR="$STAGE_DIR/Applications/DarwinFUSE"
mkdir -p "$APPS_DIR"
osacompile -o "$APPS_DIR/Uninstall DarwinFUSE.app" "$SCRIPT_DIR/uninstall.applescript"

# ---- Prepare scripts ----

echo "Preparing install scripts..."

SCRIPTS_DIR="$BUILD_DIR/scripts"
mkdir -p "$SCRIPTS_DIR"

cp "$SCRIPT_DIR/scripts/preinstall"  "$SCRIPTS_DIR/"
cp "$SCRIPT_DIR/scripts/postinstall" "$SCRIPTS_DIR/"
chmod 755 "$SCRIPTS_DIR/preinstall" "$SCRIPTS_DIR/postinstall"

# Replace version placeholder in postinstall
sed -i '' "s|__VERSION__|$VERSION|g" "$SCRIPTS_DIR/postinstall"

# ---- Prepare Distribution.xml ----

DIST_XML="$BUILD_DIR/Distribution.xml"
sed "s|__VERSION__|$VERSION|g" "$SCRIPT_DIR/Distribution.xml" > "$DIST_XML"

# ---- Build component package ----

echo "Building component package..."

pkgbuild \
    --root "$STAGE_DIR" \
    --scripts "$SCRIPTS_DIR" \
    --identifier "io.darwinfuse.pkg.core" \
    --version "$VERSION" \
    --install-location "/" \
    "$BUILD_DIR/DarwinFUSE-core.pkg"

# ---- Build distribution package ----

echo "Building distribution package..."

RESOURCES_DIR="$BUILD_DIR/resources"
mkdir -p "$RESOURCES_DIR"
cp -R "$SCRIPT_DIR/resources/"*.lproj "$RESOURCES_DIR/"

productbuild \
    --distribution "$DIST_XML" \
    --resources "$RESOURCES_DIR" \
    --package-path "$BUILD_DIR" \
    "$OUTPUT_DIR/DarwinFUSE-$VERSION.pkg"

# ---- Cleanup intermediate files ----

rm -rf "$BUILD_DIR"

# ---- Done ----

echo ""
echo "=== Package built successfully ==="
echo "    $OUTPUT_DIR/DarwinFUSE-$VERSION.pkg"
echo ""
echo "Install with:"
echo "    open $OUTPUT_DIR/DarwinFUSE-$VERSION.pkg"
echo ""
echo "Or from command line:"
echo "    sudo installer -pkg $OUTPUT_DIR/DarwinFUSE-$VERSION.pkg -target /"
