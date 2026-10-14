# Building the systemLinux ISO

The ISO is a minimal, install-only live image (kernel + initramfs + squashfs with the installer). The build
stack, desktop and language runtimes are post-install profiles (`get --profile build-toolchain`, ...).

## Prerequisites
A Linux host with sudo, ~30 GB free disk, and: `grub` with both the `i386-pc` (BIOS) and `x86_64-efi` platform files (grub-mkrescue, grub-install), `g++`, `curl` (dinit is built from source), `xorriso`, `mtools`,
`squashfs-tools`, `cpio`, `busybox`, `cryptsetup`, `efibootmgr`, `dosfstools`, `flex`, `bison`, `bc`, `pahole`,
`gcc`, `make`, `perl`, libelf/openssl headers. The kernel source `linux-7.2.6.tar.xz` goes in `systemlinux-distro/`
(CI downloads it from cdn.kernel.org). `build_iso.sh` lists anything missing.

## Build
```sh
./build_iso.sh        # or: make iso
```
Outputs: `systemLinux-2.0-x86_64.iso`, `systemLinux-2.0-x86_64.iso.sha256`, `profiles-out/profile-*`.
Name is `systemLinux-$(cat VERSION)-x86_64.iso`. Release `SHA256SUMS` (ISO + profiles) is made by CI:
```sh
mkdir dist && cp systemLinux-2.0-x86_64.iso* profiles-out/* dist/ && cd dist && sha256sum -- * | grep -v '\.sha256$' > SHA256SUMS
```

## Testing the ISO
```sh
tools/tests/boot-smoke.sh bios    # QEMU, legacy BIOS
tools/tests/boot-smoke.sh uefi    # QEMU + OVMF
```
See `docs/BIOS.md` and `docs/DINIT.md`.

## Releasing `v2.0.0` (maintainers)
1. Optionally run the `Build ISO` workflow (workflow_dispatch) and check the artifacts.
2. `git tag v2.0.0 && git push origin v2.0.0`
3. `release.yml` builds the ISO, verifies checksums and creates the release with the ISO, `.sha256`,
   `SHA256SUMS`, profiles and the `## 2.0` CHANGELOG entry as notes.
4. Confirm the links on `website/download.html` (`releases/download/v2.0.0/...`) resolve.

## Verification status
The agent sandbox cannot run the full build (needs sudo, ~30 GB, kernel build, grub/xorriso host tools);
run the command above locally or via the workflow to verify.
