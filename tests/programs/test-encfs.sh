#!/bin/bash
# encfs 1.9.5 (unmodified source except a C++ deleter fix) over DarwinFUSE, including a remount.
set -u
DARWINFUSE="$(cd "$(dirname "$0")/../.." && pwd)"
S="$1"; W="$(mktemp -d "${TMPDIR:-/tmp}/dfuse-encfs.XXXXXX")"; W="$(cd "$W" && pwd -P)"
MNT="$W/mnt"; ENC="$W/enc"; mkdir -p "$MNT" "$ENC"
pass=0; fail=0
ok(){ pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad(){ fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
limit(){ local s="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$s" "$@"; }
check(){ local n="$1"; shift; if limit 60 "$@" >"$W/out" 2>&1; then ok "$n"; else bad "$n ($(head -c 200 "$W/out" | tr '\n' ' '))"; fi; }
cleanup(){ umount "$MNT" 2>/dev/null || umount -f "$MNT" 2>/dev/null; sleep 1; pkill -f "$W" 2>/dev/null; rm -rf "$W"; }
trap cleanup EXIT
export DYLD_LIBRARY_PATH="$S/dfuse/lib"
ENCFS="$S/build/encfs/encfs/encfs"; [ -x "$ENCFS" ] || ENCFS="$(find "$S/build/encfs" -name encfs -type f -perm +111 | head -1)"
domount(){ "$ENCFS" --standard --extpass="echo dfusetest" -f "$ENC" "$MNT" >"$W/encfs.log" 2>&1 &
  PID=$!; for _ in $(seq 1 40); do mount | grep -q " on ${MNT} " && return 0; sleep 0.5; done; return 1; }
dounmount(){ umount "$MNT" 2>"$W/umount.err" && ok "umount" || bad "umount ($(cat "$W/umount.err"))"
  for _ in $(seq 1 20); do kill -0 $PID 2>/dev/null || break; sleep 0.5; done
  kill -0 $PID 2>/dev/null && bad "encfs exited after unmount" || ok "encfs exited after unmount"; }

echo "--- first mount (creates the volume)"
domount && ok "mount appeared" || { bad "mount appeared"; head -15 "$W/encfs.log"; exit 1; }
echo "--- operations"
check "create and write"     bash -c "echo hello > '$MNT/a.txt'"
check "read back"            bash -c "[ \"\$(cat '$MNT/a.txt')\" = hello ]"
check "mkdir -p"             mkdir -p "$MNT/d/e"
check "rename"               mv "$MNT/a.txt" "$MNT/d/b.txt"
check "append"               bash -c "echo more >> '$MNT/d/b.txt' && [ \$(wc -l < '$MNT/d/b.txt') -eq 2 ]"
check "truncate"             bash -c "truncate -s 3 '$MNT/d/b.txt' && [ \$(stat -f %z '$MNT/d/b.txt') -eq 3 ]"
check "touch -t (mtime)"     bash -c "touch -t 202001020304 '$MNT/d/b.txt' && [ \"\$(stat -f %Sm -t %Y%m%d%H%M '$MNT/d/b.txt')\" = 202001020304 ]"
check "chmod"                bash -c "chmod 600 '$MNT/d/b.txt' && [ \"\$(stat -f %Lp '$MNT/d/b.txt')\" = 600 ]"
check "symlink + readlink"   bash -c "ln -s b.txt '$MNT/d/link' && [ \"\$(readlink '$MNT/d/link')\" = b.txt ]"
check "unicode name"         bash -c "echo x > '$MNT/Übung ✓ 文件.txt' && [ -f '$MNT/Übung ✓ 文件.txt' ]"
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
echo "--- what is on disk"
[ -n "$(ls "$ENC" | grep -v '^\.encfs')" ] && ok "encrypted names in the root directory" || bad "no encrypted entries"
ls "$ENC" | grep -qE "^(a\.txt|d|big\.bin|tree)$" && bad "plain names visible on disk" || ok "no plain file names on disk"
dounmount
echo "--- second mount (the data must still be there)"
domount && ok "remount appeared" || { bad "remount appeared"; head -15 "$W/encfs.log"; exit 1; }
check "24 MB identical after remount" cmp "$W/src.bin" "$MNT/big.bin"
check "tree identical after remount"  diff -r $DARWINFUSE/src "$MNT/tree"
check "mtime kept after remount"      bash -c "[ \"\$(stat -f %Sm -t %Y%m%d%H%M '$MNT/d/b.txt')\" = 202001020304 ]"
dounmount
echo; echo "RESULT encfs: $pass passed, $fail failed"; [ $fail -eq 0 ]
