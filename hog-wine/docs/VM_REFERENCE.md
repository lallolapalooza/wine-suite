# Windows reference — Hog PC 5.2.1.31 on Windows 11 (guest `win11`)

Ground truth captured from a real Windows 11 guest (10.0.26200, user `adsf`, KVM/libvirt domain
`win11`, QXL/Microsoft Basic Display Adapter, no lighting hardware, no HASP key). This is the
behaviour the patched-Wine build has to match.

Host: `/home/asdf/projects/hog-wine`, `source env.sh`.
Guest command channel: `tools/vm/vmcmd.sh '<ps>'` (UAC-filtered, medium integrity) and
`tools/vm/vmcmda.sh -f <script.ps1>` (elevated loop). Screenshots: `virsh screenshot win11 x.ppm`
+ `tesseract`. Mouse/keys: `tools/vm/vmclick.py`, `virsh send-key win11 KEY_...`.

> Channel gotcha: scripts sent through the channel are `Invoke-Expression`d **in the runner's own
> scope**, so a script that assigns `$out` (or `$raw`/`$res`/`$o`/`$in`/`$U`) clobbers the runner
> and wedges the loop. All `tools/vm/hog_*.ps1` deliberately avoid those names. The old
> `C:\Users\adsf\vm_admin.ps1` loop was killed by this bug; it was replaced by
> `tools/vm/vm_admin2.ps1` (uniquely-named internals), relaunched with `tools/vm/elev.sh`.

## 1. Media and payload

| Item | Value |
|---|---|
| Zip download | `/home/asdf/Downloads/Hog_PC_5.2.1.31.zip` |
| MSI | `Hog_PC_5.2.1.31.msi`, 365 039 616 bytes |
| MSI sha256 | `29aae8efc9639462252ace17e4d359116affe3b2e68df193b7e7e80034ffcac2` |
| ProductName / Version | `Hog PC` / `5.2.1.31` (v5.2.1 b31) |
| ProductCode | `{6501E546-28F5-4A0E-97E0-1CD914185417}` |
| UpgradeCode | `{227A08B6-20D8-4CE2-9B1D-36C593C8BF0E}` |
| Package | WiX 3.14, `Template: Intel;1033` → **32-bit MSI**, `ALLUSERS=1`, single cab `HogPCCabinet.cab` |
| Features | `DefaultFeature` (L1), `Install_x64` (Level 1 via Condition `VersionNT64 AND NOT WIX_NATIVE_MACHINE="43620"`), `Install_ARM64` (only when `WIX_NATIVE_MACHINE=43620`), `VizFeature` (L1) |
| SecureCustomProperties | `ARPNOMODIFY;ARPNOREPAIR;HASPEXISTS;NEWERVERSIONBEINGDOWNGRADED;OLDERVERSIONBEINGUPGRADED;WIX_NATIVE_MACHINE` |
| `HASPEXISTS` | AppSearch property from RegLocator on `HKLM\SOFTWARE\Aladdin Knowledge Systems\HASP\Driver\Installer\Version`. On this guest it was already `9.16.156120.1` (HASP driver pre-installed before Hog, `akshasp/akshhl/aksusb.inf` → `C:\Windows\INF\oem2/3/4.inf`), so it was satisfied from the very first run. Nothing to pass on the command line. |

`CustomAction` highlights: deferred `WixQuietExec64` driver installs (`Install_umdmx_x64`,
`Install_umltc_x64`, `Install_umprowing_x64`, `Install_umupload_x64`, `Install_kmh4touch_x64`,
`Install_umblk_x64` → `pnputil /add-driver … /install` via `Install-Driver.ps1`); firewall
exceptions (`ExecFirewallExceptions`, 10 inbound-allow rules); `SA_FixLib_Unpack` (VBScript +
`7ZA.EXE` unpacking the fixture library); `Install_HASP` (VBScript ShellExecute of
`haspdinst.exe -i -kp -nomsg` — declared in the CustomAction table but **not scheduled** in
`InstallExecuteSequence`, so it never ran under `/qn`).

