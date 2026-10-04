# Mastercam 2027 on Wine — root cause of the pre-UI launch crash

**Verdict (short):** neither entry point crashes because of Wine. Both die from **one uncaught C++
exception thrown while reading a registry value that our install never created**:

```
HKLM\SOFTWARE\CNC Software\Mastercam 2027\ApplicationLocaleName   (REG_SZ)
```

`ADVAPI32!RegGetValueW(...)` returns `ERROR_FILE_NOT_FOUND` (the value really is absent — Wine's
`RegGetValueW` is fully implemented and behaves like Windows here); the app's exception is
`win32::RegistryError("Cannot read string from registry")`, thrown from
`Cnc.Utilities.Core.Windows.dll!Cnc::ResourceDllLoader::GetApplicationLocaleName()`, and it escapes
`MCTool.dll`'s CRT static-initialiser list (inside `DllMain`) → Wine's loader aborts the process.

* On Windows that value is written by the **Mastercam 2027 English Language Pack** product
  (`support/languagepacks/2027_en_language_pack_mastercam.exe`), which the bootstrapper installs and
  our direct-MSI Wine install did not. Verified on the Windows reference VM:
  `ApplicationLocaleName = "en"` (next to `LanguagePackVersion = 29.0.10172.0`,
  `LanguagePackProvider = Mastercam`, `LocalLanguagePacksDirectory = …`).
* Setting `ApplicationLocaleName = "en"` in `state/work/prefix` **removes both crashes** (verified,
  below). Nothing else changed.

**Fixable by a Wine patch?** **No.** There is no Wine-side defect in the failing path; there is
nothing to patch in Wine. The failure is missing application/install data. The `err:ole:start_rpcss`
/ `err:secur32:start_samss` / `error 1722` lines are **unrelated red herrings** (proved below).

---

## 1. Reproduction

```
cd /home/asdf/projects/mastercam-wine
tools/run_mastercam.sh direct1 --exe Mastercam.exe        --secs 40 --iv 10 \
      --debug '+timestamp,+seh,+module,+ole,+rpc,+service'
tools/run_mastercam.sh launch1 --exe MastercamLauncher.exe --secs 30 --iv 10 \
      --debug '+timestamp,+seh,+module'
tools/run_mastercam.sh direct2 --exe Mastercam.exe        --secs 40 --iv 10 --debug '+timestamp,+reg,+seh'
```

### 1.1 `Mastercam.exe` — the reported `e06d7363`

```
225464.072:0024:trace:module:MODULE_InitDLL (000000010E320000 L"MCTool.dll",PROCESS_ATTACH,…) - CALL
225464.073:0024:trace:seh:__std_exception_copy (000000000024E3B8 000000000024E438)
225464.073:0024:trace:seh:dispatch_exception code=e06d7363 (EXCEPTION_WINE_CXX_EXCEPTION) flags=1 …
225464.073:0024:trace:seh:dispatch_exception  info[0]=0000000019930520      # MSVC C++ EH magic
225464.073:0024:trace:seh:dispatch_exception  info[1]=000000000024E430      # exception object
225464.073:0024:trace:seh:dispatch_exception  info[2]=00006FFFF76440B8      # ThrowInfo
225464.073:0024:trace:seh:dispatch_exception  info[3]=00006FFFF7630000      # module base
…
225464.073:0024:trace:seh:RtlUnwindEx code=e06d7363 flags=3 end_frame=0000000024F0B0
                                          target_ip=00006FFFFFBD352A
225464.073:0024:trace:seh:RtlRestoreContext returning to 00006FFFFFBD352A stack 0000000024EFC0
225464.073:0024:trace:module:MODULE_InitDLL (000000010E320000 L"MCTool.dll",PROCESS_DETACH,…) - CALL
225464.073:0024:warn:module:process_attach Initialization of L"MCTool.dll" failed
225464.073:0024:err:module:loader_init "MCTool.dll" failed to initialize, aborting
225464.073:0024:err:module:loader_init Initializing dlls for
    L"C:\\Program Files\\Mastercam 2027\\Mastercam.exe" failed, status e06d7363
```

`0x6FFFF7630000` is `Cnc.Utilities.Core.Windows.dll` (from the same run's `+module` trace:
`build_module loaded L"…\Cnc.Utilities.Core.Windows.dll" … 00006FFFF7630000`).

