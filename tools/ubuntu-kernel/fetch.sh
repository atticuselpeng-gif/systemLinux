#!/bin/sh
# Download the newest Ubuntu generic kernel (linux-image + linux-modules) straight from the Ubuntu archive and
# unpack it, independent of the build host's own distribution and kernel.
#
# "Newest" = the latest Ubuntu series listed in changelogs.ubuntu.com/meta-release-development (the development
# release while there is one), looking at its release, -updates and -security pockets and picking the highest
# linux-image-generic version. Set UBUNTU_SERIES=noble (etc.) to pin a series instead.
#
# Integrity: InRelease is verified with gpgv against the Ubuntu archive keyring when the host has it
# (the ubuntu-keyring package); Packages.xz is checked against InRelease and every .deb against Packages
# (SHA512, or SHA256 for older series).
#
# usage: fetch.sh OUTDIR   -> OUTDIR/root/boot/vmlinuz-KVER, OUTDIR/root/lib/modules/KVER, and OUTDIR/kver
set -eu
OUT=${1:?usage: fetch.sh OUTDIR}
MIRROR=${UBUNTU_MIRROR:-http://archive.ubuntu.com/ubuntu}
FLAVOUR=${UBUNTU_KERNEL_FLAVOUR:-generic}
mkdir -p "$OUT/idx" "$OUT/debs" "$OUT/root"
get() { curl -fsSL --retry 3 -o "$2" "$1"; }
# dpkg-deb when the host has it, otherwise ar + tar (a .deb is an ar archive holding data.tar.*)
unpack_deb() {
    if command -v dpkg-deb >/dev/null; then dpkg-deb -x "$1" "$2"; return; fi
    d=$(mktemp -d); (cd "$d" && ar x "$1")
    data=$(ls "$d"/data.tar* | head -n1)
    case "$data" in
        *.zst) zstd -dqc "$data" | tar -xf - -C "$2" ;;
        *.xz)  xz -dc "$data" | tar -xf - -C "$2" ;;
        *.gz)  gzip -dc "$data" | tar -xf - -C "$2" ;;
        *)     tar -xf "$data" -C "$2" ;;
    esac
    rm -rf "$d"
}

