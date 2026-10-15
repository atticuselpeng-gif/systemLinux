# The official prebuilt toolchain (building rustc from source takes hours): rustc, cargo and the standard library.
./install.sh --prefix="$PREFIX" --destdir="$DESTDIR" --disable-ldconfig \
    --components=rustc,cargo,rust-std-x86_64-unknown-linux-gnu
# install.sh's bookkeeping; get keeps its own file list
rm -f "$DESTDIR$PREFIX"/lib/rustlib/{install.log,uninstall.sh,manifest-*,components,rust-installer-version}
