# FINDINGS — Solid Edge 2026 on Wine

Every claim here is tied to a command and its output. Milestones are `M<n>`.

---

## M1 — The web installer is a downloader for a host that no longer resolves; its media URLs are inside it

`solid edge`: `Solid_Edge_X_Web_Installer_2026 (1).exe` (650576 B, md5
`5a964219301988aff2907ff7bf41c996`) is a Mono/.NET assembly, `SEWebInstall` 226.0.5.4.

```
$ getent hosts dl.downloadsolidedge.com ; nslookup dl.downloadsolidedge.com 8.8.8.8
(nothing)                                  ; ** server can't find dl.downloadsolidedge.com: NXDOMAIN
$ curl -sI https://dl.downloadsolidedge.com/     # exit 6 (could not resolve)
```

Its own strings say `INI_PARAM_DOWNLOAD_URL`, `DOWNLOAD_URL_EXPIRATION_DATE` and *"Your access to
the download site has expired"*, so the EXE alone cannot fetch media.

**But the 30 presigned CloudFront URLS are stored as UTF-16 user strings in its `.text`.**

```
7z x -o /tmp/seisetup "Solid_Edge_X_Web_Installer_2026 (1).exe"
# then scan .text for the UTF-16LE anchor "https://d22lhzxajabytc.cloudfront.net/226X/PackageZ/"
```

Each real URL ends at `&Key-Pair-Id=K3D8T0VP0UG7TO`; what follows in the heap is `#xxx…>` filler.
Result: `Solid_Edge_Web_Package_2026.7z.001..030` + `Solid_Edge_Web_Package_2026.exe`,
`Expires=1793061009` = **2026-10-27T00:30:09Z** (valid at the time of this work).

Downloaded state, verified per chunk with a HEAD and a local size check:

| chunk | size |
|---|---|
| `.001`–`.026` | 199229440 B (190 MiB) each |
| `.027` | 112075276 B (last) |
| `.028`–`.030` | **HTTP 403 AccessDenied — not part of this package, dropped** |
| `Solid_Edge_Web_Package_2026.exe` | 205664 B (a small PE32 extractor) |

`.001` had to be **truncated to 199229440** — a `curl -C -` resume had appended 84131840 stray bytes
after an interrupted first attempt. Then:

```
$ 7z l installer/media/Solid_Edge_Web_Package_2026.7z.001
Volumes = 27
Total Physical Size = 5292040716
```

— the split archive is whole. Content root `Solid Edge/`: `setup.exe` (1336744), `Siemens Solid Edge
2026.msi` (33835520), `Setup.ini`, `0x0409.ini`, 20 `*.mst`, and the cabs (`DLLS.cab` 1.14 GB,
`Femap.cab` 836 MB, …), plus `ISSetupPrerequisites/{DotNET4.8, Evergreen WebView2 Runtime, Keyshot,
MS VC++ 2022 Redist (x64), Siemens Connector}`.

`Setup.ini`: InstallShield 30, `PackageName=Siemens Solid Edge 2026.msi`,
`ProductCode={855F6E6F-38C4-4FC0-9ECB-EB0D964ED952}`, `UpgradeCode={6BAB7EA2-6BE6-4B22-B8B4-F286A8204142}`,
`Default=0x0409`, and `1205=/S Hide initialization dialog.  For silent mode use: /S /v/qn`.

## M2 — Media inventory: the viewport is **OpenGL**, the DWM surface is small and specific

`installer/media_x/Solid Edge/*.cab` extracted into `installer/cabs_x/`. **Cab entry names are the
MSI `File` table primary keys**, so the real names are recoverable exactly (not by size guessing):

```
$ msiinfo export "Siemens Solid Edge 2026.msi" File > state/msi_File.tsv   # 25175 rows
$ python3 tools/cabx.py ls '^(edge|render|viewsup|D3DGLST)\.'
D3DGLST.dll   35840   _48F9D9B92E4BC151330E13FCB821B2FC
Edge.exe     481648   F644709_Edge.exe
render.dll  2458624   F7419_render.dll
viewsup.dll  145408   _672EE1E15013D5778F6755E0F1AC6E83
```

`msiinfo`/`msiextract` came from `apt-get download msitools` + `dpkg-deb -x` (no sudo on this box —
the password in the sibling docs no longer works; `apt-get download` is rootless).

Import scan over all 2479 cab PEs (`objdump -p`):

