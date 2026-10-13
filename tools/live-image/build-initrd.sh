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
# copy-bin.sh keeps the host paths (e.g. /usr/bin/busybox); the init script expects /bin/busybox and /sbin/cryptsetup
[ -x "$WORK/root$BB" ] || { echo "ERROR: busybox not copied to initramfs" >&2; exit 1; }
[ -x "$WORK/root$CS" ] || { echo "ERROR: cryptsetup not copied to initramfs" >&2; exit 1; }
[ "$BB" = /bin/busybox ] || ln -sf "$BB" "$WORK/root/bin/busybox"
[ "$CS" = /sbin/cryptsetup ] || ln -sf "$CS" "$WORK/root/sbin/cryptsetup"

install -m755 "$HERE/init" "$WORK/root/init"
# BUILD_ID ties this initramfs to the ISO it is shipped in (the same id goes into /live/build-id on the ISO)
[ -n "${BUILD_ID:-}" ] && echo "$BUILD_ID" > "$WORK/root/build-id"
mkdir -p "$WORK/root"/{proc,sys,dev,mnt,newroot,overlay}
( cd "$WORK/root" && find . | sort | cpio -o -H newc -R 0:0 --quiet ) > "$OUT"
ls -lh "$OUT"
