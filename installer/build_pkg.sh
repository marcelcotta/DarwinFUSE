#!/bin/bash
#
# DarwinFUSE — .pkg installer builder
#
# Builds a macOS .pkg installer using pkgbuild + productbuild.
# Can be run standalone or via `make pkg`.
#
# Usage: ./build_pkg.sh [version]
#
# Without the variables below the result is an unsigned installer for local use.
# For a release, set them to sign the library and uninstaller (hardened runtime),
# sign the .pkg, and have Apple notarize it (the ticket is stapled to the .pkg):
#
#   DARWINFUSE_APP_IDENTITY        "Developer ID Application: Name (TEAMID)"
#   DARWINFUSE_INSTALLER_IDENTITY  "Developer ID Installer: Name (TEAMID)"
#   DARWINFUSE_NOTARY_PROFILE      notarytool keychain profile
#                                  (xcrun notarytool store-credentials <name> ...)
#
# Copyright (c) 2026 Marcel Cotta. All rights reserved.
# Licensed under the MIT License.
#

set -euo pipefail

VERSION="${1:-1.1.0}"
APP_IDENTITY="${DARWINFUSE_APP_IDENTITY:-}"
INSTALLER_IDENTITY="${DARWINFUSE_INSTALLER_IDENTITY:-}"
NOTARY_PROFILE="${DARWINFUSE_NOTARY_PROFILE:-}"

if [[ -n "$NOTARY_PROFILE" && ( -z "$APP_IDENTITY" || -z "$INSTALLER_IDENTITY" ) ]]; then
    echo "Error: notarization needs DARWINFUSE_APP_IDENTITY and DARWINFUSE_INSTALLER_IDENTITY" >&2
    exit 1
fi
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

# ---- Sign the payload (Developer ID Application, hardened runtime) ----

if [[ -n "$APP_IDENTITY" ]]; then
    echo "Signing payload..."
    codesign --force --timestamp --options runtime \
        --sign "$APP_IDENTITY" "$PREFIX/lib/libfuse.2.dylib"
    codesign --force --timestamp --options runtime \
        --sign "$APP_IDENTITY" "$APPS_DIR/Uninstall DarwinFUSE.app"
    codesign --verify --strict --verbose=1 "$PREFIX/lib/libfuse.2.dylib"
    codesign --verify --strict --verbose=1 "$APPS_DIR/Uninstall DarwinFUSE.app"
fi

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

PRODUCTBUILD_SIGN=()
if [[ -n "$INSTALLER_IDENTITY" ]]; then
    PRODUCTBUILD_SIGN=(--sign "$INSTALLER_IDENTITY" --timestamp)
fi

PKG="$OUTPUT_DIR/DarwinFUSE-$VERSION.pkg"

productbuild \
    --distribution "$DIST_XML" \
    --resources "$RESOURCES_DIR" \
    --package-path "$BUILD_DIR" \
    ${PRODUCTBUILD_SIGN[@]+"${PRODUCTBUILD_SIGN[@]}"} \
    "$PKG"

if [[ -n "$INSTALLER_IDENTITY" ]]; then
    pkgutil --check-signature "$PKG"
fi

# ---- Notarize and staple ----

if [[ -n "$NOTARY_PROFILE" ]]; then
    echo "Notarizing (this can take a few minutes)..."
    NOTARY_OUT="$(xcrun notarytool submit "$PKG" --keychain-profile "$NOTARY_PROFILE" \
        --wait --output-format json)" || true
    if [[ -z "$NOTARY_OUT" ]]; then
        echo "Error: notarytool returned nothing (network problem?)." >&2
        echo "       The submission may still be running: xcrun notarytool history --keychain-profile $NOTARY_PROFILE" >&2
        exit 1
    fi
    NOTARY_STATUS="$(printf '%s' "$NOTARY_OUT" | plutil -extract status raw -o - - 2>/dev/null || true)"
    NOTARY_ID="$(printf '%s' "$NOTARY_OUT" | plutil -extract id raw -o - - 2>/dev/null || true)"
    if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
        echo "Error: notarization ended with status '${NOTARY_STATUS:-unknown}'" >&2
        [[ -n "$NOTARY_ID" ]] && xcrun notarytool log "$NOTARY_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
        exit 1
    fi
    echo "    Accepted ($NOTARY_ID)"

    # Right after acceptance the ticket can be unavailable for a moment.
    STAPLED=0
    for attempt in 1 2 3 4 5 6; do
        if xcrun stapler staple "$PKG" >/dev/null 2>&1; then STAPLED=1; break; fi
        echo "    Ticket not available yet (attempt $attempt/6)..."
        sleep 20
    done
    [[ $STAPLED -eq 1 ]] || { echo "Error: could not staple the ticket" >&2; exit 1; }
    xcrun stapler validate "$PKG"
    spctl --assess --type install -vv "$PKG"
fi

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
