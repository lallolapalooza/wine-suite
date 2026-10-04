# FINDINGS — CLIP STUDIO PAINT 5.1.4 on Wine 11.18

Ordered log of what was measured, with the evidence file for each claim. Absolute times are the
host clock; the Windows guest's clock runs two hours behind (its own timezone), so guest-side
timestamps look earlier.

## 0. Subject

`/home/asdf/Downloads/CSP_514w_setup.exe` — 488 891 856 bytes, PE32 (i386) GUI, Flexera
InstallScript Setup Launcher Unicode, `ProductName CLIP STUDIO PAINT`, `FileVersion 5.1.4.0`,
`CompanyName CELSYS`, `ISInternalVersion 30.0.233`. Embeds an InstallShield `ISc(` cabinet at file
offset `0x118EA0`.

## 1. Windows reference built first (clean VM)

The `win11` libvirt domain had AutoCAD 2027, Eos/ETC, Hog PC, Resolume Arena, Power BI, Bonjour and
15 other third-party products from earlier projects. These were removed (guest C: went from
**3.1 GB free to 22.61 GB free**); the Microsoft platform components (.NET, VC++ redistributables,
Edge, WebView2, OneDrive, WPTx64) were kept because they are not "apps".

Process: an elevated polling channel (`C:\seref\vm_admin.ps1` + `cmd_admin.txt`/`admin_out.txt`,
started through one UAC prompt answered with `virsh send-key ... KEY_LEFTALT KEY_Y`) plus a
force-removal pass (`vmshare/cleanup_force.ps1`) that stops vendor processes, deletes services and
scheduled tasks, force-removes the install trees and strips the uninstall registry keys.
The Autodesk **ODIS** uninstaller (`Installer.exe -i uninstall ...`) hangs for more than 30 minutes
per bundle and was abandoned deliberately — force-removal is the correct tool for making a clean
reference VM, not a supported uninstall.

Then CSP was installed from an ISO attached as `sde` (`sources/media/csp_media.iso`, built with
`xorriso`, also holding the pinned WebView2 installer):

```
F:\CSP_514w_setup.exe /s        -> rc 0, 559.6 MB
C:\Program Files\CELSYS\CLIP STUDIO 1.5\
    CLIP STUDIO PAINT\CLIPStudioPaint.exe        FileVersion 5.1.4.0
    CLIP STUDIO PAINT\ClipPreview.dll, LipExt.exe, OpenAL32.dll, ailia*.dll, PlugIn\, Settings\
    CLIP STUDIO\CLIPStudio.exe                   (the launcher)
```

Running `CLIPStudioPaint.exe`: process `CLIPStudioPaint` 186 MB, `Responding=True`, window title
`CLIP STUDIO PAINT`, first-run **Privacy Settings** dialog.
Evidence: `evidence/win_csp_launch.png`.

Note: the WebView2 installer pinned by the community recipe (**135.0.3179.85**) refuses to install
over the guest's WebView2 154.0.4258.53 (`exit -2147219187`). The pin is a Wine-side workaround, so
the guest was left on 154.

## 2. Wine base

`wine-11.18.tar.xz` (dl.winehq.org) + `patches/series/0001..0019` (AutoCAD 14 + Power BI 5) applied
cleanly (19/19), then **67/67** of the wine-staging `dcomp-DCompositionCreateDevice2` patchset at
tag v11.18 (`patches/local/dcomp-staging/`).

Build: `./configure --enable-archs=i386,x86_64 --prefix=$PWD/../wine-install`, `make -j17`
(job count derived from `MemAvailable`), `make install`. **41 min wall, peak RSS 683 MB**.
`wine --version` -> `wine-11.18`; smoke test `wineboot -u` + `wine cmd /c echo` -> OK, reports
`Microsoft Windows 10.0.19045`.

Incremental rebuild after adding dcomp initially failed:

```
server/d3dkmt.c:791: error: invalid use of undefined type 'struct dcomp_create_shared_visual_reply'
```

Cause: the patchset adds `@REQ(dcomp_...)` to `server/protocol.def`, and an incremental `make` does
not regenerate `include/wine/server_protocol.h`. Fix: `./tools/make_requests server/protocol.def`
from the build root (rewrites `include/wine/server_protocol.h`, `server/request_trace.h`,
`server/request_handlers.h`), then `make`. After that: `make` + `make install` OK, and
`wine-install/lib/wine/{i386,x86_64}-windows/dcomp.dll` are 1.29 MB / 1.50 MB real implementations.

