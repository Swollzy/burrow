#!/bin/bash
# shellcheck disable=SC2034  # variables here are read inside check's eval strings
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
# Downloads shown in Burrow's window: progress every 10%, not a redrawn bar per line.
mkdir -p "$work/dx/dxmt-v9.99/x86_64-windows" && head -c 3000000 /dev/urandom > "$work/dx/dxmt-v9.99/x86_64-windows/d3d11.dll"
tar -czf "$work/dx.tar.gz" -C "$work/dx" dxmt-v9.99
BURROW_DXMT_VERSION=v9.99 BURROW_DXMT_URL="file://$work/dx.tar.gz" "$burrow" setup > "$work/dl.txt" 2>&1
check "download progress suits a log window" '[ -d "$BURROW_HOME/runtimes/dxmt-v9.99/x86_64-windows" ] && ! grep -q "#" "$work/dl.txt" && [ "$(grep -c "%" "$work/dl.txt")" -le 11 ]'
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

# Per-app settings reach the program's environment.
"$burrow" settings --app "fake app" env="BURROW_TEST_VAR=hello" cpu_cores=2 >/dev/null
"$burrow" launch "fake app" >/dev/null 2>&1
lastlog=$(ls -t "$BURROW_HOME"/logs/fake-app-*.log | head -1)
check "app env and cpu cores reach the program" 'grep -q "^BURROW_TEST_VAR=hello$" "$lastlog" && grep -q "^WINE_CPU_TOPOLOGY=2:0,1$" "$lastlog"'
check "app setting shows where it came from" '"$burrow" settings --app "fake app" --plain | grep -q "^cpu_cores	2	app	int	"'
check "bottle-only settings are refused per app" '! "$burrow" settings --app "fake app" retina on 2>/dev/null'
"$burrow" add "Outside" --bottle Games --exe "$work/fakeapp.exe" >/dev/null
check "a program outside the bottle is reached through Z:" 'grep -q "^target=Z:.*\\\\fakeapp.exe$" "$BURROW_HOME/library/outside.app.conf"'

"$burrow" add "Direct" --bottle Games --exe 'C:\Program Files\Fake App\Fake App.exe' --args "--hello" >/dev/null
rm -f "$ran"; "$burrow" launch Direct >/dev/null 2>&1
check "manual add + launch with args" 'tr -d "\000" < "$ran" | grep -q -- "--hello"'
"$burrow" add "Quoted" --bottle Games --exe 'C:\Program Files\Fake App\Fake App.exe' --args '-config "C:\My Games\x.ini" *' >/dev/null
rm -f "$ran"; (cd "$here" && "$burrow" launch Quoted >/dev/null 2>&1)
check "launch options keep quoted paths and don't glob" 'c=$(tr -d "\000" < "$ran" | grep "^cmd="); case "$c" in *"\"C:\\My Games\\x.ini\""*) ;; *) false ;; esac && case "$c" in *run-tests.sh*) false ;; esac'
"$burrow" remove Quoted >/dev/null

# A relative installer path still runs the installer (it starts from its own folder).
mkdir -p "$work/dl/sub"; cp "$work/fakeapp.exe" "$work/dl/sub/other-setup.exe"
rm -f "$BURROW_HOME/bottles/Games/prefix/drive_c/Program Files/Fake App/Fake App.exe"
(cd "$work/dl" && "$burrow" install sub/other-setup.exe --bottle Games >/dev/null 2>&1)
check "install with a relative path runs the installer" '[ -f "$BURROW_HOME/bottles/Games/prefix/drive_c/Program Files/Fake App/Fake App.exe" ]'

# Old logs of other apps whose names start the same way are left alone.
touch -t 202001010000 "$BURROW_HOME/logs/fake-app-x-20200101-000000.log"
for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21; do touch -t "2021010100$i" "$BURROW_HOME/logs/fake-app-20210101-0000$i.log"; done
"$burrow" launch "fake app" >/dev/null 2>&1
check "log cleanup keeps other apps' logs" '[ -f "$BURROW_HOME/logs/fake-app-x-20200101-000000.log" ] && [ "$(ls "$BURROW_HOME"/logs/fake-app-2*.log | wc -l)" -le 20 ]'

