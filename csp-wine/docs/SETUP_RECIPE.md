# Reproducible setup: CLIP STUDIO PAINT 5.1.4 under Wine on Linux

Everything here is a **setup fix, not a Wine patch**: the recipe CSP needs beyond compiling the
patch set in `patches/`. Each item says what it fixes and how to reproduce it. If a fix here
turns out to be fixable in Wine itself, it belongs in `patches/local/` instead and this file gets
a pointer.

Reference for the version: `CSP_514w_setup.exe`, CELSYS CLIP STUDIO PAINT 5.1.4.0,
InstallScript launcher (32-bit), 488 MB.

## 0. Prerequisites

```bash
tools/check_prereqs.sh          # reports gaps with the fix for each
```
Build toolchain: `make m4 patch pkg-config flex>=2.5.33 bison>=3.0 gcc clang lld llvm-dlltool`
(`libfreetype-dev python3`), plus X11/X-extension dev headers and mesa for GL in the prefix.

## 1. Build Wine with the patch set

```bash
tools/apply_patches.sh          # series (19) then local (CSP-exclusive)
tools/build_wine.sh             # configure --enable-archs=i386,x86_64, make -j (OOM-aware), make install
```
`--enable-archs=i386,x86_64` is required: the CSP installer is a 32-bit PE while the editor is x64.
Result: `wine-install/bin/wine`.

## 2. Create and provision the prefix

```bash
tools/mkprefix.sh all           # or: tools/mkprefix.sh   (skips the slow dotnet48)
```

What each piece is for — all of these come from the WineHQ AppDB 4.x install notes and
parka6060/CSPenguin-Installer, which is the community's known-good recipe (5.x uses the same one):

| setting | value | why |
|---|---|---|
| prefix arch | win64 (WoW64) | the editor is 64-bit, the installer is 32-bit |
| global Windows version | **Windows 10** | what the app expects overall |
| `CLIPStudioPaint.exe` version | **Windows 8.1** | **without this CSP exits immediately on a Win10/11 report** — WineHQ bug 58254. Wine's registry spelling is **`win81`**: `win8.1` is rejected (`err:ver:parse_win_version Invalid Windows version value L"win8.1"`) and the app silently stays on the global win10 |
| `msedgewebview2.exe` version | **Windows 7** | the launcher's asset store stays black otherwise |
| `HKCU\Software\Wine\DllOverrides\concrt140` | `native,builtin` | fixes startup crashes: CSP ships its own `concrt140.dll` |
| winetricks `corefonts` | — | the UI asks for Arial/Verdana/etc. by name |
| winetricks `vcrun2022` | — | x64 **and** x86: CSP is x64, its helpers/plugins are x86 |
| winetricks `dotnet48` | — | CSPenguin + kojiinari both install it; slow (10–30 min). Can be skipped for a first boot |
| winetricks `gecko` | — | MSHTML: without it IE-based UI renders as a blank/grey page |
| `dxvk` `vkd3d` | — | **measured harmful here — do not use for CSP.** DXVK's `dxgi.dll` reports `CreateSwapChainForComposition: Not implemented`, which is the exact entry point the dcomp patch set provides, so CSP renders a blank white window. Install at most as an experiment, then run `tools/disable_dxvk.sh` (restores/wineboots Wine's builtin `dxgi`/`d3d11`/`dcomp` and pins them to `builtin`). The AppDB FAQ reaches the same conclusion for a different symptom ("turn DXVK/VKD3D off if the asset store does not load") |
| CJK font | WenQuanYi Micro Hei | asset store + brush names. Prefer this over winetricks `cjkfonts` (112 MB, 28 faces) which adds ~60 s to every CSP start |
| `WINEESYNC=1` | — | menus/panels otherwise take forever to open; raise `nofile` to 524288 |

### After provisioning

