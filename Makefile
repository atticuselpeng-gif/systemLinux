.PHONY: iso check test-bios test-uefi test
iso:
	./build_iso.sh

# validate the ports tree and the dinit service files (no root, no ISO needed)
check:
	tools/ports-check.sh
	tools/dinit/check-services.sh

# boot the built ISO in QEMU (needs qemu, mtools; OVMF for uefi)
test-bios:
	tools/tests/boot-smoke.sh bios
test-uefi:
	tools/tests/boot-smoke.sh uefi
test: test-bios test-uefi
