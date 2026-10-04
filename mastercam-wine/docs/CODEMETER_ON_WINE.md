# CodeMeter on Wine — what `WIBUCM64.dll` needs, and what Wine provides

Empirical probe (no guessing) of the CodeMeter 8.40a runtime shipped as
`SetupPrerequisites/CodeMeterRuntime64.msi`, of `MastercamLicensingSetup.exe`, and of the two
client↔service rendezvous involved, run under
`/home/asdf/projects/resolume-wine/wine-install/bin/wine` (wine-11.18, the 19-patch base).

Probe owner: `CodeMeterProbe`. Scratch prefix: `state/exp/CodeMeterProbe/prefix` (kept — it holds a
working CodeMeter + Mastercam Licensing Utilities install). Logs: `logs/exp/CodeMeterProbe/`.
Env for every command:

```bash
source /home/asdf/projects/mastercam-wine/state/exp/CodeMeterProbe/cm-env.sh
# WINE=/home/asdf/projects/resolume-wine/wine-install/bin/wine
# WINEPREFIX=.../state/exp/CodeMeterProbe/prefix     (win64, win10)
# WINEDEBUG=+err,+warn   WINEDLLOVERRIDES="mscoree,mshtml="
```

Everything below is a direct observation unless marked `[INFERENCE]`.

---

## BLOCKER REPORT — Mastercam can load, but it cannot be *licensed* on Wine

**Mastercam 2027 cannot be made fully work on Wine with any local licence, because every local
licence mode depends on kernel-level APIs that Wine does not implement.**

* Wine has **no kernel-driver support**. CodeMeter's driver (`CmHt`/`vusb.sys`/`wibuvd.sys`) cannot
  be loaded, and the Aladdin/Sentinel HASP USB drivers (`aksusbd`/`multikey.sys`) likewise cannot.
  This is architectural, not something a Wine API stub can fix.
* Therefore: **no hardware dongle** (CmDongle, HASP-HL, NetHASP-with-dongle-on-this-machine) and
  **no CodeMeter software container** (CmActLicense needs the driver for machine binding *and* the
  local Runtime Server's API channel — see §12, where `Global\CmApiCallIn` is never published).
* What *does* work: the application can **start**, because `WIBUCM64.dll` loads fine once the
  CodeMeter runtime is on disk (§3). It then fails the licence check and exits with
  "No Mastercam license found."
* The **only** path that could license Mastercam on Wine is a **network licence server on real
  Windows** (HASP License Manager / `nethasp.ini`, port 475/1947, or a CodeMeter network server),
  with the Wine side acting purely as a TCP/UDP client. Wine can even host the HASP LM server
  (`hasplms` runs and listens on TCP+UDP 1947, §7.3) — but the *client* side of the CodeMeter
  network path still needs the broken local service, so the Mastercam/NetHASP route is the only
  credible one, and it is **untested end-to-end here** (no dongle, no server available).

Everything else below is the evidence for those statements.

| question | answer |
|---|---|
| Does Wine load `WIBUCM64.dll`? | **Yes.** Purpose-built static-import PE + negative control (§3). |
| Does the vendor CodeMeter MSI install silently as documented? | **No.** Exit **91** (`1627 & 0xFF`), full rollback. Blocked by the `CmWebAdmin` service start (§2.1). |
| Can it be made to install? | **Yes**, one workaround: pre-create a *running* service named `CmWebAdmin.exe`. Then exit **0**, 118 MB installed (§2.2). |
| Does the CodeMeter Runtime Server service install/start/announce RUNNING? | **Yes** — service installed, SCM reports `STATE 4 RUNNING`, process alive, TCP 22350 listening. This is *not* the Autodesk session-0 class of failure (§4). |
| …but is it reachable by clients? | **No.** The server publishes all its `Global\Cm*Event` notification objects, but **never creates `Global\CmApiCallIn`**, the API channel clients use. `cmu -v` therefore reports `CodeMeter-Service: not running` (§4.3). |
| Does the kernel driver load? | **No.** No `.sys`/`.inf`/`.cat` ships at all; the driver is embedded in `CodeMeter.exe` and installed at service start. Wine has no kernel-driver support (§5). |
| Usable "no dongle" state? | **Yes, in user mode**: `cmu --list` → `Result: 0 CmContainer(s) listed.` (exit 0) (§6). |
| `MastercamLicensingSetup.exe`? | **Installs cleanly, exit 0**, and — important — it registers and **starts the HASP License Manager `hasplms`, which then listens on TCP+UDP 1947** (§7). |
| (a) start with no licence? | Yes — the `WIBUCM64.dll` import resolves once CodeMeter files exist; the licence check then fails with "No Mastercam license found." |
| (b) CodeMeter software container? | **No** — needs the missing `CmApiCallIn` service channel (+ driver for binding). |
| (c) network licence? | **Best candidate.** The *server side* (`hasplms` HASP LM) works under Wine (§7.3) and a remote real-Windows LM can be used from the client via `nethasp.ini`. |

---

## 1. Scratch prefix

```bash
WINEARCH=win64 WINEDEBUG=-all $WINE wineboot -u    # exit 0
```

Win64 prefix with Wine's new WoW64 (build ships `x86_64-unix` + `i386-windows`; there is no
`i386-unix`), so 64-bit and 32-bit prerequisites both run. The prefix identifies itself as
**Windows 10 Pro, 64-Bit** (`cmu -v`).

