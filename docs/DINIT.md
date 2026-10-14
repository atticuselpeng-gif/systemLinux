# dinit: the init system

systemLinux uses [dinit](https://github.com/davmac314/dinit) (pinned release in `tools/dinit/build.sh`, checksum verified)
as PID 1 and is the only init system. **systemd has been removed completely**: the service manager, units, generators,
journald/logind/networkd/resolved, `systemctl` & co., `systemd-udevd`, systemd's `libudev`, the NSS modules,
`/etc/systemd` and `pam_systemd` are gone, and so are the old OpenRC scripts (`/etc/init.d`, `/etc/runlevels`).
`tools/check-no-systemd.sh` enforces this.

* The device manager is **eudev** (`/usr/bin/udevd`, `udevadm`, `libudev.so.1`), built from a pinned, checksummed
  release by `tools/eudev/build.sh`.
* Prebuilt programs that were linked against `libsystemd.so.0` (dbus, NetworkManager, util-linux, shadow, PAM modules,
  pppd) get `tools/libsystemd-stub`: a small library with no systemd code that reports "not booted with systemd"
  (no journal, no logind sessions), so they use syslog/utmp/libudev instead. Its build fails if any binary in the
  image imports a symbol the stub does not provide.
* The machine id is made with `dbus-uuidgen`.

## Boot handoff
1. GRUB loads `/live/vmlinuz` + `/live/initrd.img` (installed systems: `/boot/images/<ver>/`).
2. `tools/live-image/init` (busybox) finds the medium, mounts the squashfs with an overlay and moves `/proc`, `/sys`,
   `/dev` into it. It mounts a tmpfs on `/newroot/run` (dinit creates `/run/dinitctl` immediately), then
   `exec switch_root /newroot /usr/bin/dinit`. Override with `init=/path` on the kernel command line.
3. dinit (PID 1) starts its default service `boot`.

## Services (`rootfs/etc/dinit.d/`)
| service | type | depends-on / waits-for | systemd equivalent |
|---|---|---|---|
| `boot` | internal | depends-on `early-filesystems`, `udev-trigger`, `system-identity`; waits-for `mount-fstab`, `zram`, `network`, `getty-tty1`, and everything linked in `boot.d/` | `default.target`/`multi-user.target` |
| `early-filesystems` | scripted | – | `local-fs.target`, `tmp.mount`, API mounts |
| `udevd` | process | `early-filesystems` | `systemd-udevd.service` (eudev here) |
| `udev-trigger` | scripted | `udevd` | `systemd-udev-trigger.service` |
| `mount-fstab` | scripted | `early-filesystems`, waits-for `udev-trigger` | `/etc/fstab` mounts (installed systems) |
| `system-identity` | scripted | `early-filesystems` | hostname, machine-id, loopback |
| `zram` | scripted (`stop-command`) | `early-filesystems` | `zram.service` |
| `dbus-prepare`, `dbus` | scripted, process | `system-identity` → `dbus-prepare` → `dbus` | `dbus.service` |
| `NetworkManager` | process | `dbus`, `udev-trigger` | `NetworkManager.service` |
| `network` | internal | `NetworkManager` | `network-online.target` (loosely) |
| `getty-tty1` | process | `system-identity` | `getty@tty1` + autologin override |
| `ssh-keygen` | scripted | `early-filesystems` | `systemlinux-ssh-keygen.service` (enabled by the installer via `boot.d`) |

`process` services run in the foreground and are supervised/restarted by dinit (`dbus-daemon --nofork`,
`NetworkManager --no-daemon`); `scripted` services run a helper from `rootfs/usr/lib/dinit/` to completion;
`internal` services only group dependencies. Services are enabled by linking them into `/etc/dinit.d/boot.d/`
(`dinitctl enable NAME`).

## Shutdown, reboot, poweroff
dinit's own `shutdown`, `reboot`, `poweroff`, `halt` (installed to `/usr/bin` – `/sbin` is `/usr/bin` – replacing the old
systemd tools) ask PID 1 to stop `boot` and everything it started in reverse dependency order, then
kill remaining processes, unmount filesystems, `sync`, and power off/reboot. `zram` turns swap off in its
`stop-command`.

## Checking
`tools/dinit/check-services.sh` runs `dinit-check` on the tree (CI: `.github/workflows/dinit-check.yml`);
`build_iso.sh` runs it too. `tools/tests/boot-smoke.sh` boots the ISO in QEMU and waits for `[  OK  ] boot`.
