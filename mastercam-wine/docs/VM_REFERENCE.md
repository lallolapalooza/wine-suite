# VM reference — Mastercam 2027 on the Windows 11 guest

Ground truth for "what a correct Mastercam 2027 install/launch looks like", measured on the libvirt
guest `win11` (Windows 11, user `adsf`). Every claim below is measured unless marked `[INFERENCE]`.
Evidence: `evidence/vm_install/*.png`, `logs/vm/*`.

## 0. Environment

| item | value |
|---|---|
| domain | `win11` (running; 4 vCPU, 8 GiB RAM, single SATA disk `sda` = `/var/lib/libvirt/images/win11.qcow2`, 62.9 GB C:) |
| OS | Windows 10.0.26200 (Windows 11), PowerShell 5.1.26100.9444 |
| user | `adsf` — Administrators, but UAC-filtered (medium integrity) |
| guest IP | `192.168.122.230` (bridge `virbr0`, host `192.168.122.1`) |
| channels | medium: `C:\seref\poller.ps1`+`runner.ps1`; **elevated**: `C:\seref\vm_admin.ps1` loop (`cmd_admin.txt` → `admin_out.txt`) |
| host share | `vmshare/` served by `tools/vm/vmserv.py 8000` |
| screenshots | `virsh screenshot win11 <f>` (PNG 1280×800); OCR via `tools/host/ocr.sh`, `tools/vm/vmshot.sh` |

### 0.1 Runtimes already present **before** the install

| component | version |
|---|---|
| .NET Framework | 4.8.09221 (Release 533509) |
| **.NET desktop runtime** | **10.0.9** (`C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App\10.0.9`) |
| .NET / ASP.NET Core | 10.0.9 |
| VC++ 2022 | `vcruntime140.dll` 14.50.35719.0, `msvcp140.dll` 14.50.35719.0 |
| WebView2 / Edge | present |

Mastercam's WPF `ManagedUI` targets `net10.0`, and the payload ships **no** .NET runtime — but this
guest already had the **.NET 10 desktop runtime**, and **the installer never complained** about a
missing runtime. Anything that must reproduce this under Wine needs a .NET 10 desktop runtime.

## 1. Vendor media and how it was fed to the guest

`mastercam2027-web.exe` = `PE32+ … RAR self-extracting archive`, **2 115 737 528 bytes**, RAR7
`v6:32M:m0:m3`, `TempMode`, `Setup=setup.exe` (extract to `%TEMP%`, then run `setup.exe`),
FileVersion 29.0.10172.0.

The guest had only **5.45 GB free** and an install needs a 20 GB-free minimum / 4.1 GB actually.
Rather than staging the 2 GB SFX (2.0 GB) plus its 2.3 GB `%TEMP%` extraction, the already-extracted
payload was packed into an ISO and attached read-only:

```sh
xorriso -as mkisofs -V MCMEDIA -J -R -o state/mc_media.iso /run/media/asdf/Windows/mastercam-media
virsh attach-disk win11 /home/asdf/projects/mastercam-wine/state/mc_media.iso sdd \
      --type cdrom --mode readonly --live --targetbus usb     # appears in the guest as E:
virsh detach-disk win11 sdd --live                            # when done
```

`MCMEDIA` (2 364 481 536 B) contains `setup.exe`, `mastercam/Mastercam_Installer.msi`
(1 188 374 016) + `mastercam/1033.mst` and 14 other language transforms, `SetupPrerequisites/*`
(ndp48, VC2022, CodeMeterRuntime64.msi, msxml6_*.msi, MastercamLicensing), `support/*`
(languagepacks, updater, uninstaller, nethasp tools), `datapaths.ini`, `ProductCodes.dat`.

## 2. Commands used

