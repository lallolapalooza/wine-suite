# Mastercam 2027 — install and launch under our patched Wine 11.18

**Install: fixed. Launch: still crashes before any window.**

* On the 19-patch base (`/home/asdf/projects/resolume-wine/wine-install`, `msi.dll` built
  10:22) the product MSI aborts inside an InstallShield **deferred** custom action that needs
  InstallShield's 64-bit helper (`ISBEW64.exe`) and rolls everything back — `msiexec` exit 67,
  nothing installed. Root cause (§3/§4): Wine's msiexec writes a *system* COM class
  (`CLSID_PSDispatch`) into the wrong registry view, so the helper cannot initialise.
* With **our build** (19-patch series + `patches/local/0100-msi-class-registry-view.patch` +
  `0101-services-service-logon-token.patch`) the MSI **installs cleanly: exit 0, 1215 files,
  2.5 GB** (§5A, §5B) on a prefix carrying the prerequisites (.NET 10 Desktop, .NET Framework
  4.8, VC++ 2022, CodeMeter Runtime).
* Launch is the remaining blocker: `MastercamLauncher.exe` fastfails (`c0000409`) and
  `Mastercam.exe` aborts because `MCTool.dll` fails to initialise (`e06d7363`); neither ever
  creates a window, so the Windows target state (`Mastercam 2027` window → 400x400 licence
  splash → "No Mastercam license found.") is not reached (§5B/§5C).
* Three project tool bugs found and fixed on the way (§5B): `tools/mkprefix.sh` never actually
  set Windows 10 (prefix reported Windows 7 SP1) and its `--stage fonts` could not run;
  `tools/run_mastercam.sh` SIGKILLed itself before sampling.

---

## 1. Environment

| item | value |
|---|---|
| Wine | `/home/asdf/projects/resolume-wine/wine-install/bin/wine` — `wine-11.18` |
| prefix | `/home/asdf/projects/mastercam-wine/state/exp/mcinstall/prefix` (fresh `wineboot -u`, `WINEARCH=win64`, Win10 19045) |
| media | `/run/media/asdf/Windows/mastercam-media` (read-only) |
| logs | `logs/exp/mcinstall/` and the in-prefix `C:\mc_msi_verbose*.log` |
| display | `:2` (TigerVNC) |

### 1.1 Prefix + fonts

```
export MCW_LOGS=$PWD/logs/exp/mcinstall
tools/mkprefix.sh --prefix $PWD/state/exp/mcinstall/prefix \
                  --wine /home/asdf/projects/resolume-wine/wine-install/bin/wine \
                  --stage fonts
# -> "(fonts not installed; see tools/install_corefonts.sh)"

# tools/install_corefonts.sh needs RW_TMP + WINEPREFIX_INSTALL (env.sh sets neither):
WINEPREFIX_INSTALL=/home/asdf/projects/resolume-wine/wine-install \
RW_TMP=$PWD/state/tmp \
  tools/install_corefonts.sh --prefix $PWD/state/exp/mcinstall/prefix \
                             --src /home/asdf/projects/resolume-wine/state/tmp/fonts
```

20 TTFs installed; `fontprobe` reports `FOUND family "Arial"` / `"Verdana"`.
`mkprefix.sh --stage fonts` alone is broken: `install_corefonts.sh` uses `$RW_TMP`
(mktemp dir `/corefonts.XXXXXX`), which this project's `env.sh` never defines.

### 1.2 Product MSI (run 1, the spec'd command)

```
wine msiexec /i $MCW_MEDIA/mastercam/Mastercam_Installer.msi \
     TRANSFORMS=$MCW_MEDIA/mastercam/1033.mst \
     INSTALLDIR='C:\Program Files\Mastercam 2027' \
     SHAREDDEFAULTS='C:\ProgramData\Mastercam' \
     CNC_UNIT_TYPE=I REBOOT=ReallySuppress \
     /qn /norestart /L*v 'C:\mc_msi_verbose.log'
```

The direct-MSI route was **not refused** (the bootstrapper was not needed), so
`setup.exe`'s undocumented silent mode and the `TRANSFORMS`-less variant were not run.

## 2. Results