### 1.2 Faulting stack (`winedbg`, all threads — `bt all` at the first-chance exception)

`winedbg` was driven non-interactively (internal var `HKCU\Software\Wine\WineDbg\BreakOnFirstChance=1`,
commands fed through a FIFO). At the `MCTool.dll` C++ exception:

```
Backtrace:
=>0 0x006fffff3ab49e RaiseException+0x46            [kernelbase/debug.c:334] in kernelbase
  1 0x006ffffe9992d5 _CxxThrowException+0x65        [dlls/msvcrt/cpp.c:920] in ucrtbase
  2 0x006ffff76338a5 in cnc.utilities.core.windows (+0x38a5)   <- throw site
  3 0x006ffff7633a9a in cnc.utilities.core.windows (+0x3a9a)
  4 0x006ffff7633e2a in cnc.utilities.core.windows (+0x3e2a)
  5 0x006ffff7634eb6 in cnc.utilities.core.windows (+0x4eb6)
  6 0x006ffff7634ae2 in cnc.utilities.core.windows (+0x4ae2)
  7 0x0000010e6336ed in mctool (+0x3136ed)          <- MCTool static-initialiser
  8 0x0000010e6335e9 in mctool (+0x3135e9)
  9 0x0000010e321325 in mctool (+0x1325)
 10 0x006ffffe9ab5aa _initterm+0x4a                  [dlls/msvcrt/data.c:554] in ucrtbase
 11 0x0000010e9dc062 in mctool (+0x6bc062)           <- dllmain CRT dispatch
 12 0x0000010e9dc1d3 in mctool (+0x6bc1d3)
 13 0x006fffffbceb94 in ntdll (+0xeb94)
 14 0x006fffffbdab3e MODULE_InitDLL+0x17e            [dlls/ntdll/loader.c:1709] in ntdll
 15 0x006fffffc2eead process_attach+0x1fd            [dlls/ntdll/loader.c:1802] in ntdll
 …  (loader recursion)
 60 0x006fffffc1ff71 loader_init+0x1c1               [dlls/ntdll/loader.c:4574] in ntdll
```

Register/stack dump at the stop (`rsp=0x24e290`):

```
0x0000000024e2d0:  0000000019930520 000000000024e430      # magic, exception object
0x0000000024e2e0:  00006ffff76440b8 00006ffff7630000      # ThrowInfo, image base
```

So: `MCTool.dll` `DllMain` → CRT `_initterm` over C++ static initialisers → (MCTool RVA 0x1325 →
0x3135e9 → 0x3136ed) → `Cnc.Utilities.Core.Windows.dll` → **throw**.

### 1.3 The exact call that throws

`Cnc.Utilities.Core.Windows.dll` (ImageBase `0x180000000`), export map pins the frames:

| RVA | symbol |
|---|---|
| `0x38b0` | `Cnc::ResourceDllLoader::GetApplicationLocaleName(std::wstring const&, std::wstring const&)` |
| `0x3c50` | `Cnc::ResourceDllLoader::GetResourcesPath(...)` |
| `0x4d10` | `Cnc::ResourceDllLoader::GetResourceDllHandle(...)` |
| `0x5160` | `Cnc::ResourceDllLoader::OpenRegistryKey(std::wstring const&)` → `win32::RegKey` |

so the chain is

```
MCTool.dll static init
  → ResourceDllLoader::GetResourceDllHandle   (0x4d10, return 0x4ae2)
  → ResourceDllLoader::GetResourcesPath       (0x3c50, return 0x4eb6)
  → ResourceDllLoader::GetApplicationLocaleName (0x38b0, return 0x3e2a)
  → anonymous registry helper (0x3660) → RegGetValueW  (return 0x3a9a)
  → throw                                    (+0x38a5)
```

Disassembly of the helper (the failing call and the throw block):

