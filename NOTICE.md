# Credits and licenses

Burrow's own code (`bin/`, `app/`, `wrapper/`, `install.sh`, `tests/`, `scripts/`) is by
Kyle (Swollzy), under the MIT license in `LICENSE`.

Burrow does not include Wine, DXMT, Steam or anything from Apple. `burrow setup` downloads
them from their own projects, under their own licenses:

- **Wine**: LGPL-2.1-or-later. https://www.winehq.org. macOS builds by Gcenx:
  https://github.com/Gcenx/macOS_Wine_builds
- **DXMT**: v0.80 is MIT (later releases are LGPL). https://github.com/3Shain/dxmt
- **Steam**: Valve's installer, downloaded from Valve's CDN on your Mac.

Included from other projects:

- `engine/wine-patches/*.patch`: from Neutron (https://github.com/codeWonderland/neutron,
  commit in `engine/wine-patches/NEUTRON_COMMIT`), MIT, see
  `engine/wine-patches/LICENSE-neutron`. The patches modify Wine and are distributed
  under Wine's LGPL-2.1-or-later. `burrow turbo` applies them on your Mac and builds
  from Wine's public source.
- `wrapper/steamwebhelper-wrapper.c`: a fresh implementation of the steamwebhelper
  wrapper idea from steam-on-m1-wine (https://github.com/notpop/steam-on-m1-wine, MIT,
  © 2026 notpop).

Apple's D3DMetal (Game Porting Toolkit) is not used or shipped: its license does not clearly
allow redistribution.