## 3. Prefix

`tools/mkprefix.sh` — win64 prefix, Windows 10 global, `corefonts`, WenQuanYi Micro Hei CJK font,
`vcrun2022`, `gecko`, `dxvk`, `vkd3d`, `concrt140` override, per-executable Windows versions.

## 4. CSP installs under Wine — PASS

```
wine-install/bin/wine CSP_514w_setup.exe /s     -> rc 0, 203 s
```

566 MB at `drive_c/Program Files/CELSYS/CLIP STUDIO 1.5/CLIP STUDIO PAINT/` with
`CLIPStudioPaint.exe`, `ClipPreview.dll`, `LipExt.exe`, `OpenAL32.dll`, `ailia*.dll`, `PlugIn/`,
`Settings/`. Installer log notes `regsvr32: Successfully registered DLL ...ClipPreview.dll` and
`regsvr32: Failed to register DLL ...LipPreview.dll`, plus repeated
`ole:std_release_marshal_data could not map object ID to stub manager` /
`CoReleaseMarshalData ... 0x8001011d`. Logs: `logs/csp_install_wine.log`.

## 5. CSP opens under Wine — PASS, and the two bugs that had to be fixed to get there

`CLIPStudioPaint.exe` runs. Window inventory on the X display:

```
"DXGI device window"                   113x2+3+29
"CLIP STUDIO PAINT"                    800x600+0+0   (at screen 560,240)
(unnamed child)                        1194x834+0+0  (the render surface)
0x1400014/13/15/b (unnamed)            1x1+0+0       <- the four 1x1 helper windows the AppDB comment describes
```

### Bug A: DXVK was shadowing the patched dcomp/dxgi

With `winetricks dxvk` installed, DXVK's `dxgi.dll` wins over Wine's, and the log fills with

```
warn:  CreateDXGIFactory2: Ignoring flags
err:   DxgiFactory::CreateSwapChainForComposition: Not implemented
```

`CreateSwapChainForComposition` is exactly the entry point the wine-staging dcomp patchset HACKs
into `dlls/dxgi/factory.c`, so with DXVK installed the patch set can never take effect and CSP's
composition path draws nothing: the window was a **blank white rectangle** (exactly 2 distinct
colours on a 1920x1080 screen; `evidence/wine_csp_launch.png` is 987 bytes).
`tools/disable_dxvk.sh` restores Wine's builtin modules (`wineboot -u`) and pins
`dxgi d3d8 d3d9 d3d10core d3d10_1 d3d11 d3d12 d3d12core dcomp` to `builtin`. **Never "fix" a blank
CSP window by installing DXVK.**

Do not confuse this with deleting the DLLs: in a Wine prefix `system32\*.dll` are Wine's own builtin
PE modules. Deleting them makes the app fail to start with
`err:module:import_dll Library d3d11.dll ... not found` / `status c0000135`.

### Bug B: `win8.1` is not a valid Wine version string

```
err:ver:parse_win_version Invalid Windows version value L"win8.1" specified in config file.
```

The AppDB recipe requires CSP to run as **Windows 8.1** (bug 58254: CSP exits immediately on a
Windows 10/11 report). Wine's registry spelling is **`win81`**; the dotted form is rejected and the
app silently stays on the global win10 — i.e. exactly the configuration that crashes. Fixed in
`tools/mkprefix.sh` (and applied to `CLIPStudioPaint.exe`, `CLIPStudio.exe`,
`CLIPStudioUpdater.exe`; `win7` for `msedgewebview2.exe`).

### Result (evidence `evidence/wine_csp_privacy_dialog.png`)

Screen has 722 distinct colours and CSP's dark palette, and the OCR reads the same dialog Windows
shows, verbatim:

```
CLIP STUDIO PAINT                                        x
Privacy Settings
Please help us to improve Clip Studio.   See here for details about data we collect.
Help fix errors
If an error occurs, automatically send anonymous information about the incident.
This helps us resolve bugs and errors.
Improve services
Automatically sends information about features that you use.
This helps us to improve user experience and develop new features.
You can change this at any time from File > Privacy Settings.
```

## 6. The WebView2 start page — needed the pinned runtime