```sh
cd /home/asdf/projects/mastercam-wine && source env.sh
tools/vm/vmcmd.sh '<powershell>' [timeout]          # medium integrity
tools/vm/vmcmd.sh -f vmshare/<script>.ps1 [timeout]
tools/vm/vmcmda.sh -f vmshare/<script>.ps1          # ELEVATED (vm_admin.ps1 loop)
tools/vm/vmshot.sh out.png --psm 6                  # screenshot + OCR
tools/vm/ocr_click.py 'Next' --region 331,76,618,600 --scale 3
tools/vm/ocr_click.py --key leftalt,n ; tools/vm/vmclick.py <x> <y> --screen 1280x800
tools/vm/capture.sh evidence/vm_install 5 400        # console film-strip
tools/vm/uac_yes.sh 120                             # OCR-watch for UAC and answer Alt+Y
virsh screenshot win11 f.png ; tools/host/ocr.sh f.png
```

### 2.1 The install command lines that actually ran

Bootstrapper (elevated, from the read-only media):

```
"E:\setup.exe"                                     # working dir E:\
```

The bootstrapper drives everything else. The **Updater** stage was caught on the process list
verbatim:

```
"E:\support\updater\mastercam2027-updater.exe" /L1033 /clone_wait /S \
    /v"REBOOT=ReallySuppress /L*V \"C:\Users\adsf\AppData\Local\Temp\Updater_Install_10-03-26_09-36-23.log\" /qn"
```

which in turn spawned:

```
msiexec.exe /i "C:\Users\adsf\AppData\Local\Downloaded Installations\{77E84394-2DEA-47B8-8E1D-064095FCF0DD}\Mastercam_Installer.msi" \
  REBOOT=ReallySuppress /L*V C:\Users\adsf\AppData\Local\Temp\Updater_Install_10-03-26_09-36-23.log /qn \
  TRANSFORMS="C:\Users\adsf\AppData\Local\Downloaded Installations\{77E84394-2DEA-47B8-8E1D-064095FCF0DD}\1033.MST" \
  SETUPEXEDIR="E:\support\updater" SETUPEXENAME="mastercam2027-updater.exe" \
  IS_RUNTIME_FILES_LOCATION="C:\Users\adsf\AppData\Local\Temp\{B3E5481A-821A-4674-B253-5E89A994C422}"
```

→ The vendor pattern is: **copy the MSI + transform into
`%LOCALAPPDATA%\Downloaded Installations\{GUID}\`, then `msiexec /i <cache>\Mastercam_Installer.msi
TRANSFORMS=<cache>\1033.MST … /qn`** (the 1.19 GB cached copy is why C: drops by ~1.2 GB beyond the
installed bytes). The main Mastercam feature used the same machinery; `msiexec.exe /V` (a service-hosted
nested install) was visible while it ran.

`[INFERENCE]` The equivalent hand-run unattended command for a Wine reproduction is therefore:

```
msiexec /i "<media>\mastercam\Mastercam_Installer.msi" \
         TRANSFORMS="<media>\mastercam\1033.mst" \
         INSTALLDIR="C:\Program Files\Mastercam 2027" \
         /qn /norestart /l*v C:\vm_msi.log
```
(`<media>` = the extracted payload directory; the bootstrapper's `datapaths.ini` sets
`PROGRAMFILESFOLDER\Mastercam 2027` and `PUBLICDOCUMENTS\Shared Mastercam 2027`, while the MSI's own
default root is `C:\Program Files\mcam`.)

## 3. The install flow as actually shown (screenshots)

| # | screen | evidence |
|---|---|---|
| 1 | Launcher: "MASTERCAM 2027 / Mastercam® 2027 Installs · Utilities · Documentation · Contact Us" | `page01_launcher.png` |
| 2 | **Minimum System Requirements — "Total minimum system requirements met: 3/5"** (Windows 10 Pro ✓, 8 GB RAM ✓, video OpenGL 3.2/OpenCL 1.2 ✗, monitor 1920×1080 ✗ (1280×800), **"at least 20 GB free" ✗ (had 10.1 GB)**) | `page02_sysreqs.png` |
| 3 | Select the installation language — Next stays disabled until one is chosen; chose **English** | `page03_language.png` |
| 4 | Install Options / summary | `page04_options.png` |
| 5 | END USER LICENSE AGREEMENT VERSION 1.0 — "Yes, I accept…" radio | `page05_eula.png` |
| 6 | **Currently installing** — `Setup Prerequisites` → `Licensing Utilities` → `Mastercam 2027` → `Updater` → `English Language Pack` | `page06_progress_prereqs.png`, `page07_progress_licensing.png`, `page08_progress.png`, `page09_progress.png`, `page10_progress.png` |
| 7 | **Setup Complete** — 4 rows, all "Installed." with per-product "View log file" links | `page12_complete.png` |
| 8 | Finish returns to the launcher; Exit closes it | `page13_after_finish.png` |

Wizard geometry: dialog 618×600 at (331,76); the three buttons are always 75×23 at y=609 —
**Back x=615, Next x=726, Exit x=837**. Film-strip of the whole session: `evidence/vm_install/0*.png`.

### 3.1 Install Options page — verbatim

```
Application Language: English          Product Version Number: 29.0.10172.0
User name:            adsf             System:                 U.S.
Company name:         My company name  Shared Defaults Path:   C:\Users\Public\Documents\Shared Mastercam 2027
Install For:          All users        Destination Folder:     C:\Program Files\Mastercam 2027
Space Requirements:   Setup Prerequisites 123 MB (estimated) | Licensing Utilities 393 MB
                      Mastercam 2027 3.1 GB | Updater 21 MB | English Language Pack 544 MB
