# Hog PC 5.2.1.31 on Wine — findings

One milestone per result, with the measured evidence and the command that produced it.

## M1 — The download is a single MSI: WiX 3.14, 32-bit package, Qt5/QML + QtWebEngine
`Hog_PC_5.2.1.31.zip` (363 261 314 B) contains exactly one member, `Hog_PC_5.2.1.31.msi`
(365 039 616 B), expanded to `/run/media/asdf/Windows/hog-media` (NTFS).

`msiinfo suminfo` → `Application: Windows Installer XML Toolset (3.14.1.8722)`,
**`Template: Intel;1033`** (a **32-bit x86 package**), `Subject: Hog PC`,
`Author: High End Systems, Inc.`.
`msiinfo export … Property` → `ProductName=Hog PC`, `ProductVersion=5.2.1.31`,
`ProductCode={6501E546-28F5-4A0E-97E0-1CD914185417}`, `UpgradeCode={227A08B6-20D8-4CE2-9B1D-36C593C8BF0E}`,
`ALLUSERS=1`, `ARPNOMODIFY/ARPNOREPAIR`, and **`HASPEXISTS`** among the `SecureCustomProperties`
(Sentinel HASP licensing), plus certificate custom-action properties.

`msiinfo export … Feature`:
| feature | title | level |
|---|---|---|
| `DefaultFeature` | Hog PC — "Software,Drivers and Documentation" | 1 |
| `Install_x64` | Hog PC x64 Drivers (x64 USB Drivers) | 0 |
| `Install_ARM64` | Hog PC ARM64 Drivers | 0 |
| `VizFeature` | Hog Visualizer Connectivity | 1 |

`msiinfo export … Directory` → install root `ETCROOT\HogPC` (`D_HogPC = ETCROOT\HogPC`), a `VizFolder`
("Hog Connectivity"), `drivers`, `preferences`, `resources`, and the Qt plugin trees
`QtQml`, `QtQuick.2`, `Controls.2`, `Templates.2`, `Models.2`, `WorkerScript.2`, `platforms`,
`imageformats`, `iconengines`, `sqldrivers`, `webview`. 2847 files.

`msiinfo export … File` → executables:
`launcher-win32-golden.exe`, `desktop-win32-golden.exe`, `server-win32-golden.exe`,
`monitor-win32-golden.exe`, `dp8k-win32-golden.exe`, `vob-win32-golden.exe`,
`ltc_display-Win32-golden.exe`, `netservices-win32-golden.exe`, `dialogue-win32-golden.exe`,
`critical-win32-golden.exe`, `lock-win32-golden.exe`, `Widget_Upgrader-Win32-golden.exe`,
`miniwing_test-Win32-golden.exe`, `GadgetDrvChange.exe`, **`haspdinst.exe`**, **`QtWebEngineProcess.exe`**.
Libraries: **Qt5** — `Qt5Core/Gui/Qml/Quick/QuickWidgets/Network/NetworkAuth/Sql/Svg/Xml/XmlPatterns/
Script/Scxml/Test/PrintSupport/WebSockets/Pdf` and **`Qt5WebEngineWidgets`** with the Chromium payload
(`QtWebEngineProcess.exe`, `qtwebengine_resources.pak`, `qtwebengine_devtools_resources.pak`).

So the application is a **Qt5/QML desktop app that embeds Chromium via QtWebEngine** — the component the
owner flagged as "if the app uses a browser … you can get the source and trace the source to win32 calls
without decompilation". `haspdinst.exe` is the Sentinel HASP runtime, consistent with the owner's note
that extra features unlock when hardware (which carries a licence dongle) is connected.

