#!/bin/bash
# Validate the ports tree (ports/<category>/<name>/recipe). Used by CI (.github/workflows/ports-check.yml).
#
# Checks, for every recipe:
#   * the directory layout is ports/<category>/<name>/recipe, names use [A-Za-z0-9._+-]
#   * only known keys (url sha256 requires build configure_args), each at most once, plain key=value lines
#   * url (https/http/ftp, no whitespace) or requires (meta-package) is present
#   * sha256, when present, is 64 lowercase hex digits; recipes WITHOUT sha256 are reported as warnings
#     (the original starter recipes have none); --strict turns that into an error
#   * build is one of configure, cmake, meson (the types `get` supports)
#   * every requires atom is category/name and exists; there are no dependency cycles
# With --verify the sources are downloaded and the sha256 of every recipe that has one is compared.
#
# usage: tools/ports-check.sh [--strict] [--verify [ATOM...]] [PORTS_DIR]
set -u
STRICT=0 VERIFY=0 ATOMS=() PORTS=
while [ $# -gt 0 ]; do
    case "$1" in
        --strict) STRICT=1 ;;
        --verify) VERIFY=1 ;;
        -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
        *) if [ -d "$1" ]; then PORTS=$1; else ATOMS+=("$1"); fi ;;
    esac
    shift
done
PORTS=${PORTS:-$(cd "$(dirname "$0")/.." && pwd)/ports}
errors=0 warnings=0 count=0
err()  { echo "ERROR: $1" >&2; errors=$((errors + 1)); }
warn() { echo "warning: $1" >&2; warnings=$((warnings + 1)); }
# same parser as `get`: key = value, first match wins
val() { sed -n "s/^$2[[:space:]]*=[[:space:]]*//p" "$1" | head -n1 | sed 's/[[:space:]]*$//; s/^"\(.*\)"$/\1/'; }

declare -A REQ
for recipe in "$PORTS"/*/*/recipe; do
    [ -f "$recipe" ] || continue
    dir=${recipe%/recipe}; atom=${dir#"$PORTS"/}; count=$((count + 1))
    case "$atom" in */*/*|*[!A-Za-z0-9._+/-]*) err "$atom: bad atom name"; continue ;; esac
    declare -A seen=()
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in ''|'#'*) continue ;; esac
        key=${line%%=*}; key=${key%%[[:space:]]}
        case "$line" in *=*) ;; *) err "$atom: line is not key=value: $line"; continue ;; esac
        case "$key" in
            url|sha256|requires|build|configure_args) ;;
            *) err "$atom: unknown key '$key'"; continue ;;
        esac
        [ -z "${seen[$key]:-}" ] || err "$atom: duplicate key '$key'"
        seen[$key]=1
    done < "$recipe"
    unset seen
    url=$(val "$recipe" url); sha=$(val "$recipe" sha256); req=$(val "$recipe" requires); build=$(val "$recipe" build)
    if [ -n "$url" ]; then
        case "$url" in
            https://*|http://*|ftp://*) ;;
            *) err "$atom: url must be http(s) or ftp: $url" ;;
        esac
        case "$url" in *[[:space:]]*|*[\'\"\;\`\$\|\&]*) err "$atom: url contains unsafe characters" ;; esac
    elif [ -z "$req" ]; then
        err "$atom: neither url nor requires"
    fi
    if [ -n "$sha" ]; then
        [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || err "$atom: sha256 is not 64 lowercase hex digits"
        [ -n "$url" ] || err "$atom: sha256 without url"
    elif [ -n "$url" ]; then
        if [ "$STRICT" = 1 ]; then err "$atom: missing sha256"; else warn "$atom: missing sha256"; fi
    fi
    case "$build" in ''|configure|cmake|meson) ;; *) err "$atom: unsupported build type '$build'" ;; esac
    case "$req" in *[!A-Za-z0-9._+/\ -]*) err "$atom: invalid characters in requires" ;; esac
    REQ[$atom]=$req
done

# dependencies exist and are acyclic (depth-first search; state 1 = in progress, 2 = done)
declare -A state
visit() {
    local a=$1 r
    case "${state[$a]:-}" in 2) return 0 ;; 1) err "dependency cycle through $a"; return 1 ;; esac
    state[$a]=1
    for r in ${REQ[$a]}; do
        case "$r" in */*) ;; *) err "$a: requires '$r' is not a category/name atom"; continue ;; esac
        [ -f "$PORTS/$r/recipe" ] || { err "$a: requires unknown port '$r'"; continue; }
        visit "$r" || { state[$a]=2; return 1; }
    done
    state[$a]=2
}
for a in "${!REQ[@]}"; do visit "$a"; done

if [ "$VERIFY" = 1 ]; then
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    list=("${ATOMS[@]}")
    [ ${#list[@]} -gt 0 ] || list=("${!REQ[@]}")
    for a in "${list[@]}"; do
        sha=$(val "$PORTS/$a/recipe" sha256); url=$(val "$PORTS/$a/recipe" url)
        [ -n "$sha" ] && [ -n "$url" ] || continue
        if curl -fsSL --retry 2 -m 300 -o "$tmp/src" "$url"; then
            have=$(sha256sum "$tmp/src" | cut -d' ' -f1)
            [ "$have" = "$sha" ] || err "$a: sha256 mismatch (recipe $sha, downloaded $have)"
        else
            err "$a: cannot download $url"
        fi
    done
fi

echo "ports-check: $count recipes, $errors errors, $warnings warnings"
[ "$errors" = 0 ]
