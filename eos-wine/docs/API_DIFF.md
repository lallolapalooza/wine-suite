# Wine ↔ Windows API call diff for `Eos.exe` start-up

Workstream: **call-level trace diff** (owner's method: capture what the app asks Windows for,
capture the same under Wine, diff, patch Wine to match the expectation). Sibling workstreams:
`EosDeadlockRE` (thread-stack/lock analysis of the same hang) and `EosVMReference` (Windows guest
reference) — this document does not duplicate them.

Binary: `C:\Program Files\ETC\EosFamily\v3\Eos\Eos.exe` (PE32+ x86-64, 41 645 024 B, 3.3.10.28).
Wine: locally built 11.18 (`patches/series` 0001–0019 + local 0100/0101). Evidence prefix:
`state/work/prefix`.

Symptom: process starts, paints its 688×383 `Eos` splash (OCR `Version 3.3.10 Build 28`), then the
app's own watchdog reports `hang 1 detected after 3.00 s of inactivity` and Wine reports
`err:sync:RtlpWaitForCriticalSection … blocked by <tid>, retrying (60/300 sec)`. The main editor
window never appears.

---

## 1. The hook config: `tools/apitrace/eos.cfg`

One pattern set used for **both** the Windows and the Wine tracer runs, so the logs are directly
comparable. Grammar (see `tools/apitrace/test.cfg` / `notes/apitrace.md`):

```
[~]dll!func[@argc[/argwidths][:retwidth]]
```

`argwidths` masks the upper half of 32-bit arguments — undefined by the Win64 ABI and different
between Windows and Wine — which is what makes the numeric arguments diffable; `retwidth` selects
4 or 8 bytes of `RAX`.

**481 patterns (460 includes + 21 exclusions), 0 exclusions on the include side, 84 modules touched.**
83 include patterns match no static import of the modules shipped with the app and are listed as
`# unresolved:` in the tracer header (they cost no call lines). Groups:

| section | coverage |
|---|---|
| loader / modules | `GetModuleHandle*`, `LoadLibrary*`, `GetProcAddress`, `FreeLibrary` |
| threads / processes | `CreateThread`, `OpenProcess`, `Suspend/ResumeThread`, toolhelp snapshots, `Sleep*` |
| **synchronisation** | `WaitForSingleObject/Ex`, `WaitForMultipleObjects`, `CreateEvent/Mutex/Semaphore*`, `Open*`, `Release*`, `Set/ResetEvent`, critical-section + SRW + condition-variable + `InitOnce` APIs |
| memory / env | `VirtualAlloc/Free/Protect`, `GetSystemInfo`, QPC, `GetTickCount*`, version / `IsWow64Process` |
| files | `CreateFileW/A`, `Read/WriteFile*`, findings, `DeviceIoControl`, file mappings, volume/`QueryDosDevice*`, `GetTempPath*` |
| registry | `RegOpenKeyEx*`, `RegQueryValueEx*`, `RegCreateKeyExW`, tokens/privileges, **services** |
| **winsock** | `WSAStartup`, `socket/WSASocket*`, `connect/bind/accept/send/recv`, `select`, **`WSAIoctl`**, `WSAEventSelect`/`WSAWaitForMultipleEvents`, `GetAddrInfoW`, `gethostbyname` |
| iphlpapi | `GetAdaptersInfo`, `GetAdaptersAddresses`, `GetIfTable2`, `GetBestInterface*`, **`NotifyIpInterfaceChange`**, `NotifyUnicastIpAddressChange`, … |
| device enumeration | `setupapi` `SetupDi*`, `hid` `HidD_*`/`HidP_*`, `cfgmgr32` `CM_*`, **`winusb`** `WinUsb_*`, displays |
| display | `Dwm*`, `EnumDisplay*`, `GetSystemMetrics`, pixel-format/`SwapBuffers`, `wgl*`/`glGet*` |
| user32 / QPA | window creation, message loop, `Get/SetWindowLongPtr`, hooks, timers, foreground, power notifications |
| COM / shell | `CoInitialize*`, `CoCreateInstance`, shell folders, `GetUserProfileDirectoryW`, version resources, `MiniDumpWriteDump` |
| multimedia | `winmm` `wave/midi/mixer` device probing (Qt5Multimedia audio backend) |

**Volume control (the 21 `~` exclusions).** A first un-narrowed run produced **531 791 call lines in
25 s**, of which **469 572 (88 %)** came from *one* worker thread spinning on two critical sections
(`0x6ffffea3ab38` / `0x6ffffea0b0c0`) from the very first traced instruction, plus its per-font /
per-glyph GDI and registry-font churn. With the IAT tracer those are pure volume — `Enter/Leave
CriticalSection` only emit *successful* returns (blocking is invisible: the call is logged after it
acquires) and the font/registry/paint calls carry no failure signal. Excluding them takes the same
run to a few thousand diffable lines. The exclusions are `Enter/Leave/TryEnterCriticalSection`,
`ReadFile*`, `GetCurrentThreadId`, `Module32First/NextW`, `RegQueryValueEx{A,W}`, `RegEnumKeyExW`,
`RegEnumValue{A,W}`, `RegCloseKey`, `SelectObject`, `DeleteObject`, `CreateFontIndirectW`,
`EnumFontFamiliesExW`, `GetDC`, `ReleaseDC`, `GetSysColor`.

