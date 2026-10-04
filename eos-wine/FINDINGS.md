# ETC Eos Family v3.3.10.28 on Wine — findings

One milestone per result, with the measured evidence and the command that produced it.

## M1 — The download is a zip holding one NSIS installer, and the product is a WiX x64 MSI
`ETC_EosFamily_v3.3.10.28.zip` (1 078 561 863 B) holds exactly one member,
`ETC_EosFamily_v3.3.10.28.exe` (1 131 886 512 B). `file` → `PE32 executable for MS Windows 4.00 (GUI),
Intel i386, Nullsoft Installer self-extracting archive, 5 sections`; version resource
`CompanyName: Electronic Theatre Controls, Inc.`, `ProductName: Eos Family v3 Software`,
`FileVersion/ProductVersion 3.3.10.28`, `FileDescription: Eos Family Installation Suite`.

Expanded to `/run/media/asdf/Windows/eos-media` (NTFS — `/` is the tight filesystem). NSIS payload is
51 files; the ones that matter:

| member | size | note |
|---|---|---|
| `$PLUGINSDIR/ETC_EosFamily_v3.3.10.28.msi` | 306 085 888 | **the product** |
| `$PLUGINSDIR/ETC_Augment3d_v1.4.10.3.msi` | 199 970 816 | the 3D visualiser (separate product) |
| `$PLUGINSDIR/Manual.7z` | 353 795 630 | documentation |
| `$PLUGINSDIR/haspdinst.exe` | 22 079 144 | **Sentinel HASP** driver/runtime installer |
| `$PLUGINSDIR/VC_redist.{x64,x86}.exe` | 25 640 112 / 13 957 544 | MSVC runtime |
| `$PLUGINSDIR/ETC_WES7_*.exe`, FTDI, USB/MIDI/Arduino, `certificates/*.cer` | — | console-hardware / console-OS bits, not needed for the desktop app |

So the desktop product installs from a plain MSI — the mastercam project's approach (install the MSI
directly under Wine, prerequisites separately) applies unchanged.

## M2 — The product MSI: WiX 3.11, x64-only, Qt5 application
`msiinfo suminfo` → `Application: Windows Installer XML Toolset (3.11.1.2318)`,
`Template: x64;1033`, `Subject: Eos Application v3`, `Author: Electronic Theatre Controls, Inc.`.
`msiinfo export … Property` → `ProductName=Eos Application v3`,
`ProductCode={F4DF9106-8D55-4CFB-83D4-A6C992E1D1BB}`, `UpgradeCode={228C29DA-1ACC-4D81-A2F2-1EEC804C1B22}`,
`ProductVersion=3.3.10.28`, `ALLUSERS=1`, `ARPNOMODIFY=1`.

`msiinfo export … Feature` → three features:
`Shell` ("Eos Shell", level 0), `ShellOffline` ("Eos Shell Offline", level 0),
`DefaultFeature` ("Eos Application" / "Eos Family", level 1).

`msiinfo export … Directory` → install root `D_ETC_ROOT` = **`C:\Program Files\Eos`**
(`D_EOS_ROOT_DIR`), plus `ETC_Launch` (the shell), `nodesbin`, and the classic Qt plugin subtrees:
`platforms`, `imageformats`, `mediaservice`, `playlistformats`, `printsupport`, `iconengines`,
`bearer`, `audio`, `web`, `styles`, `Symbols`, and numbered UI resource dirs
(`001_Effects`, `002_Eos_Tabs`, `003_Workspaces`, `004_Tab_Menu`, `005_Augment3d`, … `015_Miscellaneous`),
plus `Docs` and `FixtureData` under common app data.

