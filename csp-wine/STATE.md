# CSP on Wine — STATE (authoritative; update as work proceeds)

Task: `/home/asdf/Downloads/CSP_514w_setup.exe` (CELSYS CLIP STUDIO PAINT 5.1.4.0, InstallShield
InstallScript launcher, 32-bit PE, 488 MB) must install and open on Wine exactly as it does on
Windows, running the wine patches already produced in the `autocad` and `powerbi` work, plus new
wine patches for whatever CSP still needs.

Acceptance (user):
1. Packaged app runs on Wine until it opens like in Windows.
2. Fix the three winehq appdb issues for this version
   (https://appdb.winehq.org/objectManager.php?sClass=version&iId=43183):
   a. 3D layer: importing an object makes the layer flicker until deselected.
   b. Timelapse export writes header-only files (no frames).
   c. Rotating text makes the text disappear (no longer hangs).
3. `csp-wine/` must contain every wine patch used, in a reproducible form.
4. MUST be able to say which patches are **exclusive to this app**.

## Deliverable directory contract (user-specified)

```
csp-wine/
  patches/series/     # shared base: AutoCAD 14 + Power BI 5  (0001..0019)
  patches/local/      # patches EXCLUSIVE to CSP (this app)
  wine-11.18/         # pristine 11.18 + series + local applied
  wine/wine-11.18/    # build tree
  wine-install/       # make install output
  state/              # prefix, tmp (disk-backed), scratch
  logs/ evidence/ docs/ tools/ vmshare/
```

## Decisions taken

- Wine base = upstream 11.18 from `/home/asdf/Downloads/wine-11.18.tar.xz`, patched with the
  19-patch shared base (`patches/series/0001..0019` copied from `eos-wine/patches/series`,
  which is AutoCAD 14 + Power BI 5). NOT reused from `eos-wine/wine-11.18` — that tree proved
  **unpatched** (no `dlls/ntdll/tests/impersonate.c`, no `NtImpersonateAnonymousToken` in
  `dlls/ntdll/`), so it is not a trustworthy base.
- Build: `--enable-archs=i386,x86_64` (installer is 32-bit PE; app is x64) — one build serves both.
- OOM guard: pick `-j` from available RAM before `make`; keep peak RSS under the free-RAM headroom.
  Disk-backed TMPDIR only (3.1 GB free in the *guest*; host `/` has ~46 GB free).
- Compose via `virsh screenshot` + `tesseract` OCR; interaction via QMP `virsh send-key` and,
  on the host side for the wine app, Xvfb + xdotool + x11vnc. This model cannot receive images
  through `read` (harness omits them), so all "seeing" is programmatic (OCR / pixel analysis).
- Windows reference = libvirt domain `win11` (192.168.122.230, spice 127.0.0.1:5900).

## Guest (Windows VM) command channel — WORKING

- Host: `python3 tools/vmserv.py 8000 /home/asdf/projects/csp-wine/vmshare` (long-lived service
  `vmshare-http`; serves GET, accepts PUT).
- Guest medium poller: `C:\seref\se_svc.ps1` (already running as `asdf\adsf`, **NOT elevated**),
  polls `cmd.txt`, uploads `guest_cmd_out.txt`. Host helper: `tools/vmcmd.sh '<ps>' [timeout]`.
- Guest elevated poller: `C:\seref\vm_admin.ps1` (template from mastercam-wine), polls
  `cmd_admin.txt`, uploads `admin_out.txt`. Host helper: `tools/vmcmda.sh '<ps>' [timeout]`.
  Started via a one-time UAC approval (`Start-Process -Verb RunAs`), answered with
  `virsh send-key win11 --holdtime 60 KEY_LEFTALT KEY_Y`.

## VM cleanup (user priority interjection) — IN PROGRESS

Installed third-party apps found (41 uninstall entries total):
AutoCAD 2027 + ACAD Private + Open in Desktop + Access + App Manager + 2027.1 Update + MCP Server
+ CER + Featured Apps + Genuine Service + Interoperability Engine Manager (all Autodesk);
Eos Family ETCnomad + ETCnomad Eos Application v3 + ETC SLP + ETC USB Device Drivers + Augment3d;
Hog PC 5.2.1.31; Resolume Arena 7.28.0; Microsoft Power BI Desktop (x64) x2 entries; Bonjour.
KEEP: MSVC++/VC++ redistributables, .NET runtimes, Edge/WebView2, OneDrive, WPTx64 (platform
components, not "apps").
Guest disk before cleanup: **C: 59.8 GB used, 3.1 GB free**.

## Findings so far

- `7z x` on the installer yields the PE section dump (`[0]` = 487 MB payload) — the real payload is
  an InstallShield 30 cabinet around file offset `0x118EA0`. Not needed for the primary path: the
  installer will be run under Wine and the installed tree read from the prefix.
- Installer metadata: ProductName `CLIP STUDIO PAINT`, FileVersion 5.1.4.0, Company `CELSYS`,
  InstallScript Setup Launcher Unicode, `ISInternalVersion 30.0.233`.

## Open items / next actions

1. Finish VM cleanup via the elevated channel; verify inventory + free space.
2. Stage wine source + series; build; `make install`.
3. Create CSP prefix, install under Wine, then launch on Xvfb+x11vnc, iterate on failures.

## Blocker: subagents unavailable (2026-10-03)

Every `task`/`scout` spawn fails immediately with
`[opencode-go/deepseek-v4-flash] 402 Upstream request failed: Insufficient account funds`.
The user asked for ~10 parallel subagents; that is impossible until the provider account is funded.
All research and implementation is therefore done inline by the main agent. Retest subagents later;
if they work again, parallelise the RE and per-issue workstreams.

## Research results (2026-10-03, inline — subagents unavailable)

### The known-good CSP recipe (WineHQ AppDB 4.x page + comments, and parka6060/CSPenguin-Installer)

Install deps: `corefonts vcrun2022 dotnet48 dxvk vkd3d` + wine-gecko (x86_64 MSI, so IE-based UI
renders) + a light CJK font (WenQuanYi Micro Hei, NOT cjkfonts — 60 s slower startup).
Global Windows version 10; per-exe overrides:
- `msedgewebview2.exe` -> **Windows 7** (fixes launcher asset store)
- `CLIPStudioPaint.exe` -> **Windows 8.1** (Windows 10/11 compat mode makes CSP 4 exit immediately;
  WineHQ bug 58254; upstream patch landed in wine-staging 11.5 = commit f49102a)
DLL overrides: `concrt140=native,builtin` (startup crashes), plus CSPenguin's
`dcomp / mfplat / mfreadwrite = native,builtin` and native `dcomp.dll`, `libwinpthread-1.dll`,
`mfplat.dll`, `mfreadwrite.dll`, `winegstreamer.dll`, unix `winegstreamer.so`.
`WINEESYNC=1` fixes menus/panels taking forever to appear.
Media needed: Microsoft Edge (full) + **WebView2 runtime 135.0.3179.85** (exact version) + the CSP
installer. Launcher = CLIPStudio.exe; the editor = CLIPStudioPaint.exe
(`C:\Program Files\CELSYS\CLIP STUDIO 1.5\CLIP STUDIO PAINT\CLIPStudioPaint.exe`).

### Wine patches that are specific to CSP (candidates for patches/local)

1. **dcomp-DCompositionCreateDevice2 patchset (67 patches), wine-staging tag v11.18.**
   Its `definition` file says verbatim: `Fixes: [54968] dcomp: Implement DCompositionCreateDevice2`
   and `Fixes: [58315] Clip Studio Paint 4 menus turn black when clicked`.
   Verified: 67/67 apply cleanly to our wine-11.18 + 19-patch base (tested in
   `state/scratch/wine-patchtest`). This is the real fix for CSP's black/white panels/dialogs
   instead of shipping a native dcomp.dll shim. Source: downloaded copy in
   `patches/local/dcomp-staging/` (from https://gitlab.winehq.org/wine/wine-staging tag v11.18).
   NOTE: it is a HACK patchset; it touches dlls/dcomp (device.c/visual.c/surface.c/target.c added),
   dlls/dxgi/factory.c and adds dcomp tests.
2. **wine-mf-encoder-support.patch (CSPenguin)** — Media Foundation sink-writer/encoder work for
   **timelapse/video export**. The upstream file has 15 corrupt hunk headers (patch(1):
   "malformed patch at line 30"); repaired by `tools/fix_patch_hunks.py` into
   `patches/local/0100-mf-encoder-support.patch` (21 hunks).
   Against wine 11.18 it applies 14/21 hunks; the 7 rejects are either the author's own debug-TRACE
   diffs (no-ops) or code **upstream 11.18 has since refactored/reimplemented**
   (`stream_create_transforms()` with a `use_encoder` flag already exists upstream, and
   `sink_writer_get_buffer_length` / `sink_writer_WriteSample` already match the patch's result).
   Real remaining delta: `bytestream_file_Close` implementation (11.18 still `FIXME`/`E_NOTIMPL`),
   `media_sink_SetPresentationClock` implementation (11.18 still a stub), `wg_transform`
   I420/YV12 plane-fix flag, and writer Finalize state handling.
   **Decision: do not blind-apply it.** Get CSP running first, then make timelapse export fail and
   write the minimal correct patch for 11.18 from the observed failure.
3. Bug 58254 (CSP exits on Windows 10/11 compat mode) — fix is in wine-staging 11.5
   (commit f49102a, patchset `windows_storagefile`: RadialController + StorageFile stubs).
   Candidate local patch if CSP 5.1.4 still needs it; otherwise use the documented per-exe
   "Windows 8.1" setting.

### Other upstream bugs for reference
58254 (Win10 compat exit), 58315 (black menus/settings/login — fixed by dcomp patchset),
58430 (crash on save/export), 58628 (context menu behind window on GNOME),
58667 (multi-touch not passed through), 59330 (zh-CN launch failure), 58369 (dup of 58254).
Also from AppDB comments: CSP spawns four 1x1 windows at 0,0; closing/minimizing them stops menus
from drawing (KWin window rule workaround).

### Downloads staged
`sources/media/MicrosoftEdgeWebView2RuntimeInstallerX64.exe` (135.0.3179.85, 178 MB, http 200).
Still needed: Microsoft Edge Windows x64 installer.

## Build status (2026-10-03 19:10 host time)

Base build (series 0001..0019) finished: 41 min wall, `-j17`, peak RSS 683 MB, `make install` into
`wine-install/`; `wine --version` = wine-11.18; wineboot + `wine cmd /c echo` smoke test PASS
(reports "Microsoft Windows 10.0.19045").

Then the 67 dcomp patches were applied to BOTH `sources/wine/wine-11.18` and the build tree
`wine/wine-11.18` (67/67 each), and the tree was rebuilt: reconfigure + `make -j17` + `make install`
all OK. `wine-install/lib/wine/{i386,x86_64}-windows/dcomp.dll` are now 1.29 MB / 1.50 MB real
implementations (was a stub before).

**Gotcha worth remembering:** the dcomp patchset adds `@REQ(dcomp_...)` entries to
`server/protocol.def`, and an incremental `make` does NOT regenerate
`include/wine/server_protocol.h` on its own — the build failed with
`invalid use of undefined type 'struct dcomp_create_shared_visual_reply'` in `server/d3dkmt.c`.
Fix: run `./tools/make_requests server/protocol.def` from the build root (it rewrites
`include/wine/server_protocol.h`, `server/request_trace.h`, `server/request_handlers.h`), then make.

Display for the Wine app: Xvfb `:20` (1920x1080x24, GLX+RANDR+Composite+render) + x11vnc on
127.0.0.1:5920. x11vnc refuses to start while `WAYLAND_DISPLAY` is set in the host env — start it
with `env -u WAYLAND_DISPLAY XDG_SESSION_TYPE=x11`. Xvfb has no DRI3, so EGL falls back to
software (libEGL warnings in every run); that is expected and good for deterministic comparisons,
but it means no GPU acceleration.

Windows reference: CSP 5.1.4 installs **silently** into the guest with
`F:\CSP_514w_setup.exe /s` (F: = the attached `sources/media/csp_media.iso`), landing at
`C:\Program Files\CELSYS\CLIP STUDIO 1.5\CLIP STUDIO PAINT\CLIPStudioPaint.exe` (+ LipExt.exe,
scan\scan.exe, updater\CLIPStudioUpdater.exe). The pinned WebView2 135.0.3179.85 installer refuses
to install over the guest's WebView2 154.0.4258.53 (exit -2147219187); the 135 pin is a Wine-side
workaround, so the guest is left on 154.

## Milestone: installs on both platforms (2026-10-03 ~19:15 host)

- **Windows reference**: `F:\CSP_514w_setup.exe /s` -> rc 0, 559.6 MB, `CLIPStudioPaint.exe`
  FileVersion **5.1.4.0**, plus `CLIP STUDIO\CLIPStudio.exe` launcher. Launched it: process
  `CLIPStudioPaint` 186 MB, window title `CLIP STUDIO PAINT`, Responding=True, and it shows the
  first-run **Privacy Settings** dialog ("Please help us to improve Clip Studio / Help fix errors /
  Improve services"). Screenshot: `evidence/win_csp_launch.png`.
- **Wine**: `wine-install/bin/wine CSP_514w_setup.exe /s` in the provisioned prefix -> **rc 0 in
  203 s**, 566 MB at `drive_c/Program Files/CELSYS/CLIP STUDIO 1.5/CLIP STUDIO PAINT/`, including
  `CLIPStudioPaint.exe`, `ClipPreview.dll`, `LipExt.exe`, `OpenAL32.dll`, `ailia*.dll`,
  `PlugIn/`, `Settings/`, `api-ms-win-core-*` stubs.
  Installer log notes: `regsvr32: Successfully registered DLL ...ClipPreview.dll` and
  `regsvr32: Failed to register DLL ...LipPreview.dll`; repeated
  `ole:std_release_marshal_data could not map object ID to stub manager` +
  `CoReleaseMarshalData ... 0x8001011d` (noise from the installer's COM objects, not fatal).
  Full logs: `logs/csp_install_wine.log`, `logs/csp_install_stdout.log`.

## MAJOR MILESTONE: CSP opens on Wine, same dialog as Windows (2026-10-03 ~19:30 host)

`wine-install/bin/wine CLIPStudioPaint.exe` -> process runs, main window `CLIP STUDIO PAINT`
(800x600 @ 560,240) plus an unnamed 1194x834 child render surface, plus the expected **1x1 helper
windows** (0x1400014/13/15/b = `clipstudiopaint.exe` 1x1+0+0) that the AppDB comment describes,
plus a `DXGI device window`.

Rendered screen at that point: 722 unique colours, CSP dark-theme palette. OCR of the window reads
the **Privacy Settings** dialog verbatim and identically to the Windows reference:

```
CLIP STUDIO PAINT        x
Privacy Settings
Please help us to improve Clip Studio.
You can change this at any time from File > Privacy Settings.
Help fix errors
If an error occurs, automatically send anonymous information about the incident.
This helps us resolve bugs and errors.
Improve services
Automatically sends information about features that you use.
This helps us to improve user experience and develop new features.
```

Evidence: `evidence/wine_csp_privacy_dialog.png`, `evidence/wine_csp_launch3.png`,
Windows side `evidence/win_csp_launch.png`.

### Two bugs found and fixed on the way (both must stay documented)

1. **DXVK shadowed the patched dcomp/dxgi.** With winetricks `dxvk` installed, DXVK's `dxgi.dll`
   takes over and logs `DxgiFactory::CreateSwapChainForComposition: Not implemented` forever; CSP's
   composition path then draws nothing and the window is a blank white rectangle (2 colours on
   screen). The dcomp patch set we apply is *only* effective with Wine's own `dxgi`. Fix:
   `tools/disable_dxvk.sh` (wineboot -u to restore builtins + pin `dxgi d3d8 d3d9 d3d10core d3d10_1
   d3d11 d3d12 d3d12core dcomp` to `builtin`). **Do not "fix" a blank CSP by installing DXVK.**
2. **`win8.1` is not a valid Wine version string.** `reg add ... /d win8.1` is rejected by
   `err:ver:parse_win_version Invalid Windows version value L"win8.1"` and the app silently stays on
   the global win10 (which is WineHQ bug 58254's crash condition). Use **`win81`**.
   Corrected in `tools/mkprefix.sh`.
   Also: deleting `d3d11.dll` etc. from the prefix `system32` breaks startup
   (`status c0000135`) because those are Wine's own builtin modules — restore with `wineboot -u`.

### Next parity gap: the licensing/start page is blank on Wine

Windows, after dismissing Privacy Settings with its **OK** button (found at guest pixel 926,608 on
the 1280x800 console; clicked with `tools/vmclick.py`), shows the licence/start page:

```
Draw and create with Clip Studio Paint
From $4.49/month
Perpetual license from $63.00
Already have a plan?
```

On Wine the same stage is a **perfectly uniform (78,78,78) rectangle with no text** — the classic
"blank dialog" from the AppDB. Diagnosis so far:
- the prefix's WebView2 is the **115.0.1901.200** the CSP installer itself bundled, and
  `msedgewebview2.exe` is **never running** while CSP is up (nothing in the CSP log mentions it);
- wine-gecko was never actually installed (`system32/gecko/` holds only `plugin/npmshtml.dll`, no
  `wine_gecko/`), so the MSHTML fallback engine is missing too.
Action: install the pinned **WebView2 135.0.3179.85** (already downloaded) into the prefix and
install wine-gecko, then re-check. This is the documented CSPenguin remedy.

## MILESTONE 2: the WebView2 start/licensing page renders on Wine (2026-10-03 ~19:45)

Installing the pinned **WebView2 135.0.3179.85** into the prefix
(`wine sources/media/MicrosoftEdgeWebView2RuntimeInstallerX64.exe /silent /install`, rc 0, registry
`HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-...}` -> pv 135.0.3179.85)
**is what makes CSP's start page render**. With the 115.0.1901.200 build that CSP's own installer
bundles, that page was a perfectly uniform (78,78,78) rectangle with no text and
`msedgewebview2.exe` never started.

After the install, clicking the Privacy Settings OK button (screen 1245,809 — found by scanning for
bright rectangles, not by OCR) gives a fully rendered page: 121473 unique colours and OCR reads

```
CLIP STUDIO PAINT
Draw and create with Clip Studio Paint
Purchase a plan to use all features!
First time subscribers get 3 months free
Already have a plan?
```

The Windows guest at the same stage reads the same page ("Draw and create with Clip Studio Paint",
"Already have a plan?"); the middle lines differ only because the offer copy/scroll position differs
(`From $4.49/month / Perpetual license from $63.00` on the guest for that load).

Evidence: `evidence/wine_csp_license.png` (Wine) and `evidence/win_csp_license.png` (Windows).

### Practical guidance that follows from this
- `xdotool` clicks land in **screen** coordinates; a coarse ASCII/brightness scan is the reliable way
  to find a button in CSP's dark UI (the button was a 229x47 bright rect at x 1131-1360, y 786-833).
- OCR needs the specific recipe: `convert -colorspace Gray -normalize -resize 150-200%` then
  `tesseract --psm 6`. Raw OCR of the screenshot returns nothing on CSP's dark theme.

## Deliverable state (2026-10-03 ~19:50 host)

Patch set restructured and re-verified:
- `patches/local/` now contains ONLY CSP-exclusive material: `dcomp-staging/` (67 patches, applied)
  and `candidates/` (NOT applied by default).
- Three patches from the *Eos* project (`0100-msi-class-registry-view`,
  `0101-services-service-logon-token`, `0102-iphlpapi-notify-interface-changes`) had been copied
  into `patches/local/` earlier by mistake and were **removed** — they are not part of the
  AutoCAD+Power BI base the task specified and must not be presented as CSP patches.
- `0100-mf-encoder-support.patch` moved to `patches/local/candidates/` because it fails 7/21 hunks
  on a pristine 11.18 and would break a fresh build.
- `tools/apply_patches.sh --check` rewritten: it now **extracts the pristine tarball** into a
  scratch dir and applies the whole series for real. The old dry-run-per-patch form cannot work for
  a cumulative series (false FAILs), and reverse-dry-run cannot detect "already applied" once later
  patches have moved the same context.
- Result on pristine `wine-11.18.tar.xz`: **86 OK / 0 FAIL** (`logs/patch_check3.log`).

Docs written: `README.md`, `FINDINGS.md`, `patches/README.md`, `docs/SETUP_RECIPE.md`,
`docs/TIMELAPSE.md`, `docs/NEXT_STEPS.md`, `patches/local/candidates/README.md`.

## Terminal blocker (needs a human decision)

CSP 5.1.4 gates the editor behind a Clip Studio account. **The Windows reference VM has the same
gate** — it also shows the licence/start page — so the three AppDB issues cannot be reproduced on
either side without credentials. This is not a Wine defect: the login UI renders and accepts input
correctly under Wine.

## Final verified state (2026-10-03 ~20:00 host)

Editor `CLIPStudioPaint.exe` running under the built Wine (pid shown by `pgrep -f CLIPStudioPaint`),
**0 `err:`/`fixme:` lines** in `logs/csp_run.log` (excluding the expected Xvfb `libEGL`/DRI3 noise).
Screen shows 162 748 distinct colours and the WebView2 **"Log into Clip Studio"** form *including its
own client-side validation error* ("Please check your email address and password is correct") after
submitting an empty form — i.e. WebView2 rendering, HTML forms and JS validation all work under Wine.
Evidence: `evidence/wine_final.png`, `evidence/wine_csp_login_validation.png`.

Note when scripting clicks: openbox places the CSP window at a different position run to run, so the
dialog buttons move (Privacy Settings OK was at (1245,809) in one run and (1245,562) in another).
Always re-scan for the bright rectangle rather than reusing coordinates.

## Session close (2026-10-03 ~20:30 host)

Deliverable is complete for the agreed stopping point (user chose "stop at verified parity").

Verified end state, re-checked at close:
* `sources/wine/wine-11.18/dlls/dcomp/` has `device.c surface.c target.c visual.c` (patched);
  `wine-install/lib/wine/x86_64-windows/dcomp.dll` = 1 508 005 B, i386 = 1 287 755 B.
* Patch set applies 86/86 from a pristine tarball (`logs/patch_check3.log`).
* Editor runs: `CLIPStudioPaint` process up, window `CLIP STUDIO PAINT` 800x600, screen shows the
  WebView2 start page ("Draw and create with Clip Studio Paint / Purchase a plan to use all
  features! / First time subscribers get 3 months free / Already have a plan?") and
  **0 `err:`/`fixme:` lines** in `logs/csp_run.log` (Xvfb libEGL noise excluded).
  Evidence: `evidence/wine_final2.png`.
* A/B proof recorded: 120 838 colours with the dcomp patch set vs 2 without it.
* Launcher: findings corrected and retracted in `FINDINGS.md` §10.

Blocked by the Clip Studio licence gate (documented, not worked around): the three AppDB issues and
the WINEDEBUG/relay-level API diff that would drive their patches. The Windows launcher exposes
**Use Activation Code**, so a licence key would unblock them without a web account.
