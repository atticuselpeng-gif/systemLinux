#!/bin/bash
# Write the names of the packages the image itself provides (one per line, sorted), so `get` treats them as
# already satisfied dependencies instead of rebuilding them. A package counts when any of its programs or shared
# libraries survived the image's stripping (still exists in STAGE); a package with neither counts when its first
# other file (not docs, headers or removed systemd files) survived.
# With DB (get's database, e.g. STAGE/var/db/get), each of those packages is also recorded there as base/NAME with
# the files it has in the image, so get knows who owns every file: a port never overwrites base files by accident,
# and a port replaces the base package of the same name in place.
# usage: base-packages.sh ROOTFS STAGE OUT [DB]   (ROOTFS holds var/db/pkg, STAGE is the stripped image)
set -eu
ROOTFS=${1:?usage: base-packages.sh ROOTFS STAGE OUT [DB]}; STAGE=${2:?}; OUT=${3:?}; DB=${4:-}
tmp=$(mktemp)
for c in "$ROOTFS"/var/db/pkg/*/*/CONTENTS; do
    d=${c%/CONTENTS}; pf=${d##*/}
    name=$(sed -n 's/^\(.*\)-[0-9][^-]*\(-r[0-9]*\)\{0,1\}$/\1/p' <<< "$pf")
    [ -n "$name" ] || continue
    found=0 any=0
    while IFS= read -r f; do
        any=1
        if [ -e "$STAGE$f" ]; then found=1; break; fi
    done < <(awk '$1=="obj" && ($2 ~ /^\/(usr\/)?(bin|sbin|libexec)\// || $2 ~ /^\/(usr\/)?lib(64)?\/[^\/]*\.so(\.|$)/) {print $2}' "$c")
    if [ "$any" = 0 ]; then
        f=$(awk '$1=="obj" && $2 !~ /^\/usr\/(share\/(doc|man|info|locale)|lib\/(systemd|tmpfiles\.d|sysusers\.d))\// {print $2; exit}' "$c")
        [ -n "$f" ] && [ -e "$STAGE$f" ] && found=1
    fi
    [ "$found" = 1 ] || continue
    echo "$name" >> "$tmp"
    [ -n "$DB" ] || continue
    # its files and symlinks that are in the image, with the /bin, /sbin, /lib, /lib64, /usr/sbin symlinks resolved the
    # way get records paths
    pdir=$DB/pkgs/base__$name
    mkdir -p "$pdir"
    awk '$1=="obj" { p=substr($0,5); sub(/ [^ ]+ [^ ]+$/,"",p); print p }
         $1=="sym" { p=substr($0,5); sub(/ -> .*/,"",p); print p }' "$c" |
        sed -e 's#^/\(s\{0,1\}bin\)/#/usr/bin/#' -e 's#^/usr/sbin/#/usr/bin/#' -e 's#^/lib64/#/usr/lib64/#' -e 's#^/lib/#/usr/lib/#' |
        while IFS= read -r f; do if [ -e "$STAGE$f" ] || [ -L "$STAGE$f" ]; then echo "$f"; fi; done | sort -u >> "$pdir/files"
    sort -u -o "$pdir/files" "$pdir/files"
    { echo "version=${pf#"$name"-}"; echo "base=1"; } > "$pdir/info"
done
mkdir -p "$(dirname "$OUT")"
sort -u "$tmp" > "$OUT"
rm -f "$tmp"
echo "base-packages: $(wc -l < "$OUT") packages provided by the image"