SERIES=${UBUNTU_SERIES:-}
if [ -z "$SERIES" ]; then
    SERIES=$(curl -fsSL --retry 3 https://changelogs.ubuntu.com/meta-release-development | sed -n 's/^Dist: //p' | tail -n1)
    [ -n "$SERIES" ] || SERIES=devel
fi
echo "ubuntu-kernel: series $SERIES ($MIRROR)"

KEYRING=
for k in /usr/share/keyrings/ubuntu-archive-keyring.gpg /usr/share/keyrings/ubuntu-archive-keyring.pgp \
         /etc/apt/trusted.gpg.d/ubuntu-keyring-2018-archive.gpg; do
    [ -f "$k" ] && { KEYRING=$k; break; }
done
[ -n "$KEYRING" ] || echo "ubuntu-kernel: WARNING: no Ubuntu archive keyring on this host; InRelease signatures not verified" >&2
# check ALGO FILE HEX
check() { [ "$("$(echo "$1" | tr 'A-Z' 'a-z')sum" "$2" | cut -d' ' -f1)" = "$3" ]; }

best_ver=; best_idx=
for pocket in "$SERIES" "$SERIES-updates" "$SERIES-security"; do
    get "$MIRROR/dists/$pocket/InRelease" "$OUT/idx/$pocket.InRelease" 2>/dev/null || continue
    if [ -n "$KEYRING" ]; then
        gpgv --keyring "$KEYRING" "$OUT/idx/$pocket.InRelease" >/dev/null 2>&1 \
            || { echo "ubuntu-kernel: InRelease signature check failed for $pocket" >&2; exit 1; }
    fi
    # newer releases list only SHA512, older ones SHA256 too: use the strongest one present
    algo=SHA512; want=$(awk -v h="$algo:" '$0==h{s=1;next} /^[A-Za-z]/{s=0} s && $3=="main/binary-amd64/Packages.xz"{print $1}' "$OUT/idx/$pocket.InRelease")
    [ -n "$want" ] || { algo=SHA256; want=$(awk -v h="$algo:" '$0==h{s=1;next} /^[A-Za-z]/{s=0} s && $3=="main/binary-amd64/Packages.xz"{print $1}' "$OUT/idx/$pocket.InRelease"); }
    [ -n "$want" ] || continue
    get "$MIRROR/dists/$pocket/main/binary-amd64/Packages.xz" "$OUT/idx/$pocket.Packages.xz"
    check "$algo" "$OUT/idx/$pocket.Packages.xz" "$want" || { echo "ubuntu-kernel: Packages.xz checksum mismatch for $pocket" >&2; exit 1; }
    xz -dc "$OUT/idx/$pocket.Packages.xz" > "$OUT/idx/$pocket.Packages"
    v=$(awk -v RS= -v p="linux-image-$FLAVOUR" '$0 ~ "^Package: " p "\n" {print}' "$OUT/idx/$pocket.Packages" \
        | sed -n 's/^Version: //p' | sort -V | tail -n1)
    [ -n "$v" ] || continue
    if [ -z "$best_ver" ] || [ "$(printf '%s\n%s\n' "$best_ver" "$v" | sort -V | tail -n1)" = "$v" ]; then
        best_ver=$v; best_idx=$OUT/idx/$pocket.Packages
    fi
done
[ -n "$best_ver" ] || { echo "ubuntu-kernel: no linux-image-$FLAVOUR in $SERIES" >&2; exit 1; }

# linux-image-generic depends on linux-image-<abi>-generic; that names the kernel release
stanza() { awk -v RS= -v p="$1" -v v="$2" '$0 ~ "^Package: " p "\n" && (v == "" || index($0, "\nVersion: " v "\n")) {print; exit}' "$best_idx"; }
KVER=$(stanza "linux-image-$FLAVOUR" "$best_ver" | sed -n 's/^Depends: //p' | tr ',' '\n' \
    | sed -n "s/^ *linux-image-\([0-9][^ ]*-$FLAVOUR\).*/\1/p" | head -n1)
[ -n "$KVER" ] || { echo "ubuntu-kernel: cannot work out the kernel release from linux-image-$FLAVOUR $best_ver" >&2; exit 1; }
echo "ubuntu-kernel: linux-image-$FLAVOUR $best_ver -> kernel $KVER"

for pkg in "linux-image-$KVER" "linux-modules-$KVER" "linux-modules-extra-$KVER"; do
    s=$(stanza "$pkg" "")
    if [ -z "$s" ]; then
        [ "$pkg" = "linux-modules-extra-$KVER" ] && continue   # newer releases ship every module in linux-modules
        echo "ubuntu-kernel: $pkg not found" >&2; exit 1
    fi
    file=$(echo "$s" | sed -n 's/^Filename: //p')
    algo=SHA512; sum=$(echo "$s" | sed -n 's/^SHA512: //p')
    [ -n "$sum" ] || { algo=SHA256; sum=$(echo "$s" | sed -n 's/^SHA256: //p'); }
    [ -n "$file" ] && [ -n "$sum" ] || { echo "ubuntu-kernel: no file/checksum for $pkg" >&2; exit 1; }
    deb=$OUT/debs/${file##*/}
    echo "ubuntu-kernel: downloading ${file##*/}"
    get "$MIRROR/$file" "$deb"
    check "$algo" "$deb" "$sum" || { echo "ubuntu-kernel: checksum mismatch for $deb" >&2; exit 1; }
    unpack_deb "$deb" "$OUT/root"
done
# Ubuntu installs modules under /lib/modules (usrmerge: /usr/lib/modules)
[ -d "$OUT/root/lib/modules/$KVER" ] || { [ -d "$OUT/root/usr/lib/modules/$KVER" ] && mkdir -p "$OUT/root/lib" \
    && mv "$OUT/root/usr/lib/modules" "$OUT/root/lib/modules"; }
[ -f "$OUT/root/boot/vmlinuz-$KVER" ] || { echo "ubuntu-kernel: no vmlinuz in linux-image-$KVER" >&2; exit 1; }
chmod 644 "$OUT/root/boot/vmlinuz-$KVER"
echo "$KVER" > "$OUT/kver"
rm -rf "$OUT/debs" "$OUT/idx"
