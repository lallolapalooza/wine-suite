# EOS_STALL_RE — post-splash stall of `Eos.exe` under Wine 11.18

Status: root-caused. Evidence: `logs/runs/winedbg/**`, `logs/api/**`, and the app's own in-prefix
diagnostics. Reference: Windows 11 guest (`EosVMReference`, Win11/QXL, unlicensed ETCnomad).

## 0. Verdict (short)

**Category (b): the app waits on something this Wine/host environment does not provide — the
network-discovery bring-up. It is _not_ a Qt/platform-plugin problem, and _not_ a defect in Wine's
critical-section implementation.** The stall is a *start-up transient* gated on the ACN/sACN/SLP
network bring-up plus the "register for network changes" step; on Windows the same transient ends in
~10 s, under Wine it lasts ~54 s (or is still running at 115–160 s in some runs).

Named Wine gaps that keep the transient alive:

| gap | Wine source | consequence |
|---|---|---|
| `NotifyIpInterfaceChange()` is a **stub** | `dlls/iphlpapi/iphlpapi_main.c:3966` | app's interface-change callback is **never invoked** |
| `NotifyUnicastIpAddressChange()` is a **semi-stub** (only fires when `init_notify != 0`; app passes 0) | `dlls/iphlpapi/iphlpapi_main.c:4014` | same |
| SLP service registration fails | app-side `SLPReg()` → `-19` (= `SLP_NETWORK_TIMED_OUT`) | discovery component creation fails (`handle=ffffffff`) |
| sACN multicast setup fails | `setsockopt(IP_MULTICAST_IF)` / `IP_ADD_MEMBERSHIP` → `WSAEINVAL` | `[CRIT] sACN: None of the network interfaces were usable for the sACN API.` |

While the network step is pending, the GUI thread is parked in Wine's critical-section wait and the
rest of the app piles up behind it; that is the visible `err:sync:RtlpWaitForCriticalSection …`
storm and the "hang" the app's own watchdog reports. When the network step finally gives up, the
locks drain and the editor opens (`14:55:04 OnyxConsole recovered from hang after 54.09 s`, window
`"Eos : 1" 1600x1000`, OCR = the live Eos editor).

Because the transient also exists on Windows (`OnyxConsole recovered from hang after 10.10 s`), the
synchronisation code is behaving as designed; what is missing is the network plumbing on which the
app's start-up gate depends. On Wine the gate takes ~5× longer (54–58 s in the two clean runs) and
usually ends with the editor opening; runs where the SLP/discovery retry path never returns stay
stalled (≥160 s observed).

## 0b. Quantified timeline (clean control run, no Qt env overrides — `ctrl2`)

```
13:58:10.953 Console   Version Initialized: 3.3.10.28
13:58:26.183 Console   NetworkManager: Number of connected NICs changed: 0 -> 5
13:58:26.197 Console   Registering for network changes...          <-- stall starts
13:58:53.771 Network   SDT Couldn't Create component EF4DC218-… on iface 1   (SLP timeout ≈ 27.6 s)
13:59:05.030 Network   SDT Couldn't Create component EF4DC218-… on iface 2
13:59:05.030 CreateComponent Created component handle=ffffffff   (Windows: handle=80000000, ~10 ms)
13:59:05.244 OnyxConsole ACN started
13:59:05.249 OnyxConsole Console Framework started successfully (with ACN)
13:59:05.545 Console   [CRIT] sACN: None of the network interfaces were usable for the sACN API.
13:59:05.564 OnyxConsole OSC TCP Listening on 127.0.0.1:3032 / 192.168.0.2:3032 / 192.168.122.1:3032 …
13:59:09.299 OnyxConsole recovered from hang after 58.08 s
```

and by `t=75 s` the main window exists: `"Eos : 1" ("eos.exe") 1600x1000+0+0`.
So the stall is **a ~1-minute start-up block, dominated by the per-interface SLP registration
timeout**, not a permanent deadlock. Two clean runs recovered at 54.09 s and 58.08 s. Earlier runs
of the same build stayed stalled for 115–160 s (their watchdog logged `hang 4 detected after
159.77 s of inactivity`), so the duration is variable and tied to how the discovery/SLP retry path
plays out under Wine.