Total Space Required: 4.1 GB (estimated)     Remaining Space: 10.1 GB
```

### 3.2 Install logs (copied to `logs/vm/`)

| log | what |
|---|---|
| `vm_mcim_10-03-26_09-03-37-505.log` (25 KB) | bootstrapper: language, product-code map, dest dir, "Run the FrontEnd." |
| `vm_Licensing_Utilities_Install_10-03-26_09-21-15.log` (5.0 MB) | Licensing Utilities MSI verbose log |
| `vm_Mastercam_2027_Install_10-03-26_09-26-25.log` (8.4 MB) | **Mastercam 2027 MSI verbose log** |
| `vm_mc_boot.log`, `vm_dump.log`, `vm_services.txt` | launch/watch, dump, service list |

## 4. Ground truth after install

- **Install root: `C:\Program Files\Mastercam 2027\`** — **10 908 files, 3 649.0 MB**
  (full listing with sizes: `logs/vm/vm_tree_Program_Files_Mastercam_2027.txt`).
  Top-level dirs: `apps/ chooks/ common/ crashservice/ documentation/ en/ Extensions/ "glf fonts"/ help/ importexport/ ManagedUI/ simulator/`
  plus the root DLLs/EXEs (`MCCore.dll`, `TLCore.dll`, `CncReducedMKL.dll`, `Mastercam.exe`, …).
- **`C:\Program Files\Common Files\Mastercam\`** — 709 files, 127.6 MB.
- **Main executables**

| path | FileVersion | ProductVersion | description |
|---|---|---|---|
| `C:\Program Files\Mastercam 2027\Mastercam.exe` | 29.0.0.0 | 22.0 | Mastercam 2027 |
| `C:\Program Files\Mastercam 2027\MastercamLauncher.exe` | 29.0.0.0 | 2027 | Mastercam Launcher Application |
| `C:\Program Files\Common Files\Mastercam\McamVersionSelector.exe` | 29.0.0.0 | 1.2 | McamVersionSelector Executable |

  (versions from `logs/vm/vm_ver_*.txt`).

- **Registry uninstall entries** (`logs/vm/vm_uninstall_reg.txt`):

| DisplayName | DisplayVersion | InstallLocation | UninstallString |
|---|---|---|---|
| Mastercam 2027 | 29.0.10172.0 | `C:\Program Files\Mastercam 2027\` | `"…\InstallShield Installation Information\{F25E5DEF-DB04-4C91-A400-2CF4E3FC2989}\uninstaller.exe" -remove -runfromtemp -language:1033` |
| Mastercam Licensing Utilities | 29.0.10172.0 | `C:\Program Files\Common Files\Mastercam\MastercamLicensing\` | `MsiExec.exe /X{6FCF92EF-02B6-45BB-82CE-1C0A52F3338A}` |
| Mastercam 2027 Updater | 29.0.10172.0 | `C:\Program Files\Mastercam 2027 Updater\` | `MsiExec.exe /X{1E59AE7A-09DE-41B7-97A1-32A5C7CEAEDB}` |
| Mastercam 2027 English Language Pack | 29.0.10172.0 | — | — |

  Bootstrapper product-code for Mastercam: `{E3A7A159-C187-44D3-93E8-5EF961F4E0DD}` (from the mcim log).
  CodeMeter Runtime was installed as a prerequisite (`C:\Program Files\CodeMeter\Runtime\`).

- **Shortcuts**: desktop `C:\Users\Public\Desktop\Mastercam 2027.lnk`; Start Menu
  `…\Programs\Mastercam 2027\Mastercam 2027.lnk`, `…\Utilities\Mastercam Launcher.lnk`,
  `…\Documentation\Mastercam Basics.lnk`; plus a "Mastercam Licensing Utilities" folder.

- **MSI cache**: `C:\Users\adsf\AppData\Local\Downloaded Installations\{77E84394-…}\Mastercam_Installer.msi`
  (1.19 GB) + `1033.MST`.

## 5. First launch — licensing

Launched `C:\Program Files\Mastercam 2027\Mastercam.exe`. It starts **two** processes (a 64-bit UI
process and a helper), each owning a window titled `Mastercam 2027`, plus `MastercamLauncher.exe`.
The GUI is **reachable** and immediately shows the licensing flow (read via UI Automation;
`logs/vm/vm_mastercam_first_launch_uia.txt`, screenshots `evidence/vm_install/app_first_launch*.png`):

1. A 400×400 **license splash**: `License number:` / `License type:` / `User type:` /
   `Expiration date:` / `Version: 29.0.10172.0` / `© 1983-2026 CNC Software, LLC. All Rights Reserved.`
   with a progress bar labelled **"Checking license..."**.
2. A modal dialog `Mastercam 2027` (399×159) — **"No Mastercam license found.  Do you have an
   activation code?"** with **Yes** (688,468) and **No** (771,468).

So on a fresh, unlicensed reference install Mastercam reaches its own UI but stops at the licence
prompt — that is the expected Windows behaviour to reproduce. (Deeper UI exploration past that
prompt was not reached in this run.)

## 6. Guest free space

| step | free GB |
|---|---|
| initial | 5.45 |
| after clearing other projects' leftovers (`Downloads\ResArena.exe`, `%TEMP%\mcsize.txt` 2 GB, temp) | 10.14 |
| after prerequisites + licensing + Mastercam + updater + language pack (and the 1.19 GB MSI cache) | **2.34** |
| after launching Mastercam | 1.74 |

The wizard's own minimum is "at least 20 GB free"; the install consumed ~7.8 GB of C: (4.1 GB of
products + the cached MSI + prerequisite temp).

## 7. Gotchas that cost time

1. **`vmserv.py` ignores HTTP `Range`** — `curl -r` on the 2 GB SFX streams the whole file and wedged
   the original single-threaded guest poller. Use full GETs.
2. **UAC**: the poller is medium integrity; anything touching `C:\Program Files`/`msiexec` must be
   elevated. Working routes: `Start-Process -Verb RunAs` + `Alt+Y` (the consent dialog defaults to
   **No**), or the persistent `vm_admin.ps1` elevated loop. `Register-ScheduledTask -RunLevel Highest`
   from the medium poller silently registered nothing.
3. **Blanked display screenshots as pure black** (`mean=0`) — looks like a hung guest. Wake with a
   key and set `powercfg /change monitor-timeout-ac 0`.
4. The installer's main dialog is **created hidden** and appears only after the whole 1.19 GB MSI has
   been read off the media (~70 s at ~21 MB/s); a cross-integrity `ShowWindow` cannot force it (UIPI).
5. The wizard's controls are owner-drawn — `EnumChildWindows`/`GetWindowText` return no labels.
   Drive it with **UI Automation from an elevated process** (`vmshare/vm_uia.ps1`,
   `vm_mcuia.ps1`) plus OCR of the fixed button rectangles.
6. The guest is shared with leftovers of earlier projects: **AutoCAD 2027, Power BI Desktop,
   Resolume Arena 7** are installed (~16 GB) — not yet removed.
