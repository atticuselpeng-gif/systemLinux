#!/bin/sh
# Build the libsystemd.so.0 stub (sd-stub.c, no systemd code) and install it under DESTDIR/usr/lib64,
# replacing systemd's library. Fails if any binary in DESTDIR needs an sd_* symbol the stub does not export.
# usage: build.sh DESTDIR
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
DESTDIR=${1:?usage: build.sh DESTDIR}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
${CC:-cc} -O2 -fPIC -fvisibility=hidden -shared -Wall -Wextra -Werror \
    -Wl,--version-script="$HERE/libsystemd.sym" -Wl,-soname,libsystemd.so.0 \
    -o "$W/libsystemd.so.0" "$HERE/sd-stub.c"
L=$DESTDIR/usr/lib64
rm -f "$L"/libsystemd.so "$L"/libsystemd.so.0 "$L"/libsystemd.so.0.* "$L/pkgconfig/libsystemd.pc"
install -Dm755 "$W/libsystemd.so.0" "$L/libsystemd.so.0"

# every sd_*@VERSION the image's programs import must be exported by the stub
nm -D --defined-only "$W/libsystemd.so.0" | awk '{sub(/@@/, "@", $3); print $3}' | sort -u > "$W/have"
find "$DESTDIR/usr" -type f \( -name '*.so*' -o -perm -u+x \) 2>/dev/null | while read -r f; do
    readelf -d "$f" 2>/dev/null | grep -q 'NEEDED.*\[libsystemd\.so\.0\]' || continue
    nm -D --undefined-only "$f" 2>/dev/null | awk '$2 ~ /^sd_/ {print $2}'
done | sort -u > "$W/need"
missing=$(comm -23 "$W/need" "$W/have")
[ -z "$missing" ] || { echo "libsystemd-stub: symbols used by the image but not provided:" $missing >&2; exit 1; }
echo "libsystemd-stub: installed ($(wc -l < "$W/need") imported symbols covered)"
