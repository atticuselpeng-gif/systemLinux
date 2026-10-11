#!/bin/sh
# Package profiles (see profiles/README): publish them, and keep them out of the live ISO.
#   profiles.sh build OUTDIR   pack every profile found under $ROOTFS into OUTDIR/profile-NAME.tar.xz
#                              (+ .sha256 and .requires), for `get --profile NAME`
#   profiles.sh strip STAGE    remove every non-@keep profile's paths from a staged live image
# ROOTFS defaults to the repository's rootfs/.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
ROOTFS=${ROOTFS:-$REPO/rootfs}
PROFILES=$REPO/profiles
MODE=${1:-}; TARGET=${2:-}
case "$MODE" in build|strip) [ -n "$TARGET" ] ;; *) false ;; esac || { sed -n '2,7p' "$0" >&2; exit 2; }

# expand_paths DIR MANIFEST: print the existing paths (relative to DIR) that the manifest's globs match
expand_paths() {
    (
        cd "$1"
        grep -v '^[@#]' "$2" | grep -v '^[[:space:]]*$' | while IFS= read -r g; do
            # Handle globs properly - use find for glob expansion to handle spaces
            case "$g" in
                *[*?[]*)
                    # It's a glob pattern
                    find . -path "./$g" -prune -print 2>/dev/null | sed 's#^\./##'
                    ;;
                *)
                    # Exact path
                    if [ -e "$g" ] || [ -L "$g" ]; then
                        printf '%s\n' "$g"
                    fi
                    ;;
            esac
        done
    )
}

for m in "$PROFILES"/*.list; do
    name=$(basename "$m" .list)
    keep=0; grep -q '^@keep' "$m" && keep=1
    case "$MODE" in
    strip)
        [ "$keep" = 0 ] || continue
        expand_paths "$TARGET" "$m" | while read -r p; do rm -rf "${TARGET:?}/$p"; done
        echo "stripped profile $name from the live image"
        ;;
    build)
        mkdir -p "$TARGET"
        list=$(mktemp)
        expand_paths "$ROOTFS" "$m" > "$list"
        if [ ! -s "$list" ]; then echo "skipping profile $name: nothing in $ROOTFS matches" >&2; rm -f "$list"; continue; fi
        tar -C "$ROOTFS" -cJf "$TARGET/profile-$name.tar.xz" -T "$list"
        # Extract all @requires lines (supporting multiple dependencies)
        sed -n 's/^@requires[[:space:]]*//p' "$m" > "$TARGET/profile-$name.requires"
        ( cd "$TARGET" && sha256sum "profile-$name.tar.xz" > "profile-$name.tar.xz.sha256" )
        rm -f "$list"
        echo "built profile $name"
        ;;
    esac
done
