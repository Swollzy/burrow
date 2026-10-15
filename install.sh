#!/bin/bash
# Installs Burrow for this Mac user. Run it from Terminal:
#     bash ~/Downloads/Burrow/install.sh
# (Typing "bash " and dragging this file into Terminal works too.)
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

# Let "burrow" work in new Terminal windows.
mkdir -p "$HOME/.local/bin"
ln -sf "$dest/bin/burrow" "$HOME/.local/bin/burrow"
marker="# added by Burrow"
for rc in "$HOME/.zprofile" "$HOME/.bash_profile"; do
  if [ -f "$rc" ] || [ "$rc" = "$HOME/.zprofile" ]; then
    grep -q "$marker" "$rc" 2>/dev/null || printf '\nexport PATH="$HOME/.local/bin:$PATH" %s\n' "$marker" >> "$rc"
  fi
done

"$dest/bin/burrow" app "$HOME/Applications/Burrow.app"
"$dest/bin/burrow" setup

echo
printf 'Build turbo graphics now? Most 3D games need it. It takes a few minutes. [Y/n] '
read -r answer || answer=y
case "$answer" in [nN]*) ;; *) "$dest/bin/burrow" turbo ;; esac

echo
printf 'Install and open Windows Steam now? [Y/n] '
read -r answer || answer=y
case "$answer" in [nN]*) ;; *) "$dest/bin/burrow" steam ;; esac

echo
echo "Done. Open Burrow from ~/Applications/Burrow.app (drag it to your Dock), or type: burrow help"
