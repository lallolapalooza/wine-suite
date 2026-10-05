# CLIP STUDIO PAINT 5.1.4 on Linux with a locally built, patched Wine

CLIP STUDIO PAINT is a registered trademark of CELSYS, Inc. This repository is not associated with, affiliated with, supported nor endorsed by CELSYS, Inc. No guarantees are made, as for the suitability of the content of this repository for any particular purpose.

No CELSYS software is redistributed here. The install media must come from your own CLIP STUDIO PAINT download; the scripts take it from `$CSP_SETUP` or `$CSP_MEDIA` (see `env.sh`).

Subject: `/home/asdf/Downloads/CSP_514w_setup.exe` (CELSYS CLIP STUDIO PAINT 5.1.4.0,
InstallShield InstallScript launcher, 32-bit, 488 MB) on **Wine 11.18** built from source with the
AutoCAD-on-Wine + Power BI-on-Wine patch series and the wine-staging DirectComposition patch set.

## Result

| step | outcome | evidence |
|---|---|---|
| install under Wine | **PASS** — `CSP_514w_setup.exe /s` -> rc 0 in 203 s, 566 MB of product in the prefix | `logs/csp_install_wine.log` |
| launch the editor | **PASS** — `CLIPStudioPaint.exe` runs, main window `CLIP STUDIO PAINT`, DXGI/dcomp surfaces, the four 1x1 helper windows | §5 of `FINDINGS.md` |
| first-run dialog | **PASS, byte-for-byte text parity with Windows** — the Privacy Settings dialog reads identically on both | `evidence/wine_csp_privacy_dialog.png` vs `evidence/win_csp_launch.png` |
| WebView2 start page | **PASS** — renders after installing WebView2 135.0.3179.85; reaches the "Log into Clip Studio" form; the launcher spawns `msedgewebview2.exe` (Chromium 135.0.7049.96) | `evidence/wine_csp_license.png`, `evidence/wine_csp_login_page.png` |
| the three AppDB canvas issues | **BLOCKED — needs a licensed session** (Clip Studio account). See `docs/NEXT_STEPS.md` | `FINDINGS.md` §8 |

Start here: **[`FINDINGS.md`](FINDINGS.md)** for the measurements, **[`docs/SETUP_RECIPE.md`](docs/SETUP_RECIPE.md)**
for the reproducible non-patch fixes, **[`patches/README.md`](patches/README.md)** for which patches are
CSP-specific, **[`STATE.md`](STATE.md)** for the running log.

## Quick start

```bash
source env.sh
tools/apply_patches.sh              # series (19) then local (CSP-exclusive), idempotent
tools/build_wine.sh                 # configure --enable-archs=i386,x86_64, OOM-aware make, install
tools/mkprefix.sh                   # corefonts, vcrun2022, gecko, cjk, overrides, per-exe versions
tools/disable_dxvk.sh               # IMPORTANT: keep Wine's dxgi/d3d11, not DXVK (see below)
tools/run_csp.sh installer          # wine CSP_514w_setup.exe  (or: ... /s for silent)
tools/start_csp_bg.sh editor        # launch the editor detached on the project display
```

Display (Xvfb + x11vnc, so the app is watchable and scriptable):

```bash
Xvfb :20 -screen 0 1920x1080x24 +extension GLX +extension RANDR +extension Composite +render &
openbox --display :20 &                     # a WM is needed for wmctrl/window management
env -u WAYLAND_DISPLAY XDG_SESSION_TYPE=x11 \
    x11vnc -display :20 -rfbport 5920 -forever -shared -nopw &
# drive it with tools/uix.py (shot, ocr, find, click, key, type, pixel, diff)
```

## The two fixes that matter most

