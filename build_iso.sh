#!/bin/bash
# systemLinux ISO build: a minimal live installer ISO (small initramfs + /live/rootfs.squashfs, mounted
# with an overlayfs; nothing is loaded into a RAM disk): the full-driver kernel plus the bare minimum
# needed to run the installer (systemd, NetworkManager, disk/boot tools, `get`). No firmware, desktop,
# daemons, docs, locales, compilers or language runtimes. After installing, `get --profile build-toolchain`
# (and common-build-deps, lang-runtimes, ...) adds the build stack; `get URL` builds source tarballs.
#
#   ./build_iso.sh    -> systemLinux-2.0-x86_64.iso + .sha256  (root shell, console only, installable with the handbook)
#
# Run from a normal terminal (sudo needs a password prompt). Works from any Linux host with
# grub2, xorriso, mtools, squashfs-tools and cpio on PATH (install them with your host's own
# package manager, e.g. `emerge sys-boot/grub app-cdr/xorriso sys-fs/mtools sys-fs/squashfs-tools
# app-arch/cpio` on Gentoo, `apt install grub2 xorriso mtools squashfs-tools cpio` on Debian, or
# equivalent). The installer's own boot tools (grub, efibootmgr, mkfs.fat, cryptsetup, busybox) are
# copied from the build host together with their libraries. UEFI only.
set -euo pipefail

BUILD_DIR=$(cd "$(dirname "$0")" && pwd)
ROOTFS=$BUILD_DIR/rootfs
WORKSPACE=$BUILD_DIR/iso_workspace
# the "full" kernel is the same Linux 7.2.6 with drivers for almost everything built in
KERNEL=${KERNEL:-$BUILD_DIR/tools/kernel-full/vmlinuz-7.2.6-full}
IMAGE_VERSION=$(cat "$BUILD_DIR/VERSION")
PROFILES_OUT=${PROFILES_OUT:-$BUILD_DIR/profiles-out}
ISO=${ISO:-$BUILD_DIR/systemLinux-$IMAGE_VERSION-x86_64.iso}
cd "$BUILD_DIR"
# fail early, with the fix, instead of halfway through the kernel build
missing=
for t in xorriso mksquashfs mformat cpio make gcc flex bison bc perl pahole busybox cryptsetup efibootmgr mkfs.fat grub-install grub-mkimage; do
    command -v "$t" >/dev/null || missing="$missing $t"
done
command -v grub-mkrescue >/dev/null || command -v grub2-mkrescue >/dev/null || missing="$missing grub-mkrescue"
command -v grub-script-check >/dev/null || command -v grub2-script-check >/dev/null || missing="$missing grub-script-check"
if [ -n "$missing" ]; then
    echo "ERROR: missing build tools:$missing"
    echo "  (the installer needs the grub-* command names; on Fedora add symlinks from grub2-*)"
    echo "  Fedora: sudo dnf install xorriso squashfs-tools mtools cpio busybox cryptsetup efibootmgr dosfstools grub2-efi-x64 grub2-tools flex bison bc dwarves elfutils-libelf-devel openssl-devel openssl-devel-engine grub2-tools-extra"
    echo "  Debian: sudo apt install xorriso squashfs-tools mtools cpio busybox cryptsetup efibootmgr dosfstools grub-efi-amd64-bin flex bison bc dwarves libelf-dev libssl-dev grub-common"
    exit 1
fi
# Fedora and friends name the GRUB tools grub2-*
GRUB_MKRESCUE=$(command -v grub-mkrescue || command -v grub2-mkrescue || echo grub-mkrescue)
GRUB_SCRIPT_CHECK=$(command -v grub-script-check || command -v grub2-script-check || echo grub-script-check)
GRUB_MKIMAGE=$(command -v grub-mkimage || command -v grub2-mkimage || echo grub-mkimage)

echo "=== [1/7] BUILDING THE FULL KERNEL ==="
if [ ! -f "$KERNEL" ]; then "$BUILD_DIR/tools/kernel-full/build-kernel.sh"; fi
[ -f "$KERNEL" ] || { echo "ERROR: kernel not found at $KERNEL"; exit 1; }

