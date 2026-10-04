# Bundled components of Resolume Arena 7.28 — load mode, kill switches, Windows needs

Research slice: `installer/media_x/app/` + `Arena.exe` strings. Read-only.
Tools used: `strings -a` / `strings -a -el` (UTF-16LE strings matter — most Windows API
names/paths in this binary are wide), `objdump -p`, `file`, `grep -a`.

> Proof-of-method note: `strings -a` alone misses the BugSplat/Wire loader names because
> they are UTF-16LE. E.g. `strings -a Arena.exe | grep -i bugsp` returns only RTTI +
> `DISABLE_BUGSPLAT`, but `strings -a -el Arena.exe` returns the real monitor command line
> and `BugSplatWer.dll`. Always run both.

## 0. Arena.exe import table (what the PE loader resolves before `main`)

```
$ objdump -p Arena.exe | grep 'DLL Name:' | sort -u
```
Relevant entries (full list in artifact, app/system DLLs omitted):

```
	DLL Name: Artnet.dll
	DLL Name: Processing.NDI.Lib.x64.dll
	DLL Name: WinSparkle.dll
	DLL Name: avcodec-61.dll
	DLL Name: avformat-61.dll
	DLL Name: avutil-59.dll
	DLL Name: swscale-8.dll
	DLL Name: libltc.dll
	DLL Name: d3d11.dll
	DLL Name: dxgi.dll
	DLL Name: MF.dll
	DLL Name: MFPlat.DLL
```

There is **no delay-import directory**:
```
$ objdump -p Arena.exe | grep -A1 'Delay Import Directory'
Entry d 0000000000000000 00000000 Delay Import Directory   <- size 0 == none
```
So everything in the import table is resolved by the Windows loader at process start.
Missing = Arena.exe fails to start (before any UI).

Confirmed imported symbols (excerpts from `objdump -p Arena.exe`):

```
	02052438  <none>  0012  NDIlib_initialize
	02052480  <none>  0003  NDIlib_find_create_v2
	02052400  <none>  0016  NDIlib_recv_capture_v2
	02052448  <none>  005b  NDIlib_send_send_video_async_v2
	02052d58  <none>  0008  win_sparkle_init
	02052d48  <none>  000c  win_sparkle_set_automatic_check_for_updates
	02052d10  <none>  000a  win_sparkle_set_app_details
	020510f0  <none>  0009  artnet_new
	02051120  <none>  002f  artnet_start
	020536f0  <none>  0000  ltc_decoder_create
	020536f8  <none>  0005  ltc_decoder_read
	02051918  <none>  0101  CreateProcessW
	020513b8  <none>  0638  WerRegisterRuntimeExceptionModule
```

Note the On-disk/import **case mismatch for Artnet**: import name `Artnet.dll`, file on disk
is `artnet.dll`. Windows is case-insensitive; Wine's PE loader must also match
case-insensitively for `Artnet.dll` → `artnet.dll`. Flag for the Wine tree.

## 1. Per-component verdicts

| Component | Verdict | Loaded when |
|---|---|---|
| `Processing.NDI.Lib.x64.dll` | **static import** (Arena.exe) | process start, unconditionally |
| `WinSparkle.dll` | **static import** (Arena.exe) | process start, unconditionally |
| `artnet.dll` (import name `Artnet.dll`) | **static import** (Arena.exe) | process start, unconditionally |
| `libltc.dll` | **static import** (Arena.exe) | process start, unconditionally |
| `WireLib.dll` | **dynamic load** (Arena, `LoadLibraryW("WireLib.dll")`) | at Wire/plugins init, optional |
| `WireNodes.dll` | **never referenced by Arena**; static import of `WireLib.dll` | when WireLib loads |
| `onnxruntime.dll` | **never referenced by Arena**; dynamic load inside `WireLib.dll` | when an ONNX Wire node runs |
| `DirectML.dll` | **never referenced by Arena**; dynamic load inside `WireLib.dll` | when onnxruntime picks the DML EP |
| `BugSplatWer.dll` | **dynamic** (Arena, registered via `WerRegisterRuntimeExceptionModule`) | on BugSplat init |
| `BugSplatMonitor.exe` | **dynamic spawn** (Arena, `CreateProcessW`) | on BugSplat crash/init |
| `BugSplatRc.dll` | **never referenced by Arena**; resource DLL loaded by `BugSplatMonitor.exe` | when monitor shows UI |
| `plugins/afx/*.dll` | **dynamic plugin load** from `plugins/afx` | at plugin scan |
| `plugins/wire/*.wired` | **dynamic data load** from `plugins/wire` | at plugin scan |