| API | importers |
|---|---|
| `opengl32.dll` | **14** — `render.dll`, `viewsup.dll`, `Visual.dll`, `vwdata.dll`, `corevw.dvx`, `VWCMDS.DCX`, `igl.dll`, `IJGL.dll`, `JtOGL-10.8.0.dll`, `SEPreview.ocx`, `SEAMCheckers.dll`, `ViewerControl3dLib.dll`, `ToolkitPro2410vc170x64U.dll`, `SE_Tech_Pubs_Export.dll` |
| `glu32.dll` | 9 (the same set) |
| `d3d11.dll` | 1 — `LicensingTool.exe` only |
| `dxgi.dll` | 1 — `LicensingTool.exe` only |
| `dcomp.dll` | 1 — `SEInkHost.dll` |
| `dwmapi.dll` | 2 — `LicensingTool.exe`, `control.dll` (`DwmIsCompositionEnabled`, `DwmEnableBlurBehindWindow`, `DwmSetWindowAttribute` — **not** `DwmGetWindowAttribute`) |

**The 3D viewport is OpenGL** (`render.dll` imports `wglGetProcAddress`, `wglGetCurrentDC`,
`wglCopyContext`, `glBegin`/`glEnd`, `gluNewTess`/`gluTessVertex`, `gluProject`). `D3DGLST.dll`
imports only `render.dll`/`jengine.dll`/`ugeom.dll` — it is a thin layer over `render.dll`.
This is the subsystem bug #1 (flickering black viewport) lives in.

## M3 — `DwmGetWindowAttribute` on Windows: E_INVALIDARG for the unknown, S_OK + 0 for `DWMWA_CLOAKED`

`tools/winapi/dwmprobe.c` is one PE that runs on both platforms; Windows reference captured by
running it in the `win11` guest through the file channel (`tools/vm/vmcmd.sh`):

```
== os version 6.2 build 0
DwmIsCompositionEnabled -> hr=0x00000000 enabled=1
attr  1 DWMWA_NCRENDERING_ENABLED           hr=0x00000000  DWORD 0x00000001 (1)
attr  5 DWMWA_CAPTION_BUTTON_BOUNDS         hr=0x8007007a  (needs a RECT-sized buffer)
attr  9 DWMWA_EXTENDED_FRAME_BOUNDS         hr=0x00000000  RECT 57,50,443,343
attr 14 DWMWA_CLOAKED                       hr=0x00000000  DWORD 0x00000000 (0)
attr 15 DWMWA_FREEZE_REPRESENTATION         hr=0x00000000  DWORD 0x00000000 (0)
attr 16 DWMWA_PASSIVE_UPDATE_MODE           hr=0x00000000  DWORD 0x00000000 (0)
attr 19/20 USE_IMMERSIVE_DARK_MODE(20)      hr=0x00000000  DWORD 0x00000000 (0)
attr 33 DWMWA_WINDOW_CORNER_PREFERENCE      hr=0x00000000  DWORD 0x00000000 (0)
attr 37 DWMWA_VISIBLE_FRAME_BORDER_THICKNESS hr=0x00000000 DWORD 0x00000001 (1)
attr 38 DWMWA_SYSTEMBACKDROP_TYPE           hr=0x00000000  DWORD 0x00000000 (0)
attr 0,2,3,4,6,7,8,10,11,12,13,17,18,21..32,34,35,36,39  hr=0x80070057 (E_INVALIDARG)
attr 14 pv=NULL size=0   -> hr=0x80070057 (E_INVALIDARG)
attr 14 size=0           -> hr=0x80070057 (E_INVALIDARG)
attr 14 bogus hwnd       -> hr=0x80070006 (E_HANDLE)
```

So the Windows contract is: **argument validation first, `E_INVALIDARG` for attributes it does not
know, and a real `S_OK | *out = 0` for `DWMWA_CLOAKED` (14)**, 15, 16, 19/20, 33, 37, 38.

Wine's `dlls/dwmapi/dwmapi_main.c` implements only `DWMWA_EXTENDED_FRAME_BOUNDS` and answers
`FIXME("attribute %ld not implemented.")` + `E_NOTIMPL` for everything else — which is exactly the
line the user sees when they click Close Sketch. `DwmIsCompositionEnabled` is not the problem: it
already reports `TRUE` (real `RtlGetVersion` >= 6.3, and the prefix is set to `win10`), so Wine takes
the "composition enabled" path and reaches the attribute switch.

## M4 — QEMU's left-modifier qcodes are `ctrl`/`alt`/`shift`, not `ctrl_l`/`alt_l`