```bash
tools/disable_dxvk.sh        # pin dxgi/d3d11/dcomp to builtin — required for CSP's composition path
# install the pinned WebView2 into the prefix (see §3):
wine  sources/media/MicrosoftEdgeWebView2RuntimeInstallerX64.exe /silent /install
```

## 3. Media

| file | version | note |
|---|---|---|
| CSP installer | 5.1.4 (`CSP_514w_setup.exe`) | this project's subject; local copy in `/home/asdf/Downloads` |
| WebView2 runtime | **135.0.3179.85 exactly, installed INTO the prefix** | measured: with the **115.0.1901.200** build that CSP's own installer bundles, `msedgewebview2.exe` never starts and the start page is a uniform grey rectangle with no text; installing 135 makes the page render and the sign-in form usable. Staged at `sources/media/MicrosoftEdgeWebView2RuntimeInstallerX64.exe`; install with `wine <installer> /silent /install`. Verify with `reg query 'HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'` -> `pv` |
| Microsoft Edge (full) | any | the AppDB 4.x recipe installs it; CSPenguin does **not** and still works, so treat full Edge as optional |
| wine-gecko MSI | matching the Wine version | via `winetricks gecko` |

WebView2 URL used (direct, version-pinned):
`https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/76eb3dc4-7851-45b7-a392-460523b0e2bb/MicrosoftEdgeWebView2RuntimeInstallerX64.exe`

Note: `https://go.microsoft.com/fwlink/?linkid=2093435` and `?linkid=2108834` return HTML/JS
landing pages, not the installer — do not script against them.

## 4. Install and launch

```bash
export WINEPREFIX=$PWD/state/prefix WINEESYNC=1 DISPLAY=:20
wine-install/bin/wine /home/asdf/Downloads/CSP_514w_setup.exe    # NSIS/InstallScript GUI installer
# editor:
wine-install/bin/wine "$WINEPREFIX/drive_c/Program Files/CELSYS/CLIP STUDIO 1.5/CLIP STUDIO PAINT/CLIPStudioPaint.exe"
# launcher:
wine-install/bin/wine "$WINEPREFIX/drive_c/Program Files/CELSYS/CLIP STUDIO 1.5/CLIPStudio.exe"
```

Install WebView2 into the same prefix **before** first launching the launcher.

`tools/run_csp.sh` wraps all of this (display, env, logging).

## 5. Display

The app runs on a dedicated Xvfb + x11vnc so it can be watched and driven headlessly:

```bash
Xvfb :20 -screen 0 1920x1080x24 +extension GLX +extension RANDR +extension Composite +render
env -u WAYLAND_DISPLAY XDG_SESSION_TYPE=x11 x11vnc -display :20 -rfbport 5920 -forever -shared -nopw
```

`x11vnc` aborts with "Wayland display server detected" unless `WAYLAND_DISPLAY` is unset — that is
a host-session quirk, not a Wine issue.

Host-side automation: `tools/uix.py` (capture, OCR, find text, click, type, pixel, frame diff).

## 6. Known non-Wine issues from the AppDB that still apply

| symptom | cause / workaround |
|---|---|
| menus (File, ...) sometimes do not draw | CSP spawns four untitled 1x1 windows at 0,0; if the WM closes or minimizes them the menus stop being drawn. Add a window rule that keeps empty-title windows unminimizable/unclosable (KDE: easy; GNOME: menus become separate windows) |
| Save / Export As crash in some 4.x EX builds | WineHQ bug 58430 |
| context menu opens behind the window on GNOME | WineHQ bug 58628 |
| multi-touch gestures not passed through | WineHQ bug 58667 |
| pen pressure dead | Preferences → Tablet → "Use mouse mode in tablet driver settings"; or set the tablet operation area to the whole tablet |
| cursor offset / pen freezes | same tablet setting |
| everything renders tiny under fractional scaling | set the prefix DPI in `winecfg` Graphics to the real screen DPI, then restart wineserver |
