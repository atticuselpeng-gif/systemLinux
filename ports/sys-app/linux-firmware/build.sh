# upstream's own installer: copies every file listed in WHENCE (and its symlinks) to the firmware directory.
# zstd-compressed (a quarter of the size); the kernel (Ubuntu's, CONFIG_FW_LOADER_COMPRESS_ZSTD) loads .zst firmware itself.
./copy-firmware.sh --zstd "$DESTDIR$PREFIX/lib/firmware"
install -m644 WHENCE "$DESTDIR$PREFIX/lib/firmware/WHENCE"