After the privacy dialog, Windows shows the licence/start page
(`evidence/win_csp_license.png`): "Draw and create with Clip Studio Paint", pricing,
"Already have a plan?".

On Wine that stage was a **perfectly uniform (78,78,78) rectangle, no text** — the AppDB's "blank
dialog" symptom. Measurements:
* the prefix's WebView2 was **115.0.1901.200**, the build CSP's own installer bundles, and
  `msedgewebview2.exe` was **never running**;
* `grep -ic 'webview|msedge' logs/csp_run.log` -> 0, i.e. CSP never got as far as logging a host
  process;
* wine-gecko was also absent (`system32/gecko/` contained only `plugin/npmshtml.dll`).

Installing the pinned **135.0.3179.85**
(`wine sources/media/MicrosoftEdgeWebView2RuntimeInstallerX64.exe /silent /install`, rc 0,
registry `pv` -> 135.0.3179.85) fixed it: the page renders fully (121 473 distinct colours) and OCR
reads it. Evidence `evidence/wine_csp_license.png`. Clicking through reaches a fully rendered
**"Log into Clip Studio"** form (email + password + "Create account"), documented in
`evidence/wine_csp_login_page.png`, and the launcher `CLIPStudio.exe` spawns
`msedgewebview2.exe --embedded-browser-webview=1 --webview-exe-name=CLIPStudio.exe ...` with
Chromium `135.0.7049.96` and a live mojo channel — i.e. WebView2 genuinely works under Wine here.

## 7. Automation notes (why this was drivable headlessly)

* The harness drops images from `read` for this model, so everything is measured: screen capture
  (`import`), OCR (`tesseract`), programmatic pixel analysis.
* OCR of CSP's dark UI only works with `convert -colorspace Gray -normalize -resize 150-200%` then
  `tesseract --psm 6`; raw OCR returns nothing.
* Buttons are found by scanning for large bright rectangles, not by OCR. The Privacy Settings OK
  button is the 229x47 bright rect at x 1131-1360, y 786-833 -> click at **(1245, 809)**.
  `xdotool` clicks use **screen** coordinates.
* A window manager must be running (`openbox` on `:20`) for `wmctrl` to work at all; without one,
  `wmctrl -l` fails with "Cannot get client list properties".
* `x11vnc` refuses to start while the host env sets `WAYLAND_DISPLAY`; start it with
  `env -u WAYLAND_DISPLAY XDG_SESSION_TYPE=x11 x11vnc -display :20 ...`.
* Xvfb has no DRI3, so EGL/GLX fall back to software (every run logs
  `libEGL warning: DRI3 error: Could not get DRI3 device`). This is expected on `:20`; using a real
  GPU display is a separate, performance-only concern.

## 8. Blocker for the three AppDB issues

The AppDB issues (3D-layer flicker, timelapse export, disappearing rotated text) all need an
**interactive, licensed editor session**. CSP 5.1.4 gates the editor behind a Clip Studio account:
the start page offers "View plans" and "Already have a plan?", and the sign-in form needs an email
and password (or a new account, which needs email verification). No offline/trial-without-account
path was found on the start page.

So: the app installs, opens and renders its real UI under Wine, matching Windows — but exercising
the three canvas features requires credentials that cannot be obtained autonomously. See
`docs/NEXT_STEPS.md` for the options.

## 9. Proof that the dcomp patch set is load-bearing (A/B)

`tools/ab_dcomp.sh revert` reverse-applies all 67 dcomp patches in the build tree, regenerates
`server/protocol.h` with `tools/make_requests` (the header then contains **0** `dcomp` entries),
rebuilds and installs to a separate `DESTDIR` (`state/nodcomp/...`) so the working `wine-install`
is untouched. `tools/ab_dcomp_test.sh` then runs the editor twice **from the same wiped first-run
state** — `CELSYS`/`CELSYS_EN`/`CELSYSUserData` moved aside, then restored afterwards — and captures
the first-run dialog each time.

| build | `dcomp.dll` | distinct colours on screen | OCR of the dialog |
|---|---|---|---|
| with the patch set (`wine-install`) | 1 508 005 B | **701** | `CLIP STUDIO PAINT x / Privacy Settings / Please help us to improve Clip Studio. / Help fix errors / If an error occurs, automatically send anonymous information about the incident.` |
| without it (`state/nodcomp`) | 150 925 B (the stub) | **2** | nothing |