## 2. Getting the MSI into the guest + the install command

Transfer was plain HTTP (the host `vmserv.py` on `0.0.0.0:8000` serves the project `vmshare/`; the
guest reaches it at `http://192.168.122.1:8000/`). No ISO needed.

```powershell
# in the guest (elevated)
New-Item -ItemType Directory -Force -Path C:\hog | Out-Null
curl.exe -s -o C:\hog\Hog_PC_5.2.1.31.msi http://192.168.122.1:8000/Hog_PC_5.2.1.31.msi   # 3.4 s, 365039616 bytes
```

The install command that worked (elevated, ~91 s, exit code **0**):

```powershell
msiexec /i C:\hog\Hog_PC_5.2.1.31.msi /qn /norestart /L*v C:\hog\hog_msi2.log
```

* No extra MSI properties were needed — the plain `/qn` command line installs everything.
* `HASPEXISTS` does **not** need to be passed (it was already set by AppSearch from the guest's
  pre-existing HASP driver). `haspdinst.exe` is installed as a *file* (v8.31.58072.1, 25.9 MB) but
  the package's `Install_HASP`/`Enable_HASP` custom actions are **not scheduled** in the execute
  sequence, and neither run's log shows `haspdinst` ever executing — so a silent `/qn` install does
  **not** install or refresh the HASP driver.
* Run it **elevated** (the guest user is a UAC-filtered admin, so a plain shell returns 1603).

### The one hard requirement: disk space

First attempt, guest C: free **6.554 GB** → `MSI_RC=1603` after 94 s. The failure is
`SA_FixLib_Unpack`: the fixture library is *not* a small file — `fixturelib.hog5lib` (136 903 059 B,
gzip) unpacks to a 2 919 501 312 B tar whose single 2 904 825 856 B member `hogdatabase.mk2` is then
extracted in place, so the step needs ~5.8 GB **peak** on top of the ~0.6 GB install + 0.36 GB MSI
cache. With 6.55 GB free it filled the volume during the second extraction and returned 3 → 1603
with rollback (leaving 4.44 GB of debris in `C:\ProgramData\ETC\HogPC`).

After freeing space (deleted that debris plus the old Eos Family install, `C:\apitrace`), free was
**7.903 GB** and the identical command returned **0** in 91 s. Peak measured: 7.903 GB → 3.180 GB
free. **Rule of thumb: give the guest ≥ 8 GB free before installing Hog PC 5.2.1.31.**

The MSI log from both runs is in `logs/vm/vm_hog_msi.log` (failed) and `logs/vm/vm_hog_msi2.log`
(success).

## 3. Installed result

Install root: **`C:\Program Files (x86)\ETC\HogPC`** — 565.7 MB (the package is 32-bit, so
`ProgramFilesFolder` → `Program Files (x86)`).
Per-user/machine data goes to **`C:\ProgramData\ETC\HogPC`** (fixture library, `helptext`, `resources`).

Top-level layout of the install root:

```
7ZA.EXE  archive.dll  avcodec/avdevice/avfilter/avformat/avutil.dll  bzip2.dll  libx265.dll
postproc.dll  swresample.dll  swscale.dll  zlib1.dll
Qt5Core/Qt5Gui/Qt5Qml/Qt5Quick/Qt5QuickControls2/Qt5Network/Qt5Sql/Qt5Svg/Qt5Widgets/Qt5Xml/…
Qt5WebEngineCore.dll (72 512 000 B)  Qt5WebEngine.dll  Qt5WebEngineWidgets.dll  QtWebEngineProcess.exe
<name>-win32-golden.exe  (see below)  GadgetDrvChange.exe  haspdinst.exe  Manual.url
drivers/  iconengines/  imageformats/  platforms/  QtQml/  QtQuick/  QtQuick.2/  resources/
sqldrivers/  webview/
```