The guest channel needs keystrokes. `virsh qemu-monitor-command … 'input-send-event'` with
`{"data":"ctrl_l"}` answers:

```
{"error":{"class":"GenericError","desc":"Parameter 'data' does not accept value 'ctrl_l'"}}
```

and with `"ctrl"`: `{"return":{}}`. Because the wrapper swallowed the error, every `ctrl+a` /
`alt+f4` silently did nothing for ~40 minutes of guest work. Fixed in `tools/vm/vmkey.py`.

## M5 — The caller of attribute 14 is .NET's `UIAutomationClient`, and it reads the HRESULT

The FIXME comes from a *managed* caller, not from Solid Edge's own code:

* `objdump -p` over all 2479 cab PEs finds `DwmGetWindowAttribute` statically imported only by
  `LicensingTool.exe`; `control.dll` imports `dwmapi` but only `DwmIsCompositionEnabled` /
  `DwmEnableBlurBehindWindow` / `DwmSetWindowAttribute`.
* A scan of all 2479 PEs for the string in both ASCII and UTF-16 finds it in
  `DevComponents.DotNetBar2.dll`, `LicensingTool.exe`, `SE_Tech_Pubs_Export.dll`,
  `ToolkitPro2410vc170x64U.dll`. Decompiling each: `ToolkitPro` resolves it with `GetProcAddress`
  and calls it with **attribute 9** (`mov $0x9,%edx`, size `0x10`, stack RECT);
  `DevComponents.DotNetBar2` declares the P/Invoke and **never calls it** (whole-module ILSpy dump,
  467787 lines, one occurrence: the declaration); `SE_Tech_Pubs_Export.dll`'s only reference is a
  pointer in a string table.
* The real caller is in the .NET Framework the prefix will get: **`UIAutomationClient.dll`**.
  `7z x ~/.cache/winetricks/dotnet48/ndp48-x86-x64-allos-enu.exe` then the
  `x64-Windows10.0-KB4486129-x64.cab` inside it; ILSpy on
  `msil_uiautomationclient_*/uiautomationclient.dll`:

```csharp
[DllImport("DwmApi.dll")]
internal static extern int DwmGetWindowAttribute(NativeMethods.HWND hwnd, int dwAttributeToGet,
                                                 ref int pvAttributeValue, int cbAttribute);

private static bool IsWindowCloaked(NativeMethods.HWND hwnd)
{
    int pvAttributeValue = 0;
    if (SafeNativeMethods.DwmGetWindowAttribute(hwnd, 14, ref pvAttributeValue, 4) == 0)
        return pvAttributeValue != 0;
    return false;                       // <- Wine's E_NOTIMPL lands here
}

private static bool IsWindowReallyVisible(NativeMethods.HWND hwnd)
{
    if (!SafeNativeMethods.IsWindowVisible(hwnd)) return false;
    if (!Misc.GetWindowRect(hwnd, out var rc)) return false;
    if (rc.right - rc.left <= 0 || rc.bottom - rc.top <= 0) return false;
    if (IsWindowCloaked(hwnd)) return false;
    return true;
}
```

`IsWindowReallyVisible` is called from `GetAllUIFragmentRoots`/`FindModalWindow`, i.e. UIA's
"which window of this process is the real one" logic — which a Solid Edge command that opens or
closes a UI fragment goes through.  **`IsWindowCloaked` tolerates the failure** (it falls back to
"not cloaked"), so the `E_NOTIMPL` is *not by itself* the reason the sketch will not close; it is
a Wine-vs-Windows API difference on a code path the application reached, and it must be fixed for
the contract to match.  The actual close failure still has to be located.

## M6 — the exact vendor install command line and the trial activation code

`SEWebInstall.frmSEWebInstall` (ILSpy) builds the install command; it is the recipe the media was
meant to be installed with:

```
setup.exe /s /clone_wait /v"/qn"
          /v"INSTALLDIR=\"<install dir>\""          (with a trailing backslash)
          /v"USERFILESPEC=\"<install dir>\Preferences\SELicense.lic\""
         [/v"INSTALLENGLISH=Yes"]
          /v"/l*v \"%TEMP%\SESilentInstall.log\""
```

and it then checks `<install dir>\Program\Edge.exe` exists, else "Installation failure".  The
installer is `SEInstallerWrapperAPIs`/`SEWebInstallUtilities`; the media root it expects is
`<download dir>\Solid Edge\` — which is exactly the layout inside the 7z.

The download URLs are embedded in `SEWebInstallIniParamTags` as `<value>#<filler>` and
`GetParamValueFromReplacementTag()` returns everything before the `#` — that is what the trailing
`#xxxx…>` junk was.  The same class carries