```
1800036d4:  ff 15 26 a9 00 00   call QWORD PTR [rip+0xa926]   # 0x18000e000  = ADVAPI32!RegGetValueW
1800036da:  85 c0               test eax,eax
1800036dc:  0f 85 9e 01 00 00   jne 0x180003880              # non-zero == failure
…
180003880:  44 8b c0            mov  r8d,eax                  # Win32 error -> 3rd ctor arg
180003883:  48 8d 15 9c d5 00 00 lea  rdx,[rip+0xd59c]        # 0x180010e00
                                                            # "Cannot read string from registry"
18000388a:  48 8d 4c 24 50      lea  rcx,[rsp+0x50]
18000388f:  e8 8c fc ff ff      call 0x180003520             # win32::RegistryError(msg, err) ctor
180003894:  48 8d 15 1d 08 01 00 lea  rdx,[rip+0x1081d]       # 0x1800140b8 (ThrowInfo)
18000389b:  48 8d 4c 24 50      lea  rcx,[rsp+0x50]
1800038a0:  e8 c9 88 00 00      call 0x18000c16e             # _CxxThrowException
1800038a5:  cc                  int3
```

Call arguments (`RegGetValueW(HKEY, lpSubKey, lpValue, dwFlags, pdwType, pvData, pcbData)`):
`hkey` = the key handle, `lpSubKey = L""`, `lpValue = L"ApplicationLocaleName"`,
`dwFlags = 2 (RRF_RT_REG_SZ)`, `pdwType = NULL`, `pvData = NULL`, `pcbData = &size` (the
"how big is it" probe).

The `ThrowInfo` at RVA `0x140b8` names the exception and its bases:

```
.?AVRegistryError@win32@@     (win32::RegistryError)
.?AVruntime_error@std@@
.?AVexception@std@@
```

## 2. Which value, exactly — `+reg` trace (decisive)

```
trace:reg:NtOpenKeyEx (0x20,L"Software\\CNC Software\\Mastercam 2027",20119,0x24e440)
trace:reg:NtOpenKeyEx <- 0xd8                                   # 0x20 = HKEY_LOCAL_MACHINE
trace:reg:RegGetValueW (00000000000000D8,L"",L"ApplicationLocaleName",2,0000000000000000,
                        0000000000000000,000000000024E450=0)
trace:reg:RegQueryValueExW (00000000000000D8,L"ApplicationLocaleName",…,000000000024E388=0)
trace:reg:NtQueryValueKey (0xd8,L"ApplicationLocaleName",2,0x24e1c0,12)   # -> name not found
trace:seh:__std_exception_copy (…)
trace:seh:dispatch_exception code=e06d7363 …
```

The `msiexec` install log and the MSI itself never write this value: `msiinfo export
Mastercam_Installer.msi Registry` = 912 rows and **no `ApplicationLocaleName`** (the row set is
`Directory/InstallLanguage/InstallTimeStamp/RegCompany/RegUser/revision/SharedDir/Startup-Units/
Update` + `Flags\RepairNeeded` + `UpdateNotify\AutoCheck` — exactly what the prefix contains);
`1033.mst` and the rest of the media don't contain the string either.

**Windows ground truth** (queried live on the reference VM through the guest channel):

```
HKEY_LOCAL_MACHINE\SOFTWARE\CNC Software\Mastercam 2027
    ApplicationLocaleName       REG_SZ    en
    CheckForUpdatesDir          REG_SZ    C:\Program Files\Mastercam 2027 Updater\
    LanguagePackProvider        REG_SZ    Mastercam
    LanguagePackVersion         REG_SZ    29.0.10172.0
    LocalLanguagePacksDirectory REG_SZ    E:\support\languagepacks
    Directory / InstallLanguage / InstallTimeStamp / RegCompany / RegUser /
    revision / SharedDir / Startup-Units / Update        (the base-MSI rows we also have)
```

