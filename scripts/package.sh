#!/bin/bash
# Makes dist/Burrow-<version>.zip: a "Burrow" folder with everything install.sh needs.
#   scripts/package.sh
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
version=$(sed -n 's/^BURROW_VERSION="\(.*\)"$/\1/p' "$root/bin/burrow")
[ -n "$version" ] || { echo "couldn't read BURROW_VERSION from bin/burrow" >&2; exit 1; }
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/Burrow" "$root/dist"
cp -R "$root/bin" "$root/app" "$root/engine" "$root/wrapper" "$stage/Burrow/"
cp "$root/install.sh" "$root/README.md" "$root/NOTICE.md" "$root/LICENSE" "$stage/Burrow/"
chmod +x "$stage/Burrow/bin/burrow" "$stage/Burrow/install.sh"
out="$root/dist/Burrow-$version.zip"
rm -f "$out"
(cd "$stage" && zip -qr -X "$out" Burrow)
echo "$out"
