#!/bin/bash
# Check that every shared library the given programs need (recursively) exists inside an image tree, using
# the image's own library paths (/usr/lib64, /usr/lib, /etc/ld.so.conf[.d]). A missing library in PID 1's
# chain is a kernel panic at boot, so the build stops here instead.
# usage: check-libs.sh ROOT PROGRAM...   (PROGRAM paths relative to ROOT)
set -eu
R=${1:?usage: check-libs.sh ROOT PROGRAM...}; shift
dirs="usr/lib64 lib64 usr/lib lib usr/local/lib64 usr/local/lib"
for c in "$R"/etc/ld.so.conf "$R"/etc/ld.so.conf.d/*.conf; do
    [ -f "$c" ] && dirs="$dirs $(sed -n 's#^/##p' "$c" | grep -v '^include' | tr '\n' ' ')"
done
find_lib() { for d in $dirs; do { [ -e "$R/$d/$1" ] || [ -L "$R/$d/$1" ]; } && return 0; done; return 1; }
bad=0 seen=" "
check() {
    local f=$1 lib d
    [ -e "$R/$f" ] || { echo "check-libs: missing program /$f" >&2; bad=1; return; }
    for lib in $(readelf -d "$R/$f" 2>/dev/null | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p'); do
        case "$seen" in *" $lib "*) continue ;; esac
        seen="$seen$lib "
        if find_lib "$lib"; then
            for d in $dirs; do [ -e "$R/$d/$lib" ] && { check "$d/$lib"; break; }; done
        else
            echo "check-libs: /$f needs $lib, which is not in the image" >&2; bad=1
        fi
    done
}
for p in "$@"; do check "$p"; done
[ "$bad" = 0 ] && echo "check-libs: OK ($# programs)"
exit "$bad"
