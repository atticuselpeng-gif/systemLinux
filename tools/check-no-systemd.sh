#!/bin/sh
# Fails if the systemd service manager (or any of its tools/units) is present in a rootfs tree.
# Only the udev daemon/tools and the libsystemd/libudev shared libraries may remain.
# usage: tools/check-no-systemd.sh [rootfs-dir]   (default: ./rootfs)
R=${1:-rootfs}
bad=0
for p in usr/lib/systemd etc/systemd usr/bin/systemctl usr/bin/journalctl usr/bin/loginctl usr/bin/machinectl \
         usr/bin/systemd-tmpfiles usr/bin/systemd-sysusers usr/bin/systemd-machine-id-setup usr/sbin/systemctl \
         usr/lib64/security/pam_systemd.so; do
    if [ -e "$R/$p" ] || [ -L "$R/$p" ]; then echo "systemd leftover: $p"; bad=1; fi
done
for l in usr/bin/init usr/sbin/init; do
    [ -L "$R/$l" ] && case "$(readlink "$R/$l")" in *systemd*) echo "init still points at systemd: $l"; bad=1;; esac
done
for u in "$R"/usr/bin/reboot "$R"/usr/bin/poweroff "$R"/usr/bin/halt "$R"/usr/bin/shutdown; do
    [ -L "$u" ] && case "$(readlink "$u")" in *systemctl*) echo "systemctl symlink: ${u#$R/}"; bad=1;; esac
done
if [ "$bad" = 0 ]; then echo "check-no-systemd: OK"; fi
exit "$bad"