| run | MSI | features | result | exit | wall |
|---|---|---|---|---|---|
| 1 | original | all (default) | abort in `InstallFinalize` → rollback | **67** | 9m43s |
| 2 | scratch copy, 3 CA rows deleted | all | abort at `SetDateTimeFormat` (0xc0000005) | **67** | 5m11s |
| 3 | original | `ADDLOCAL=UninstallFeatureMCAM` (+`+ole,+msi,+process` trace) | abort at `SetDateTimeFormat` | **67** | 5m14s |
| 4 | original, after restoring the 64-bit PS key | all | abort at `SetDateTimeFormat` | **67** | 5m07s |
| 5 | original, on a **fresh prefix** (`/run/media/asdf/Windows/mc-scratch/pfx-clean`) with a registry monitor | all | abort in `InstallFinalize` → rollback (identical to run 1) | **67** | 9m12s |

**What is installed afterwards: nothing.**
`drive_c/Program Files/Mastercam 2027/` contains only an empty `common/` directory
(0 files, 16 KB). No `MastercamLauncher.exe`, `Mastercam.exe`, `Mastercam.dll`.
Step 5 of the ticket (launch) is therefore unreachable.

Leftovers the failed installs *do* leave in the prefix (~2.0 GB total):
`drive_c/windows/syswow64/asycfilt.dll` (147 728 B, 1998-03-08 — the MSI's shipped file),
~40 MSI component/SharedDLLs registry entries, `%TEMP%\msi*.tmp`, `_isA774.exe`,
`{B7BFBF47-…}\wac6CA1.tmp`, and the extracted 1.6 MB verbose logs.

## 3. The decisive evidence

### 3.1 MSI log (`drive_c/mc_msi_verbose.log`)

```
InstallShield 11:02:50: Extracted ISBEW64.exe to 'C:\users\asdf\AppData\Local\Temp\{B7BFBF47-…}\wac6CA1.tmp'
InstallShield 11:02:50: Failed to initialize 64-bit helper, error 80004002
InstallShield 11:02:50: Failed to obtain 64-bit helper process for permission item
                       'MACHINE\SOFTWARE\CNC Software\Mastercam 2027\Flags', error '80004002'
InstallShield 11:02:51: Failed to apply permissions for object 'MACHINE\SOFTWARE\CNC Software\Mastercam 2027\Flags', error 0x80004002
Error 27555.Error attempting to apply permissions to object 'MACHINE\SOFTWARE\CNC Software\Mastercam 2027\Flags'. System error:  (-2147467262)
InstallShield 11:02:51: Error returned from ApplyPermissionsItems: 0x00000643
Action ended 11:02:51: ISLockPermissionsInstall. Return value 0.
Action ended 11:02:51: InstallFinalize. Return value 0.
```

No `Return value 3` and no `MSI (s) … Note: 1: 2262` lines exist — Wine's msiexec does
not emit the Windows Installer log format; the same evidence appears on Wine's stderr
(§3.2). Action order (install pass, `InstallExecuteSequence`):
`ISLockPermissionsCost@1402 → StopCodeMeterService@1300 → SxsInstallCA → UnregisterClassInfo
→ InstallFiles → RunNGEN@4180 → RegisterClassInfo → WriteRegistryValues → RegisterTypeLibraries
→ ISLockPermissionsInstall@5901 → PublishComponents → RegisterMastercamFiles@6445
→ InstallFinalize@6600` (and `StartCodeMeterService@6604` / `LaunchBatchFile@6607` never ran).

### 3.2 Wine stderr (`logs/exp/mcinstall/winedbg_install.log`)

```
err:msi:iterate_load_verb Verb unable to find loaded extension L"mcam-emcx"          (benign)
err:msi:execute_script Execution of script 0 halted; action
    L"[MACHINE\SOFTWARE\CNC Software\Mastercam 2027\Flags|Registry|ASDF-THINKPAD-E|Everyone|983103|8<=>S-1-5-21-0-0-0-1000<=>{E3A7A159-…}]ISLockPermissionsInstall"
    returned 1603
err:msi:ITERATE_Actions Execution halted, action L"InstallFinalize" returned 1603
err:msi:__wine_msi_call_dll_function Custom action (...\msiD5D2.tmp:"f34") caused an exception: 0xc0000005
err:msi:execute_script Execution of script 2 halted; action L"StartCodeMeterServiceOnRollback" returned 1603
```

**Single most important excerpt** (from the traced run, §4):

```
221686.992:0154:trace:ole:CoGetPSClsid {00020400-0000-0000-c000-000000000046}
221686.992:0154:trace:ole:CoGetPSClsid () Returning CLSID {00020420-0000-0000-c000-000000000046}
221686.992:0154:trace:ole:CoGetClassObject {00020420-0000-0000-c000-000000000046}, 0x80000001, {d5f569d0-…}
221686.993:0154:err:ole:com_get_class_object class {00020420-0000-0000-c000-000000000046} not registered
221686.993:0154:err:ole:com_get_class_object no class object {00020420-0000-0000-c000-000000000046} could be created for context 0x80000001
221686.993:0154:warn:ole:marshal_object couldn't get IPSFactory buffer for interface {00020400-0000-0000-c000-000000000046}
```

### 3.3 Service path is **not** the blocker (answer to the AutoCAD prior art)

`InstallServices` and `StartServices` both completed `Return value 1` at 11:02:50;
`grep -c err:service` over the whole stderr = **0**; the prefix contains no service keys
(`HKLM\System\CurrentControlSet\Services`) and the MSI's `ServiceInstall` table is empty.
The 5-minute stalls are InstallShield's own helper timeout, not `service_pipe_timeout`.

### 3.4 Live capture: `RegisterClassInfo` overwrites, `UnregisterClassInfo` deletes

Run 5 (fresh prefix) polled `HKLM\Software\Classes\CLSID\{00020420-…}\InprocServer32`
every ~8 s (`logs/exp/mcinstall/keymon2.log`):

```
11:29:31 [(Default) REG_SZ C:\windows\system32\oleaut32.dll]   <- fresh prefix (wineboot)
11:33:04 [(Default) REG_SZ C:\windows\syswow64\oleaut32.dll]   <- RegisterClassInfo OVERWRITES it
11:33:18 []                                                    <- rollback UnregisterClassInfo DELETES it
```

correlated with the MSI log (`pfx-clean/drive_c/mc_msi_clean.log`):

```
11627: Action ended 11:32:59: RegisterClassInfo. Return value 1.     <- 64-bit value now syswow64
12439: InstallShield 11:33:09: Failed to initialize 64-bit helper, error 80004002
12448: Error 27555.Error attempting to apply permissions … System error: (-2147467262)
12443: InstallShield 11:33:09: Error returned from ApplyPermissionsItems: 0x00000643
12444: Action ended 11:33:10: ISLockPermissionsInstall. Return value 0.
14141: Action ended 11:33:14: UnregisterClassInfo. Return value 1.    <- key deleted (rollback)
```

and stderr at the same instant:

```
222694.677:0374:err:ole:apartment_add_dll couldn't load in-process dll L"C:\windows\syswow64\oleaut32.dll"
222694.677:0374:err:ole:com_get_class_object no class object {00020420-…} could be created for context 0x80000001
```

So the damage is done by the **install** path (overwrite), not only by the rollback; the
rollback then removes what is left. Restoring the key before a run cannot help — it is
overwritten again at `RegisterClassInfo` time.

## 4. Root cause

The CA that fails (`ISLockPermissionsInstall`, type 3073 = deferred) is
`Binary.ISLockPermissions.dll` — PE32 **i386** — an InstallShield engine which extracts the
64-bit helper `ISBEW64.exe` from its own resource (`ISCUSTOM/ISBEW64EXE`, carved: PE32+
x86-64, imports ole32/oleaut32/RPCRT4) and talks to it over COM. Wine runs the CA in a
32-bit server (`C:\windows\syswow64\msiexec.exe -Embedding <pid>`, by design —
`dlls/msi/custom.c:custom_start_server` picks the arch from the CA DLL's PE machine type),
which spawns `…\Temp\{…}\_isA774.exe` (the 64-bit helper).

The helper's very first COM step fails:

1. `CoGetPSClsid(IID_IDispatch)` → `{00020420-…}` (CLSID_PSDispatch / PSOAInterface);
2. `CoGetClassObject({00020420-…}, CLSCTX_INPROC_SERVER|CLSCTX_PS_DLL, IID_IPSFactoryBuffer)`
   → **`REGDB_E_CLASSNOTREG`** because the class is not in the **64-bit** view;
3. `marshal_object` cannot get an `IPSFactoryBuffer` for IDispatch
   (`dlls/combase/marshal.c:get_facbuf_for_iid` → `dlls/combase/apartment.c:apartment_get_inproc_class_object`
   → `dlls/combase/combase.c:1884`);
4. InstallShield reports `Failed to initialize 64-bit helper, error 80004002`
   (`E_NOINTERFACE`) → `ISLockPermissions`, 1603 → `InstallFinalize` halted → rollback.

Measured prefix state (the damage):

* two sibling prefixes created minutes earlier by the same Wine build **do** have
  `HKLM\Software\Classes\CLSID\{00020420-…}` in the 64-bit view;
* after run 1 this prefix had it **only** under `…\Wow6432Node\CLSID\…`;
* the MSI's own `Class` table declares ownership of that class:
  `{00020420-…}` = *PSDispatch* and `{00020424-…}` = *PSOAInterface*, component
  `Global_System_OLEAUT32.8C0C59A0_7DC8_11D2_B95D_006097C4DE24`, feature
  **Redistributables** — a Microsoft merge module that also ships `oleaut32.dll`
  (598 288 B, 2.40.4275.1) and `asycfilt.dll` (whose 1998 copy is still in `syswow64`);
* run 1's log line `apartment_add_dll couldn't load in-process dll
  C:\windows\syswow64\oleaut32.dll` shows the 64-bit helper was handed a **32-bit** path:
  Wine's `ACTION_RegisterClassInfo` wrote the 32-bit component's key file
  (`file->TargetPath`, resolved in the 32-bit system dir) into the **64-bit** view;
  the rollback's `ACTION_UnregisterClassInfo` (same view computation) then **deleted**
  the 64-bit entry. `ACTION_RegisterClassInfo`/`UnregisterClassInfo` are the boundaries:
  log lines `Action ended 10:59:59: RegisterClassInfo. Return value 1.`
  (before the failing helper call at 11:02:50) and the rollback's
  `Action start/ended 11:03:25: UnregisterClassInfo`.

Defect — pre-patch code (upstream Wine 11.18, `dlls/msi/classes.c`, `ACTION_RegisterClassInfo`
≈line 692 and `ACTION_UnregisterClassInfo` ≈line 880; the same `is_wow64 || is_64bit`
idiom appears at `dlls/msi/action.c:2489`):

```c
    REGSAM access = KEY_ALL_ACCESS;          /* before the per-class loop */
    ...
    if (package->platform == PLATFORM_INTEL)
        access |= KEY_WOW64_32KEY;
    else
        access |= KEY_WOW64_64KEY;           /* AMD64 package -> 64-bit view for EVERY component */
    if (RegCreateKeyExW( HKEY_CLASSES_ROOT, L"CLSID", 0, NULL, 0, access, NULL, &hkey, NULL ))
        return ERROR_FUNCTION_FAILED;
```

The view is chosen once per *package* (and `hkey` is reused for every class), so a 32-bit
merge-module component in this AMD64 package gets its classes written to — and, on
rollback, deleted from — the **64-bit** view, using its 32-bit key-file path.

`patches/local/0100-msi-class-registry-view.patch` moves that choice into the per-component
loop:

```c
        access = KEY_ALL_ACCESS;
        if (is_wow64 || is_64bit)
            access |= (comp->Attributes & msidbComponentAttributes64bit) ? KEY_WOW64_64KEY : KEY_WOW64_32KEY;
        if (RegCreateKeyExW( HKEY_CLASSES_ROOT, L"CLSID", 0, NULL, 0, access, NULL, &hkey, NULL ))
            return ERROR_FUNCTION_FAILED;
```

(the patch also moves `RegCloseKey(hkey)` inside the loop, fixing the reused handle).
With it, `Global_System_OLEAUT32` (no `msidbComponentAttributes64bit`) is written to
`Wow6432Node`, and the 64-bit view keeps wineboot's `C:\windows\system32\oleaut32.dll`.

### 4.1 Why the isolated repro passes

`ps_test32/64.exe` (sources in `/run/media/asdf/Windows/mc-scratch/ps_test.c`) call exactly
`CoGetPSClsid(IID_IDispatch)` then
`CoGetClassObject({00020420-…}, INPROC_SERVER|PS_DLL, IID_IPSFactoryBuffer)`:

```
32-bit:  -> 0x00000000        (Wow6432Node had the class)
64-bit:  -> 0x80040154        REGDB_E_CLASSNOTREG  (64-bit view had been clobbered)
64-bit after `wine regsvr32 oleaut32.dll`: -> 0x00000000
```

Note `oleaut32.dll` is **not** in `wine.inf`'s `[RegisterDllsSection]`; the prefix gets
these PS classes from the `BaseInstall`/`BaseWow64Install` registration pass, which is why
an MSI that deletes them cannot be repaired by a later install.

### 4.2 Subsequent runs fail even earlier (prefix poisoning)

Restoring the 64-bit `{00020420-…}` key does **not** make the install complete:
runs 2–4 all die at the *first* InstallScript CA `SetDateTimeFormat` (`ISSetup.dll` f12)
with `caused an exception: 0xc0000005` after a ~5-minute stall
(`11:22:45 → 11:27:48`), i.e. before `RegisterClassInfo` is even reached.
`ACTION_UnregisterClassInfo` deletes **every** class owned by the Redistributables
components (`comcat`, `comdlg32.ocx`, `mscomctl.ocx`, `msbind`, `olepro32`, `stdole2` …)
from the same wrong view, so the prefix's 64-bit COM registry is left broken; restoring
one class is not enough. Run 4's key monitor
(`logs/exp/mcinstall/pskey_monitor.log`) shows `{00020420-…}` unchanged throughout — the
residual damage is in the other classes.

## 5. Blocking points, in order

1. **Primary (proven):** `ISLockPermissionsInstall` → `ISBEW64.exe` helper init →
   `CoGetClassObject({00020420-…}, PS_DLL)` = `REGDB_E_CLASSNOTREG` → 1603 → rollback of a
   completed 3.3 GB payload install. Fix = `patches/local/0100-…`.
2. **Secondary:** registry poisoning of the 64-bit COM view by
   `ACTION_RegisterClassInfo`/`UnregisterClassInfo`; after any failed attempt, later runs
   abort at `SetDateTimeFormat` (`0xc0000005`).
3. **Tertiary:** `StartCodeMeterServiceOnRollback` (`ISSetup.dll` f34) raises
   `0xc0000005` (`marshal_object … IPSFactory … {9428a859-6da5-4b68-b599-3751b6c6b281}`)
   during rollback — same 64-bit-helper COM path; also makes the rollback noisy.
4. Not blocking: services/SCM, `LaunchConditions` (`VersionNT64=603` accepted),
   `ISSetupFilesExtract`, `RunNGEN`, `RegisterMastercamFiles`, CodeMeter service start.

## 5A. VERIFIED FIX — the MSI installs with our patched build

`wine-install/bin/wine` (our tree: 19-patch series + `patches/local/0100-…` + `0101-…`;
`lib/wine/x86_64-windows/msi.dll` rebuilt 11:50, i.e. **after** `classes.c` was patched at
11:27) on a fresh prefix at `/run/media/asdf/Windows/mc-scratch/pfx2`, same command as
§1.2 (`/qn /norestart /L*v C:\mc_msi_ourwine.log`, `WINEDEBUG=+timestamp,+err,+warn`),
logged by `logs/exp/mcinstall/rerun_ourwine.sh`:

```
MSIEXEC_EXIT=0
Action ended 11:55:38: RegisterClassInfo. Return value 1.
Action ended 11:56:38: RegisterClassInfo. Return value 1.
Action ended 11:56:48: ISLockPermissionsInstall. Return value 1.      <- was 1603/27555 before
Action ended 11:56:53: InstallFinalize. Return value 1.
Action ended 11:56:59: INSTALL. Return value 1.
```

* the only stderr `err:msi` lines are the benign
  `iterate_load_verb Verb unable to find loaded extension L"mcam-emcx"/L"mcam-mcx"`;
* **installed: 1215 files, 2.5 GB** in `drive_c/Program Files/Mastercam 2027`,
  including `MastercamLauncher.exe` (11 815 768 B) and `Mastercam.exe` (226 136 B);
* registry monitor (`logs/exp/mcinstall/keymon3.log`) shows a **single** unique value for
  `HKLM\Software\Classes\CLSID\{00020420-…}\InprocServer32` for the whole run:
  `C:\windows\system32\oleaut32.dll` — the syswow64 clobber of §3.4 is gone, and the
  rollback no longer deletes the class);
* `ps_test32.exe` **and** `ps_test64.exe` both return `CoGetClassObject(PS, PS_DLL) -> 0x00000000`.

So patch 0100 removes the primary blocker; with it the payload installs cleanly.

## 5B. End-to-end install on the full prefix (our build)

`state/work/prefix` (`$MCW_PREFIX`), our `wine-install/bin/wine`, logged by
`logs/exp/mcinstall/e2e_stage{A,B}.sh`:

| stage | command | result |
|---|---|---|
| prefix | `tools/mkprefix.sh --stage fonts` + `install_corefonts.sh` | fonts OK (Arial/Verdana enumerated) |
| .NET 10 Desktop | `wd10.exe /install /quiet /norestart` (`/run/media/asdf/Windows/mc-scratch/wd10.exe` = 10.0.12 x64) | rc=0, `Program Files/dotnet/host/fxr` present |
| .NET Framework 4.8 | `winetricks -q -f dotnet48` (≈8 min) | rc=0, `Framework64/v4.0.30319` populated |
| VC++ 2022 x64 | `VC_redist.x64.exe /install /quiet /norestart` | rc=0 |
| CodeMeter | `msiexec /i CodeMeterRuntime64.msi ALLOW_BELOW=1 /qn` | **1st: exit 67** — aborted at `CA_OSBelowWinVerX` (OS guard), *not* at a service; **after fixing the prefix version: exit 0**, 118 MB, `Runtime/bin/CodeMeter.exe`, `system32/WibuCm64.dll`, `StartServices. Return value 1`, services `CmWebAdmin` + `CodeMeter Runtime Server` **running**, no `err:service`/1053 |
| Mastercam MSI | §1.2 command line | **exit 0**, 1215 files / 2.5 GB, `MastercamLauncher.exe` + `Mastercam.exe` present |
| probes | `ps_test32.exe` / `ps_test64.exe` | `CoGetClassObject(PS, PS_DLL) -> 0x00000000` in both |

**Patch 0101 verdict:** with our build the `CmWebAdmin` service start succeeds as-is
(`StartServices` return 1, service listed as running) — the CodeMeterProbe stub-service
workaround (§2.2 of `docs/CODEMETER_ON_WINE.md`) is **not needed**. The only CodeMeter
problem we hit was the prefix reporting Windows 7 (see below), which made the MSI abort
before any service action ran.

### Tool bugs found and fixed while doing this

1. `tools/mkprefix.sh` "set Windows 10": the `ProductName|Windows 10 Pro` entry was split on
   the *space*, so it wrote a value literally named `ProductName|Windows`; and setting only
   the `CurrentVersion` **string** is ignored by Wine when the
   `CurrentMajorVersionNumber`/`CurrentMinorVersionNumber` DWORDs exist. Result: the prefix
   reported **Windows 7 SP1 (6.1.7601)**, which is what tripped CodeMeter's
   `CA_OSBelowWinVerX`. Fixed: set the two DWORDs (10/0) plus `CurrentBuildNumber`,
   `CurrentBuild`, `CurrentVersion` (6.3, as winecfg does) and `ProductName`.
2. `tools/mkprefix.sh --stage fonts`: `tools/install_corefonts.sh` needs `RW_TMP` (otherwise
   `mktemp -d /corefonts.XXXXXX`); fixed by exporting `RW_TMP="$MCW_TMP"`.
3. `tools/run_mastercam.sh` SIGKILLed itself: its pre-run cleanup does `pgrep -f "$EXE"`,
   which matches the wrapper script's own command line (`--exe MastercamLauncher.exe`) and
   whose environment contains `WINEPREFIX=…`, so it ran `kill -9` on itself before sampling
   anything ("Killed", empty `out.txt`). Fixed: skip `$$`/`$PPID` and require the match to be
   a `wine`/`wineserver` process (`/proc/<pid>/comm`).

### Launch result

`MastercamLauncher.exe` starts and gets as far as CodeMeter/WMI/device probing, then:
`err:seh:NtRaiseException Unhandled exception code c0000409 flags 1 addr 0x140800701`
(≈5.6 s after start); **no window is ever created** — no `Mastercam 2027` window, no 400x400
licence splash, nothing to OCR (all `screen_*.png`/`win_*.png` OCR to empty). The wrapper
stays resident for the full sample window. See §5C for the `Mastercam.exe` run.
Other new-looking Wine lines from that run:
`err:secur32:start_samss Failed to start SamSs service`,
`err:ole:start_rpcss Failed to start RpcSs service`,
`err:service:device_notify_proc failed to open RPC handle, error 1722`.

## 5C. `Mastercam.exe` directly (skipping the launcher)

`tools/run_mastercam.sh mcdirect --exe Mastercam.exe` (`WINEDEBUG=+timestamp,+err,+warn,+seh`):

```
225131.853:0024:err:module:loader_init "MCTool.dll" failed to initialize, aborting
225131.853:0024:err:module:loader_init Initializing dlls for L"C:\Program Files\Mastercam 2027\Mastercam.exe" failed, status e06d7363
```

`e06d7363` = an MSVC C++ exception escaping `MCTool.dll`'s initialisation; the `+seh` trace
shows the `__CxxFrameHandler4` unwind that ends in `RtlRestoreContext` immediately before the
loader aborts, and earlier in the same run:
`err:secur32:start_samss Failed to start SamSs service`,
`err:ole:start_rpcss Failed to start RpcSs service`,
`err:service:device_notify_proc failed to open RPC handle, error 1722`,
plus `dispatch_exception code=6ba (RPC_S_SERVER_UNAVAILABLE)`.

Again **no window at all** (window tree = Openbox only; all captures OCR to empty text).
So neither entry point reaches the Windows target state (`Mastercam 2027` window → 400x400
licence splash → "No Mastercam license found."): both die during start-up, before any UI.

Next suspects for the launch failure, in order:
1. `MCTool.dll` init throwing — dlls loaded by `Mastercam.exe` before MCTool.dll are
   `Mastercam.dll`/`MCCore.dll`…; the exception type is in the exe's own image
   (`info[3]=0x140000000`).
2. The RPC/SamSs start failures (`RpcSs`, `SamSs` not started for that process) — COM/RPC
   calls in the licence/MCTool path fail with `RPC_S_SERVER_UNAVAILABLE`.
3. `MastercamLauncher.exe`'s `c0000409` fastfail (see §5B) — happens while it probes
   CodeMeter/devices right after `RegisterEventSourceA("CodeMeter Runtime Server")`.

## 6. How to re-check after the patch

```
# 1. registry-view regression (expect S_OK / 0x00000000 from both)
WINEPREFIX=<prefix> wine /run/media/asdf/Windows/mc-scratch/ps_test32.exe
WINEPREFIX=<prefix> wine /run/media/asdf/Windows/mc-scratch/ps_test64.exe

# 2. install on a fresh prefix and confirm the 64-bit view survives
grep -cF 'Classes\CLSID\{00020420-0000-0000-C000-000000000046}' <prefix>/system.reg   # expect 3

# 3. the MSI command from §1.2; success = exit 0 and
ls "<prefix>/drive_c/Program Files/Mastercam 2027/MastercamLauncher.exe"
```

Artifacts kept in `/run/media/asdf/Windows/mc-scratch/` (NTFS, off `/`):
`ps_test.c`, `ps_test32.exe`, `ps_test64.exe`, `oleaut_test.c`, `oleaut_test32.exe`,
`oleaut_test64.exe`, `dll/` (carved `Binary.ISLockPermissions.dll` + `ISBEW64.exe`),
`dll2/` (`Binary.ISSetup.dll`, `Binary.ISSetupFilesHelper`, `Binary.SetAllUsers.dll`).
Logs: `logs/exp/mcinstall/` (`winedbg_*.log`, `msi_*_time.log`, `keymon2.log`,
`pskey_monitor.log`, `wineboot_clean.log`); in-prefix verbose logs:
`state/exp/mcinstall/prefix/drive_c/mc_msi_verbose*.log`.
The scratch prefix used for run 5 (`mc-scratch/pfx-clean`) and the patched MSI copy
(`mc-scratch/mc_patched.msi`) were deleted after the experiment; the main scratch prefix
`state/exp/mcinstall/prefix` (2.0 GB) is kept for follow-up.