---

## 2. `CodeMeterRuntime64.msi` silent install

### 2.1 Attempt 1 — as documented. **Fails, exit 91.**

```bash
$WINE msiexec /i 'Z:\run\media\asdf\Windows\mastercam-media\SetupPrerequisites\CodeMeterRuntime64.msi' \
      ALLOW_BELOW=1 REBOOT=ReallySuppress /qn /norestart /l*v 'C:\cm-install.log'
# exit 91
```

`Program Files/CodeMeter/` does not exist afterwards (no `InstallFinalize` in the 16,349-line log —
the transaction rolled back). Registry left over: only
`HKLM\SOFTWARE\WIBU-SYSTEMS\CodeMeter\Server\CurrentVersion\ShmTimeout`.

Cause, from the Wine console log (`logs/exp/CodeMeterProbe/install.log`):

```
025c:err:service:process_send_start_message service L"CmWebAdmin.exe" failed to start
0124:err:msi:ITERATE_StartService failed to start service L"CmWebAdmin.exe" (1053)
0124:err:msi:execute_script Execution of script 0 halted; action L"StartServices" returned 1627
0124:err:msi:ITERATE_Actions Execution halted, action L"InstallExecute" returned 1627
```

`1053` = `ERROR_SERVICE_REQUEST_TIMEOUT`, `1627` = `ERROR_FUNCTION_FAILED`; Wine returns
`1627 & 0xFF` = **91**. The MSI's `StartServices` action processes `ServiceControl` row

```
SC_CmWebAdmin_start_64.1992E333_…   CmWebAdmin.exe   1   (no args)   Wait=0   C_CmWebAdmin_SvcCtl_StartChkd64
```

which lives in feature **`Complete`** (level 1, condition `(VersionNT64) AND (NOT CM_NODOWNGRADE)`)
— so it is always installed and cannot be deselected with `REMOVE=`/`CM_HIDE_WEBADMIN` (the latter
only gates the separate `AccessToWebAdmin` feature). Wine's
`ITERATE_StartService` (`wine-11.18/dlls/msi/action.c:5928`) calls `StartServiceW()`; Wine's
services.exe launches `CmWebAdmin.exe` and waits for it to report `START_PENDING`. It never does →
1053 → the script halts → rollback. **The optional `CmWebAdmin` web UI is the sole blocker.**

### 2.2 Attempt 2 — with a running stand-in service. **Exit 0.**

Wine tolerates `ERROR_SERVICE_ALREADY_RUNNING` in `ITERATE_StartService` and
`ERROR_SERVICE_EXISTS` in `ITERATE_InstallService` (`action.c:5839`), so a pre-existing, running
service of the same name satisfies both.

```bash
# cmstub.c: StartServiceCtrlDispatcherW({"CmWebAdmin.exe"}) + SetServiceStatus(RUNNING) + idle
x86_64-w64-mingw32-gcc -O2 -municode -o cmstub.exe cmstub.c -ladvapi32
cp cmstub.exe "$WINEPREFIX/drive_c/cmstub.exe"
$WINE sc create 'CmWebAdmin.exe' binPath= 'C:\cmstub.exe' type= own start= auto DisplayName= 'CmWebAdmin'
$WINE sc query 'CmWebAdmin.exe'      # STATE 4 RUNNING (Wine auto-starts it)
$WINE msiexec /i '<msi>' ALLOW_BELOW=1 REBOOT=ReallySuppress /qn /norestart /l*v 'C:\cm-install2.log'
# exit 0
```

An equally valid alternative (not applied, only prepared): a transform that imports a
`ServiceControl` table with the two `Event=1` rows removed — table dumps and the edited
`ServiceControl.idt` are in `state/exp/CodeMeterProbe/idt/`.
`msibuild -i` could not be used here (libmsi's `idt` import fails at open with
`open failed for <path>` on this host), so the running-stub route was used.

### 2.3 What lands in the prefix

```
C:\Program Files\CodeMeter\                    118 MB
  Runtime\bin\  CodeMeter.exe (51,652,088 B), CmWebAdmin.exe, cmu.exe, cmu32.exe,
                CodeMeterCC.exe, CmRmtAct64.dll, WibuCmTrigger64.dll, *.l??
  Runtime\help\…
C:\windows\system32\   cpsrt.dll, WibuCm64.dll, wibucmJNI64.dll, WibuXpm4J64.dll
                       (+ .lcn .lde .les .lfr .lit .ljp .lru), i.e. the client library and the
                       shared runtime are installed to system32, NOT to Runtime\bin
C:\ProgramData\CodeMeter\{CmAct (Catalogue.WibuCmHt), CmCloud, Logs, Backup}
services:  CodeMeter.exe ("CodeMeter Runtime Server"),  CmWebAdmin.exe
```

