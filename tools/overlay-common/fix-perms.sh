#!/bin/sh
# Owners and modes git does not keep. rootfs/ comes from a git checkout, so every file is owned by the build user
# and no setuid/setgid/sticky bit survives: su, passwd and sudo cannot work and /etc/shadow is world-readable.
# Run as root on the staged image, right before it is packed.
# usage: fix-perms.sh ROOTFS
set -eu
R=${1:?usage: fix-perms.sh ROOTFS}
chown -R 0:0 "$R"
for d in tmp var/tmp; do mkdir -p "$R/$d"; chmod 1777 "$R/$d"; done
mkdir -p "$R/root"; chmod 700 "$R/root"
for f in etc/shadow etc/shadow- etc/gshadow etc/gshadow-; do [ -e "$R/$f" ] && chmod 600 "$R/$f"; done
for f in usr/bin/su usr/bin/sudo usr/bin/passwd usr/bin/chsh usr/bin/chfn usr/bin/gpasswd usr/bin/newgrp \
         usr/bin/chage usr/bin/expiry usr/bin/mount usr/bin/umount usr/bin/fusermount usr/bin/fusermount3 \
         usr/bin/newuidmap usr/bin/newgidmap usr/bin/ping usr/bin/crontab; do
    [ -f "$R/$f" ] && [ ! -L "$R/$f" ] && chmod 4755 "$R/$f"
done
for f in sbin/unix_chkpwd usr/sbin/unix_chkpwd usr/bin/unix_chkpwd; do
    [ -f "$R/$f" ] && [ ! -L "$R/$f" ] && chmod 4711 "$R/$f"
done
[ -f "$R/etc/sudoers" ] && chmod 440 "$R/etc/sudoers"
if [ -d "$R/etc/sudoers.d" ]; then chmod 750 "$R/etc/sudoers.d"; find "$R/etc/sudoers.d" -type f -exec chmod 440 {} +; fi
[ -d "$R/var/db/sudo" ] && chmod -R go-rwx "$R/var/db/sudo"
# D-Bus activation helper: setuid root, runnable only by the messagebus group
MB=$(sed -n 's/^messagebus:[^:]*:\([0-9]*\):.*/\1/p' "$R/etc/group")
if [ -n "$MB" ] && [ -f "$R/usr/libexec/dbus-daemon-launch-helper" ]; then
    chown "0:$MB" "$R/usr/libexec/dbus-daemon-launch-helper"; chmod 4750 "$R/usr/libexec/dbus-daemon-launch-helper"
fi
