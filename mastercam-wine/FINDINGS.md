# Mastercam 2027 on Wine — findings

One milestone per result, with the measured evidence and the command that produced it.
Ordered by discovery.

## M1 — The "web" installer is an offline RAR7 SFX (2018 MiB), and 7-Zip cannot open it
`file mastercam2027-web.exe` → `PE32+ ... RAR self-extracting archive, 5 sections`.
`7z l` → `Type = PE`, inner `Type = Rar5`, `Method = v6:32M:m0:m3`, `Solid = -`, 83 files / 43 dirs,
2 348 825 246 bytes uncompressed.
`7z x` fails on every file: `ERROR: Unsupported Method` (82 sub-items). 7-Zip 26.00 predates the
RAR7 `m3` method.
**Fix**: official **unrar 7.12** (`state/tmp/rar/unrar`, from `rarlinux-x64-712.tar.gz`) lists and
extracts it cleanly (`rc=0`). Payload extracted to `/run/media/asdf/Windows/mastercam-media` (2.2 GiB).

Payload inventory (the significant members):
| member | size (uncompressed) |
|---|---|
| `mastercam/Mastercam_Installer.msi` | 1 188 374 016 |
| `SetupPrerequisites/MastercamLicensing/MastercamLicensingSetup.exe` | 460 780 776 |
| `SetupPrerequisites/CodeMeterRuntime64.msi` | 195 231 744 |
| `SetupPrerequisites/ndp48-x86-x64-allos-enu.exe` | 121 307 088 |
| `SetupPrerequisites/VC2022/VC_redist.x64.exe` | 25 633 440 |
| `support/languagepacks/2027_en_language_pack_mastercam.exe` | 182 057 816 |
| `support/updater/mastercam2027-updater.exe` | 31 363 936 |
| `support/uninstaller/uninstaller.exe` | 3 956 496 |
| `setup.exe` (bootstrapper) | 11 869 528 |
| `mastercam/*.mst` | 15 transform files (~2.5 MB each) |
| `support/resources/<lang>/*` | per-language DvdSetupRes / NHaspXRes / licence RTF |

SFX metadata: `CompanyName: CNC Software, LLC`, `FileDescription: Mastercam Installer`,
`FileVersion: 29.0.10172.0`, inner RAR comment `Title=Mastercam extractor`, `Setup=setup.exe`,
`TempMode` (i.e. the SFX extracts to `%TEMP%` then runs `setup.exe`).
So the bundle is **fully offline** — no download needed to install.

## M2 — Guest control channel works
`tools/vm/vmcmd.sh 'whoami; hostname'` → `asdf\adsf` / `asdf` in ~2.4 s. The guest runs a PowerShell
poller (`C:\seref`, GET `http://192.168.122.1:8000/cmd.txt`, PUT `guest_cmd_out.txt`); the host side
is `tools/vm/vmserv.py 8000 vmshare`. `vmserv.py` ignores HTTP `Range` — a `curl -r 0-1000` on the
2018 MiB installer hung (it streams the whole file); use HEAD or small files.

## M3 — Guest control channel: how it wedged and the hardened replacement
The original poller ran each command **inline** (`Invoke-Expression`), so a long command blocked it
forever; the 2 GB `curl` above did exactly that and every later `vmcmd.sh` timed out. The guest
display had also gone to sleep (a `virsh screenshot` then returns an all-black frame; send any key,
e.g. `virsh send-key win11 --codeset linux KEY_ESC`, to wake it).

Recovery, with no reboot and no guest agent — **GUI keyboard injection**:
`virsh send-key win11 --holdtime 120 KEY_LEFTMETA` opens the Start menu,
`tools/vm/vmtype2.py 'cmd' --enter` opens a Command Prompt, then type
`curl -s -o %TEMP%\m.bat http://192.168.122.1:8000/mc_svc.bat && %TEMP%\m.bat`.
(A QMP `input-send-event` batch with `meta_l`+`r` did **not** open the Run dialog.) The model has no
vision, so the guest screen is read by `virsh screenshot` + `tesseract` OCR.