### Evidence

`WireLib.dll`/`WireNodes.dll`/`onnxruntime.dll`/`DirectML.dll` absent from Arena import table:

```
$ strings -a Arena.exe | grep -c WireNodes
0
$ strings -a Arena.exe | grep -ciE 'directml|onnx'
0
```

`WireLib.dll` is named in Arena (dynamic loader path):
```
$ strings -a Arena.exe | grep -n -F 'WireLib.dll'
591169:WireLib.dll
```
and Arena has graceful "not found" messages, i.e. it is optional at runtime:
```
$ strings -a Arena.exe | sed -n '591166,591176p'
Resolume Wire 
Wire.exe
WireLib.dll
plugins/wire
Shipped wire patches not found in location: 
...
User compiled patches not found in location: 
Wire executable not found in location: 
Libwire not found in location: 
```

`WireNodes.dll` **is** a static import of `WireLib.dll`:
```
$ objdump -p WireLib.dll | grep 'DLL Name:'
	DLL Name: WireNodes.dll
	...
```

`WireLib.dll` dynamically loads onnxruntime/DirectML — both names present as strings, neither in
its import table, and it imports the loader:
```
$ objdump -p WireLib.dll | grep 'DLL Name:' | grep -iE 'onnx|directml'   # (no output)
$ strings -a WireLib.dll | grep -aoE '[A-Za-z0-9_.-]+\.dll' | sort -u | grep -iE 'onnx|directml'
DirectML.dll
onnxruntime.dll
$ objdump -p WireLib.dll | grep -aiE 'LoadLibrary|GetProcAddress'
	01018338  <none>  03f6  LoadLibraryW
	010183c0  <none>  03f3  LoadLibraryA
	01018580  <none>  03f5  LoadLibraryExW
	01018588  <none>  02dc  GetProcAddress
```

BugSplat is present but **all wide strings**, hence invisible to plain `strings`:
```
$ strings -a -el Arena.exe | grep -aiE 'bugsplat|wer'
"%s\BugSplatMonitor.exe" -m %lu
BugSplat Initialization
BugSplat SetupExceptionSystem
BugSplat StartMonitorProcess %s
Failed to create BugSplat monitor process
Global\BugSplatOutOfProcSharedMemory
Global\BugSplatOutOfProcStartExceptionEvent
Global\BugSplatOutOfProcFinishedExceptionEvent
BugSplatWer.dll
BugSplat.log
BugSplatCrashData.json
BugSplat\
```
`BugSplatRc.dll` is only referenced by the monitor, not by Arena:
```
$ strings -a -el BugSplatMonitor.exe | grep -aiE 'bugsplatrc|resource dll'
BugSplatRc.dll
BugSplatMonitor: BugSplatRc resource DLL not found
$ grep -alr BugSplatRc app/        # only BugSplatMonitor.exe matches
```
BUGSPLATRc.dll itself is **resource-only** (no import/export):
```
$ objdump -p BugSplatRc.dll | grep -E 'Entry 0|Entry 1'
Entry 0 ... Export Directory [.edata ...]      <- empty
Entry 1 ... Import Directory [parts of .idata] <- empty
Entry 2 ... Resource Directory [.rsrc]
```

Plugin dirs named by Arena:
```
$ strings -a Arena.exe | grep -nE 'plugins/(afx|vfx|wire)'
584474:plugins/vfx
584475:plugins/afx
591170:plugins/wire
```

## 2. Concrete neutralisation recipes

### Static imports (cannot be removed without a stub)
Because NDI / WinSparkle / Artnet / libltc are **static** imports with **no delay-load**, you
cannot "disable" them with a setting or by deleting the file — deletion makes Arena.exe fail at
load. Options:
1. Keep the real DLL. (NDI/WinSparkle/artnet/libltc are self-contained and load under Wine far
   more easily than DirectML.)
2. Better for Wine bring-up: replace the DLL with a **stub DLL exporting exactly the imported
   names** above (`NDIlib_*`, `win_sparkle_*`, `artnet_*`, `ltc_*`), so Arena starts and the
   feature is inert. The exact export list is available from `objdump -p Arena.exe`
   (import names per DLL).
3. A Wine **DLL override** (`WINEDLLOVERRIDES=...`) only selects native vs builtin; it does not
   make the import disappear, so it does not help bypass a required static import.

