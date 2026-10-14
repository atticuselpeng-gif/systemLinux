#!/bin/sh
# Build eudev (the udev device manager without systemd) from a pinned release tarball and install it under
# DESTDIR: /usr/bin/udevd, /usr/bin/udevadm, libudev.so.1, the udev helpers (ata_id, scsi_id, ...), rules and
# hwdb. It replaces systemd-udevd and systemd's libudev. Needs gcc, make, curl, gperf, pkg-config and the
# libkmod and libblkid headers on the build host (Debian: gperf libkmod-dev libblkid-dev).
# usage: build.sh DESTDIR
set -eu
DESTDIR=${1:?usage: build.sh DESTDIR}
EUDEV_VERSION=3.2.14
EUDEV_SHA256=8da4319102f24abbf7fff5ce9c416af848df163b29590e666d334cc1927f006f
URL=https://github.com/eudev-project/eudev/releases/download/v$EUDEV_VERSION/eudev-$EUDEV_VERSION.tar.gz
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
curl -fsSL -o "$W/eudev.tar.gz" "$URL"
[ "$(sha256sum "$W/eudev.tar.gz" | cut -d' ' -f1)" = "$EUDEV_SHA256" ] || { echo "eudev: checksum mismatch" >&2; exit 1; }
mkdir "$W/src"; tar -xzf "$W/eudev.tar.gz" -C "$W/src" --strip-components=1
cd "$W/src"
./configure -q --prefix=/usr --sysconfdir=/etc --bindir=/usr/bin --sbindir=/usr/bin --libdir=/usr/lib64 \
    --with-rootprefix=/usr --with-rootlibdir=/usr/lib64 --with-rootlibexecdir=/usr/lib/udev \
    --enable-kmod --enable-blkid --enable-hwdb --disable-manpages --disable-selinux --disable-static
make -j"$(nproc)"
# systemd's libudev.so.1.7.x would otherwise stay next to eudev's and keep the libudev.so.1 symlink
rm -f "$DESTDIR"/usr/lib64/libudev.so*
make install DESTDIR="$DESTDIR"
rm -f "$DESTDIR/usr/lib64/libudev.la"
# the dinit service and older scripts call it as /usr/lib/udev/udevd
ln -sf ../../bin/udevd "$DESTDIR/usr/lib/udev/udevd"
# compile eudev's hwdb plus the hwdb.d files other packages installed (built on this host, so it runs here)
"$DESTDIR/usr/bin/udevadm" hwdb --update --root "$DESTDIR"
