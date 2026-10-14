# Changelog

## 0.2.2

### Fixed
- The live ISO failed to boot with `could not find the live medium (a device with /live/rootfs.squashfs)`: distro
  kernels build isofs, squashfs, overlay, loop and the storage drivers as modules, and the initramfs had none.
  `build_iso.sh` now fetches the `linux-modules` (and `-extra`) packages for the embedded kernel, `build-initrd.sh`
  copies the needed modules (decompressed, with dependencies) and runs `depmod`, and `init` loads them first.
- `init` also finds the medium by its volume label (`SYSTEMLINUX`, or `systemlinux.label=`), logs
  `[live] medium found` and prints filesystems and block devices on failure.

### Changed
- Version 0.2.2; the ISO is `systemLinux-0.2.2-x86_64.iso`, with a BIOS+UEFI hybrid layout when `grub-pc-bin` is installed.
- CI boots the built ISO headless in QEMU and only uploads the artifact when it reaches the live init marker.

## 2.0.0 (2.0)

### Breaking changes
- `goget` is removed and replaced by `get`, a POSIX `sh` script: `get URL` downloads a source tarball, extracts it,
  runs `./configure`, `make` and `make install` into a chosen prefix. `goget upgrade`, the nixpkgs-based package set
  and the `goget-check` update notifier no longer exist; update by installing the new ISO.
- The live ISO is minimal and install-only: the kernel plus the bare minimum to run `systemlinux-install`
  (systemd, NetworkManager, disk/boot tools, `get`). No desktop, firmware bundles, docs, locales, extra daemons,
  compilers or language runtimes.
- The build stack is now installed after installation with `get --profile build-toolchain`
  (also `common-build-deps`, `lang-runtimes`, ...); `validate-build-ready` checks it.
- The init system is systemd (introduced in 1.2); the previous init is gone.
- The ISO is named `systemLinux-2.0-x86_64.iso` (was `systemlinux-vX.Y.iso`) and ships with a `.sha256` file and a
  release-wide `SHA256SUMS`.

### Added
- GitHub Actions: `build-iso.yml` builds the ISO and checksums; `release.yml` publishes a GitHub Release on a
  `v2.0.0` (or `v2.0`) tag.
- Release assets: `systemLinux-2.0-x86_64.iso`, `systemLinux-2.0-x86_64.iso.sha256`, `SHA256SUMS` (covers the ISO and
  the profile archives) and the `profile-NAME.tar.xz` / `.sha256` / `.requires` files that `get --profile NAME` installs.
- `make iso` as a shortcut for `./build_iso.sh`.
- Website: what's new section, 2.0 download and checksum links, `get` usage examples.

### Changed
- Version bumped to 2.0 in `VERSION`, `os-release`, `issue`, the installer/provisioning script, README and website.
