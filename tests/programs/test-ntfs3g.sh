#!/bin/bash
# ntfs-3g 2022.10.3 (unmodified source, high-level API) on a real NTFS image, over DarwinFUSE.
set -u
DARWINFUSE="$(cd "$(dirname "$0")/../.." && pwd)"
S="$1"; W="$(mktemp -d "${TMPDIR:-/tmp}/dfuse-ntfs.XXXXXX")"; W="$(cd "$W" && pwd -P)"
MNT="$W/mnt"; IMG="$W/test.ntfs"; mkdir -p "$MNT"
pass=0; fail=0
ok(){ pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad(){ fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
limit(){ local s="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$s" "$@"; }
check(){ local n="$1"; shift; if limit 60 "$@" >"$W/out" 2>&1; then ok "$n"; else bad "$n ($(head -c 200 "$W/out" | tr '\n' ' '))"; fi; }
cleanup(){ umount "$MNT" 2>/dev/null || umount -f "$MNT" 2>/dev/null; sleep 1; pkill -f "$W" 2>/dev/null; rm -rf "$W"; }
trap cleanup EXIT
export DYLD_LIBRARY_PATH="$S/dfuse/lib:$S/build/ntfs3g/libntfs-3g/.libs"
NTFS="$S/build/ntfs3g/src/.libs/ntfs-3g"; MKNTFS="$S/build/ntfs3g/ntfsprogs/mkntfs"; FIX="$S/build/ntfs3g/ntfsprogs/ntfsfix"

echo "--- image"
dd if=/dev/zero of="$IMG" bs=1m count=0 seek=96 2>/dev/null
"$MKNTFS" -F -Q -L DFUSE "$IMG" >"$W/mkntfs.log" 2>&1 && ok "mkntfs created a 96 MB NTFS image" || { bad "mkntfs ($(tail -2 "$W/mkntfs.log" | tr '\n' ' '))"; exit 1; }
echo "--- mount"
"$NTFS" -o no_detach,rw,noatime "$IMG" "$MNT" >"$W/ntfs.log" 2>&1 &
PID=$!
for _ in $(seq 1 40); do mount | grep -q " on ${MNT} " && break; sleep 0.5; done
mount | grep -q " on ${MNT} " || { bad "mount appeared"; head -15 "$W/ntfs.log"; exit 1; }
ok "mount appeared"
echo "--- operations"
check "create and write"     bash -c "echo hello > '$MNT/a.txt'"
check "read back"            bash -c "[ \"\$(cat '$MNT/a.txt')\" = hello ]"
check "mkdir -p"             mkdir -p "$MNT/d/e"
check "rename"               mv "$MNT/a.txt" "$MNT/d/b.txt"
check "append"               bash -c "echo more >> '$MNT/d/b.txt' && [ \$(wc -l < '$MNT/d/b.txt') -eq 2 ]"
check "truncate"             bash -c "truncate -s 3 '$MNT/d/b.txt' && [ \$(stat -f %z '$MNT/d/b.txt') -eq 3 ]"
check "touch -t (mtime)"     bash -c "touch -t 202001020304 '$MNT/d/b.txt' && [ \"\$(stat -f %Sm -t %Y%m%d%H%M '$MNT/d/b.txt')\" = 202001020304 ]"
check "unicode name"         bash -c "echo x > '$MNT/Übung ✓ 文件.txt' && [ -f '$MNT/Übung ✓ 文件.txt' ]"
check "unlink and rmdir"     bash -c "rm '$MNT/d/b.txt' && rmdir '$MNT/d/e'"
check "df"                   bash -c "df '$MNT' | tail -1 | grep -q ."
echo "--- data"
dd if=/dev/urandom of="$W/src.bin" bs=1m count=24 2>/dev/null
check "copy 24 MB in"        cp "$W/src.bin" "$MNT/big.bin"
check "24 MB identical"      cmp "$W/src.bin" "$MNT/big.bin"
check "copy a source tree"   cp -RX $DARWINFUSE/src "$MNT/tree"
check "tree identical"       diff -r $DARWINFUSE/src "$MNT/tree"
mkdir "$MNT/many"; n=0; for i in $(seq 1 300); do : > "$MNT/many/file_with_a_longer_name_$i.txt" 2>/dev/null && n=$((n+1)); done
got=$(limit 60 ls -A "$MNT/many" 2>/dev/null | wc -l | tr -d ' ')
[ "$n" = 300 ] && [ "$got" = 300 ] && ok "create and list 300 entries" || bad "300 entries (created $n, listed $got)"
echo "--- unmount"
umount "$MNT" 2>"$W/umount.err" && ok "umount" || bad "umount ($(cat "$W/umount.err"))"
for _ in $(seq 1 20); do kill -0 $PID 2>/dev/null || break; sleep 0.5; done
kill -0 $PID 2>/dev/null && bad "ntfs-3g exited after unmount" || ok "ntfs-3g exited after unmount"
echo "--- file system check of the image (ntfsfix -n: read-only check)"
"$FIX" -n "$IMG" 2>&1 | tail -6 | sed 's/^/  /'
"$FIX" -n "$IMG" >"$W/fix.out" 2>&1 && ok "ntfsfix finds no problem" || bad "ntfsfix reports a problem"
echo; echo "RESULT ntfs-3g: $pass passed, $fail failed"; [ $fail -eq 0 ]