`msiinfo export … File` → the executables: **`Eos.exe`** (the application), `setup.exe`,
`ETC_Launch.exe`, `ETC_LaunchOffline.exe`, `7za.exe`, `gmaconv.exe`, and a set of console-hardware
tools (`ConsoleHardwareTester.exe`, `ConsoleUpgrader.exe`, `TouchTest.exe`, `MM_ConsoleTester.exe`,
`IODownloader.exe`, `ETCDoctor.exe`, `GioFan.exe`) that this project does not need.
Libraries: **Qt5** — `Qt5Core/Gui/Widgets/Qml/Network/Multimedia/Svg/WinExtras/WebSockets/WebChannel/
PrintSupport/Concurrent`, `qtaudio_windows`/`qtaudio_wasapi`, `qtmedia_audioengine`,
`qtmultimedia_m3u`, `qtga`/`qtiff`, plus `avcodec-60.dll` (ffmpeg). No `Qt5WebEngineCore` was found, so
no embedded Chromium — a big simplification versus the AutoCAD/Mastercam cases.

Licensing: Sentinel **HASP** (`haspdinst.exe`), consistent with the owner's note that the product
supports a licence key but still works without one (the offline editor).

## M3 — Patch base
`wine-11.18/` carries `patches/series/0001..0019` (AutoCAD-on-Wine 14 + Power BI-on-Wine 5) **and**
`patches/local/0100-msi-class-registry-view.patch` + `0101-services-service-logon-token.patch` — the
two Wine bug fixes written and verified in the `mastercam-wine` project (MSI per-component registry
view; service-logon token for SCM-started services). All 21 apply cleanly
(`tools/apply_patches.sh wine-11.18`). `wine-install/` is the identical built Wine copied from that
project (`wine --version` → `wine-11.18`); a fresh build of this project's own tree is deferred until a
patch specific to Eos is needed.

## M4 — The MSI installs cleanly and the app boots to its splash window under Wine
`tools/mkprefix.sh --fresh --stage all` with `wine-install` (19-patch series + `0100` + `0101`):
core fonts, VC++ 2022 x64 **and** x86 both `rc=0`, and the product MSI

```
wine msiexec /i <msi> /qn /norestart /L*v C:\eos_msi.log      -> rc=0, "INSTALL. Return value 1"
```