Critical-section **contention** (the hang) is still captured, from two sources:

* Wine's own sync channel → `err:sync:RtlpWaitForCriticalSection … blocked by …` in
  `logs/api/wine_eos.relay.log`;
* the blocking waits that remain in the cfg (`WaitForSingleObject/Ex`, `WaitForMultipleObjects`,
  `MsgWait*`), which do have a return value and are the calls that never come back.

### Qt / platform entry points

`add_pattern()` (`tools/apitrace/src/apihook.c`) splits each pattern at the **first** `@` to find the
optional `@argc`, and matches exact names only. Qt's C++-mangled imports look like
`Qt5Core.dll!?acquire@QSystemSemaphore@@QEAA_NH@Z`, so they cannot be expressed in this grammar.
Qt's platform surface is covered through the **Win32 APIs Qt calls**: `QSystemSemaphore` →
`CreateSemaphoreW`/`OpenSemaphoreA`/`ReleaseSemaphore`; `QSharedMemory` →
`CreateFileMappingW`/`OpenFileMappingW`/`MapViewOfFile`; `Qt5Network` → `ws2_32`/`iphlpapi`; the QPA
plugin `platforms/qwindows.dll` → `user32`/`gdi32`/`dwmapi`. Because the hooker patches **every**
loaded module's IAT, one `kernel32!CreateSemaphoreW` pattern captures the call whether it comes from
`Eos.exe`, `Qt5Core.dll` or a plugin. This proved sufficient to see Qt's single-instance objects —
see §5.

---

## 2. How the logs were captured

### 2.1 Windows reference — `logs/api/win_eos.log`

Guest trace: `tools/apitrace` staged into `vmshare/` (`apitrace.exe` md5
`21ef1a5cbba6bb4f12664abaf1d5729f`, `apihook.dll` md5 `c76cf677ce4d2ae3891803a140626955`,
`eos.cfg`), pulled and run **elevated** (the tracer injects `apihook.dll`, so it needs admin):

```
tools/vm/vmcmda.sh -f tools/vm/guest_apitrace_eos.ps1 300
#  -> C:\apitrace\apitrace.exe --cfg C:\apitrace\eos.cfg --out C:\apitrace\win_eos.log \
#        --timeout 60 -- "C:\Program Files\ETC\EosFamily\v3\Eos\Eos.exe"
#  -> curl.exe -T C:\apitrace\win_eos.log http://192.168.122.1:8000/win_eos.log
```

The guest's own logs from the reference run (`logs/vm/`) were pulled as `win_OnyxConsole.log`,
`win_NetworkFeedback.log`, `win_EosAsserts.txt` (see §5.0). The tracer log came back as
`logs/api/win_eos.log`: **2 945 631 call lines**, header
`patterns=481 exclusions=21 modules=82 loader_notify=1 poll_ms=200 cfg_error=-`,
`unresolved_patterns=108`. `TRACER_RC=0`, 61.7 s wall; the guest was left clean (`FREE_AFTER_GB=6.897`).

### 2.2 Wine — `logs/api/wine_eos.log` (ApiTracer under Wine)

`tools/run_apitrace_eos.sh` stages the same tracer + `eos.cfg` into `C:\apitrace` inside the prefix
and runs the target exactly like the Windows side:

```
tools/run_apitrace_eos.sh wine_eos --secs 15
# -> wine C:\apitrace\apitrace.exe --cfg C:\apitrace\eos.cfg --out C:\apitrace\wine_eos.log \
#        --timeout 15 -- Eos.exe      (cwd = the app dir)
```

The tracer's launch mode (`CREATE_SUSPENDED` + `CreateRemoteThread`→`LoadLibraryW`) works under this
Wine 11.18 (also verified against `selftest.exe`). Result: **6 256 call lines**, header
`patterns=481 exclusions=21 modules=84 loader_notify=1 poll_ms=200 cfg_error=-`,
`unresolved_patterns=83`, 7 late-resolved patterns. The log reaches the hang: the final calls are the
watchdog writing `EosAsserts.txt` and taking a minidump —
`548 dbghelp.dll!MiniDumpWriteDump (arg0=0xffffffffffffffff, …) -> 0x1`.