The three `LanguagePack*` values + `ApplicationLocaleName` are the neighbouring block written by the
language-pack product (`logs/vm/vm_uninstall_reg.txt` lists *Mastercam 2027 English Language Pack*
as a separate installed product). Our Wine install ran only `Mastercam_Installer.msi`, so those rows
(and the `en\` resource tree the Windows install has at the product root) do not exist.
[INFERENCE] that the language-pack MSI writes `ApplicationLocaleName`; the value's absence and the
Windows value `"en"` are measured facts.

## 3. `MastercamLauncher.exe` — the `c0000409` fastfail is the *same* exception

Pre-fix, `MastercamLauncher.exe` dies ~5.6 s in. `+seh,+reg` shows the identical read and a
`c0000409` that is *not* a separate bug:

```
trace:reg:NtOpenKeyEx (0x20,L"Software\\CNC Software\\Mastercam 2027",20119,0x14f480) <- 0xc0
trace:reg:RegGetValueW (0xc0,L"",L"ApplicationLocaleName",2,0,0,0x14F490=0)
trace:reg:NtQueryValueKey (0xc0,L"ApplicationLocaleName",2,0x14f200,12)
trace:seh:__std_exception_copy (000000000014F3F8 000000000014F478)
trace:seh:dispatch_exception code=e06d7363 … info[2]=00006FFFFAA340B8 info[3]=00006FFFFAA20000
err:seh:NtRaiseException Unhandled exception code c0000409 flags 1 addr 0x140800701
```

`winedbg` `bt` at that C++ exception:

```
=>0 RaiseException+0x46                        [kernelbase/debug.c:334]
  1 _CxxThrowException+0x65                    [dlls/msvcrt/cpp.c:920] in ucrtbase
  2 0x006ffff85d38a5 in cnc.utilities.core.windows (+0x38a5)      <- same throw site
  3 0x006ffff85d3a9a in cnc.utilities.core.windows (+0x3a9a)
  4 0x006ffff85d3e2a in cnc.utilities.core.windows (+0x3e2a)
  5 0x006ffff85d4eb6 in cnc.utilities.core.windows (+0x4eb6)
  6 0x006ffff85d4ae2 in cnc.utilities.core.windows (+0x4ae2)
  7 0x000001400a043b in mastercamlauncher (+0xa043b)
  8 0x000001400a012a in mastercamlauncher (+0xa012a)
  9 0x00000140823dd3 in mastercamlauncher (+0x823dd3)
 10 0x000001402b1c12 in mastercamlauncher (+0x2b1c12)
 11 0x006fffff9f1799 in kernel32 (+0x11799)
 12 0x006fffffbd111b in ntdll (+0x1111b)
```

i.e. the same `ResourceDllLoader::GetApplicationLocaleName` exception, this time on the launcher's
main thread during its own initialisation. The launcher's CRT turns the uncaught C++ exception into
`abort()`:

```
1408006fc: b9 07 00 00 00   mov  ecx,0x7      # FAST_FAIL_FATAL_APP_EXIT
140800701: cd 29            int  0x29         # __fastfail  -> STATUS_STACK_BUFFER_OVERRUN c0000409
140800703: 41 b8 01 00 00 00 mov r8d,1        # fallback: RaiseException(STATUS_FATAL_APP_EXIT,…)
```

`0x140800701` is therefore inside the launcher's static CRT `abort()` path, not a bug of its own —
the reported `c0000409` is the *symptom* of the same missing registry value.

## 4. Proof of causality (both entry points fixed by one value)

```
WINEPREFIX=$PWD/state/work/prefix wine reg add \
  'HKLM\Software\CNC Software\Mastercam 2027' /v ApplicationLocaleName /t REG_SZ /d en /f
```

| run | before | after |
|---|---|---|
| `Mastercam.exe` (`direct1` / `direct3`) | `loader_init "MCTool.dll" failed to initialize … e06d7363`; process gone | alive the whole 45 s window, no `loader_init` line; window `0xc00003 "mastercam.exe"` |
| `MastercamLauncher.exe` (`launch1` / `launch3`) | `Unhandled exception c0000409 … 0x140800701` after ~5.6 s | alive 75 s, no exception at all; window `0xe00003 "mastercamlauncher.exe"` |

**This value is now present in `state/work/prefix`** (the only change made to the prefix). Note it is
not yet enough to reach the Windows target state: both processes now stay up but own only 1×1 hidden
windows (no `Mastercam 2027` window / licence splash within 75 s) — see §7.

## 5. Why the RPC / SCM / CodeMeter theories are wrong

The run's alarming lines are all present *after* the fix too, and the app no longer crashes:

```
err:secur32:start_samss Failed to start SamSs service
err:secur32:load_auth_packages Failed to get security packages list: 80090304
err:ole:start_rpcss Failed to start RpcSs service
err:service:device_notify_proc failed to open RPC handle, error 1722
```

* (a) `start_rpcss`/`SamSs`: **not causal.** `+seh` shows the `6ba (RPC_S_SERVER_UNAVAILABLE)`
  exceptions are **raised and handled in-process**: `dlls/secur32/lsa.c` wraps the LSA call in
  `__TRY/__EXCEPT` (`RpcExceptionFilter` → `EXCEPTION_CONTINUE_EXECUTION`), and
  `dlls/combase/rpc.c:start_rpcss()` simply fails to *start* the service. `RpcSs` is in fact
  `RUNNING` in this prefix (`wine sc query RpcSs` → `STATE: 4 RUNNING`). Even with
  `err:ole:start_rpcss` printed, both apps run: the error lines appear *before* the crash and around
  it, not as its cause.
* (b) `Global\CmApiCallIn` / CodeMeter: **not involved.** The faulting stack (§1.2/§3) is only
  `MCTool.dll` CRT static-init → `Cnc.Utilities` registry read → `throw`; no licence or CodeMeter
  code appears on it, and the missing datum is an application locale string, not a CodeMeter object.
* (c) missing/incorrect Wine API: **no.** The failing import is implemented and correct (§6).
* (d) → **something else: a missing registry value produced by an uninstalled companion product.**

### 5.1 Cheap discriminator: COM/RPC works while `err:ole:start_rpcss` is printed

`ps_test32.exe` / `ps_test64.exe` (`CoInitialize` + `CoGetPSClsid(IID_IDispatch)` +
`CoGetClassObject({00020420-…}, INPROC_SERVER|CLSCTX_PS_DLL, IID_IPSFactoryBuffer)`) in this very
prefix, with those `err:` lines present:

```
ps_test32: CoInitialize -> 0x00000000 ; CoGetPSClsid -> 0x00000000 ; CoGetClassObject(PS,INPROC|PS_DLL) -> 0x00000000
ps_test64: CoInitialize -> 0x00000000 ; CoGetPSClsid -> 0x00000000 ; CoGetClassObject(PS,INPROC|PS_DLL) -> 0x00000000
```

(and `HKLM\Software\Classes\CLSID\{00020420-…}\InprocServer32 = C:\windows\system32\oleaut32.dll`).
So the RPC/COM surface is functional and in-proc COM creation/calls do not depend on `RpcSs`.

### 5.2 AutoCAD 2027 prior art (`autocad2027-private-main/FINDINGS.md`, M24c/M24k/M24l)

The prior art *did* hit a genuine Wine-side defect: `err:ole:start_rpcss Failed to start RpcSs
service` because Wine's SCM starts one service at a time (`programs/services/services.c`,
`service_wait_for_startup` / `service_pipe_timeout`) and the prefix had `RpcSs\Start = 3`
(demand) whereas Windows runs it auto-start; the prefix fix is `RpcSs\Start = 2` (+ `SamSs\Start = 2`),
after which ncalrpc `lsasspirpc` binds and the error vanishes (M24l). That defect is real, but it
only bites a **Windows service** whose own start-up needs `RpcSs`; Mastercam's crash is in the GUI
process's DLL static-init and is unaffected. In this prefix `RpcSs\Start` is still `3` and
`RpcSs` is running — the errors are cosmetic. See §6 for where a Wine fix would live if it were
needed (it is not, for this task).

## 6. Wine-side implementation state of the named call

| item | value |
|---|---|
| failing import | **`RegGetValueW`** from `ADVAPI32.dll` (IAT RVA `0x18000e000` of `Cnc.Utilities.Core.Windows.dll`) |
| Wine tree | `wine-11.18/dlls/kernelbase/registry.c:1900` (`RegGetValueW`, kernelbase.@) |
| status | **fully implemented** (not a stub/`fixme`): opens the subkey, calls `RegQueryValueExW`, expands/nulls strings, returns the underlying error |
| observed behaviour | returns `ERROR_FILE_NOT_FOUND` because the value genuinely does not exist; identical to Windows |
| `err:ole:start_rpcss` | `wine-11.18/dlls/combase/rpc.c:185 start_rpcss()` (line 229) — benign here |
| `err:secur32:start_samss` | `wine-11.18/dlls/secur32/lsa.c:128 start_samss()` (line 172) — benign here |
| SCM one-service-at-a-time | `wine-11.18/programs/services/services.c:1079 service_wait_for_startup()`, `:44 service_pipe_timeout` (=30000 in this tree, our patch 0101) |

## 7. Fixability verdict and what is left

* **Wine patch needed? No — nothing in Wine is at fault on the failing path.** The throw is the
  application's own `win32::RegistryError` from a *correctly implemented* Wine API; Windows would
  behave identically with that value missing. "Patchable in Wine" would mean faking application
  data, which is not a Wine fix.
* The real fix is an install fix: also run the **English Language Pack**
  (`/run/media/asdf/Windows/mastercam-media/support/languagepacks/2027_en_language_pack_mastercam.exe`)
  — and, per the Windows reference, the **Updater** MSI — or at minimum seed
  `HKLM\SOFTWARE\CNC Software\Mastercam 2027\ApplicationLocaleName = "en"` (done in
  `state/work/prefix`) together with the language pack's `en\` resource tree.
* If a Wine-side hardening were ever wanted (it is **not** required to make Mastercam work), it would
  have to be an app-compat shim writing that value — not a change to any of the APIs above.
* Remaining blocker (out of scope, next investigation): after the fix both processes stay alive but
  only own 1×1 hidden windows for ≥75 s — no `Mastercam 2027` window and no 400×400
  `Checking license...` splash. Both entry points are *past* the crash and now need the missing
  `en\` resource tree / the licence path to be looked at.

## 8. Artifacts

* `logs/runs/direct1/` `+seh,+module,+ole,+rpc,+service` (Mastercam.exe, pre-fix)
* `logs/runs/direct2/` `+reg,+seh` (the `RegGetValueW … ApplicationLocaleName` line, pre-fix)
* `logs/runs/launch2/` `+reg,+seh` (launcher: same value, then `c0000409`)
* `logs/runs/direct3/` (Mastercam.exe, post-fix — no `loader_init` failure)
* `logs/runs/launch3/` (launcher, post-fix — no exception, 75 s)
* `winedbg` transcripts (FIFO-driven, `HKCU\Software\Wine\WineDbg\BreakOnFirstChance=1`):
  `logs/runs/winedbg/mastercam_exe_bt.txt` (`bt all` at the `MCTool.dll` exception) and
  `logs/runs/winedbg/mastercamlauncher_bt.txt` (launcher `bt` at the same exception).
* MSI evidence: `msiinfo export Mastercam_Installer.msi Registry` → `/tmp/wdbg/reg.idt` (912 rows, no
  `ApplicationLocaleName`).
* Windows ground truth: live `reg query` on the `win11` VM via `tools/vm/vmcmda.sh` (output above).

---

## 9. Follow-up: installing the English Language Pack, and what the UI does now

The missing registry value was fixed by installing the companion product the bootstrapper installs
on Windows.

### 9.1 Language pack install — works under our Wine

```
WINEPREFIX=$PWD/state/work/prefix wine \
  "/run/media/asdf/Windows/mastercam-media/support/languagepacks/2027_en_language_pack_mastercam.exe" \
  /s /v"/qn REBOOT=ReallySuppress"        # rc=0, ~68 s
```

Verified afterwards:

| check | result |
|---|---|
| `HKLM\SOFTWARE\CNC Software\Mastercam 2027` | now has `LanguagePackProvider=Mastercam`, `LanguagePackVersion=29.0.10172.0`, `LocalLanguagePacksDirectory=Z:\…\support\languagepacks` (+ our `ApplicationLocaleName=en`) — the same block the Windows VM has |
| uninstall entry | `Mastercam 2027 English Language Pack` (product code `{C253C79A-…}`) |
| `en\` trees | `en\` (31 resource DLLs incl. `opmanres.dll`, `MCToolRes.dll`, `MCCoreRes.dll`), `apps\en`, `chooks\en`, `Extensions\en`, `importexport\en`, `simulator\en`, `help\en`, `Documentation\en` |
| `*Res.dll` count | **95 — exactly the Windows reference count (95)** |
| app dir total | 8129 files / 3.0 GB (Windows: 10908; still missing the `Mastercam 2027 Updater` and `Common Files\Mastercam\MastercamLicensing` products) |

No Wine errors during the install (`WINEDEBUG` default; `CryptDecodeObjectEx … 1.3.6.1.4.1.311.2.1.4`
fixmes and `InvokeShellLinker failed to extract icon` for the documentation PDFs only).

### 9.2 `Mastercam.exe` (240 s) — real dialogs now, but the licence gate

The process stays up the whole 240 s and creates **viewable** UI (Map State: IsViewable):

```
0x206a16 (frame 356x147) -> 0x1200001 "Warning"      (client 354x124, OK)   <- text area NOT painted
0x206a7b (frame 253x105) -> 0xc00001  "Exiting..."   (client 251x82,  OK)   <- OCR: "No Valid Mastercam License found"
0xc00003 / 0xc00002      hidden 1x1 message + "Default IME" windows
crashpad_handler.exe     started by the app
```

* The `Exiting...` text matches the resource string in `en/opmanres.dll`:
  `Exiting... No Valid Mastercam License found`.
* The `Warning` dialog's client area is a solid black rectangle (no glyphs at any brightness
  threshold 0–255 inside it) — the app's own text is never painted there under Wine, so OCR cannot
  read it. `en/opmanres.dll` is the string DLL that holds `No Mastercam license found.  Do you have
  an activation code?` and the licence error strings.
* Dismissing `Warning` (click OK) then `Exiting...` (click OK) **terminates the process**. There is
  no `Mastercam 2027` main window, no 400×400 `Checking license...` splash and no activation prompt
  in any sample (20…240 s).
* Timeline from `+reg,+seh` (mc_diag): the dialogs exist by t=10 s; the app spends the remainder
  inside .NET/CLR activation (`mscoree` CLR-version lookups for
  `C:\windows\Microsoft.NET\Framework64\v4.0.30319\clr`).

### 9.3 `MastercamLauncher.exe` (240 s) — same terminus

Alive all 240 s, one viewable dialog `0xc00001 "MastercamLauncher"` (159×103 frame), OCR:
**"No license found"** — i.e. exactly the terminus already documented in
`docs/LICENSING_VERDICT.md` ("launcher loads, then reports `No Mastercam license found.`").

### 9.4 The next blocker is the (already documented) licensing wall

* `WIBUCM64.dll` (CodeMeter) is loaded by `Mastercam.exe` during start-up (`+module` trace:
  `MODULE_InitDLL (… L"WIBUCM64.dll", THREAD_ATTACH)`), so the licence check goes through
  CodeMeter's client.
* `docs/LICENSING_VERDICT.md` (and `docs/CODEMETER_ON_WINE.md`) already prove **why** that can never
  succeed here: the CodeMeter service never publishes `Global\CmApiCallIn` because the Wibu/HASP
  **kernel driver + device surfaces** (`vusb.sys`, `\\.\pipe\SafeNet-SentinelPIPE-…`, `\\.\Nsi`,
  `\\.\PhysicalDriveN`, …) do not exist in Wine — architectural, not an API stub.
* So the app can only reach its "no valid licence" exit path, which is what we observe; the Windows
  reference reaches the *interactive* licence UI (splash + activation prompt) because its licensing
  stack initialises there. This is the same wall, now hit *after* the crash documented in §1–§8.
* **Conclusion for "does the UI open?": no.** Wine's user32/GDI do create real windows (the dialogs
  above are visible and clickable, and clicking them works), but the licence gate fires before the
  main window, so the Windows target state is not reachable under Wine.

### 9.5 Side finding — not the blocker

`err:module:import_dll Library ManagedUI.Controllers.dll (which is needed by
L"…\Mastercam 2027\ManagedUI\MCCore.Controllers.dll") not found` (first hard error, ~2 s in).
`+module` shows `ManagedUI.Controllers.dll` was mapped 0.66 s earlier by the CLR (full path,
`build_module loaded …`) and then detached; `MCCore.Controllers.dll` (a mixed-mode C++/CLI assembly,
imports `ijwhost.dll`) is loaded by full path with the standard search path
(`C:\Program Files\Mastercam 2027;…` — **no `…\ManagedUI`**), so the by-name import lookup fails
(`status=c0000135`). Tested: copying `ManagedUI\Controllers.dll` into `Mastercam 2027\` makes the
error disappear **and changes nothing** (same dialogs, same exit) → it is not the blocker. Copy
reverted.

### 9.6 Artifacts (follow-up)

* `logs/runs/langpack/install.stderr` — language-pack install log
* `logs/runs/mc_lp/`, `logs/runs/mc_diag/`, `logs/runs/mc_mod/`, `logs/runs/mc_fix1/` — Mastercam.exe runs
* `logs/runs/launcher_lp/` — launcher run
* `/tmp/mc_live.stderr`, `/tmp/mc_live2.stderr`, `/tmp/mclaunch_live.stderr`, `/tmp/lch.png`,
  `/tmp/win_0x1200001.png`, `/tmp/win_0xc00001.png` — live captures (scratch)
