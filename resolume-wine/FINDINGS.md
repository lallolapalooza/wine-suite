# Resolume Arena 7 on Wine — findings

One entry per measured result. Every claim here was run, not assumed. Deeper per-topic notes are
in `notes/` (produced by parallel research agents; each is command-grounded).

## M1 — the installer is Inno Setup 6.1.0 and its payload is enumerable without running it
`innoextract 1.9` (fetched via `apt-get download` + `dpkg-deb -x`, no sudo) lists and extracts it:
`innoextract -l` reports 1096 entries, `-e` writes them to `installer/media_x/` (3.1 GB).
The EXE header says `built with Inno Setup`; setup data version **6.1.0 (unicode)**.

## M2 — payload inventory (what has to run)
| path | size | note |
|---|---|---|
| `app/Arena.exe` | 56.6 MiB | **the application** |
| `app/avcodec-61`/`avformat-61`/`avutil-59`/`swscale-8` | 17 MiB | FFmpeg 7.x — open source, tracable from source |
| `app/WireNodes.dll` | 24.7 MiB | Resolume Wire node engine (dynamic: `Libwire not found in location:`) |
| `app/Processing.NDI.Lib.x64.dll` | 27.4 MiB | NDI — **static import** of Arena.exe |
| `app/onnxruntime.dll` + `app/DirectML.dll` | 34 MiB | AI inference; only loaded by WireLib |
| `app/plugins/afx/*.dll` | 6×7.9 MiB | audio effects (JUCE); optional dir |
| `app/plugins/wire/*.wired` | — | Wire patches; optional |
| `app/WinSparkle.dll` | 2.7 MiB | Sparkle updater — **static import** |
| `app/BugSplat*.{exe,dll}` | — | crash reporter; spawned, kill switch string `DISABLE_BUGSPLAT` |
| `app/artnet.dll`, `app/libltc.dll` | — | Art-Net, LTC timecode — static imports |
| `pf/Resolume Wire/Wire.exe`, `pf/Resolume Alley/Alley.exe` | — | standalone Wire / Alley |
| `tmp/VC_redist_2022.x64.exe`, `tmp/vulkan-runtime.exe`, `tmp/Bonjour64.msi` | — | prerequisites |
| `tmp/DXV3*.{prm,aex}` | — | DXV3 codec plugins for Adobe hosts |

## M3 — Arena.exe's PE shape (notes/arena-pe.md)
PE32+ x86-64 GUI, image base `0x140000000`, subsystem 6.0, linker 14.44 (VS 2022 17.14),
PDB `…\RelWithDebInfo\Arena.pdb`, **49 imported DLLs / 1224 functions**, **no delay imports, no
bound imports**. Manifest: `asInvoker`, `dpiAware=true`, `SegmentHeap`, supportedOS Win10/11,
dependency `Microsoft.Windows.Common-Controls 6.0.0.0`. Authenticode-signed by Resolume B.V.
Biggest import consumers: KERNEL32 229, MSVCP140 223, USER32 125, OPENGL32 42.
OPENGL32 = fixed-function GL 1.x + `wglCreateContext/wglMakeCurrent/wglGetProcAddress`; pixel
format and `SwapBuffers` come from GDI32. Also imports `d3d11`, `dxgi`, `MF.dll`, `MFPlat.DLL`,
`SETUPAPI`, `WINTRUST`, `CRYPT32`, `WININET`, `IPHLPAPI`, `MSWSOCK`, `WS2_32`, `WSOCK32` (29
winsock-1.1 ordinals), `OLEAUT32` (10 ordinals), `SHLWAPI` (ord219 `QISearch`), `IMM32`.
Every import resolves in patched Wine 11.18's specs; `COMCTL32` ordinal 345 (`TaskDialogIndirect`)
is supplied by the separate `comctl32_v6` module, which Wine loads for the SxS v6 dependency.