- **NDI** — no disable key/preference found (searched: `strings -a(-el) Arena.exe | grep -i ndi`
  → only class RTTI `NDIOutputDevice`, `NDIVideoSource`, etc., plus runtime errors
  `Cannot run NDI.` / `Cannot run NDI because the CPU is not sufficient`). Runtime is already
  defensive if `NDIlib_initialize` fails, but the DLL must load. Neutralise = stub DLL or
  simply don't create NDI inputs/outputs.
- **WinSparkle** — static; must exist. Disable the *behaviour* without touching the DLL:
  WinSparkle reads its state from the registry under a `\WinSparkle` subkey
  (`strings -a -el Arena.exe | grep -i WinSparkle` → `\WinSparkle`), and exposes
  `win_sparkle_set_automatic_check_for_updates` / `win_sparkle_get_automatic_check_for_updates`
  (both imported). Arena's own UI string is `CheckForUpdates` / `checkForUpdatesLabel`.
  Practical: clear/neutralise the appcast URL (`win_sparkle_set_appcast_url` is imported; URL
  strings `https://resolume.com/update/`, `https://resolume.com/update/developmentSparkle.php`)
  or just don't connect to network. A stub DLL exporting `win_sparkle_*` is the hard disable.
- **artnet** — static; no disable key found. It is only *activated* when a DMX/Art-Net
  input/output node exists (`artnet_new`/`artnet_start` called from Arena's DMX layer). Stub or
  ignore. Needs UDP 6454.
- **libltc** — static; pure CPU LTC timecode parser. Needs only kernel32+CRT. Stub or ignore.

### Dynamic / optional components (safe to remove or rename)

- **WireLib.dll / WireNodes.dll / plugins/wire / ai-models** — rename or remove
  `WireLib.dll`. Arena prints `Libwire not found in location:` and continues (the Wire effect
  types simply won't appear). `WireNodes.dll` can never be removed independently: it is a hard
  static import of WireLib.dll, so removing it while keeping WireLib makes WireLib fail to load
  (Arena still continues via its "not found" path). `plugins/wire/*.wired` are separate data
  files loaded from `plugins/wire`; deleting that dir yields
  `Shipped wire patches not found in location:`. `ai-models/` (666 MB: depth-estimation 587 MB,
  human-segmentation 79 MB) is only needed by the ONNX Wire nodes
  (`WireNodes.dll` strings contain `depth-estimation/onnx/*.onnx`,
  `human-segmentation/onnx/*.onnx`) and can be deleted with no startup impact.
- **onnxruntime.dll + DirectML.dll** — both are loaded lazily by WireLib for ONNX AI effects.
  Rename/remove either and WireLib degrades gracefully; observed message in WireLib.dll:
  `ONNX-backed AI effects render as a passthrough until Arena is restarted.` and
  `the node renders as a passthrough`. This is the cheapest way to kill the DirectML/D3D12
  path under Wine (DirectML.dll imports `d3d12.dll` and
  `api-ms-win-appmodel-runtime-l1-1-0.dll`).
- **plugins/afx/*.dll** (6 JUCE audio-effect DLLs: Bitcrusher, Distortion, EQ-3, Flanger,
  HighPass, LowPass) — loaded from `plugins/afx`. Delete the directory to drop them. Additionally
  Arena has a documented-ish CLI switch `--BypassPlugins` (and `--UnbypassPlugins`) found in
  strings; [INFERENCE] it bypasses effect-plugin scanning at startup — the exact scope was not
  measured, but it is the only plugin on/off switch present. Same string set includes
  `--crash-on-gl-error`, `--debug-gl`, `--nosplash`, `--runMemoryLeakTest`.
- **BugSplat (BugSplatRc.dll / BugSplatWer.dll / BugSplatMonitor.exe)** — fully dynamic, so all
  three can be deleted without breaking Arena start. There is an explicit kill switch string in
  Arena.exe: **`DISABLE_BUGSPLAT`** (ANSI; `strings -a Arena.exe | grep DISABLE_BUGSPLAT`).
  [INFERENCE] it is the BugSplat SDK's environment variable checked before initialising the
  reporter; set `DISABLE_BUGSPLAT=1` in the process environment. Deleting the three files is the
  belt-and-braces option; BugSplatMonitor.exe self-reports
  `BugSplatMonitor: BugSplatRc resource DLL not found` if only the resource DLL is removed.

## 3. Windows API surface each component needs (for Wine work)

- **Processing.NDI.Lib.x64.dll** (imports, `objdump -p`): `WS2_32.dll`, `MSWSOCK.dll`,
  `IPHLPAPI.DLL`, `bcrypt.dll`, `d3d11.dll`, `dxgi.dll`, `ole32.dll`, `OLEAUT32.dll`,
  `CRYPT32.dll`, `WINMM.dll`, `ntdll.dll`. Network filtering/discovery; also names optional
  plugin DLLs (`Processing.NDI.Plugins.IPCam.x64.dll`, `avcodec-ndi-61.dll`, `nvcuda.dll`,
  `nvcuvid.dll`, `evr.dll`) that are absent but only loaded on demand.
  Arena additionally references the wide string `dnssd.dll` (Bonjour); `tmp/Bonjour64.msi`
  ships as a prerequisite → [INFERENCE] NDI discovery uses Bonjour/mDNS.
- **WinSparkle.dll**: `WININET.dll` (HTTP appcast), `CRYPT32.dll`/`WINTRUST` (DSA/EdDSA
  signature verification of the update), `RPCRT4.dll`, `COMCTL32.dll`, `UxTheme.dll`,
  registry via `ADVAPI32`. Update state lives under `\WinSparkle` (wide string in Arena).
- **BugSplat**: Arena needs `WerRegisterRuntimeExceptionModule` (kernel32) + the WER service and
  `BugSplatWer.dll` (an out-of-process WER exception module exporting
  `OutOfProcessExceptionEventCallback`, `OutOfProcessExceptionEventDebuggerLaunchCallback`,
  `OutOfProcessExceptionEventSignatureCallback` — `objdump -p BugSplatWer.dll`). Arena spawns
  `"%s\BugSplatMonitor.exe" -m %lu` via `CreateProcessW` and coordinates over named objects
  `Global\BugSplatOutOfProc*Event` + `Global\BugSplatOutOfProcSharedMemory`. Monitor needs
  `WINHTTP.dll` (uploads to `.bugsplat.com/api/getCrashUploadUrl` /
  `commitS3CrashUpload`), `dbghelp.dll` (`MiniDumpWriteDump`), `OpenProcess`/
  `OpenProcessToken` (may need debug privileges), and writes `BugSplatCrash.zip` /
  `BugSplatCrashData.json` / `\wer_crash.dmp`.
- **onnxruntime.dll**: `ADVAPI32`, `SETUPAPI`, `dbghelp`, MSVC/UCRT; no network.
  **DirectML.dll**: `d3d12.dll` + `api-ms-win-appmodel-runtime-l1-1-0.dll` + many
  `api-ms-win-core-*` — the hard part under Wine; DirectML is a D3D12 compute provider.
  onnxruntime's own strings expose env knobs `ORT_DISABLE_ALL` / `ORT_DISABLE_ALL`-family and
  generic `NO_GPU` (mostly internal), not a documented Arena switch.
- **WireLib.dll / WireNodes.dll**: `OPENGL32.dll`, `MF.dll`, `MFPlat.DLL`, `DWrite.dll`,
  `SHCore.dll`, `UIAutomationCore.dll`, `d2d1.dll`, `dxgi.dll`, `SETUPAPI`, `WINTRUST`,
  `mswsock`-class networking; plus `avcodec/avformat/avutil/swscale-61/59/8` (WireLib imports
  these statically). WireNodes imports only `OPENGL32`, `USER32`, `WINMM`, `WSOCK32`, `avutil-59`
  → it is the GPU shader side.
- **artnet.dll**: `WS2_32`/`MSWSOCK`/`IPHLPAPI` (UDP broadcast 6454).
- **libltc.dll**: only `KERNEL32.dll`, `VCRUNTIME140.dll`, UCRT api-sets → lowest-risk of the
  static imports.
- **plugins/afx/*.dll**: JUCE-based; standard Win32 + `WININET`, `dbghelp`, `dxgi`, `ole32`,
  `COMDLG32`, `VERSION`. No exotic deps.

## 4. Runtime dependency note (separate from app/ dir)

`app/` ships **no** `msvcp140*.dll` / `vcruntime140*.dll` / `ucrt*.dll`; those live in
`tmp/ffmpeg/` (and `tmp/VC_redist_2022.x64.exe`). All of Arena, NDI, WinSparkle, WireLib etc.
statically import `MSVCP140.dll`/`VCRUNTIME140.dll`/`VCRUNTIME140_1.dll`, so the VC++ 2022
x64 runtime must be installed (or the DLLs placed next to `Arena.exe`) before anything loads.
