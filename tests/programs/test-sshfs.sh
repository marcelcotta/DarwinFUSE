#!/bin/bash
# sshfs 2.10 (built from the unmodified source) over DarwinFUSE, via a local sftp-server.
set -u
S="$1"; W="$(mktemp -d "${TMPDIR:-/tmp}/dfuse-sshfs.XXXXXX")"; W="$(cd "$W" && pwd -P)"
MNT="$W/mnt"; BACK="$W/back"; mkdir -p "$MNT" "$BACK"
pass=0; fail=0
ok(){ pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad(){ fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check(){ local n="$1"; shift; if limit 60 "$@" >"$W/out" 2>&1; then ok "$n"; else bad "$n ($(head -c 160 "$W/out" | tr '\n' ' '))"; fi; }
limit(){ local s="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$s" "$@"; }
cleanup(){ umount "$MNT" 2>/dev/null || umount -f "$MNT" 2>/dev/null; sleep 1; pkill -f "$W" 2>/dev/null; rm -rf "$W"; }
trap cleanup EXIT

export DYLD_LIBRARY_PATH="$S/dfuse/lib"
echo "--- library the binary loads"; otool -L "$S/build/sshfs/sshfs" | sed -n 2p | awk '{print "  "$1}'
echo "--- mount (options: -p 2222 -C, ssh_command, reconnect)"
"$S/build/sshfs/sshfs" -f -p 2222 -C -o "ssh_command=$S/scripts/fakessh" -o reconnect "localhost:$BACK" "$MNT" >"$W/sshfs.log" 2>&1 &
PID=$!
for _ in $(seq 1 40); do mount | grep -q " on ${MNT} " && break; sleep 0.5; done
mount | grep -q " on ${MNT} " || { bad "mount appeared"; head -20 "$W/sshfs.log"; exit 1; }
ok "mount appeared"; mount | grep " on ${MNT} " | sed 's/.* (/  (/' 

echo "--- operations"
check "create and write"     bash -c "echo hello > '$MNT/a.txt'"
check "read back / on disk"  bash -c "[ \"\$(cat '$MNT/a.txt')\" = hello ] && [ \"\$(cat '$BACK/a.txt')\" = hello ]"
check "mkdir -p"             mkdir -p "$MNT/d/e"
check "rename"               bash -c "mv '$MNT/a.txt' '$MNT/d/b.txt' && [ -f '$BACK/d/b.txt' ]"
check "symlink + readlink"   bash -c "ln -s b.txt '$MNT/d/link' && [ \"\$(readlink '$MNT/d/link')\" = b.txt ]"
check "chmod"                bash -c "chmod 600 '$MNT/d/b.txt' && [ \"\$(stat -f %Lp '$BACK/d/b.txt')\" = 600 ]"
check "truncate"             bash -c "truncate -s 3 '$MNT/d/b.txt' && [ \$(stat -f %z '$BACK/d/b.txt') -eq 3 ]"
check "touch -t (mtime)"     bash -c "touch -t 202001020304 '$MNT/d/b.txt' && [ \"\$(stat -f %Sm -t %Y%m%d%H%M '$BACK/d/b.txt')\" = 202001020304 ]"
check "unlink and rmdir"     bash -c "rm '$MNT/d/link' && rmdir '$MNT/d/e'"
check "unicode name"         bash -c "echo x > '$MNT/Übung ✓ 文件.txt' && [ -f '$BACK/Übung ✓ 文件.txt' ]"
check "df"                   bash -c "df '$MNT' | tail -1 | grep -q ."
echo "--- data"
dd if=/dev/urandom of="$W/src.bin" bs=1m count=32 2>/dev/null
check "copy 32 MB in"        cp "$W/src.bin" "$MNT/big.bin"
check "32 MB identical"      cmp "$W/src.bin" "$BACK/big.bin"
check "read 32 MB back"      bash -c "cmp '$W/src.bin' '$MNT/big.bin'"
mkdir "$BACK/many"; ( cd "$BACK/many" && for i in $(seq 1 1000); do : > "file_with_a_longer_name_number_$i.txt"; done )
got=$(limit 60 ls -A "$MNT/many" 2>/dev/null | wc -l | tr -d ' ')
[ "$got" = 1000 ] && ok "list 1000 entries" || bad "list 1000 entries (got $got)"
echo "--- unmount"
umount "$MNT" 2>"$W/umount.err" && ok "umount" || bad "umount ($(cat "$W/umount.err"))"
for _ in $(seq 1 20); do kill -0 $PID 2>/dev/null || break; sleep 0.5; done
kill -0 $PID 2>/dev/null && bad "sshfs exited after unmount" || ok "sshfs exited after unmount"
echo; echo "RESULT sshfs: $pass passed, $fail failed"; [ $fail -eq 0 ]