# Names that make the same id must not overwrite each other; a reinstall keeps app settings.
"$burrow" add "東方" --bottle Games --exe 'C:\a.exe' >/dev/null
"$burrow" add "ゼルダ" --bottle Games --exe 'C:\b.exe' >/dev/null
"$burrow" add "Doom" --bottle Games --exe 'C:\d.exe' >/dev/null
"$burrow" add "DOOM!" --bottle Games --exe 'C:\d2.exe' >/dev/null
check "non-Latin names each get their own entry" '"$burrow" apps --plain | grep -q "	東方	" && "$burrow" apps --plain | grep -q "	ゼルダ	"'
check "look-alike names each get their own entry" '[ "$("$burrow" apps --plain | cut -f2 | grep -ci "^doom!*$")" = 2 ]'
"$burrow" settings --app "DOOM!" cpu_cores=3 >/dev/null
"$burrow" add "DOOM!" --bottle Games --exe 'C:\d3.exe' >/dev/null
check "re-adding an app keeps its settings and takes the new target" 'f="$BURROW_HOME/library/$("$burrow" apps --plain | awk -F"\t" "\$2==\"DOOM!\"{print \$1}").app.conf"; grep -qx "cpu_cores=3" "$f" && grep -qxF "target=C:\\d3.exe" "$f"'
for n in "東方" "ゼルダ" "Doom" "DOOM!"; do "$burrow" remove "$n" >/dev/null; done
check "removing by name removes the right ones" '! "$burrow" apps --plain | grep -qiE "	(東方|ゼルダ|doom!?)	"'

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
st="$BURROW_HOME/bottles/Steam/prefix/drive_c/burrow-test"
check "webhelper wrapped" 'grep -aq BURROW-WEBHELPER-WRAPPER-1 "$sroot/bin/cef/cef.win64/steamwebhelper.exe"'
check "Valve helper kept as _real" '[ -f "$sroot/bin/cef/cef.win64/steamwebhelper_real.exe" ]'
check "steam started with -no-cef-sandbox -noverifyfiles" 'tr -d "\000" < "$st/steam.txt" | grep -q -- "-no-cef-sandbox -noverifyfiles"'
check "helper got CPU flags then Steam args" 'tr -d "\000" < "$st/helper.txt" | grep -q -- "--disable-gpu --single-process -lang=en_US --type=browser"'

# Run through a symlink, the way install.sh puts burrow on the PATH.
mkdir -p "$work/linkbin" && ln -s "$burrow" "$work/linkbin/burrow"
check "works through a symlink (finds its wrapper)" '"$work/linkbin/burrow" steam fix >/dev/null 2>&1'

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
# Two Steam games with the same name, a non-Latin name, and a name with escaped quotes.
for g in "2222221 Prey" "2222222 Prey" "2222223 原神" '2222224 The \"Quoted\" Game'; do
  printf '"AppState"\n{\n\t"appid"\t\t"%s"\n\t"name"\t\t"%s"\n}\n' "${g%% *}" "${g#* }" > "$sroot/steamapps/appmanifest_${g%% *}.acf"
done
"$burrow" steam sync >/dev/null; "$burrow" steam sync >/dev/null
check "steam sync keeps same-name games apart" '[ "$("$burrow" apps --plain | grep -c "	Prey	Steam	222222[12]$")" = 2 ]'
check "steam sync keeps non-Latin names" '"$burrow" apps --plain | grep -q "	原神	Steam	2222223$"'
check "steam names lose VDF escapes" '"$burrow" apps --plain | grep -qF "	The \"Quoted\" Game	Steam	2222224"'
rm -f "$sroot"/steamapps/appmanifest_222222[1-4].acf
mkdir -p "$BURROW_HOME/runtimes/dxmt-v0.80/x86_64-windows" "$sroot/steamapps/common/Schedule I"
head -c 2000000 /dev/zero > "$sroot/steamapps/common/Schedule I/game.bin"   # stands in for the DXMT download
check "status line" '"$burrow" status | grep -q "^setup=1 turbo=0 steam=1 clt=0 "'
check "status reports the hardware and macOS version" '"$burrow" status | grep -q " arm=0 rosetta=1 macos=0$"'
check "usage lists bottles, games and free space" 'out=$("$burrow" usage --plain); printf "%s" "$out" | grep -q "^DISK	bottle	Steam	" && printf "%s" "$out" | grep -q "^DISK	game	Schedule I	" && printf "%s" "$out" | grep -q "^FREE	[0-9]"'
"$burrow" run Games notepad >/dev/null 2>&1 &
for _ in 1 2 3 4 5 6 7 8 9 10; do "$burrow" usage --ram --plain | grep -qi "notepad.exe" && break; sleep 1; done
check "usage --ram finds a running program in its bottle" '"$burrow" usage --ram --plain | grep -qi "^PROC	Games	notepad.exe	[0-9]*	[0-9]"'
check "usage human output" '"$burrow" usage | grep -q "Memory (RAM)"'
"$burrow" kill Games >/dev/null 2>&1