1. **Do not install DXVK in this prefix.** DXVK's `dxgi.dll` reports
   `CreateSwapChainForComposition: Not implemented` — the exact entry point the dcomp patch set
   provides — so CSP renders a blank white window. `tools/disable_dxvk.sh` puts Wine's builtin
   `dxgi`/`d3d11`/`dcomp` back and pins them. (Installing DXVK is in the community recipe for other
   reasons; for CSP's UI path it is actively harmful.)
2. **Windows version must be spelled `win81`, not `win8.1`.** CSP must report Windows 8.1
   (WineHQ bug 58254: it exits immediately on 10/11). The dotted spelling is rejected by
   `err:ver:parse_win_version` and silently leaves the app on win10.

Plus: install the **pinned WebView2 135.0.3179.85** into the prefix, otherwise the start page
(and the sign-in form) is a blank grey rectangle — the 115.0.1901.200 build that CSP's own
installer bundles never starts `msedgewebview2.exe` under Wine.

## Proof that the dcomp patch set is load-bearing

`tools/ab_dcomp.sh revert` reverse-applies the 67 patches, rebuilds and installs to a separate
`DESTDIR`; `tools/ab_dcomp_test.sh` then runs the editor twice from the same wiped first-run state:

| build | `dcomp.dll` | app alive at capture | distinct colours on screen |
|---|---|---|---|
| with the patch set | 1 508 005 B | yes | **120 838** (real UI) |
| without it (stub) | 150 925 B | yes | **2** (blank white window) |

Raw artefacts: `evidence/ab_with_dcomp.png`, `evidence/ab_without_dcomp.png`.
`tools/ab_dcomp.sh restore` puts the tree back (verified: 1 508 005 B).

Caveat that cost real debugging time: the two builds have **different wineserver protocol
versions** (the patch set adds `@REQ` entries to `server/protocol.def`), so a leftover wineserver
makes the next run die with `wine client error:0: version mismatch`. Kill the wineserver before
switching builds, or you will be measuring the previous frame.

## Layout

| path | what it is |
|---|---|
| `sources/wine/wine-11.18/` | Wine 11.18 with `patches/series` + `patches/local` applied |
| `wine/wine-11.18/` | the build tree (out-of-tree copy) |
| `wine-install/` | `make install` output; `wine-install/bin/wine` |
| `patches/series/` | shared base: AutoCAD 14 + Power BI 5 (`0001..0019`) |
| `patches/local/` | **CSP-exclusive**: the 67-patch dcomp set, and the MF-encoder candidate |
| `tools/` | build/prefix/launch/automation scripts |
| `vmshare/`, `tools/vmcmd*.sh` | the Windows guest command channel |
| `evidence/` | screenshots of both platforms |
| `logs/`, `state/` | build/run logs; prefix, scratch and disk-backed TMPDIR |
| `docs/` | setup recipe, timelapse analysis, next steps, upstream bug notes |

## Which patches are exclusive to this application

Answer: `patches/local/dcomp-staging/` (67 patches). Its upstream `definition` file states it
`Fixes: [58315] Clip Studio Paint 4 menus turn black when clicked`, which is CSP specifically —
the black/white panel symptom that this project's own blank start page exhibited. The shared
`patches/series/` set (AutoCAD + Power BI) is a general Wine-API base and is *not* CSP-specific.
Details and provenance: `patches/README.md`.

## Honest limits

* The three AppDB bugs on this app version (3D-layer flicker, timelapse header-only export,
  rotated text disappearing) are **not** fixed here: they need an interactive licensed editor
  session, and CSP 5.1.4 gates the editor behind a Clip Studio account. Nothing about them was
  guessed or patched blind — see `docs/NEXT_STEPS.md` and `docs/TIMELAPSE.md`. The Windows
  launcher's home screen also offers **Use Activation Code**, so a licence key (no web account
  needed) would be enough to unblock this.
* The **launcher** (`CLIPStudio.exe`): renders, spawns WebView2 135 correctly and shows its
  crash-recovery notice as legible text (OCR-verified — an earlier "blank window" claim of mine was
  wrong and is retracted in `FINDINGS.md` §10). Its *home* screen content carries no OCR-legible
  text on Wine, but the Windows reference was captured while its own editor was open, so it was in a
  different, blocked state; the comparison is inconclusive rather than a demonstrated Wine bug.
  A fair test needs both platforms running the launcher alone with `quitinfo.json` cleared.
* Rendering ran on Xvfb without DRI3 (software GL). That is fine for correctness measurements but
  says nothing about GPU performance.
* `LipPreview.dll` fails `regsvr32` during install (cosmetic for our purposes; noted in the log).