Two colours means the entire 1920x1080 screen is only black and white — a blank white window, the
same failure signature the DXVK run produced. Evidence: `evidence/ab_with_dcomp.png` (48 KB of real
UI) vs `evidence/ab_without_dcomp.png`.

`tools/ab_dcomp.sh restore` re-applies the patches, rebuilds and reinstalls; verified afterwards that
`wine-install/lib/wine/x86_64-windows/dcomp.dll` is back to 1 508 005 B.

So for this application the 67-patch DirectComposition set is not incidental: without it CSP's very
first window is blank, with it the app renders its UI.

### 9b. Re-validation (the first A/B run was confounded)

The first A/B pass was not trustworthy: the two builds have **different wineserver protocol
versions** because the dcomp patchset adds `@REQ` entries to `server/protocol.def` (the handshake
numbers observed were 963 vs 965). A leftover wineserver from the other build then makes the next
run die with

```
wine client error:0: version mismatch 963/965.
```

which would have left stale pixels on screen and silently invalidated the result. The test was
therefore rewritten to kill every project wineserver between legs, wait for the app process to
appear, and record whether it was alive at capture time, and it was re-run:

| build | `dcomp.dll` | process alive at capture | version-mismatch lines | distinct colours |
|---|---|---|---|---|
| with the patch set | 1 508 005 B | **yes** | **0** | **120 838** |
| without it | 150 925 B (stub) | **yes** | **0** | **2** (black + white) |

Both legs genuinely ran; the difference is entirely the dcomp implementation. Evidence files are
regenerated by `tools/ab_dcomp_test.sh`: `evidence/ab_with_dcomp.png`,
`evidence/ab_without_dcomp.png`.

Operational note for anyone reusing this prefix: **kill the wineserver before switching between two
Wine builds**, or the app will not start and you will be looking at the previous frame.

## 10. The launcher (`CLIPStudio.exe`) — corrected findings

**My first claim was wrong and is retracted.** From a coarse ASCII view I called the launcher window
"blank". Cropping its two windows and OCR-ing them at high magnification shows it renders text fine:

```
CLIP STUDIO                                                                    x
Clip Studio failed to close normally last time.
To draw in Clip Studio Paint, launch the app and tap "Open Clip Studio Paint".
If Clip Studio repeatedly fails to launch, please see the following FAQ.
[Open Clip Studio] [Open FAQ] [Open Clip Studio Paint]
```

Measured layout: two windows titled `CLIP STUDIO` — a 475x116 splash at +722+321 and a 1034x797
main window at +443+141 — plus a `DXGI device window` and the usual 1x1 helpers; 255 grey levels in
the splash crop. So the launcher's native UI renders and is OCR-legible.

What that panel is: a **crash-recovery notice**, because this project kills CSP with `pkill` instead
of closing its window. The marker is
`AppData/Roaming/CELSYS/CLIPStudio/1.5.0/Preference/quitinfo.json` = `{"running":true}`; writing
`{"running":false}` before launch removes the notice. Note the launcher renders that notice in
*both* its windows (the splash and the main window show the same text), which is why the earlier
coarse view of the main window looked like an empty panel.

After clearing the marker the launcher starts, spawns
`msedgewebview2.exe ... --webview-exe-name=CLIPStudio.exe --webview-exe-version=5.1.4` (WebView2
135.0.3179.85, Chromium 135.0.7049.96) and its window renders, but the home content carries **no
OCR-legible text** (470x100 crop of the content panel at 500%: nothing under `--psm 6` or `--psm 11`;
~274 distinct colours on screen).

Reference comparison is **inconclusive, not a demonstrated Wine bug**: the Windows guest's launcher
was captured while the Windows CSP editor was still open, and it was showing a blocking banner of
its own —

```
CLIP STUDIO
Please do not launch other Clip Studio applications until this process is complete
Projects / Materials / Log in / Use Activation Code
```

— so the two sides were not in the same state. A fair test needs both platforms running the launcher
alone, with no editor open, and the marker cleared on both. That is the concrete next step if the
launcher's home screen matters; the editor (the actual product surface) renders fully and is
unaffected by this.

Incidental discovery worth recording: the Windows launcher's home screen offers **Use Activation
Code** as well as **Log in** — so a licence key, if the user has one, can be entered without a web
account, which would also unblock the three canvas issues.