Hardened channel: `vmshare/se_svc2.ps1` → `C:\seref\poller.ps1` writes the command to `cmd_in.txt`
and launches `vmshare/runner.ps1` → `C:\seref\runner.ps1` as a **separate hidden process**; the runner
executes it, writes `cmd_out.txt` and PUTs `guest_cmd_out.txt`. The poller can therefore never block on
a slow command. `tools/vm/vmcmd.sh` prepends a nonce so identical commands still run.
Verified: `vmcmd.sh 'echo RECOVERED'` → `RECOVERED`, 4.5 s.

Guest: Windows 11 kernel **10.0.26200**, PowerShell 5.1. It already has **.NET Windows Desktop Runtime
10.0.9 (x64)** installed — which Mastercam's WPF ManagedUI needs — plus leftovers from the earlier
projects (AutoCAD 2027, Power BI Desktop, Resolume Arena 7.28, Bonjour, WPTx64) that the VM agent is
removing on the owner's instruction.

## M4 — The MSI install fails in InstallShield's `ISLockPermissions` CA, not in the service path
Measured by agent `McInstallWine` (scratch prefix, `wine msiexec /qn /L*v`). `InstallServices` and
`StartServices` both return **1** at 11:02:50 with zero `err:service` lines — the Mastercam MSI has
effectively no `ServiceInstall` rows, so the licensing-service theory is **not** the install blocker.

The abort is the deferred custom action **`ISLockPermissionsInstall`** (InstallShield's
`ISLockPermissions.dll`, a registry-ACL helper):

```
err:msi:execute_script Execution of script 0 halted;
  action L"[MACHINE\SOFTWARE\CNC Software\Mastercam 2027\Flags|Registry|ASDF-THINKPAD-E|Everyone|983103|...]ISLockPermissionsInstall"
  returned 1603
err:msi:ITERATE_Actions Execution halted, action L"InstallFinalize" returned 1603
```
MSI log: `Error 27555 … System error: (-2147467262)` (0x80004002 `E_NOINTERFACE`) +
`InstallShield: Failed to initialize 64-bit helper, error 80004002` +
`Error returned from ApplyPermissionsItems: 0x00000643` → **full rollback**, `msiexec` exit 67.

Secondary: CodeMeter's InstallScript rollback CA (`ISSetup.dll` f34 = `StartCodeMeterServiceOnRollback`)
AVs (`0xc0000005`) after stalling ~5 min in the ISBEW64 engine init.

## M5 — CodeMeter under Wine: install/start OK, API channel missing, HASP path works
Full detail in `docs/CODEMETER_ON_WINE.md` (agent `CodeMeterProbe`).
- `WIBUCM64.dll` static import **works** once CodeMeter files are on disk (without them the launcher
  dies at load with `c0000135`).
- `CodeMeterRuntime64.msi` **fails** (`/qn`): `process_send_start_message L"CmWebAdmin.exe"` fails →
  `ITERATE_StartService` 1053 → `StartServices` 1627 → rollback, exit 91. **Verified workaround**: a
  pre-created running stand-in service named `CmWebAdmin.exe` makes the same command exit 0 (118 MB
  installed: `CodeMeter.exe`, `cpsrt.dll`, `WibuCm64.dll`, `CmWebAdmin.exe`, `cmu.exe`, …).
- The CodeMeter service then **installs and starts** — `sc query CodeMeter.exe` = **STATE 4 RUNNING**
  with a persistent wineserver. So this is *not* the Autodesk session-0/`service_pipe_timeout` class.
- **First divergence: the service is unreachable.** It publishes its `Global\Cm*` notification events
  but never creates `Global\CmApiCallIn`, the channel clients use (`GetLastError=2`); `cmu.exe -v`
  therefore says "CodeMeter-Service: not running" while the SCM says RUNNING.
- The kernel driver **never loads** (no `.sys`/`.inf` ships; it is embedded in `CodeMeter.exe`) — so no
  dongle and no CmActLicense machine binding.