echo "=== [2/7] INSTALLING get AND init LINKS INTO ROOTFS ==="
sudo install -Dm755 ./get "$ROOTFS/usr/local/bin/get"
sudo install -Dm755 ./tools/validate-build-ready.sh "$ROOTFS/usr/local/bin/validate-build-ready"
sudo rm -f "$ROOTFS/init" "$ROOTFS/sbin/init" "$ROOTFS/sbin/lenine"
sudo ln -sf usr/lib/systemd/systemd "$ROOTFS/init"
sudo ln -sf ../lib/systemd/systemd "$ROOTFS/sbin/init"
for n in reboot poweroff halt shutdown; do
    sudo ln -sf systemctl "$ROOTFS/usr/bin/$n"
done
# boot to the console (there is no display manager), with NetworkManager and a tmpfs /tmp
sudo ln -sf /usr/lib/systemd/system/multi-user.target "$ROOTFS/etc/systemd/system/default.target"
sudo mkdir -p "$ROOTFS/etc/systemd/system/multi-user.target.wants" "$ROOTFS/etc/systemd/system/local-fs.target.wants"
sudo ln -sf /usr/lib/systemd/system/NetworkManager.service "$ROOTFS/etc/systemd/system/multi-user.target.wants/NetworkManager.service"
sudo ln -sf /usr/lib/systemd/system/tmp.mount "$ROOTFS/etc/systemd/system/local-fs.target.wants/tmp.mount"
sudo install -Dm644 "$KERNEL" "$ROOTFS/boot/vmlinuz"

echo "=== [3/7] ROOTFS FIXES AND BRANDING ==="
# D-Bus activation needs the launch helper setuid root (it was owned by the build user with no setuid bit)
# (the image's own messagebus gid: the host may not have that group, e.g. Fedora calls it dbus)
MB=$(sed -n 's/^messagebus:[^:]*:\([0-9]*\):.*/\1/p' "$ROOTFS/etc/group")
sudo chown "0:${MB:?no messagebus group in $ROOTFS/etc/group}" "$ROOTFS/usr/libexec/dbus-daemon-launch-helper"
sudo chmod 4750 "$ROOTFS/usr/libexec/dbus-daemon-launch-helper"
# GNU bash is the system shell (/bin/bash and /bin/sh); the bbash fork stays installed as its own command.
# Built static, so it does not depend on the base's libtinfo. The libarchive tools (BSD tar and friends)
# are removed: GNU tar is the tar.
[ -x tools/gnu-bash/bash ] || tools/gnu-bash/build.sh
sudo install -Dm755 tools/gnu-bash/bash "$ROOTFS/usr/bin/bash"
sudo ln -sf bash "$ROOTFS/usr/bin/sh"
sudo rm -f "$ROOTFS"/usr/bin/bsdtar "$ROOTFS"/usr/bin/bsdcat "$ROOTFS"/usr/bin/bsdcpio "$ROOTFS"/usr/bin/bsdunzip
# issue, os-release, release files and the login banner (GNU/Linux branding)
sudo ./tools/installer/usr/local/bin/systemlinux-provision "$ROOTFS"

echo "=== [4/7] PREPARING ISO WORKSPACE ==="
if mount | grep -q " $ROOTFS/"; then
    echo "ERROR: something is still mounted under $ROOTFS; refusing to pack it"; exit 1
fi
sudo rm -rf "$WORKSPACE"
mkdir -p "$WORKSPACE/live" "$WORKSPACE/boot/grub"

echo "=== [5/7] BUILDING THE SQUASHFS AND THE INITRAMFS ==="
STAGE=$WORKSPACE/stage
sudo mkdir -p "$STAGE"
sudo cp -a "$ROOTFS/." "$STAGE/"
sudo "$BUILD_DIR/tools/overlay-common/strip-gentoo.sh" "$STAGE"
# the installer's boot/disk tools (the build host's own binaries and libraries)
sudo "$BUILD_DIR/tools/overlay-common/copy-bin.sh" "$STAGE" grub-install "$GRUB_MKIMAGE" grub-probe grub-editenv \
    grub-set-default grub-reboot efibootmgr mkfs.fat