## M4 — the media stack is FFmpeg 7.1.1, static MSVC, hwaccel-heavy (notes/ffmpeg.md)
`avcodec-61.dll` reports **FFmpeg 7.1.1 / libavcodec 61.19.101**, MSVC vcpkg build, `--enable-shared
--enable-debug`. Enabled Windows backends: `d3d11va d3d12va dxva2 mediafoundation schannel cuda
nvenc nvdec cuvid ffnvcodec amf w32threads`; **no vulkan, no opengl**. The four DLLs import only
kernel32/user32/ole32/bcrypt/secur32/ws2_32 + the MSVC CRT + each other — every one of those
functions exists (non-stub) in patched Wine 11.18's specs. HW paths are `LoadLibrary`+`GetProcAddress`
at runtime. Modules Wine lacks that FFmpeg may probe: `dxgidebug.dll`, `nvcuda.dll`, `nvcuvid.dll`,
`nvEncodeAPI64.dll`, `amfrt64.dll`; Wine's dxgi also lacks `DXGIGetDebugInterface` and
`DXGIDeclareAdapterRemovalSupport`.

## M5 — Media Foundation is mostly real in Wine 11.18 (notes/mf-gap.md)
All 12 MF entry points Arena imports are real (not stubs) in the patched tree; the sample-grabber
sink delivers samples; `CLSID_CColorConvertDMO` (colorcnv) and `CLSID_VideoProcessorMFT` (msvproc)
are implemented on libswscale. The H.264 decoder MFT delegates to winegstreamer and **needs the
host GStreamer H.264 plugins**: this host has gstreamer1.0-plugins-{base,good,bad,ugly,libav} plus
`libgstopenh264`/`libgstsvtav1`, so it is satisfied.

## M6 — optional components and how to neutralise them (notes/components.md)
- Arena.exe **statically imports** NDI, WinSparkle, artnet (case: disk `artnet.dll`), libltc, the
  FFmpeg DLLs, d3d11, dxgi, MF/MFPlat. Those cannot be dropped without file replacement.
- WireLib.dll is `LoadLibrary`-ed (graceful message `Libwire not found in location:`);
  WireNodes/onnxruntime/DirectML are loaded by WireLib only → removing them yields passthrough.
- BugSplat: `"%s\BugSplatMonitor.exe" -m <pid>` + `WerRegisterRuntimeExceptionModule`; kill switch
  is the string `DISABLE_BUGSPLAT`.
- `app/`. ships no VC++ runtime DLLs although everything imports them → the installer's
  `VC_redist_2022` step (or a Wine builtin) must satisfy `msvcp140`/`vcruntime140`/`vcruntime140_1`.

## M7 — vendor installer behaviour (notes/installer.md)
- Silent: `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /LOG="..." /DIR="..."` (Inno 6.1, English).
- `PrivilegesRequired=Admin`; `/ALLUSERS`/`/CURRENTUSER` are parsed but have **no effect**
  (`PrivilegesRequiredOverridesAllowed` empty) → UAC elevation is mandatory.
- Default dir `{pf}\Resolume Arena`; uninstall key `HKLM\…\Uninstall\Resolume Arena_is1`.
- Prerequisites run from `[Code]`: `msiexec /i "{tmp}\Bonjour64.msi" /quiet`,
  `{tmp}\VC_redist_2022.x64.exe /quiet /norestart`, `{tmp}\vulkan-runtime.exe` (no args).
- `[Run]` adds `netsh` firewall rules, launches Arena.exe (skipped in silent), and runs
  `{pf}\Resolume Wire\Wire.exe --FixLicensePermissions`.