## M2 — Patch base
`wine-11.18/` carries `patches/series/0001..0019` (the AutoCAD-on-Wine 14 + Power BI-on-Wine 5 base the
owner asked for) **and all three patches from the sibling projects**, which the owner suggested reusing:
`0100-msi-class-registry-view.patch`, `0101-services-service-logon-token.patch`,
`0102-iphlpapi-notify-interface-changes.patch`. All 22 apply cleanly
(`tools/apply_patches.sh wine-11.18` → all `OK`). `wine-install/` is the identical built Wine copied
from `eos-wine` (`wine --version` → `wine-11.18`); a fresh build of this project's own tree is deferred
until a Hog-specific patch is needed. **Every patch used by this project is in `patches/` and documented
in `patches/README.md`.**

## M3 — Hog PC installs with exit 0 and the full console UI opens under Wine
Install: `tools/mkprefix.sh --fresh --stage all` with `wine-install` → win64 prefix, Windows-10 version,
core fonts, and

```
wine msiexec /i Hog_PC_5.2.1.31.msi /qn /norestart /L*v C:\hog_msi.log     -> rc=0
```
installs **577 MB** to `C:\Program Files (x86)\ETC\HogPC` (as expected for the Intel/32-bit package)
plus `C:\ProgramData\ETC\HogPC` (help text, resources, fixture library) and
`Documents\ETC\HogPC\{Shows,Logs,Exports,Reports}`. Start-Menu shortcut "Hog PC" → `launcher-win32-golden.exe`.

Run (`tools/run_hog.sh hog1 --secs 180 --iv 15`, then driven interactively):

| step | result |
|---|---|
| launcher | window **`"Hog Start"` 792x338** appears by t=15 s and stays; process alive throughout |
| its UI (OCR) | `Hog Start` · `Control Panel` · `+ New File` · `Show Browser / Browse` · `Hog PC` · `Version: v5.2.1 (b31)` · `No Show found` · `HN IP: 127.0.0.1` · `FN IP:` · `Date: 3 October 2026` |
| clicking `+ New File` | a **`"New Show"` dialog (658x477)** appears (`Look In: Shows`, `Created`/`Modified` columns, `Finish`/`Cancel`) |
| clicking `Finish` | show created (`Documents\ETC\HogPC\Shows\NewShow\{hog_ident.json,hogdatabase.mk2,blackbox/}`), and two processes start: **`server-win32-golden -port=6600 -netnum=1 -showpath=… -showname=NewShow`** and **`desktop-win32-golden -port=6600 -nodeid=1 -netnum=1`** |
| server | **listening on `0.0.0.0:6600`** |
| desktop | window **`"Hog PC - Primary Screen"` 1288x799**, `Map State: IsViewable`, and the console UI renders (OCR: `HOG`, `Palettes / Master / Programmer / Output`, `Copy Size Move Max Focus Chose`, `Knock Out / Flip / Unblock / Renumber / Back Up`, `Grand / Select / Segments / Touch / Suck / Undo / Redo / Park`, `UserA`, `1: Page 1 Programmer`, clock) |

**Zero `err:` lines** in the whole launcher run. The only `fixme`s seen, and their assessment:

| fixme | assessment |
|---|---|
| `file:NtLockFile` (5×) | **implemented** in `dlls/ntdll/unix/file.c:7112` — the message is incidental; the show database's locking is not stubbed out |
| `netprofm:init_networks` | `dlls/netprofm/list.c:1844` exists but has a FIXME inside; affects network-profile reporting, not start-up |
| `setupapi:DiInstallDriverA` | `dlls/newdev/main.c:154` is a deliberate stub returning TRUE — relevant only to installing the USB **hardware** drivers, which this project does not need |
| `ntdll:NtQuerySystemInformation SYSTEM_PERFORMANCE_INFORMATION` | cosmetic (`unix/system.c:3403`) |
| `system:EnableNonClientDpiScaling`, `win:RegisterPowerSettingNotification`, `wtsapi:WTSQuerySessionInformationW`, `font:get_nearest_charset`/`find_matching_face` | benign |