GRUBDATA=0
for d in /usr/lib/grub /usr/lib64/grub /usr/share/grub /usr/lib/grub2 /usr/share/grub2; do
    if [ -d "$d" ]; then sudo mkdir -p "$STAGE$d"; sudo cp -a "$d/." "$STAGE$d/"; GRUBDATA=1; fi
done
[ "$GRUBDATA" = 1 ] || { echo "ERROR: no GRUB platform files (x86_64-efi) found on the build host"; exit 1; }
MKFS=$(readlink -f "$(command -v mkfs.fat)")
sudo ln -sf "$(basename "$MKFS")" "$STAGE$(dirname "$MKFS")/mkfs.vfat"
# the installer itself, and the minimal systemd preset / hostname
sudo cp -a "$BUILD_DIR/tools/installer/." "$STAGE/"
sudo chmod 755 "$STAGE"/usr/local/bin/systemlinux-*
sudo "$BUILD_DIR/tools/live-image/strip-live.sh" "$STAGE"
# the build toolchain, build dependencies and language runtimes are post-install profiles, not live media
sudo "$BUILD_DIR/tools/profiles/profiles.sh" strip "$STAGE"
echo "$IMAGE_VERSION" | sudo tee "$STAGE/usr/share/systemlinux/image-version" >/dev/null
sudo install -Dm644 "$KERNEL" "$STAGE/boot/vmlinuz"
sudo mksquashfs "$STAGE" "$WORKSPACE/live/rootfs.squashfs" -comp zstd -Xcompression-level 6 -b 1M -noappend -no-xattrs
sudo rm -rf "$STAGE"
sudo chown "$USER" "$WORKSPACE/live/rootfs.squashfs"
ls -lh "$WORKSPACE/live/rootfs.squashfs"
BUILD_ID="$IMAGE_VERSION-$(date +%s)"
echo "$BUILD_ID" > "$WORKSPACE/live/build-id"
BUILD_ID=$BUILD_ID WORK=$HOME/.cache/systemlinux-initrd "$BUILD_DIR/tools/live-image/build-initrd.sh" "$WORKSPACE/live/initrd.img"

echo "=== [6/7] COPYING KERNEL AND WRITING grub.cfg ==="
cp "$KERNEL" "$WORKSPACE/live/vmlinuz"
cat > "$WORKSPACE/boot/grub/grub.cfg" << GRUBEOF
set default=0
set timeout=3

menuentry "systemLinux $IMAGE_VERSION" {
    # Use the device GRUB booted from (works under Ventoy's loopback); only search if the
    # kernel isn't there, so another disk's /live/vmlinuz is never picked up.
    if [ ! -f /live/vmlinuz ]; then
        search --no-floppy --set=root --file /live/vmlinuz
    fi
    linux /live/vmlinuz quiet loglevel=3 console=tty0
    initrd /live/initrd.img
}

menuentry "systemLinux $IMAGE_VERSION (copy to RAM)" {
    if [ ! -f /live/vmlinuz ]; then
        search --no-floppy --set=root --file /live/vmlinuz
    fi
    linux /live/vmlinuz systemlinux.toram=1 quiet loglevel=3 console=tty0
    initrd /live/initrd.img
}

menuentry "systemLinux $IMAGE_VERSION (debug shell)" {
    if [ ! -f /live/vmlinuz ]; then
        search --no-floppy --set=root --file /live/vmlinuz
    fi
    linux /live/vmlinuz systemlinux.debug=1 console=tty0
    initrd /live/initrd.img
}
GRUBEOF
"$GRUB_SCRIPT_CHECK" "$WORKSPACE/boot/grub/grub.cfg"

echo "=== [7/7] MASTERING ISO AND PACKING PROFILES ==="
# profile-*.tar.xz (+ .sha256/.requires): upload them next to the ISO in the release; `get --profile NAME` installs them
ROOTFS=$ROOTFS "$BUILD_DIR/tools/profiles/profiles.sh" build "$PROFILES_OUT"
"$GRUB_MKRESCUE" -o "$ISO" "$WORKSPACE"
sudo rm -rf "$WORKSPACE"
(cd "$(dirname "$ISO")" && sha256sum "$(basename "$ISO")" | tee "$(basename "$ISO").sha256")
echo "SUCCESS: $ISO"