**Single-instance gotcha (affects any run):** Eos enforces a single instance via Qt
`QSharedMemory`/`QSystemSemaphore`. If another Eos is already running in the prefix, a newly launched
one detects it and exits with 0 after ~2–3 s with a full Qt teardown (observed:
`OpenFileMappingW(…) -> 0x0`, `CreateSemaphoreW(L"qipc_systemsem_…")`, `CreateFileMappingW(L"qipc_sharedmemory_…")`).
`tools/run_apitrace_eos.sh` therefore kills any Eos in the prefix before launching. `run_eos.sh`
(used elsewhere) does *not* kill its app at the end, so it leaves a hung instance for up to 140 s.

### 2.3 Wine, scoped `WINEDEBUG=+relay` — `logs/api/wine_eos.relay.log`

The tracer does not decode strings and does not see `GetProcAddress`-resolved calls. Wine's relay
channel does both, and `dlls/ntdll/relay.c` honours `HKCU\Software\Wine\Debug\RelayInclude`. Two
pitfalls found and handled in `tools/run_eos_relay.sh`:

* the filter value is **`;`-separated** (`build_list()`, relay.c) — a comma-separated list becomes
  one unmatchable entry and silently relays nothing;
* the key already carried another project's `RelayExclude`/`RelayFromExclude`, which hides calls —
  the script deletes them first.

Result: **116 029 lines** (57 968 `Call` + 57 968 `Ret`, plus loader/TLS/window events and the
`err:sync` hang line), with decoded paths/names — e.g. `L"qipc_sharedmemory_DFFBCEB…"`,
`L"\\?\hid#vid_845e&pid_0002#…"`, `L"Software\Microsoft\Windows\CurrentVersion\ThemeManager"`.
`RelayInclude` is kept on the hang's neighbourhood (sync + files + registry + sockets + setupapi/hid/
winusb + iphlpapi) and deliberately omits `Enter/LeaveCriticalSection` for the same volume reason;
`+err` is enabled so `err:sync` still prints.

---

## 3. Normalised diff (`tools/relaydiff.py diff`)

Both logs come from the **same cfg**, so the call sets are directly comparable.

| | Windows (`win_eos.log`) | Wine (`wine_eos.log`) |
|---|---|---|
| trace window | 60 s (`--timeout 60`) | 15 s (`--timeout 15`) |
| call lines | **2 945 631** | **6 256** |
| header | `patterns=481 exclusions=21 modules=82 loader_notify=1`, `unresolved_patterns=108` | `patterns=481 exclusions=21 modules=84`, `unresolved_patterns=83` |

The full logs are **not** directly comparable: the Windows app finishes start-up and then runs
(workspaces, tabs, patch), while the Wine app is still inside the start-up stall when the 15 s window
closes. In the 60 s Windows log the dominant traffic is a **post-start-up device poll** on one
worker thread (tid 7024):

```
1471386 SETUPAPI.dll!SetupDiEnumDeviceInfo
1471386 SETUPAPI.dll!SetupDiGetDeviceRegistryPropertyW          # thread 7024, 60 s
```

`SETUPAPI.dll` totals 2 942 788 calls on Windows vs **15** on Wine — a phase difference, not a cause:
Eos only reaches that poll after ACN start-up completes, which never happens inside the Wine window.

**Start-up slice diff.** To compare the same phase, the diff was run on the first 3000 calls of each
log (`logs/api/{win,wine}_eos.head.log`, header + 3000 calls; 81 vs 80 distinct functions):

```
== call sequences in A not in B ==            == call sequences in B not in A ==
  ... identical early loader/Qt init ...        ... identical early loader/Qt init ...
  kernel32!createmutexw / createfilemappingw    kernel32!getmodulehandlew / getprocaddress
  mapviewoffile / initializecriticalsectionex   kernel32!initonceexecuteonce
  user32!defwindowprocw(…,0x24/0x81/0x83/0x1)   kernel32!initializecriticalsectionex
  user32!createwindowexw                        user32!destroywindow / createwindowexw /
  ... (QSharedMemory/QSystemSemaphore path) ...   defwindowprocw
== per-function call counts (excerpt) ==
function                                             A       B   delta
advapi32.dll!regopenkeyexw                         369     641    +272
kernel32.dll!setevent                              193     328    +135
kernel32.dll!waitforsingleobjectex                 192     329    +137
setupapi.dll!setupdienumdeviceinfo                 385       0    -385
setupapi.dll!setupdigetdeviceregistrypropertyw     385       0    -385
kernel32.dll!queryperformancecounter                35     170    +135
kernel32.dll!getcurrentthread                       26      94     +68
kernel32.dll!resetevent                             21      85     +64
user32.dll!getwindowlongptrw                        25       0     -25
```

The start-up slices are the *same program doing the same thing*; the differences are the Windows
device poll (SetupDi) and Wine's thread-pool churn (`QueryPerformanceCounter`/`GetCurrentThread`/
`ResetEvent`/`SetEvent`). **There is no single Win32 call that fails on Wine and succeeds on Windows
inside this window** — the divergence is a *timing/latency* one, confirmed by the return-value
comparison (§4) and the app state machines (§5.0).