## 1. Reproduce

```sh
source env.sh
tools/run_eos.sh stall1 --secs 120 --iv 15 --debug '+timestamp,+sync,+seh'
# capture stacks (adds an LD_PRELOAD that re-allows ptrace after Wine's own prctl):
tools/host/stall_dump.sh run4 45      # gdb native stacks for every thread
tools/host/win_stack_run.sh win1 45   # TEB stack bounds + raw Windows stacks
tools/host/stack_dump.sh stacks1 45   # wine-tid / rsp / raw stack words
```

The app **installs and starts fine** and paints the splash (`0x1200003 "Eos" 688x383`, OCR `Version
3.3.10 Build 28`). It then stops progressing for 54–160 s. On one 110 s run it recovered and the
main editor window (`"Eos : 1" 1600x1000`) came up. The app writes its own hang dumps:
`C:\users\asdf\AppData\Local\ETC\EosFamily\v3\EOSHang.3.3.10.28_*_S.dmp`.

## 2. What the app itself says (in-prefix diagnostics)

`…/AppData/Local/ETC/EosFamily/v3/EosAsserts.txt` (every run, from the first second):

```
hang 1 detected after 3.00 s of inactivity
hang 2 detected after 57.00 s of inactivity
hang 3 detected after 5.00 s of inactivity
hang 4 detected after 115.00 s / 159.77 s of inactivity  -> generating hang dump EOSHang.*_S.dmp
```

`…/OnyxConsole.log` — the app gets all the way through UI start-up (fonts, fixture library,
Softkey/Encoder/Parameter/HIM/hardware wrappers, brightness, LED manager) and then *stops logging*
at the network step:

```
13:48:12.391 Console  NetworkManager starting up
13:48:12.421 Console  NetworkMonitor: Physical Interface enp0s31f6 changed: Link Speed: 0 bps -> 1 Mbps
13:48:12.422 Console  NetworkManager: Number of connected NICs (physical + virtual) changed: 0 -> 5
13:48:12.431 OnyxConsole Disabled operating system idle mode
13:48:12.431 Libraries  ACN Library 2.3.0.15 / sACN 3.0.0.24 / EtcPal 1.0.0.25
13:48:12.454 Console  Registering for network changes...        <-- last line for the hung runs
```

`…/NetworkFeedback.log` (hung runs, repeated per interface):

```
Network Discovery Started
Network Discovery InternalRegister: SLPReg() failed with result -19.
```

`…/OnyxConsole.log` (same runs, ~28 s later):

```
Network SDT Couldn't Create component EF4DC218-7071-4C6E-98DF-40B730C5C7CF on iface 1
        -- Couldn't register that protocol in discovery
CreateComponent Created component handle=ffffffff cid=EF4DC218-…
```

`…/CriticalIssues.txt` (one run): `The Eos application is about to crash` → `EOS.3.3.10.28_S.dmp`;
`EosAsserts.txt` records a first-chance `0xc0000005` (read at `0x23C`) with the faulting PC inside
Wine's `kernelbase.dll` — but this only appears in the apitrace-hooked runs and is *not* the hang
(the hang is already logged 3 s in, before any exception).

**Windows reference** (`EosVMReference`): the same transient exists — unresponsive at +10 s, then
`OnyxConsole recovered from hang after 10.10 s`, editor up and responding from ~+18 s. On Windows
the network step succeeds: `Number of connected NICs … 0 -> 9`, `CreateComponent … handle=80000000`,
`ACN started`, `Discovery: Component [192.168.122.230:51464,0] … online`, and **no `SLPReg()`
failure at all**. No licence dialogue either side (unlicensed offline is silent).

## 3. Per-thread stacks at the stall

Two independent captures agree (live `gdb` attach, and the app's own minidump parsed with
`tools/host/mdmp.py`). Representative stacks:

**A. GUI/key thread — blocked on an app CRITICAL_SECTION** (`logs/runs/winedbg/dumps/hang_threads.txt`,
tid 0x264; live equivalent in `logs/runs/winedbg/stacks1/gdb_raw.txt`):

