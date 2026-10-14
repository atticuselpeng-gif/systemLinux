#!/bin/bash
# Check that every shared library the given programs need (recursively) exists inside an image tree, using
# the image's own library paths (/usr/lib64, /usr/lib, /etc/ld.so.conf[.d]). Symlinks (also absolute ones, as
# in the GCC/binutils wrappers) are resolved inside the image, never against the build host. A missing library
# in PID 1's chain is a kernel panic at boot, and in the toolchain a system that cannot build anything, so the
# build stops here instead.
# usage: check-libs.sh ROOT PROGRAM...   (PROGRAM paths relative to ROOT; globs are expanded inside ROOT)
set -eu
R=${1:?usage: check-libs.sh ROOT PROGRAM...}; shift
dirs="/usr/lib64 /lib64 /usr/lib /lib /usr/local/lib64 /usr/local/lib"
for c in "$R"/etc/ld.so.conf "$R"/etc/ld.so.conf.d/*.conf; do
    [ -f "$c" ] && dirs="$dirs $(grep '^/' "$c" | tr '\n' ' ')"
done
# resolve PATH (absolute, inside the image) through symlinks; prints the final path, fails if it does not exist
resolve() {
    local p=$1 t i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        [ -L "$R$p" ] || break
        t=$(readlink "$R$p")
        case "$t" in /*) p=$t ;; *) p=$(dirname "$p")/$t ;; esac
    done
    [ -f "$R$p" ] && printf '%s\n' "$p"
}
find_lib() { local d f; for d in $dirs; do f=$(resolve "$d/$1") && { printf '%s\n' "$f"; return 0; }; done; return 1; }
bad=0 seen=" "
check() {
    local f=$1 real lib path
    real=$(resolve "$f") || { echo "check-libs: missing program $f" >&2; bad=1; return; }
    for lib in $(readelf -d "$R$real" 2>/dev/null | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p'); do
        case "$seen" in *" $lib "*) continue ;; esac
        seen="$seen$lib "
        if path=$(find_lib "$lib"); then check "$path"
        else echo "check-libs: $f needs $lib, which is not in the image" >&2; bad=1; fi
    done
}
n=0
for p in "$@"; do
    case "$p" in
        *[*?]*) for m in "$R"/$p; do [ -e "$m" ] || { echo "check-libs: nothing matches /$p" >&2; bad=1; continue; }; check "${m#"$R"}"; n=$((n + 1)); done ;;
        *) check "/$p"; n=$((n + 1)) ;;
    esac
done
[ "$bad" = 0 ] && echo "check-libs: OK ($n programs)"
exit "$bad"
