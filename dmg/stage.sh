#!/bin/bash
# Lays Burrow out the way make-dmg.sh expects:
#
#   bash dmg/stage.sh <output-folder>
#
#   <output-folder>/Sources/BurrowApp.swift
#   <output-folder>/Resources/Info.plist        (app/Info.plist with the version filled in)
#   <output-folder>/Resources/burrow-cli/       the command-line tool, as install.sh copies it
#
# The window app copies burrow-cli into ~/Library/Application Support/Burrow/app on launch
# (BurrowModel.installBundledCLI), which is where install.sh would have put it.
# Keep this file plain ASCII and write variables as ${NAME}: macOS ships bash 3.2.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:?usage: stage.sh <output-folder>}"

VERSION="$(sed -n 's/^BURROW_VERSION="\(.*\)"$/\1/p' "${ROOT}/bin/burrow")"
[[ -n "${VERSION}" ]] || { echo "couldn't read BURROW_VERSION from bin/burrow" >&2; exit 1; }

# OUT is replaced, so only an empty folder or an earlier stage may be there.
if [[ -e "${OUT}" && -n "$(ls -A "${OUT}" 2>/dev/null)" && ! -f "${OUT}/Sources/BurrowApp.swift" ]]; then
    echo "${OUT} isn't empty; give stage.sh a new folder" >&2
    exit 1
fi
rm -rf "${OUT}"
mkdir -p "${OUT}/Sources" "${OUT}/Resources/burrow-cli"
cp "${ROOT}/app/BurrowApp.swift" "${OUT}/Sources/"
sed "s/__VERSION__/${VERSION}/g" "${ROOT}/app/Info.plist" > "${OUT}/Resources/Info.plist"
cp -R "${ROOT}/bin" "${ROOT}/engine" "${ROOT}/wrapper" "${ROOT}/app" "${OUT}/Resources/burrow-cli/"
cp "${ROOT}/README.md" "${ROOT}/NOTICE.md" "${ROOT}/LICENSE" "${OUT}/Resources/burrow-cli/"
chmod +x "${OUT}/Resources/burrow-cli/bin/burrow"
if [[ -f "${ROOT}/app/AppIcon.icns" ]]; then cp "${ROOT}/app/AppIcon.icns" "${OUT}/Resources/"; fi
echo "${VERSION}"
