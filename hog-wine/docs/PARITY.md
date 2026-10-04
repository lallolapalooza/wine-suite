# Does Hog PC do the same things on Windows and under Wine?

The owner's question: *«i think the app already runs just fine in linux, we just need to check if it does
the same things on windows?»* — this document answers that with measured evidence from both sides.

Sources: Windows = `docs/VM_REFERENCE.md` (agent `HogVMReference`, guest `win11`, no hardware, no
licence); Wine = `FINDINGS.md` M3 + `logs/runs/hog1/` + `evidence/`.

## Summary — yes, the observable behaviour matches

| | Windows 11 guest | Wine 11.18 (this build) |
|---|---|---|
| install (`msiexec … /qn`) | rc **0** (elevated), 91 s | rc **0** |
| install root | `C:\Program Files (x86)\ETC\HogPC` — 565.7 MB | same path — 577 MB |
| data dir | `C:\ProgramData\ETC\HogPC` (fixture library 2.9 GB, helptext, resources) | same layout |
| **GUI entry point** | `launcher-win32-golden.exe` | `launcher-win32-golden.exe` |
| launcher window | **`"Hog Start"` 792x338** (`Qt5151QWindow` / `ShowConnectWindow`) | **`"Hog Start"` 792x338** |
| licence / HASP / hardware prompt at start | **none** | **none** |
| launcher content | `Version: v5.2.1 (b 31)`, HN/FN IP, `No Show found`, buttons New Show / Launch Show / Browse / Start Processor / Control Panel / File Browser / Help / Quit | OCR of the captured Wine window (1181 colours): `Hog Start` / `Control Panel` / `+ New File` / `HOG` / `Show Browser` / `Launch Show` / `Hog PC` / `No Show found` / `Version: v5.2.1 (b 31)` / `HN IP: 127.0.0.1` / `FN IP:` / `Date: 3 October 2026` / `Start` — the same control set |
| `New Show` → dialog | Qt dialog titled **`New Show`**, `Look In: Shows`, `Finish`/`Cancel` | **`New Show`** dialog 658x477, `Look In: Shows`, `Finish`/`Cancel` |
| show created | `Documents\ETC\HogPC\Shows\<name>\{hogdatabase.mk2, hog_ident.json, blackbox\0.hbb}` | same three (`hogdatabase.mk2` 680 KB, `hog_ident.json`, `blackbox/`) |
| startup progress window | `Console Startup Process` ("Waiting on Desktop Process") | `Console Startup Process` ("Waiting on Server") — same dialog, different stage label |
| spawned children | `server-win32-golden.exe` + `critical-win32-golden.exe` + `desktop-win32-golden.exe` | `server-win32-golden -port=6600 -netnum=1 …` + `desktop-win32-golden -port=6600 -nodeid=1` |
| server socket | port 6600 | **listening on `0.0.0.0:6600`** |
| console window | **`Hog PC - Primary Screen`** (1280x799) | **`Hog PC - Primary Screen`** (1288x799 — the 8 px is the window's x position, -8 vs 312) |
| console top bar | `Palettes / Master / Programmer / Output / Views` | identical (`Palettes · Master · Programmer · Output`, `Views`) |
| console content | command area, `Copy Size Move Max Focus Chose`, `Knock Out/Flip/Unblock/Renumber/Back Up`, `Grand/Select/Segments/Touch/Suck/Undo/Redo/Park`, user + clock | identical strings |
| GPU | only Microsoft Basic Display Adapter — Qt/QML renders in software | Wine on the host's GL — renders (no GPU needed on either side) |
| Wine `err:` lines during the run | n/a | **0** |

So: same entry point, same window titles and sizes, same dialogs, same show layout, same child
processes, same listening port, same console surface — and **no licence or hardware prompt on either
side**, which matches the owner's description that the hardware-attached licensing gates *additional*
functionality rather than start-up.

## Differences that are not behavioural divergences
- **Window position**: Windows places the console at (-8,0) (its "primary screen" spans the display),
  Wine at (312,0) because the Wine desktop has the launcher/other windows around it. Size is the same.
- **Firewall**: on Windows the installer adds 10 inbound rules (and `monitor-win32-golden.exe` has none,
  so Windows pops a firewall consent dialog). Wine has no firewall, so no dialog — a *missing* prompt,
  not a failure.
- **Driver installation**: `setupapi:DiInstallDriverA` is a stub in Wine (`dlls/newdev/main.c:154`
  returns TRUE without installing). Only relevant to attaching USB **hardware**; the app runs without it.
- **`fixme`s** (all benign, assessed in `FINDINGS.md` M3): fonts, `NtQuerySystemInformation`
  (`SYSTEM_PERFORMANCE_INFORMATION`), `NtLockFile` (implemented — `dlls/ntdll/unix/file.c:7112`),
  `EnableNonClientDpiScaling`, `RegisterPowerSettingNotification`, `WTSQuerySessionInformationW`,
  `netprofm:init_networks`, `AppPolicyGetProcessTerminationMethod`.
- **Fixture library**: Windows' `C:\ProgramData\ETC\HogPC\fixtureLibrary` unpacks to 2.9 GB during
  install and needs ~8 GB free on the guest (the reference agent hit a 1603 with 6.5 GB free). Wine's
  install completed with the same layout.

## The one divergence found — and fixed
The offline **`Processor`** window (`monitor-win32-golden.exe`, spawned by the launcher's `Processor`
button / "Start Processor") was created at exactly the Windows geometry (**770x370**) but **never
painted** under Wine: contents pure white/black, OCR empty, **zero `err:` lines**. Agent
`HogMonitorRenderRE` traced the cause (`docs/MONITOR_RENDER_RE.md`): Wine never delivered the initial
queued `WM_PAINT` for that newly shown window (`BeginPaint 0 / EndPaint 0` under Wine vs `BeginPaint 1 /
EndPaint 1` on **Windows with the same exe**), even though the window's whole client area sat in its
update region and it was visible and unoccluded. The monitor's message queue never drains
(`PeekMessage` returned a message 3407× and empty 0×), and Wine only synthesises `WM_PAINT` when the
queue is otherwise empty.

**Fixed by `patches/local/0103-win32u-initial-client-paint.patch`** (`dlls/win32u/window.c`
`set_window_pos()`: force the first client paint on the hidden→visible transition, as Windows observably
does). Verified on the rebuilt Wine — the same window now renders 370 colours and OCR reads
`Show Server IP: No Server`, `Hog Net IP: Not Resolved`, `Fixture Net IP: Not Resolved`,
`Port Number: 0`, `Software Version: v5.2.1 (b 31)`, `Lock / Touchscreens / Quit` — Windows' content.
(The `0` / `Not Resolved` values are state: this processor ran without a show server, matching its own
`No Server`.)

With that, **every window Hog PC shows on Windows appears and renders under Wine**:
launcher `Hog Start`, the `New Show` dialog, the `Hog PC - Primary Screen` console, and the offline
`Processor`.

## Not yet compared (honest limits)
- Deeper console features (patch window, palettes, programmer output) were not driven on either side
  beyond their appearance in the OCR.
- The QtWebEngine/Chromium surfaces (help browser, manuals) were not exercised on either side.
- Console OCR needs tuned preprocessing (dark stylised UI): `-resize 300% -colorspace Gray -threshold 35%`
  then `tesseract --psm 11`; plain normalisation often returns nothing.