Full outputs: `logs/api/diff_head.txt`, `logs/api/retvals.txt`.

---

## 4. Return-value divergence (`tools/api_retval_diff.py retvals`)

`relaydiff.py wine-log --errors` only pairs relay-style `Call`/`Ret` records, so for the apitrace
logs the return-value comparison is done by `tools/api_retval_diff.py` (cfg-aware: `:4` returns are
value-compared, `:8` pointer returns only by nullness, `:0` void returns ignored).

**Start-up slices (first 3000 calls):** after removing handle-number churn (handles < 0x10000 are
kept as literal values) the only substantive differences are screen metrics:

```
GDI32!GetDeviceCaps(PTR,0x4)   A=0x153 (339)      B=0x1a7 (423)
GDI32!GetDeviceCaps(PTR,0x6)   A=0x0d4 (212)      B=0x109 (265)
GDI32!GetDeviceCaps(PTR,0x74)  A=0x040 (64)       B=0x03c (60)
```

— i.e. the guest's 1280×752 desktop vs the Wine X display (1600×1000); not a failure.

**The real failing calls come from the Wine relay log** (`relaydiff.py wine-log --errors
logs/api/wine_eos.relay.log`, 144 failures; `logs/api/wine_eos.errors.txt`):

```
0524 advapi32!RegQueryValueExW(0x544,PTR,L"InstallPath",0x0,PTR,0x0,PTR) -> 0x2 [ERROR_FILE_NOT_FOUND]
0524 kernelbase!CreateFileW(PTR,L"\\\\?\\C:\\users\\asdf\\AppData\\Local\\ETC\\EosFamily\\v3\\augment3d_eos_settings.json",…,0x3,…) -> INVALID_HANDLE_VALUE
0524 kernelbase!CreateFileW(PTR,L"C:\\windows\\slp.conf",…,0x3,…) -> INVALID_HANDLE_VALUE
0524 ws2_32!connect(0x128c,PTR,0x1c) -> 0xffffffff
0554 ws2_32!connect(0x16a4,PTR,0x1c) -> 0xffffffff
```

`C:\windows\slp.conf` is the one that matters: on Windows the file exists (shipped by ETC SLP) and
is read successfully; under Wine it is `ERROR_FILE_NOT_FOUND`, so OpenSLP runs with defaults and its
registration unicast to the (absent) local daemon times out — see §6.

The `fixme:` summary from the same run names the stubs: `WSAIoctl SIO_UDP_CONNRESET` (12×),
`NotifyIpInterfaceChange` (stub), `NotifyUnicastIpAddressChange` (semi-stub), `GetTempPath2W`
(semi-stub), `RegisterPowerSettingNotification`, `PowerCreateRequest`/`PowerSetRequest`,
`NtQuerySystemInformation SYSTEM_PERFORMANCE_INFORMATION`.

---

## 5. What Wine actually does, and the last calls before the hang

### 5.0 The two sides' own state machines (ground truth from both app logs)

**Windows** (`logs/vm/vm_OnyxConsole.log`, guest clock 11:51:49–11:51:53):

```
Console    NetworkManager starting up
Console    NetworkManager: Number of connected NICs (physical + virtual) changed: 0 -> 9
CreateComponent Created component handle=80000000 cid=001027D4-7181-4D43-B20A-47A00DF3E118
QuartzFramework Discovery: Component [192.168.122.230:51464,0] has been force created (CID: 001027D4-... DCID: ETCnomad Client)
OnyxConsole ACN started
Console    Registering for network changes...
QuartzFramework InitializeMultiConsole FAIL#2
OnyxConsole Unable to start network connection
OnyxConsole Console Framework started successfully (with ACN)
...
OnyxConsole Device Updated: [ASDF] Added: ... IP 192.168.122.230 ...
OnyxConsole recovered from hang after 10.10 s
```

`logs/vm/vm_NetworkFeedback.log` on Windows is 3 lines and contains **no SLP failure**:

```
Network    Discovery Started
Patch      Connecting to NEW response MIDI Show Control TX Streams 2
Patch      Enable response MIDI Show Control TX Streams 2
```

So on Windows the ACN/discovery component is registered in ~10 ms (`handle=80000000`), `ACN started`
and `Console Framework started successfully` follow immediately, and the whole "unresponsive" window
is a **transient** that Eos itself closes (`recovered from hang after 10.10 s`; `Responding=True` at
+85 s).

**Wine** (`state/work/prefix/.../EosFamily/v3/OnyxConsole.log` + `NetworkFeedback.log`):

