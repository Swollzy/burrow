# Burrow (working name)

Run Windows programs and **Windows Steam** on a Mac, the way CrossOver does: each program
lives in its own "bottle" (a private Windows folder), and you open them from Burrow's menu
or from Mac shortcuts in your Dock.

Burrow is a launcher. The heavy lifting is done by free open source projects that it
downloads from their own sites during setup:

| Layer | Project | What it does |
|---|---|---|
| Windows itself | [Wine](https://www.winehq.org) 11.18, [Gcenx's macOS build](https://github.com/Gcenx/macOS_Wine_builds) | Pretends to be Windows so programs run |
| 3D graphics | [DXMT](https://github.com/3Shain/dxmt) v0.80 | Turns Direct3D 10/11 (what most Steam games use) into Apple's Metal |
| Older graphics | wined3d (part of Wine) | Direct3D 9 and older, through OpenGL |
| Intel code | Rosetta 2 (Apple) | Runs Windows' Intel code on Apple Silicon |

## Install (on the Mac)

1. Unzip `Burrow.zip` in Downloads.
2. Open **Terminal**, type `bash ` (with a space), drag `install.sh` from the Burrow
   folder into the window, and press Return.
3. It downloads Wine and DXMT, asks to build **turbo graphics** (say yes; it takes a few
   minutes and installs Apple's free Command Line Tools and three Homebrew packages the
   first time), then installs and opens Windows Steam.
4. Sign in to Steam and install your games as usual.
5. Next time, open **Burrow** from `~/Applications` (drag it to your Dock). Pick
   "Add my Steam games to this list" once, then pick a game to play it, or make a Dock
   shortcut for it.

Burrow needs macOS 11 or newer; turbo graphics needs an Apple Silicon Mac and DXMT works best
on macOS 15 Sequoia or newer. Leave about 20 GB free for Wine and the bottles, plus your games.

## Commands

```
burrow setup                   download Wine and DXMT (once)
burrow turbo                   build fast Metal graphics for 3D games (once)
burrow steam                   install (first time) and open Windows Steam
burrow steam games             list installed Steam games
burrow steam play "Schedule I" start a Steam game
burrow steam sync              put your Steam games in the library
burrow install <setup.exe|url> install any Windows program into its own bottle
burrow apps                    list your library
burrow launch <app>            start a program (--graphics turbo|compat to override)
burrow shortcut <app>          make a Mac app for it in ~/Applications/Burrow
burrow doctor                  check everything
burrow kill                    force-quit Windows programs
```

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
  while Steam is open.

## What won't work

- Games with kernel-level anti-cheat (Valorant, Fortnite, many competitive shooters).
- Direct3D 12-only games. Apple's D3DMetal handles those in CrossOver, but its license
  doesn't allow us to ship it and it only runs on older CrossOver-based Wine. A later
  version could use a copy you download from Apple yourself.
- Rosetta 2 is being phased out after macOS 27 (Apple is keeping a subset for games).

## Tests

`tests/run-tests.sh` runs Burrow against Linux Wine with small Windows test programs
(`tests/mocks/`): bottles, installer shortcuts, launching, the Steam wrapper and re-wrap
after an update, Steam library parsing and launching by name. It can't test anything
Mac-specific (Rosetta, osacompile, Metal, the turbo build).

Rebuild the wrapper with:
`x86_64-w64-mingw32-gcc -O2 -municode -mwindows -static -s -o wrapper/steamwebhelper.exe wrapper/steamwebhelper-wrapper.c`
