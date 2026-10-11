#!/bin/bash
# Build the small live initramfs: busybox + cryptsetup (for LUKS-encrypted installs) + the init
# script. No firmware: the live image is kernel + installer only.
#
# busybox and cryptsetup come from the build host (install them with its package manager; a static
# busybox is best); copy-bin.sh copies each program with the shared libraries it needs.
#
# usage: WORK=~/.cache/systemlinux-initrd ./build-initrd.sh OUTPUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
OUT=${1:?usage: build-initrd.sh OUTPUT}
WORK=${WORK:-$HOME/.cache/systemlinux-initrd}
rm -rf "$WORK/root" && mkdir -p "$WORK/root/bin" "$WORK/root/sbin" "$WORK/root/etc"

echo "== copying busybox and cryptsetup from the build host"
"$REPO/tools/overlay-common/copy-bin.sh" "$WORK/root" busybox cryptsetup
BB=$(readlink -f "$(command -v busybox)"); CS=$(readlink -f "$(command -v cryptsetup)")
[ -x "$WORK/root/bin/busybox" ] || { echo "ERROR: busybox not copied to initramfs" >&2; exit 1; }
[ -x "$WORK/root/sbin/cryptsetup" ] || { echo "ERROR: cryptsetup not copied to initramfs" >&2; exit 1; }
ln -sf "$BB" "$WORK/root/bin/busybox"
ln -sf "$CS" "$WORK/root/sbin/cryptsetup"

install -m755 "$HERE/init" "$WORK/root/init"
# BUILD_ID ties this initramfs to the ISO it is shipped in (the same id goes into /live/build-id on the ISO)
[ -n "${BUILD_ID:-}" ] && echo "$BUILD_ID" > "$WORK/root/build-id"
mkdir -p "$WORK/root"/{proc,sys,dev,mnt,newroot,overlay}
( cd "$WORK/root" && find . | sort | cpio -o -H newc -R 0:0 --quiet ) > "$OUT"
ls -lh "$OUT"
