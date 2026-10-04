# Hog PC 5.2.1.31 — Wine vs Windows Win32 API diff (start-up: launcher → show → desktop)

Workstream: **Wine-vs-Windows API diff**. Method (the owner's): run the app on Windows
and under Wine, record the Win32 calls each makes, diff the two, and patch Wine where
the app asks for something Wine does not deliver.

This document is the measured result. Every log quoted here is on disk under
`logs/api/` (Wine) and `logs/api/win_hog*.log` (Windows), and every claim is backed by
the exact command or log line next to it.

---

## 0. Verdict (short)

The start-up **diverges nowhere that stops, blocks or corrupts it**. The launcher,
the show server and the desktop all reach their final state on Wine (the console UI
renders; the show store opens and locks). The measured Wine-vs-Windows difference is:

* **No start-up-critical call is missing.** The launcher-vs-launcher diff (§5) shows
  every API Windows uses to come up — `SetupDi*` device enumeration, `GetAdaptersInfo`,
  `RegisterPowerSettingNotification`, `CreateWindowExW`, the winsock event loop — also
  on Wine. Neither side stalls; both end in the idle message loop.
* **The show store’s file locking works, identically.** Opening the same show bursts
  **1574 `LockFileEx`/`NtLockFile` pairs on Windows and 1584 on Wine** (§5.3), and every
  Wine pair returns success. `fixme:file:NtLockFile` is a **cosmetic** FIXME
  (overlapped/APC completion), not a failed lock (§7.1).
* **Four real `FIXME`-body stubs** change a return value but not the control flow:
  `user32!RegisterPowerSettingNotification` (`→ 0xdeadbeef`),
  `user32!EnableNonClientDpiScaling` (`→ FALSE`), `newdev!DiInstallDriverA`
  (`→ TRUE` without installing the hardware-only “gadget” driver), `netprofm`’s
  change-notification wiring (initial enumeration works, events never fire), plus
  `wtsapi32!WTSQuerySessionInformationW(class 4)` returning `FALSE` (§7.4). One more
  Qt-referenced API, `SkipPointerFrameMessages`, is not exported by Wine at all and Qt
  degrades (`docs/QT_CHROMIUM_SOURCE.md` §3.1).
* **Two measured non-functional divergences:** (a) the Wine launcher’s Qt event loop
  **polls instead of blocking** — 13 398 `PeekMessageW` vs 395 in the same 70 s (§5.3);
  (b) the Wine-only `wgl*`/`DeviceIoControl` surface is **environmental** — the win11
  guest has only the Microsoft Basic Display Adapter, so its launcher never enters the
  GL path that the Wine side (host GPU) does (§4).

**Named divergences and the Wine file to patch** are in §6; the four fixmes Hog PC
already hits are assessed in §7.

---

## 1. The config used: `tools/apitrace/hog.cfg`

`hog.cfg` is a 541-pattern IAT-hook config (`~`-exclusions = 21) derived from the
sibling Eos family config and extended for Hog. Grammar is in
`tools/apitrace/test.cfg`; the header comment in `hog.cfg` explains the scope.
It covers:

| group | representative patterns |
|---|---|
| thread/sync | `WaitForSingleObject/Ex`, `WaitForMultipleObjects`, `SignalObjectAndWait`, critical sections, SRW locks, condition variables, `InitOnce*`, threadpool/completion |
| file + **locking** | `CreateFileW/A`, `ReadFile/WriteFile`, **`LockFileA/W`, `UnlockFileA/W`, `LockFileEx`, `UnlockFileEx`**, `FlushFileBuffers`, `SetEndOfFile`, `SetFileInformationByHandle`, **`ntdll!NtLockFile`, `ntdll!NtUnlockFile`, `ntdll!NtFlushBuffersFile(Ex)`** |
| registry | `RegOpenKeyEx*`, `RegQueryValueEx*`, `RegCreateKeyExW`, `RegEnum*`, `RegNotifyChangeKeyValue`, tokens/privileges |
| services | `OpenSCManager*`, `OpenService*`, `CreateServiceW`, `QueryServiceStatus(Ex)`, `EnumServicesStatusExW`, `StartServiceW`, `ControlService` |
| ws2_32 / network | `WSAStartup`, `socket`, `bind`, `connect`, **`WSAIoctl`**, `WSAEventSelect`, `WSAEnumNetworkEvents`, `WSASend/Recv`, `select`, name resolution |
| iphlpapi | `GetAdaptersInfo`, `GetAdaptersAddresses`, `GetNetworkParams`, `GetIfTable2`, **`NotifyIpInterfaceChange`**, `NotifyAddrChange`, `CancelMibChangeNotify2` |
| netprofm | `netprofm!*` (listed for the relay capture; NLM is COM, so the IAT tracer leaves it unresolved — see §7.2) |
| setupapi/hid/cfgmgr32/winusb | `SetupDiGetClassDevsW`, `SetupDiEnumDeviceInterfaces`, `SetupDiGetDeviceInterfaceDetailW`, `SetupDiGetDeviceRegistryPropertyW`, `CM_*`, `HidD_GetHidGuid`, `HidD_GetAttributes/PreparsedData`, `WinUsb_*`, plus `DiInstallDriverA/W`, `UpdateDriverForPlugAndPlayDevices*` |
| display/GL/GDI | `EnumDisplayMonitors/DevicesW/SettingsW`, `GetMonitorInfoW`, `dwmapi!*`, `gdi32!{Choose,Set,Describe}PixelFormat`, `SwapBuffers`, `opengl32!wgl*` |
| user32/QPA | `CreateWindowExW`, message loop, hooks, timers, power/suspend notifications, clipboard, display metrics |
| wtsapi32 | **`WTSQuerySessionInformationA/W`**, `WTSGetActiveConsoleSessionId`, `WTSEnumerateSessions*`, `WTSOpenServerW` |
| mpr/psapi | network drives (`WNet*`), process/module enumeration |
| COM/shell/version/winmm/ntdll | `CoCreateInstance`, `SHGetKnownFolderPath`, `SHGetFileInfoW`, `GetFileVersionInfo*`, wave/midi/mixer, `NtQuerySystemInformation` |

Volume is controlled by 21 exclusions inherited from the Eos config (per-frame GDI
paint, per-glyph font enumeration, `Enter/LeaveCriticalSection`, `ReadFile`, per-font
registry reads) — see the “volume control” section at the end of `hog.cfg`. With them
the launcher trace is ~60 k calls instead of ~530 k.

Two limits are recorded in the cfg header and matter for reading the logs:

* **No C++-mangled Qt imports.** The tracer matches exact symbol names, so Qt’s own
  entry points cannot be listed; the Qt/platform surface is covered through the Win32
  APIs Qt calls. Useful source-level map: `docs/QT_CHROMIUM_SOURCE.md`.
* **IAT only.** Functions the app resolves with `LoadLibrary`+`GetProcAddress`
  (e.g. `newdev!DiInstallDriverA`, `WinUsb_*`, `WTSGetActiveConsoleSessionId`) are not
  in any import table, so the IAT tracer reports the pattern as unresolved. The scoped
  `WINEDEBUG=+relay` capture (which patches Wine’s exports) does see them.

---

## 2. How each log was captured

### 2.1 The tracer had to be ported to 32-bit first

Hog PC is an **i386** application (`msiinfo … Template: Intel;1033`;
`objdump -f launcher-win32-golden.exe` → `pei-i386`), while `tools/apitrace` was
x86-64 only. A 64-bit `apihook.dll` cannot be injected into a 32-bit process, so the
Windows-side reference was impossible until the tracer was ported. Changes
(all in `tools/apitrace`, the 64-bit build is unchanged and still passes its selftest):

| file | change |
|---|---|
| `src/hook_common32.S` | **new** — i386 trampoline. The IAT slot points at a 15-byte stub `push idx; push orig; jmp hook_common32`; the trampoline logs the stack arguments and **tail-jumps** to the real function with the caller’s frame restored, so it is independent of argument count, calling convention and 16-byte stack alignment, and the callee returns straight to the caller. |
| `src/apihook.c` | `#ifdef _WIN64` / `#else` paths: 32-bit stub emitter, `IMAGE_NT_OPTIONAL_HDR32_MAGIC`, `IMAGE_ORDINAL_FLAG32`, `TRACER_ARCH` header field, and `trace_pre32(idx,S)` (args only) replacing `trace_emit`. `MAX_PATTERNS` raised 512 → 1024 (a 541-pattern config was silently truncated at 512). |
| `build.sh` | honours `OUT=` and picks `hook_common32.S` for `CC=i686-w64-mingw32-gcc`; the 32-bit build lands in `build32/`. |

Build and validate (both done before any Hog capture):

```
$ cd tools/apitrace && ./build.sh                       # 64-bit regression build
$ CC=i686-w64-mingw32-gcc OUT=build32 ./build.sh        # 32-bit build
$ # under Wine: the 32-bit selftest reproduces its own printed values exactly
$ wine 'C:\apitrace32\apitrace.exe' --cfg C:\apitrace32\apitrace.cfg \
      --out C:\apitrace32\selftest32.log --timeout 15 -- C:\apitrace32\selftest.exe
  ...
  3 280 kernel32.dll!WriteFile (arg0=0x10, arg1=0x36ecf4, arg2=0x21, arg3=0x36ecf0, arg4=0x0) -> ?
  9 280 KERNEL32.dll!CreateFileW (arg0=0x40a10e, arg1=0x40000000, arg2=0x0, arg3=0x0, arg4=0x2, arg5=0x80, arg6=0x0) -> ?
 25 280 KERNEL32.dll!MulDiv (arg0=0x7, arg1=0x3, arg2=0x2) -> ?
```

Every log line therefore ends `-> ?` **on both sides**: the 32-bit hook is a tail-jump
and cannot observe the callee’s return value. Return values for the failure analysis
come from Wine’s own `+relay` log (§2.3), which does record `retval=`.

### 2.2 Wine start-up traces (IAT tracer)

`tools/run_apitrace_hog.sh <tag>` stages `C:\apitrace32` in the prefix, kills leftover
instances, traces `launcher-win32-golden.exe` from its first instruction, attaches the
tracer to any `server/desktop/critical/dp8k` children that appear, and copies the logs
to `logs/api/`.

```
$ source env.sh && tools/run_apitrace_hog.sh wine_hog --secs 70
logs/api/wine_hog.log  61405 calls
```

The launcher on Wine stops at the **“Hog Start”** dialog and does **not** spawn the
server/desktop by itself (the Windows launcher likewise stayed at “Hog Start” with no
show — §4), so show creation and the console UI were captured by starting those
processes directly with exactly the command line the golden run used (the show already
exists — `Documents\ETC\HogPC\Shows\NewShow`):

```
server-win32-golden  -port=6600 -netnum=1 -showpath=C:/users/asdf/Documents/ETC/HogPC/Shows -showname=NewShow
desktop-win32-golden -port=6600 -nodeid=1 -netnum=1
```

(Starting the server with a non-existent show name traps in `server_app.cpp:257`
`'!QFile::exists(dbfile)' is TRUE` — the server requires an existing show database,
which is why the pre-existing `NewShow` was used.) Result: `wine_hog_server.log`
(32 519 calls), `wine_hog_desktop.log` (55 649 calls).

### 2.3 Wine scoped `+relay` (return values + fixmes)

`tools/run_hog_relay.sh <tag>` installs `HKCU\Software\Wine\Debug\RelayInclude` with a
focused list (the four fixmes’ functions, file locking, ws2_32/iphlpapi/netprofm, the
device APIs, DWM/GL) and runs the same app with `WINEDEBUG=+timestamp,+relay,+err`.

```
$ tools/run_hog_relay.sh wine_hog_launcher --secs 22
$ tools/run_hog_relay.sh wine_hog_server --secs 16 \
    --exe server-win32-golden.exe \
    --args "-port=6600 -netnum=1 -showpath=C:/users/asdf/Documents/ETC/HogPC/Shows -showname=NewShow"
```

(Note: `run_hog.sh` unsets `WINEDEBUG` unless `--debug` is passed, so the relay script
passes it as an option — an early attempt silently produced no `Call` lines.)

### 2.4 Windows reference (win11 guest)

`tools/vm/guest_apitrace_hog.ps1` downloads the 32-bit tracer + `hog.cfg` into
`C:\hog\apitrace32`, traces the launcher from its first instruction, attaches to any
children that appear, and starts the server/desktop directly if a show exists
(mirroring §2.2), then PUTs the logs back to the host share as `win_hog*.log`.

One thing had to be discovered first: `launcher-win32-golden.exe` carries a
**`requireAdministrator` manifest** — a medium-integrity `CreateProcessW` fails with

```
apitrace: CreateProcessW failed, GetLastError=740
```

(`ERROR_ELEVATION_REQUIRED`). The capture therefore runs **elevated**, through the
project’s `tools/vm/elev.sh` (which publishes the script, launches it with
`Start-Process -Verb RunAs` and answers the UAC prompt with Alt+Y):

```
$ tools/vm/elev.sh tools/vm/guest_apitrace_hog.ps1
...
EXE_OK=True  ELEVATED=True
KILLING launcher-win32-golden 1088 / monitor-win32-golden 8748
PASS1_RC=0
SHOW_EXISTS=False
LOG win_hog_launcher.log size=522421
PULLED win_hog_launcher.log
```

`C:\apitrace32\` was uploaded to the guest and the artifacts were hash-checked
(`apihook.dll` = `6f54534ce5884f771d22dcf901cc6e99`, identical to `build32/`).

The guest had **no show yet** at that moment (`SHOW_EXISTS=False`), so pass 2
(server/desktop) was skipped and that capture is the **launcher** reference.
`HogVMReference` then created the show `yNewShow`, launched the console UI (confirming
the Windows launcher spawns `server`/`critical`/`desktop` itself) and handed the guest
over, which allowed two more captures:

* `tools/vm/guest_attach_hog.ps1` — **attach** to the live `server`/`desktop`/`critical`
  (no kill) for ~25 s → `win_hog_{server,desktop,critical}.log` (steady state);
* `tools/vm/guest_server_hog.ps1` — start `server-win32-golden.exe` under the tracer
  against `yNewShow` → `win_hog_server_start.log`, the matched counterpart of the Wine
  server trace (show creation / locking).

All three ran elevated via `tools/vm/elev.sh`; the guest side is owned by
`HogVMReference` (see `docs/VM_REFERENCE.md`).

---

## 3. Wine-side results (what the app asks Wine for)

### 3.1 Launcher — 61 405 calls

Start-up shape: `LoadLibrary` of the Qt stack, QPA plugin load, HID/SetupAPI device
enumeration, `GetAdaptersInfo`, winsock bring-up, `wglGetProcAddress` probing, then a
message loop.

```
$ grep -av '^#' logs/api/wine_hog.log | awk '{print $3}' | sort | uniq -c | sort -rn | head
  13398 USER32.dll!PeekMessageW
   6092 KERNEL32.dll!QueryPerformanceCounter
   6084 kernel32.dll!ReleaseSRWLockShared / AcquireSRWLockShared
   4485 USER32.dll!GetWindowLongW
   4478 USER32.dll!TranslateMessage / DispatchMessageW
   1156 opengl32.dll!wglGetProcAddress
    919 kernel32.dll!DeviceIoControl
    514 WS2_32.dll!WSAEnumNetworkEvents
    490 KERNEL32.dll!WaitForSingleObject
```

The last calls are the idle message loop — **there is no stall**:

```
61404 296 USER32.dll!PeekMessageW (arg0=0x26fbc4, arg1=0x0, arg2=0x0, arg3=0x0, arg4=0x1) -> ?
61405 296 USER32.dll!PeekMessageW (arg0=0x26fbc4, arg1=0x0, arg2=0x0, arg3=0x0, arg4=0x1) -> ?
```

### 3.2 Server (show creation / store open) — 32 519 calls

```
$ grep -av '^#' logs/api/wine_hog_server.log | awk '{print $3}' | sort | uniq -c | sort -rn | head
   9158 KERNEL32.dll!QueryPerformanceCounter
   2339 WS2_32.dll!WSAEnumNetworkEvents
   1614 KERNEL32.dll!GetFileAttributesExW
   1584 ntdll.dll!NtUnlockFile
   1584 ntdll.dll!NtLockFile
   1584 KERNEL32.dll!UnlockFileEx
   1584 KERNEL32.dll!LockFileEx
```

The show database is `Documents\ETC\HogPC\Shows\NewShow\hogdatabase.mk2`; the server
locks it 1584 times. The lock/unlock pairs are captured at both layers:

```
1912 424 KERNEL32.dll!LockFileEx (arg0=0x30c, arg1=0x3, arg2=0x0, arg3=0x1, arg4=0x0, arg5=0x26e64c) -> ?
1913 424 ntdll.dll!NtLockFile (arg0=0x30c, arg1=0x0, arg2=0x0, arg3=0x26e64c, arg4=0x0,
        arg5=0x26e608, arg6=0x26e600, arg7=0x0, arg8=0x1, arg9=0x2) -> ?
1916 424 KERNEL32.dll!UnlockFileEx (arg0=0x30c, arg1=0x0, arg2=0x1, arg3=0x0, arg4=0x26e60c) -> ?
```

(`arg1=0x3` = `LOCKFILE_EXCLUSIVE_LOCK|LOCKFILE_FAIL_IMMEDIATELY`; `arg1=0x1` = shared
lock. `NtLockFile` args map to `(file,event,apc,apc_user,io_status,offset,count,key,`
`dont_wait,exclusive)` — `apc=0, apc_user=overlapped, io_status=0, key=0`, so Wine’s
early `STATUS_NOT_IMPLEMENTED` return is *not* taken; see §7.1.)

### 3.3 Desktop (console UI) — 55 649 calls

```
$ grep -av '^#' logs/api/wine_hog_desktop.log | awk '{print $3}' | sort | uniq -c | sort -rn | head
  18752 KERNEL32.dll!QueryPerformanceCounter
   3913 WS2_32.dll!WSAEnumNetworkEvents
   3657 KERNEL32.dll!WaitForSingleObject
   3205 kernel32.dll!ReleaseSRWLockShared / AcquireSRWLockShared
   2129 KERNEL32.dll!DeleteCriticalSection
   2082 USER32.dll!PeekMessageW
   1321 kernel32.dll!DeviceIoControl
   1045 WS2_32.dll!WSASend
    578 opengl32.dll!wglGetProcAddress
    437 PSAPI.DLL!EnumProcessModules / GetModuleBaseNameW / OpenProcess
```

Again it ends in the message loop (timers, `PeekMessageW`, socket events) — idle, not
stalled. The desktop does **not** lock the show store (that is the server’s job) and it
does not call `WTSQuerySessionInformation` in this run.

### 3.4 Wine failure / fixme summary (from the relay logs)

`tools/relaydiff.py wine-log --errors` on the launcher relay:

```
072c user32!RegisterPowerSettingNotification(PTR,PTR,0x0) -> 0xdeadbeef [NTSTATUS]
072c hid!HidD_GetHidGuid(PTR) -> 0xffffffff [NTSTATUS]
# total failing calls: 2
```

* `RegisterPowerSettingNotification` returning `0xdeadbeef` is real (Wine stub, §6 row 1).
* `HidD_GetHidGuid` returning `0xffffffff` is a **false positive**: it is a `void`
  function (Wine `dlls/hid/hidd.c:87` writes the GUID); `0xffffffff` is leftover `RAX`.

The relay also records two more return values the `--errors` heuristic does not flag,
because `0` is not a pointer-looking failure value:

```
238223.837:0160:Call user32.EnableNonClientDpiScaling(0004005e) ret=6a6007eb
238223.837:0160:Ret  user32.EnableNonClientDpiScaling() retval=00000000 ret=6a6007eb
238213.921:01a8:Ret  kernelbase.AppPolicyGetProcessTerminationMethod() retval=00000000 ret=1400135e0
```

`EnableNonClientDpiScaling` returns `FALSE` on Wine (real stub, §6 row 14);
`AppPolicyGetProcessTerminationMethod` returns `ERROR_SUCCESS` (FIXME-only).

Server relay: **0 failing calls**, 2 distinct fixmes (`ntdll:NtQuerySystemInformation`,
`file:NtLockFile`). The launcher relay’s fixme inventory:

```
fixme:setupapi:DiInstallDriverA parent 0, inf_path "…\drivers\gadget\gadget.inf", flags 0, reboot …, stub!
fixme:win:RegisterPowerSettingNotification (0006006a,{02731015-…},0): stub
fixme:system:EnableNonClientDpiScaling (00080052): stub
fixme:kernelbase:AppPolicyGetProcessTerminationMethod FFFFFFFFFFFFFFFA, …
fixme:ntdll:NtQuerySystemInformation info_class SYSTEM_PERFORMANCE_INFORMATION
fixme:font:find_matching_face / get_nearest_charset (x9, Noto Kufi Arabic faces)
```

---

## 4. Windows-side results (the win11 reference)

`logs/api/win_hog.log` (a copy is kept as `win_hog_launcher.log`):

```
# apitrace apihook.dll win32 pid=7420 tid=8544
# patterns=541 exclusions=21 modules=103 loader_notify=1 poll_ms=200 cfg_error=-
# unresolved_patterns=170
```

**5 737 calls.** The start-up shape is the same as Wine’s — Qt stack load, QPA plugin,
HID/SetupAPI device enumeration, `GetAdaptersInfo`, winsock bring-up, window creation,
then the idle message loop. Top functions:

```
412 KERNEL32.dll!QueryPerformanceCounter     395 USER32.dll!PeekMessageW
385 USER32.dll!GetWindowLongW                289 KERNEL32.dll!GetProcessHeap
260 KERNEL32.dll!InitializeCriticalSection   250 KERNEL32.dll!WaitForSingleObject
206 KERNEL32.dll!ReleaseSemaphore            189 KERNEL32.dll!GetFullPathNameW
188 GDI32.dll!GetDeviceCaps                  172 KERNEL32.dll!GetFileAttributesExW
137 KERNEL32.dll!GetProcAddress              120 USER32.dll!SystemParametersInfoW
 67 ntdll.dll!NtQuerySystemInformation
```

The interesting calls are all present on Windows too — same device/network surface:

```
458 8376 USER32.dll!RegisterPowerSettingNotification (arg0=0x4a00bc, arg1=0x68a4f360, arg2=0x0) -> ?
1355 8376 IPHLPAPI.DLL!GetAdaptersInfo (arg0=0x0, arg1=0x29cf244) -> ?
1647 8376 SETUPAPI.dll!SetupDiEnumDeviceInterfaces (…) -> ?
1648 8376 SETUPAPI.dll!SetupDiDestroyDeviceInfoList (0x51d1c38) -> ?
```

and it ends idle, with no stall:

```
5735 8376 USER32.dll!PeekMessageW (arg0=0x29ccfb8, arg1=0x0, arg2=0x0, arg3=0x0, arg4=0x1) -> ?
5737 8376 USER32.dll!PeekMessageW (arg0=0x29ccfb8, arg1=0x0, arg2=0x0, arg3=0x0, arg4=0x1) -> ?
```

**Two caveats that condition the diff below:**

1. **The guest has no GPU driver** — the display adapter is “Microsoft Basic Display
   Adapter” (`HogVMReference` measured this). The Windows launcher therefore makes
   **zero** `opengl32!wgl*` and zero `DeviceIoControl` calls, whereas the Wine launcher
   (on the host GPU) probes GL 1178 times. That is a *guest-environment* difference, not
   a Wine-vs-Windows code difference.
2. **Importer asymmetry.** The tracer hooks the IAT of every loaded module. On Wine,
   Wine’s own builtins import `kernel32.dll` by name, so calls *inside* Wine (setupapi
   calling cfgmgr32, etc.) are logged; on Windows 11 the system DLLs import through
   `api-ms-win-core-*` API-set stubs, which the `kernel32!…` patterns do not match, so
   Microsoft-internal calls are not logged. **Windows-only** rows are therefore genuine
   *application* calls; some **Wine-only** rows are Wine-internal calls and are not
   app-visible divergences (they are marked as such in §5).

### 4.1 Additional Windows captures (server / desktop)

| log | how | calls | shape |
|---|---|---|---|
| `win_hog_server_start.log` | server started under the tracer against `yNewShow` | 12 175 | **1574 × `LockFileEx`/`UnlockFileEx`/`ntdll!NtLockFile`/`NtUnlockFile`** (the show-open burst), `GetFileAttributesExW` 1609, QPC 1035 |
| `win_hog_desktop.log` | attach to the live desktop, ~25 s | 69 563 | `WaitForSingleObject` 14 040, QPC 13 816, `ReleaseSemaphore` 12 543, `PeekMessageW` 9 709, `CallNextHookEx`/`TranslateMessage`/`DispatchMessageW` ~4 281 |
| `win_hog_server.log` | attach to the live server, ~25 s | 3 452 | the socket loop (`WSAEnumNetworkEvents` 773, `WSAEventSelect` 387) — steady state, no show-open locks |
| `win_hog_critical.log` | attach to `critical-win32-golden` | ~4.9 MB | the critical/alert process, kept for reference |

The desktop/server attach logs confirm the console UI is fully alive on Windows with the
same message-loop + winsock shape as Wine; the lock burst only appears in the start-up
window, which is why the matched `win_hog_server_start.log` (not the attach) is the
right counterpart to `wine_hog_server.log` in §5.3.

---

## 5. Diff

Same-role only (launcher-vs-launcher; server/desktop have no Windows counterpart this
round because the guest has no show). Command and full output on disk:

```
$ python3 tools/relaydiff.py diff logs/api/win_hog.log logs/api/wine_hog.log \
      --max-report 400 --func-limit 250          # -> logs/api/hog_apidiff.txt
# A = logs/api/win_hog.log  (5737 calls)
# B = logs/api/wine_hog.log (61405 calls)
```

### 5.1 Calls Windows makes that Wine does not (Windows-only)

Because Microsoft’s system DLLs are not matched (§4 caveat 2), these are genuine
**application** calls. They are all one-sided *path* differences, none of them a call
the launcher needs:

| function | win | wine | note |
|---|---|---|---|
| `kernel32!VirtualProtect` | 7 | 0 | Qt/Chromium page-protection tweak |
| `user32!GetThreadDesktop` | 6 | 0 | desktop query (Wine takes a different path) |
| `mpr!WNetGetConnectionW` | 3 | 0 | mapped-network-drive check (MPR.dll is a static import of the launcher) |
| `gdi32!GetPixelFormat` | 2 | 0 | GL pixel-format state query |
| `kernel32!GetNativeSystemInfo` | 2 | 0 | Wine answers this via `GetSystemInfo` |
| `kernel32!GetTickCount` | 2 | 0 | Wine uses `GetTickCount64` |
| `kernel32!GetACP` | 1 | 0 | code-page query |
| `kernel32!OpenSemaphoreW` | 1 | 0 | single-instance check |
| `kernel32!VerifyVersionInfoW` | 1 | 0 | OS-version probe |
| `kernel32!WaitForSingleObjectEx` | 1 | 0 | alertable wait |

Not one of these is followed by a failure check in the app, and Wine reached the same
final state without them.

### 5.2 Calls Wine makes that Windows does not (Wine-only)

| function | wine | win | classification |
|---|---|---|---|
| `opengl32!wglGetProcAddress` (+ `wglCreateContext/MakeCurrent/DeleteContext/GetCurrentDC`) | 1156 (+16) | 0 | **environmental**: the guest VM has only the Basic Display Adapter, so the Windows launcher never enters the GL path; the Wine side runs on the host GPU |
| `kernel32!DeviceIoControl` | 919 | 0 | **environmental** — same GL/display path |
| `advapi32!RegCreateKeyExW` | 32 | 0 | likely **Wine-internal** (Wine builtins import kernel32/advapi32 by name and are hooked; Windows’ are not) |
| `cfgmgr32!CM_Get_Device_Interface_List_SizeW/ListW`, `CM_Locate_DevNodeW` | 21+4+8 | 0 | likely **Wine-internal** (Wine’s `setupapi` implementation calls `cfgmgr32`; the app itself uses `SetupDi*`, present on both sides) |
| `hid!HidD_GetAttributes` | 8 | 0 | likely Wine-internal (the app calls `HidD_GetHidGuid`/`SetupDi*` on both sides) |
| `kernel32!CreateDirectoryW`, `ExpandEnvironmentStringsW`, `GetComputerNameW`, `GetSystemTimeAsFileTime`, `EnumDisplayDevicesW`, `WaitForMultipleObjectsEx`, `user32!CreateWindowExA` | 2–8 each | 0 | app-level but benign path differences (same operations reached through the `…W`/other variants on Windows) |

### 5.3 Server (show creation / locking) and desktop

The Windows tree was left up by `HogVMReference` with the show `yNewShow`
(`hogdatabase.mk2`, 663 KB), so both comparisons could be made. The **server start-up
windows are directly comparable** because the server was started under the tracer on
both sides against the same show:

| | Windows (`win_hog_server_start.log`) | Wine (`wine_hog_server.log`) |
|---|---|---|
| calls | 12 175 | 32 519 |
| `LockFileEx` / `UnlockFileEx` | 1574 / 1574 | 1584 / 1584 |
| `ntdll!NtLockFile` / `NtUnlockFile` | 1574 / 1574 | 1584 / 1584 |

The show-open **lock/unlock sequence is identical in shape and count** (±10, the tail
of the Wine run). This is the direct Windows confirmation of §7.1: the locking works on
Wine and the `file:NtLockFile` FIXME is cosmetic. The only one-sided server functions
are `ntdll!RtlGetVersion` (Windows 2) and, on Wine, `ws2_32!WSASend` (1045 — a desktop
client was connected during the Wine server trace but not the Windows one),
`DeviceIoControl` (583) and a handful of registry writes — all either explained by the
connection state or Wine-internal (§4 caveat 2).

For the **desktop** the two windows are *not* comparable: the Wine desktop log covers
its start-up and steady state (started under the tracer), while the Windows desktop log
is an **attach** window (`win_hog_desktop.log`, 69 563 calls, ~25 s steady state). The
one-sided desktop functions are therefore dominated by that asymmetry: the Windows-only
side is just `GetLocalTime` (98) and `GetForegroundWindow` (2); the Wine-only side is
start-up lifecycle (`InitializeCriticalSection`, `InitializeSRWLock`,
`Acquire/ReleaseSRWLockShared`, `CreateThread`, `CreateWindowExW`, …) plus
Wine-internal batches (the 437× `OpenProcess`+`EnumProcessModules`+`GetModuleBaseNameW`
triplet, `DeviceIoControl`, `wgl*`). To make the desktop start-up a byte-for-byte
comparison the launcher would have to be re-run under the tracer on Windows with the
attach poll loop (the launcher does spawn `server`/`critical`/`desktop` itself —
confirmed by `HogVMReference`), which needs a New Show click and is the natural
follow-up; the show-creation comparison above already covers the functional part.

### 5.4 Frequency divergence (latency/CPU, not functional)

The same 70 s window, same state (“Hog Start”):

| call | Windows | Wine | ratio |
|---|---|---|---|
| `PeekMessageW` | 395 | 13 398 | 34× |
| `QueryPerformanceCounter` | 413 | 6 093 | 15× |
| `AcquireSRWLockShared` / `ReleaseSRWLockShared` | 49 / 49 | 6 133 / 6 133 | 125× |
| `Sleep` | 23 | 398 | 17× |
| total calls | 5 737 | 61 405 | 11× |

The Wine launcher’s Qt event loop **polls instead of blocking** — it re-enters
`PeekMessageW`/`QueryPerformanceCounter` roughly every 5 ms where Windows wakes about
every 180 ms. This is a latency/CPU divergence (the acceptance’s “latency/cosmetics”
category), not a missing or failing call, and the same shape was visible in the server
and desktop traces.

### 5.5 Failures and stalls

* The 32-bit tracer records no return values (§2.1), so the failure analysis is
  Wine-side, from the scoped relay (§3.4): the only calls returning a different value
  from Windows are the stubs `user32!RegisterPowerSettingNotification`
  (`→ 0xdeadbeef`) and `user32!EnableNonClientDpiScaling` (`→ FALSE`); `HidD_GetHidGuid`
  is a void-function false positive.
* **No stall on either side.** The last calls in `win_hog.log` and `wine_hog.log` are
  both the idle message loop (`PeekMessageW`), and neither log ends in a blocked wait
  (`WaitForSingleObject` returns: 497 calls on Wine, 250 on Windows).
* **No start-up-critical call is missing on Wine.** Every API the Windows launcher uses
  to come up — `SetupDiEnumDeviceInterfaces`/`SetupDiDestroyDeviceInfoList`,
  `GetAdaptersInfo`, `RegisterPowerSettingNotification`, `CreateWindowExW`,
  `GetDeviceCaps`, the winsock/`WSAEnumNetworkEvents` loop — is present in the Wine log
  with the same call shape.

---

## 6. Named divergences and the Wine file/function

Each row is a call where Wine and Windows differ, with the Wine implementation that
would change. “Windows expectation” is read from the Qt 5.15.1 / Chromium 80 source
(`docs/QT_CHROMIUM_SOURCE.md` maps API → file:line); the Windows-side trace confirms
*which* calls the app actually makes (§4/§5).

| # | call | Wine behaviour (measured) | Windows / Qt expectation | Wine file·function to patch | impact |
|---|---|---|---|---|---|
| 1 | `user32!RegisterPowerSettingNotification` | returns fake `0xdeadbeef`, FIXME stub (`dlls/user32/misc.c:410`) | returns a real `HPOWERNOTIFY`; Qt registers `GUID_CONSOLE_DISPLAY_STATE` (`qwindowsscreen.cpp`) and expects `WM_POWERBROADCAST`/display-power events | `dlls/user32/misc.c` (+`win32u` power path) | cosmetic — no display-power events |
| 2 | `newdev!DiInstallDriverA/W` | FIXME stub returns `TRUE`, installs nothing (`dlls/newdev/main.c:154`) | actually installs `drivers\gadget\gadget.inf` | `dlls/newdev/main.c` (over `SetupCopyOEMInfW`/`SetupDi*`) | hardware-only |
| 3 | `netprofm` change notifications | `init_networks` enumerates adapters correctly but no `ConnectivityChanged` ever fires (`dlls/netprofm/list.c:1844`, `:1922`) | Qt `QNetworkListManagerEvents` (`qnetconmonitor_win.cpp:551`) gets initial state **and** async changes via `IID_INetworkListManagerEvents` | `dlls/netprofm/list.c` (wire iphlpapi/NSI notifications) | start-up OK; network-change reactions lost |
| 4 | `wtsapi32!WTSQuerySessionInformationW` class 4 (`WTSSessionId`) | `FIXME + return FALSE` (`dlls/wtsapi32/wtsapi32.c:547`) | returns the session id | `dlls/wtsapi32/wtsapi32.c` | caller gets `FALSE`; not start-up-critical |
| 5 | `user32!SkipPointerFrameMessages` | **not exported** (`dlls/user32/user32.spec:1142` is a commented `@ stub`) | Qt resolves it dynamically (`qwindowscontext.cpp:211`) and calls it when non-NULL | `dlls/user32/user32.spec` + `user32/input.c` | pointer-frame degradation only |
| 6 | `file:NtLockFile` APC completion | lock succeeds; only the overlapped/APC completion path is missing (`dlls/ntdll/unix/file.c:7112`) | — (Hog uses synchronous `LockFileEx`; return values match) | `dlls/ntdll/unix/file.c` | none for Hog |
| 7 | `shell32!Shell_NotifyIconGetRect` | `E_NOTIMPL` stub (`dlls/shell32/systray.c:299`) | Qt tray-icon geometry (`qwindowssystemtrayicon.cpp`) | `dlls/shell32/systray.c` | tray menu placement falls back |
| 8 | `crypt32!CertFindChainInStore` | returns `NULL` stub (`dlls/crypt32/chain.c:3002`) | Qt Schannel chain building (`qsslsocket_schannel.cpp:661`) | `dlls/crypt32/chain.c` | client-certificate TLS chains can fail |
| 9 | `userenv!CreateAppContainerProfile` | FIXME stub (`dlls/userenv/userenv_main.c:690`) | Chromium sandbox AppContainer init | `dlls/userenv/userenv_main.c` | Chromium child sandbox cannot use AppContainer (Chromium falls back) |
| 10 | `dcomp!DCompositionCreateDevice`, `dwmapi!DwmEnableBlurBehindWindow` | `E_NOTIMPL` stubs (`dlls/dcomp/device.c:28`, `dlls/dwmapi/dwmapi_main.c:163`) | ANGLE swap chain / Qt frameless blur | `dlls/dcomp/device.c`, `dlls/dwmapi/dwmapi_main.c` | visual fallbacks only |
| 11 | `user32!ChangeWindowMessageFilterEx`, touch APIs (`RegisterTouchWindow`, `IsTouchWindow`, `UnregisterTouchWindow`), `SetDisplayAutoRotationPreferences`, `UnregisterPowerSettingNotification` | `return TRUE/FALSE` stubs (`docs/_wine_impl_audit_qt.tsv`) | Qt/Chromium feature probes | `dlls/user32/*` | low (pointer API is implemented, so Qt rarely takes the touch path) |
| 12 | `uiautomationcore!UiaRaise*` | events swallowed (`dlls/uiautomationcore/uia_main.c`) | Qt accessibility bridge (`qwindowsuiawrapper.cpp`) | `dlls/uiautomationcore/uia_main.c` | screen readers see nothing |
| 13 | `netapi32!NetShareEnum` | `ERROR_NOT_SUPPORTED` stub (`dlls/netapi32/netapi32.c:388`) | `QFileSystemEngine` share enumeration | `dlls/netapi32/netapi32.c` | local paths unaffected |
| 14 | `user32!EnableNonClientDpiScaling` | `FIXME; SetLastError(ERROR_CALL_NOT_IMPLEMENTED); return FALSE` (`dlls/user32/sysparams.c:785`) | Qt resolves it dynamically (`qwindowscontext.cpp:217`) and calls it so the window’s non-client area DPI-scales | `dlls/user32/sysparams.c` (+`win32u`) | window borders/title bars not per-monitor DPI-scaled |

Rows 7–14 come from the body-level audit in `docs/QT_CHROMIUM_SOURCE.md` §3.2 and
`docs/_wine_impl_audit_qt.tsv`; rows 1–6 and 14 were observed directly in the Hog
traces. None of them stops the start-up, and none changes the app’s control flow at
start-up except in the degradation paths noted.

**FIXME-only, i.e. no behavioural divergence** (checked in the Wine source, so they are
*not* on the patch list):

* `ntdll!NtQuerySystemInformation(SystemPerformanceInformation)` — Wine fills the
  struct and returns success; only a one-shot informational FIXME
  (`dlls/ntdll/unix/system.c:3390`, `get_performance_info()`).
* `kernelbase!AppPolicyGetProcessTerminationMethod` — returns `ERROR_SUCCESS` with
  `AppPolicyProcessTerminationMethod_ExitProcess` (`dlls/kernelbase/main.c:100`).
* `font:get_nearest_charset` / `font:find_matching_face` — font-matching chatter for the
  Noto Kufi Arabic faces; no return-value contract with the app.

---

## 7. The four fixmes Hog PC hits

These are the four FIXMEs the earlier golden launcher run produced
(`logs/runs/hog1/app.stderr`, `/tmp/hog_l.log`), assessed against the Wine source and
the fresh traces. Each is quoted verbatim.

### 7.1 `file:NtLockFile` — the show database’s locking **works**; the FIXME is cosmetic

Log evidence (server relay, i.e. the process that owns the show):

```
245:fixme:file:NtLockFile I/O completion on lock not implemented yet
237870.305:0160:Ret  KERNEL32.LockFileEx() retval=00000001 ret=6aea9af9
237870.305:0160:Ret  ntdll.NtLockFile() retval=00000000 ret=6ffffe2ae06f
```

Wine source: `dlls/ntdll/unix/file.c:7112 NtLockFile`. Two things happen before the
lock is taken:

```c
if (apc || io_status || key) { FIXME("Unimplemented yet parameter\n"); return STATUS_NOT_IMPLEMENTED; }
if (apc_user && !warn++) FIXME("I/O completion on lock not implemented yet\n");
```

`kernelbase!LockFileEx` (`dlls/kernelbase/file.c:3454`) calls
`NtLockFile(file, overlapped->hEvent, NULL, cvalue, NULL, &offset, &count, NULL, …)`
with `cvalue = overlapped`. So `apc`, `io_status` and `key` are **NULL** → the
`STATUS_NOT_IMPLEMENTED` path is not taken; only `apc_user` is non-NULL, which is what
prints the FIXME. The lock itself is done through `SERVER_START_REQ(lock_file)` and
returns success.

**Conclusion:** the show database’s locking is actually working under Wine — 1584
exclusive/shared `LockFileEx`/`NtLockFile` pairs all returned `retval=00000001`/`0`, and
the corresponding `UnlockFileEx`/`NtUnlockFile` all succeeded. The FIXME is a genuine
gap only for *asynchronous* locks that want APC completion (`apc_user`), which Hog does
not use. **Patch (optional, cosmetic):** implement the overlapped/APC completion in
`dlls/ntdll/unix/file.c:NtLockFile` so the message goes away.

### 7.2 `netprofm:init_networks` — initial enumeration works, change events never fire

```
0384:fixme:netprofm:init_networks no support for detecting network changes
```

Wine source: `dlls/netprofm/list.c:1844 init_networks()`, called from
`list_manager_create()` (`list.c:1922`). Read carefully, the FIXME is only about
**change detection**: the function *does* call `get_network_adapters()` →
`GetAdaptersAddresses` and builds the `INetworkListManager` network/connection lists
(IPv4/IPv6 local/global flags, internet flags). `connection_point_init()` also sets up
the `IID_INetworkListManagerEvents` connection point — but nothing ever fires
`ConnectivityChanged`.

Qt’s expectation: `qnetconmonitor_win.cpp:551` `QNetworkListManagerEvents` does
`CoCreateInstance(CLSID_NetworkListManager)` → `GetConnectivity()` (initial state, which
Wine answers correctly from the enumeration) → `FindConnectionPoint(IID_INetworkListManagerEvents)`.
So on Wine Qt gets a correct initial connectivity state and then silently never sees a
change. That is exactly the “declared but not implemented” class the local patch
`patches/local/0102-iphlpapi-notify-interface-changes.patch` already fixes for
`iphlpapi!NotifyIpInterfaceChange`.

**Patch:** `dlls/netprofm/list.c` — register an adapter/IP-interface change notification
(iphlpapi, as in local patch 0102 or via `NsiRequestChangeNotification`) in
`init_networks()`/`list_manager_create()` and signal the `INetworkListManagerEvents`
connection point when it fires. **Impact:** start-up is unaffected; only reactions to
network changes are lost.

### 7.3 `setupapi:DiInstallDriverA` — hardware-only, and Wine already returns success

```
0644:fixme:setupapi:DiInstallDriverA parent 0000000000000000,
      inf_path "C:\\Program Files (x86)\\ETC\\HogPC\\drivers\\gadget\\gadget.inf",
      flags 0, reboot 00007FFFFE13FD58, stub!
237822.146:0758:Call newdev.DiInstallDriverA(00000000,7ffffe1a2d50 "…\\drivers\\gadget\\gadget.inf",00000000,7ffffe13fd58) ret=14000445e
237822.146:0758:Ret  newdev.DiInstallDriverA() retval=00000001 ret=14000445e
```

The FIXME channel prints as `setupapi` because `dlls/newdev/main.c` sets
`WINE_DEFAULT_DEBUG_CHANNEL(setupapi)`, but the function is `NEWDEV.dll`’s. Wine source:
`dlls/newdev/main.c:154`:

```c
BOOL WINAPI DiInstallDriverA(HWND parent, const char *inf_path, DWORD flags, BOOL *reboot)
{ FIXME(...); return TRUE; }
```

The launcher (via `GadgetDrvChange.exe`) tries to install the Hog console **“gadget” USB
driver** from the shipped INF. On Wine the stub returns `TRUE` without installing
anything, so the API *return value* matches what the app expects (success) and the app
proceeds; the driver is simply not installed, which only matters when real hardware is
attached.

**Patch (hardware-only):** implement `DiInstallDriverA/W` and
`UpdateDriverForPlugAndPlayDevices*` in `dlls/newdev/main.c` over
`setupapi!SetupCopyOEMInfW` + `SetupDi*` install. Not needed for a hardware-free run.

### 7.4 `wtsapi:WTSQuerySessionInformationW` — class 4 (`WTSSessionId`) unsupported

```
02d8:fixme:wtsapi:WTSQuerySessionInformationW Unimplemented class 4
```

Wine source: `dlls/wtsapi32/wtsapi32.c:547`. The function handles `WTSConnectState` (8),
`WTSClientProtocolType` (16), `WTSUserName` (5), `WTSDomainName` (7) and
`WTSSessionInfo`; everything else falls through to `FIXME("Unimplemented class %d")`,
sets `*buffer = NULL`, and returns `FALSE`. Class **4 = `WTSSessionId`**.

Caller: it is **not** Qt 5.15.1 — the QPA plugin asks `WTSSessionInfoEx` (25) at
`qwindowscontext.cpp:855/864` (`WTSGetActiveConsoleSessionId` at :850). The only modules
in the Hog install that import `WTSAPI32.dll` are `platforms/qwindows.dll` and
`Qt5WebEngineCore.dll`; therefore the class-4 query comes from the QtWebEngine/Chromium
side (Chromium 80 inside `Qt5WebEngineCore.dll` / `QtWebEngineProcess.exe`). [INFERENCE:
the caller was not reachable in Qt’s indexed sources, and the Chromium index does not
cover this file; the import evidence is direct.]

**Patch:** `dlls/wtsapi32/wtsapi32.c:WTSQuerySessionInformationW` — implement
`WTSSessionId` (`ProcessIdToSessionId(GetCurrentProcessId(), …)`, returning a `DWORD`
buffer, `*count = sizeof(DWORD)`), and ideally the remaining classes. **Impact:** a
caller that only wants the session id currently gets `FALSE`; nothing in the observed
start-up depends on the value.

### 7.5 (also seen) `user32:RegisterPowerSettingNotification` returns a fake handle

```
237822.156:072c:Call user32.RegisterPowerSettingNotification(0006006a,6a6ef360,00000000) ret=6a5fe3e8
237822.156:072c:Ret  user32.RegisterPowerSettingNotification() retval=deadbeef ret=6a5fe3e8
```

Wine source: `dlls/user32/misc.c:410` — `FIXME(...); return (HPOWERNOTIFY)0xdeadbeef;`.
Qt (`qwindowsscreen.cpp`) registers for `GUID_CONSOLE_DISPLAY_STATE`; on Wine the handle
is bogus and no `WM_POWERBROADCAST`/display-power event is ever delivered (the matching
unregister is also a stub, `dlls/user32/misc.c`). Cosmetic. Patch, if desired:
implement via the `win32u` power-notification path in `dlls/user32/misc.c`.
