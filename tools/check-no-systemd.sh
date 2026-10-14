#!/bin/sh
# Fails if anything from systemd is present in a rootfs tree. dinit is the only init system and eudev
# (tools/eudev/build.sh) the device manager. The only file named after systemd that may exist is
# libsystemd.so.0 built from tools/libsystemd-stub (no systemd code; it must not export the real library's
# sd_bus_* API).
# usage: tools/check-no-systemd.sh [rootfs-dir]   (default: ./rootfs)
R=${1:-rootfs}
bad=0
fail() { echo "systemd leftover: $*"; bad=1; }
for p in usr/lib/systemd usr/lib64/systemd etc/systemd etc/xdg/systemd usr/share/systemd var/lib/systemd \
         usr/include/systemd usr/bin/systemctl usr/bin/journalctl usr/bin/loginctl usr/bin/machinectl \
         usr/bin/systemd-tmpfiles usr/bin/systemd-sysusers usr/bin/systemd-machine-id-setup usr/bin/run0 \
         usr/bin/varlinkctl usr/bin/storagectl usr/lib64/security/pam_systemd.so \
         usr/lib64/libnss_systemd.so.2 usr/lib64/libnss_resolve.so.2 usr/lib64/libnss_myhostname.so.2 \
         usr/lib64/libnss_mymachines.so.2 usr/lib64/pkgconfig/libsystemd.pc etc/init.d etc/runlevels; do
    if [ -e "$R/$p" ] || [ -L "$R/$p" ]; then fail "$p"; fi
done
for f in "$R"/usr/bin/systemd-* "$R"/usr/lib64/libsystemd-shared-* "$R"/usr/lib64/libudev.so.1.7.* \
         "$R"/var/db/pkg/sys-apps/systemd-[0-9]* "$R"/var/db/pkg/sys-apps/gentoo-systemd-integration-*; do
    if [ -e "$f" ] || [ -L "$f" ]; then fail "${f#$R/}"; fi
done
for l in usr/bin/init usr/sbin/init init; do
    [ -L "$R/$l" ] && case "$(readlink "$R/$l")" in *systemd*) echo "init still points at systemd: $l"; bad=1;; esac
done
for u in "$R"/usr/bin/reboot "$R"/usr/bin/poweroff "$R"/usr/bin/halt "$R"/usr/bin/shutdown; do
    [ -L "$u" ] && case "$(readlink "$u")" in *systemctl*) echo "systemctl symlink: ${u#$R/}"; bad=1;; esac
done
# systemd-udevd is udevadm under another name; eudev ships two separate programs
for u in "$R"/usr/lib/udev/udevd "$R"/usr/bin/udevd; do
    [ -L "$u" ] && case "$(readlink "$u")" in *udevadm*) echo "udevd is systemd's udevadm: ${u#$R/}"; bad=1;; esac
done
if [ -e "$R/usr/lib64/libsystemd.so.0" ] && nm -D --defined-only "$R/usr/lib64/libsystemd.so.0" 2>/dev/null | grep -q ' sd_bus_open'; then
    echo "systemd's own libsystemd.so.0 is installed (expected the tools/libsystemd-stub build)"; bad=1
fi
grep -Eq '^[a-z]+:.*\b(systemd|resolve|myhostname|mymachines)\b' "$R/etc/nsswitch.conf" 2>/dev/null \
    && { echo "nsswitch.conf uses systemd NSS modules"; bad=1; }
grep -q '^systemd-' "$R/etc/passwd" "$R/etc/group" 2>/dev/null && { echo "systemd accounts in passwd/group"; bad=1; }
if [ "$bad" = 0 ]; then echo "check-no-systemd: OK"; fi
exit "$bad"