# Settings, presets and the registry.
"$burrow" bottle new Tweak --preset apps >/dev/null 2>&1
ureg="$BURROW_HOME/bottles/Tweak/prefix/user.reg"
check "apps preset turns on Retina and Cmd as Ctrl" 'grep -q "^\"RetinaMode\"=\"y\"" "$ureg" && grep -q "^\"LeftCommandIsCtrl\"=\"y\"" "$ureg"'
"$burrow" settings Tweak windows_version=win7 dpi=144 virtual_desktop=1024x768 >/dev/null 2>&1
check "settings set the Windows version" 'grep -q "^\"Version\"=\"win7\"" "$ureg"'
check "settings set the DPI" 'grep -q "^\"LogPixels\"=dword:00000090" "$BURROW_HOME/bottles/Tweak/prefix/system.reg"'
check "virtual desktop on" 'grep -q "^\"Desktop\"=\"Burrow\"" "$ureg" && grep -q "^\"Burrow\"=\"1024x768\"" "$ureg"'
"$burrow" settings Tweak virtual_desktop off >/dev/null 2>&1
check "virtual desktop off" '! grep -q "^\"Desktop\"=\"Burrow\"" "$ureg"'
check "bad values are refused" '! "$burrow" settings Tweak dpi 9999 2>/dev/null && ! "$burrow" settings Tweak retina maybe 2>/dev/null && ! "$burrow" settings Tweak nonsense 1 2>/dev/null && ! "$burrow" settings Tweak env "1BAD" 2>/dev/null'
check "a refused change changes nothing" '! "$burrow" settings Tweak cpu_cores=4 dpi=1 2>/dev/null; [ "$("$burrow" settings Tweak cpu_cores)" = 0 ]'
check "settings --plain" '"$burrow" settings Tweak --plain | grep -q "^windows_version	win7	bottle	choice	"'
"$burrow" settings Tweak preset retro >/dev/null 2>&1
check "a preset replaces the settings" '[ "$("$burrow" settings Tweak windows_version)" = winxp64 ] && [ "$("$burrow" settings Tweak dpi)" = 96 ] && [ "$("$burrow" settings Tweak virtual_desktop)" = 1024x768 ]'
check "presets --plain" '[ "$("$burrow" presets --plain | wc -l)" -eq 5 ]'
check "bottle list --plain" '"$burrow" bottle list --plain | grep -q "^Tweak	compat	winxp64	retro	1024x768$"'

# Snapshots and copies.
echo keep > "$BURROW_HOME/bottles/Tweak/prefix/drive_c/marker.txt"
"$burrow" snapshot save Tweak "before" >/dev/null
snap=$("$burrow" snapshot list Tweak --plain | cut -f1 | head -1)
check "snapshot list --plain" '"$burrow" snapshot list Tweak --plain | grep -q "	before	"'
rm -f "$BURROW_HOME/bottles/Tweak/prefix/drive_c/marker.txt"
"$burrow" settings Tweak windows_version win11 >/dev/null 2>&1
"$burrow" snapshot restore Tweak "$snap" >/dev/null
check "snapshot restore brings files and settings back" '[ -f "$BURROW_HOME/bottles/Tweak/prefix/drive_c/marker.txt" ] && [ "$("$burrow" settings Tweak windows_version)" = winxp64 ]'
check "usage counts snapshots" '"$burrow" usage --plain | grep -q "^DISK	snapshot	Snapshots	"'
"$burrow" snapshot delete Tweak "$snap" >/dev/null
check "snapshot delete" '[ -z "$("$burrow" snapshot list Tweak --plain)" ]'
"$burrow" bottle clone Tweak Tweak2 >/dev/null
check "bottle clone copies files and settings" '[ -f "$BURROW_HOME/bottles/Tweak2/prefix/drive_c/marker.txt" ] && [ "$("$burrow" settings Tweak2 windows_version)" = winxp64 ]'

