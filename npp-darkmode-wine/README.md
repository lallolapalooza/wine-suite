# Notepad++ dark mode on Wine (Wine bug 57555)

Goal: make Notepad++ dark mode work under Wine the way it does on Windows, by patching
Wine. Notepad++ is a pure Win32 application (no frameworks/SDKs/browsers), so the fix is
a generic set of win32u/uxtheme/dwmapi patches — **not** an app hack, and it does not
depend on patches from any other project. Built on a pristine `wine-11.18` tarball from
dl.winehq.org.

## Status: FIXED and verified
| | stock Wine 11.18 | patched Wine 11.18 |
|---|---|---|
| menu bar (dark mode) | `#FFFFFF` light (bug) | `#202020` **dark** |
| popup menus (File ▾) | `#FFFFFF` light | `#202020` **dark**, `#E0E0E0` text, `#454545` hover |
| toolbar / editor | dark | dark |
| light mode | light | light (unchanged) |
| "Follow Windows" mode (registry dark) | dark chrome, light menus | fully dark |

`compare_stock_vs_patched.png` (top = stock, bottom = patched, same UI state:
File menu open in dark mode) — stock shows a light menu bar and a light white
dropdown inside an otherwise dark window; patched shows both drawn dark.

## Root cause
Notepad++ paints its menu bar itself using the undocumented **UAH protocol** that Windows
10 1809+ uses for dark-mode apps: it subclasses the frame window
(`NppBigSwitch.cpp:228`) and only draws in response to `WM_UAHDRAWMENU` (0x0091) /
`WM_UAHDRAWMENUITEM` (0x0092) / `WM_UAHMEASUREMENUITEM` (0x0094)
(`NppDarkMode.cpp:4154-4210`, `src/full/PowerEditor/src/DarkMode/UAHMenuBar.h`).

Wine 11.18 never sends those messages, and the app's dark-mode signals were dropped:
* `uxtheme` ordinals 133 `AllowDarkModeForWindow`, 135 `SetPreferredAppMode`,
  136 `FlushMenuThemes`, 137 `IsDarkModeAllowedForWindow` were `FIXME("stub")`
  returning `FALSE`/`0` (`dlls/uxtheme/system.c`).
* `dwmapi`'s `DwmSetWindowAttribute` ignored `DWMWA_USE_IMMERSIVE_DARK_MODE` (=20), which
  is what Notepad++ uses on Windows 10 2004+ (`NppDarkMode.cpp:4236`; Wine reports build
  19045).
* `dlls/win32u/menu.c` had no dark-mode handling at all (menu bar and popups were drawn
  with system colours).

## The patches (`patches/`, regenerate with `tools/make_patches.sh`)
Apply from the Wine source root with `patch -p1` (verified to apply cleanly on pristine
wine-11.18 and to reproduce the tested tree byte-for-byte):

1. `0001-win32u-Send-UAH-menu-bar-messages.patch`
   `NtUserDrawMenuBarTemp()` now detects dark-mode windows, sends `WM_UAHINITMENU` +
   `WM_UAHDRAWMENU` + one `WM_UAHDRAWMENUITEM` per item and skips the default drawing,
   so the application paints its own dark menu bar (like Windows 1809+).
   It also draws popup menus dark (background/text/hover/separators/frame) when the
   owner window uses dark mode. Dark mode is read from the `__wine_dark_mode` window
   property (1 = dark, 2 = explicitly light, absent = unset).
2. `0002-uxtheme-Implement-dark-mode-entry-points.patch`
   `AllowDarkModeForWindow` / `IsDarkModeAllowedForWindow` set/read that property instead
   of reporting failure; `SetPreferredAppMode(ForceDark)` marks the existing windows of
   the process; `FlushMenuThemes` / `RefreshImmersiveColorPolicyState` are no-ops.
3. `0003-dwmapi-Implement-immersive-dark-mode.patch`
   `DwmSetWindowAttribute` / `DwmGetWindowAttribute` implement
   `DWMWA_USE_IMMERSIVE_DARK_MODE` by storing/reading the same property, so the
   documented API Notepad++ uses on modern Windows actually works.

All three are generic Win32 behaviour fixes (any dark-mode application benefits);
**no patch is Notepad++-specific**, so `patches/app-specific/npp/` contains only a note.

## Building
```sh
cd wine-build
../wine-src/configure --enable-archs=x86_64   # already configured
./config.status && make -j$(nproc)
```
The build is x86_64-only, so it needs its own prefix (no syswow64):
```sh
DISPLAY=:99 WINEPREFIX=$PWD/prefix-build $PWD/wine-build/wine wineboot -i
```
Wine build gotchas hit while doing this (see STATE.md for details):
* `win32u` is a dual module: the real implementation lives in the unix library
  `win32u.so`; new sources need `#pragma makedep unix`.
* Unix-side wide string literals must be `WCHAR` char arrays, not `L"..."`.
* Adding new win32u syscalls also requires regenerating the checked-in table
  `dlls/win32u/win32syscalls.h` — avoided entirely by using window properties.

## Verifying
```sh
python3 tools/npp_dark_test.py --wine $PWD/wine-build/wine \
        --prefix $PWD/prefix-build --mode dark            # -> OK (dark mode fully applied)
python3 tools/npp_dark_test.py --wine /opt/wine-staging/bin/wine \
        --dllpath /opt/wine-staging/lib/wine --prefix $PWD/prefix --mode dark
                                                          # -> BUG (chrome dark, menu bar light)
```
Screenshots: `compare_stock_vs_patched.png`, `shot_final_patched.png`,
`shot_popup_dark3.png` (dark popup), `shot_final_stock.png` (stock bug),
`compare_light_vs_dark.png` (first reproduction).

Probes used to characterise the APIs: `probe.exe` (uxtheme ordinals + UAH delivery),
`probe2.exe` (theme `Menu`/`MENU_BARITEM` availability), `probe3.exe` (registry /
high-contrast / version checks).

## Known remaining differences vs Windows
* Menu popup scroll arrows and check-mark bitmaps still use system colours (rare in
  Notepad++ menus).
* Caption/title-bar darkening is not applicable: Wine has no DWM compositor and the
  decorations come from the X11 window manager; the DWM attribute is stored but unused.
* Wine has no dark Win32 scrollbars (Notepad++'s `OpenNcThemeData` hooking trick).

## Method notes
* No Windows VM was used (the available VM belongs to another agent and cannot be
  duplicated safely: 52 GB image vs 18 GB free disk). The contract was taken from
  Notepad++'s own source, which is the authoritative statement of what the app expects.
* Patches are not to be submitted upstream through this process (per instruction).
