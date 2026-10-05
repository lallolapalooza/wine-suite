# Mastercam 2027 on Wine

Mastercam is a registered trademark of CNC Software, LLC. This repository is not associated with, affiliated with, supported nor endorsed by CNC Software, LLC. No guarantees are made, as for the suitability of the content of this repository for any particular purpose.

No Mastercam software is redistributed here. The install media must come from your own Mastercam download; the scripts take it from `$MCW_MEDIA` (see `env.sh`).

`mastercam2027-web.exe` (CNC Software, **Mastercam 2027**, 29.0.10172.0) under a locally built, patched
**Wine 11.18**, on this host, with the Windows reference taken from the libvirt guest `win11`.

## Result

**The app installs and runs under Wine; it cannot be licensed, and that is architectural.**

- A locally built **Wine 11.18** (19-patch base series + **two new Wine patches written here**) installs
  the product (`Mastercam 2027`), its prerequisites (.NET 10 Desktop, .NET Framework 4.8, VC++ 2022,
  CodeMeter) and the English Language Pack, into a 7.5 GB prefix.
- `Mastercam.exe` then **runs indefinitely without crashing** (240 s measured, zero exceptions) and
  creates real, viewable, clickable windows — but the licence gate fires first, so it shows
  `Warning` + `Exiting... No Valid Mastercam License found` and exits. **No main window is created.**
- On **Windows** (unlicensed, the only state available here — there is no licence, dongle or licence
  server in this environment) it goes one step further: the `Mastercam 2027` main window, the
  `Checking license...` splash, then the interactive `No Mastercam license found.  Do you have an
  activation code?` prompt.
- The difference is exactly the licensing stack: **Wine cannot load the CodeMeter/HASP kernel drivers
  or the device surfaces the client enumerates**, so the CodeMeter service never publishes
  `Global\CmApiCallIn` and every local licence mode (dongle, software container) is unreachable. This
  was proven to the level of a name-level object trace, and the last alternative (an `advapi32`
  mandatory-label SDDL gap) was measured and excluded.
- The only remaining, untested path is a **network licence server** on real Windows: Wine even runs the
  Aladdin Sentinel manager `hasplms` (TCP+UDP 1947) and the client side is plain TCP/UDP via
  `nethasp.ini`. It cannot be verified here for want of anything to license against.

Per the owner's rule — *if the app can run but cannot be licensed because Wine lacks kernel-level
APIs, document it and stop* — the work stops here, with everything above documented and reproducible.

Full measured evidence: **`docs/LICENSING_VERDICT.md`**, `FINDINGS.md` (M1–M13),
`docs/CODEMETER_ON_WINE.md`, `docs/LAUNCH_CRASH_RE.md`, `docs/MC_INSTALL_WINE.md`,
`docs/ISLOCKPERMISSIONS_RE.md`, `docs/PAYLOAD_RECON.md`, `docs/DOTNET_ON_WINE.md`,
`docs/PATCH_SERIES.md`, `docs/VM_REFERENCE.md`.

## The two Wine patches this project produced

