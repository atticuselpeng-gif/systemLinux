# Mozilla's prebuilt Firefox runs on any glibc system: unpack it to $PREFIX/lib/firefox and add the launcher,
# desktop entry and icons. Updates come with the port (Firefox's own updater is turned off).
mkdir -p "$DESTDIR$PREFIX/lib/firefox" "$DESTDIR$PREFIX/bin"
cp -a . "$DESTDIR$PREFIX/lib/firefox/"
ln -s ../lib/firefox/firefox "$DESTDIR$PREFIX/bin/firefox"
mkdir -p "$DESTDIR$PREFIX/lib/firefox/distribution"
cat > "$DESTDIR$PREFIX/lib/firefox/distribution/policies.json" <<'JSON'
{ "policies": { "DisableAppUpdate": true } }
JSON
for s in 16 32 48 64 128; do
    [ -f browser/chrome/icons/default/default$s.png ] || continue
    install -Dm644 browser/chrome/icons/default/default$s.png "$DESTDIR$PREFIX/share/icons/hicolor/${s}x$s/apps/firefox.png"
done
install -Dm644 /dev/stdin "$DESTDIR$PREFIX/share/applications/firefox.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Firefox
GenericName=Web Browser
Exec=firefox %u
Icon=firefox
Terminal=false
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupWMClass=firefox
DESKTOP