# Windows components, with a stand-in for winetricks.
cat > "$work/winetricks" <<'SH'
#!/bin/sh
echo "$WINEPREFIX $*" > "$WINEPREFIX/fake-winetricks.txt"
for v; do case "$v" in -*) ;; *) echo "$v" >> "$WINEPREFIX/winetricks.log" ;; esac; done
SH
chmod +x "$work/winetricks"
BURROW_WINETRICKS="$work/winetricks" "$burrow" components Tweak install vcrun2022 corefonts >/dev/null 2>&1
check "components run winetricks in the bottle" 'grep -q "Tweak/prefix --unattended vcrun2022 corefonts$" "$BURROW_HOME/bottles/Tweak/prefix/fake-winetricks.txt"'
check "components list marks what's installed" '"$burrow" components Tweak list --plain | grep -q "^vcrun2022	1	" && "$burrow" components Tweak list --plain | grep -q "^dotnet48	0	"'
check "component names are checked" '! BURROW_WINETRICKS="$work/winetricks" "$burrow" components Tweak install --evil 2>/dev/null'

# The Windows desktop window.
BURROW_FOREGROUND=0 "$burrow" desktop Games 800x600 >/dev/null 2>&1
for _ in 1 2 3 4 5 6 7 8 9 10; do ps -axww -o command= | grep -q "[d]esktop=Burrow,800x600" && break; sleep 1; done
check "desktop opens a Windows desktop window" 'ps -axww -o command= | grep -q "[d]esktop=Burrow,800x600"'
"$burrow" kill Games >/dev/null 2>&1

# Bad input fails fast instead of hanging or reaching outside Burrow's folders.
hung=""
for a in "bottle new Nope --preset" "install x.exe --bottle" "launch x --graphics" "settings --app"; do
  # shellcheck disable=SC2086  # $a is several words on purpose
  timeout 10 "$burrow" $a 2>&1 | grep -q "needs a value" || hung="$hung [$a]"
done
check "a flag without its value fails instead of hanging" '[ -z "$hung" ]'
check "bottle delete refuses paths" '! "$burrow" bottle delete ../library --yes 2>/dev/null && [ -d "$BURROW_HOME/library" ]'

# A leftover Steam PID file from a crash or restart doesn't stop Steam from opening properly.
sleep 60 & stale=$!
echo "$stale" > "$BURROW_HOME/bottles/Steam/.steam-running"
rm -f "$st/steam.txt"; "$burrow" steam >/dev/null 2>&1
check "a stale Steam PID file is ignored" 'tr -d "\000" < "$st/steam.txt" 2>/dev/null | grep -q -- "-noverifyfiles"'
kill "$stale" 2>/dev/null

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
mkdir -p "$BURROW_SHORTCUTS/Fake App.app/Contents"
"$burrow" bottle delete Games --yes >/dev/null
check "bottle delete removes its apps" '! "$burrow" apps | grep -q "Fake App" && [ ! -d "$BURROW_HOME/bottles/Games" ]'
check "bottle delete removes its apps' Mac shortcuts" '[ ! -d "$BURROW_SHORTCUTS/Fake App.app" ]'

# Cleanup after an update: what older versions left goes, everything of the user's stays.
for _ in $(seq 1 20); do "$burrow" usage --ram --plain | grep -q "^PROC" || break; sleep 1; done
h="$BURROW_HOME"
mkdir -p "$h/engines/wine-10.0/bin" "$h/engines/wine-11.18/bin" "$h/engines/wine-11.18-turbo/bin" \
  "$h/runtimes/dxmt-v0.70/x86_64-windows" "$h/runtimes/dxmt-v0.80/x86_64-windows" "$h/app.new" "$h/cache/turbo"
touch "$h/cache/wine-devel-10.0-osx64.tar.xz" "$h/cache/wine-devel-11.18-osx64.tar.xz" \
  "$h/cache/dxmt-v0.70-builtin.tar.gz" "$h/cache/dxmt-v0.80-builtin.tar.gz" "$h/runtimes/winetricks-20230212" \
  "$h/cache/half.part" "$h/logs/ancient-20200101-000000.log" "$h/logs/recent-20990101-000000.log"
