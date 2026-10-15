# Packaging software for systemLinux

A package in systemLinux is a **port**: a folder in the ports tree with a small `recipe` file that says where the
source is and how to build it. `get` reads the recipe, builds the program from source, installs it into `/usr`
(configuration in `/etc`) and records every file, so `get remove` can undo it exactly. This guide shows how to write
one.

- [Quick start](#quick-start)
- [The port folder](#the-port-folder)
- [Recipe keys](#recipe-keys)
- [Build types](#build-types)
- [Dependencies](#dependencies-requires-and-check)
- [Patches, extra files and build scripts](#patches-extra-files-and-build-scripts)
- [Prebuilt upstream builds (-bin ports)](#prebuilt-upstream-builds-bin-ports)
- [dinit services](#dinit-services)
- [Testing a port](#testing-a-port)
- [Rules and conventions](#rules-and-conventions)
- [Submitting](#submitting)
- [Worked examples](#worked-examples)

## Quick start

Packaging GNU `hello`:

```sh
git clone https://github.com/tortr-rs/systemLinux && cd systemLinux
mkdir -p ports/text/hello
curl -LO https://ftpmirror.gnu.org/gnu/hello/hello-2.12.2.tar.gz
sha256sum hello-2.12.2.tar.gz
```

`ports/text/hello/recipe`:

```
version=2.12.2
description=The GNU Hello program
url=https://ftpmirror.gnu.org/gnu/hello/hello-2.12.2.tar.gz
sha256=<the sha256sum output>
build=configure
check=cmd:hello
```

Then check it and build it:

```sh
tools/ports-check.sh --verify text/hello   # layout, keys, dependencies, and the checksum
sudo ./get install hello                   # in a checkout, get uses ./ports
hello
sudo ./get remove hello
```

`get` uses the `ports/` folder next to the script when there is one, so you can test a checkout without touching
`/usr/ports`. `GET_PORTS=/path/to/ports` points it at any other tree.

## The port folder

```
ports/<category>/<name>/
    recipe              required: key=value lines
    patches/*.patch     optional: applied with patch -p1, in name order
    dinit/<service>     optional: dinit service files, installed to /etc/dinit.d
    files/<path>        optional: extra files copied into place relative to /
    build.sh            optional: the build itself, for build=script
```

**Categories**: put the port where people will look for it.

| category | for |
| --- | --- |
| `sys-app` | system tools, daemons, file systems, monitoring |
| `dev-apps` | developer tools, build systems, version control |
| `dev-libs` | libraries |
| `dev-python` | Python modules |
| `lang` | compilers and interpreters |
| `text` | editors, text and file tools, terminal file managers |
| `shells` | shells and shell plugins |
| `net` | network tools, servers, clients |
| `sec` | security and cryptography |
| `media` | audio, video, images |
| `x11` | X11 and Wayland: servers, libraries, window managers, desktop apps |
| `db` | databases |
| `games` | games |
| `sci` | science and math |

**Names** use `[A-Za-z0-9._+-]`, lower case, the upstream name (`ripgrep`, not `rg`). A name should be unique
across categories, so that `get install NAME` works without a category. Check first:

```sh
ls -d ports/*/NAME
```

## Recipe keys

The recipe is plain `key=value`, one per line, read with `sed` (never run as a shell script). Unknown keys are
an error in `tools/ports-check.sh`.

| key | required | meaning |
| --- | --- | --- |
| `version` | yes | upstream version, shown by `get list` and `get info` |
| `description` | yes | one line, searched by `get search` |
| `url` | yes (except meta-packages) | the source archive: `.tar.gz`, `.tgz`, `.tar.bz2`, `.tar.xz`, `.tar.zst` or `.tar` |
| `sha256` | yes | checksum of that archive; a mismatch stops the install |
| `build` | recommended | the build type (below); detected from the source when left out |
| `configure_args` | no | extra arguments for configure / cmake / meson / pip / cargo / go, or for build.sh |
| `make_args` | no | extra arguments for make (configure, autotools, make, perl); for go, the packages to build |
| `requires` | no | space-separated `category/name` atoms built first |
| `check` | no | how to tell whether the system already has it (see below) |
| `srcdir` | no | build in this subfolder of the source (for example one crate of a Rust workspace) |

A **meta-package** has no `url`, only `requires` (for example `x11/xfce4` pulls in the whole desktop).

**Where to get the URL**: prefer the release tarball upstream publishes (`releases/download/...`, ftp mirrors),
because it usually contains a ready `configure` script. GitHub tag archives
(`https://github.com/OWNER/REPO/archive/refs/tags/TAG.tar.gz`) work too; their checksums are stable. For GNU
software use `https://ftpmirror.gnu.org/gnu/...`. Always `https`.

## Build types

`get` builds every port with `DESTDIR` staging into an empty folder, then copies the files into `/` and records
them. The prefix is `/usr` (`$PREFIX` below), with libraries in `/usr/lib64`, configuration in `/etc` and state in
`/var`; get passes those directories to every build system that takes them (`--libdir`, `--sysconfdir`,
`--localstatedir` and the cmake/meson equivalents).

| build | what get runs |
| --- | --- |
| `configure` | `./configure --prefix=$PREFIX configure_args`, `make make_args`, `make install DESTDIR=...` |
| `autotools` | like `configure`, but first `./autogen.sh` or `autoreconf -fi` (for git archives with no `configure`) |
| `cmake` | `cmake -G Ninja -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF configure_args`, build, install |
| `meson` | `meson setup --prefix=$PREFIX --buildtype=release configure_args`, compile, install |
| `make` | `make PREFIX=$PREFIX prefix=$PREFIX configure_args make_args`, then the same with `install DESTDIR=...` |
| `python` | `pip install --no-deps --no-build-isolation --prefix=$PREFIX` (needs the build backend installed: add it to `requires`) |
| `cargo` | `cargo install --locked --path .` (add `lang/rust` to `requires`); in a workspace, the crate with a program named like the port, or `srcdir` |
| `go` | `go build -trimpath -o $PREFIX/bin/ make_args` (`make_args` defaults to `./...`; name the main package, e.g. `./cmd/gh`) |
| `perl` | `perl Makefile.PL PREFIX=$PREFIX INSTALLDIRS=site`, make, install |
| `fonts` | no build: every `.ttf`, `.otf`, `.ttc` and `.pcf.gz` goes to `$PREFIX/share/fonts/NAME`, then `fc-cache` |
| `script` | runs the port's `build.sh` (see below) |

Builds use all CPUs (`get -j N` to change). `get install -k NAME` keeps the build folder when something fails,
so you can look at it.

### Turning things off

Builds should not need anything the port does not list in `requires`. Turn off what a desktop distribution
would not want by default or what pulls in big dependencies:

- **documentation**: `-Ddocs=false`, `-Dman-pages=disabled`, `--disable-gtk-doc`, `--disable-html-docs`
- **tests and examples**: `-Dtests=false`, `-DBUILD_TESTING=OFF` (already passed for cmake)
- **introspection**: `-Dintrospection=disabled` (there is no gobject-introspection in the base)
- **systemd**: always off: `-Dsystemd=disabled`, `-Dlogind=disabled`, `SYSTEMD=0`. systemLinux has no systemd
  (see `docs/DINIT.md`); programs that need sd-bus can use `dev-libs/basu`.

Meson errors on options that do not exist, so copy option names from the project's `meson_options.txt` /
`meson.options` for the exact version you package.

## Dependencies: requires and check

`requires` lists what must be installed before building: libraries, build tools, and things needed at run time.
Use full atoms (`dev-libs/cairo`, not `cairo`). Build tools count too: meson ports need
`dev-apps/meson dev-apps/ninja`, cmake ports `dev-apps/cmake`, Rust ports `lang/rust`, Go ports `dev-apps/go`.

`get` skips a dependency the system already has:

1. installed with get earlier, or
2. the port's `check` says the system has it, or
3. without a `check`: the base system has a package of the same name (recorded in get's database as `base/NAME`).

`check` takes one of:

| check | means "already there" when |
| --- | --- |
| `pkgconfig:NAME` | `pkg-config --exists NAME` (use for libraries) |
| `cmd:NAME` | `NAME` is in `PATH` (use for programs) |
| `file:/PATH` | that file exists |
| `python:MODULE` | `python3 -c "import MODULE"` works |

**One set of files.** get records the base system's files too, so it knows who owns every file in `/usr` and
`/etc`. A port never overwrites a file another package owns (the install stops and names the owner), with one
exception: a port **replaces the base package with the same name** in place (its files take over the base
package's), for when the base copy lacks a feature. Such a port cannot be removed without `-f`, since the system
would lose that package.

**Always add a `check`**. It matters when the base has a package of the same name built without something you
need: the base `cairo` has no X11 support, so `dev-libs/cairo` says `check=pkgconfig:cairo-xcb` and gets rebuilt
for i3. It also catches name differences: the base calls the PCRE2 library `libpcre2`, so `dev-libs/pcre2` says
`check=pkgconfig:libpcre2-8`; without it get would try to build it and stop at the first file `base/libpcre2` owns.

To see what a library's pkg-config name is: `ls /usr/lib64/pkgconfig /usr/share/pkgconfig`, or look for the
`.pc.in` / `pkgconfig` lines in the source.

## Patches, extra files and build scripts

**patches/**: every `*.patch` is applied with `patch -p1` from the top of the source (after `srcdir`), in name
order. Number them: `01-fix-build-with-gcc15.patch`. Start each patch with a line or two saying why it is
needed, and send fixes upstream when you can. Make one with:

```sh
tar xf foo-1.0.tar.gz && cp -r foo-1.0 foo-1.0.orig
# edit foo-1.0/...
diff -ruN foo-1.0.orig foo-1.0 > ports/cat/foo/patches/01-what-it-fixes.patch
```

**files/**: copied into place relative to `/` after the build: `files/etc/greetd/config.toml` becomes
`/etc/greetd/config.toml`. Use it for default configuration, wrapper scripts and helpers. A configuration file the
user already has is never overwritten: the port's version is installed next to it as `FILE.get-new`.

**build.sh** (`build=script`): for software that none of the build types fit, for example a prebuilt toolchain
(`lang/rust`) or a project with an unusual build. It runs with `bash -e` in the source folder, and gets:

| variable | value |
| --- | --- |
| `DESTDIR` | the staging folder; install into `$DESTDIR$PREFIX/...` |
| `PREFIX` | `/usr` |
| `SYSCONFDIR`, `LOCALSTATEDIR` | `/etc`, `/var` |
| `JOBS` | parallel jobs to use |
| `PORTDIR` | the port's own folder |

`configure_args` are passed as its arguments. Keep it short and never write outside `$DESTDIR`.

`get` does not run install scripts after copying the files. Things that must happen at run time (creating a
system user, a cache folder) belong in the program's start-up: for a daemon, a small start script in
`files/usr/libexec/` that the dinit service runs (see `sys-app/greetd`).

## Prebuilt upstream builds (-bin ports)

systemLinux builds from source, with one exception for software whose build takes hours: a port named `NAME-bin` may
install **the project's own official prebuilt release** (Mozilla's Firefox tarball, the Rust toolchain, LLVM's
release binaries). Rules:

- only builds the upstream project publishes itself, never another distribution's packages;
- the `sha256` must match the checksum upstream publishes (for example Mozilla's `SHA256SUMS`);
- `build=script`; the `build.sh` unpacks into `$DESTDIR$PREFIX` (for example `$PREFIX/lib/firefox` plus a link in
  `$PREFIX/bin`), and turns off the program's own updater: updates come with the port;
- `requires` lists the libraries the binaries load (check with `ldd`);
- the description says it is the official build, and names the source port if there is one.

Examples: `x11/firefox-bin`, `lang/rust`.

## dinit services

systemLinux uses [dinit](https://github.com/davmac314/dinit) as init (`docs/DINIT.md`). A daemon port should ship
a service file in `dinit/`; it is installed to `/etc/dinit.d/NAME` and the user turns it on with
`dinitctl enable NAME`. Do not ship systemd units or OpenRC scripts (turn their installation off).

`ports/sys-app/seatd/dinit/seatd`:

```
# Seat management daemon: gives Wayland compositors (sway, ...) access to the GPU and input devices.
# Members of the "video" group may use it.
type = process
command = /usr/bin/seatd -g video
depends-on = early-filesystems
waits-for = udev-trigger
smooth-recovery = true
```

- `type = process`: dinit runs the program in the foreground and restarts it. Use the daemon's "do not fork"
  option (`--nofork`, `-f`, `-D`, `--foreground`). Prefer this type.
- `type = bgprocess` with `pid-file = /run/foo.pid`: only for daemons that cannot stay in the foreground.
- `type = scripted` with `command =` (and `stop-command =`): one-off setup, like loading settings.
- Dependencies use the base services: `early-filesystems` (mounts), `udev-trigger` (devices), `system-identity`
  (hostname), `dbus`, `network` (NetworkManager up). Use `depends-on` for hard needs and `waits-for` for
  "start after, but do not fail without it".
- Programs are in `/usr/bin`.
- Logs: add `logfile = /var/log/NAME.log` if the daemon writes to stdout.
- Start a comment block with what the service does and how to use it.

Test it on a running system: `dinitctl start NAME`, `dinitctl status NAME`, `dinitctl stop NAME`.

Per-user services (PipeWire, notification daemons) are started from the user's session instead: the window
manager's config (`exec pipewire` in sway), `~/.xinitrc`, or the program's own autostart. Say how in the
description or a comment in the shipped config.

## Testing a port

1. **Check the recipe:**

   ```sh
   tools/ports-check.sh                     # whole tree: layout, keys, requires, cycles
   tools/ports-check.sh --verify cat/name   # also downloads the source and checks sha256
   ```

2. **Build it on systemLinux**, ideally a fresh live system (in QEMU or on real hardware), so dependencies that
   your own machine happens to have do not hide missing `requires`:

   ```sh
   sudo ./get install -k cat/name
   ```

3. **Run it.** Start the program, not just `--version`; for a library, build something that uses it.
4. **Remove it** with `sudo ./get remove cat/name` and check nothing is left behind.
5. For a service: `dinitctl enable NAME`, reboot, `dinitctl status NAME`.

A quick way to test without booting: extract the release image and build inside it as a chroot.

```sh
bsdtar -xf systemLinux-*.iso live/rootfs.squashfs
unsquashfs -d img live/rootfs.squashfs
cp -r ports img/usr/ports && install -m755 get img/usr/local/bin/get
sudo mount --rbind /dev img/dev && sudo mount -t proc proc img/proc
sudo cp /etc/resolv.conf img/etc/resolv.conf
sudo chroot img /usr/local/bin/get install cat/name
```

## Rules and conventions

- **Checksums are required.** Compute them from a download you made yourself over https.
- **Latest stable release**, not a git snapshot, unless upstream has no releases.
- **No network during the build** except where the language tool requires it (cargo and go download their
  locked dependencies; meson may fetch declared subprojects).
- **Use the standard directories**: `$PREFIX` (`/usr`), `/etc` for configuration, `/etc/dinit.d` for services
  (through `dinit/`). Nothing goes to `/usr/local`, which is left to the user.
- **One program per port.** Split libraries that other ports need into their own port.
- **Complete `requires`.** If it links against it or runs it, list it.
- **Free software that may be redistributed.** No ports that download proprietary blobs without saying so in
  the description.
- **Updating a port**: change `version`, `url` and `sha256` together, re-test, and drop patches upstream has
  merged.

## Submitting

1. Fork https://github.com/tortr-rs/systemLinux and make a branch.
2. Add or update the port, run `tools/ports-check.sh`, and build it on systemLinux.
3. Open a pull request. Say what you tested (built, ran, services started) and on what (live ISO, installed
   system, chroot). CI runs `tools/ports-check.sh` on every change under `ports/`.

Bug in an existing port? Open an issue with the output of `get install -k NAME`.

## Worked examples

**Meson library** (`ports/dev-libs/basu/recipe`):

```
version=0.2.1
description=The sd-bus D-Bus library without systemd
url=https://git.sr.ht/~emersion/basu/archive/v0.2.1.tar.gz
sha256=43b327073d1ac7bc6cbc0d3dfff729348fc970dfff0551ad40e366332e990204
build=meson
configure_args=-Daudit=disabled -Dlibcap=disabled
requires=dev-apps/meson dev-apps/ninja
check=pkgconfig:basu
```

**Plain Makefile with arguments** (`ports/x11/dmenu/recipe`): suckless programs hard-code old X11 paths
(`/usr/X11R6`), so `make_args` points them at the right ones:

```
build=make
make_args=X11INC=/usr/include X11LIB=/usr/lib64 FREETYPEINC=/usr/include/freetype2
requires=x11/libx11 x11/libxft x11/libxinerama
check=cmd:dmenu
```

**Rust workspace** (`ports/sys-app/greetd/recipe`): `srcdir` picks the crate, and the port ships a dinit service,
a start script, a PAM file and a default config:

```
ports/sys-app/greetd/
    recipe                                  build=cargo, srcdir=greetd, requires=lang/rust dev-libs/pam
    dinit/greetd                            runs /usr/libexec/greetd-start
    files/usr/libexec/greetd-start          creates the greeter user, then execs greetd
    files/etc/greetd/config.toml            tuigreet on tty7
    files/etc/pam.d/greetd
```

**Go program with several commands** (`ports/dev-apps/gh/recipe`): `make_args=./cmd/gh` builds only `gh`.

**Prebuilt toolchain** (`ports/lang/rust`): `build=script` with a three-line `build.sh` running the official
installer into `$DESTDIR`.
