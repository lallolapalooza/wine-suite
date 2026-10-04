# Windows reference — ETC Eos Family v3.3.10.28 (win11 guest)

Ground truth captured from the real Windows 11 guest (`win11`, 10.0.26200, user `adsf`), for
comparison against the patched Wine 11.18 build. Everything below was observed on the guest unless
marked **[host]** (derived on the host from the MSI database / extracted payload).

Guest timestamps in the logs run ~2 h behind the host's wall clock (the guest reports UTC-07:00
while the host is in EST). Where a guest log line is quoted it is quoted verbatim; host-side
correlations are spelled out where they matter.

---

## 0. TL;DR

| | |
|---|---|
| Installer that worked | `E:\ETC_EosFamily_v3.3.10.28.exe /S /noreboot`, **run elevated** → exit code `0`, 4 min 20 s |
| Install root | `C:\Program Files\ETC\` (`EosFamily\v3`, `Augment3d`) + `C:\ProgramData\ETC\EosFamily\v3` |
| Footprint | 1658.8 MB, 10 744 files, 757 dirs |
| Main exes | `...\EosFamily\v3\Eos\Eos.exe` (41 645 024 B) · `...\v3\ETC_Launch\ETC_LaunchOffline.exe` (11 316 696 B) · `...\ETC\Augment3d\augment3d_app.exe` |
| Licence | **No key/activation prompt of any kind.** Launches straight into the full editor as *ETCnomad*, `Mode=Offline`, `UserID=1`, `Device Status: Offline`; the launcher's `Backup` role button is greyed out |
| Start-up stall | Unresponsive for ~10–18 s, then self-recovers (`recovered from hang after 10.10 s`) |
| Guest free space | 1.716 GiB before housekeeping → 9.917 GiB after housekeeping → 7.287 GiB after install → **6.897 GiB at hand-off** |

---

## 1. Payload provenance **[host]**

Source: `/run/media/asdf/Windows/eos-media/` (NTFS partition, expanded from
`~/Downloads/ETC_EosFamily_v3.3.10.28.zip`).

```
cf1011a5d71ad885f7f576ac81e5085114e2d02a0f071cafcc7084ab018eabb4  ETC_EosFamily_v3.3.10.28.exe
9833a2e154b51c474e7671150cfaf8372958726b3d951424fa84a17e679b1027  msi/$PLUGINSDIR/ETC_EosFamily_v3.3.10.28.msi
d637fc6fec5029518d1f037eb92ec70f40243e582e494c089bc26efa06d00981  msi/$PLUGINSDIR/ETC_Augment3d_v1.4.10.3.msi
10e7e31fe8b5032eadc437e5951a3946c20088b3868036257e4c8ac447351345  msi/$PLUGINSDIR/haspdinst.exe
```
(saved in `logs/vm/payload_sha256.txt`)

The outer `.exe` is a **Nullsoft NSIS 3.09** installer (`InternalName=Setup`,
`FileDescription=Eos Family Installation Suite`). It is *not* a WiX Burn bundle — the `.wixburn`
strings inside come from the WiX-built MSIs it carries. Its `$PLUGINSDIR` payload contains
`ETC_EosFamily_v3.3.10.28.msi`, `ETC_Augment3d_v1.4.10.3.msi`, `ETC_Serial_Widget.msi`,
`ETC_SLP_Install.exe`, `VC_redist.{x64,x86}.exe`, `Manual.7z`, `haspdinst.exe`, FTDI/USB
driver installers and the WES7 patch executables (console-only).

Reconstructed NSIS command lines (from the installer's own string table, kept as
`logs/vm/nsis_installer_strings.txt`): each MSI is run as
`msiexec /package <x>.msi /norestart /passive /l* <log>`, the VC redists as `/install /quiet /norestart`,
the HASP driver as `haspdinst.exe -i -fi -kp -fss -nomsg`, the SLP service as `ETC_SLP_Install.exe /S`.

### MSI ground truth (Eos Application v3) **[host]**

| | |
|---|---|
| ProductCode | `{F4DF9106-8D55-4CFB-83D4-A6C992E1D1BB}` |
| UpgradeCode | `{228C29DA-1ACC-4D81-A2F2-1EEC804C1B22}` |
| Version | 3.3.10.28 · Template `x64;1033` · WiX 3.11.1.2318 |
| Property `ProductName` | `Eos Application v3`, **overwritten at install to `ETCnomad Eos Application v3`** by the `SetProductName` custom action when `NOT IS_CONSOLE` |
| Media | one cab `eos1.cab`, 920 files |
| Features | `DefaultFeature` (level 1), `Shell` (0), `ShellOffline` (0) |
| `Condition` table | `Shell`→1 when `IS_CONSOLE`, **`ShellOffline`→1 when `NOT IS_CONSOLE`** |
| Firewall | `Eos (TCP-in)`, `Eos (UDP-in)` for `[#MainApp]`, all profiles |
| Services | none |

So on a non-console Windows box the effective install is **DefaultFeature + ShellOffline**: the Eos
application *and* the offline launcher — but **not** the console `Shell` feature, which is why
`ETC_Launch.exe` and the `Winlogon\Shell` registry write do not happen here.

Augment3d MSI: ProductCode `{5BAB341A-E50E-4D25-AD9D-2E9D3019E759}`, version 1.4.10.3,
1171 files, one feature, install dir `<installroot>\Augment3d`, 4 firewall rules
(`Augment3d Application`/`Engine`, TCP+UDP in).

---

## 2. Guest housekeeping

Executed first, because the guest was down to **1.716 GiB free** on C: and the Eos installer refuses
to run below 3.5 GB (`partition too full to install! 3584 MB required`).

`(Get-PSDrive C).Free`:

| stage | bytes | GiB |
|---|---|---|
| before anything | 1 842 880 512 | **1.716** |
| after housekeeping (see below) | ≈ 10.65 × 10⁹ | **9.917** |
| right after Eos install | — | **7.287** |
| at hand-off (incl. sibling workstream's 417 MB apitrace log) | — | **6.897** |

Exact commands (PowerShell in the guest). **The default guest command channel is not elevated**, and
that matters twice: the first housekeeping run through `tools/vm/vmcmd.sh` returned `rc=1603`
(fatal error) for **every** MSI, while the identical commands re-run through the elevated loop
`tools/vm/vmcmda.sh` returned `rc=0`; and launching the *installer* from the normal channel died
outright with `The operation was canceled by the user` (NSIS `requireAdministrator` + an unanswered
UAC prompt, screenshot `evidence/vm_uac_eos_install.png`). Use `vmcmda.sh` for anything that writes
to a machine-wide location.

```powershell
# 1. uninstall the previous project's products (elevated channel)
foreach ($id in '{C253C79A-FFA7-493A-BE3D-053214932BA9}',   # Mastercam 2027 English Language Pack
                '{1E59AE7A-09DE-41B7-97A1-32A5C7CEAEDB}',   # Mastercam 2027 Updater
                '{6FCF92EF-02B6-45BB-82CE-1C0A52F3338A}',   # Mastercam Licensing Utilities
                '{E3A7A159-C187-44D3-93E8-5EF961F4E0DD}',   # Mastercam 2027
                '{F5234E0C-A06D-4404-8175-DCF5F9CFC337}') { # CodeMeter Runtime Kit v8.40a
  Start-Process msiexec.exe -ArgumentList "/X$id /qn /norestart" -Wait -PassThru | % ExitCode
}
& "C:\Program Files (x86)\InstallShield Installation Information\{F25E5DEF-DB04-4C91-A400-2CF4E3FC2989}\uninstaller.exe" `
  -remove -runfromtemp -language:1033 -silent

# 2. stop licence/HASP services, then delete what the MSIs left behind
foreach ($s in 'CodeMeter.exe','hasplms') { Stop-Service -Name $s -Force }
Get-Process CmWebAdmin,'Cnc.Math.GridCompute.Server.Windows',CodeMeter -EA SilentlyContinue | Stop-Process -Force
Remove-Item 'C:\Program Files\Mastercam 2027','C:\Program Files\Mastercam 2027 Updater',
            'C:\Program Files\CodeMeter','C:\Program Files (x86)\CodeMeter','C:\ProgramData\CodeMeter',
            'C:\Users\adsf\AppData\Roaming\Mastercam',
            'C:\Users\adsf\AppData\Local\Downloaded Installations' -Recurse -Force
```

Removed: Mastercam 2027 (3 649 MB), its Updater (21.5 MB), Licensing Utilities, English Language
Pack, CodeMeter runtime (114.5 MB + 3.6 MB, services stopped first), `%LOCALAPPDATA%\Downloaded
Installations` (20.7 MB), `%TEMP%`.

**Kept** (expensive to reinstall, and Eos may use them): Edge WebView2 Runtime, Microsoft Visual C++
2022 x64+x86, .NET 10 Desktop Runtime, .NET Framework 4.8, Microsoft Edge.

**Could not remove / not removed:**

* `C:\Users\adsf\AppData\Local\Temp\39b6e56b-….tmp` — held by a live process; only 36 MB, left alone.
* `C:\ProgramData\Package Cache` (758.7 MB) — contents are VC++ 2022 (v14.50.35719), .NET 10
  (v80.36.53633) and Power BI (`v2.157.1354.0`) payloads, i.e. shared MSI repair sources belonging to
  kept products. Deliberately not touched.
* Other unrelated products left in place because they belong to sibling workstreams: AutoCAD 2027,
  Autodesk Access/App Manager/CER, Resolume Arena, Power BI Desktop, Bonjour.
* After deleting the Mastercam trees, its uninstall registry entries still existed; the elevated MSI
  `/X` pass above removed all of them cleanly (verified: no `Mastercam*`/`CodeMeter*` rows remain).

The installer's own space precheck was the binding constraint, not the ISO size.

---

## 3. Getting the payload into the guest

`vmserv.py` ignores HTTP `Range`, so a 1.13 GB pull over the share is fragile — a read-only ISO was
used instead. **[host]**

```sh
# build the ISO from the NTFS payload without copying it (graft-points)
xorriso -as mkisofs -o state/eosmedia.iso -V EOSMEDIA -J -R -graft-points \
  "ETC_EosFamily_v3.3.10.28.exe=$EW_MEDIA/ETC_EosFamily_v3.3.10.28.exe" \
  "msi/ETC_EosFamily_v3.3.10.28.msi=$EW_MEDIA/msi/\$PLUGINSDIR/ETC_EosFamily_v3.3.10.28.msi" \
  "msi/ETC_Augment3d_v1.4.10.3.msi=$EW_MEDIA/msi/\$PLUGINSDIR/ETC_Augment3d_v1.4.10.3.msi" \
  "msi/VC_redist.x64.exe=…" "msi/VC_redist.x86.exe=…" "msi/haspdinst.exe=…"     # 1 699 997 696 B

# attach it. `virsh attach-disk … sdd --type cdrom` FAILS on this domain
#   ("internal error: No more available PCI slots"), and attach-disk has no --bus option.
# The guest's existing cdrom is on USB, so attach via XML instead:
cat > state/tmp/eosmedia-disk.xml <<'XML'
<disk type='file' device='cdrom'>
  <driver name='qemu' type='raw'/>
  <source file='/home/asdf/projects/eos-wine/state/eosmedia.iso'/>
  <target dev='sdd' bus='usb'/>
  <readonly/>
</disk>
XML
virsh attach-device win11 state/tmp/eosmedia-disk.xml --live      # "Device attached successfully"
# (detach later with: virsh detach-device win11 state/tmp/eosmedia-disk.xml --live)

# expected detach / cleanup
virsh detach-device win11 /home/asdf/projects/eos-wine/state/tmp/eosmedia-disk.xml --live
```

The guest sees it as **`E:` (label `EOSMEDIA`, 1 699 997 696 B)**, `E:\ETC_EosFamily_v3.3.10.28.exe`
present. Note the domain already had `sdc` = the solidedge `gshare.iso` (not ours — left alone).

---

## 4. The install line that worked

```powershell
# in the guest, from the ELEVATED channel (tools/vm/vmcmda.sh):
C:\eos-ref>  Start-Process -FilePath 'E:\ETC_EosFamily_v3.3.10.28.exe' `
                           -ArgumentList '/S','/noreboot' -Wait -PassThru | % ExitCode
0
```

* NSIS silent switch is `/S`; `/noreboot` is honoured by ETC's own script (`Detected [/noreboot] in
  cmd line parameters`) and suppresses the post-driver reboot.
* Elapsed **4.33 min**, exit code **0**, free space 9.925 GB → 7.287 GB.
* `/passive` is *not* needed and, per the script's own string table, only affects presentation.

**What did not work, and why (important for anyone reproducing this):** running it through the
default channel (`tools/vm/vmcmd.sh`) fails immediately with

```
Start-Process : This command cannot be run due to the error: The operation was canceled by the user.
```

That is NSIS's `requireAdministrator` manifest meeting an *unanswered* UAC consent prompt. The film
strip (`evidence/install_filmstrip/0010.png`, kept as `evidence/vm_uac_eos_install.png`) shows the
prompt: *“Do you want to allow this app to make changes to your device? — Eos Family Installation
Suite · Verified publisher: Electronic Theatre Controls, Inc. · File origin: CD/DVD drive”*. Use the
elevated loop (`vmcmda.sh`), or answer the prompt with `tools/vm/uac_yes.sh`.

The install was **silent**, so the only GUI it produced on the successful run was the UAC consent
prompt. Re-running the same installer **without** `/S` (elevated) does draw a GUI, and what it draws
is worth recording: a small 402×208 dark dialog at (443,297), title `Eos Family v3 Software Setup`,
`style=0x94C801C5`:

> **Eos Family v3 Software Setup** ×
> To continue with setup for Eos Family ETCnomad v3.3.10.28
> the following applications must be closed:
> ETCnomad Shell
> Eos
> Once they are closed you may click retry to continue.

This guard fires even when neither `Eos.exe` nor `ETC_LaunchOffline.exe` is running (verified with
`Get-Process` from both channels), so a re-run of the *interactive* installer on an idle box is a
dead end — use `/S` again for maintenance. Evidence:
`evidence/vm_installer_gui_page.png` (screen) and `evidence/vm_installer_gui_close_apps.png`
(the dialog, cropped/thresholded so it is OCR-readable — the dialog is light-on-navy and a plain
full-screen OCR misses it). Note the process stayed alive and had to be killed **from the elevated
channel**: the normal channel cannot terminate an elevated process.

The installer also ran, unasked, the prerequisites it ships: ETC SLP service, ETC USB drivers
(`ETC USB Device Drivers 2.0.7`), the Sentinel HASP/LDK driver, VC++ 2022 redists (skipped: a newer
14.50.35719 was already present) and the Eos manual extraction.

---

## 5. Ground truth on disk

Full listing: **`logs/vm/vm_install_tree.txt`** (11 503 lines: `path <TAB> DIR|<bytes> <TAB> mtime`).
Machine-readable registry dump: `logs/vm/vm_install_registry.txt`. Facts: `logs/vm/vm_install_facts.txt`.

### 5.1 Layout and sizes

| root | dirs | bytes |
|---|---|---|
| `C:\Program Files\ETC\EosFamily\v3` | 40 | 295.8 MB |
| `C:\Program Files\ETC\Augment3d` | 66 | 394.8 MB |
| `C:\ProgramData\ETC\EosFamily\v3` | 651 | 968.3 MB |
| **total** | **757** (759 incl. two intermediate dirs) | **1658.8 MB** (10 744 files) |

```
C:\Program Files\ETC\
├─ EosFamily\v3\
│  ├─ Eos\                       233.8 MB  Eos.exe + Qt5 + ffmpeg + StockIcons/Symbols/Sounds + *.dev + web
│  ├─ ETC_Launch\                 61.3 MB  ETC_LaunchOffline.exe, ETCDoctor.exe, ConsoleHardwareTester.exe,
│  │                                        TouchTest.exe, Qt5*, <locale>.keys/.flag.png/.shell.qm, Utils\
│  ├─ ETCIconDark_NSIS.ico
│  └─ Uninstall_Eos_Family_v3_Software.exe    (393 KB, NSIS uninstaller)
└─ Augment3d\                    394.8 MB  augment3d_app.exe, augment3d_engine.exe, UnityPlayer.dll,
                                            augment3d_engine_Data\ (179.8 MB), rc\ (127.2 MB),
                                            MonoBleedingEdge\, SketchUpAPI.dll, Qt5*, draco.dll, …
C:\ProgramData\ETC\EosFamily\v3\
├─ Manual\                       560.7 MB  648 files — extracted Eos manual (Eos\, Resources\)
├─ FixtureData\                  407.4 MB  release_fix.dat/.idx, release_fxd.idx, release_gob.dat/.idx,
│                                           release_gel.*, release_src.*, release_whl.idx, CIE spectra
└─ Docs\EosFamily_KeyboardShortcuts.pdf
```

`ETC_Launch.exe` and the `Shell` feature are **absent** — see §1.

### 5.2 Executables (versions = file version resource)

| path | version | size | SHA-256 (from guest) |
|---|---|---|---|
| `…\EosFamily\v3\Eos\Eos.exe` | 3.3.10.28 | 41 645 024 | `41007AC5E252D0A4A7CDA9CA99E1ADD2B24343FDF0143D371AADD0B6A7EFFA8A` |
| `…\v3\ETC_Launch\ETC_LaunchOffline.exe` | 3.3.10.28 | 11 316 696 | `463979AEF93E5AFF3640C84B2B9F5E3A59C451DE73D507E483935D32B8694552` |
| `…\v3\ETC_Launch\ETCDoctor.exe` | 3.3.10.28 | 6 896 600 | `2525D7B2A51AD686953D7588B3C9F4813E68A821E1772FC74206B74C8CB15ABB` |
| `…\ETC\Augment3d\augment3d_app.exe` | 1.4.10.3 | 3 749 848 | `C3DAF5D8478F45CB033D5C6E0904947F0EE01B45D069BA50261293EDF4422879` |
| `…\ETC\Augment3d\augment3d_engine.exe` | 1.4.10.3 | 255 448 | `75FAE92DB496118F8E2664D576B699E46104F81826D8B2D9128FC1A6F292AC39` |

Host-side PE facts **[host, from `msitbl/` extraction of `eos1.cab`]**:

* `Eos.exe` — PE32+ x64, subsystem 6.1 GUI. Static imports **only**
  `Qt5Core/Qt5Gui/Qt5Multimedia/Qt5Widgets + dxva2.dll` (everything else is loaded from its own
  directory). **No application manifest** at all: no `requestedExecutionLevel`, no DPI awareness.
* `ETC_LaunchOffline.exe` — PE32+ x64, manifest `asInvoker`, imports include
  `HID.DLL, SETUPAPI, NETAPI32, MPR, WS2_32, Qt5WinExtras, dbghelp`.
* `ETC_Launch.exe` (Shell feature, not installed here) — same shape without `Qt5WinExtras`.
* `shellinstallex` (Shell feature) — `ShellInstallEx.exe` 1.0.0.2, console subsystem, writes the
  `HKLM\…\Winlogon\Shell` value that turns a console into Eos.

### 5.3 Registry

Add/Remove Programs (both hives scanned; nothing else ETC-related is present):

| DisplayName | Version | key | UninstallString |
|---|---|---|---|
| `Eos Family ETCnomad Software` | 3.3.10.28 | `HKLM\…\Uninstall\27024dc9-1a70-41ec-954c-6017cabe9d83` | `C:\Program Files\ETC\EosFamily\v3\Uninstall_Eos_Family_v3_Software.exe` |
| `ETCnomad Eos Application v3` | 3.3.10.28 | `{F4DF9106-8D55-4CFB-83D4-A6C992E1D1BB}` | `MsiExec.exe /X{F4DF9106-…}` |
| `Augment3d` | 1.4.10.3 | `{5BAB341A-E50E-4D25-AD9D-2E9D3019E759}` | `MsiExec.exe /X{5BAB341A-…}` |
| `ETC USB Device Drivers` | 2.0.7 | `{02FA636E-E6C1-4EEB-824D-45F7029F6DD7}` | (MSI) |
| `ETC SLP` | 3.0.0.22 | `{F433EE14-D722-4CEE-841D-B5D838EC44AB}` | `C:\Windows\SysWOW64\SLP_Uninstall.exe` |

The first row is the NSIS bundle's own entry (`InstallLocation=C:\Program Files\ETC\EosFamily\v3`,
`DisplayIcon=…\ETCIconDark_NSIS.ico`, `NoModify=1`, no QuietUninstallString). The second is the
product MSI, renamed to **`ETCnomad …`** by the installer. `EstimatedSize` 751 250 KB (Eos) and
406 485 KB (Augment3d).

ETC registry roots created: `HKLM\SOFTWARE\ETC\EosFamily\v3`, `HKLM\SOFTWARE\ETC\Augment3d\v1`,
`HKLM\SOFTWARE\WOW6432Node\ETC\ETC USB Device Drivers\2.0.7`, `HKLM\SOFTWARE\WOW6432Node\ETC\WinUSB`.

### 5.4 Services, firewall, shortcuts, user data

* **Services:** no Eos service. The installer adds the HASP/Sentinel LDK service
  `hasplms` (Sentinel LDK License Manager, Auto, **Stopped** — needs a reboot) and ETC's SLP daemon
  `slpd` (Service Location Protocol, Auto, **Running**) from `C:\Windows\SysWOW64\slpd.exe`.
  There is **no** `Winlogon\Shell` rewrite (Shell feature not installed, non-console).
* **Firewall rules** (all Inbound/Allow/Any profile): `Eos (TCP-in)`, `Eos (UDP-in)`,
  `Augment3d Application (TCP-in/UDP-in)`, `Augment3d Engine (TCP-in/UDP-in)`.
* **Shortcuts:** `C:\ProgramData\Microsoft\Windows\Start Menu\Programs\ETC\Eos Family v3\`
  → `Launch Eos Family v3.lnk`, `Documentation.lnk`, `Manual - Eos Family.lnk`; plus
  `C:\Users\Public\Desktop\Launch Eos Family v3.lnk` (ALLUSERS=1 ⇒ per-machine desktop shortcut).
  Both `Launch Eos Family v3.lnk` files resolve to
  target `C:\Program Files\ETC\EosFamily\v3\ETC_Launch\ETC_LaunchOffline.exe`, no arguments,
  working dir `…\v3\ETC_Launch\`. Nothing was placed in `C:\Users\adsf\Desktop`.
* **User data created at first run:** `C:\Users\adsf\Documents\ETC\Eos\{ShowArchive,MediaArchive,ModelArchive}`
  (`MediaArchive\000…255`), `C:\Users\adsf\AppData\Local\ETC\Eos\eos.ini`,
  `C:\Users\adsf\AppData\Local\ETC\EosFamily\v3\` (logs, show files, `working.a3d`),
  `C:\Users\adsf\AppData\Local\ETC\EosFamily\v3\EosInstall_v3.3.10.28_20261003T114353\` (installer logs).
* `eos.ini` is written to `…\AppData\Local\ETC\Eos\eos.ini` (not under `EosFamily\v3`). Notable keys:
  `[ACN] CID=001027D4-…, Enable=1, MaxDMXPerSession=20`, `[DMX] Channels=1-32767488`,
  `[MultiConsole] Mode=Offline, UserID=1, Name=ASDF`, `[Shell] ConsoleMode=Default`,
  `[EOS] OfflineOutputEnable=0`, `[LocalDMX] ClientOutput=0` (copy: `logs/vm/vm_eos.ini`).
  There is **no** `MaxDMXStartupTimout` key in this version's file.

---

## 6. First launch with no licence key

**Entry points.** The Start-Menu shortcut starts `ETC_LaunchOffline.exe` ("ETCnomad Shell"), which is a
launcher, not the editor:

1. **"Please select your console mode"** — two big buttons, `Eos_Mode_Button` / `Element_Mode_Button`
   (found via UI Automation; the buttons are images, so OCR only reads the caption).
   → `evidence/vm_shell_select_console_mode.png`
2. **Eos launcher panel** with the Eos product button on the left and, on the right:
   `Offline w/viz` · `Backup` (**disabled/greyed**) · `Mirror` · `Offline` · `Augment3d Tether` ·
   `Settings`, plus a `Change console mode` link.
   → `evidence/vm_shell_launcher.png`
3. Clicking **`Offline`** spawns `Eos.exe` → the real editor.

**What it asks for: nothing.** At no point is a licence key, activation code, dongle or account
requested. There is no "demo mode" prompt either — the unlicensed state is silent:

* the shell's `Backup` button is disabled;
* the product identifies itself as *ETCnomad* (`ETCnomad Shell`, `ETCnomad Eos Application v3`);
* the editor logs `System Health System User State Changed: (None) -> User 1` and
  `Device Status Changed: (None) -> Offline`;
* `eos.ini` records `[MultiConsole] Mode=Offline, UserID=1` and `[EOS] OfflineOutputEnable=0`.

**What works.** Everything the editor needs to be usable offline: the show opens as `(untitled)`, the
standard Eos CIA is live with the `Live`/`Table`/`2PSD`/`Patch` tabs, the command-line softkeys
(`Intensity Focus Color Form Image Shutter Address Query Snapshot Highlight Assert Color Path More SK`),
`Preview/Fader/Offset`, `Cue/Loop/Curve/Rate`, the `Tracking` indicator and the `LIVE:`/`Offline`
status — i.e. a **complete offline editor**. What the licence would add is the *console roles*: the
launcher's `Backup` button is greyed out, the chosen MultiConsole mode is `Offline`, and
`[EOS] OfflineOutputEnable=0` in `eos.ini`. So output is not merely blocked by a dialog — there is no
output path in this mode at all. Screenshots: `evidence/vm_eos_editor_01.png`,
`evidence/vm_eos_editor_status.png`.

**Start-up timeline (this matters for the Wine diff).**

```
11:51:35  Eos.exe started by ETC_LaunchOffline (ETCnomad Shell)
          … window is UNRESPONSIVE (Process.Responding = False at +10 s) …
11:51:49.996  NetworkManager starting up
11:51:50.001  NetworkManager: Number of connected NICs changed: 0 -> 9
11:51:50.032  CreateComponent Created component handle=80000000 cid=001027D4-…
11:51:50.033  ACN started ; Console  Registering for network changes...
11:51:50.062  QuartzFramework InitializeMultiConsole FAIL#2 ; Unable to start network connection
11:51:50.065  Console Framework started successfully (with ACN)
11:51:50.333  Discovery: Component [192.168.122.230:51464,0] ... DCID: ETCnomad Client   (online)
11:51:52.2    Workspace[1] moved/resized -> 1280x752 ; tabs 1.1/2.1/12.1/7.1/5.1 opened
11:51:53.626  System User State: (None) -> User 1 ; Device Status: (None) -> Offline
11:51:53.660  OnyxConsole recovered from hang after 10.10 s
11:53:01      Process.Responding = True (verified), WorkingSet ~1.05 GB, ~30 threads
```

So on Windows the ~10 s unresponsive window is **self-detected and recovered**; the GUI thread starts
pumping about 18 s after process start. Full log: `logs/vm/vm_OnyxConsole.log`
(174 lines, keeps being appended; last line at capture time
`2026-10-03 11:53:03.852 OnyxConsole [SYSMON] Fade Engine Rate Peak (ms): 93 (+20)`).
`NetworkFeedback.log` (3 lines) has **no** `SLPReg() failed` — on Windows the ETC SLP daemon
(`slpd`, listening on 127.0.0.1:427 and 192.168.122.230:427; Eos.exe holds an ESTABLISHED TCP
connection to 127.0.0.1:427) answers, and `slptool findsrvtypes` reports `service:acn.esta`.

**GPU.** The guest has QXL only (no 3D). QXL was **not** a blocker: the shell and the editor both
render fine at 1280×800 (Eos falls back to its own GL/ANGLE path with `libEGL.dll`/`libGLESv2.dll`
shipped in `…\Eos\`). No "GPU required" dialog appeared.

**Note on focus.** Neither the shell nor Eos.exe took the foreground — both windows were created
*behind* the console window. Screenshots therefore required raising them
(`SetWindowPos(HWND_TOPMOST)` / `ShowWindow(SW_MINIMIZE)` on the console), which is also why the
launch film strip shows the console until `…/0076.png`.

---

## 7. Evidence index

Screenshots (`evidence/`):

| file | content |
|---|---|
| `vm_uac_eos_install.png` | UAC consent prompt for the NSIS installer (also `install_filmstrip/0010.png`) |
| `vm_install_cancelled_desktop.png` | desktop immediately after the un-elevated attempt was cancelled |
| `vm_installer_gui_page.png` | interactive (non-silent) installer launch: screen with its dialog |
| `vm_installer_gui_close_apps.png` | that dialog, cropped + thresholded — "the following applications must be closed: ETCnomad Shell / Eos" |
| `vm_shell_select_console_mode.png`, `…_crop.png` | "Please select your console mode" (Eos / Element) |
| `vm_shell_launcher.png` | ETCnomad Shell launcher (Offline / Offline w/viz / Mirror / Backup(disabled) / …) |
| `vm_shell_01.png`, `vm_shell_02.png` | first appearance of the shell window before/after raising it |
| `vm_after_eos_mode.png` | launcher panel right after choosing Eos mode |
| `vm_eos_editor_01.png`, `vm_eos_editor_status.png` | the offline editor, `(untitled)`, tabs + CIA |
| `install_filmstrip/`, `launch_filmstrip/` | 8 s and 3 s film strips of both flows (distinct frames only) |

Logs/artefacts (`logs/vm/`): `vm_install_tree.txt` (full tree), `vm_install_registry.txt`,
`vm_install_facts.txt`, `vm_etc_tree_user.txt`, `vm_OnyxConsole.log`, `vm_NetworkFeedback.log`,
`vm_eos.ini`, `vm_uia.txt` (UI-Automation dump of the launcher), `vm_winprobe.txt` / `vm_windows.txt`
(window rects/state), plus the host-side MSI tables (`msi_*.txt`, `aug3d_*.txt`,
`msi_install_tree_from_tables.txt`) and `payload_sha256.txt`.

Guest scripts used (kept in `vmshare/`, mirror in `state/tmp/`): `winlist.ps1`, `winprobe.ps1`,
`raise.ps1`, `raise2.ps1`, `installer_shot.ps1`, `uia.ps1`, `uia_click.ps1`, `grab_logs.ps1`,
`housekeep.ps1`, `install.ps1`, `capture.ps1`, `capture2.ps1`.

---

## 8. Guest state at hand-off

```powershell
(Get-PSDrive C).Free/1GB     # 6.897 now;  1.716 before housekeeping, 9.917 after housekeeping, 7.287 right after install
```

The 7.287 → 6.897 GiB drop is the sibling API-diff workstream's 417 MB
`C:\apitrace\win_eos.log` (their `apitrace` reference run; files also staged as `C:\apitrace\{apitrace.exe,apihook.dll,eos.cfg}`),
not Eos itself.

Installed and left in place: Eos Family v3.3.10.28 (Eos + ETCnomad Shell + Augment3d), ETC SLP
service, ETC USB drivers, Sentinel HASP driver (service stopped), VC++ 2022, .NET, WebView2.
No Eos/Augment/apitrace process is left running. The second (interactive, maintenance-mode) launch of
the installer used to photograph its window was closed again, and both
`…\v3\Eos\Eos.exe` and `…\v3\ETC_Launch\ETC_LaunchOffline.exe` are still present afterwards.
`E:` still holds the read-only `EOSMEDIA` ISO until detached (§3).

---

## 9. Exact command reference (host)

```sh
cd /home/asdf/projects/eos-wine && source env.sh

# guest command channels — note the elevation difference
tools/vm/vmcmd.sh  '<powershell>' [timeout]      # normal user context (UAC prompts unanswered)
tools/vm/vmcmd.sh  -f script.ps1 [timeout]
tools/vm/vmcmda.sh '<powershell>' [timeout]      # ELEVATED loop (use for installers/msiexec)
tools/vm/vmcmda.sh -f script.ps1 [timeout]

# screenshots / OCR (no vision)
tools/vm/vmshot.sh out.png --psm 6
tools/vm/capture.sh <outdir> 3 340               # film strip, distinct frames only
virsh screenshot win11 out.ppm

# pulling files the guest PUT into vmshare/
tools/vm/pull_artifacts.sh                       # vm_*.{log,txt}->logs/vm, vm_*.png->evidence
```