**No HASP runtime is installed and no lighting hardware is connected** — the MSI only does an
`AppSearch` on the `HaspVersion` signature (`HASPEXISTS`), and `haspdinst.exe` ships but is never run.
The base application reaches its full console UI anyway, which matches the owner's description: the
licence/hardware gate applies to *additional* functionality, not to starting the app.

Evidence: `evidence/hog_desktop_root.png` (root capture — the desktop UI is GL/Qt-composited, so
per-window `import -window` comes back blank), `evidence/hog_launcher_wine.png`,
`evidence/hog_desktop_wine.ocr.txt`, `logs/runs/hog1/`.

## M4 — Behaviour parity with Windows, and one real Wine bug found in the offline Processor
Agent `HogApiDiff` (`docs/API_DIFF.md`) built a 32-bit port of our IAT tracer (Hog is i386) and diffed
launcher → show creation → desktop on both sides:

> *"Hog PC's start-up diverges nowhere on Wine that stops, blocks or corrupts it. Locking of the show
> store is identical (1574 `LockFileEx`/`NtLockFile` pairs on Windows vs 1584 on Wine for the same
> show-open burst, all success on Wine). No start-up-critical call is missing in the launcher-vs-launcher
> diff; both sides end idle at `Hog Start`. No stall on either side."*