```
ntdll.dll!ZwWaitForAlertByThreadId      <- syscall, futex
ntdll.dll!RtlWaitOnAddress              (+0x3cc88)
ntdll.dll!RtlpWaitForCriticalSection    (+0x3e6a6)
ntdll.dll!RtlEnterCriticalSection       (+0x26531)
… Eos.exe / Qt5Core.dll frames …
```

and the live `+sync` stream names the lock and its owner:

```
err:sync:RtlpWaitForCriticalSection section 00007B42C31F4BB8 "?" wait timed out in thread 01cc,
        blocked by 07ec, retrying (60 sec)
err:sync:RtlpWaitForCriticalSection section 00007B42C31F48B8 "?" wait timed out in thread 01d8,
        blocked by 07ec, retrying (60 sec)
err:sync:RtlpWaitForCriticalSection section 00007B42C31F48F8 "?" wait timed out in thread 07ec,
        blocked by 01d0, retrying (60 sec)      <-- the GUI thread itself
```

The three sections (+0x38/+0x78/+0x338 inside one heap object) recur identically in every run.

**B. The owner of the section the GUI thread wants (`0x1d0`)** is parked in Wine's *unix* server wait
(not in a lock):

```
libc read()  ->  ntdll.so!wait_select_reply   (dlls/ntdll/unix/server.c:357)
             ->  ntdll.so!server_select       (dlls/ntdll/unix/server.c:777)
             ->  ntdll.so!wait_reply          (dlls/ntdll/unix/server.c:276)
             ->  ntdll.so!server_call_unlocked(dlls/ntdll/unix/server.c:292)
```

i.e. a `WaitForSingleObject`-class wait on a Wine server object (`ntdll!NtWaitFor…`), with the
thread's Linux wchan = `anon_pipe_read` (Wine's client/server channel is a *pipe*,
`dlls/ntdll/unix/server.c:1280 server_pipe()`), so `anon_pipe_read` in `wchan` just means "blocked
in a Wine server wait", not an application pipe.

**C. Everything else is idle and normal** (67 threads in the hang dump):

| what | count | top frame |
|---|---|---|
| pooled app workers | ~48 | `ntdll!ZwWaitForSingleObject` / `ZwRemoveIoCompletion` |
| app worker objects (same Eos.exe frames) | 4 | `kernelbase!WaitForSingleObject` |
| socket pollers | 2 | `ws2_32!select` (Linux wchan `poll_schedule_timeout`) |
| Qt event dispatcher thread | 1 | `kernelbase!WaitForSingleObjectEx` ← `Qt5Core!QWaitCondition::wait` |
| WINMM multimedia thread | 1 | `RtlSleepConditionVariableCS` |
| network monitor | 1 | `ntdll!ZwDelayExecution` (Sleep loop) |

## 4. Discriminators (cheap)

* `+sync` on / `+relay` off → **same stall** (`+relay` only changes the retry period 60 s → 300 s).
* `-platform windows`, explicit `QT_QPA_PLATFORM_PLUGIN_PATH`,
  `QT_LOGGING_RULES=qt.qpa.*=true`, `QT_OPENGL=software`,
  `WINEDLLOVERRIDES="d3d11,dxgi,d2d1,opengl32=b"` → **same stall, same network phase** (this run
  then recovered at 54.09 s and opened the editor). Graphics/Qt is not the blocker: the app's own
  log shows UI init completed and the graphics/Vulkan threads are idle in every dump.
* `WINEDLLOVERRIDES` for the graphics DLLs is a no-op here (d3d11/dxgi/d2d1/opengl32 are already
  builtin); `QT_LOGGING_RULES` only adds qpa noise.
* The relay trace shows the app's "register for network changes" calls:

```
Call iphlpapi.NotifyIpInterfaceChange(0, 0x141284330, ctx, init_notify 0, handle)
fixme:iphlpapi:NotifyIpInterfaceChange (…): stub
Ret  iphlpapi.NotifyIpInterfaceChange() retval=00000000
fixme:iphlpapi:NotifyUnicastIpAddressChange (… init_notify 0 …): semi-stub
```

  Both return success, but Wine never invokes the callbacks → the app's monitor waits forever.