Executables in the install root (name, size, FileVersion):

| exe | size | version | note |
|---|---|---|---|
| `launcher-win32-golden.exe` | 32 617 432 | 5.2.1.31 | **GUI entry point** (shortcut target) |
| `desktop-win32-golden.exe` | 33 603 040 | 5.2.1.31 | desktop/console UI |
| `server-win32-golden.exe` | 32 182 744 | 5.2.1.31 | show server |
| `monitor-win32-golden.exe` | 32 209 880 | — | processor status window |
| `dialogue-win32-golden.exe` | 31 571 424 | 5.2.1.31 | |
| `miniwing_test-Win32-golden.exe` | 31 874 520 | 5.2.1.31 | |
| `dp8k-win32-golden.exe` | 10 678 232 | 5.2.1.31 | DP8K |
| `vob-win32-golden.exe` | 9 926 616 | 5.2.1.31 | |
| `Widget_Upgrader-Win32-golden.exe` | 12 103 640 | 5.2.1.31 | |
| `critical-win32-golden.exe` | 5 481 440 | 5.2.1.31 | |
| `lock-win32-golden.exe` | 851 936 | 5.2.1.31 | |
| `ltc_display-Win32-golden.exe` | 615 392 | 5.2.1.31 | |
| `netservices-win32-golden.exe` | 465 376 | 5.2.1.31 | service image |
| `QtWebEngineProcess.exe` | 505 344 | — | embedded Chromium |
| `GadgetDrvChange.exe` | 187 360 | 0.0.0.0 | |
| `haspdinst.exe` | 25 914 528 | 8.31 | HASP driver installer |
| `7ZA.EXE` | 739 840 | 19.00 | used by `SA_FixLib_Unpack` |

Full recursive listing: `logs/vm/vm_hog_capture.txt`.

### Registry / services / shortcuts / firewall