- First run is unregistered & watermarked (strings: `#1 is not registered. The video and audio are
  watermarked.`, `Enter your #1 serial number...`); registration lives in
  `{commonappdata}\Resolume Arena\Registration\`.

## M9 — the Windows reference: guest has no GPU, so Mesa llvmpipe is dropped in
Installed Resolume in the guest with the vendor's own silent line, **elevated**:
`ResArena.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /LOG=C:\res_install.log` → exit 0,
2,208,639,986 bytes in `C:\Program Files\Resolume Arena` in ~10 min (prerequisites Bonjour/VC++/
Vulkan included).
The guest's only display adapter is **Microsoft Basic Display Adapter** → OpenGL 1.1, and Arena
answers `Application failed to initialize. … eg OpenGL version 4.1`. Dropped **Mesa3D 26.2.3
(pal1000 mesa-dist-win, release-msvc)** `opengl32.dll` + `libgallium_wgl.dll` (+`dxil.dll`) into the
app directory: with `GALLIUM_DRIVER=llvmpipe` Arena's full UI now renders:
`Resolume Arena - Example.avc - Loading...`, Composition/Preview monitors, `/composition 1920x1080`,
`Resolume Arena 7.28.0` status bar. Baseline screenshots: `logs/vm-baseline/arena_llvmpipe_*.png`.
**Arena requires OpenGL 4.1** — a hard requirement for the Wine side too (the host's Intel Arc via
Mesa gives 4.6).

## M10 — the Wine side has OpenGL 4.6, so Arena's 4.1 requirement is met
`tools/winapi/glprobe.c` (a differential probe, built with `x86_64-w64-mingw32-gcc`) run under the
built Wine on `DISPLAY=:2`:
```
ChoosePixelFormat = 104
wglCreateContext = 0000000000010001
GL_VERSION  = 4.6 (Compatibility Profile) Mesa 26.0.8-1ubuntu0.3
GL_VENDOR   = Intel
GL_RENDERER = Mesa Intel(R) Arc(tm) Graphics (MTL)
GLSL        = 4.60
WGL_extensions = WGL_ARB_create_context … WGL_ARB_pbuffer WGL_ARB_render_texture
                 WGL_EXT_swap_control … WGL_WINE_pixel_format_passthrough
wglCreateContextAttribsARB = present
4.1 core context = 0000000000010002
GL41_VERSION = 4.6 (Core Profile) Mesa 26.0.8-1ubuntu0.3
```
So Wine exposes the host's Mesa on the Intel Arc with core-profile 4.1+ contexts — the GL side is
not expected to be the blocker.

## M11 — the vendor Inno installer runs under Wine (and needed the payload prerequisites first)
`tools/mkprefix.sh` (wineboot, Windows 10 registry, then the payload's `VC_redist_2022.x64.exe`
and `vulkan-runtime.exe`) leaves `msvcp140.dll` (5,047,293 B) in the prefix's `system32`, and Inno's
own check then reports `VC Redist Version check : found v14.50.35710.00 / VC Redist is up to date:
14.50.35710.0 >= 14.50.35710.0`. With that, the vendor installer runs file-by-file under Wine
(`C:\res_wine.log` shows each `Successfully installed the file.`) — **Inno Setup 6.2.1**, not 6.1.0
as the payload header suggested; `PrivilegesRequired=Admin` and Inno sees the Wine user as
`User privileges: Administrative`.
Note: two installer instances were accidentally run concurrently and were killed; a single clean
run then produced a complete tree.

## M12 — ROOT CAUSE: Arena aborts at `Find default fonts` because Wine does not enumerate Arial/Verdana
Arena's own log (read out of the prefix while the app runs) ends at:
```
INFO: Enumerate fonts
INFO: Find default fonts
INFO: Default fonts not available
```
The Windows guest's log for the same phase continues past it:
```
INFO: Find default fonts
INFO: Create Application Object      <-- Wine never gets here
```
Disassembly of the caller (`Arena.exe+0xbd4fxx`) shows the argument it passes to its font lookup
(`0x140fd87f0`) is a two-element table at `0x142f4fa00` of `{name, length}` pairs:
`("Arial", 5)` and `("Verdana", 7)` with style `("Regular", 7)` — i.e. it enumerates system font
**families** for *Arial Regular* and *Verdana Regular* and gives up if neither exists.

`tools/winapi/fontprobe.c` under Wine before the fix:
```
CreateFont("Arial")   -> GetTextFace "Liberation Sans"   <-- creation substitutes...
CreateFont("Verdana") -> GetTextFace "Liberation Sans"
total families=2498 interesting=23                        <-- ...but enumeration has no "Arial"
  FOUND family "Liberation Sans" / "DejaVu Sans" / "Tahoma" / "MS Sans Serif"   (no Arial, no Verdana)