```
INI_PARAM_ACTIVATION_CODE    = "7262936774378157"
INI_PARAM_DATE_TIME_GENERATED= "09/26/2026 20:30"
```

and `SEWebInstallPackageCodes` carries a **SHA-512 per package** (used by
`IsSEFileChecksumValid`), usable to verify the chunks.

The media itself ships a demo license, `installer/cabs_x/selicense.lic` (67 bytes, from
`Licens~1.cab`):

```
FEATURE SolidEdge sedemon 1.0 permanent uncounted 0 HOSTID=DEMO
```

`SELicense.ini` (from the media) documents the licensing model: a license server
(`SE_LICENSE_SERVER`), "I have a license file", "I have an activation code", plus
**"Free 2D Drafting" and "Viewer Mode"** — two licence-free modes that are an escape hatch if the
FlexLM path does not come up under Wine.

## M7 — the Windows guest cannot be an OpenGL reference: it has no GPU driver

`tools/winapi/wglprobe.exe` (one PE, both platforms). On the guest (QEMU QXL adapter, no 3D
driver installed):

```
DescribePixelFormat(hdc, 1, 0, NULL) = 36          # 36 pixel formats, Wine reports 200
ChoosePixelFormat(...)                = 3  (last error 87)
  chosen: type=RGBA color=32 depth=32 stencil=8 flags=DOUBLEBUFFER DRAW_TO_WINDOW
          SUPPORT_OPENGL GENERIC_FORMAT SWAP_COPY       # every format is GENERIC_FORMAT
wglCreateContext = 0000000000010000
glGetString(GL_VENDOR)   = Microsoft Corporation
glGetString(GL_RENDERER) = GDI Generic              # Microsoft's software OpenGL
glGetString(GL_VERSION)  = 1.1.0
wglGetExtensionsStringARB/EXT = 0
wglChoosePixelFormatARB / wglCreateContextAttribsARB / wglSwapIntervalEXT = 0
```

Under Wine on the VNC display (`:2`, host GPU):

```
DescribePixelFormat(hdc, 1, 0, NULL) = 200
ChoosePixelFormat(...)                = 104
  chosen: type=RGBA color=32 depth=24 stencil=8 flags=DOUBLEBUFFER DRAW_TO_WINDOW DRAW_TO_BITMAP SUPPORT_OPENGL
                                                    # no GENERIC_FORMAT anywhere in the list
glGetString(GL_VENDOR)   = Intel
glGetString(GL_RENDERER) = Mesa Intel(R) Arc(tm) Graphics (MTL)
glGetString(GL_VERSION)  = 4.6 (Compatibility Profile) Mesa 26.0.8-1ubuntu0.3
WGL extensions: WGL_ARB_create_context[_profile|_no_error] WGL_ARB_extensions_string
                WGL_ARB_framebuffer_sRGB WGL_ARB_make_current_read WGL_ARB_multisample
                WGL_ARB_pbuffer WGL_ARB_pixel_format WGL_ARB_pixel_format_float
                WGL_ARB_render_texture WGL_ATI_pixel_format_float WGL_EXT_extensions_string
                WGL_EXT_framebuffer_sRGB WGL_EXT_pixel_format_packed_float WGL_EXT_swap_control
                WGL_EXT_swap_control_tear WGL_WINE_pixel_format_passthrough WGL_WINE_query_renderer
wglChoosePixelFormatARB -> 1 err=0 nformats=0 format=0      # <- worth a second look
```

Consequences: the guest answers `GDI Generic` / `GL 1.1` / all-`GENERIC_FORMAT`, so it exercises
Solid Edge's *software* path, not the accelerated one Wine will take; it is a reference for
everything **except** the graphics stack.  Two Wine-side observations to chase later: the ARB
format query returned success with **zero** formats, and Wine's real-GPU format list carries no
`PFD_GENERIC_FORMAT` at all.  (`SupportsOpenGL(HDC, DWORD)`, `JValidateGraphicSubsystem()` and
`JCreateGDI2OpenGL()` are all exported by `Visual.dll`, so Solid Edge does look at these flags to
choose a rendering path.)

## M8 — the tools that make "action → log line" attribution possible

The user's requirement is to *match actions to log lines and log lines to disassembled Solid Edge
code*. Three pieces do that, all in `tools/`:

