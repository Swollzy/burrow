#!/bin/bash
# Installs Burrow for this Mac user and opens the Burrow window. Run it from Terminal:
#     bash ~/Downloads/Burrow/install.sh
# (Typing "bash " and dragging this file into Terminal works too.)
# Everything after this (Wine, turbo graphics, Steam) is done from the Burrow window.
set -eu

src="$(cd "$(dirname "$0")" && pwd)"
home="${BURROW_HOME:-$HOME/Library/Application Support/Burrow}"
dest="$home/app"

[ "$(uname -s)" = Darwin ] || { echo "Burrow is for macOS." >&2; exit 1; }

echo "Installing Burrow into $dest"
mkdir -p "$home"
rm -rf "$dest.new"
mkdir -p "$dest.new"
cp -R "$src/bin" "$src/engine" "$src/wrapper" "$src/app" "$dest.new/"
cp "$src/README.md" "$src/NOTICE.md" "$dest.new/" 2>/dev/null || true
chmod +x "$dest.new/bin/burrow"
rm -rf "$dest"
mv "$dest.new" "$dest"
xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true

# Let "burrow" work in new Terminal windows too.
mkdir -p "$HOME/.local/bin"
ln -sf "$dest/bin/burrow" "$HOME/.local/bin/burrow"
marker="# added by Burrow"
for rc in "$HOME/.zprofile" "$HOME/.bash_profile"; do
  if [ -f "$rc" ] || [ "$rc" = "$HOME/.zprofile" ]; then
    grep -q "$marker" "$rc" 2>/dev/null || printf '\nexport PATH="$HOME/.local/bin:$PATH" %s\n' "$marker" >> "$rc"
  fi
done

# The Burrow window is built on this Mac with Apple's free Command Line Tools (turbo
# graphics needs them too). Without them Burrow falls back to a simple menu.
if ! xcode-select -p >/dev/null 2>&1; then
  echo
  echo "Burrow needs Apple's free Command Line Tools. Click Install in the window that opens."
  xcode-select --install 2>/dev/null || true
  echo "Waiting for the install to finish (this window carries on by itself)…"
  waited=0
  until xcode-select -p >/dev/null 2>&1; do
    sleep 10
    waited=$((waited + 10))
    if [ "$waited" -ge 3600 ]; then
      echo "Still not installed; continuing with the simple menu. Run 'burrow app' later for the window."
      break
    fi
  done
fi

"$dest/bin/burrow" app "$HOME/Applications/Burrow.app"

# An update: clear out what older versions left (old Wine engines and downloads, an older
# Burrow.app in /Applications). Bottles, games and settings stay.
"$dest/bin/burrow" cleanup --if-updated --keep-app "$HOME/Applications/Burrow.app" || true

echo
echo "Done. Burrow is in your Applications folder (~/Applications/Burrow.app); drag it to your Dock."
echo "Opening it now. Start on the Setup tab."
open "$HOME/Applications/Burrow.app"