The MSI ships **no `.sys`, `.inf` or `.cat`** — verified twice: the `File` table contains none, and
a full unpack of the MSI plus all 24 cabinets (`7z x CodeMeterRuntime64.msi`, then every
`cabNN.cab`, 214 MB) yields none. The kernel driver is embedded in `CodeMeter.exe`.

---

## 3. `WIBUCM64.dll` — the static import of `MastercamLauncher.exe`

Reproduced with a purpose-built PE (`state/exp/CodeMeterProbe/witest/`) whose import is
**by ordinal, NONAME** — the same shape as Mastercam's import table
(`dlltool -d WIBUCM64.def -l libWIBUCM64.a`, `EXPORTS wibu_o1 @1 NONAME`; `WibuCm64.dll` exports by
ordinal only, no names):

| setup | Wine log | result |
|---|---|---|
| `C:\WIBUCM64.dll` (or `C:\windows\system32\WibuCm64.dll`) present | `trace:loaddll:build_module Loaded L"C:\WIBUCM64.dll" at 0000000076FA0000: native` | **exit 0** |
| DLL removed everywhere | `err:module:import_dll Library WIBUCM64.dll (which is needed by L"C:\witest.exe") not found`<br>`err:module:loader_init Importing dlls for L"C:\witest.exe" failed, status c0000135` | **process never starts** |

`0xc0000135` = `STATUS_DLL_NOT_FOUND`. So the static import of `WIBUCM64.dll` is **not** a Wine
problem; it is purely "is the CodeMeter runtime on disk". Loading the DLL also runs its init, which
calls Wine's `EnumDeviceDrivers` (stubbed, returns nothing) while probing for the kernel driver.

---

## 4. The CodeMeter Runtime Server service

Wine tears services down as soon as the last `wine` client exits, so **keep the wineserver alive**:

```bash
$WINE wineserver -p        # mandatory for meaningful service observations
```

### 4.1 It installs, starts and announces RUNNING

```bash
$WINE sc start CodeMeter.exe       # rc=32; stderr: "ShellExecuteEx failed: File not found."
                                   # (Wine's `sc start` mis-parses the MSI's UNQUOTED ImagePath;
                                   #  the SCM auto-starts the service anyway, StartType=2)
$WINE sc query CodeMeter.exe
    STATE : 4  RUNNING      CHECKPOINT : 0x10
pgrep -af CodeMeter.exe    # C:\Program Files\CodeMeter\Runtime\bin\CodeMeter.exe
```

SCM trace (`WINEDEBUG=+service`): `StartServiceW` → `err:sc:wmain failed to start service 1056`
(`ERROR_SERVICE_ALREADY_RUNNING` — already auto-started). An earlier run showed the same service in
`STATE 2 START_PENDING / CHECKPOINT 0xb` when the wineserver was not persistent; with `wineserver -p`
it reaches RUNNING. **CodeMeter therefore does *not* hit the Autodesk `services-session-0` /
`service_pipe_timeout` class of failure** — the SCM handshake works.

The service also opens its network port:

```
LISTEN 0 511 127.0.0.1:22350   users:(("wineserver",pid=2430076,fd=714))
```

### 4.2 …and publishes its notification objects

Wine's `Global\` namespace itself works (self-test from a 64-bit probe:
`CreateEvent(Global\CmProbeSelfTest)` → handle `0x38`, `OpenEvent` → `0x3c`,
`CreateFileMapping(Global\CmProbeSelfMap)` → `0x38`). And the *service* publishes its events, so
there is no session/namespace split:

| object | probe result (as event / mutex / section) |
|---|---|
| `Global\CmBoxAddedEvent` | **open OK (0x38)** |
| `Global\CmBoxEnabled` / `CmBoxDisabled` | **open OK (0x38)** |
| `Global\CmEntryAltered` | **open OK (0x38)** |
| `Global\CmServerTerminatedEvent` | **open OK (0x38)** |
| `Global\CmNetworkLostEvent` | **open OK (0x38)** |
| `Global\CmThresholdExpDateEvent` / `CmThresholdUCEvent` | **open OK (0x38)** |
| **`Global\CmApiCallIn`** | **absent — event=NULL, mutex=NULL, map RO=NULL, map RW=NULL, `GetLastError()==2`** |

### 4.3 The divergence

`Global\CmApiCallIn` is the channel a client writes API calls into. It is **never created** — not as
an event, mutex, section or file mapping — while the service is RUNNING and holding TCP 22350. The
consequence is exactly what the product reports:

```bash
$WINE cmu.exe -v | grep CodeMeter-Service
 CodeMeter-Service:       not running        # SCM says RUNNING; the API channel is missing
```

