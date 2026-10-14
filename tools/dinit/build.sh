#!/bin/sh
# Build dinit (PID 1) from a pinned release tarball and install it under DESTDIR.
# /sbin and /bin are both /usr/bin in the image, so the programs (dinit, dinitctl, dinit-check, and
# shutdown/reboot/poweroff/halt/soft-reboot) all go to /usr/bin.
# usage: build.sh DESTDIR
set -eu
DESTDIR=${1:?usage: build.sh DESTDIR}
DINIT_VERSION=0.20.0
DINIT_SHA256=cd75b572a2eab4a9bd0610a2bb8cc154da7e80074e61cb1059a996dfd977baae
URL=https://github.com/davmac314/dinit/archive/refs/tags/v$DINIT_VERSION.tar.gz
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
curl -fsSL -o "$W/dinit.tar.gz" "$URL"
[ "$(sha256sum "$W/dinit.tar.gz" | cut -d' ' -f1)" = "$DINIT_SHA256" ] || { echo "dinit: checksum mismatch" >&2; exit 1; }
mkdir "$W/src"; tar -xzf "$W/dinit.tar.gz" -C "$W/src" --strip-components=1
cd "$W/src"
./configure -q --prefix=/usr --sbindir=/usr/bin --syscontrolsocket=/run/dinitctl
make -j"$(nproc)"
# make sure no stale reboot/poweroff symlinks are in the way of make install
for n in reboot poweroff halt shutdown soft-reboot; do rm -f "$DESTDIR/usr/bin/$n"; done
make install DESTDIR="$DESTDIR"
