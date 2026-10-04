# Can Mastercam 2027 be licensed under Wine? — measured verdict

**Short answer: no, not locally.** Mastercam 2027 *starts* under the patched Wine in this project (the
launcher loads, `WIBUCM64.dll` resolves), but it **cannot be licensed**, because every local licence
mode needs kernel-level surfaces that Wine does not provide. This is architectural, not a missing
API stub: no Wine patch closes it. The only theoretically Wine-hostable path is a **network** licence
server on real Windows, which cannot be tested here because no licence, dongle or licence server
exists in this environment.

Evidence below is from agent `CodeMeterProbe`; full detail in `docs/CODEMETER_ON_WINE.md`
(§11 = installer bug A, §12/12.1/12.2 = licensing blocker B).

## What Mastercam's licensing needs

`MastercamLauncher.exe` **statically imports `WIBUCM64.dll`** (CodeMeter). The payload carries
`CodeMeterRuntime64.msi` (Runtime Kit 8.40a) and `MastercamLicensingSetup.exe`, and the licence can be
one of HASP / NetHASP / CodeMeter software container (`AdministratorGuide.pdf`). All three ultimately
need the CodeMeter or HASP **kernel driver** plus the device surfaces the client enumerates.

## What works under Wine (measured)

| step | result |
|---|---|
| `WIBUCM64.dll` load | **works** — a 64-bit PE importing it loads it (`trace:loaddll Loaded L"C:\WIBUCM64.dll"`, exit 0). With the DLL absent the launcher dies at load with `c0000135`. |
| CodeMeter Runtime **install** | works only with a workaround: a pre-created running stand-in service named `CmWebAdmin.exe` makes `msiexec /qn` exit 0 (118 MB installed). Without it, exit 91 — see "installer bug" below. |
| CodeMeter **service** | installs and starts: `sc query CodeMeter.exe` = **STATE 4 RUNNING**, `TCP 127.0.0.1:22350` listening, 13+ `Global\Cm*Event` notification objects created. |
| `MastercamLicensingSetup.exe` | installs cleanly (`/s /v"/qn"` → exit 0). Its Aladdin/Sentinel manager **`hasplms` runs and LISTENs on TCP+UDP 1947** — Wine *can host the network licence manager*. |
| no-licence start | **the app runs**: after the English Language Pack fix (M12/M13 in `FINDINGS.md`) `Mastercam.exe` runs 240 s with zero exceptions and shows real dialogs (`"Warning"`, `"Exiting..."` = `No Valid Mastercam License found`); `MastercamLauncher.exe` shows `No license found`. Both then exit; **no main window is created** because the licence gate fires first. |

## What is blocked, and the exact evidence

The CodeMeter **client** only reaches the service through `Global\CmApiCallIn`, and that object is
**never created**. A name-level trace over a full service start shows the service creates *only* its
notification events and **never issues any `CmApi*` create/open at all** (`WINEDEBUG=+sync,+virtual`):

- created: `Global\CmBoxAddedEvent`, `CmBoxEnabled/Disabled/Remove/ReplaceEvent`,
  `CmEntryAltered/ModifiedEvent`, `CmNetworkLost/ReplacedEvent`, `CmServerTerminatedEvent`,
  `CmThresholdUC/ExpDateEvent`;
- **zero** `CmApi*` names, **zero** named `NtCreateSection/NtOpenSection`.

So there is **no failing API to patch** — the code path is never reached. What *does* fail in the same
run is only the kernel/device surface:

```
7×  kernel-driver probes (vusb.sys, vusbbus.sys, wibuvd.sys, b70bus.sys, mcamvusb.sys,
    multikey.sys, Znet_hasp64.sys)              -> c0000034
50× CreateFileW \\.\pipe\SafeNet-SentinelPIPE-124-356   -> c0000034
31× ...\SafeNet Sentinel\Sentinel LDK\installed  missing
24× \\.\Nsi                                     -> c0000034
 9× \\.\PhysicalDrive0..15                      -> c0000034
```
The CodeMeter service also probes those seven `.sys` files at start, finds none, and never opens a
device — so it never publishes the API channel. The runtime's driver is not shipped as a file at all
(it is embedded in `CodeMeter.exe`); `aksusbd`/`multikey.sys` (HASP USB) are likewise absent.

**The last non-kernel lead was closed by measurement, not inference.** CodeMeter also sets a
low-integrity mandatory label (`S:(ML;;NW;;;LW)`) on its objects; a Wine `advapi32` gap there could
have been the real cause. A probe (`state/exp/CodeMeterProbe/sdprobe.c`) shows Wine converts
`D:(A;;GA;;;WD)`, `S:(ML;;NW;;;LW)` and the combined form with `err=0` and creates events/file
mappings with each — **there is no Wine SDDL/security gap on that path.**

## Conclusion against the owner's decision rule

> If the app cannot run, or can run but cannot be licensed because Wine lacks kernel-level APIs,
> then say so, document it, and stop.

- **It runs:** the product MSI installs (with patch `0100`), the prerequisites install, the app starts
  and runs indefinitely without crashing (240 s measured, zero exceptions), and it creates real,
  clickable windows. It then takes its hard no-licence exit path: `Warning` + `Exiting... No Valid
  Mastercam License found` (launcher: `No license found`) and exits — **no main window**.
- **Windows goes one step further** with the same absent licence: it draws its main window and the
  `Checking license...` splash and then offers the interactive `No Mastercam license found.  Do you
  have an activation code?` prompt. The difference is precisely that Windows' licensing stack is
  intact (its CodeMeter/HASP drivers load); Wine's cannot be.
- **It cannot be licensed locally:** every local mode (dongle, CodeMeter software container) depends
  on a Wibu/HASP kernel driver and device surface that Wine cannot provide. No patch is available
  because no Wine call is on the failing path.
- **The one untested path** is a **network licence**: Wine even runs `hasplms` (TCP+UDP 1947), and the
  Mastercam/NetHASP client side is plain TCP/UDP via `nethasp.ini` (`NH_TCPIP`/`NH_SERVER_ADDR`), so a
  licence server on a real Windows host *might* license a Wine client. This cannot be verified here:
  no dongle, no licence and no licence server exist in this environment.

**Therefore: documented as blocked-by-design, and stopped** — with the two genuine Wine bugs found on
the way fixed and shipped as patches (`patches/local/0100-*`, `patches/local/0101-*`).

## Reproduce
```sh
source env.sh
tools/build_wine.sh --jobs 8            # pristine 11.18 + patches/series + patches/local
tools/mkprefix.sh --stage fonts         # then .NET 10 desktop + dotnet48 + VC++ + CodeMeter
wine msiexec /i "$MCW_MEDIA/mastercam/Mastercam_Installer.msi" \
     TRANSFORMS="$MCW_MEDIA/mastercam/1033.mst" \
     INSTALLDIR='C:\Program Files\Mastercam 2027' REBOOT=ReallySuppress /qn /norestart /L*v C:\mc.log
wine "C:\Program Files\Mastercam 2027\MastercamLauncher.exe"   # -> "No Mastercam license found."
```
Licensing probes kept under `state/exp/CodeMeterProbe/` (`tokprobe`, `sessprobe`, `sdprobe`, `cmprobe`,
`cmstub`, `idt/`).