**First divergence from Windows: the CodeMeter Runtime Server serves its event/notification set but
never publishes the `Global\CmApiCallIn` API channel.** `[INFERENCE]` it defers creating that channel
until its kernel-driver/device initialisation succeeds, which cannot happen on Wine (§5). Every
Mastercam license query goes through that channel, so licensing is dead even with the runtime
"installed and RUNNING".

---

## 5. Kernel driver

* Driver identifiers are inside `CodeMeter.exe`: `CmHt`, `CmHt3`, `CmHtD`, `WibuCmHtH`, plus
  section-related strings `EXPECTED_A_SECTION_NAME`, `INVALID_SECTION`, `UNABLE_TO_CREATE_NEW_SECTION`,
  `SECTION_NOT_FOUND`, `NtQuerySection`. `CodeMeter.exe` imports `SETUPAPI.dll` (it installs its driver
  itself) and `cpsrt.dll`.
* No `.sys`/`.inf`/`.cat` anywhere in the MSI or the payload (§2.3).
* Wine logged `fixme:seh:EnumDeviceDrivers (…) stub` while `WibuCm64.dll` and the service probed for
  loaded kernel drivers — Wine answers "none".
* `C:\windows\system32\drivers\` gained **no** Wibu driver and no `Type=1` service appeared. The only
  artefact was a Wine ACL sidecar `BuHt.winsecurity` (65,536 B) whose first 4 bytes are `CmHt`
  (the driver object name), created once during the first service start; it did not reproduce on
  later starts and no corresponding driver file existed.

**Consequence: no hardware CmDongle/HASP, and any licence binding that requires the driver
(CmActLicense machine binding, error 268 "cannot bind CmActLicense to this machine") is unavailable.**

---

## 6. "No dongle" state is reported cleanly in user mode

```bash
$WINE cmu.exe -l
List all locally connected CmContainers:
Result: 0 CmContainer(s) listed.          # exit 0
```

`cmu.exe --help | -v | -l` all run; `-v` reports `Operating System: Microsoft Windows 10 Pro, 64-Bit`
and the 8.40.7120.501 file versions (only cosmetic console-codepage noise: `setting console output
to utf8 failed (12)`). The DLL also ships the relevant error catalogue, e.g.
"*For CmActLicense the CodeMeter License Server must run as a service, Error 267*",
"*CodeMeter cannot bind CmActLicense to this machine, Error 268*",
"*CodeMeter License Server start is still pending, Error 238*".

---

## 7. `MastercamLicensingSetup.exe` (Mastercam Licensing Utilities)

```bash
$WINE 'Z:\run\media\asdf\Windows\mastercam-media\SetupPrerequisites\MastercamLicensing\MastercamLicensingSetup.exe' \
      /s /v"/qn REBOOT=ReallySuppress /L*V \"C:\lic.log\""
```

Self-extracts to `%TEMP%\{GUID}` and re-invokes msiexec (child command line observed via `pgrep`):

```
C:\windows\system32\MSIEXEC.EXE /i …\Mastercam Licensing Utilities.msi /qn REBOOT=ReallySuppress
   /L*V C:\lic.log TRANSFORMS=…\1033.MST SETUPEXEDIR=Z:\…\MastercamLicensing
   SETUPEXENAME=MastercamLicensingSetup.exe IS_RUNTIME_FILES_LOCATION=C:\users\asdf\AppData\Local\Temp\{…}