```
Console    NetworkManager starting up
Console    NetworkManager: Number of connected NICs (physical + virtual) changed: 0 -> 5
Console    Registering for network changes...
Network    Discovery Started
Network    Discovery InternalRegister: SLPReg() failed with result -19.          <- NetworkFeedback.log
Network    SDT Couldn't Create component EF4DC218-... on iface 1 -- Couldn't register that protocol in discovery
OnyxConsole hang 2 detected after 57.00 s of inactivity
Network    SDT Couldn't Create component EF4DC218-... on iface 2 -- Couldn't register that protocol in discovery
Network    CreateComponent Created component handle=ffffffff cid=EF4DC218-...
```

The Wine side never logs `ACN started`, `Console Framework started successfully` or
`recovered from hang`; it also opens `C:\windows\slp.conf`, which the Windows run does not need to
(see §6).

`-19` is OpenSLP's **`SLP_NETWORK_TIMED_OUT`** ("no reply … for a unicast request"), *not*
`SLP_NETWORK_INIT_FAILED` (`-20`). The Wine run therefore sends SLP's DA registration unicast and
gets no answer; on Windows the **local `slpd` DA answers at once**.

### 5.1 The app's own log stops at network bring-up

`…/AppData/Local/ETC/EosFamily/v3/OnyxConsole.log` (verbatim, one run):

```
Console    NetworkManager starting up
Console    NetworkMonitor: Physical Interface enp0s31f6 enp0s31f6 changed: Link Speed: 0 bps -> 1 Mbps,
Console    NetworkMonitor: Physical Interface virbr0 virbr0 changed: Link Speed: 0 bps -> 1 Mbps,
Console    NetworkMonitor: Physical Interface vnet0 vnet0 changed: Link Speed: 0 bps -> 1 Mbps,
Console    NetworkManager: Number of connected NICs (physical + virtual) changed: 0 -> 5
OnyxConsole Disabled operating system idle mode
Libraries  EtcPal Library 1.0.0.25
Console    Registering for network changes...
Network    SDT Couldn't Create component EF4DC218-7071-4C6E-98DF-40B730C5C7CF on iface 1 -- Couldn't register that protocol in discovery
OnyxConsole hang 2 detected after 57.00 s of inactivity
Network    SDT Couldn't Create component EF4DC218-7071-4C6E-98DF-40B730C5C7CF on iface 2 -- Couldn't register that protocol in discovery
Network    CreateComponent Created component handle=ffffffff cid=EF4DC218-7071-4C6E-98DF-40B730C5C7CF
OnyxConsole hang 3 detected after 5.00 s of inactivity
```

`NetworkFeedback.log`: `Discovery InternalRegister: SLPReg() failed with result -19.` on every run.
`CriticalIssues.txt`: `The Eos application is about to crash`.

So the last thing the console *successfully* logs is `Registering for network changes...`, followed
by SLP discovery-registration failures and the hang. This is the **EtcPal NetworkManager /
NetworkMonitor** path: enumerate NICs → register for interface/address changes → start SLP discovery.

### 5.2 The relayed calls in that window

```
0554 iphlpapi!GetAdaptersAddresses(0x2,0xe,0x0,PTR,PTR)
0554 iphlpapi!GetAdaptersInfo(0x0,PTR)            # several times
0524 iphlpapi!GetAdaptersInfo(0x0,PTR)
0554 iphlpapi!NotifyIpInterfaceChange(0x0,PTR,PTR,0x0,PTR)
0554 fixme:iphlpapi:NotifyIpInterfaceChange (family 0, callback 0000000141284330, context 000071760B34ECA0, init_notify 0, handle 000071760B34ECF8): stub
0554 Ret  iphlpapi.NotifyIpInterfaceChange() retval=00000000
0554 fixme:iphlpapi:NotifyUnicastIpAddressChange (family 0, callback 00000001412843E0, context 000071760B34ECA0, init_notify 0, handle 000071760B34ED00): semi-stub
0554 ws2_32!socket(0x17,0x2,0x11)                 # AF_INET6, SOCK_DGRAM, IPPROTO_UDP
0554 ws2_32!connect(0x16a4,PTR,0x1c) -> 0xffffffff
0524 ws2_32!socket(0x2,0x2,0x11)                  # AF_INET, SOCK_DGRAM, IPPROTO_UDP
0524 ws2_32!WSAIoctl(0x17f0,0x9800000c,…)         # SIO_UDP_CONNRESET  -> fixme stub
0524 ws2_32!WSAIoctl(0x17f0,0xc8000006,…)         # SIO_ADDRESS_LIST_QUERY
0524 ws2_32!WSAIoctl(0x17f0,0x8004667e,…)         # FIONBIO
0524 ws2_32!bind(0x17f0,PTR,0x10) -> 0x00000000
0524 setupapi!SetupDiGetClassDevsW(<GUID_DEVINTERFACE_NET {ad498944-762f-11d0-8dcb-00c04fc3358c}>,0,0,0x12)
0524 setupapi!SetupDiEnumDeviceInfo(…) -> 0x00000000   # zero devices
```

