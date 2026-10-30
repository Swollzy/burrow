#!/bin/bash
# Double-click this on your Mac to turn Burrow into a DMG that friends install by dragging
# to Applications (no Terminal for them). The DMG lands in a "DMGs" folder on your Desktop.
#
# If macOS says it can't open this file: System Settings > Privacy & Security, scroll
# down, click "Open Anyway". Or in Terminal type "bash " and drag this file in.
#
# Keep this file plain ASCII and write variables as ${NAME}: macOS ships bash 3.2.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${HOME}/Desktop/DMGs"

finish() {
    echo
    if [[ -t 0 ]]; then read -r -p "Press Return to close this window. " _ || true; fi
    exit "$1"
}

[[ "$(uname)" == "Darwin" ]] || { echo "This runs on a Mac."; finish 1; }

# Apple's free Command Line Tools provide the Swift compiler.
have_tools() { xcode-select -p >/dev/null 2>&1 && xcrun --find swiftc >/dev/null 2>&1; }
if ! have_tools; then
    echo "Building needs Apple's free Command Line Tools (one time, about 5 minutes)."
    echo "A window will pop up: click Install. This waits and carries on by itself."
    xcode-select --install >/dev/null 2>&1 || true
    for _ in $(seq 1 360); do
        have_tools && break
        sleep 5
    done
    have_tools || { echo "The Command Line Tools still aren't installed. Install them, then run this again."; finish 1; }
fi

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
VERSION="$(bash "${HERE}/dmg/stage.sh" "${WORK}/Burrow")" || finish 1

printf '\n\033[1mBurrow %s\033[0m\n' "${VERSION}"
mkdir -p "${OUT}"
if bash "${HERE}/dmg/make-dmg.sh" "${WORK}/Burrow" "${OUT}"; then
    open "${OUT}"
    echo
    echo "  Send friends the .dmg. It has a 'Read Me First' with the one-time"
    echo "  'Open Anyway' step macOS asks for on apps that aren't from the App Store."
    finish 0
fi
echo
echo "  Didn't build. Send Burrow-build-error.log from ${OUT} to Claude."
finish 1