| patch | bug | why it blocked Mastercam |
|---|---|---|
| `patches/local/0100-msi-class-registry-view.patch` | `dlls/msi/classes.c` chose the registry view from the **package** platform, while `dlls/msi/action.c` uses the **per-component** `msidbComponentAttributes64bit` flag. | A 64-bit package containing a **32-bit** merge-module component that owns the Automation PS classes `{00020420-…}`/`{00020424-…}` had `ACTION_RegisterClassInfo` overwrite the 64-bit `oleaut32` proxy-stub `InprocServer32` with a **syswow64** path, and the rollback then **deleted** the system's 64-bit entry. InstallShield's deferred `ISLockPermissionsInstall` CA could no longer marshal `IID_IDispatch` (`CoGetClassObject(CLSID_PSDispatch, CLSCTX_PS_DLL, IID_IPSFactoryBuffer)` → `E_NOINTERFACE`) → 1603 → `InstallFinalize` halted → **rollback, exit 67, nothing installed**. |
| `patches/local/0101-services-service-logon-token.patch` | Wine started service processes with the ordinary **interactive** token, so `golang.org/x/sys/windows/svc.IsAnInteractiveSession()` (used by CodeMeter's `CmWebAdmin.exe`) saw `S-1-5-4` present and `S-1-5-6` absent, concluded "interactive", and never called `StartServiceCtrlDispatcherW`. | The SCM timed the service out (`1053` → `StartServices` 1627) and the **CodeMeter MSI rolled back, exit 91**. Fixed by giving session-0 children a service logon token (drop `S-1-5-4`, add `S-1-5-6`), mirroring the existing `0004-services-session-0` patch; also aligns `service_pipe_timeout` 10 s → 30 s. |

`docs/MC_INSTALL_WINE.md` and `docs/ISLOCKPERMISSIONS_RE.md` carry the log/decompilation evidence for
0100; `docs/CODEMETER_ON_WINE.md` §11/§12 for 0101 and the licensing blocker.

## Layout
| path | what it is |
|---|---|
| `wine-11.18/` | Wine 11.18 source (tarball) **with** `patches/series/*` + `patches/local/*` applied |
| `wine/wine-11.18/` | the tree that was built (configure `--enable-archs=i386,x86_64`) |
| `wine-install/` | `make install` output; `wine-install/bin/wine` |
| `patches/series/` | `0001..0019` — the AutoCAD-on-Wine (14) + Power BI-on-Wine (5) base the owner asked for |
| `patches/local/` | **this project's patches** (`0100`, `0101`) |
| `patches/sources/` | untouched copies of the two source series |
| `docs/` | all the evidence documents listed above |
| `tools/` | build / prefix / run / probe / VM tooling |
| `vmshare/` | HTTP share with the Windows guest (command channel, payload ISO) |
| `state/work/prefix` | the Wine prefix Mastercam is installed in |
| `logs/` | build logs, run logs, per-agent experiment logs |
| `state/mc_media.iso` (deleted after use) | a read-only ISO of the payload, used to install Mastercam in the `win11` guest; regenerable from `$MCW_MEDIA` |

## Setup fixes that are *not* Wine patches (reproducible)
These were required and are documented so the result is reproducible without a patch:

| fix | why | how |
|---|---|---|
| **Windows 10 version in the prefix** | CodeMeter's `CA_OSBelowWinVerX` guard aborts the MSI if the prefix reports Windows 7. Wine reports the version from `CurrentMajorVersionNumber`/`CurrentMinorVersionNumber` (REG_DWORD); the `CurrentVersion` string alone is ignored. | `tools/mkprefix.sh` now writes `CurrentMajorVersionNumber=10`, `CurrentMinorVersionNumber=0`, `CurrentBuildNumber`/`CurrentBuild=19045`, `CurrentVersion=6.3`, `ProductName='Windows 10 Pro'`. |
| **Core fonts** | Wine substitutes Arial/Verdana but does not *enumerate* them; native/WPF UI needs them present. | `tools/install_corefonts.sh` (needs `RW_TMP`), called from `tools/mkprefix.sh --stage fonts`. |
| **.NET 10 Desktop Runtime** | Mastercam's `ManagedUI` assemblies target `net10.0` and the payload ships **no** runtime. | `windowsdesktop-runtime-10.0.12-win-x64.exe /install /quiet /norestart` (verified: WPF paints a real window, tier 2). |
| **.NET Framework 4.8** | A separate requirement from .NET 10; some components need it. | `winetricks -q -f dotnet48` (`LC_ALL=C`). |
| **VC++ 2022 x64** | Runtime DLLs for the native MFC/C++ code. | `$MCW_MEDIA/SetupPrerequisites/VC2022/VC_redist.x64.exe /install /quiet /norestart`. |
| **CodeMeter Runtime** | `MastercamLauncher.exe` **statically imports `WIBUCM64.dll`**; without CodeMeter on disk it dies at load with `c0000135`. | `msiexec /i CodeMeterRuntime64.msi ALLOW_BELOW=1 /qn` — works because patch `0101` fixes the service token; before it, the MSI rolled back with exit 91. |
| **English Language Pack** | Without it the app **crashes before any UI**: `MCTool.dll`'s static init throws `win32::RegistryError` because `HKLM\SOFTWARE\CNC Software\Mastercam 2027\ApplicationLocaleName` is missing. | `2027_en_language_pack_mastercam.exe /s /v"/qn REBOOT=ReallySuppress"` (or set `ApplicationLocaleName=REG_SZ en`). After it: 95 `*Res.dll` in the prefix == 95 on Windows, and the app runs instead of crashing. |

## Reproduce
```sh
source env.sh
tools/apply_patches.sh wine-11.18          # series + local (patch -N, re-runnable)
tools/apply_patches.sh wine/wine-11.18
tools/build_wine.sh --jobs 8               # configure --enable-archs=i386,x86_64 && make && make install
tools/mkprefix.sh --fresh --stage fonts    # win64 prefix, Windows 10 version, core fonts
#   then, in the prefix: .NET 10 desktop, winetricks dotnet48, VC++ 2022, CodeMeter
wine msiexec /i "$MCW_MEDIA/mastercam/Mastercam_Installer.msi" \
     TRANSFORMS="$MCW_MEDIA/mastercam/1033.mst" \
     INSTALLDIR='C:\Program Files\Mastercam 2027' SHAREDDEFAULTS='C:\ProgramData\Mastercam' \
     CNC_UNIT_TYPE=I REBOOT=ReallySuppress /qn /norestart /L*v C:\mc.log      # -> exit 0
wine "$MCW_MEDIA/support/languagepacks/2027_en_language_pack_mastercam.exe" /s /v"/qn REBOOT=ReallySuppress"
tools/run_mastercam.sh mc1 --exe Mastercam.exe --secs 240 --iv 20
#   -> real windows: "Warning" and "Exiting..." = "No Valid Mastercam License found" (OK), then exit
```

## Environment notes
- Linux 7.0, 22 cores, 30 GiB RAM; the `win11` guest holds 8 GiB. Check `free -m` before a build or a
  run (`tools/build_wine.sh` enforces a 5000 MiB guard and caps `-j`).
- `/` is the only writable filesystem of any size (~19 GiB free at the end); the extracted payload and
  scratch downloads live on the NTFS partition to keep it that way.
- Wine UI runs on TigerVNC `:2`; the model has **no vision**, so screenshots are read with `tesseract`
  OCR and `xwininfo`/UI-Automation text, never by eye.
- Never use `curl -r` against a large file on `tools/vm/vmserv.py` (it ignores HTTP `Range`).

## Netiquette
Not upstream-ready, and no merge request was opened: the work is AI-assisted, which is why the two
patches live here rather than being submitted to Wine.
