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

# Apple signing: once "Set Up Signing.command" has run, DMGs open on friends' Macs with no
# warning. Until then, offer it (it skips what's already done, so a no costs nothing later).
SIGNING_CONF="${HOME}/Library/Application Support/Swollzy/signing.conf"
if [[ ! -f "${SIGNING_CONF}" && -z "${DEVELOPER_ID:-}" && -t 0 ]]; then
    echo
    echo "Apple signing isn't set up on this Mac yet, so friends would have to click 'Open Anyway'."
    read -r -p "Set it up now? It's once, about 5 minutes, and needs your Apple Developer account. [Y/n] " ANSWER || ANSWER="n"
    case "${ANSWER}" in
        [nN]*) echo "Making an unsigned DMG. Double-click Set Up Signing.command any time to add signing." ;;
        *) bash "${HERE}/Set Up Signing.command" --inline || echo "Signing isn't set up, so this DMG is unsigned." ;;
    esac
fi

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
VERSION="$(bash "${HERE}/dmg/stage.sh" "${WORK}/Burrow")" || finish 1

printf '\n\033[1mBurrow %s\033[0m\n' "${VERSION}"
mkdir -p "${OUT}"
if bash "${HERE}/dmg/make-dmg.sh" "${WORK}/Burrow" "${OUT}"; then
    # Older Burrow DMGs in the folder are out of date now.
    for old in "${OUT}"/Burrow-*.dmg; do
        [[ -f "${old}" ]] || continue
        case "$(basename "${old}")" in "Burrow-${VERSION}.dmg"|"Burrow-${VERSION}-"*.dmg) ;; *) rm -f "${old}"; echo "  Removed the older ${old##*/}" ;; esac
    done
    open "${OUT}"
    echo
    echo "  Send friends the .dmg."
    finish 0
fi
echo
if [[ -f "${OUT}/Burrow-notarize.log" ]]; then
    echo "  Apple didn't notarize Burrow. Run this again, or send Burrow-notarize.log from ${OUT} to Claude."
else
    echo "  Didn't build. Send Burrow-build-error.log from ${OUT} to Claude."
fi
finish 1