1. **Timestamps in the Wine log.** Wine has a `timestamp` debug channel:
   `dlls/ntdll/unix/debug.c:339  if (TRACE_ON(timestamp))`. So
   `WINEDEBUG=+timestamp,+<channels>` prefixes every line with an elapsed-time stamp, and
   `tools/run_se.sh --debug '+timestamp,+dwmapi'` is a log whose lines can be ordered against a
   click.
2. **Timestamped actions.** `tools/se_drive.sh <window> <actions-file>` runs a directive script
   (`wait`, `click x y`, `dblclick`, `key`, `type`, `shot`, `note`) against the app window on the
   VNC display and writes every step with a millisecond timestamp to `drive.log`. Both logs use the
   same host clock, so a `NOTE` marker in the action file brackets whatever the app does next.
3. **Which module calls an import.** `tools/xref.py <pe> <import>` prints the absolute VAs that call
   an imported function, handling both `call qword ptr [rip+disp]` (FF 15) and the `jmp [rip+disp]`
   (FF 25) thunk form, because MSVC emits the thunk when it links against a DLL import library.
   Getting this wrong cost time: `objdump -p` prints import IAT addresses as **RVAs** while
   `objdump -h` prints section VMAs as **absolute** addresses, and `objdump -p`'s export
   `[Ordinal/Name Pointer] Table` numbers are ordinals, not RVAs.

Worked example from that tool: in `control.dll`,
`EnableMenuItem` is called from 60+ sites, and the `SC_CLOSE` (0xf060) site is at `0x180254442` /
`0x180254617`, where the code maps an internal command id to an `SC_*` code and then
`PostMessageW(tab_item_hwnd, WM_SYSCOMMAND (0x112), SC_*, 0)` — i.e. that is the **document tab's**
close path (`CXTPTabManagerItem::GetHandle` from `ToolkitPro2410vc170x64U.dll` supplies the HWND),
not the main frame's title-bar X.

## M9 — the DwmGetWindowAttribute patch, verified two ways

`patches/local/0023-dwmapi-window-attributes.patch` implements the M3 contract and stores
`DwmSetWindowAttribute` values as window properties so they round-trip (as Windows does).

**1. The Wine test suite** (the form every sibling project uses for evidence):

```
$ DISP=:2 tools/run_wine_tests.sh dwmapi dwmapi
== building dlls/dwmapi/tests
== running dwmapi_test.exe dwmapi under .../wine-install/bin/wine
0020:dwmapi: 54 tests executed (0 marked as todo, 0 as flaky, 0 failures), 0 skipped.
```

`test_DWMWA_attributes()` asserts the whole table: `S_OK`+value for 1/14/15/16/20/33/37/38,
`E_INVALIDARG` for the attributes Windows does not know, `E_INVALIDARG` for a NULL pointer or a
too-small DWORD buffer, `E_NOT_SUFFICIENT_BUFFER` for a too-small RECT buffer on 5/9, `E_HANDLE`
for a bogus HWND and for a child window on 9, an exact-DWORD requirement on 37, and the
set/get round trips.

**2. The differential probe** — the same `dwmprobe.exe` on the guest and under this fork, diffed:

```
$ diff <(grep -E '^attr|^pv|^size|^bogus|^set|^get|^DwmIs' logs/dwmprobe_windows.txt) \
       <(grep -E '^attr|^pv|^size|^bogus|^set|^get|^DwmIs' logs/dwmprobe_wine.txt)
13c13
< attr  5 size 16 DWMWA_CAPTION_BUTTON_BOUNDS   hr=0x00000000  INT[4] 247 0 393 30
> attr  5 size 16 DWMWA_CAPTION_BUTTON_BOUNDS   hr=0x00000000  INT[4] 346 0 400 26
21c21
< attr  9 size 16 DWMWA_EXTENDED_FRAME_BOUNDS   hr=0x00000000  INT[4] 57 50 443 343
> attr  9 size 16 DWMWA_EXTENDED_FRAME_BOUNDS   hr=0x00000000  INT[4] 50 50 450 350
82c82
< attr 40 size  4                                hr=0x8007007a  unchanged abababab..
> attr 40 size  4                                hr=0x80070057  unchanged abababab..
```

Every **status code and buffer-size rule** now matches. The remaining differences:

* attributes 5 and 9 return *a* rect in both cases; the numbers depend on each platform's window
  decoration and non-client metrics (`INT[4] 247 0 393 30` vs `346 0 400 26`), so they are not
  comparable values and the test does not assert them.
