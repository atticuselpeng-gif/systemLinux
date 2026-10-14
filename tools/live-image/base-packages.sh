#!/bin/bash
# Write the names of the packages the image itself provides (one per line, sorted), so `get` treats them as
# already satisfied dependencies instead of rebuilding them. A package counts only when its files survived the
# image's stripping: the first program or library it installed must still exist in STAGE.
# usage: base-packages.sh ROOTFS STAGE OUT   (ROOTFS holds var/db/pkg, STAGE is the stripped image)
set -eu
ROOTFS=${1:?usage: base-packages.sh ROOTFS STAGE OUT}; STAGE=${2:?}; OUT=${3:?}
tmp=$(mktemp)
for c in "$ROOTFS"/var/db/pkg/*/*/CONTENTS; do
    d=${c%/CONTENTS}; pf=${d##*/}
    name=$(sed -n 's/^\(.*\)-[0-9][^-]*\(-r[0-9]*\)\{0,1\}$/\1/p' <<< "$pf")
    [ -n "$name" ] || continue
    # the first installed program or library decides (docs, man pages and headers are stripped or irrelevant)
    f=$(awk '$1=="obj" && $2 ~ /^\/usr\/(bin|sbin|lib64|lib|libexec)\// {print $2; exit}' "$c")
    if [ -z "$f" ]; then f=$(awk '$1=="obj" && $2 !~ /^\/usr\/share\/(doc|man|info|locale)\// {print $2; exit}' "$c"); fi
    [ -n "$f" ] && [ -e "$STAGE$f" ] && echo "$name" >> "$tmp"
done
mkdir -p "$(dirname "$OUT")"
sort -u "$tmp" > "$OUT"
rm -f "$tmp"
echo "base-packages: $(wc -l < "$OUT") packages provided by the image"