```

### 7.1 Outcome: **exit 0**

`lic.log` ends with `Action ended …: INSTALL. Return value 1.`; no `Return value 3`, no errors.
`Property(S)`: `ProductName = Mastercam Licensing Utilities`, `ProductVersion = 29.0.10172.0`,
`ProductCode = {6FCF92EF-02B6-45BB-82CE-1C0A52F3338A}`, `ALLUSERS = 1`.
Installed to `C:\Program Files\Common Files\Mastercam\MastercamLicensing\` (plus a chained
`/qn /i …\CodeMeterRuntime64.msi` run — which also passed, because the stub service from §2.2 was
still registered).

The tree is the whole licensing stack:

* NetHASP/HASP: `nethasp.ini`, `NHaspX.exe`, `haspds_windows.dll`, `hdinst_windows.dll`,
  `hinstall.exe`, `haspdinst.exe`, `HASPUserSetup.exe`, `HaspX.exe`
* CodeMeter: `WibuCmNET.dll` (the managed Wibu wrapper)
* Managed UX/tools: `ActivationWizard.exe` + `.Console.exe`, `MastercamLicenseBorrowUtility.exe`,
  `MastercamDotComLinking.exe` (WPF; the installer also brought the .NET desktop runtime into
  `C:\Program Files\dotnet`)

### 7.2 Services after the licensing install

```
hasplms     STATE 4 RUNNING   ImagePath "C:\Program Files (x86)\Common Files\Aladdin Shared\HASP\hasplms.exe" -run
CodeMeter.exe STATE 4 RUNNING
CmWebAdmin.exe STATE 4 RUNNING   (the §2.2 stub)
aksusbd     not present          (kernel driver; would be installed by haspdinst.exe)
```

### 7.3 The HASP License Manager actually serves

```
LISTEN 0 128 0.0.0.0:1947  users:(("hasplms.exe",pid=2436727,fd=34))
LISTEN 0 128    [::]:1947  users:(("hasplms.exe",pid=2436727,fd=36))
UNCONN 0   0 0.0.0.0:1947  users:(("hasplms.exe",pid=2436727,fd=35))
UNCONN 0   0    [::]:1947  users:(("hasplms.exe",pid=2436727,fd=37))
```

**The Aladdin/Sentinel HASP License Manager is fully functional under Wine** — running as a service
and listening on TCP+UDP **1947** (the Sentinel LDK LM port; Mastercam's guide quotes 475 for the
older `nhsrvw32` NetHASP server). Note there is *no* local listener on 475; only 1947.
A local HASP *dongle* still cannot work (kernel driver), but the **network licence-manager role does**.

---

## 8. Answers to the three licence modes

**(a) No licence at all — plausible.** Once the CodeMeter files are on disk the `WIBUCM64.dll` static
import resolves (§3) and the launcher can load. It then runs its licence check, CodeMeter reports
zero containers (§6), and Mastercam exits with "No Mastercam license found."
Nothing in that path needs the driver, the service channel or a network — only that CodeMeter be
installed (which needs the §2.2 workaround).

**(b) CodeMeter software container (CmActLicense) — not on Wine.** Requires the API channel
`Global\CmApiCallIn` that never appears (§4.3), plus the kernel driver for machine binding (§5).
`ActivationWizard.exe`/`CodeMeterCC.exe` would have nothing to talk to.

**(c) Network licence — the only Wine-hostable path, and it looks genuinely promising.**
`hasplms` (HASP License Manager) installs, runs and **listens on 1947** under Wine (§7.3), so Wine
can be either the client or the server. Mastercam's client side is controlled by
`nethasp.ini` (`[NH_COMMON] NH_TCPIP = Enabled`, then `[NH_TCPIP] NH_SERVER_ADDR = <ip>`), and the
launcher contains `?AVNetHaspIo@@` and `<license_manager hostname="localhost">`. Server-side
requirements: a real HASP/NetHASP dongle, or the `hasplms`/`nhsrvw32` LM on a real Windows host.
Client-side this is plain TCP/UDP from the Wine prefix and does not go through Wine's SCM or the
Wibu service. **Untested end-to-end here** — no dongle or remote LM was available — but this is the
only path whose prerequisites Wine demonstrably satisfies.

---

## 9. Blocking points, ranked

1. `CmWebAdmin.exe` service start (1053) aborts the CodeMeter MSI (1627 → exit 91). Root cause (§11):
   it is a Go binary using `svc.IsAnInteractiveSession()`, and Wine's service token still carries
   the INTERACTIVE group SID, so it never calls `svc.Run()`. *Workaround verified (§2.2); the real
   fix is a service-logon token group set (§11.5).*
2. The Runtime Server never publishes `Global\CmApiCallIn` → clients see "CodeMeter-Service: not
   running" even though the SCM says RUNNING and events exist. Gated behind the Wibu kernel driver,
   which Wine cannot provide (§12) — unreachable by design.
3. No kernel-driver support ⇒ no dongle, no CmActLicense binding (§5).

Ranked next steps: (i) patch token groups for session-0 children so Go services recognise
themselves (fixes the MSI install without a stub, and any other Go/kardianos service); (ii) ship the
§2.2 stub or the `ServiceControl` transform meanwhile; (iii) chase the `S:(ML;;NW;;;LW)` SDDL lead
(§12) before writing off the local CodeMeter runtime; (iv) prefer the `nethasp.ini` network path,
which avoids 2 and 3 entirely.

---

## 10. Reproduce

```bash
cd /home/asdf/projects/mastercam-wine
source state/exp/CodeMeterProbe/cm-env.sh
WINEARCH=win64 WINEDEBUG=-all $WINE wineboot -u

# stub service so the CodeMeter MSI's StartServices can succeed
x86_64-w64-mingw32-gcc -O2 -municode -o state/exp/CodeMeterProbe/cmstub.exe state/exp/CodeMeterProbe/cmstub.c -ladvapi32
cp state/exp/CodeMeterProbe/cmstub.exe "$WINEPREFIX/drive_c/cmstub.exe"
$WINE sc create 'CmWebAdmin.exe' binPath= 'C:\cmstub.exe' type= own start= auto DisplayName= 'CmWebAdmin'

# CodeMeter  -> exit 0
$WINE msiexec /i 'Z:\run\media\asdf\Windows\mastercam-media\SetupPrerequisites\CodeMeterRuntime64.msi' \
      ALLOW_BELOW=1 REBOOT=ReallySuppress /qn /norestart /l*v 'C:\cm-install2.log'

# Mastercam Licensing Utilities -> exit 0 (also starts hasplms, listener on 1947)
$WINE 'Z:\run\media\asdf\Windows\mastercam-media\SetupPrerequisites\MastercamLicensing\MastercamLicensingSetup.exe' \
      /s /v"/qn REBOOT=ReallySuppress /L*V \"C:\lic.log\""