* attribute 40 is one Windows knows and Wine has no constant for; only its `size < 8` case differs
  in which failure it reports (`ERROR_INSUFFICIENT_BUFFER` vs `E_INVALIDARG`).
* attribute **19** is the pre-Windows-11 number for `DWMWA_WINDOW_CORNER_PREFERENCE` (33), and
  Windows 11 still answers it: `set 19=3` → `S_OK`, then `get 19` → `1` while `get 33` is
  unchanged at `2`, and `set 33=4` leaves `get 19` at `1` — so they are **separate slots**. The
  patch answers both (`DWMWA_WINDOW_CORNER_PREFERENCE_OLD`); the only residual difference is that
  Windows *clamps* the value it reads back (3 → 1) where Wine returns what was set, which the test
  deliberately does not assert.
* `set 20=5` then `get 18` → `E_INVALIDARG` on both: 18 is not a usable number on this build even
  though the SDK names it.

## M10 — a ~900 ms SwapBuffers on the VNC display is the *display's*, not Wine's (native control)

Measured while looking for the flickering viewport: on the TigerVNC display `:2` with the Intel Arc
GPU, `SwapBuffers`/`glXSwapBuffers` with a swap interval of 1 blocks for **~900 ms** — with interval
0 it is ~1.5 ms. Wine's per-window interval defaults to 1 (`dlls/win32u/window.c:5971
win->swap_interval = 1;`), the same as Windows, and Solid Edge's `Visual.dll` names
`wglSwapInterval{,ARB,EXT}`, so it can set it too.

| client | display | interval | swap |
|---|---|---|---|
| `tools/winapi/swapprobe.exe` (Wine, top-level) | `:2` | 0 | **1.59 ms** |
| `tools/winapi/swapprobe.exe` (Wine, top-level) | `:2` | 1 | **899.95 ms** (max 1001.61) |
| `tools/winapi/swapprobe.exe` (Wine, child) | `:2` | 0 | 1.30 ms |
| `tools/winapi/swapprobe.exe` (Wine, child) | `:2` | 1 | 899.93 ms |
| `tools/winapi/swapprobe.exe` (Wine) | `:9` Xvfb/llvmpipe | 1 | 0.66 ms |
| `tools/native/glxswap` (**native X client**, no Wine) | `:2` | 1 | **899.39 ms** (max 1001.18) |
| `tools/native/glxswap` (**native X client**, no Wine) | `:2` | 0 | 1.67 ms |
| `tools/native/glxswap` (native) | `:2`, `LIBGL_ALWAYS_SOFTWARE=1` | 1 | 0.50 ms |

The native control settles it: the block is Xtigervnc's GLX present path, not Wine — so there is no
Wine patch to write for it, and **a vsync-enabled GL application cannot be judged on `:2` with
hardware GL** (it would run at ~1 fps and look exactly like a viewport that keeps going black).
Two ways out, both measured: `LIBGL_ALWAYS_SOFTWARE=1` (llvmpipe, 0.50 ms at interval 1) or an
Xvfb display.  Consequences for this project: run Solid Edge with
`LIBGL_ALWAYS_SOFTWARE=1` while judging *presentation*, and re-check any timing claim on a display
whose present does not block.

A second control, for the record: `tools/winapi/glchild.exe` builds the shape of Solid Edge's
viewport — a frame that paints its background and a GL child that draws and swaps — with the
variants that Solid Edge's own imports suggest (`control.dll` and `ToolkitPro2410vc170x64U.dll`
import `SetLayeredWindowAttributes`/`UpdateLayeredWindow`/`SetWindowRgn`, and `control.dll` calls
`DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE (0x21), 2 /* ROUND */, 4)`), and
`tools/host/flicker.py` counted **0 black frames in every variant**:

| variant | black frames |
|---|---|
| `--clipchildren` (default) | 0 / 60 |
| `--no-clipchildren` | 0 / 60 |
| `--single` (no `PFD_DOUBLEBUFFER`) | 0 / 60 |
| `--no-clipchildren --single` | 0 / 60 |
| `--layered` (`WS_EX_LAYERED` + `SetLayeredWindowAttributes`) | 0 / 50 |
| `--rgn` (`SetWindowRgn` with a round rect) | 0 / 50 |
| `--layered --rgn` | 0 / 50 |

So "a GL child window in Wine", even a layered one with a rounded frame, does not flicker black on
its own; the flicker needs whatever else Solid Edge does, and has to be found in the application's
own logs and window tree rather than reproduced from its imports.