- With no licence the launcher still loads and then reports `No Mastercam license found.` (mode (a)).
- **`MastercamLicensingSetup.exe` installs cleanly** (`/s /v"/qn"` → exit 0) and the Aladdin/Sentinel
  licence manager `hasplms` **runs and LISTENs on TCP+UDP 1947** under Wine. So the only Wine-hostable
  licensing path is a **HASP/NetHASP network licence** via `nethasp.ini` (client side is plain TCP/UDP,
  bypassing both the Wibu service and Wine's SCM); untested end-to-end (no dongle/remote LM available).

## M6 — .NET 10 desktop runtime and WPF **work** under our patched Wine
Full detail in `docs/DOTNET_ON_WINE.md` (agent `DotnetProbe`). This removes the biggest risk
(Mastercam's WPF ManagedUI targets `net10.0`).

- `windowsdesktop-runtime-10.0.12-win-x64.exe /install /quiet /norestart` → **exit 0**, installing
  `shared/Microsoft.NETCore.App/10.0.12` (188 files) and
  `shared/Microsoft.WindowsDesktop.App/10.0.12` (78 files incl. `PresentationFramework`,
  `wpfgfx_cor3`, `D3DCompiler_47_cor3`), plus the `hostfxr`/`sharedhost` registry keys.
- Managed code runs both ways: `wine hello.exe` and `wine dotnet.exe hello.dll` (exit code 42
  propagated); `dotnet --info` reports Host 10.0.12, `Microsoft.WindowsDesktop.App 10.0.12`.
- **WPF presents a real painted window**: a `net10.0-windows`/`UseWPF` probe (runtimeconfig pinned to
  10.0.0 exactly like Mastercam's) created a mapped, viewable 412x226 window; OCR of the captured
  pixels reads `WPF PROBE OK`; `RenderCapability.Tier = 131072` (tier 2, hardware) via
  wined3d→OpenGL; WPF infrastructure windows (`MediaContextNotificationWindow`,
  `SystemResourceNotifyWindow`) present, i.e. MilCore/MediaContext are live. **Zero `err:` lines.**
- `.NET Framework 4.8` is a *separate* requirement and also works: `winetricks -q -f dotnet48`
  (≈15 min, ≈2.7 GiB) → `NDP\v4\Full Release=0x80eb1` (4.8) and a compiled test exe reports
  `CLR 4.0.30319.42000 / .NET Framework 4.8.3761.0`. Mastercam needs **both** 4.8 and .NET 10.
- Caveats: `dwmapi:DwmAttachMilContent/DwmDetachMilContent` are benign Wine stubs; winetricks notes a
  WPF infinite-loop bug under non-`en_US.UTF-8` locales (workaround `LC_ALL=C`); on a GPU-less Xvfb
  there are cosmetic `d3d`/libEGL messages, and `import`/`xwd -root` is refused on display `:0`, so
  capture on the Xvfb/TigerVNC display.
- The shipped `WebView2Loader.dll`/wrappers do **not** replace the Edge WebView2 Evergreen Runtime — a
  separate prerequisite if the My-Mastercam panel is needed.

## M7 — The MSI install blocker is a Wine registry-view bug (patch `0100`, written)
Measured by `McInstallWine` with a registry poll across a 9 m 12 s run on a fresh prefix:

```
11:29:31  HKLM\Software\Classes\CLSID\{00020420-…}\InprocServer32 = C:\windows\system32\oleaut32.dll   (fresh prefix)
11:33:04  ...                                                    = C:\windows\syswow64\oleaut32.dll    <- RegisterClassInfo OVERWRITES it
11:33:18  ...                                                    = (deleted)                            <- rollback UnregisterClassInfo DELETES it
```
Correlated MSI log: `RegisterClassInfo. Return value 1.` → `Failed to initialize 64-bit helper, error
80004002` → `Error 27555 … 0x00000643` → `UnregisterClassInfo`. Stderr at the same second:
`err:ole:apartment_add_dll couldn't load in-process dll C:\windows\syswow64\oleaut32.dll`.

**Root cause.** `dlls/msi/classes.c` chose the registry view from the **package** platform
(`package->platform == PLATFORM_INTEL ? KEY_WOW64_32KEY : KEY_WOW64_64KEY`), while `dlls/msi/action.c`
(registry table) uses the **per-component** flag
(`comp->Attributes & msidbComponentAttributes64bit`). Mastercam's MSI is AMD64 and a third-party merge
module declares the Automation PS classes `{00020420-…}` (`CLSID_PSDispatch`) and `{00020424-…}`
(`PSOAInterface`) for a **32-bit** component (`Global_System_OLEAUT32…`, feature `Redistributables`),
so `ACTION_RegisterClassInfo` wrote the 32-bit component's `syswow64\oleaut32.dll` path into the
**64-bit** view and the rollback deleted the system's 64-bit entry. The InstallScript CA then could not
marshal `IID_IDispatch` (`CoGetClassObject(CLSID_PSDispatch, CLSCTX_PS_DLL, IID_IPSFactoryBuffer)` →
`E_NOINTERFACE`) → 1603 → `InstallFinalize` halted → rollback → exit 67, nothing installed.

Decompilation evidence for the CA side: `docs/ISLOCKPERMISSIONS_RE.md` (agent `LockPermRE`): the
32-bit `ISLockPermissions.dll` extracts `ISBEW64.exe` (PE32+ x86-64, imports ole32/oleaut32/RPCRT4)
from its `ISCUSTOM/ISBEW64EXE` resource; the 64-bit helper does `CoGetPSClsid(IID_IDispatch)` →
`CoGetClassObject({00020420-…}, CLSCTX_INPROC_SERVER|CLSCTX_PS_DLL, IID_IPSFactoryBuffer)`;
`combase.c:com_get_class_object` → `E_NOINTERFACE` via `marshal.c:get_ps_clsid`.

**Fix:** `patches/local/0100-msi-class-registry-view.patch` — compute the view per class from
`comp->Attributes & msidbComponentAttributes64bit` in both `ACTION_RegisterClassInfo` and
`ACTION_UnregisterClassInfo` (same idiom as `action.c:2490`).

**Side effect to remember:** after a *failed* install the prefix's 64-bit COM registry is gutted, so
later attempts abort even earlier (`SetDateTimeFormat`, `0xc0000005`) — always re-test on a **fresh
prefix**.

## M8 — CodeMeter's Go service needs a *service logon token* (patch `0101`, written)
`CmWebAdmin.exe` calls `golang.org/x/sys/windows/svc.IsAnInteractiveSession()`, which inspects the
**token groups**. Wine gives SCM-started services the ordinary interactive token, so the measured
groups were `S-1-1-0, S-1-2-0, S-1-5-4(INTERACTIVE), S-1-5-11, …` → INTERACTIVE=1, SERVICE=0. Go
therefore thinks it is a console program, never calls `StartServiceCtrlDispatcherW`, and the SCM times
it out (`process_send_start_message L"CmWebAdmin.exe" failed to start`, 1053) → `StartServices` 1627 →
CodeMeter MSI rollback, exit 91. (The process session id and parent *are* already correct — patch 0004
fixed those; the newer `IsWindowsService()` precondition holds, the token-group check does not.)

**Fix:** `patches/local/0101-services-service-logon-token.patch` — `token_make_service_logon()` in
`server/token.c` drops the INTERACTIVE SID and adds `S-1-5-6` (enabled), called from
`create_process()` when `parent->session_id == 0 && !token` (i.e. started by the service manager).
Also aligns `service_pipe_timeout` 10 s → 30 s (Windows' budget), which is *not* the fix on its own.
Validated by a clean `patch -p1 --dry-run` on a `pristine + series` tree; a compiled workaround (a
stand-in running service named `CmWebAdmin.exe`) already exists in `state/exp/CodeMeterProbe/`.

## M9 — Process lesson: the patch series must be applied *before* the build
The first build ran for ~50 min on a **pristine** tree because `build_wine.sh` copies `wine-11.18/`
into `wine/wine-11.18/` and nothing had applied `patches/series/*`. Caught by grepping for patch
markers. Both trees now carry the series + local patches, and `tools/apply_patches.sh` uses `patch -N`
so re-running it cannot silently *reverse* an already-applied patch.

## M10 — Process lesson: `cp -al` hardlinks across projects are dangerous
`wine-11.18/` was created with `cp -al` from the sibling resolume project, so editing `classes.c` in
place also modified `/home/asdf/projects/resolume-wine/wine-11.18/dlls/msi/classes.c` (same inode).
Detected by diffing the sibling tree against the pristine tarball; restored that one file and then
converted this project's source tree to real copies (`find ... -printf '%n'` → max link count 1).

## M11 — Windows reference: install flow and first launch (agent `VMReference-2`)
Full detail in `docs/VM_REFERENCE.md`; guest tree listing in
`logs/vm/vm_tree_Program_Files_Mastercam_2027.txt`.

**Install (Windows):** `E:\setup.exe` (from a read-only ISO of the extracted payload; C: was too small
for the 2 GB SFX) completes 4/4 products — Licensing Utilities, Mastercam 2027, Updater, English
Language Pack. Root `C:\Program Files\Mastercam 2027` = **10 908 files / 3 649.0 MB**; plus
`C:\Program Files\Common Files\Mastercam` (709 files). Main executables:
`Mastercam.exe` (29.0.0.0), `MastercamLauncher.exe` ("Mastercam Launcher Application"),
`C:\Program Files\Common Files\Mastercam\McamVersionSelector.exe`.
The vendor bootstrapper's own msiexec invocation was captured verbatim on the updater stage:
`msiexec.exe /i "…\Mastercam_Installer.msi" REBOOT=ReallySuppress /L*V <log> /qn TRANSFORMS="…\1033.MST" …`.

**First launch (unlicensed, which is this environment's only state):**
two `Mastercam` processes each with a window titled **"Mastercam 2027"**, plus the launcher; then
- a 400x400 **licence splash** (`License number / License type / User type / Expiration date /
  Version: 29.0.10172.0`, progress bar `**Checking license...**`), and
- a modal dialog **`Mastercam 2027`**: **`No Mastercam license found.  Do you have an activation
  code?`** with Yes/No.

Read via UI Automation (`logs/vm/vm_mastercam_first_launch_uia.txt`) because the app's own windows
screenshot as blank frames.

**This is the target for Wine:** "opens like in Windows" in this environment means reaching exactly
this state — the licence splash and the `No Mastercam license found.` dialog. Windows cannot license
it either (no licence, dongle or licence server exists here); what differs is only that Windows *could*
use a CodeMeter container or dongle because its kernel driver loads, whereas Wine cannot (M5/§12, see
`docs/LICENSING_VERDICT.md`).

Prerequisites present in the guest: .NET Framework 4.8.09221, **.NET 10.0.9 desktop runtime**, VC++ 2022
14.50; the installer did not complain about a missing runtime. CodeMeter was installed by the setup's
prerequisite stage.

## M12 — The pre-UI crash is NOT a Wine bug: a missing `ApplicationLocaleName` value
Agent `LaunchCrashRE` (docs/LAUNCH_CRASH_RE.md, with `winedbg` backtraces) traced **both** crashes to a
single uncaught C++ exception:

```
ADVAPI32!RegGetValueW(hkey, L"", L"ApplicationLocaleName", RRF_RT_REG_SZ, NULL, NULL, &size)
   -> ERROR_FILE_NOT_FOUND
   inside Cnc.Utilities.Core.Windows.dll!Cnc::ResourceDllLoader::GetApplicationLocaleName (RVA 0x38b0)
   -> throw win32::RegistryError("Cannot read string from registry") -> _CxxThrowException
```
`Mastercam.exe`: `MCTool.dll` `DllMain` → CRT static initialisers → … → `GetApplicationLocaleName`
→ throw → uncaught at load → `loader_init "MCTool.dll" failed to initialize`, status `e06d73e3`
(`e06d7363`). `MastercamLauncher.exe`: same throw from its main thread → CRT `abort()` → `int 0x29`
(`__fastfail`, `FAST_FAIL_FATAL_APP_EXIT`) → `c0000409`. So the launcher's `c0000409` is a symptom of
the same missing value, not a separate bug.

Wine is not at fault: `RegGetValueW` is fully implemented
(`wine-11.18/dlls/kernelbase/registry.c:1900`) and correctly returns `ERROR_FILE_NOT_FOUND` because the
value is genuinely absent. The `err:ole:start_rpcss` / `err:secur32:start_samss` lines are benign here
(their `6ba` exceptions are caught in-process; COM works during them — `ps_test32/64` report
`CoGetClassObject(PS, INPROC|PS_DLL)=0`). The AutoCAD project's RpcSs finding is a real Wine defect but
is **not** implicated.

**Cause:** the value is written by the *English Language Pack* product
(`support/languagepacks/2027_en_language_pack_mastercam.exe`), which the vendor bootstrapper installs
and our direct-MSI Wine install skipped. Windows ground truth: `ApplicationLocaleName = REG_SZ "en"`,
next to `LanguagePackVersion = 29.0.10172.0` / `LanguagePackProvider = Mastercam`; the base
`Mastercam_Installer.msi` Registry table (912 rows) contains no `ApplicationLocaleName`.

**Fix (reproducible, no patch):** install the language pack — or set
`HKLM\SOFTWARE\CNC Software\Mastercam 2027\ApplicationLocaleName = REG_SZ "en"`. Setting it removed
**both** crashes: `Mastercam.exe` ran 45 s and `MastercamLauncher.exe` 75 s with no loader/abort error
and real windows present. Remaining: both processes then own only 1×1 hidden windows for ≥75 s — no
licence splash yet.

## M13 — Final state: the app RUNS under Wine, then hits the licence wall
Agent `LaunchCrashRE`, after installing the English Language Pack
(`support/languagepacks/2027_en_language_pack_mastercam.exe /s /v"/qn REBOOT=ReallySuppress"`, exit 0,
~68 s) into `state/work/prefix`:

- Registry now matches Windows exactly: `LanguagePackProvider=Mastercam`,
  `LanguagePackVersion=29.0.10172.0`, `LocalLanguagePacksDirectory`, `ApplicationLocaleName=en`; the
  `en\` resource trees exist (`en`, `apps/en`, `chooks/en`, `Extensions/en`, `importexport/en`,
  `simulator/en`, `help/en`, `Documentation/en`); **95 `*Res.dll` in the prefix == 95 on Windows**;
  app dir 8129 files / 3.0 GB (Windows 10 908 files — the difference is the Updater and
  `Common Files\Mastercam\MastercamLicensing` products, not installed by the direct-MSI route).
- `Mastercam.exe` then ran a **full 240 s with zero exceptions** and created **real, viewable,
  clickable** windows:
  - `"Warning"` (frame 356x147) — client painted solid black, unreadable/not OCR-able at any threshold;
  - `"Exiting..."` (frame 253x105) — OCR: **`No Valid Mastercam License found`** (the exact string
    exists in `en/opmanres.dll`: `Exiting... No Valid Mastercam License found`).
- `MastercamLauncher.exe` also ran the whole 240 s with no error and showed `"MastercamLauncher"`
  with OCR **`No license found`**.
- Clicking OK on both dialogs exits the process; **no main window is ever created**.

**Windows target not reached** — Windows shows a `Mastercam 2027` main window, a 400x400
`Checking license...` splash and a modal `No Mastercam license found.  Do you have an activation
code?` with Yes/No. Under Wine the licence gate fires earlier and the app takes its hard
"no valid licence" exit path. `+module` confirms `Mastercam.exe` loads `WIBUCM64.dll` at start-up, so
the check goes through CodeMeter — i.e. into the wall documented in `docs/LICENSING_VERDICT.md`
(the service never publishes `Global\CmApiCallIn` because the Wibu/HASP kernel driver and device
surfaces are absent).

Side finding, **not** the blocker: `err:module:import_dll Library ManagedUI.Controllers.dll (needed by
…\ManagedUI\MCCore.Controllers.dll) not found` — the CLR maps it, then a by-name import from the
mixed-mode `MCCore.Controllers.dll` misses it because the app dir is not on the search path
(`dlls/ntdll/loader.c` `find_dll_file`). Copying it next to `MCCore.Controllers.dll` removes the error
and changes nothing; the copy was reverted. Worth a Wine loader patch in principle, but it is not on
the critical path.