# service investigation (wineserver must be persistent)
$WINE wineserver -p
$WINE sc query CodeMeter.exe                                   # STATE 4 RUNNING
x86_64-w64-mingw32-gcc -O2 -municode -o state/exp/CodeMeterProbe/cmprobe.exe state/exp/CodeMeterProbe/cmprobe.c
cp state/exp/CodeMeterProbe/cmprobe.exe "$WINEPREFIX/drive_c/cmprobe.exe"
$WINE 'C:\cmprobe.exe'                                         # Cm*Event OK, CmApiCallIn missing
$WINE 'C:\Program Files\CodeMeter\Runtime\bin\cmu.exe' -v      # "CodeMeter-Service: not running"
$WINE 'C:\Program Files\CodeMeter\Runtime\bin\cmu.exe' -l      # "0 CmContainer(s) listed."
ss -ltnp | grep -E '22350|1947'
```

Evidence files: `logs/exp/CodeMeterProbe/{install.log,install2.log,cm-svc-start.log,svc-start2.log,cmu-*.out,lic-install.log}`;
sources/tools kept: `state/exp/CodeMeterProbe/{cm-env.sh,cmstub.c,cmstub.exe,cmprobe.c,cmprobe.exe,sessprobe.c,witest/,idt/}`.

---

# 11. Follow-up A — why `CmWebAdmin.exe` never reaches SERVICE_RUNNING

**Answer: `golang.org/x/sys/windows/svc.IsAnInteractiveSession()` reads the process token's
*groups*; Wine's service processes still carry the interactive logon token (S-1-5-4 present,
S-1-5-6 absent), so Wibu's Go program classifies itself as "interactive" and never calls
`svc.Run()`.**

### 11.1 What the binary actually is

`CmWebAdmin.exe` is a **Go** binary (13 MB, PE32+ x86-64). Its static imports are only
`WIBUCM64.dll`, `KERNEL32.dll`, `msvcrt.dll` — advapi32 is loaded lazily by the Go runtime. Its Go
symbol table (pclntab strings) contains:

```
golang.org/x/sys/windows/svc.IsAnInteractiveSession
golang.org/x/sys/windows/svc.Run
golang.org/x/sys/windows/svc.allocSid
golang.org/x/sys/windows/svc.serviceMain / ctlHandler / ChangeRequest / Status
```

It uses the **older/deprecated** `IsAnInteractiveSession`, not `IsWindowsService` — which is why
patch 0004 (process session id) does not help here.

### 11.2 The Go source, traced to Win32

`golang.org/x/sys/windows/svc/security.go` (upstream master):

```go
func IsAnInteractiveSession() (bool, error) {
	interSid, _ := allocSid(windows.SECURITY_INTERACTIVE_RID)   // S-1-5-4   (AllocateAndInitializeSid)
	serviceSid, _ := allocSid(windows.SECURITY_SERVICE_RID)     // S-1-5-6
	t, _ := windows.OpenCurrentProcessToken()
	gs, _ := t.GetTokenGroups()
	for _, g := range gs.AllGroups() {
		if windows.EqualSid(g.Sid, interSid) { return true, nil }   // INTERACTIVE -> console mode
		if windows.EqualSid(g.Sid, serviceSid) { return false, nil } // SERVICE     -> service mode
	}
	return false, nil
}
```

Win32 calls involved: `AllocateAndInitializeSid`, `OpenProcessToken/OpenCurrentProcessToken`,
`GetTokenInformation(TokenGroups)`, `EqualSid`. **None of them is a Wine API failure** — the
problem is the *content* of the token Wine builds for a service process.

### 11.3 Measured in Wine (probe `tokprobe.c`)

```
# as a normal process (parent = shell)
[tokprobe] pid=644 INTERACTIVE=1 SERVICE=0
# as a service started by Wine's SCM (parent = services.exe, session 0)
pid=696 TokenGroups:
   S-1-1-0  S-1-2-0  S-1-5-4  S-1-5-11  S-1-5-21-0-0-0-513  S-1-5-32-544  S-1-5-32-545  S-1-5-5-0-0
   => INTERACTIVE(S-1-5-4)=1 SERVICE(S-1-5-6)=0
   => svc.IsAnInteractiveSession() would return true  => console/CM mode