* Uninstall entry: `HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{6501E546-28F5-4A0E-97E0-1CD914185417}`
  — `DisplayName=Hog PC`, `DisplayVersion=5.2.1.31`, `InstallLocation=C:\Program Files (x86)\`,
  `EstimatedSize=776187` (KB), `UninstallString=MsiExec.exe /X{6501E546-28F5-4A0E-97E0-1CD914185417}`.
* `HKLM\SOFTWARE\WOW6432Node\ETC\HogPC` → `ProductVersion=5.2.1.31` (mirror key `HKLM\SOFTWARE\ETC\HogPC`).
* Services (Manual, Stopped after install):
  `fpstftp` = "Hog TFTP Service", `fpsdhcp` = "Hog DHCP Service", both
  `"C:\Program Files (x86)\ETC\HogPC\netservices-win32-golden.exe"`.
* Shortcuts: Start-Menu `…\Programs\HogPC\` → `Hog PC.lnk` → `launcher-win32-golden.exe`;
  `Widget Upgrader.lnk` → `Widget_Upgrader-Win32-golden.exe`; `Hog Manuals.lnk` → `Manual.url`.
  Public desktop `Hog PC.lnk` → `launcher-win32-golden.exe`.
* Windows Firewall inbound-allow rules added by the installer: `Hog PC Server TCP/UDP`,
  `Hog PC Critical TCP/UDP`, `Hog PC Launcher TCP/UDP`, `Hog PC Desktop TCP/UDP`,
  `Hog PC DP8K TCP/UDP`. (There is **no** rule for `monitor-win32-golden.exe` — see first launch.)

## 4. First launch — no hardware, no licence

Launched `launcher-win32-golden.exe` with no HASP key and no lighting hardware.

**Entry point = `launcher-win32-golden.exe`** (not `desktop-…`). It is a 32-bit Qt 5.15.1 app; it
creates exactly one top-level window:

* class `Qt5151QWindow`, title **"Hog Start"**, 792×338 at (244,231).
* Content: Hog logo; text `Hog PC`, `Version: v5.2.1 (b 31)`,
  `HN IP: 192.168.122.230 / FN IP: 192.168.122.230 / Date: 3 October 2026`; a `No Show found`
  label.
* Buttons: **New Show** (enabled), *Launch Show* (**disabled**), combo + **Browse** (enabled),
  *Connect to Show* (**disabled**), **Start Processor**, **Control Panel**, **File Browser**,
  **Help**, **Quit**.

**No licence dialog, no HASP/hardware error, no demo nag** — the launcher comes straight up.
Evidence: `evidence/vm_hog_launch_01_hogstart.png`, `_03_launcher.png` (+ `_crop`).

Clicking **Start Processor** spawns `monitor-win32-golden.exe`, whose top-level window is:

* title **"Processor"**, class `MonitorWindow`, 770×370 at (255,215). Contents:
  `Show Server IP: No Server`, `Hog Net IP: 192.168.122.230`, `Fixture Net IP: 192.168.122.230`,
  **`Offline`** indicator, `Port Number: 6600`, `Software Version: v5.2.1 (b 31)`;
  buttons **Lock**, **Touchscreens**, **Quit**.
  → i.e. the processor runs happily **offline with no show and no hardware**, on port 6600.

The only dialog ever raised was the Windows Firewall prompt
*"Windows Firewall has blocked some features of monitor-win32-golden on all public and private
networks"* (Allow/Cancel) — because the installer has no firewall rule for `monitor-…`. After
"Allow" the Processor window is fully usable.
Evidence: `evidence/vm_hog_launch_04_firewall_monitor.png`, `_05_processor.png` (+ `_crop`).

**GPU:** the guest exposes only `Microsoft Basic Display Adapter` (10.0.26100.1); the Qt/QML UI
renders correctly in software. **No GPU is required** for the launcher or the processor window.

Process/window dumps and the exact UIA button inventory:
`logs/vm/vm_hog_launch.txt`, `logs/vm/vm_hog_uia_launcher.txt`, `logs/vm/vm_hog_dialogs.txt`.

### Elevation

`launcher-win32-golden.exe` (and the `Hog PC` shortcuts that point at it) **requests elevation**:
started from a normal UAC-filtered shell it raises the consent dialog
*"Do you want to allow this app to make changes to your device? — launcher / Application /
Verified publisher: Electronic Theatre Controls, Inc. / File origin: Hard drive on this computer"*.
So a normal user double-click on the shortcut = one UAC prompt before the app appears.
Evidence: `evidence/vm_hog_launch_07_launcher_non_elevated.png`.

### New Show → the real console UI (still no hardware, no licence)

Clicking **New Show** (button name is `"New\nShow"`) opens Hog's own Qt file dialog,
window title **"New Show"** (class `Qt5151QWindow`, 660×477 at (310,161)), a `ShowConnectWindow`
outer frame:

* `Look In:` combo (items `Shows`, `Hog PC`) + 4 nav buttons; `Tree` with columns
  `Name / Description / Created / Modified`; `File name:` edit (376,505)-(958,537);
  `Comment:` edit (376,543)-(958,575); buttons **Finish** (752,590)-(852,626) and **Cancel**.
* Typing a name and pressing **Finish** creates the show and immediately starts the console:
  a window titled **"Console Startup Process"** appears with the text *"Waiting on Desktop
  Process"* + `Details >>`.

The launcher then spawns (observed live, still with no hardware and no licence key):

```
launcher-win32-golden.exe   (pid 5836, window "Hog Start" / "New Show")
server-win32-golden.exe     (pid 8136)
critical-win32-golden.exe   (pid 8176)
desktop-win32-golden.exe    (pid 9668)
```

and the real console UI comes up: **window title "Hog PC - Primary Screen"**,
class `Qt5151QWindowIcon`, rect (-8,0)-(1280,799) — nearly full-screen, top bar with
`… Palettes | Master | Programmer | Output | 5 | 6 | Views …` buttons (187 UIA elements).
**No licence dialog, no hardware error anywhere.** Evidence:
`evidence/vm_hog_launch_12_console_startup.png`, `_13_console.png`;
UI inventory `logs/vm/vm_hog_uia_console.txt`.

> Answer to the Wine question: on Windows the launcher **does** spawn `server-`, `critical-` and
> `desktop-win32-golden.exe` itself — the "Launch Show" path does not need hand-started children.
> (WMI reports empty `CommandLine` for these because they are elevated, so the exact argv was not
> recoverable from the guest.)

### Persisted state written while exercising the UI

* `%APPDATA%\ETC\Persistent\client_settings.json` —
  `{"backlightTimeout":300,"isLocked":false,"pin":1234,"portNum":6600,"startOb":…,"startProcessor":…,
  "startServer":…,"startVob":false,"userNum":1,"watchdogOn":true}`. Once `startProcessor`/`startServer`
  are `true`, the next launcher start **auto-starts** the processor (and hides "Hog Start"), so reset
  this file to observe a pristine first launch.
* Also written: `last_newshow.json`, `old_shows.json`, `server_settings.json`,
  `playback_bar_config.json`, `customlock.png`, and `%APPDATA%\ETC\Hog.ini`
  (`[General] PB_BAR_0_PC_HW_LOCK=false`).
* Show created by the dialog is a directory:
  `C:\Users\adsf\Documents\ETC\HogPC\Shows\<name>\` containing `hogdatabase.mk2`,
  `hog_ident.json`, `blackbox\0.hbb` (the same layout as the vendor fixture library's
  `hogdatabase.mk2`).

### Not exercised

* `Control Panel`, `File Browser`, `Help`, `Connect to Show`, `Browse`.
* Exact argv the launcher passes to its children (empty in WMI; needs an elevated query or a
  process-monitor capture).

## 5. Guest disk accounting (`Get-PSDrive C`)

| point | Free (GB) |
|---|---|
| before housekeeping | 6.894 |
| after cleanup (removed failed-install debris + Eos Family + `C:\apitrace`) | **7.903** |
| immediately after successful install | **3.180** |
| a few minutes later (launcher running) | 3.16 |
| at hand-off, after creating a show + full console | **3.125** |

Removed to make room (Eos Family was explicitly disposable): `C:\Program Files\ETC` (0.67 GB),
`C:\ProgramData\ETC\EosFamily` (0.95 GB), `C:\apitrace` (0.39 GB), plus 4.44 GB of Hog fixture-library
debris from the failed first install. Kept as instructed: WebView2, VC++ 2022, .NET 10 desktop,
.NET Framework 4.8.

## 6. Reproduce in one go

```sh
cd /home/asdf/projects/hog-wine && source env.sh
# 1. publish the MSI on the host HTTP share (once)
cp "$HOG_MSI" vmshare/Hog_PC_5.2.1.31.msi
# 2. guest: fetch + install elevated, needs >= 8 GB free on C:
tools/vm/vmcmda.sh 'New-Item -ItemType Directory -Force C:\hog | Out-Null; curl.exe -s -o C:\hog\Hog_PC_5.2.1.31.msi http://192.168.122.1:8000/Hog_PC_5.2.1.31.msi' 300
tools/vm/vmcmda.sh 'Start-Process msiexec -ArgumentList "/i","C:\hog\Hog_PC_5.2.1.31.msi","/qn","/norestart","/L*v","C:\hog\hog_msi.log" -Wait -PassThru | ForEach-Object { "RC=" + $_.ExitCode }' 900
# 3. ground truth + launch
tools/vm/vmcmda.sh -f tools/vm/hog_capture.ps1 600        # tree/registry/services/shortcuts
tools/vm/vmcmda.sh -f tools/vm/hog_launch.ps1 300         # launches launcher-win32-golden.exe, dumps windows
tools/vm/pull_artifacts.sh                                 # logs/vm + evidence
```
