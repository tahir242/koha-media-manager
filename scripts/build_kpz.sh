#!/bin/sh
# Build MediaManager.kpz in the repository root (Linux/macOS).
# Self-contained POSIX sh, no Python: the archive is written by the standard `zip` tool, or by
# bsdtar when zip is not installed (macOS ships bsdtar as `tar`).
# Usage: scripts/build_kpz.sh [OutputName.kpz]
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(dirname -- "$here")
out=${1:-MediaManager.kpz}
case $out in
    */* | .* | '') echo "OutputName must be a .kpz filename within this repository." >&2; exit 1 ;;
    *.kpz) ;;
    *) echo "OutputName must be a .kpz filename within this repository." >&2; exit 1 ;;
esac

base=Koha/Plugin/Com/Library
# Strict allowlist: exactly these files, nothing else from the plugin directory.
files="MediaManager.pm MediaManager/Controller.pm MediaManager/Health.pm MediaManager/Security.pm MediaManager/Store.pm
MediaManager/breadcrumbs.tt MediaManager/configure.tt MediaManager/continue.tt MediaManager/error.tt MediaManager/layout.tt
MediaManager/openapi.json MediaManager/tool.tt"

fail() { echo "$*" >&2; echo "Build failed." >&2; exit 1; }

# The zip writer: Info-ZIP zip, else bsdtar (as `bsdtar`, or as `tar` on macOS/BSD).
if command -v zip >/dev/null 2>&1; then
    writer=zip
elif command -v bsdtar >/dev/null 2>&1; then
    writer=bsdtar
elif tar --version 2>/dev/null | grep -q bsdtar; then
    writer=tar
else
    fail "build_kpz.sh: needs the zip tool (e.g. apt install zip / dnf install zip) or bsdtar."
fi

# Refuse unexpected plugin files, so nothing is packaged or left out by accident.
for path in "$root/$base/MediaManager/"*.pm "$root/$base/MediaManager/"*.tt "$root/$base/MediaManager/"*.json; do
    [ -e "$path" ] || continue
    name=MediaManager/${path##*/}
    case " $(echo $files) " in *" $name "*) ;; *) fail "Unexpected plugin file: $name" ;; esac
done

work=$(mktemp -d "${TMPDIR:-/tmp}/mm-kpz.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM
mkdir -p "$work/tree/$base/MediaManager"

paths=
for name in $files; do
    [ -s "$root/$base/$name" ] || fail "Missing or empty required file: $name"
    cp "$root/$base/$name" "$work/tree/$base/$name"
    # Build time, NOT the source file time: Koha keeps the extracted file times, and Koha's
    # Template Toolkit cache only recompiles a template whose file is newer than its cached copy.
    touch "$work/tree/$base/$name"
    paths="$paths $base/$name"
done

# $paths holds space-free relative names; word splitting is intended.
case $writer in
    zip) (cd "$work/tree" && zip -q -X -9 "$work/build.zip" $paths) ;;
    *) (cd "$work/tree" && "$writer" --format zip -cf "$work/build.zip" $paths) ;;
esac || fail "Could not create the archive."

# Verify the layout (exactly the allowlisted entries) and every entry's checksum.
if command -v unzip >/dev/null 2>&1; then
    listing=$(unzip -Z1 "$work/build.zip") || fail "Archive verification failed."
    unzip -tqq "$work/build.zip" >/dev/null || fail "Archive verification failed."
else
    reader=$writer
    [ "$reader" = zip ] && fail "build_kpz.sh: needs unzip to verify the archive made by zip."
    listing=$("$reader" -tf "$work/build.zip") || fail "Archive verification failed."
    "$reader" -xOf "$work/build.zip" >/dev/null || fail "Archive verification failed."
fi
expected=$(for name in $files; do echo "$base/$name"; done | LC_ALL=C sort)
[ "$(echo "$listing" | LC_ALL=C sort)" = "$expected" ] || fail "Invalid archive layout."

mv -f "$work/build.zip" "$root/$out"
if command -v sha256sum >/dev/null 2>&1; then
    hash=$(sha256sum "$root/$out" | cut -d' ' -f1)
elif command -v shasum >/dev/null 2>&1; then
    hash=$(shasum -a 256 "$root/$out" | cut -d' ' -f1)
else
    hash=$(openssl dgst -sha256 "$root/$out" | sed 's/.*= //')
fi
echo "$out: SHA256 $hash"
