# OPENSOURCE_TRACE — Win32 API surface of the open-source components in the Tableau 2026.2.3 payload, and what Wine 11.18 does with it

Method: **trace the upstream source, do not decompile.** Every claim below comes from (a) the payload's own
files (`strings`, `objdump -p` import tables, PE version resources — no disassembly), (b) upstream source at a
pinned tag/branch, (c) the patched Wine tree `wine-11.18/` read at `file:line`, and (d) small mingw probes run
under Wine. `/home/asdf/projects/tableau-wine/wine-11.18` is the ground truth for "does Wine implement it".

Payload root `$BIN` = `app/tableau_exe/msi_root/Tableau/Tableau 2026.2/bin` (5425 files, PE32+ x86-64 except
`bin/d3dcompiler_47.dll`, which is i386).

Evidence written alongside this file (reproducible, small):
- `recon/evidence/dll_imports.txt` — DLL-level import lists.
- `recon/evidence/symbol_imports.txt` — symbol-level import lists for eps.exe, yaxcatd.exe, Qt6*.
- `recon/evidence/load_time_gaps.json` — machine-checked diff of every payload PE import vs Wine's export table.

---

## 1. Version table (all measured from the payload)

| component | version | evidence (command) |
|---|---|---|
| Qt | **6.5.11**, MSVC 2019, `x86_64-little_endian-llp64 shared (dynamic) release` | `strings $BIN/Qt6Core.dll \| grep -F 'Qt 6.5.11'` |
| Qt WebEngine / Chromium | **Chromium 122.0.6261.171** | `strings $BIN/Qt6WebEngineCore.dll \| grep -F 'Chrome/'` → `Chrome/122.0.6261.171` |
| V8 | **12.2.281.28** | `strings $BIN/Qt6WebEngineCore.dll \| grep -E '^12\.[0-9]+\.[0-9]+'` |
| ANGLE | **2.1.0** commit `57ea533f79a7`; static imports USER32 + **d3d9**; `\d3d11.dll`, `\dxgi.dll`, `d3dcompiler_{43,46,47}.dll`, `QT_D3DCOMPILER_DLL` present as **UTF-16 strings** (loaded at runtime) | `strings -a $BIN/libGLESv2.dll \| grep 'ANGLE 2.1.0'`; `strings -a -e l $BIN/libGLESv2.dll \| grep -iE 'd3d'`; `objdump -p` |
| SwiftShader | **4.1.0.5** ("OpenGL ES 3.0 SwiftShader 4.1.0.5"), `swiftshader/libGLESv2.dll` 38 434 144 B; imports ADVAPI32/GDI32/USER32/WS2_32/ole32, **no D3D** | `strings -a $BIN/swiftshader/libGLESv2.dll \| grep SwiftShader` |
| Node.js | **v22.17.1**, `NODE_MODULE_VERSION 127`, bundled **OpenSSL 3.0.16**, **ICU 77** (`icu_77` symbols) | `strings -a $BIN/eps/eps.exe \| grep -E 'v22\.17\.1\|NODE_MODULE_VERSION\|OpenSSL [0-9]\|icu_77'` |
| libuv (inside Node 22.17.1) | **1.51.0** (not 1.48 as the brief said) | upstream `deps/uv/include/uv/version.h` @ `v22.17.1` |
| ICU (Qt's, shipped) | **74** (`icudt74.dll`, `icuuc74.dll`, `icuin74.dll`); exact minor UNVERIFIED | `ls $BIN/icu*74.dll` |
| OpenSSL (Tableau's, shipped) | **3.5.6 (7 Apr 2026)** | `strings -a $BIN/libcrypto-3.dll \| grep 'OpenSSL [0-9]'` |
| libcurl | **8.21.0** | `strings -a $BIN/libcurl.dll \| grep -F 'libcurl/'` |
| `yaxcatd.exe` stack | **gRPC 1.52.2** + **Boost 1.80.4** + BoringSSL + zlib 1.2.13; **not Envoy** (§6) | build paths in `strings -a $BIN/yaxcat/yaxcatd.exe` |
| VC runtime / UCRT | MSVC 14.29 (`MajorLinkerVersion 14`, `MinorLinkerVersion 29`), `MSVCP140`/`VCRUNTIME140` + `api-ms-win-crt-*` | `objdump -p $BIN/Qt6Widgets.dll \| head` |

---

## 2. Payload-wide load-time import audit (do this before anything else)

**Procedure** (script kept inline; ~90 s for 280 PEs): parse every `.spec` in the Wine tree into
`dll -> exported names`, parse each payload PE's import table with `objdump -p`, resolve `api-ms-*`/`ext-ms-*`
through `dlls/apisetschema/apisetschema.spec`, and diff. Result in `recon/evidence/load_time_gaps.json`.

Two parser traps that produce **false positives** (both cost me a wrong headline before I checked):
1. `.spec` verbs may carry flags: `@ stdcall -arch=!i386 RtlVirtualUnwind(...)`, `@ varargs wsprintfA(...)`.
   A naive `@ (stdcall|cdecl) Name` regex misses them and reports ~270 bogus "missing" symbols per binary.
2. **Wine's api-set lookup is version-agnostic.** `get_apiset_entry()` (`dlls/ntdll/loader.c:685-724`) hashes the
   name only up to its **last `-`**, then compares exactly that many characters. So
   `api-ms-win-core-synch-l1-2-0` resolves to the `-l1-2-1` entry, `api-ms-win-core-realtime-l1-1-1` to
   `-l1-1-0`, `api-ms-win-core-winrt-string-l1-1-0` to `-l1-1-1`. Consequences: a name absent from
   `dlls/apisetschema/apisetschema.spec` is **not** automatically a load failure. Verified by probe:

```
# /tmp/apisetprobe/probe.exe: static import WaitOnAddress from api-ms-win-core-synch-l1-2-0.dll
LoadLibraryW(api-ms-win-core-synch-l1-1-0.dll)       -> 0x6fffff5e0000  err=0
LoadLibraryW(api-ms-win-core-synch-l1-2-1.dll)       -> 0x6fffff5e0000  err=0
LoadLibraryW(api-ms-win-core-synch-l1-2-0.dll)       -> 0x6fffff5e0000  err=0   # not in the schema!
LoadLibraryW(api-ms-win-core-realtime-l1-1-1.dll)    -> 0x6fffff5e0000  err=0   # not in the schema!
LoadLibraryW(api-ms-win-core-winrt-string-l1-1-0.dll)-> 0x6fffffcda0000  err=0   # not in the schema!
```

**Result of the corrected audit: exactly two genuine gaps, zero unresolved api-sets.**

| missing export | imported by | Wine state |
|---|---|---|
| `USERENV.dll!DeriveAppContainerSidFromAppContainerName` | `bin/Qt6WebEngineCore.dll`, `bin/QtWebEngineProcess.exe` | absent from `dlls/userenv/userenv.spec` (Wine's only AppContainer export is `CreateAppContainerProfile`, spec line 3) |
| `USER32.dll!SkipPointerFrameMessages` | `bin/plugins/platforms/qwindows.dll` | commented out in `dlls/user32/user32.spec:1142` (`# @ stub …`) |

**What Wine does with an unresolved import (measured, not guessed).** The module still **loads**; the loader
binds the IAT slot to an abort-thunk, not a failure: `allocate_stub()` (`dlls/ntdll/loader.c:1207,1213,1234,1250`)
emits a thunk calling `stub_entry_point()` (`loader.c:381-395`), which raises non-continuable
`EXCEPTION_WINE_STUB` (dispatch/message at `dlls/ntdll/exception.c:246-254`). Probe (a PE statically importing
`userenv.dll!DeriveAppContainerSidFromAppContainerName`) run under Wine:

```
static import resolved at 00000001400014e0
wine: Call from 00006FFFFFD0EFFC to unimplemented function
      userenv.dll.DeriveAppContainerSidFromAppContainerName, aborting
```

So the symptom is **not** `ERROR_PROC_NOT_FOUND` at load; it is an abort **on first call**, i.e. only if that
code path is reached. See §4 for when Chromium reaches it and the probe command in §8.

---

## 3. Qt 6.5.11 (Windows QPA) — API families

Upstream: `https://raw.githubusercontent.com/qt/qtbase/6.5/src/plugins/platforms/windows/<file>`.

| family | upstream file / function | Win32 used | Wine 11.18 | symptom under Wine |
|---|---|---|---|---|
| DWM frame/composition | `qwindowswindow.cpp:3288-3307` (`queryDarkBorder`/`setDarkBorder`), `qwindowscontext.cpp:917` | `DwmGetWindowAttribute(DWMWA_USE_IMMERSIVE_DARK_MODE)`, `DwmSetWindowAttribute` | `dwmapi_main.c:185` implements **only** `DWMWA_EXTENDED_FRAME_BOUNDS`, else `FIXME`+`E_NOTIMPL`; `:101` `DwmSetWindowAttribute` is a **FIXME stub returning `S_OK`** | Query fails (`qCWarning` "Unable to retrieve dark window border setting"); the *write* silently "succeeds" → dark title bar never appears, **no warning** (nastiest failure to diagnose) |
| DWM blur | `qwindowswindow.cpp:440-454` (`applyBlurBehindWindow`) for `WA_TranslucentBackground` | `DwmEnableBlurBehindWindow` | `dwmapi_main.c:163` `FIXME`, returns `E_NOTIMPL` | Translucent toplevels get no blur; usually an opaque/black background |
| DWM composition state | `qwindowscontext.cpp` (WM_DWM*CHANGED) | `DwmIsCompositionEnabled` | `dwmapi_main.c:39-53` returns TRUE for reported OS ≥ 6.3; default Wine prefix reports Win10 → **TRUE** | Qt takes the "composition is on" path even though every composition call above is a stub |
| `SetWindowCompositionAttribute` (mica/acrylic) | **no Qt 6.5 call site** | — | `user32/win.c:1602` `FIXME` stub, `ERROR_CALL_NOT_IMPLEMENTED`, returns FALSE; `GetWindowCompositionAttribute` `@ stub` | Not exercised by stock Tableau 2026.2.3. `DwmExtendFrameIntoClientArea` is likewise **not called by Qt 6.5** (`dwmapi_main.c:69` is a stub returning `S_OK`, so it would be harmless anyway) |
| touch | `qwindowsmousehandler.cpp:579-633` (`translateTouchEvent`) | `GetTouchInputInfo`, `CloseTouchInputHandle` | `user32/input.c:657` `FIXME` returns FALSE; `:647` stub; backing `NtUserGetTouchInputInfo` is a `SYSCALL_STUB` (`dlls/win32u/win32syscalls.h:3852`) | Touch support dead (no touch device exists in Wine anyway) |
| touch registration | `qwindowswindow.cpp:3420-3441` | `RegisterTouchWindow`, `UnregisterTouchWindow` | `user32/input.c:676` stub **returning TRUE**, `:685` stub | "Succeeds", registers nothing; Wine never synthesises WM_TOUCH |
| pointer | `qwindowspointerhandler.cpp` (`translatePointerEvent`), `qwindowspointerhandler.cpp:522` | `GetPointerType`, `GetPointerDeviceRects`, `GetPointerFrameTouchInfo*`, `SkipPointerFrameMessages` | `GetPointerType`/`GetPointerInfoList` real (`win32u/input.c:3109,3135`; FIXME for types ≠ `PT_POINTER`); `GetPointerDevices` partial stub (`user32/misc.c:473`); **`SkipPointerFrameMessages` absent → abort-stub** | `SkipPointerFrameMessages` is called only inside Qt's **touch** frame loop (`qwindowspointerhandler.cpp:522`), i.e. never on mouse input (Qt 6.5 never calls `EnableMouseInPointer`; Wine's mouse→`WM_POINTER` translation is gated on it, `win32u/message.c:2645`/`input.c:2773`). Latent abort, reachable only if a touch/pen pointer frame is delivered |
| IME | `qwindowsinputcontext.cpp:53-527` | `ImmGetContext`, `ImmSetCompositionWindow`, `ImmGetCompositionString`, `ImmAssociateContextEx`, … | **functional**: `imm32/imm.c:1770,2350,1031,2646,1742`; backend `winex11.drv/xim.c:145,574` (XIM) | Works when the host X server has XIM/IBus; without it, no composition events (no crash) |
| clipboard / OLE | `qwindowsclipboard.cpp:84,293,312`; `qwindowscontext.cpp:182` (`OleInitialize`) | `OleGetClipboard`/`OleSetClipboard`/`OleFlushClipboard`, `RegisterClipboardFormat` | **functional**: `ole32/clipboard.c:2179,2233,2277`; X11 bridge in `winex11.drv/clipboard.c` | Text/HTML/PNG copy-paste works; exotic `TYMED_IStorage` gaps (`clipboard.c:51-55`) |
| tray | `qwindowssystemtrayicon.cpp:321-334,193` | `Shell_NotifyIcon`, `Shell_NotifyIconGetRect` | `shell32/systray.c:207` requires a `Shell_TrayWnd` host window (default Wine prefix has none) → returns FALSE; `:299` `GetRect` `FIXME` `E_NOTIMPL` | No tray icon at all in a bare prefix |
| taskbar badge | `qwindowsintegration.cpp:770-791` | `CoCreateInstance(CLSID_TaskbarList)`, `ITaskbarList3::SetOverlayIcon` | CLSID served by `dlls/explorerframe` (`explorerframe_main.c:174`), but every method is a `FIXME` stub "faking success" (`taskbarlist.c:139-250`) | Badge/progress/thumb buttons are no-ops (no crash) |
| dark mode | `qwindowstheme.cpp:1079-1087` reads `…\Themes\Personalize\AppsUseLightTheme` | plain `RegGetValueW` | registry read fine; uxtheme `.132 ShouldAppsUseDarkMode`/`.138 ShouldSystemUseDarkMode` functional (`uxtheme/system.c:1288,1271`); `.133/.135/.136/.137` stubs (`:1303,1313,1323,1332`) | Qt 6.5 does not call the stub ordinals; dark *palette* works, dark *frame* does not (DWM, above) |
| high DPI | `qwindowscontext.cpp:380-409,844` | `SetProcessDpiAwarenessContext`, `SystemParametersInfoForDpi`, `GetSystemMetricsForDpi`, `GetDpiForWindow`, `GetDpiForMonitor` | all real: `user32/sysparams.c:691`→`win32u/sysparams.c:7472`; `user32/win.c:627`→`win32u/window.c:1220` (`get_dpi_for_window`, real per-monitor); `user32/sysparams.c:408`; `shcore/main.c:77` | Works; two caveats: awareness is **first-write-wins** (`ERROR_ACCESS_DENIED` on the second call), and under X11 the DPI comes from the X server |
| fonts | `qwindowsfontdatabasebase.cpp:546-565` | `DWriteCreateFactory` | real: `dwrite/main.c:2267` (~35 kLOC, incomplete but functional) | Works |
| D2D paint engine | **removed in Qt 6.5** (`qwindowsdirect2dpaintengine.cpp` no longer exists) | — | `d2d1/factory.c` `D2D1CreateFactory` exists regardless | Not a risk area for 6.5 |
| D3D11 RHI shaders | `src/gui/rhi/qrhid3d11.cpp:4215,4292` | `D3DCompile` (`D3DCompiler_47`) | real: `d3dcompiler_43/compiler.c:342` → vkd3d HLSL frontend (`:335`); `d3dcompiler_47` is the same source with `-DD3D_COMPILER_VERSION=47` (`d3dcompiler_47/Makefile.in`) | Works for SM≤5 in principle; the payload ships only an **i386** `d3dcompiler_47.dll`, so the x64 processes load Wine's builtin |
| OpenGL | `qwindowsglcontext.cpp:952-962` | `wglGetProcAddress`, `wglCreateContextAttribsARB` | real: `opengl32/wgl.c:1075` (GLX-backed in `winex11.drv/opengl.c`) | Works with a working host GL stack |
| screens | `qwindowsscreen.cpp:380,53-260` | `EnumDisplayMonitors`, `QueryDisplayConfig`, `DisplayConfigGetDeviceInfo` | real (`win32u/sysparams.c:3503,3708,7748`); `GET_SDR_WHITE_LEVEL` **unimplemented** (`win32u/sysparams.c:7988`) | Monitor list/EDID fine; HDR white level silently falls back to 200.0 (`qwindowsscreen.cpp:103`) |

Net for Qt: **nothing in the Qt layer aborts the process**. The damage is cosmetic (DWM frame/blur, tray,
taskbar, pointer/touch) — with the single latent exception of `SkipPointerFrameMessages` (touch frame only).

---

## 4. Chromium 122 / Qt WebEngine

Upstream: `https://chromium.googlesource.com/chromium/src/+/refs/branch-heads/6261/<path>` (add `?format=TEXT`
for base64; `?format=JSON` lists directories).

### 4.1 Sandbox surface

| API | Chromium 122 file | Wine 11.18 | consequence |
|---|---|---|---|
| `NtCreateLowBoxToken` | `sandbox/win/src/app_container_base.cc`, `base/win/access_token.cc` | **stub**: `ntdll/unix/security.c:744` — `FIXME`, sets `*token_handle = NULL`, returns `STATUS_SUCCESS` | A "successful" lowbox token that is NULL; any later use is meaningless. Not a crash by itself |
| `CreateAppContainerProfile` | `app_container_base.cc:34` (`CreateProfile`) | **stub**: `userenv/userenv_main.c:690` returns `E_NOTIMPL` | `CreateProfile` returns nullptr (the `ERROR_ALREADY_EXISTS`→`Open()` fallback is only for a *successful* create) |
| `DeriveAppContainerSidFromAppContainerName` | `app_container_base.cc:51` (`Open`) | **absent** → abort-stub (§2) | Aborts the process **if called** |
| `DeleteAppContainerProfile`, `GetAppContainerFolderPath` | `app_container_base.cc` (`Delete`), path service | **absent** | same |
| `Set/GetProcessMitigationPolicy` | `sandbox/win/src/process_mitigations.cc` | **stubs returning TRUE**: `kernelbase/process.c:1277,933` | Chromium's `PCHECK` does not fire; no mitigation applied. This is *good* under Wine |
| jobs: `CreateJobObject`, `SetInformationJobObject(kLockdown ⇒ ExtendedLimit + BasicUIRestrictions)`, `AssignProcessToJobObject` | `sandbox/win/src/job.cc`, `sandbox/win/src/sandbox_policy_base.cc` | jobs real; `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` enforced (`server/process.c:350`); all flags Chromium uses pass validation (mask `0x7fff`, `include/winnt.h:6797`); `JobObjectBasicUIRestrictions` is **accepted and ignored** (`ntdll/unix/sync.c:1612-1617`: `status = STATUS_SUCCESS; /* fall through */ FIXME`) | Children die with the broker (good); UI restrictions are not enforced (sandbox weaker, not broken) |
| window station / desktop | `sandbox/win/src/alternate_desktop.cc`, `window.cc` | real: `user32/winstation.c:148,251`; `win32u/winstation.c:448,466,577,606`; `server/winstation.c:584,674,740` | Alternate desktop is created but maps onto the same X display → nominal isolation only |
| crosscall IPC (shared memory + events) | `sandbox/win/src/sharedmem_ipc_server.cc`, `crosscall_server.cc` | real | works |
| Mojo named pipes | `mojo/public/cpp/platform/named_platform_channel_win.cc`, `platform_channel_server_win.cc` | real: `kernelbase/sync.c:1379,1350`; `STATUS_PIPE_CONNECTED`→`ERROR_PIPE_CONNECTED` (`server/named_pipe.c:1263`). `PIPE_REJECT_REMOTE_CLIENTS` ignored (harmless); `ImpersonateNamedPipeClient` impersonates the **wrong** token (`server/named_pipe.c:1311` FIXME) | Channels work; impersonation-dependent code sees the server's own identity |
| shared memory (`Local\`, `Global\`) | `base/memory/shared_memory_win.cc` | `kernelbase/sync.c:1032`; names are literal children of `\Sessions\<id>\BaseNamedObjects` (`:60,89`) | Works as long as both ends use the identical literal name (they do) |

**Crucial default-state fact (measured upstream, M122):** `kRendererAppContainer` and `kGpuAppContainer` are
`base::FEATURE_DISABLED_BY_DEFAULT` (`sandbox/policy/features.cc:53-55, 63-65`), and
`sandbox/policy/win/sandbox_win.cc:662-668` only reaches `CreateAppContainerProfile`/`Open` via
`IsAppContainerEnabledForSandbox()` (which returns those flags, `:878-888`). The **default** renderer policy is
`SetJobLevel(kLockdown, …)` + integrity levels (`:640,690`) — all of which Wine implements or ignores benignly.
So the AppContainer abort is a **landmine that arms when the feature is enabled**, not the default startup path.
Enabling it (e.g. `--enable-features=RendererAppContainer`) makes Wine abort the process at
`DeriveAppContainerSidFromAppContainerName` (or fail at `CreateAppContainerProfile` = `E_NOTIMPL`).

### 4.2 GPU path

| API | Wine 11.18 | consequence |
|---|---|---|
| `CreateDXGIFactory2` | `dxgi/dxgi_main.c:56` — ignores all flags (`DXGI_CREATE_FACTORY_DEBUG` unsupported) | fine unless the debug layer is requested |
| `IDXGIFactory::EnumAdapters`/`GetDesc` | real (`dxgi/factory.c`, `dxgi/adapter.c`) | adapter/LUID enumeration works via wined3d |
| `D3D11CreateDevice` | real (`d3d11/d3d11_main.c:287`); default feature-level list caps at `D3D_FEATURE_LEVEL_11_0` (`:149`, scout-reported) | device creation OK at FL11_0; no 11_1/12 |
| `D3DCompile` | real, via vkd3d HLSL (`d3dcompiler_43/compiler.c:342,335`) | Chromium/ANGLE shader compilation may fail on HLSL constructs vkd3d doesn't accept → GPU init failure → software fallback |
| ANGLE (`libEGL.dll`/`libGLESv2.dll` shipped by Qt) | the payload's ANGLE (2.1.0) statically imports **d3d9** and loads `d3d11.dll`/`dxgi.dll`/`d3dcompiler_4*.dll` by name at runtime | goes through Wine's d3d11→wined3d→GL (or the d3d9 path); needs a usable host GL/Vulkan driver |
| SwiftShader 4.1.0.5 (shipped) | pure CPU, imports no D3D | the software fallback that should save the GPU process when everything else fails |
| display/DPI (`EnumDisplayDevices`, `GetSystemMetricsForDpi`, `GetDpiForMonitor`) | real | fine |

### 4.3 Practical consequences for `QtWebEngineProcess.exe --type=renderer|gpu-process`

- Qt WebEngine adds **no** `--no-sandbox` on Windows; disable via `QTWEBENGINE_DISABLE_SANDBOX=1` or
  `QTWEBENGINE_CHROMIUM_FLAGS=--no-sandbox` (Qt 6.5 platform notes).
- With the sandbox on (default) Wine implements the pieces the *default* policy uses (jobs, integrity, token
  duplication, named pipes, shared memory, alternate desktop), and the mitigation policies that are stubbed
  return TRUE so no `PCHECK` fires. Expect it to start, but with no real isolation.
- The abort landmine is armed by `--enable-features=RendererAppContainer` / `GpuAppContainer` (or by a Chrome
  version that flips the defaults). Watch for `unimplemented function userenv.dll.DeriveAppContainerSidFromAppContainerName`.
- The GPU process is the likely first real casualty (ANGLE/D3D11 through wined3d, vkd3d HLSL), with
  SwiftShader as the fallback; `--disable-gpu` / `QSG_RHI_PREFER_SOFTWARE_RENDERER` are the safety valves.
- `PowerRegisterSuspendResumeNotification` (`powrprof` FIXME stub returning `0xdeadbeef`) and
  `RegisterSuspendResumeNotification` (`user32/misc.c:428` stub) are called by `base::PowerMonitor`; bogus
  handle, no crash.

---

## 5. Node.js 22.17.1 (`eps/eps.exe`) — libuv 1.51.0 on IOCP

Upstream: `https://raw.githubusercontent.com/nodejs/node/v22.17.1/deps/uv/src/win/<file>`.

Measured import table (`recon/evidence/symbol_imports.txt`, `objdump -p eps/eps.exe`): `CreateIoCompletionPort`,
`GetQueuedCompletionStatusEx`, `PostQueuedCompletionStatus`, `GetStdHandle`, `SetConsoleMode`,
`GetConsoleMode`, `GetNumberOfConsoleInputEvents`, `ReadConsoleInputW`, `PeekNamedPipe`, `CreateNamedPipeW`,
`ConnectNamedPipe`, `SetNamedPipeHandleState`, `GetOverlappedResult`, `CancelIoEx`, `CreateProcessW`,
`CreateJobObjectW`, `SetInformationJobObject`, `AssignProcessToJobObject`, `ResumeThread`, `ReadFile`,
`WriteFile`, `SetFileCompletionNotificationModes`, `GetFinalPathNameByHandleW`, `SetFileInformationByHandle`,
`DeviceIoControl`, `CreateSymbolicLinkW`, `GetFileInformationByHandleEx`, `WSARecv`/`WSASend`/
`WSAGetOverlappedResult`/`WSAIoctl`, `SystemFunction036`, dbghelp (`SymInitialize`, `StackWalk64`,
`MiniDumpWriteDump`). **No `NtReadFile`/`NtWriteFile`** (libuv uses kernel32 + `NtQuery/NtSetInformationFile`).

| libuv site (v22.17.1) | API | Wine 11.18 |
|---|---|---|
| `core.c:230,449,169` | `CreateIoCompletionPort`, `GetQueuedCompletionStatusEx`, `PostQueuedCompletionStatus` | real: `kernelbase/sync.c:1214,1280,1303` (`NtRemoveIoCompletionEx`, not a stub) |
| `handle.c:30-52` (`uv_guess_handle`) | `GetFileType` + `GetConsoleMode` | real (`kernelbase/file.c:3318`, `kernelbase/console.c:932`) |
| `tty.c:170,188,735,753` | `CONOUT$`/`CONIN$`, `GetConsoleScreenBufferInfo`, `SetConsoleMode`, `ReadConsoleInputW` | real (condrv ioctls; `kernelbase/console.c:301,1624,1019,1813`) |
| `pipe.c:533,318,1097,470` | `CreateNamedPipeW`, overlapped `ConnectNamedPipe`, `SetNamedPipeHandleState` | real; `STATUS_PIPE_CONNECTED` handled (`server/named_pipe.c:1263`); fd-backed pipes fixed by patch 0003 |
| `pipe.c:1884-1960,1374` | overlapped/sync/zero-length `ReadFile`, `GetOverlappedResult`, `CancelIoEx` | real (`kernelbase/file.c:3623,4026`; `ntdll/unix/file.c:6115,6416`) |
| `pipe.c:1933` | `PeekNamedPipe` | real (`kernelbase/sync.c:1581`) |
| `process.c:871-1086` | `CreateProcessW` + `STARTUPINFO` (plain, **no** `PROC_THREAD_ATTRIBUTE_HANDLE_LIST`), `CREATE_SUSPENDED`, `ResumeThread`, **and a job object** (`process.c:94-104,1068`) | all real; jobs fine |
| `process-stdio.c:76-111,146` | `GetStdHandle`, `SetHandleInformation`, `DuplicateHandle`, `NUL` | real |
| `fs.c:2241,2857,2916` | `MoveFileExW`, `CreateSymbolicLinkW`, `GetFinalPathNameByHandleW`; fs metadata via `NtSetInformationFile` (not `SetFileInformationByHandle`) | real |
| `tcp.c:489,896` / `winsock.c:44` | overlapped `WSARecv`/`WSASend`; `WSAIoctl(SIO_GET_EXTENSION_FUNCTION_POINTER)` for `AcceptEx`/`ConnectEx` | real (`ws2_32/socket.c:2655,2664-2667,1422,944`) |
| `poll.c:292` | **WinSock `select()`** (not `WSAPoll`) | real |
| `getaddrinfo.c:89` | `GetAddrInfoW` | real |
| `util.c:65,1140,1537,450,1684` | `SystemFunction036` (RtlGenRandom), `GetUserNameW`, `RtlGetVersion`, `QueryPerformanceCounter`, `GetSystemTimeAsFileTime` | real (`cryptbase/cryptbase_main.c:61`) |
| `signal.c:43` | `SetConsoleCtrlHandler` | real |

### 5.1 The piped-stdout `EBADF` — already fixed by this project's patch series

`uv_pipe_open` → `SetNamedPipeHandleState` → `NtSetInformationFile(FilePipeInformation)`; stock Wine answered
`STATUS_OBJECT_TYPE_MISMATCH` for an fd-backed Unix pipe → `ERROR_INVALID_HANDLE` → `UV_EBADF`. The union tree
already carries the two fixes:
- `patches/0002-server-completion-info-non-overlapped.patch` — `server/fd.c`: `set_completion_info` no longer
  requires `is_fd_overlapped()`, so `CreateIoCompletionPort` succeeds on inherited non-overlapped std handles.
- `patches/0003-ntdll-fd-backed-pipe-semantics.patch` — `dlls/ntdll/unix/file.c`: accept `FilePipeInformation`
  byte mode, `FSCTL_PIPE_PEEK` via `FIONREAD`, zero-length read waits (no 100 % CPU spin).

Both are applied (e.g. `fd_is_unix_pipe()` at `dlls/ntdll/unix/file.c:5204`; patched gate at `server/fd.c:3165`).
Prior-art note: `/home/asdf/projects/acad-wine-main/README.md:182-183` still lists this as an *unresolved* limit
("`AdskAccessUIHost.exe` … hits an unresolved Node/libuv stdio problem under Wine (`EBADF` on a piped stdout)")
— that text is **stale**: the repo's own patches 0008/0009 (this project's 0002/0003) carry the before/after
evidence (`node -e "console.log('x')" | cat` → EBADF before, `x` after).

**Verdict: the one concrete Node failure mode on record is COVERED.** Everything else in the libuv surface is
stock Wine with no project patch and no measurement either way — notably console/TTY (`ReadConsoleInputW`,
condrv), `uv_spawn` + the job object, and `select()`-based polling.

---

## 6. `bin/yaxcat/yaxcatd.exe` — **not Envoy**; it is Tableau's own gRPC/Asio server

Correction, with evidence (the brief assumed Envoy; it is not):

| evidence | value |
|---|---|
| Build paths in the binary | `C:\builds\algernonteam\yaxcat\server\aggmodel_service.cc`, `…\yaxcat\aggmodel\gp\{model,data,kernel,likelihood,line_search}.cc`, `…\aggmodel/model_xy.cc`, `…\aggmodel\measure_model.cc` |
| deps under `C:/builds/algernonteam/yaxcat/_deps/` | `grpc-cmake-src/1.52.2/…`, `boost-src/1.80.4/…`; and `C:/builds/vizqlserver/grpc-cmake-build/_deps/grpc-src/third_party/boringssl-with-bazel/…` |
| CLI switches it implements | `--port-file`, `--health-check-port`, `--worker-threads`, `--server-config-file`, `--metadata`, `--password`, `--auto-exit`, `--log-rotate-seconds`, `--verbose`, `--version` |
| log/format strings | `yaxcatd (%s) built at %s listening on %s with %u worker threads.`, `Could not start yaxcatd gRPC service.`, `Starting gRPC health check service listening on `, `Creating channel to ping aggmodel at localhost:` |
| Envoy source paths | **none** (`envoy/source/...` absent). The `envoy…` strings are protobuf **descriptor names** vendored by gRPC 1.52.2 for xDS (`envoy/api/v2/…`, `EnvoyGrpc`, `EnvoyMobileHttpConnectionManager`) |
| symbol imports | IOCP trio, `CreatePipe`, overlapped `WSARecv`/`WSASend`/`WSAConnect`/`WSASocketA`, `WSAIoctl`, `WSAGetOverlappedResult`, `SetHandleInformation`, `CreateProcessA`, `SystemFunction036`, `BCryptGenRandom`, `GetVersionExA`, `GetLogicalProcessorInformation`, `dbghelp` (`SymFromAddr`, `RtlLookupFunctionEntry`, `RtlVirtualUnwind`), MSVC STL/CRT. **No `mswsock`, no CRYPT32/NCrypt/secur32** |

So the "Envoy version" question is moot; the relevant upstreams are **gRPC 1.52.2 iomgr**, **Boost.Asio 1.80.4**
and **BoringSSL**.

| API | upstream | Wine 11.18 | consequence |
|---|---|---|---|
| IOCP: `CreateIoCompletionPort`, `GetQueuedCompletionStatus(Ex)`, `PostQueuedCompletionStatus` | grpc `src/core/lib/iomgr/iocp_windows.cc`, asio `win_iocp_*` | real | works |
| overlapped sockets `WSARecv`/`WSASend`/`WSAConnect` | grpc `tcp_windows.cc` | real | works |
| `WSAIoctl(SIO_GET_EXTENSION_FUNCTION_POINTER)` → `AcceptEx`/`ConnectEx`/`DisconnectEx` | grpc `socket_windows.cc`, asio `win_iocp_socket_service_base.hpp` | real: `ws2_32/socket.c:2655`, table `:2664-2667` (`WS2_ConnectEx` `:1422`, `WS2_AcceptEx` `:944`); unknown GUIDs → `WSAEINVAL` | works — and this must be the path used, since yaxcatd does not import `mswsock` |
| `SetFileCompletionNotificationModes` | asio | real (`kernel32/file.c:255`) | works |
| `BCryptGenRandom`, `SystemFunction036` | BoringSSL `CRYPTO_sysrand` | real (`bcrypt/bcrypt_main.c:571` → `RtlGenRandom`; `cryptbase/cryptbase_main.c:61`) | works |
| dbghelp crash handler (`SymInitialize`, `StackWalk64`, `SymFromAddr`, `MiniDumpWriteDump`) | yaxcat's own crash handler | real (`dbghelp/dbghelp.c:454,521`; `stack.c:216`; `minidump.c:1022`); all `SymSrv*` are `@ stub` → **no symbol-server download, no hang** | works, degraded symbols |
| **AF_UNIX** (`SOCKADDR_UN`) — used if yaxcatd is configured with a Unix-domain endpoint | n/a for gRPC's default TCP iomgr, but the xDS/Envoy `Pipe` address type is AF_UNIX (`source/common/network/address_impl.cc`) | **NOT IMPLEMENTED**: `include/afunix.h:33`/`ws2def.h:40` define the constants, but `family_map` in `ws2_32/unixlib.c:139-150` has **no AF_UNIX**, `union unix_sockaddr` (`:480-491`) has no `sun_path` member, and upstream marks it `todo_wine win_skip("AF_UNIX sockets not supported")` (`ws2_32/tests/sock.c:14913-14919`) | Measured on the probe: `socket(AF_UNIX, SOCK_STREAM, 0)` → `-1`, `WSAGetLastError()=10047` (`WSAEAFNOSUPPORT`); `socket(AF_INET)` → valid. Any UDS/pipe-address listener fails to bind. TCP-only configs are unaffected |

---

## 7. Ranked predicted breakages (with the single confirming experiment for each)

Confidence = how much of the chain I verified myself (mechanism + state), not a probability guess.

| # | prediction | component | expected symptom | Wine code path | single experiment to confirm |
|---|---|---|---|---|---|
| 1 | **AppContainer abort when the feature is enabled** — `DeriveAppContainerSidFromAppContainerName` is bound to an abort-stub; `CreateAppContainerProfile` returns `E_NOTIMPL` | Qt WebEngine / TableauStack (web view) | process aborts: `unimplemented function userenv.dll.DeriveAppContainerSidFromAppContainerName, aborting` (or `SBOX_FATAL` on profile creation) | `ntdll/loader.c:1213,1250`+`:381`; `ntdll/exception.c:246`; `userenv/userenv_main.c:690`; `userenv.spec` | run with `QTWEBENGINE_CHROMIUM_FLAGS=--enable-features=RendererAppContainer` and watch stderr; the standalone probe in §8 reproduces it without the app. **Default M122 has the flag off** (`sandbox/policy/features.cc:63-65`) |
| 2 | **AF_UNIX unsupported** → any UDS/`Pipe` endpoint fails to bind | yaxcatd (if configured with one), any component using `QLocalSocket`-style UDS on Windows | `WSAEAFNOSUPPORT` (10047), server refuses to start / client cannot connect | `ws2_32/unixlib.c:139-150,480-491`; `ws2_32/tests/sock.c:14913-14919` | `WINEDEBUG=+winsock wine /tmp/apisetprobe/afunix.exe` (already run: `err=10047`); in-app: `GRPC_TRACE=tcp,iocp` / `WINEDEBUG=+winsock,+mswsock` |
| 3 | **GPU process fails, web view blank/stalls** — ANGLE D3D11 via wined3d + vkd3d `D3DCompile` may fail; caps stop at FL11_0 | Qt WebEngine | blank page, `GPU process crashed`, or heavy software rendering | `d3d11/d3d11_main.c:287`(+`:149`); `dxgi/dxgi_main.c:56`; `d3dcompiler_43/compiler.c:342,335` | run with `QTWEBENGINE_CHROMIUM_FLAGS="--enable-logging=stderr --v=1"` and look for GPU init/`D3DCompile` failures; compare with `--disable-gpu` (should then use SwiftShader 4.1.0.5) |
| 4 | **Node stdio over a pipe → `UV_EBADF`** | `eps/eps.exe` | `Error: open EBADF` at `new Socket`, exit 1 | *already fixed* by `patches/0002` + `patches/0003` | `wine bin/eps/eps.exe -e "console.log('x')" \| cat` — expect `x`, rc 0; remove patch 0003 to see it fail (before/after in the patch header) |
| 5 | **Residual, unpatched libuv surfaces** (console/TTY condrv, `uv_spawn`+job, `select()` poll) | `eps/eps.exe` | hang or spurious errors in an embedded Node service | stock Wine (`kernelbase/console.c`, `kernelbase/sync.c`) | `wine bin/eps/eps.exe -p "process.stdout.isTTY; require('os').cpus().length"` and an `eps` run with stdout attached to a *console* vs a *pipe* |
| 6 | **Tray icon never appears** | Qt (`qwindows.dll`) | `Shell_NotifyIcon` returns FALSE silently | `shell32/systray.c:207` needs `Shell_TrayWnd` | `WINEDEBUG=+systray` while showing a tray icon; or run under a Wine shell that creates `Shell_TrayWnd` |
| 7 | **Dark title bar silently ignored** | Qt | frame stays light, **no** warning (the API returns `S_OK`) | `dwmapi_main.c:101` (`S_OK` no-op), `:185` (query `E_NOTIMPL`) | `wine tableau.exe -platform windows:darkmode=1` + `WINEDEBUG=+dwmapi`; expect `DwmSetWindowAttribute` traced with no visual change |
| 8 | **Translucent windows render opaque/black** | Qt | no blur behind `WA_TranslucentBackground` | `dwmapi_main.c:163` (`E_NOTIMPL`) | `WINEDEBUG=+dwmapi` on a splash/translucent window |
| 9 | **Touch/pen via WM_POINTER aborts** (only if a touch pointer frame is delivered) | Qt platform plugin | abort at `SkipPointerFrameMessages` | absent export (`user32.spec:1142`), abort-stub (§2) | synthesize a touch pointer frame under Wine (or inject a HID touch device) while running `WINEDEBUG=+relay` limited to `qwindows` |
| 10 | **Named-pipe impersonation gives the wrong identity** | Chromium Mojo / sandboxed child | permission checks behave oddly; nothing crashes | `server/named_pipe.c:1311` (FIXME: duplicates the *current* token) | a two-process probe that creates a pipe, connects, and calls `ImpersonateNamedPipeClient` + `GetTokenInformation(TokenUser)` on both sides (Windows vs Wine) |
| 11 | **Windows-store client certificates unavailable** | Qt WebEngine TLS (`NCrypt`) | TLS client-auth fails for store-backed certs | `ncrypt/main.c:536,543` (`NTE_NOT_SUPPORTED`; scout-reported) | `certprobe`-style comparison on the Windows guest vs Wine |
| 12 | **HDR/SDR white level defaulted** | Qt screens | wrong tone mapping (falls back to 200.0) | `win32u/sysparams.c:7988` returns `STATUS_INVALID_PARAMETER` | `WINEDEBUG=+displayconfig` on a monitor-query path |
| 13 | **Taskbar progress/badge no-ops** | Qt | nothing drawn, no error | `explorerframe/taskbarlist.c:139-250` (FIXME "faking success") | call `ITaskbarList3::SetProgressValue` from a probe and check `WINEDEBUG=+explorerframe` |
| 14 | **Power suspend/resume notifications dead** | Chromium `base::PowerMonitor` | callbacks never fire | `dlls/powrprof/powrprof.c:333` stub returning `0xdeadbeef`; `user32/misc.c:428` (`RegisterSuspendResumeNotification`) is the stub twin (scout-reported line) | `WINEDEBUG=+powrprof` at startup |
| 15 | **`GetFileInformationByHandleEx(FileRemoteProtocolInfo)` unsupported** | Chromium/Node file layer | protocol reported as unknown (graceful) | `kernelbase/file.c` returns `ERROR_INVALID_PARAMETER` (scout-reported) | a one-call probe compared against Windows |
| 16 | **`CreateWaitableTimerExW(HIGH_RESOLUTION)` ignored** | Chromium timers | coarse timer accuracy | `kernelbase/sync.c:870` honours only `MANUAL_RESET` (scout-reported) | probe: create a high-res timer, measure jitter under Wine vs Windows |

Ranking rationale: #1 and #2 are the only *hard* failures with a fully verified mechanism (abort-stub; measured
`WSAEAFNOSUPPORT`), but #1 is gated behind a disabled-by-default Chromium feature, so #2 is the likeliest hard
failure *if* a UDS endpoint is configured. #3 is the likeliest visible failure in the web view. #4 is the one
known Node failure and it is already fixed. #5–#16 are degradations, mostly silent.

---

## 8. Procedure — trace, don't decompile

For any failing component, the sequence is always **upstream source → spec (is it exported?) → implementation
(real or stub?) → probe**. Worked example included.

### 8.1 Find the exact upstream call site

- **Qt 6.5.11** — `github.com/qt/qtbase`, branch `6.5`. Windows-specific code lives in
  `src/plugins/platforms/windows/` (QPA: windows, screens, input, IME, clipboard, tray, theme, pointer,
  tablet) and `src/gui/{rhi,painting,text/windows}` (graphics). Fetch raw files:
  `https://raw.githubusercontent.com/qt/qtbase/6.5/<path>`; then grep for the Win32 symbol you suspect, e.g.
  `grep -n 'SkipPointerFrameMessages\|EnableMouseInPointer\|Dwm[A-Z]' src/plugins/platforms/windows/*.cpp`.
  Each hit gives the file, function and line — that is the answer to "what does Qt call".
- **Qt WebEngine / Chromium 122** — `chromium.googlesource.com/chromium/src/+/refs/branch-heads/6261/<path>`
  (`?format=TEXT` = base64, `?format=JSON` = directory listing; the GitHub `main` mirror is a fallback but note
  the version drift). Sandbox = `sandbox/win/src/*`, policy = `sandbox/policy/win/sandbox_win.cc` and
  `sandbox/policy/features.cc` (**always check the BASE_FEATURE default**), IPC = `mojo/public/cpp/platform/*`,
  GPU = `gpu/config/gpu_info_collector_win.cc` + `ui/gl/*`. Qt WebEngine's own glue is
  `code.qt.io/cgit/qt/qtwebengine.git/plain/src/core/<file>?h=6.5` (`web_engine_context.cpp`,
  `process_main.cpp`, `sandbox_win.cpp`).
- **Node 22.17.1** — `raw.githubusercontent.com/nodejs/node/v22.17.1/deps/uv/src/win/<file>`; the mapping
  "behaviour → file" is stable: `core.c` (IOCP loop), `pipe.c`, `tty.c`/`handle.c` (console & classification),
  `process.c`/`process-stdio.c`/`process-stdio.c` (spawn + job), `fs.c`, `tcp.c`/`winsock.c`/`poll.c`,
  `signal.c`, `util.c`. Node's own bundled deps are versioned in `deps/uv/include/uv/version.h`.
- **gRPC / Asio / BoringSSL** (yaxcatd) — `grpc/grpc` tag `v1.52.2` (`src/core/lib/iomgr/*_windows.cc`),
  `boostorg/asio` tag `boost-1.80.0` (`include/boost/asio/detail/win_iocp_*`).
- **What cannot be traced this way**: Tableau's own binaries. For those, only the *import table*
  (`objdump -p`) is legitimate evidence; do not disassemble.

### 8.2 Is it exported by Wine? Is it real?

```
# 1. exported at all?
grep -n '^\s*@\s\+\S\+\s\+\(-[\w!=]\+\s\+\)*SYMBOL('  wine-11.18/dlls/*/*.spec
#    -> absent/commented ('# @ stub') means the loader will bind an abort-thunk (see §2)
# 2. real or no-op stub?
grep -rn -A20 'SYMBOL' wine-11.18/dlls/<dll>/*.c
#    look for: FIXME(...) + return TRUE/S_OK/E_NOTIMPL, or a real body calling Nt*/winex11
# 3. is there a syscall/SYSCALL_STUB underneath?
grep -n 'SYMBOL' wine-11.18/dlls/win32u/win32syscalls.h
```

### 8.3 Confirm with a probe, on both platforms

Differential probes are the project's established method (`recon/WINDOWS_METHOD.md`): one mingw PE, run under
Wine **and** on the Windows guest (`192.168.122.230`, via the `:8000` hub), diff the output. All three probes
used in this report are in `/tmp/apisetprobe/` and rebuild in seconds:

```
# (a) does a static import from an api-set resolve?  (version-agnostic apiset proof)
x86_64-w64-mingw32-dlltool -d apiset.def -l libapiset.a --dllname api-ms-win-core-synch-l1-2-0.dll
x86_64-w64-mingw32-gcc -o probe.exe probe.c -L. -lapiset && wine probe.exe

# (b) what happens when an imported symbol is not in Wine's userenv?
x86_64-w64-mingw32-gcc -o probe2.exe probe2.c -L. -luserenv_stub && wine probe2.exe
#   -> "wine: Call from ... to unimplemented function userenv.dll.DeriveAppContainerSidFromAppContainerName, aborting"

# (c) AF_UNIX support
x86_64-w64-mingw32-gcc -o afunix.exe afunix.c -lws2_32 && wine afunix.exe
#   -> socket(AF_UNIX,STREAM) = -1  err=10047
```

### 8.4 Then turn on the app's own trace

| component | switch |
|---|---|
| Qt QPA | `QT_LOGGING_RULES="qt.qpa.*=true"` (or `-platform windows:darkmode=1`), plus `WINEDEBUG=+dwmapi,+systray,+uxtheme` |
| Qt WebEngine | `QTWEBENGINE_CHROMIUM_FLAGS="--enable-logging=stderr --v=1"`; `QTWEBENGINE_DISABLE_SANDBOX=1`; `--enable-features=RendererAppContainer` to arm §7-1 |
| Node (`eps.exe`) | its own `--verbose`-style flags, plus `WINEDEBUG=+sync,+file,+pipe` |
| gRPC (yaxcatd) | `GRPC_VERBOSITY=DEBUG GRPC_TRACE=tcp,iocp,event_engine,api`, its `--verbose`, `WINEDEBUG=+winsock,+mswsock,+afd` |
| Wine loader | `WINEDEBUG=+module,+imports` (shows `allocate_stub` / "No implementation for X.Y" warnings) |

### 8.5 Re-run the payload-wide audit

The audit in §2 is reproducible; keep the two parser fixes in mind (flags between verb and name; api-set
version-agnosticism) and re-run it after **every** Wine tree change, because it is the cheapest way to find
new hard-import gaps before launching anything.

---

## 9. Corrections to the brief (all measured)

1. `yaxcatd.exe` is **not Envoy**; it is Tableau's own gRPC 1.52.2 + Boost.Asio 1.80.4 server (§6). Its Envoy
   strings come from gRPC's vendored xDS protos. The relevant open-source upstreams are therefore gRPC, Asio,
   BoringSSL.
2. Node 22.17.1 ships **libuv 1.51.0**, not 1.48, and libuv does **not** call `NtReadFile`/`NtWriteFile`; it
   also uses `SystemFunction036` (not `BCryptGenRandom`), `select()` (not `WSAPoll`), `GetAddrInfoW` (not
   `GetAddrInfoEx*`), `SetConsoleCtrlHandler` (not a hidden message window), and `NtSetInformationFile` (not
   `SetFileInformationByHandle`).
3. The api-set names Wine "lacks" (`…-synch-l1-2-0`, `…-realtime-l1-1-1`, `…-winrt-string-l1-1-0`) all resolve —
   Wine's apiset lookup is version-agnostic (§2). There are **no** unresolved api-sets in the payload.
4. Qt 6.5 does **not** call `SetWindowCompositionAttribute`, `DwmExtendFrameIntoClientArea`, uxtheme dark-mode
   ordinals, or Direct2D; those were listed as risks in the brief but have no call site in 6.5. The real Qt
   composition gap is `DwmSetWindowAttribute` (silent `S_OK` no-op) and `DwmEnableBlurBehindWindow` (`E_NOTIMPL`).
5. Chromium 122's `kRendererAppContainer`/`kGpuAppContainer` are **disabled by default**
   (`sandbox/policy/features.cc:53-55,63-65`), so the AppContainer code path (and the missing
   `DeriveAppContainerSidFromAppContainerName`) is a landmine reached only when the feature is enabled — not the
   default startup path. `sandbox/win/src/{ipc_pipe,named_pipe,lowbox_token,mitigation_policy}.cc` do not exist
   at M122 (crosscall IPC is shared memory + events; the pipes are Mojo's).
6. The AutoCAD README's "unresolved Node/libuv stdio `EBADF`" note (`README.md:182-183`) is **stale** — the fix
   is in that repo's own patches and in this project's `patches/0002`+`0003`.

## 10. UNVERIFIED items

- Exact ICU minor version of Qt's `icuuc74.dll` (only major 74 measured) and whether Node's ICU 77 affects
  anything here.
- `d3d11/d3d11_main.c:149` feature-level cap, `dlls/kernelbase/file.c` `FileRemoteProtocolInfo` return
  (`:3864`), `user32/misc.c:428` `RegisterSuspendResumeNotification`, and `CreateWaitableTimerExW`'s
  `HIGH_RESOLUTION` handling (`kernelbase/sync.c:870`) are **scout-reported**; I verified the neighbouring code
  and the other cited lines (jobs, uxtheme ordinals, `GET_SDR_WHITE_LEVEL`, `GetPointerDevices`, `ncrypt`,
  `powrprof`, `dbghelp`) directly.
- Whether Wine's `SetProcessDpiAwarenessContext` first-write-wins rejects Qt's call on a *default* prefix (it
  depends on whether the manifest/winecfg set a context first).
- Whether `CoCreateInstance(CLSID_TaskbarList)` reaches `explorerframe.dll` in a default prefix (shdocvw
  forwards the CLSID, `shdocvw_main.c:81`; `explorerframe.dll` is not in `loader/wine.inf.in`'s register list).
- Whether yaxcatd's actual runtime configuration uses a UDS/`Pipe` endpoint (its `--server-config-file` content
  was not available); only then does prediction #2 bind for it.
- The behaviour of `uv_spawn`'s job object and console/TTY paths for `eps.exe` (no measurement taken).
