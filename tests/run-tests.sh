#!/bin/bash
# Exercises Burrow's logic with Linux Wine and small Windows test programs (tests/mocks).
# Nothing here can check the Mac parts (Rosetta, osacompile, Metal); those need a Mac.
#   tests/run-tests.sh            (needs wine and x86_64-w64-mingw32-gcc)
set -u
# Opening .lnk shortcuts goes through Wine's desktop, which needs a display.
if [ -z "${DISPLAY:-}" ] && [ -z "${BURROW_TEST_NOX:-}" ] && command -v xvfb-run >/dev/null; then
  exec env BURROW_TEST_NOX=1 xvfb-run -a "$0" "$@"
fi
here="$(cd "$(dirname "$0")" && pwd)"
burrow="$here/../bin/burrow"
work="$(mktemp -d)"
trap 'BURROW_HOME="$work/home" BURROW_WINE="$WINEBIN" "$burrow" kill >/dev/null 2>&1; rm -rf "$work"' EXIT
export BURROW_HOME="$work/home" BURROW_SHORTCUTS="$work/shortcuts" BURROW_FOREGROUND=1
WINEBIN="${WINEBIN:-$(command -v wine64 || command -v wine)}"
export BURROW_WINE="$WINEBIN"
pass=0; fail=0
check() { if eval "$2"; then echo "ok   $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }

for n in fakeapp fakesteam fakehelper; do
  x86_64-w64-mingw32-gcc -O1 -municode -o "$work/$n.exe" "$here/mocks/$n.c" -lole32 -luuid -lshell32 2>/dev/null || { echo "can't build $n"; exit 1; }
done
cp "$work/fakeapp.exe" "$work/fake-setup.exe"

"$burrow" setup >/dev/null 2>&1 || true   # downloads DXMT; fine if offline
"$burrow" bottle new Games >/dev/null
check "bottle created" '[ -d "$BURROW_HOME/bottles/Games/prefix/drive_c" ]'
check "bottle reports Windows 10" 'grep -q "\"Version\"=\"win10\"" "$BURROW_HOME/bottles/Games/prefix/user.reg"'

"$burrow" install "$work/fake-setup.exe" --bottle Games >/dev/null 2>&1
check "installer shortcut added to library" '"$burrow" apps | grep -q "Fake App"'
check "uninstall shortcut skipped" '! "$burrow" apps | grep -qi uninstall'
check "library entry points at the .lnk" 'grep -q "^target=C:.*Fake App.lnk$" "$BURROW_HOME/library/fake-app.app.conf"'

"$burrow" launch "fake app" >/dev/null 2>&1
# `start` hands a .lnk to the shell, which returns before the program has run.
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$BURROW_HOME/bottles/Games/prefix/drive_c/burrow-test/ran.txt" ] && break; sleep 1; done
ran="$BURROW_HOME/bottles/Games/prefix/drive_c/burrow-test/ran.txt"
check "launch runs the program" '[ -f "$ran" ]'
check "launch passes shortcut arguments" 'grep -aq -- "--from-shortcut" "$ran" 2>/dev/null || iconv -f utf-16le -t utf-8 "$ran" 2>/dev/null | grep -q -- "--from-shortcut"'
check "launch uses the program folder" 'tr -d "\000" < "$ran" | grep -q "cwd=C:\\\\Program Files\\\\Fake App"'

"$burrow" add "Direct" --bottle Games --exe 'C:\Program Files\Fake App\Fake App.exe' --args "--hello" >/dev/null
rm -f "$ran"; "$burrow" launch Direct >/dev/null 2>&1
check "manual add + launch with args" 'tr -d "\000" < "$ran" | grep -q -- "--hello"'

# Steam, with stand-ins for Steam.exe and steamwebhelper.exe.
"$burrow" bottle new Steam >/dev/null
sroot="$BURROW_HOME/bottles/Steam/prefix/drive_c/Program Files (x86)/Steam"
mkdir -p "$sroot/bin/cef/cef.win64" "$sroot/steamapps/common" "$work/lib2/steamapps"
cp "$work/fakesteam.exe" "$sroot/steam.exe"
cp "$work/fakehelper.exe" "$sroot/bin/cef/cef.win64/steamwebhelper.exe"
cat > "$sroot/steamapps/appmanifest_3164500.acf" <<'ACF'
"AppState"
{
	"appid"		"3164500"
	"name"		"Schedule I"
	"installdir"		"Schedule I"
}
ACF
cat > "$sroot/steamapps/appmanifest_228980.acf" <<'ACF'
"AppState"
{
	"appid"		"228980"
	"name"		"Steamworks Common Redistributables"
}
ACF
ln -s "$work/lib2" "$BURROW_HOME/bottles/Steam/prefix/dosdevices/d:"
cat > "$work/lib2/steamapps/appmanifest_1111111.acf" <<'ACF'
"AppState"
{
	"appid"		"1111111"
	"name"		"Data Center"
	"installdir"		"Data Center"
}
ACF
cat > "$sroot/steamapps/libraryfolders.vdf" <<'VDF'
"libraryfolders"
{
	"0"
	{
		"path"		"C:\\Program Files (x86)\\Steam"
	}
	"1"
	{
		"path"		"D:\\"
	}
}
VDF
check "steam games lists both libraries" '[ "$("$burrow" steam games | wc -l)" -eq 2 ] && "$burrow" steam games | grep -q "Data Center"'
check "steam games skips redistributables" '! "$burrow" steam games | grep -q 228980'

"$burrow" steam >/dev/null 2>&1
# shellcheck disable=SC2034  # used inside check's eval strings
st="$BURROW_HOME/bottles/Steam/prefix/drive_c/burrow-test"
check "webhelper wrapped" 'grep -aq BURROW-WEBHELPER-WRAPPER-1 "$sroot/bin/cef/cef.win64/steamwebhelper.exe"'
check "Valve helper kept as _real" '[ -f "$sroot/bin/cef/cef.win64/steamwebhelper_real.exe" ]'
check "steam started with -no-cef-sandbox" 'tr -d "\000" < "$st/steam.txt" | grep -q -- "-no-cef-sandbox"'
check "helper got CPU flags then Steam args" 'tr -d "\000" < "$st/helper.txt" | grep -q -- "--disable-gpu --single-process -lang=en_US --type=browser"'

# Steam "updates" the helper: the next launch must wrap it again.
cp "$work/fakehelper.exe" "$sroot/bin/cef/cef.win64/steamwebhelper.exe"
"$burrow" steam play schedule >/dev/null 2>&1
check "re-wrapped after a Steam update" 'grep -aq BURROW-WEBHELPER-WRAPPER-1 "$sroot/bin/cef/cef.win64/steamwebhelper.exe"'
check "steam play by name uses -applaunch" 'tr -d "\000" < "$st/steam.txt" | grep -q -- "-applaunch 3164500"'

"$burrow" steam sync >/dev/null
check "steam sync adds games to the library" '"$burrow" apps | grep -q "Schedule I" && "$burrow" apps | grep -q "Data Center"'
"$burrow" launch "Data Center" >/dev/null 2>&1
check "library launch of a Steam game goes through Steam" 'tr -d "\000" < "$st/steam.txt" | grep -q -- "-applaunch 1111111"'

check "apps --plain is id<TAB>name<TAB>bottle<TAB>appid" '"$burrow" apps --plain | grep -q "^schedule-i	Schedule I	Steam	3164500$"'
check "steam games --plain" '"$burrow" steam games --plain | grep -q "^1111111	Data Center$"'
mkdir -p "$BURROW_HOME/runtimes/dxmt-v0.80/x86_64-windows" "$sroot/steamapps/common/Schedule I"
head -c 2000000 /dev/zero > "$sroot/steamapps/common/Schedule I/game.bin"   # stands in for the DXMT download
check "status line" '"$burrow" status | grep -q "^setup=1 turbo=0 steam=1 clt=0 "'
check "usage lists bottles, games and free space" 'out=$("$burrow" usage --plain); printf "%s" "$out" | grep -q "^DISK	bottle	Steam	" && printf "%s" "$out" | grep -q "^DISK	game	Schedule I	" && printf "%s" "$out" | grep -q "^FREE	[0-9]"'
"$burrow" run Games notepad >/dev/null 2>&1 &
for _ in 1 2 3 4 5 6 7 8 9 10; do "$burrow" usage --ram --plain | grep -qi "notepad.exe" && break; sleep 1; done
check "usage --ram finds a running program in its bottle" '"$burrow" usage --ram --plain | grep -qi "^PROC	Games	notepad.exe	[0-9]*	[0-9]"'
check "usage human output" '"$burrow" usage | grep -q "Memory (RAM)"'
"$burrow" kill Games >/dev/null 2>&1

# Same program name in two bottles: both stay in the library.
"$burrow" bottle new Other >/dev/null
"$burrow" add "Direct" --bottle Other --exe 'C:\windows\notepad.exe' >/dev/null
check "same name in another bottle gets its own entry" '[ -f "$BURROW_HOME/library/direct.app.conf" ] && grep -qx "bottle=Other" "$BURROW_HOME/library/direct-2.app.conf"'
"$burrow" add "Direct" --bottle Other --exe 'C:\windows\regedit.exe' >/dev/null
check "re-adding in the same bottle replaces its entry" '[ ! -f "$BURROW_HOME/library/direct-3.app.conf" ] && grep -q "regedit" "$BURROW_HOME/library/direct-2.app.conf"'
"$burrow" bottle delete Other --yes >/dev/null
check "bottle delete keeps other bottles' apps" '[ ! -f "$BURROW_HOME/library/direct-2.app.conf" ] && [ -f "$BURROW_HOME/library/direct.app.conf" ]'
"$burrow" remove Direct >/dev/null
check "remove" '! "$burrow" apps | grep -q Direct'
"$burrow" bottle delete Games --yes >/dev/null
check "bottle delete removes its apps" '! "$burrow" apps | grep -q "Fake App" && [ ! -d "$BURROW_HOME/bottles/Games" ]'

echo; echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
