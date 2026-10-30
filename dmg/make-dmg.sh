#!/bin/bash
# Builds one Mac app from source and wraps it in a drag-to-Applications DMG.
#
#   bash make-dmg.sh <app-folder> <output-folder>
#
# <app-folder> is what stage.sh makes:
#   Sources/**/*.swift          compiled together into one program
#   Resources/Info.plist        becomes Contents/Info.plist (name, id and version come from it)
#   Resources/everything else   copied into Contents/Resources
#
# The app is built for Apple Silicon and Intel (one universal file) when the Command Line
# Tools can do both, and ad-hoc signed. Set DEVELOPER_ID (and NOTARY_PROFILE) to sign and
# notarize with a paid Apple Developer account instead; see README.md.
#
# Keep this file plain ASCII and write variables as ${NAME}: macOS ships bash 3.2.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "${1:?usage: make-dmg.sh <app-folder> <output-folder>}" && pwd)"
OUT_ARG="${2:?usage: make-dmg.sh <app-folder> <output-folder>}"
mkdir -p "${OUT_ARG}"
OUT="$(cd "${OUT_ARG}" && pwd)"

info() { printf '    %s\n' "$*"; }
warn() { printf '    \033[33m%s\033[0m\n' "$*"; }
die() { printf '    \033[31m%s\033[0m\n' "$*" >&2; exit 1; }

[[ "$(uname)" == "Darwin" ]] || die "DMGs are made on a Mac."
PLIST="${SRC}/Resources/Info.plist"
[[ -f "${PLIST}" ]] || die "No Resources/Info.plist in ${SRC}"
plist_get() { /usr/libexec/PlistBuddy -c "Print :$1" "${PLIST}"; }
NAME="$(plist_get CFBundleExecutable)"
VERSION="$(plist_get CFBundleShortVersionString)"
BUNDLE_ID="$(plist_get CFBundleIdentifier)"
MIN_OS="$(plist_get LSMinimumSystemVersion 2>/dev/null || echo 13.0)"

WORK="$(mktemp -d)"
DEVICE=""
cleanup() {
    [[ -n "${DEVICE}" ]] && hdiutil detach "${DEVICE}" -force >/dev/null 2>&1 || true
    rm -rf "${WORK}"
}
trap cleanup EXIT