touch -t 202001010000 "$h/app.new" "$h/cache/half.part" "$h/logs/ancient-20200101-000000.log"
(exit 0) & dead=$!; wait "$dead"
touch "$h/library/x.app.conf.tmp.$dead" "$h/bottles/Tweak/bottle.conf.tmp.$dead"
"$burrow" cleanup --dry-run >/dev/null
check "cleanup --dry-run changes nothing" '[ -d "$h/engines/wine-10.0" ] && [ -f "$h/cache/half.part" ]'
"$burrow" cleanup > "$work/cleanup.txt" 2>&1
check "cleanup removes old engines, downloads and half-finished files" '[ ! -e "$h/engines/wine-10.0" ] && [ ! -e "$h/runtimes/dxmt-v0.70" ] && [ ! -e "$h/runtimes/winetricks-20230212" ] && [ ! -e "$h/cache/wine-devel-10.0-osx64.tar.xz" ] && [ ! -e "$h/cache/dxmt-v0.70-builtin.tar.gz" ] && [ ! -e "$h/cache/turbo" ] && [ ! -e "$h/app.new" ] && [ ! -e "$h/cache/half.part" ] && [ ! -e "$h/library/x.app.conf.tmp.$dead" ] && [ ! -e "$h/bottles/Tweak/bottle.conf.tmp.$dead" ] && [ ! -e "$h/logs/ancient-20200101-000000.log" ]'
check "cleanup keeps current engines, downloads, recent logs and the user's things" '[ -d "$h/engines/wine-11.18" ] && [ -d "$h/engines/wine-11.18-turbo" ] && [ -d "$h/runtimes/dxmt-v0.80" ] && [ -f "$h/cache/wine-devel-11.18-osx64.tar.xz" ] && [ -f "$h/cache/dxmt-v0.80-builtin.tar.gz" ] && [ -f "$h/logs/recent-20990101-000000.log" ] && [ -d "$h/bottles/Tweak/prefix/drive_c" ] && [ -d "$h/bottles/Steam/prefix/drive_c" ] && [ -n "$(ls "$h/library")" ]'
check "cleanup says what it freed" 'grep -q "Freed .* Your bottles, games and settings" "$work/cleanup.txt"'
mkdir -p "$h/engines/wine-9.0"
check "cleanup --if-updated runs once per version" '[ "$(cat "$h/.burrow-version")" = "$("$burrow" version | cut -d" " -f2)" ] && "$burrow" cleanup --if-updated && [ -d "$h/engines/wine-9.0" ]'
"$burrow" run Tweak notepad >/dev/null 2>&1 &
for _ in 1 2 3 4 5 6 7 8 9 10; do "$burrow" usage --ram --plain | grep -qi "notepad.exe" && break; sleep 1; done
"$burrow" cleanup >/dev/null 2>&1
check "cleanup leaves engines alone while programs run" '[ -d "$h/engines/wine-9.0" ]'
"$burrow" kill Tweak >/dev/null 2>&1

# Without Apple Silicon, turbo (DXMT) is never used, even when it has been built.
ln -sf "$WINEBIN" "$h/engines/wine-11.18-turbo/bin/wine"
"$burrow" add T1 --bottle Tweak --exe 'C:\windows\notepad.exe' >/dev/null
BURROW_FOREGROUND=0 "$burrow" launch T1 >/dev/null 2>&1; sleep 2; "$burrow" kill Tweak >/dev/null 2>&1
lastlog=$(ls -t "$h"/logs/t1-*.log | head -1)
check "without Apple Silicon, auto never picks turbo" 'head -1 "$lastlog" | grep -q " on wine-11.18$"'
check "asking for turbo without Apple Silicon says why" '"$burrow" launch T1 --graphics turbo 2>&1 | grep -q "needs an Apple Silicon Mac"'
check "turbo build refuses without Apple Silicon" 'BURROW_TURBO_ANYWHERE=0 "$burrow" turbo 2>&1 | grep -qE "Mac itself|Apple Silicon"'
"$burrow" remove T1 >/dev/null
rm -rf "$h/engines/wine-11.18" "$h/engines/wine-11.18-turbo" "$h/engines/wine-9.0"

echo; echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
