#!/bin/bash
# Boot the built ISO headless in QEMU through its real bootloader and check that the whole chain works:
# GRUB (legacy BIOS or UEFI) -> kernel -> initramfs (finds the live medium) -> dinit (PID 1) -> "boot" service.
#
# A tiny extra disk carrying a /SMOKETEST file makes the ISO's grub.cfg choose its "serial console" entry, so
# the log shows up on QEMU's serial port and nobody has to press a key.
#
# usage: boot-smoke.sh bios|uefi [ISO]        (ISO defaults to systemLinux-$(cat VERSION)-x86_64.iso)
#   TIMEOUT=SECONDS   how long to wait for the boot target (default 300)
#   OVMF=FILE         UEFI firmware image (default: searched in the usual distro locations)
#   KEEP=1            keep the work directory (serial.log) after the run
# Needs: qemu-system-x86_64, mtools (mformat, mcopy); for uefi also OVMF.
set -euo pipefail
MODE=${1:?usage: boot-smoke.sh bios|uefi [ISO]}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
ISO=${2:-$REPO/systemLinux-$(cat "$REPO/VERSION")-x86_64.iso}
TIMEOUT=${TIMEOUT:-300}
[ -f "$ISO" ] || { echo "boot-smoke: ISO $ISO not found" >&2; exit 2; }
W=$(mktemp -d)
cleanup() { [ -n "${QPID:-}" ] && kill "$QPID" 2>/dev/null || true; [ "${KEEP:-0}" = 1 ] && echo "kept $W" || rm -rf "$W"; }
trap cleanup EXIT

truncate -s 8M "$W/smoke.img"
mformat -i "$W/smoke.img" ::
echo smoke > "$W/SMOKETEST"
mcopy -i "$W/smoke.img" "$W/SMOKETEST" ::SMOKETEST

args=(-m 2G -smp 2 -no-reboot -display none -serial "file:$W/serial.log"
      -drive "file=$W/smoke.img,format=raw,if=ide,index=0" -drive "file=$ISO,media=cdrom,readonly=on,index=2" -boot d)
case "$MODE" in
    bios) ;;
    uefi)
        OVMF=${OVMF:-$(ls /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/ovmf/OVMF.fd /usr/share/edk2/ovmf/OVMF_CODE.fd /usr/share/qemu/OVMF.fd 2>/dev/null | head -n1)}
        [ -n "$OVMF" ] && [ -f "$OVMF" ] || { echo "boot-smoke: no OVMF firmware found (set OVMF=)" >&2; exit 2; }
        args+=(-drive "if=pflash,format=raw,readonly=on,file=$OVMF") ;;
    *) echo "boot-smoke: mode must be bios or uefi" >&2; exit 2 ;;
esac
: > "$W/serial.log"
qemu-system-x86_64 "${args[@]}" &
QPID=$!

ok=0
for _ in $(seq 1 $((TIMEOUT / 2))); do
    grep -q 'could not find the live medium\|Kernel panic' "$W/serial.log" && break
    if grep -qE '\[ +OK +\] boot' "$W/serial.log"; then ok=1; break; fi
    kill -0 "$QPID" 2>/dev/null || break
    sleep 2
done
cat "$W/serial.log"
if [ "$ok" = 1 ]; then echo "boot-smoke ($MODE): PASS (dinit reached the boot service)"; else echo "boot-smoke ($MODE): FAIL" >&2; exit 1; fi