# --- 1. Compile, once per CPU type -----------------------------------------------------
SOURCES=()
while IFS= read -r f; do SOURCES+=("${f}"); done < <(find "${SRC}/Sources" -name '*.swift' | LC_ALL=C sort)
(( ${#SOURCES[@]} > 0 )) || die "No Swift files in ${SRC}/Sources"

SDK="$(xcrun --show-sdk-path)"
NATIVE="$(uname -m)"
if [[ "${NATIVE}" == "arm64" ]]; then OTHER="x86_64"; else OTHER="arm64"; fi
LOG="${OUT}/${NAME}-build-error.log"
rm -f "${LOG}"

compile() { # arch -> 0 if it built
    xcrun swiftc -O -parse-as-library -swift-version 5 -module-name "${NAME}" \
        -target "$1-apple-macos${MIN_OS}" -sdk "${SDK}" \
        -o "${WORK}/${NAME}-$1" "${SOURCES[@]}" 2> "${WORK}/build-$1.log"
}
save_log() { # arch
    { echo "macOS $(sw_vers -productVersion) ${NATIVE}, building $1"; xcrun swiftc --version 2>&1; echo
      cat "${WORK}/build-$1.log"; } >> "${LOG}" 2>/dev/null || true
}

info "Compiling for ${NATIVE}"
if ! compile "${NATIVE}"; then
    save_log "${NATIVE}"
    grep -m 20 "error:" "${WORK}/build-${NATIVE}.log" >&2 || true
    die "${NAME} didn't compile. Details are in ${LOG}"
fi
ARCHS="${NATIVE}"
info "Compiling for ${OTHER}"
if compile "${OTHER}"; then
    ARCHS="${NATIVE} ${OTHER}"
else
    save_log "${OTHER}"
    warn "The ${OTHER} build failed, so this DMG only runs on ${NATIVE} Macs (details in ${LOG})."
fi

# --- 2. Put the app together -----------------------------------------------------------
APP="${WORK}/app/${NAME}.app"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
if [[ "${ARCHS}" == *" "* ]]; then
    lipo -create -output "${APP}/Contents/MacOS/${NAME}" "${WORK}/${NAME}-arm64" "${WORK}/${NAME}-x86_64"
else
    cp "${WORK}/${NAME}-${NATIVE}" "${APP}/Contents/MacOS/${NAME}"
fi
cp "${PLIST}" "${APP}/Contents/Info.plist"
for item in "${SRC}/Resources/"*; do
    [[ "$(basename "${item}")" == "Info.plist" ]] && continue
    cp -R "${item}" "${APP}/Contents/Resources/"
done
find "${APP}" -name .DS_Store -delete
xattr -cr "${APP}" 2>/dev/null || true

if [[ -n "${DEVELOPER_ID:-}" ]]; then
    info "Signing with ${DEVELOPER_ID}"
    codesign --force --options runtime --timestamp --sign "${DEVELOPER_ID}" \
        --identifier "${BUNDLE_ID}" "${APP}" || die "codesign failed."
else
    # Ad-hoc signature: required on Apple Silicon, and it seals the bundle.
    codesign --force --sign - --identifier "${BUNDLE_ID}" "${APP}" >/dev/null 2>&1 || die "codesign failed."
fi
codesign --verify --strict "${APP}" || die "The signature didn't verify."

# --- 3. Lay out the DMG window ---------------------------------------------------------
STAGE="${WORK}/stage"
mkdir -p "${STAGE}/.background"
cp -R "${APP}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"
README="${HERE}/readme/${NAME}.txt"
sed -e "s/{{NAME}}/${NAME}/g" -e "s/{{VERSION}}/${VERSION}/g" "${README}" > "${STAGE}/Read Me First.txt"
BG="${HERE}/art/${NAME}-bg.png"
BG2X="${BG%.png}@2x.png"
if [[ -f "${BG2X}" ]] && tiffutil -cathidpicheck "${BG}" "${BG2X}" -out "${STAGE}/.background/background.tiff" >/dev/null 2>&1; then
    BG_FILE="background.tiff"
else
    cp "${BG}" "${STAGE}/.background/background.png"
    BG_FILE="background.png"
fi

VOLNAME="${NAME} ${VERSION}"
SIZE_MB=$(( $(du -sm "${STAGE}" | cut -f1) + 20 ))
hdiutil create -quiet -volname "${VOLNAME}" -srcfolder "${STAGE}" -fs HFS+ \
    -format UDRW -size "${SIZE_MB}m" -ov "${WORK}/rw.dmg" || die "hdiutil create failed."
ATTACH="$(hdiutil attach -readwrite -noverify -noautoopen "${WORK}/rw.dmg")" || die "hdiutil attach failed."
DEVICE="$(printf '%s\n' "${ATTACH}" | grep '/Volumes/' | head -1 | awk '{print $1}')"
MOUNT="$(printf '%s\n' "${ATTACH}" | grep -o '/Volumes/.*' | head -1)"
DISK="$(basename "${MOUNT}")"

# Finder writes the icon positions and background into the DMG's .DS_Store. The first
# time, macOS asks whether Terminal may control Finder: click OK. If it's refused the
# DMG still works, it just opens as a plain window.
if ! osascript >/dev/null 2>&1 <<APPLESCRIPT
with timeout of 60 seconds
    tell application "Finder"
        tell disk "${DISK}"
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set the bounds of container window to {200, 120, 840, 548}
            set opts to the icon view options of container window
            set arrangement of opts to not arranged
            set icon size of opts to 96
            set text size of opts to 13
            set background picture of opts to file ".background:${BG_FILE}"
            set position of item "${NAME}.app" of container window to {170, 165}
            set position of item "Applications" of container window to {470, 165}
            set position of item "Read Me First.txt" of container window to {320, 300}
            close
            open
            update without registering applications
            delay 2
            close
        end tell
    end tell
end timeout
APPLESCRIPT
then
    warn "Couldn't arrange the DMG window (Terminal needs permission to control Finder)."
    warn "The DMG still works. To fix: System Settings > Privacy & Security > Automation > Terminal > Finder."
fi
sync
sleep 1
hdiutil detach "${DEVICE}" -quiet || { sleep 3; hdiutil detach "${DEVICE}" -force -quiet; }
DEVICE=""

# --- 4. Compress (and optionally notarize) ---------------------------------------------
case "${ARCHS}" in
    *" "*) SUFFIX="" ;;
    arm64) SUFFIX="-AppleSilicon" ;;
    *) SUFFIX="-Intel" ;;
esac
DMG="${OUT}/${NAME}-${VERSION}${SUFFIX}.dmg"
rm -f "${DMG}"
hdiutil convert -quiet "${WORK}/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "${DMG}" \
    || die "hdiutil convert failed."

if [[ -n "${DEVELOPER_ID:-}" ]]; then
    codesign --force --timestamp --sign "${DEVELOPER_ID}" "${DMG}" || die "Signing the DMG failed."
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        info "Sending to Apple for notarizing (a few minutes)"
        xcrun notarytool submit "${DMG}" --keychain-profile "${NOTARY_PROFILE}" --wait || die "Notarizing failed."
        xcrun stapler staple "${DMG}" || die "Stapling failed."
    fi
fi

info "Made ${DMG} ($(du -h "${DMG}" | cut -f1 | tr -d ' '), ${ARCHS// / + })"