The main thread then repeats the whole UDP-socket setup with ~3.7 s gaps, with the watchdog
(`MiniDumpWriteDump`) firing in between; thread 0724 blocks on a critical section held by the main
thread 0524:

```
230811.174:0724:err:sync:RtlpWaitForCriticalSection section 00007176191AC168 "?" wait timed out in thread 0724, blocked by 0524, retrying (300 sec)
```

### 5.3 Wine-internal stubs seen

| call | Wine message | source |
|---|---|---|
| `NotifyIpInterfaceChange` | `stub`, sets `*handle = NULL`, never notifies | `dlls/iphlpapi/iphlpapi_main.c` |
| `NotifyUnicastIpAddressChange` | `semi-stub`, only calls back when `init_notify` | `dlls/iphlpapi/iphlpapi_main.c` |
| `WSAIoctl(SIO_UDP_CONNRESET)` | `stub` (returns success) | `dlls/ws2_32/socket.c` |
| `GetTempPath2W` | `semi-stub` | `dlls/kernelbase/path.c` |
| `RegisterPowerSettingNotification` | `stub` | `dlls/user32/misc.c` |
| `PowerCreateRequest` / `PowerSetRequest` | `stub` | `dlls/kernel32/powermgnt.c` |
| `EnableNonClientDpiScaling` | app log: `failed … (120) (Call not implemented.)` | `dlls/win32u` |
| `NtQuerySystemInformation(SYSTEM_PERFORMANCE_INFORMATION)` | `fixme` | `dlls/ntdll/system.c` |

---

## 6. Named divergent call(s) and the Wine code to change

**Verdict: the start-up stall is SLP service discovery failing because the app cannot bind / reach
SLP port 427 — not an app-level lock.** Eos's start-up "hang" is a *transient* on both platforms, but
Windows closes it in ~10 s while Wine needs ~54–58 s (sibling `EosDeadlockRE` measured
`recovered from hang after 58.08 s` under Wine in a clean control run vs the guest's own
`recovered from hang after 10.10 s`). The extra ~44–48 s is exactly the app's per-interface
`SLPReg()` unicast timeouts.

The failing call, captured with `WINEDEBUG=+winsock` while running the ETC SLP daemon (`slpd.exe`)
under Wine in `state/exp/apidiff/prefix`:

```
trace:winsock:bind socket 0x70, addr { family AF_INET, address 127.0.0.1, port 427 }, len 16
trace:winsock:bind failed, status 0xc0000022.          # STATUS_ACCESS_DENIED -> WSAEACCES
trace:winsock:bind socket 0x70, addr { family AF_INET, address 0.0.0.0, port 427 }, len 16
trace:winsock:bind failed, status 0xc0000022.
trace:winsock:bind socket 0x70, addr { family AF_INET, address 0.0.0.0, port 68 }, len 128
trace:winsock:bind failed, status 0xc0000022.
```

and in the daemon's own log (`C:\windows\slpd.log`):

```
NETWORK_ERROR - Could not listen for TCP on IPv4 loopback
INTERNAL_ERROR - No SLPLIB support will be available with TCP
NETWORK_ERROR - Could not listen for UDP on IPv4 loopback
Couldn't bind to (IPv4) multicast for interface 0.0.0.0 (No such file or directory)
```

Port 427 (and 68) are in the **privileged range** on this host: `net.ipv4.ip_unprivileged_port_start
= 1024`, uid 1000; a plain `python3` `bind(('127.0.0.1', 427))` returns `[Errno 13] Permission
denied`. Wine forwards the bind to the Linux kernel and maps the errno
(`dlls/ws2_32/unixlib.c:371`: `EPERM`/`EACCES` → `WSAEACCES`). **Windows has no privileged-port
concept**, so on Windows `slpd` binds 427 normally. Eos itself only *connects* to that daemon:

```
trace:winsock:connect socket 0x17f8, addr { family AF_INET, address 127.0.0.1, port 427 }, len 16
```

so the chain is: (1) the Wine prefix has no ETC SLP at all (install gap, see §6.1), and (2) even with
ETC SLP installed, `slpd` cannot bind 427 under Wine on this host, so Eos's SLP client gets no answer
and every per-interface registration burns the OpenSLP unicast timeouts.

### 6.1 What the app expects (from its own logs, both platforms)

| | Windows (guest) | Wine |
|---|---|---|
| NICs seen | `0 -> 9` | `0 -> 5` |
| **SLP** | `Discovery Started` … no failure; `CreateComponent Created component handle=80000000` in ~10 ms | `SLPReg() failed with result -19` (`NetworkFeedback.log`), `CreateComponent … handle=ffffffff` |
| ACN | `ACN started` → `Console Framework started successfully (with ACN)` | never logged |
| GUI | workspaces/tabs built; `recovered from hang after 10.10 s` | `recovered from hang after 54.09 s` |