installs to **`C:\Program Files\ETC\EosFamily\v3\Eos\`** (297 MB under `Program Files\ETC`), features
`DefaultFeature` + `ShellOffline`, and registers firewall rules for `Eos.exe`
(`CustomActionData = 1?Eos (TCP-in)?…Eos.exe…1?Eos (UDP-in)?…Eos.exe…`). Main binary
`Eos.exe` = `PE32+ executable for MS Windows 6.01 (GUI), x86-64`, 41 645 024 B. No MSI failure of any
kind — no sign of the `ISLockPermissions`/class-view class of problem.

First run (`tools/run_eos.sh eos1 --secs 120 --iv 15`):

- the process stays alive for the whole 120 s (`alive=2`) and **creates a real named window
  `0x1200003 "Eos"` (688x383)**;
- OCR of the screen reads exactly **`Version 3.3.10 Build 28`** — i.e. the Eos splash/version screen
  is up. So the Qt5 UI starts and paints.
- Then it stalls: repeated `err:sync:RtlpWaitForCriticalSection section … wait timed out in thread
  0250, blocked by 01e8, retrying (60 sec)` across many threads, with the main thread `01e8` itself
  blocked by another thread — a deadlock/livelock signature. The main editor window never appears.
- Benign/`fixme` noise seen at startup: `RegisterPowerSettingNotification` (stub),
  `EnableNonClientDpiScaling` (stub), `GetTempPath2W` (semi-stub), `PowerCreateRequest`/
  `PowerSetRequest` (stubs), `winsock:WSAIoctl SIO_UDP_CONNRESET` (stub), font charset
  `fixme`s, `NtQuerySystemInformation SYSTEM_PERFORMANCE_INFORMATION`.
- Install root for the harness is `Program Files/ETC/EosFamily/v3/Eos` (fixed in `tools/run_eos.sh`);
  the window-title grep must not match the `"eos.exe"` *class* name (it did at first).

## M5 — The editor OPENS under Wine
`tools/run_eos.sh eos_clean --secs 300 --iv 15` (SLP component installed and `slpd` RUNNING):

- the process stays alive the whole 300 s (`alive=2`);
- the X window tree contains **`0x1a00006 "Eos : 1" 1600x1000+0+0`** — the main editor window —
  present from t≈105 s to the end, alongside the 688x383 `"Eos"` splash and a 100x30 `"Eos"` child;
- the app's own log `%LOCALAPPDATA%\ETC\EosFamily\v3\OnyxConsole.log` walks the full start-up:

```
14:05:43.191 Console    Registering for network changes...
14:06:09.574 CreateComponent Created component handle=ffffffff cid=EF4DC218-7071-4C6E-98DF-40B730C5C7CF
14:06:09.870 OnyxConsole ACN started
14:06:17.613 OnyxConsole recovered from hang after 47.90 s
14:06:18.291 OnyxConsole TickDistributed: EP Connected/Disconnected/Changed
```

So the Eos console/editor reaches its running state under Wine. Windows does the same in ~10 s of
"hang" (~18 s to the editor); Wine takes ~48–58 s.

## M6 — The extra ~44 s is the SLP path, and it is an *environment* fix, not a Wine patch
Windows installs **ETC SLP 3.0.0.22** (`C:\Windows\SysWOW64\slpd.exe` + `C:\Windows\slp.conf`, service
`slpd` Running/Automatic); the product MSI alone does not, so our MSI-only prefix lacked it. Installing
it (`$PLUGINSDIR/ETC_SLP_Install.exe /S`) puts the files and the service in the prefix and `sc start
slpd` reaches **STATE 4 RUNNING** — but `slpd` still cannot register, and `NetworkFeedback.log` keeps
printing `Discovery InternalRegister: SLPReg() failed with result -19`
(`SLP_NETWORK_TIMED_OUT`) per interface. Agent `EosApiDiff` found the reason:

```
trace:winsock:bind socket 0x70, addr { AF_INET, address 127.0.0.1, port 427 }, len 16
trace:winsock:bind failed, status 0xc0000022        <- STATUS_ACCESS_DENIED -> WSAEACCES
```
Port **427** (and 68) are in the **privileged** range on this host
(`net.ipv4.ip_unprivileged_port_start = 1024`, uid 1000), so Linux refuses the bind and Wine faithfully
reports `WSAEACCES`. **Windows has no privileged-port concept**, so `slpd` binds 427 fine there; `Eos.exe`
itself only ever *connects* to `127.0.0.1:427`. This is not a Wine source bug — the fix is to lift the
host restriction for the Wine process:

```sh
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=0        # host-wide, simplest
# or, narrower:
sudo setcap 'cap_net_bind_service=+ep' \
  wine-install/bin/wine wine-install/bin/wine64 wine-install/bin/wine64-preloader wine-install/bin/wineserver
