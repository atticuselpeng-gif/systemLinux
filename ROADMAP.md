# systemLinux roadmap

## Toward 0.3.0: a themed Sway live ISO with Firefox and foot

Each release does one job and is shippable on its own, and every release also adds a large batch of new ports.
Decided: Firefox comes as `firefox-bin` (Mozilla's build), installed systems get the same themed Sway desktop as the
live ISO, and there is no elogind (seatd, the login-time runtime directory and a per-user dinit do its job).

- **0.2.5: install by hand.** Stage tarball, the systemLinux Wiki with a Gentoo-style Handbook, `root=UUID=` boot with
  LUKS, GRUB that boots on UEFI from any build host, desktop sessions without elogind, `linux-firmware`.
- **0.2.6: build inside the stage.** `build_iso.sh` works like Gentoo's catalyst: it chroots into a seed stage and
  builds the release there, so any Linux distribution can build it, and installs ports into the image with `get`
  (which already works on the live system).
  `systemlinux-install` makes stage installs (no more image installs, which also fixes `--luks`). An initramfs
  builder on the installed system. ModemManager stops printing over the login prompt.
- **0.2.7: the graphics stack in the image.** Mesa (without LLVM), wlroots, Sway, foot, seatd, PipeWire and
  WirePlumber, fonts and the `desktop-runtime` profile, built as ports into the image. CI build time stays under the
  runners' limit.
- **0.2.8: the live desktop.** A `live` user logged in automatically into Sway on tty1, `firefox-bin`, foot, a launcher,
  and the theme: a Tux wallpaper. The installer runs from a foot window, and installed systems get the same desktop.
- **0.2.9: release candidate.** A graphical smoke test in CI (QEMU screenshots: Sway and Firefox appear), ISO size and
  memory checks, the wiki updated for the live desktop.
- **0.3.0: the themed Sway live ISO**, with Firefox and foot.

After 0.3.0: the base system as ports and `get upgrade` (0.4), a base built from source with musl (0.5), and toward
1.0, KDE Plasma as the desktop with a graphical installer.

---

## Older roadmap (historical)


> **Refactor note:** `goget` (the Go package manager, with `goget upgrade` image updates and the nixpkgs-based
> overlays for firmware, Bluetooth, audio, printing and so on) has been replaced by `get`, a POSIX `sh` script
> that builds a source tarball. The live ISO is now minimal installer media only: kernel plus the bare
> minimum to run `systemlinux-install`. Items below that mention goget, firmware or the removed services
> are historical. Follow-ups: image updates and a firmware package would need new designs.

1.0 through 1.2 together mean: install it on a laptop, use it every day for browsing, mail, media, calls and
development, and update it without fear. Status is honest: done means tested (in a VM, or here,
a real rebuilt kernel), not just written. Items
that fundamentally need real hardware or real UEFI firmware to verify are marked as such and left
open, not checked off on faith.

## Done (0.4 - 0.6)
- Live console system, native CLI installer (`systemlinux-install`), persistent installs, signed
  image updates with rollback (`goget upgrade`, since removed)
- Full-driver kernel, firmware, Wi-Fi via NetworkManager

## 1.1: minimal-only, no GUI installer, everyday hardware
The GNOME live edition and its GTK4 graphical installer are gone entirely — one console-only ISO,
installed with `systemlinux-install` (a terminal tool) or by hand from the Handbook. Everything
below that used to be GNOME-desktop-only now runs as plain systemd services instead.

- [x] power off / reboot (`systemctl`, no desktop needed)
- [x] audio: PipeWire + WirePlumber + PulseAudio compatibility, system-wide (reworked off the old
      GNOME-session-only autostart)
- [x] Bluetooth (bluez) — no GNOME panel, `bluetoothctl` is the console-edition's interface
- [x] time sync (chrony), power profiles (`powerprofilesctl`), Flatpak + Flathub (remote added
      automatically at install) — no GNOME Software, that was GNOME-specific and is dropped
- [x] firewall on by default (nftables, default-deny-inbound) — this needed a real kernel config
      fix (`NF_TABLES_INET/IPV4/IPV6/ARP/BRIDGE` were compiled out) and a real kernel rebuild, both
      done; not just a config file edit
- [x] LUKS full-disk encryption, in `systemlinux-install` and the manual Handbook steps, with the
      live initramfs able to unlock an encrypted installed system at boot
- [x] dual-boot / resize-free install: `systemlinux-install --partition` installs onto an existing
      partition you've already freed up yourself (GParted/Disk Management beforehand) instead of
      erasing a whole disk — deliberately *not* automatic resizing, which would be a genuinely
      risky thing to do unattended to someone's existing Windows/Linux partitions
- [x] printing (CUPS), firmware updates (fwupd)
- [x] locales (glibc-locales, `en_US.UTF-8` pre-baked, others addable), CJK fonts, fcitx5
      installed (not auto-started — no desktop session to launch it from yet; ibus was dropped —
      its prebuilt closure drags in a GTK+Python setup GUI that can't run without a desktop
      session anyway, and fcitx5 alone covers the same need much more cheaply)
- [x] a CLI update notifier: `goget-check.timer` runs `goget upgrade --check` every 12h, visible in
      `systemctl list-timers`
- [x] documented recovery: a real Recovery chapter in the Handbook (GRUB older-image rollback,
      live-ISO chroot repair, `/persist` backup guidance)
- [ ] suspend/resume and lid/power keys, battery and brightness **verified on real laptops** —
      systemd-logind (session/seat tracking, `loginctl suspend`, lid-switch and power-key
      handling per `logind.conf`) and kernel-level suspend support (`CONFIG_SUSPEND`,
      `CONFIG_ACPI_SLEEP`) are both in place, but none of it has been tried on real hardware
- [ ] clean shutdown path **verified on real hardware** — systemd's own shutdown path, with the
      overlay root on the data partition; "verified on real hardware" specifically is still open
- [ ] NVIDIA proprietary driver, hybrid graphics — no packaging path exists (no proprietary blobs
      bundled); open nouveau is what's in the kernel today
- [ ] Secure Boot (signed shim + GRUB) — the kernel is structurally ready (module signing, EFI
      stub, lockdown LSM), but there is no shim/MOK signing pipeline in this repo. Not started,
      not half-done — genuinely nothing here yet. Needs real UEFI firmware to verify enrollment
      even once it exists.
- [ ] scanners (SANE) — not addressed at all yet
- [ ] translations of the installer/website UI itself — only the locale *mechanism* is in place;
      the actual English-only strings haven't been translated
- [x] **ISO size**: fixed. Root cause was nixpkgs' `linux-firmware` bundling firmware for
      every device that has ever existed, included *twice* (initramfs + squashfs), where the
      old Debian-based build cherry-picked ~17 relevant per-vendor packages instead. Tried
      the surgical fix first (filter to only what this kernel's drivers reference via
      `MODULE_FIRMWARE()` in the kernel source) and abandoned it: `iwlwifi` — extremely
      common Intel WiFi hardware — builds its firmware filenames entirely at runtime with
      zero literal strings in source, so that approach would have silently broken WiFi for a
      large share of real laptops. Used a categorical exclusion instead: dropped vendor
      directories that cannot run on x86_64 *at all* (Qualcomm Snapdragon/Adreno SoC
      firmware — 450 MB alone — plus other ARM/embedded-only vendors) and enterprise
      datacenter NICs outside this project's laptop/desktop target (Netronome, Mellanox).
      Real PC WiFi/BT/GPU vendors (MediaTek, Marvell, Atheros, AMD, Intel, NVIDIA) untouched.
      Final measured ISO: 1.9 GB, under GitHub's 2 GB release-asset limit with real margin —
      attached directly to the `v1.1` release, no split files, no external hosting needed.

## 1.2: systemd
- [x] systemd is the init again (lenine, the custom Go init, is gone); the base services and
      timers are ordinary systemd units, and `systemctl`/`journalctl`/`loginctl` work as usual
- [x] systemd-logind replaces elogind; lid-switch and power-key handling come from `logind.conf`
- [x] installed systems ask for a login on tty1 (the live ISO still logs root in by itself)
- [x] compressed swap in RAM: `CONFIG_ZRAM` is now built into the kernel, so `zram.service`
      (4 GB zstd zram swap) actually works
- [x] booted in a UEFI VM: every base service, both timers, NetworkManager and logind come up

## 1.3 and beyond
- [ ] a week of daily use on real hardware (ThinkPad, IdeaPad, a desktop) with no reinstall
- [ ] Secure Boot: build the actual signing pipeline once someone can test real enrollment
- [ ] suspend/resume on lid/power-key events validated on real hardware
- [ ] scanners, UI translations
- [ ] a real per-driver firmware trim (matching this kernel's actual driver set, not just
      whole-vendor exclusion) — safe to attempt now that there's ISO-size headroom again, no
      rush

## Unreleased: dinit and BIOS
- [x] dinit replaces systemd as PID 1 (`docs/DINIT.md`)
- [x] legacy BIOS + UEFI hybrid ISO and installer (`docs/BIOS.md`)
- [ ] the dinit boot and the BIOS/UEFI smoke tests have not been run yet in CI or on real hardware
