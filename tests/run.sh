#!/bin/bash
#
# Mount a passthrough filesystem through DarwinFUSE and exercise it.
#
# Run it from a normal Terminal session. Processes inside a sandbox (some editors,
# agents) are refused access to the NFS mount ("Operation not permitted").
#
# Usage: tests/run.sh            (or: make test)
#
# By default the test filesystem is linked against the static library built here.
# To test an installed or packaged libfuse.2.dylib instead, name its directory:
#   DARWINFUSE_DYLIB_DIR=/usr/local/lib tests/run.sh
#
set -u
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
W="$(mktemp -d "${TMPDIR:-/tmp}/darwinfuse-test.XXXXXX")"
W="$(cd "$W" && pwd -P)"     # mount(8) lists resolved paths (/private/var/...)
MNT="$W/mnt"; BACK="$W/back"; LOG="$W/fs.log"
mkdir -p "$MNT" "$BACK"
pass=0; fail=0

ok()   { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() {
    local name="$1"; shift
    if "$@" >"$W/out" 2>&1; then ok "$name"; else bad "$name ($(head -c 160 "$W/out" | tr '\n' ' '))"; fi
}
# Fail instead of hanging when the server stops answering.
limit() { local s="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$s" "$@"; }

cleanup() {
    umount "$MNT" 2>/dev/null || umount -f "$MNT" 2>/dev/null
    sleep 1; pkill -f "$W/passthrough" 2>/dev/null
    rm -rf "$W"
}
trap cleanup EXIT

echo "--- build"
if [ -n "${DARWINFUSE_DYLIB_DIR:-}" ]; then
    LINK="$DARWINFUSE_DYLIB_DIR/libfuse.2.dylib"
    export DYLD_LIBRARY_PATH="$DARWINFUSE_DYLIB_DIR"
    echo "  linking against $LINK"
else
    make -C "$ROOT_DIR" -s >/dev/null || { echo "library build failed"; exit 1; }
    LINK="$ROOT_DIR/libdarwinfuse.a"
fi
cc -arch "$(uname -m)" -Wall -D_FILE_OFFSET_BITS=64 -D_DARWIN_USE_64_BIT_INODE \
   -I"$ROOT_DIR/include" -o "$W/passthrough" "$ROOT_DIR/tests/passthrough.c" \
   "$LINK" || { echo "test build failed"; exit 1; }

echo "--- mount"
PFS_ROOT="$BACK" "$W/passthrough" -f "$MNT" >"$LOG" 2>&1 &
PID=$!
for _ in $(seq 1 30); do mount | grep -q " on ${MNT} " && break; sleep 0.5; done
mount | grep -q " on ${MNT} " || { bad "mount appeared"; head -20 "$LOG"; exit 1; }
ok "mount appeared"

echo "--- basic operations"
check "create and write"       bash -c "echo hello > '$MNT/a.txt'"
check "read back"              bash -c "[ \"\$(cat '$MNT/a.txt')\" = hello ] && [ \"\$(cat '$BACK/a.txt')\" = hello ]"
check "mkdir -p"               mkdir -p "$MNT/d/e/f"
check "append"                 bash -c "echo more >> '$MNT/a.txt' && [ \$(wc -l < '$MNT/a.txt') -eq 2 ]"
check "rename"                 bash -c "mv '$MNT/a.txt' '$MNT/d/b.txt' && [ -f '$MNT/d/b.txt' ] && [ ! -e '$MNT/a.txt' ]"
check "symlink and readlink"   bash -c "ln -s b.txt '$MNT/d/link' && [ \"\$(readlink '$MNT/d/link')\" = b.txt ] && [ \"\$(head -1 '$MNT/d/link')\" = hello ]"
check "hard link"              bash -c "ln '$MNT/d/b.txt' '$MNT/d/hl' && [ \$(stat -f %l '$MNT/d/b.txt') -eq 2 ]"
check "chmod"                  bash -c "chmod 600 '$MNT/d/b.txt' && [ \"\$(stat -f %Lp '$MNT/d/b.txt')\" = 600 ]"
check "truncate"               bash -c "truncate -s 3 '$MNT/d/b.txt' && [ \$(stat -f %z '$MNT/d/b.txt') -eq 3 ]"
check "unlink"                 rm "$MNT/d/hl" "$MNT/d/link"
check "rmdir refuses non-empty" bash -c "! rmdir '$MNT/d' 2>/dev/null"
check "rmdir"                  rmdir "$MNT/d/e/f"
check "unicode name"           bash -c "echo x > '$MNT/Übung ✓ 文件.txt' && [ -f '$BACK/Übung ✓ 文件.txt' ]"
check "ENOENT"                 bash -c "! cat '$MNT/missing' 2>/dev/null"
check "EEXIST"                 bash -c "! mkdir '$MNT/d' 2>/dev/null"
check "statfs (df)"            bash -c "df '$MNT' | tail -1 | grep -q ."

echo "--- timestamps"
: > "$BACK/t.txt"
check "touch -t sets mtime"    bash -c "touch -t 202001020304 '$MNT/t.txt' && [ \"\$(stat -f %Sm -t %Y%m%d%H%M '$BACK/t.txt')\" = 202001020304 ]"
check "touch -a -t sets atime" bash -c "touch -a -t 201912312359 '$MNT/t.txt' && [ \"\$(stat -f %Sa -t %Y%m%d%H%M '$BACK/t.txt')\" = 201912312359 ]"
echo data > "$BACK/old.txt"; touch -t 200001010000 "$BACK/old.txt"
check "cp -p keeps mtime"      bash -c "cp -p '$MNT/old.txt' '$MNT/copy.txt' && [ \"\$(stat -f %m '$BACK/copy.txt')\" = \"\$(stat -f %m '$BACK/old.txt')\" ]"

echo "--- data"
dd if=/dev/urandom of="$W/src.bin" bs=1m count=64 2>/dev/null
check "copy 64 MB in"          cp "$W/src.bin" "$MNT/big.bin"
check "64 MB identical"        cmp "$W/src.bin" "$MNT/big.bin"
check "random-offset write"    bash -c "dd if=/dev/urandom of='$MNT/big.bin' bs=4096 seek=777 count=3 conv=notrunc 2>/dev/null && cmp '$MNT/big.bin' '$BACK/big.bin'"
check "copy a source tree"     cp -R "$ROOT_DIR/src" "$MNT/tree"
check "tree identical"         diff -r "$ROOT_DIR/src" "$MNT/tree"
check "parallel readers"       bash -c "for i in 1 2 3 4; do (cat '$MNT/big.bin' | shasum >/dev/null) & done; wait"

echo "--- directories"
mkdir "$MNT/many"
fails=0; for i in $(seq 1 500); do echo "$i" > "$MNT/many/f$i" 2>/dev/null || fails=$((fails+1)); done
[ $fails -eq 0 ] && [ "$(ls "$BACK/many" | wc -l | tr -d ' ')" = 500 ] && ok "create 500 files" || bad "create 500 files ($fails failed)"
for n in 1000 5000; do
    mkdir "$BACK/big$n"; ( cd "$BACK/big$n" && for i in $(seq 1 $n); do : > "file_with_a_longer_name_number_$i.txt"; done )
    got=$(limit 60 ls -A "$MNT/big$n" 2>/dev/null | wc -l | tr -d ' ')
    [ "$got" = "$n" ] && ok "list $n entries" || bad "list $n entries (got $got)"
done

echo "--- unmount"
if umount "$MNT" 2>"$W/umount.err"; then ok "umount"; else bad "umount ($(cat "$W/umount.err"))"; fi
for _ in $(seq 1 20); do kill -0 $PID 2>/dev/null || break; sleep 0.5; done
kill -0 $PID 2>/dev/null && bad "server exited after unmount" || ok "server exited after unmount"
mount | grep -q " on ${MNT} " && bad "no mount left" || ok "no mount left"

echo; echo "RESULT: $pass passed, $fail failed"
[ $fail -eq 0 ]