```

The service token is **identical** to the interactive one: Wine creates no "service logon"
flavour. (Contrast `sessprobe.c`, which shows the *process* session is correctly 0 and the parent
is `services.exe` — the preconditions of the newer `IsWindowsService()` are satisfied; the
token-based check is the one that fails.)

### 11.4 The observed consequence chain

1. `CmWebAdmin.exe`, started by the SCM, decides "interactive" and runs its console path. Proof:
   with the service running it prints `Running in CM mode` / `Starting HTTP-Server...` in a plain
   run, and as a service it **opens TCP 127.0.0.1:22352** (the WebAdmin HTTP listener) instead of
   registering.
2. It never calls `StartServiceCtrlDispatcherW`: the `WINEDEBUG=+service` stream for a start
   contains **no** `service_run_main_thread ... Starting N services` line and no control-pipe
   connect from that PID (native services *do* log it).
3. Wine's SCM side:
   ```
   0188:trace:service:svcctl_StartServiceW (...)
   0188:trace:service:process_send_start_message 00007FFFFE8C3FF0 L"CmWebAdminTest" ... 0
   0188:err:service:process_send_start_message service L"CmWebAdminTest" failed to start
   0188:trace:service:service_start returning 1053
   ```
   after `WaitForMultipleObjects(..., service_pipe_timeout)` — `service_pipe_timeout = 10000`
   (`wine-11.18/programs/services/services.c:44`); Windows' SCM budget is 30 s.
4. The MSI's `StartServices` therefore returns 1627 → rollback → **exit 91** (§2.1).

### 11.5 Proposed Wine patch

* **Failing API**: `GetTokenInformation(TokenGroups)` on a process started by the SCM
  (`golang.org/x/sys/windows/svc.IsAnInteractiveSession`).
* **Wine implementation**: token creation in `server/token.c` (`token_create` / group building);
  service processes are launched by `server/process.c` with the ordinary interactive user token.
  Patch `0004-services-session-0.patch` already computes "parent is session 0 ⇒ this process is
  session 0" there, and its notes explicitly say the *token* was left untouched.
* **Patch (proposed)**: when `parent->session_id == 0` (i.e. the process is started by
  `services.exe`), give the new process a **service-logon token** — build the token's groups
  without the INTERACTIVE well-known SID (`S-1-5-4`) and with the SERVICE SID (`S-1-5-6`,
  `SE_GROUP_ENABLED`) added, mirroring Windows' service logon. Mechanically this is the same shape
  as patch 0004: a flag derived from the parent in `server/process.c` honoured in
  `server/token.c`'s group construction. That makes both families of checks agree —
  `IsAnInteractiveSession()` (token groups) *and* `IsWindowsService()` (parent session + image).
* **Secondary (not the root cause)**: align `service_pipe_timeout` in
  `programs/services/services.c:44` with Windows' 30 s, so a genuinely slow service start is not
  misreported as 1053. It would **not** fix this hang (the service never connects at all).
* Until patched, the §2.2 stub service (or the `ServiceControl` transform) is required to install
  CodeMeter at all.

---

# 12. Follow-up B — why `Global\CmApiCallIn` is never created

**Answer: unreachable, by design.** The CodeMeter Runtime Server publishes its notification
objects but never the API channel, and the only credible gate — the Wibu kernel driver — cannot
exist on Wine.

* The service is genuinely up: SCM `STATE 4 RUNNING`, process alive, **TCP 127.0.0.1:22350
  listening**, and all of `Global\CmBoxAddedEvent`, `CmBoxEnabled/Disabled`, `CmEntryAltered`,
  `CmServerTerminatedEvent`, `CmNetworkLostEvent`, `CmThresholdExpDateEvent`,
  `Global\CmThresholdUCEvent` open successfully from a separate session-1 process.
* `Global\CmApiCallIn` / `CmApiCallOut` do **not** exist in any form — as event, mutex, section or
  file mapping (`OpenEvent/OpenMutex/OpenFileMapping(R/W)` all return NULL, `GetLastError()==2`).
  Wine's namespace itself is fine (probe self-test: `CreateEvent(Global\CmProbeSelfTest)`, 
  `CreateFileMapping(Global\CmProbeSelfMap)` both succeed).
* The literal name exists only in the **client** library `C:\windows\system32\WibuCm64.dll`
  (UTF-16). `CodeMeter.exe` and `cpsrt.dll` contain no plaintext copy — the server-side name is
  obfuscated/constructed, so a plain string-xref hunt dead-ends.
* What the server *does* at that moment (`WINEDEBUG=+file`, `CodeMeter.exe`):
  it probes for seven **kernel driver files** — `drivers\vusb.sys`, `vusbbus.sys`, `wibuvd.sys`,
  `b70bus.sys`, `mcamvusb.sys`, `multikey.sys`, `Znet_hasp64.sys` — none of which ship anywhere in
  the MSI or payload (§2.3); none is found (`c0000034`). No device open (`\??\vusb`, `\??\CmHt`,
  …), no `NtLoadDriver` and no driver `CreateService` follows; the only device-ish opens are
  `\??\MountPointManager`, `\??\Nsi`, `\??\PhysicalDrive0`, `\??\VSCSI`-class and `\??\pipe\svcctl`.
  `WibuCm64.dll` additionally calls `EnumDeviceDrivers`, which Wine stubs (returns 0 drivers).
* Client behaviour matches: `cmu.exe -v` → `CodeMeter-Service: not running`;
  `cmu.exe -l` → `Result: 0 CmContainer(s) listed.` (the user-mode "no container" path works).

**Failing API**: none fails outright; there is no Wine API to patch here.
**Wine implementation**: n/a — Wine cannot load kernel drivers, so `vusb.sys`/`wibuvd.sys`/`CmHt`
state can never exist.
**Verdict**: *unreachable, by design.* Any licence mode that requires the local CodeMeter Runtime
Server (CmActLicense software containers, local dongles) cannot work on Wine; the HASP/network path
(§7.3, §8c) is the way forward.

**Open lead — now TESTED and negative.** The client library embeds the SDDL fragment
`S:(ML;;NW;;;LW)` (a low-integrity mandatory label) and `CodeMeter.exe` imports
`ConvertStringSecurityDescriptorToSecurityDescriptorA`, so a Wine advapi32 gap was a plausible second
cause. Probe `state/exp/CodeMeterProbe/sdprobe.c` shows there is **no such gap**:

```
SDDL "D:(A;;GA;;;WD)"                 convert=1 err=0  control=0x8004  CreateEvent/CreateFileMapping OK
SDDL "S:(ML;;NW;;;LW)"                convert=1 err=0  control=0x8010  CreateEvent/CreateFileMapping OK
SDDL "D:(A;;GA;;;WD)S:(ML;;NW;;;LW)"  convert=1 err=0  control=0x8014  CreateEvent/CreateFileMapping OK
```

Wine accepts every form and objects can be created with the resulting descriptors. (Only cosmetic:
Wine's back-conversion renders the label flags as `S:(;;CC;;;LW)` instead of `NW`, i.e. the ACE
*flags* are mapped loosely — irrelevant here because CodeMeter never reads the descriptor back.)
The one non-kernel lead is therefore closed: **the missing `Global\CmApiCallIn` is not caused by a
patchable advapi32/security gap.**

### 12.1 Decisive object-level trace — the channel is never even attempted

Running the service start with `WINEDEBUG=+sync,+virtual,+err,+warn` and filtering to `Cm[A-Z]`
(events/mutants from `+sync`, named sections from `+virtual`) over a full startup
(`logs/exp/CodeMeterProbe/cm-objects.log`) shows the service creates **only its notification
events** — and nothing else whose name contains `Cm`:

```
NtCreateEvent ... name L"Global\\CmBoxAddedEvent"        (and -1 variants)
NtCreateEvent ... name L"Global\\CmBoxEnabled" / CmBoxDisabled / CmBoxRemoveEvent / CmBoxReplaceEvent
NtCreateEvent ... name L"Global\\CmEntryAltered / CmEntryModifiedEvent
NtCreateEvent ... name L"Global\\CmNetworkLostEvent / CmNetworkReplacedEvent
NtCreateEvent ... name L"Global\\CmServerTerminatedEvent
NtCreateEvent ... name L"Global\\CmThresholdUCEvent / CmThresholdExpDateEvent
--- zero occurrences of CmApi, and zero named NtCreateSection/NtOpenSection calls ---
```

There is **no failing API call** to point at: the runtime never issues any
`NtCreateEvent`/`NtOpenEvent`/`NtCreateSection`/`NtOpenSection` for an API-channel name, so nothing
in Wine rejects it — the code path simply stops before that point. What *does* fail nearby, from the
same run (`+file`), is the surrounding Windows kernel/device surface:

```
50x warn CreateFileW L"\\\\.\\pipe\\SafeNet-SentinelPIPE-124-356"   -> c0000034 (SafeNet/Sentinel LDK runtime pipe)
31x warn L"...\\SafeNet Sentinel\\Sentinel LDK\\installed"          -> c0000034
24x warn CreateFileW L"\\\\.\\Nsi"                                  -> c0000034
9x  warn CreateFileW L"\\\\.\\PhysicalDrive0..15"                   -> c0000034
```

plus the seven kernel-driver `.sys` probes that all return `c0000034` (first block of this section).

### 12.2 Verdict for the bounded question

**`Global\CmApiCallIn` is gated by (b) — the kernel driver / Windows kernel-surface not existing —
not by a patchable Wine advapi32/security gap.**

Evidence, in the requested form:

| | |
|---|---|
| failing API | **none** — the service never calls any Create/Open for the API-channel name (proven by the `+sync,+virtual` name trace above); the candidate `ConvertStringSecurityDescriptorToSecurityDescriptor` **succeeds** for every SDDL form, including `S:(ML;;NW;;;LW)` |
| Wine implementation | n/a: no Wine API is on the failing path. Wine's named objects and SDDL parser both work (service creates 13+ `Global\Cm*Event` objects; probe creates objects with the label SD) |
| patch | **none available** — the gate is the absent Wibu kernel driver (`vusb.sys`/`vusbbus.sys`/`wibuvd.sys`/`CmHt`) and Windows kernel device surface (`\\.\PhysicalDriveN`, `\\.\Nsi`), none of which Wine can supply |

**This is the documented architectural blocker. Local CodeMeter licensing on Wine is not
achievable; stop chasing it and use the network/HASP path (§7.3, §8c) or a real Windows host.**
