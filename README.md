# Burrow

[![CI](https://github.com/Swollzy/burrow/actions/workflows/ci.yml/badge.svg)](https://github.com/Swollzy/burrow/actions/workflows/ci.yml)

Run Windows programs and **Windows Steam** on a Mac, the way CrossOver does: each program
lives in its own "bottle" (a private Windows folder), and you open them from Burrow's window
or from Mac shortcuts in your Dock.

> **Status: early.** The command-line tool is tested against Linux Wine, CI compiles the
> Mac window on every push, and Kyle has tested Burrow on a Mac with a couple of Windows games. Expect
> rough edges, and send the log from `~/Library/Application Support/Burrow/logs` when
> something fails.

Burrow is a launcher. The heavy lifting is done by free open source projects that it
downloads from their own sites during setup:

| Layer | Project | What it does |
|---|---|---|
| Windows itself | [Wine](https://www.winehq.org) 11.18, [Gcenx's macOS build](https://github.com/Gcenx/macOS_Wine_builds) | Pretends to be Windows so programs run |
| 3D graphics | [DXMT](https://github.com/3Shain/dxmt) v0.80 | Turns Direct3D 10/11 (what most Steam games use) into Apple's Metal |
| Older graphics | wined3d (part of Wine) | Direct3D 9 and older, through OpenGL |
| Intel code | Rosetta 2 (Apple) | Runs Windows' Intel code on Apple Silicon |

## Install (on the Mac)

1. Download `Burrow-<version>.zip` from the
   [latest release](https://github.com/Swollzy/burrow/releases/latest) (or **Code → Download
   ZIP** on this page) and unzip it in Downloads.
2. Open **Terminal**, type `bash ` (with a space), drag `install.sh` from the Burrow
   folder into the window, and press Return. This is the only Terminal step.
3. If Apple's free Command Line Tools aren't installed, a macOS window asks to install
   them; click Install and the script waits. They're needed to build the Burrow window
   (and turbo graphics).
4. The **Burrow** window opens (it lives in `~/Applications`; drag it to your Dock) and sets
   itself up: the first launch downloads Wine and DXMT on its own. For 3D games, finish the
   **Setup** tab: install Homebrew (opens in Terminal because it asks for your password) and
   build turbo graphics.
5. Install Windows programs inside Burrow: drop an installer (`.exe` or `.msi`) on the
   window, press ⌘O, or right-click it in Finder and choose **Open With > Burrow**. Burrow
   asks which bottle it goes in and which preset to use, then runs it.
6. For Steam games, install Windows Steam (Steam or Setup tab), sign in and install your
   games, press "Add Games to Library", then play them from **Library**.

The window has five tabs:

- **Library**: your programs and Steam games as cards with a Play button. The `…` menu
  makes a Dock shortcut, plays with compatible (slower, older) graphics, opens the
  program's own settings or its bottle's, or removes it.
- **Bottles**: each Windows install, like a lightweight VM. Open one as a whole Windows
  desktop in a window, change its settings or preset, take and restore snapshots, install
  Windows components, run a program once, duplicate it, or delete it.
- **Steam**: install or open Windows Steam, list installed games, play one.
- **Usage**: disk space for each bottle, each Steam game, Wine and downloads, plus free
  space on your Mac (orange under 20 GB); and live memory (RAM) for every running Windows
  program, grouped by bottle, with Quit buttons.
- **Setup**: each step with a check mark, plus "Check Everything" and the logs folder.

**Burrow > Settings** (⌘,) turns notifications on or off and has **Uninstall Burrow…**.

- **Notifications**: when Wine setup, the turbo build, an install or another long job finishes
  or stops with an error while you're in another app, Burrow says so in Notification Center
  (macOS asks once, the first time a job starts). Clicking an error opens its details.
- **Permissions**: Windows programs see your Documents, Desktop and Downloads folders as their
  own, so macOS asks before Burrow uses them, saying why. A signed Burrow keeps those answers
  across updates.

## Share it as a DMG (no Terminal for friends)

On your Mac, download this repo (**Code → Download ZIP**, or `git clone`) and double-click
**Make DMG.command**. It compiles the Burrow window for Apple Silicon and Intel, puts the
command-line tool inside the app, signs it and writes `~/Desktop/DMGs/Burrow-<version>.dmg`:
a window with Burrow, an arrow, the Applications folder and a "Read Me First".

- If macOS won't open the `.command`: System Settings > Privacy & Security > **Open Anyway**,
  or in Terminal type `bash ` and drag the file in.
- The first time, macOS asks whether Terminal may control Finder. Click **OK**: that lays out
  the DMG window. Saying no still makes a working, plain-looking DMG.
- With the paid Apple Developer account, double-click **Set Up Signing.command** once (Make
  DMG also offers it). It makes the Developer ID Application certificate if the keychain has
  none (it writes a request file to the Desktop and opens Apple's page: pick **Developer ID
  Application**, upload the file, click Download), saves the notary login (Apple ID plus an
  app-specific password from account.apple.com) in the keychain as notarytool profile
  `Swollzy`, and writes `~/Library/Application Support/Swollzy/signing.conf` (no passwords).
  From then on each DMG is signed with the hardened runtime, notarized by Apple and stapled,
  and friends just drag and open it. If Apple says no, the DMG is deleted and the reason is in
  `~/Desktop/DMGs/Burrow-notarize.log`. One setup covers Wallflower, Swivel and Molt too: they
  share `dmg/signing.sh`.
- Without that setup the app is ad-hoc signed, and friends do macOS's one-time **Open Anyway**
  step (the Read Me walks through it).
- On first launch Burrow copies its tool to `~/Library/Application Support/Burrow/app`, the
  same place `install.sh` uses.
- Build errors go to `~/Desktop/DMGs/Burrow-build-error.log`. A new build removes the older
  `Burrow-*.dmg` files in that folder.

## Updating

Install the new version the same way (the DMG, or `install.sh`). The first time it runs,
Burrow cleans up what older versions left behind: Wine engines and DXMT versions it no longer
uses, their downloads and turbo build files, half-finished downloads, logs older than 30 days,
and an older copy of Burrow.app in the other Applications folder. Your bottles, games,
snapshots, library, settings and shortcuts stay. Old Wine engines wait while Windows programs
are running. Run it yourself with `burrow cleanup` (`--dry-run` lists what it would remove) or
**Clean Up Old Files** on the Setup tab.

## Uninstalling

**Burrow > Settings > Uninstall Burrow…**, or `burrow uninstall` in Terminal (`--dry-run` lists
what it would remove). It removes Wine, DXMT and winetricks, the downloads and turbo build
files, logs, the `burrow` command, Dock shortcuts, the window's settings, the permissions macOS
gave Burrow, and Burrow.app (to the Trash). Your bottles hold your installed games and their
saves, so they stay, with the library and snapshots: installing Burrow again brings them back.
Tick **Also delete my games and bottles** (asked twice), or add `--everything`, to delete those
too. Windows programs have to be closed first.

## Bottles: lightweight Windows VMs

A bottle is a private Windows install: its own C: drive, registry, settings and programs.
It isn't a real virtual machine (no Windows licence, no emulated hardware, nothing to boot),
so it opens in a second or two and runs programs at close to native speed, but each one is
kept apart like a VM. Use one bottle per program, or group programs that need each other.

**Presets** set a bottle up for a kind of program in one go (`burrow presets`):

| Preset | For | What it sets |
|---|---|---|
| `gaming` | Steam and modern 3D games (the Steam bottle uses it) | turbo graphics, Windows 10 |
| `apps` | Office, creative and other desktop apps | Retina, 200% scale, Cmd-C/Cmd-V as Ctrl |
| `legacy` | Windows 7-era games and programs | OpenGL graphics, Windows 7, 8 CPU cores |
| `retro` | Windows XP-era games | Windows XP, OpenGL, 2 cores, 1024x768 desktop window |
| `desktop` | Using Windows like a VM | everything in one 1600x1000 Windows desktop window |

**Settings** fine-tune a bottle, and some can be set for just one program in it
(`burrow settings --list` describes them all):

| Setting | Bottle | App | Values |
|---|---|---|---|
| `graphics` | ✓ | ✓ | auto, turbo (DXMT/Metal), compat (OpenGL) |
| `windows_version` | ✓ | | win11, win10, win81, win8, win7, vista, winxp64 |
| `virtual_desktop` | ✓ | | off, or a size like 1920x1080: the whole bottle in one window |
| `retina` | ✓ | | on/off: full Retina resolution |
| `dpi` | ✓ | | 96 (100%), 144 (150%), 192 (200%)… |
| `option_as_alt` | ✓ | | on/off |
| `command_as_ctrl` | ✓ | | on/off: Cmd-C/Cmd-V work in Windows apps |
| `fullscreen_capture` | ✓ | | on/off: fullscreen takes over the display |
| `msync` | ✓ | ✓ | on/off: fast thread syncing (turn off if a program hangs) |
| `cpu_cores` | ✓ | ✓ | 0 (all) or a limit, for old games that crash with many cores |
| `hud` | ✓ | ✓ | on/off: Metal frame-rate HUD |
| `wine_debug` | ✓ | ✓ | off, errors, verbose: how much goes in the logs |
| `dll_overrides` | ✓ | ✓ | Wine DLL overrides, e.g. `d3dx9_43=n,b` |
| `env` | ✓ | ✓ | extra environment variables, e.g. `DXMT_LOG_LEVEL=info;FOO=1` |
| `args` | | ✓ | launch options for the program |

```
burrow settings Games                        show a bottle's settings
burrow settings Games windows_version win7   change one
burrow settings Games retina=on dpi=192      change several
burrow settings Games dpi default            back to the default
burrow settings Games preset retro           switch preset
burrow settings --app "Old Game" cpu_cores=2 just for one program
```

**Snapshots** save a whole bottle so you can roll back after a bad mod, update or setting.
On a Mac they're APFS clones: they take seconds and almost no space until the bottle
changes. **Duplicating** a bottle works the same way, so you can try something risky on a
copy.

**Windows components** that Wine doesn't include, like the Visual C++ runtimes, .NET 4.8,
DirectX 9 helpers or Microsoft's fonts, install with
[winetricks](https://github.com/Winetricks/winetricks) (downloaded on first use; needs
`cabextract`, which Burrow installs with Homebrew).

**The Windows desktop** (`burrow desktop <bottle>`, or the button on the Bottles tab) opens
the bottle as a full Windows desktop in one Mac window with File Explorer open, the closest
thing to a VM window. Setting `virtual_desktop` makes every program in that bottle open
inside the same window. Both are tested with Linux Wine but not yet on a Mac; if the
window doesn't appear there, turn `virtual_desktop` off again.

Burrow needs macOS 11 or newer (the window needs macOS 13); turbo graphics needs an Apple
Silicon Mac and DXMT works best on macOS 15 Sequoia or newer. Leave about 20 GB free for Wine
and the bottles, plus your games. If the window can't be built, Burrow falls back to a
simple pick-from-a-list menu and saves the reason in `logs/app-build.log`.

## Commands

```
burrow setup                   download Wine and DXMT (once)
burrow turbo                   build fast Metal graphics for 3D games (once)
burrow steam                   install (first time) and open Windows Steam
burrow steam games             list installed Steam games
burrow steam play "Schedule I" start a Steam game
burrow steam sync              put your Steam games in the library
burrow install <setup.exe|url> install any Windows program into its own bottle
                               (--bottle NAME to choose one, --preset apps to set it up)
burrow apps                    list your library
burrow add NAME --bottle B --exe /path/to/program.exe   add a portable program
burrow launch <app>            start a program (--graphics turbo|compat to override)
burrow shortcut <app>          make a Mac app for it in ~/Applications/Burrow
burrow usage                   disk space per bottle and game, RAM of running programs
burrow usage --ram             just the memory of running programs
burrow doctor                  check everything
burrow cleanup [--dry-run]     remove files older versions left behind (bottles stay)
burrow uninstall [--everything] remove Burrow; bottles (games, saves) stay unless --everything
burrow kill                    force-quit Windows programs

burrow bottle new NAME --preset apps    a new bottle (also: list, clone, delete)
burrow desktop <bottle> [1600x1000]     the bottle as one Windows desktop window
burrow settings <bottle> [key value]    compatibility settings; --app <app> for one program
burrow presets                          the ready-made settings
burrow snapshot save <bottle> "label"   save a bottle (also: list, restore, delete)
burrow components <bottle> install vcrun2022 corefonts   Windows components
burrow winecfg <bottle>                 Wine's own settings window
```

The Burrow window runs these same commands, so Terminal and the window always agree.
Everything lives in `~/Library/Application Support/Burrow` (engines, bottles, library,
logs). Each launch writes a log to `logs/` there, which is what to send when a game fails.

## How it works

- **Bottles**: one Wine prefix per program (Steam gets the `Steam` bottle), set to Windows
  10, with Option acting as Alt.
- **Library**: when an installer finishes, Burrow picks up the Start Menu shortcuts it
  created (skipping uninstall/readme links) and adds them. Steam games come from Steam's
  `appmanifest_*.acf` files in every library folder and launch through Steam
  (`-applaunch`), so Steam's sign-in, DRM and cloud saves keep working.
- **Turbo graphics**: DXMT draws through functions that stock Wine keeps private, so
  `burrow turbo` downloads the Wine 11.18 source, applies the patches in
  `engine/wine-patches/`, compiles only the Mac driver and the handful of DLLs they touch,
  and lays DXMT over an APFS clone of the stock engine. Bottles on "auto" then use it; the
  stock engine stays as the "compat" fallback. The patches come from
  [Neutron](https://github.com/codeWonderland/neutron) (tested there on Wine 11.18 with Steam,
  Unity and Unreal games).
- **Steam's window**: Steam's UI is a Chromium browser that paints black and can't connect
  under Wine on a Mac. Burrow puts a small wrapper (`wrapper/steamwebhelper.exe`) in front
  of `steamwebhelper.exe` that runs it with `--disable-gpu --single-process` (the fix from
  [steam-on-m1-wine](https://github.com/notpop/steam-on-m1-wine)). Steam replaces that file
  when it updates, so Burrow re-applies the wrapper before every launch and keeps watching
  while Steam is open (leaving files alone while Steam's updater is still writing them).
  Steam starts with `-noverifyfiles`; otherwise it sees the wrapper as a damaged file and
  reinstalls its update in a loop.

## What won't work

- Games with kernel-level anti-cheat (Valorant, Fortnite, many competitive shooters).
- Direct3D 12-only games. Apple's D3DMetal handles those in CrossOver, but its license
  doesn't allow us to ship it and it only runs on older CrossOver-based Wine. A later
  version could use a copy you download from Apple yourself.
- Rosetta 2 is being phased out after macOS 27 (Apple is keeping a subset for games).
- Intel Macs: Windows programs run, but turbo graphics (DXMT) needs Apple Silicon, so Burrow
  doesn't offer it there and games use compatible graphics (wined3d). Older and 2D games are
  fine; most new 3D games won't run.

## Development

```
bin/burrow                 the whole CLI (bash 3.2, as shipped with macOS)
app/BurrowApp.swift        the SwiftUI window; runs bin/burrow for everything
app/Info.plist             the window app's Info.plist (install.sh and the DMG both use it)
app/Burrow.applescript     fallback menu when the window can't be compiled
engine/wine-patches/       Wine patches for turbo graphics (from Neutron)
wrapper/                   the steamwebhelper wrapper (source and prebuilt .exe)
tests/                     Linux Wine tests with small Windows test programs
scripts/package.sh         builds dist/Burrow-<version>.zip
Make DMG.command           builds ~/Desktop/DMGs/Burrow-<version>.dmg on a Mac
Set Up Signing.command     once per Mac: Developer ID certificate and notary login for the DMGs
dmg/                       DMG build: stage.sh, make-dmg.sh, window background, Read Me
```

`tests/run-tests.sh` runs Burrow against Linux Wine with small Windows test programs
(`tests/mocks/`): bottles, installer shortcuts, launching, the library, the Steam wrapper and
re-wrap after an update, Steam library parsing and launching by name, and the usage report.
It needs `wine`, `x86_64-w64-mingw32-gcc` and (without a display) `xvfb-run`. It can't test
anything Mac-specific (Rosetta, Metal, the turbo build).

CI (`.github/workflows/ci.yml`) runs ShellCheck and those tests on Linux, and on macOS
checks the scripts with the system bash 3.2, compiles the window app for Apple Silicon and
Intel, compiles the fallback menu and runs `burrow app`. Pushing a tag like `v0.3.2` that
matches `BURROW_VERSION` in `bin/burrow` publishes the zip as a GitHub release.

Rebuild the wrapper with:
`x86_64-w64-mingw32-gcc -O2 -municode -mwindows -static -s -o wrapper/steamwebhelper.exe wrapper/steamwebhelper-wrapper.c`

## License

Burrow's own code is MIT (see `LICENSE`). Wine, DXMT and Steam are downloaded from their own
projects at setup time and never bundled; see `NOTICE.md` for credits and the licenses of the
included Wine patches.