The launcher control set matches Windows (OCR of the Wine window: `Hog Start`, `Control Panel`,
`+ New File`, `HOG`, `Show Browser`, `Launch Show`, `Hog PC`, `No Show found`, `Version: v5.2.1 (b 31)`,
`HN IP: 127.0.0.1`, `FN IP:`, `Date: 3 October 2026`, `Start`). Clicking `Processor` (Windows: "Start
Processor") spawns `monitor-win32-golden -port=6600 -netnum=1` and its window appears at **exactly the
Windows geometry (770x370)**. `docs/PARITY.md` has the full side-by-side.

**The one real divergence (and it is a Wine bug).** `monitor-win32-golden.exe`'s `Processor` window is
created correctly — `Qt5151QWindow`, 770x370, style `0x96000000`, `IsViewable`, unoccluded — but its
contents are **never painted** (window and screen come back pure black/white; OCR empty), with **zero
`err:` lines**. Agent `HogMonitorRenderRE` (`docs/MONITOR_RENDER_RE.md`) traced it:

- Wine's `+relay` of the hwnd shows the whole window-proc stream —
  `WM_NCCREATE WM_NCCALCSIZE WM_CREATE WM_SIZE WM_MOVE WM_WINDOWPOSCHANGING WM_WINDOWPOSCHANGED
  WM_SETICON WM_SETTEXT WM_SHOWWINDOW WM_QUERYNEWPALETTE WM_ACTIVATEAPP WM_NCACTIVATE WM_ACTIVATE
  WM_IME_SETCONTEXT WM_SETFOCUS WM_NCPAINT WM_ERASEBKGND` — and **no `WM_PAINT` at all** (30 s capture).
- Counters under Wine: `BeginPaint 0, EndPaint 0, GetUpdateRect 0, InvalidateRect 0, UpdateWindow 0,
  RedrawWindow 0, ValidateRect 0`. **Windows, same exe/argv: `BeginPaint 1` + `EndPaint 1`.**
- The window *is* a valid paint target: `GetUpdateRgn` continuously returns
  `SIMPLEREGION box=(0,0)-(770,370)`, `Visible=1`, and `ValidateRect(NULL)` clears it while
  `RedrawWindow(RDW_INVALIDATE)` re-invalidates it — still no queued `WM_PAINT`.
- The **app is fine**: `PostMessage(hwnd, WM_PAINT, 0, 0)` or
  `RedrawWindow(RDW_INVALIDATE|RDW_UPDATENOW|RDW_ERASE|RDW_ALLCHILDREN)` paints the complete UI
  immediately. Only the *queued* path is broken; the *synchronous* paths work.

So Wine never generates the initial queued `WM_PAINT` that Windows does for a newly shown window. The
agent named the sites: `server/queue.c` `DECL_HANDLER(get_message)`'s "now check for WM_PAINT" branch
(`queue->paint_count && … && find_window_to_repaint(...)`), `server/window.c`
`find_window_to_repaint()`/`win_needs_repaint()`, `dlls/win32u/window.c` `set_window_pos()`'s
"Give newly shown windows a chance to redraw" block (~4197, `erase_now()` emits only
`WM_NCPAINT`/`WM_ERASEBKGND`), and `dlls/win32u/dce.c` `redraw_window()`/`erase_now()` vs the synchronous
`update_now()`. It is **not** the Power BI occlusion gap (that one is a painted window never re-damaged);
here the window was never painted once.

A minimal native repro with the same owner/style/`ShowWindow` sequence *does* get its `WM_PAINT`, so the
trigger involves per-process state of the monitor. Fix being written as
`patches/local/0103-*` (`docs/INITIAL_PAINT_PATCH.md`).

## M5 — Patch `0103` fixes the never-painted window (verified), with no regression
`patches/local/0103-win32u-initial-client-paint.patch` — `dlls/win32u/window.c` `set_window_pos()`: on the
hidden→visible transition (the same block that already calls `erase_now()`), also force the window's
first client paint (`NtUserRedrawWindow(hwnd, NULL, NULL, RDW_INVALIDATE|RDW_ERASE|RDW_UPDATENOW)`), the
way Windows observably paints a newly shown window. Applied to `wine-11.18` and `wine/wine-11.18`,
incremental rebuild (`win32u.dll` i386 + x86_64 rebuilt).

**Result — the `Processor` window now paints.** Same window, same geometry (770x370), but 370 colours
instead of 1, and OCR:

```
Net Num                     Show Server IP:   No Server
Info                        Hog Net IP:       Not Resolved
                            Fixture Net IP:   Not Resolved
                            Port Number:      0
                            Software Version: v5.2.1 (b 31)
                            Lock   Touchscreens   Quit
```
(Windows: `Show Server IP: No Server`, Hog/Fixture Net IP, `Offline`, `Port Number: 6600`,
`Software Version: v5.2.1 (b 31)`, Lock/Touchscreens/Quit. The `Port Number: 0` / `Not Resolved` values
are state — this processor was started without a running show server, exactly as `No Server` says.)

**No regression.** Full flow re-run on the patched build: launcher (`Hog Start` renders) → `New Show`
dialog → `Finish` → **all four processes** (`launcher`, `server-win32-golden -port=6600`,
`critical-win32-golden`, `desktop-win32-golden`) → console window `Hog PC - Primary Screen` (1288x799)
rendering (3217 colours) with OCR `HOG · Palettes § Master Programmer Output · Views · NewShow (2) ·
User A · Copy/Size/Move/Max/Focus`. **Zero `err:` lines.**

Console OCR note: this dark, stylised UI needs tuned preprocessing — the reliable recipe is
`convert <root crop> -resize 300% -colorspace Gray -threshold 35%` then `tesseract --psm 11`
(saved in `evidence/hog_desktop_wine.ocr.txt`); plain normalisation often returns nothing.

**Risk noted when the patch lands** (from `docs/INITIAL_PAINT_PATCH.md`): the first `WM_PAINT` is now
sent from inside `SetWindowPos`/`ShowWindow` (the same place Wine already sends `WM_NCPAINT`/
`WM_ERASEBKGND`/`WM_WINDOWPOSCHANGED`, and where Windows paints a newly shown window), and
`CreateWindowEx(WS_VISIBLE)` goes through the same block — worth watching for apps whose window procs
assume no paint until the message loop runs. Hog (all four processes) and the minimal
`tools/winenum/showpaint3.exe` probe behave correctly on this build.
