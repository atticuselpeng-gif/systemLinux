# Legacy BIOS and UEFI boot

## The ISO
`build_iso.sh` masters the ISO with `grub-mkrescue`, which produces a hybrid image: an El Torito BIOS entry that boots
GRUB `i386-pc` (needs `grub-pc-bin`/`grub2-pc-modules` on the build host), an El Torito EFI entry with GRUB `x86_64-efi`
(`grub-efi-amd64-bin`), and an MBR/GPT so that it also boots when written to a USB stick. The build stops with
an error if either platform's GRUB files are missing, instead of silently producing a UEFI-only image.
The same `grub.cfg` serves both.

## Installing
`systemlinux-install` follows the firmware it was booted with:

* `--disk DISK` always writes **GPT**: partition 1 = 1 MiB *BIOS boot* (`21686148-6449-6E6F-744E-656564454649`),
  2 = 512 MiB EFI System Partition, 3 = ext4 data. GRUB `i386-pc` goes to the disk (core.img in the BIOS boot
  partition) and GRUB `x86_64-efi` to the ESP (removable path, plus an `efibootmgr` entry when booted in UEFI),
  so the installed disk boots in either mode.
* `--partition PART` in **UEFI** mode needs an ESP (auto-detected or `--esp`), as before. In **BIOS** mode no ESP is
  needed; GRUB is written to the disk that holds `PART`. That disk must be MBR (embedding gap) or GPT with a
  BIOS boot partition you created yourself.

## Testing
`tools/tests/boot-smoke.sh bios|uefi [ISO]` boots the ISO in QEMU (SeaBIOS or OVMF) through GRUB and checks that
dinit reaches its `boot` service. CI runs both modes (`.github/workflows/build-iso.yml`). Needs `qemu-system-x86_64`, `mtools`
and, for UEFI, OVMF.