* **Single instance / shared prefix (important for anyone reproducing):** `Eos.exe` holds a
  single-instance object (`QSharedMemory`/`QSystemSemaphore`, and the installer a named mutex
  `Eos_Family_v3_Software_aa8b3a6d-…`), so if an older `Eos.exe` is still alive in
  `state/work/prefix` a new one **exits within ~3 s** with no window and no log lines. Worse,
  `tools/run_eos.sh`'s "kill earlier instances" loop checks `/proc/<pid>/comm` for `wine`
  (`grep -qa -e wine -e wineserver`), but the app process' comm is `Eos.exe` — so it **does not
  kill leftovers**. `pkill -9 -x Eos.exe` before each run, and expect the previous run's window
  handles (`0x1a0000x`) to still be on the display otherwise.
* Tooling notes: `winedbg <dmp>` loads the app's hang dumps but its `info threads` hangs
  (`thread <tid>` is a no-op for minidumps), and `winedbg` attach/host **gdb** need
  `PR_SET_PTRACER` re-armed after Wine itself sets `prctl(PR_SET_PTRACER, server_pid)`
  (`dlls/ntdll/unix/server.c:1668`). `tools/host/{mdmp.py,late_ptrace.c,stall_dump.sh,win_stack_run.sh}`
  handle this; `tools/host/mdmp.py` parses the app's minidumps directly and is the most reliable
  per-thread-stack source.

## 5. Where to patch / what would fix it

1. **`dlls/iphlpapi/iphlpapi_main.c:3966 NotifyIpInterfaceChange()`** — implement it on top of the
   existing NSI plumbing (`NotifyAddrChange()` already does:
   `NsiRequestChangeNotification(0, &NPI_MS_IPV4_MODULEID, NSI_IP_UNICAST_TABLE, …)`,
   `nsiproxy.sys` `IOCTL_NSIPROXY_WINE_CHANGE_NOTIFICATION`), and call the app callback on change
   instead of returning `NO_ERROR` with `*handle = NULL`. Same for **:4014
   `NotifyUnicastIpAddressChange()`** (deliver changes, not only the `init_notify` event).
2. Optionally provide/relay an SLP SA so `SLPReg()` does not time out (`-19`), and/or make the
   app's degraded path acceptable.
3. `ws2_32` `setsockopt(IP_MULTICAST_IF)` / `IP_ADD_MEMBERSHIP` currently fail with `WSAEINVAL` on
   Wine interfaces, which makes the app declare all interfaces unusable for sACN
   (`[CRIT] sACN: None of the network interfaces were usable for the sACN API.`).

None of the fixes is in `dlls/ntdll/sync.c`: `RtlpWaitForCriticalSection` is doing exactly what the
app asked for; the lock is simply never released because the owner's network step never completes.

## 6. Evidence index

* `logs/runs/winedbg/run4/gdb.txt`, `run4/maps.txt`, `run4/task_state.txt`, `run4/sync_errors.txt`
* `logs/runs/winedbg/stacks1/{gdb_raw.txt,maps.txt,task_state.txt,sync_errors.txt}`
* `logs/runs/winedbg/dumps/{hang_A_S.dmp,bt_hangS.txt,hang_threads.txt,EosAsserts.txt,OnyxConsole.log,NetworkFeedback.log,CriticalIssues.txt}`
* `logs/runs/disc1/{out.txt,windows_60.txt,screen_60s.png}` — the recovering run (editor window + OCR)
* `logs/api/wine_eos.relay.log` — `NotifyIpInterfaceChange` / `NotifyUnicastIpAddressChange` calls
* Windows reference: `EosVMReference` report (guest `OnyxConsole.log`, `logs/vm/vm_winprobe.txt`)
* tools used: `tools/host/{mdmp.py,bt_raw.py,resolve_addr.py,stall_dump.sh,win_stack_run.sh,stack_dump.sh,late_ptrace.c}`