```
After installing the real fonts into the prefix's `drive_c/windows/Fonts` (20 TTFs copied out of the
guest's `C:\Windows\Fonts`, incl. the Arial/Verdana/Times/Courier families via `corefonts.zip` on the
HTTP channel):
```
CreateFont("Arial")   -> GetTextFace "Arial"
CreateFont("Verdana") -> GetTextFace "Verdana"
FOUND family "Arial" ...
FOUND family "Verdana" ...
```
**Finding:** Wine's GDI *substitutes* Arial/Verdana for creation but does not expose them in
`EnumFontFamiliesEx`, whereas on Windows they are installed and therefore enumerated. Any app that
enumerates families (JUCE's font handling does) fails to find them under Wine.

## M13 — FIX: `IDXGIOutput::WaitForVBlank` implemented in `dxgi` (Arena now opens)
`patches/local/0100-dxgi-output-WaitForVBlank.patch` (applies clean to the pristine tree).

Wine's `dxgi_output_WaitForVBlank` (`dlls/dxgi/output.c`) was a stub returning **`E_NOTIMPL`**, and
Arena calls it while bringing up its display/output path — the last GPU call the tracer records
before the stall is `dxgi!CreateDXGIFactory`. Without a real wait the caller makes no progress: the
app idled with a black window, a `GetMessage` loop, one worker polling
`WaitForSingleObject(handle,1ms)` ~900×/s and no paint calls.

The patch paces the caller at the output's refresh rate (`wined3d_output_get_display_mode`), one
blank per call, anchored on the first call and re-anchored after an unexpectedly long gap.

**Result (measured):** with the patch built and both fixes in place, the app completes startup.
Window list and log after ~20 s:
```
0xc00035 "Resolume Arena - Example (1280 x 720, 8bpc)"  1560x960
0xc00031 "Advanced Output"                              1100x593
0xc0002c/…19/18/17 "Resapi offscreen window"            111x64   (×4)
0xc0001e "DirectSound", 0xc0001b/1c/1d "Windows Audio", 0xc0001a "JuceMidiDeviceDetector_"
INFO: Attach Notes Panel inspector / Load auto-saved layout
INFO: Attach StatusBar inspector to MainComponent
INFO: Initializing OpenGLComponent
INFO: ... Loading startup composition finished
```
`logs/runs/ui1_root.png` (vision-checked) shows the full UI: composition/layer/clip grid with clips
(`SpaceUniverse`, `Ethnik2`, `FogAndDust`, …), `Composition - 1280x720` and Preview monitors,
transport `BPM 128`, the Composition/Layer/Clip panels with effects (`Shift RGB`, `Hue Rotate`,
`Wave Warp`, …), the Files browser and the status bar **`Resolume Arena 7.28.0`**.
The `dxgi_output_WaitForVBlank … stub!` fixme is gone (`grep -c` = 0).

**Both fixes are required.** The font fix (`M12`, `docs/FONT_REQUIREMENT.md`) is needed for the later
`Find default fonts` step; the `dxgi` patch is what lets startup reach it at all.

## M8 — Windows guest: the control channel and UAC
- Command channel is a PowerShell poller in the guest (`vmshare/se_svc.ps1`) pulling `cmd.txt` from
  `http://192.168.122.1:8000/` and PUTting `guest_cmd_out.txt` back; host side is
  `tools/vm/vmserv.py` (must support PUT).
- `tools/vm/vmcmd.sh '<powershell>'` sends a command; `tools/vm/vmtype2.py` types into the guest
  (per-character `virsh send-key --holdtime`, which does not leak a stuck shift the way per-key
  QMP calls do); `virsh send-key win11 --holdtime 60 KEY_LEFTALT KEY_F4` is a reliable combo.
- The guest user `adsf` is in Administrators **but UAC-filtered (medium integrity)**, so writing to
  `Program Files` fails with access-denied from the poller. The UAC consent dialog focuses **No**
  by default → the prompt must be answered with **Alt+Y** (`tools/vm/elev.sh`).
- Guest keyboard is US; verified by typing `d:\g.bat` into Notepad character-for-character.