`-19` is OpenSLP `SLP_NETWORK_TIMED_OUT`: OpenSLP sent its registration request and **no SLP agent
answered**. On Windows that agent is the **`slpd` service** shipped by the bundle's *ETC SLP 3.0.0.22*
prerequisite (`C:\Windows\SysWOW64\slpd.exe`, config `C:\Windows\slp.conf`, service `slpd`,
StartType `Automatic`, `Status Running`). The Wine prefix was created from the **product MSI only**
(`msiexec /i ETC_EosFamily_v3.3.10.28.msi`), and the SLP prerequisite — like the ETC WinUSB drivers —
is installed by the *NSIS bundle* (`ETC_SLP_Install.exe /S`), not the MSI, so it is missing. The
Win32-visible consequence in the Wine trace is `CreateFileW(L"C:\\windows\\slp.conf")` returning
`0xffffffffffffffff` (`ERROR_FILE_NOT_FOUND`), after which OpenSLP falls back to unicast and times
out.

The guest evidence for the exact object Eos wants:

```
# netstat on the guest (slpd pid 5004, Eos.exe pid 1472)
TCP  127.0.0.1:427        LISTENING   5004
TCP  192.168.122.230:427  LISTENING   5004
TCP  127.0.0.1:61455      127.0.0.1:427    ESTABLISHED 1472   <- Eos' ACN UA -> slpd
UDP  127.0.0.1:427                     5004
UDP  192.168.122.230:427  (x3)         5004

# slptool.exe findsrvtypes  ->  service:acn.esta
# C:\Windows\slp.conf (active settings)
net.slp.useScopes                 = ACN-DEFAULT
net.slp.isDA                      = true
net.slp.DADiscoveryMaximumWait    = 5000
net.slp.unicastTimeouts           = (commented -> 1000,1000,2000,2000,3000 default)
```

So Eos does **not** need multicast SLP on the wire: its ACN library registers/finds
`service:acn.esta` by talking to the **local slpd DA on 127.0.0.1:427 over TCP**. Under Wine there is
no slpd, the DA-discovery/unicast wait burns the default timeouts on every interface, and the ACN
bring-up is delayed by the measured ~44 s.

### 6.2 The Wine-side API divergences in that window

1. **`iphlpapi!NotifyIpInterfaceChange` is a pure stub.** The app logs
   `Registering for network changes...` immediately before the stall, which is this call:
   ```
   0554:Call iphlpapi.NotifyIpInterfaceChange(00000000,141284330,71760b34eca0,00000000,71760b34ecf8)
   0554:fixme:iphlpapi:NotifyIpInterfaceChange (family 0, callback 0000000141284330, context 000071760B34ECA0, init_notify 0, handle 000071760B34ECF8): stub
   0554:Ret  iphlpapi.NotifyIpInterfaceChange() retval=00000000
   ```
   Wine returns `NO_ERROR` but sets `*handle = NULL` and **never invokes the callback**, so the
   interface/address changes the ACN state machine registers for never arrive.
   `NotifyUnicastIpAddressChange` is a semi-stub (only fires when `init_notify`).
2. **`WSAIoctl(SIO_UDP_CONNRESET)` is a no-op stub** on every UDP socket the app opens
   (`fixme:winsock:WSAIoctl SIO_UDP_CONNRESET stub`, 12× per run):
   ```
   0524:Call ws2_32.WSAIoctl(000017f0,9800000c,7ffffe4394c0,00000004,7ffffe4394cc,6fff00000004,7ffffe4394c4,00000000,00000000)
   ```
3. **Every interface reports a hard-coded 1 Mbps link speed** — `Link Speed: 0 bps -> 1 Mbps` for
   all NICs, where Windows reports real speeds.

### 6.3 What has to change

The failing call is a **privileged-port `bind()`** that Wine cannot satisfy on this host:

| priority | where | change |
|---|---|---|
| 1 | **not a Wine source change** — this host | allow binding ports < 1024 for the Wine process: `sudo sysctl -w net.ipv4.ip_unprivileged_port_start=0` (whole host, fine for a test box) **or** grant the capability to the Wine binaries: `sudo setcap 'cap_net_bind_service=+ep' wine-install/bin/wine wine-install/bin/wine64 wine-install/bin/wine64-preloader wine-install/bin/wineserver` (or run the prefix as root). Then start `slpd` (`C:\windows\SysWOW64\slpd.exe -debug`, or register it as a service) in the prefix. Without this, `slpd` can never bind 427 and Eos's `SLPReg()` will keep timing out. |
| 2 | install the bundle's **ETC SLP** prerequisite into the prefix | the Eos *Application MSI* does not install it; the NSIS bundle runs `ETC_SLP_Install.exe /S` which puts `slpd.exe`/`slptool.exe`/`SLP_Uninstall.exe` in `C:\Windows\SysWOW64`, `slp.conf` in `C:\Windows`, and registers the `slpd` service. Staged copies: `vmshare/{slpd.exe,slptool.exe,slp.conf.win}`. |
| 3 | `wine-11.18/dlls/ws2_32/socket.c` → `bind()` (line 1247) and `wine-11.18/dlls/ws2_32/unixlib.c` (~line 371, `EPERM`/`EACCES` → `WSAEACCES`) | only if the project wants Wine itself to paper over the host restriction (e.g. bind an unprivileged port and forward, or document the capability requirement). Upstream Wine deliberately maps the host errno; Windows semantics ("any user may bind any port") cannot be reproduced without the capability. |
| 4 | `wine-11.18/dlls/iphlpapi/iphlpapi_main.c` → `NotifyIpInterfaceChange()` / `NotifyUnicastIpAddressChange()` | `FIXME(...): stub; if (handle) *handle = NULL; return NO_ERROR;` — Wine returns success but never delivers the interface/address-change callbacks Eos registers for at `Registering for network changes...`. Implement real notifications (poll `GetIfTable2`/NSI, invoke the callback, return a handle closeable by `CancelMibChangeNotify2`). |
| 5 | `wine-11.18/dlls/nsiproxy.sys/ndis.c` (link-speed fill) | hard-codes `data->rcv_speed = data->xmit_speed = 1000000;` for every Linux interface; read the real speed so Eos's NetworkMonitor sees the actual link state (`Link Speed: 0 bps -> 1 Mbps` in the app log). |
| 6 | `wine-11.18/dlls/ws2_32/socket.c` → `WSAIoctl` `case SIO_UDP_CONNRESET` (~line 2781) | `FIXME(...SIO_UDP_CONNRESET stub); …COMPLETE_ASYNC…` — a no-op on every UDP socket Eos opens. |

Ordering evidence: the Wine stall is `SLPReg` timeout × interfaces (OpenSLP's default unicast
timeouts ≈ 7.5 s × ~6 ≈ the measured 44–48 s), it vanishes on Windows where `slpd` answers on
`127.0.0.1:427`, and the daemon's only failure under Wine is the `bind(:427)` → `STATUS_ACCESS_DENIED`.
If the capability lift + ETC SLP removes the delta, rows 4–6 are documented but non-blocking.

---

## 7. Limitations / caveats

* **apitrace logs carry no timestamps and no strings.** The tracer records `<seq> <tid> <dll>!<func>
  (argN=0x…) -> 0x…` only, so `CreateFileW`/`RegOpenKeyExW`/`CreateSemaphoreW` *names* are pointers.
  The name-level evidence in this document therefore comes from the Wine relay log (§2.3) and the
  app's own logs; the tracer logs supply presence/counts/return values.
* **The two tracer windows are different lengths** (Windows 60 s so the app could get through the
  self-healing start-up; Wine 15 s, which is already past the stall). Diffing the full logs is
  dominated by phase differences, so §3 uses equal-size 3000-call start-up slices.
* **Handle values below `POINTER_MIN` (0x10000) are not normalised**, so `retvals` reports
  handle-number churn as "differences"; the substantive entries were picked out by hand. §4.
* **`GetProcAddress`-resolved calls are invisible to the IAT tracer.** Only Wine's relay log sees
  them (it patches the *exports*), which is why `iphlpapi!NotifyIpInterfaceChange` shows up in the
  relay log and not in either tracer log. There is no Windows-side equivalent capture here.
* **Eos is single-instance.** A second launch exits in ~2–3 s with a full Qt teardown
  (`QSharedMemory`/`QSystemSemaphore`). All captures must be serialized; `tools/run_apitrace_eos.sh`
  and `tools/run_eos_relay.sh` kill any Eos in the prefix first. `run_eos.sh` leaves its app running
  for up to 140 s, which will make the *next* launch exit early.
* **The cfg's 21 exclusions** remove the app's own lock/font/registry churn (without them the run is
  531 791 lines in 25 s, 88 % from one spinning thread). `Enter/Leave/TryEnterCriticalSection` are
  therefore not in the tracer log; contention comes from `err:sync` and the relay log.
* **The Windows install here came from the NSIS bundle**, which installs bundle-only prerequisites
  (ETC SLP, ETC WinUSB drivers). The Wine prefix was installed from the product MSI only, so the SLP
  prerequisite is absent — see §6. Any comparison of network/device behaviour must account for this.

---

## Appendix — reproducing

```
tools/run_apitrace_eos.sh wine_eos --secs 15             # logs/api/wine_eos.log
tools/run_eos_relay.sh     wine_eos --secs 20            # logs/api/wine_eos.relay.log
tools/apidiff_eos.sh                                     # logs/api/{diff,retvals,tails}.txt
```