```
Both need root; this account has no passwordless sudo, so the experiment is documented rather than
applied. With it, the expectation is that `SLPReg()` stops failing and the stall falls toward Windows'
~10 s.

Other measured (smaller) divergences, from `docs/API_DIFF.md`:
- `iphlpapi!NotifyIpInterfaceChange` was a **stub** and `NotifyUnicastIpAddressChange` a semi-stub →
  fixed by our `patches/local/0102-iphlpapi-notify-interface-changes.patch`.
- `nsiproxy.sys/ndis.c` hard-codes `rcv_speed = xmit_speed = 1000000` for every Linux interface →
  the app logs `Link Speed: 0 bps -> 1 Mbps` for all five NICs.
- `ws2_32` `WSAIoctl(SIO_UDP_CONNRESET)` is a no-op stub (12×); sACN's `setsockopt(IPPROTO_IP, 0x29, …)`
  returns `WSAEINVAL`.
- The diff found **no Win32 call that fails on Wine but succeeds on Windows** in the start-up window —
  the divergence is latency, plus the stubs above.

## M7 — With the SLP fix, Wine matches Windows (and the editor UI renders)
Applied: ETC SLP installed in the prefix, `slpd` started, and
`pkexec sysctl -w net.ipv4.ip_unprivileged_port_start=0` (now `0`; `bind(127.0.0.1:427)` succeeds).
Clean measurement, `tools/run_eos.sh eos_final --secs 150 --iv 15`:

| measure | before | after | Windows |
|---|---|---|---|
| `NetworkFeedback.log` `SLPReg() failed` lines | many (−19 per interface) | **0** (file not even created) | 0 |
| `CreateComponent … handle=` | `ffffffff` | **`80000000`** | `80000000` |
| `recovered from hang after` | 47.9–58 s | **18.67 s** | 10.10 s |
| editor window | appears ~48–105 s | **`"Eos : 1"` 1600x1000 up from t=30 s** | ~18 s |
| process | alive | alive the whole 150 s | — |

`OnyxConsole.log`:
```
14:19:18.293 Console    Registering for network changes...
14:19:18.322 CreateComponent Created component handle=80000000 cid=EF4DC218-…
14:19:18.324 OnyxConsole ACN started
14:19:18.335 CreateComponent Created component handle=80000001 cid=43B7EF9E-…
14:19:24.562 OnyxConsole recovered from hang after 18.67 s
```
`slpd.log` now shows a healthy daemon:
`Multicast (IPv4) socket on 0.0.0.0 ready … Unicast socket on 0.0.0.0 ready …
Startup complete entering main run loop ...`.

**The editor UI renders.** Captured from window `"Eos : 1"` (`logs/runs/eos_final/win_90s.png`,
copied to `evidence/eos_editor_wine.png`), OCR of the pixels:

```
(untitled)                        …  2:20:35PM
Tracking
Cue Up Down Focus Color Beam Dur … Link Loop Curve Rate Label FX
… ‘untitled’
LIVE: _   | User 1| Offline | Alert
Preview   Fader Offset
```
— i.e. the Eos command line, the cue list, the Live/Offline status bar and `User 1`, the same surface the
Windows reference shows. `slpd`/`slp.conf`/`slptool.exe` and `Eos.exe` itself are the only pieces needed;
**no licence key is involved anywhere** (matching Windows, where the shell offers *Offline* mode and the
editor runs unlicensed).

## M8 — Final verification with the patched build (Windows parity)
`patches/local/0102-iphlpapi-notify-interface-changes.patch` applied to the build tree, `iphlpapi.dll`
rebuilt (1 009 024 B) and installed, then `tools/run_eos.sh eos_0102 --secs 120 --iv 15`:

| check | result |
|---|---|
| `fixme:iphlpapi:NotifyIpInterfaceChange … stub` / `…NotifyUnicastIpAddressChange … semi-stub` | **0 occurrences** (were present before the patch); no `iphlpapi` lines at all now — the notifications are delivered silently |
| `CreateComponent … handle=` | **`80000000`** = the Windows value (`80000001` for the second component) |
| `recovered from hang after` | **16.40 s** (Windows 10.10 s; was 47.9–58 s) |
| `SLPReg() failed` | **0** |
| editor window | **`"Eos : 1" 1600x1000` up from t=30 s** and stable for the whole 120 s |
| process | alive (`alive=2`) throughout |

**Surface parity.** OCR of the Windows reference (`evidence/vm_eos_editor_01.png`) and of Wine
(`evidence/eos_editor_wine.png`, `.ocr.txt`) reads the same editor: `(untitled)` show tab, `Tracking`,
the cue list header `Cue … Loop Curve Rate`, the status line `LIVE: | User 1 | Offline`, and
`Preview / Fader / Offset` — both windows 1600x1000.

**Status: the goal is met.** ETC Eos Family v3.3.10.28 installs and opens its editor under this patched
Wine 11.18, unlicensed, matching the Windows reference's surface and — after the SLP setup fix and the
`0102` patch — its start-up behaviour to within ~6 s.
