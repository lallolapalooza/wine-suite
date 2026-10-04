# Qt 5.15.1 / Chromium 80.0.3987.163 → Win32 call index

Hog PC 5.2.1.31 is a **Qt 5.15.1 (MSVC 2019, 32-bit) + QtWebEngine (Chromium
80.0.3987.163)** application. Both are open source, so a Wine trace that shows a
Win32 call failing can be turned into a *source-level* question: read the caller in
Qt or Chromium and check what it expects, instead of disassembling the app.

This document is that index. It contains:

1. where the sources live on disk;
2. a Win32 API → Qt source `file:line` → expectation table;
3. the same cross-check against Wine 11.18 (`.spec` stubs and FIXME-only bodies);
4. the recipe for fetching individual Chromium files at the exact tag, plus the
   Win32 surfaces Chromium's `base/win`, `sandbox/win`, `gpu/`, `content/` and the
   GPU process rely on;
5. a short playbook for "the trace shows call X failing — now what?".

---

## 0. Sixty-second version

| Question | Where to look |
|---|---|
| Qt source for the platform plugin | `/run/media/asdf/Windows/qt-src/qtbase/src/plugins/platforms/windows/` |
| Qt corelib Win32 back-ends | `/run/media/asdf/Windows/qt-src/qtbase/src/corelib/{io,kernel,thread,plugin,text,global,time,codecs}/` |
| Fonts / DirectWrite | `/run/media/asdf/Windows/qt-src/qtbase/src/platformsupport/fontdatabases/windows/` |
| Bundled ANGLE (D3D11/D3D9 GL) | `/run/media/asdf/Windows/qt-src/qtbase/src/3rdparty/angle/` |
| Network / Schannel / Winsock | `/run/media/asdf/Windows/qt-src/qtbase/src/network/` |
| Chromium source (single files, cached) | `/run/media/asdf/Windows/chromium-src/<same path as in the repo>` |
| Canonical Win32 name list (per DLL) | `/run/media/asdf/Windows/qt-src/winapi/winapi-0.3.9/src/{um,shared}/` |
| Wine specs / implementations | `/home/asdf/projects/hog-wine/wine-11.18/dlls/<dll>/` |
| Regenerate everything | §7 |

**The single most important caveat:** Qt is compiled with `UNICODE`, so the Qt
source writes the *base* macro name (`CreateWindowEx`, `RegisterClassEx`,
`SQLDriverConnect`) while Wine implements the `…W` export. The index resolves that
alias and records the token Qt actually wrote.

---

## 1. Where the sources live

| Tree | Path | Version evidence |
|---|---|---|
| Qt base module | `/run/media/asdf/Windows/qt-src/qtbase/` | `.qmake.conf: MODULE_VERSION = 5.15.1`; tarball `qtbase-5.15.1.tar.gz` from the `qt/qtbase` tag `v5.15.1` |
| winapi-rs 0.3.9 | `/run/media/asdf/Windows/qt-src/winapi/winapi-0.3.9/` | canonical per-DLL Win32/COM declaration list (used to catch APIs Wine has no spec entry for) |
| Wine | `/home/asdf/projects/hog-wine/wine-11.18/` | this tree already has `patches/local/0102-*` applied (see §3.3) |
| Chromium 80.0.3987.163 | `/run/media/asdf/Windows/chromium-src/` | only the files actually fetched, mirroring the repo layout; see §4.1 |

Only `qtbase` was downloaded — that is where the Windows platform plugin,
corelib Win32 back-ends, QtNetwork, the Windows font database, the bundled ANGLE
and the SQL drivers live. QtWebEngine's Chromium is *not* in qtbase, which is why
Chromium is handled by single-file fetch instead (§4).

Nothing here modifies the prefix, the Wine trees, or runs the app.

### 1.1 What the shipped Hog PC tree actually loads

Read-only inspection of
`state/work/prefix/drive_c/Program Files (x86)/ETC/HogPC/`:

* `platforms/qwindows.dll` — the `qwindows` QPA plugin (**all** of §2.2 applies);
* `sqldrivers/qsqlite.dll` **only** (no `qsqlodbc.dll`), so the ODBC calls Qt's
  `qsql_odbc.cpp` performs are indexed for completeness but are **not reached by
  this installer**; `QSqlDatabase` goes through the bundled SQLite;
* `Qt5Quick*.dll`, `Qt5Qml*.dll`, `QtWebEngineCore.dll`, `QtWebEngineProcess.exe`,
  `resources/qtwebengine_resources*.pak`;
* `imageformats/` (gif/ico/jpeg/pdf/svg/tga/tiff/wbmp/webp), `webview/qtwebview_webengine.dll`.

**Observation (verify against a live trace).** The staged tree contains **no**
`libEGL.dll`, `libGLESv2.dll`, `opengl32sw.dll` or `vk_swiftshader*.dll`. Qt's own
Windows packages normally ship those for ANGLE/software GL. If they are really
absent at runtime, the expected trace is:
`LoadLibraryW("libEGL.dll") → NULL`, `LoadLibraryW("libGLESv2.dll") → NULL`,
`LoadLibraryW("opengl32sw.dll") → NULL`, and Qt/Chromium falling back to the
*desktop* GL path — i.e. Wine's `opengl32.dll` — or to software compositing.
Those `NULL` returns are then **not Wine bugs**; they are the documented fallback
chain. `d3dcompiler_47.dll` *is* present (`C:\windows\system32`, Wine builtin), so
Chromium's `LoadLibrary("d3dcompiler_47.dll")` succeeds. `[INFERENCE]` for the
fallback behaviour; the file absence itself was observed directly.

---

## 2. Qt 5.15.1 → Win32 index

### 2.1 How the index was produced

Tool: `tools/qt_win32_index.py` (regenerate in §7). Method:

1. build the candidate API set from **(a)** all named exports of the Windows API
   DLLs in Wine's `.spec` files, **(b)** the canonical winapi-rs declaration list,
   **(c)** a curated list of the APIs this app's Qt/Chromium build is known to
   reach. Symbol names exported `-noname` (ordinal-only) are excluded — a
   same-named Qt member call is then not evidence of a Win32 call.
2. scan the scoped Qt sources for those identifiers, accepting an occurrence only
   in a plausible use context: `::`-qualified, `Name(`, or a long unambiguous
   name; occurrences inside string literals are handled separately (§2.4);
   comment/Doxygen lines are skipped; C-runtime identifiers are denied.
3. map base macro names to their `…W` export (UNICODE build) and record the token
   Qt actually wrote.
4. resolve each API against Wine's `.spec` files (implemented / forwarded /
   `@ stub` / absent).

Scope scanned (386 files): the whole `qwindows` platform plugin (window creation,
DPI, GL/EGL/Vulkan, clipboard, MIME, drag&drop, session, system tray, tablet,
input context, theme, UI Automator), `platformsupport/fontdatabases/windows`,
corelib Windows back-ends (`qeventdispatcher_win`, `qcoreapplication_win`,
`qlibrary_win`, `qfilesystem*_win`, `qsettings_win`, `qstandardpaths_win`,
`qprocess_win`, `qthread_win`, `qmutex_win`, `qwaitcondition_win`,
`qsystemsemaphore_win`, `qsharedmemory_win`, `qwinregistry`, `qwindowscodec`,
`qtimezoneprivate_win`, `qcollator_win`, `qlocale_win`,
`qoperatingsystemversion_win`), `gui/kernel/qguiapplication.cpp`,
`gui/painting`, `gui/rhi` (D3D11 backend), `gui/vulkan`, `gui/image/qpixmap_win`,
`network/**` (native socket engine, interface/DNS/proxy, SSL/Schannel/DTLS),
`platformsupport/windowsuiautomation`, and the bundled ANGLE D3D renderers.

Non-Windows back-ends shipped next to them (`*_unix.cpp`, `*_winrt.cpp`,
`*_mac.cpp`, …) are excluded; they contain the same POSIX names and would be pure
noise.

Result: **<!--B:STATS_QT-->820 APIs referenced from 386 Qt files, resolved against Wine: 1 absent, 371 forward, 433 impl, 15 not-an-export; 82 APIs also have a dynamic (`resolve`/`GetProcAddress`) site, 38 are reached only dynamically.<!--E:STATS_QT-->**

### 2.2 Core map — the calls that decide whether the app starts

Curated from the generated index; the raw call site is the evidence. The complete
one-row-per-API appendix is in §2.5.

<!--B:QT_CORE-->
#### Window, input, DPI (user32 / shcore)

| Win32 API | Wine DLL | Wine status | Qt source | What Qt expects |
|---|---|---|---|---|
| `CreateWindowExW` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:909 | create the native HWND; NULL => Qt aborts platform window creation (check class registration, DPI awareness, window station) |
| `RegisterClassExW` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:673 | register the Qt window class (QT_WINDOW_CLASS_NAME / Qt6Build...); 0 with ERROR_CLASS_ALREADY_EXISTS is tolerated by Qt |
| `DefWindowProcW` | user32 | forward | src/plugins/platforms/windows/qwindowsclipboard.cpp:145 | default handling of unhandled window messages; Qt relies on it for non-Qt classes |
| `DestroyWindow` | user32 | forward | src/plugins/platforms/windows/qwindowsclipboard.cpp:219 | must succeed; failure is logged and leaked HWNDs accumulate |
| `SetWindowLongPtrW` | user32 | impl | src/plugins/platforms/windows/qwindowswindow.cpp:853 | install the Qt window proc and GWLP_USERDATA; 0 may mean previous value was 0 (check GetLastError) |
| `GetWindowLongPtrW` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:819 | read GWLP_USERDATA / window style; Qt uses it to recover the QWindowsWindow |
| `AdjustWindowRectEx` | user32 | impl | src/plugins/platforms/windows/qwindowswindow.cpp:925 | convert client geometry to frame geometry; FALSE => geometry is wrong |
| `SetWindowPos` | user32 | forward | src/plugins/platforms/windows/qwindowscontext.cpp:1011 | move/resize/z-order; FALSE => Qt logs a warning |
| `MoveWindow` | user32 | forward | src/plugins/platforms/windows/qwindowswindow.cpp:2021 | resize path; FALSE => Qt keeps the old geometry |
| `GetMonitorInfoW` | user32 | impl | src/plugins/platforms/windows/qwindowsscreen.cpp:84 | monitor work area / device name for QScreen |
| `EnumDisplayMonitors` | user32 | forward | src/plugins/platforms/windows/qwindowsscreen.cpp:145 | enumerate QScreens |
| `GetSystemMetrics` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:659 | screen metrics, virtual desktop, multi-monitor |
| `SystemParametersInfoW` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:1020 | theme/font/DPI settings, QWindowsTheme |
| `GetSysColorBrush` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:620 | system colours for QWindowsTheme palettes |
| `SetCapture` | user32 | forward | src/plugins/platforms/windows/qwindowswindow.cpp:2608 | mouse capture during drag/resize; NULL => capture lost |
| `ReleaseCapture` | user32 | forward | src/plugins/platforms/windows/qwindowswindow.cpp:2378 | balance SetCapture |
| `TrackMouseEvent` | user32 | forward | src/plugins/platforms/windows/qwindowsmousehandler.cpp:447 | hover/leave tracking for QCursor::setPos + enter/leave events |
| `GetKeyState` | user32 | forward | src/plugins/platforms/windows/qwindowskeymapper.cpp:958 | modifier state (Shift/Ctrl/Alt) for key events |
| `MapVirtualKeyW` | user32 | impl | src/plugins/platforms/windows/qwindowskeymapper.cpp:1207 | translate VK codes to characters |
| `GetKeyboardLayout` | user32 | forward | src/plugins/platforms/windows/qwindowsinputcontext.cpp:102 | active layout; Qt caches per-thread layouts |
| `RegisterTouchWindow` | user32 | impl | src/plugins/platforms/windows/qwindowswindow.cpp:3056 | enable WM_TOUCH; failure => Qt uses pointer/tablet path instead |
| `IsTouchWindow` | user32 | impl | src/plugins/platforms/windows/qwindowswindow.cpp:3051 | `const bool ret = IsTouchWindow(m_data.hwnd, &touchFlags);` |
| `GetPointerInfo` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:204 | Win8 pointer input for touch/pen |
| `GetPointerTouchInfo` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:206 | touch/pen detail for QPointerEvent synthesis |
| `GetDC` | user32 | forward | src/plugins/platforms/windows/qwindowscontext.cpp:292 | screen DC used to query OPENGL caps |
| `ReleaseDC` | user32 | forward | src/plugins/platforms/windows/qwindowscontext.cpp:336 | balance GetDC; failure leaks DCs |
| `SetForegroundWindow` | user32 | forward | src/plugins/platforms/windows/qwindowssystemtrayicon.cpp:429 | activate a window; Windows may refuse (returns FALSE) — Qt falls back to AttachThreadInput |
| `AttachThreadInput` | user32 | forward | src/plugins/platforms/windows/qwindowswindow.cpp:2554 | `attached = AttachThreadInput(foregroundThread, currentThread, TRUE) == TRUE;` |
| `MsgWaitForMultipleObjectsEx` | user32 | forward | src/corelib/kernel/qeventdispatcher_win.cpp:573 | the QEventDispatcherWin32 core wait (events + WM_* queue) |
| `PeekMessageW` | user32 | impl | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:136 | drain the thread message queue |
| `DispatchMessageW` | user32 | impl | src/corelib/kernel/qeventdispatcher_win.cpp:607 | deliver messages to the Qt window proc |
| `PostMessageW` | user32 | impl | src/plugins/platforms/windows/qwindowsclipboard.cpp:254 | async cross-thread notification (0 => queue full / invalid hwnd) |
| `SendMessageW` | user32 | impl | src/plugins/platforms/windows/qwindowsclipboard.cpp:256 | synchronous cross-thread call; Qt uses it for WM_QT_* internal messages |
| `GetMessageW` | user32 | impl | src/corelib/kernel/qeventdispatcher_win.cpp:476 | modal loop message pump |
| `GetDpiForMonitor` | shcore | impl | src/plugins/platforms/windows/qwindowscontext.cpp:238 | per-monitor DPI (shcore); HRESULT failure falls back to GetDeviceCaps |
| `SetProcessDpiAwareness` | shcore | impl | src/plugins/platforms/windows/qwindowscontext.cpp:237 | Win8.1 process DPI awareness; failure => Qt falls back to SetProcessDPIAware |
| `SetProcessDPIAware` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:193 | Vista DPI awareness fallback; FALSE if already set is benign |
| `GetProcessDpiAwareness` | shcore | impl | src/plugins/platforms/windows/qwindowscontext.cpp:236 | `getProcessDpiAwareness = (GetProcessDpiAwareness)library.resolve("GetProcessDpiAwareness");` |
| `SetDisplayAutoRotationPreferences` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:199 | `setDisplayAutoRotationPreferences = (SetDisplayAutoRotationPreferences)library.resolve("SetDisplayAutoRotationPreferences");` |
| `UnregisterPowerSettingNotification` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:325 | `UnregisterPowerSettingNotification(d->m_powerNotification);` |
| `ChangeWindowMessageFilterEx` | user32 | impl | src/plugins/platforms/windows/qwindowssystemtrayicon.cpp:326 | `ChangeWindowMessageFilterEx(m_hwnd, MYWM_TASKBARCREATED, MSGFLT_ALLOW, nullptr);` |

#### GDI, fonts, DirectWrite (gdi32 / dwrite)

| Win32 API | Wine DLL | Wine status | Qt source | What Qt expects |
|---|---|---|---|---|
| `CreateDCW` | gdi32 | impl | src/plugins/platforms/windows/qwindowsscreen.cpp:94 | screen/display DC for GDI painting and font metrics |
| `CreateCompatibleDC` | gdi32 | forward | src/plugins/platforms/windows/qwindowsscreen.cpp:217 | memory DC for backing store / pixmaps |
| `CreateCompatibleBitmap` | gdi32 | impl | src/plugins/platforms/windows/qwindowsscreen.cpp:218 | backing store bitmap |
| `CreateDIBSection` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsnativeimage.cpp:101 | top-down DIB for QImage on Windows (shared pixel memory) |
| `BitBlt` | gdi32 | impl | src/plugins/platforms/windows/qwindowsbackingstore.cpp:119 | blit backing store to the window DC |
| `GetDIBits` | gdi32 | impl | src/gui/image/qpixmap_win.cpp:111 | read back GDI bitmap data into a QImage |
| `SelectObject` | gdi32 | impl | src/plugins/platforms/windows/qwindowsscreen.cpp:219 | `HGDIOBJ null_bitmap = SelectObject(bitmap_dc, bitmap);` |
| `DeleteObject` | gdi32 | impl | src/plugins/platforms/windows/qwindowscursor.cpp:128 | `DeleteObject(ic);` |
| `CreateFontIndirectW` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontdatabase.cpp:923 | logical font creation in the GDI font engine |
| `EnumFontFamiliesExW` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontdatabase.cpp:1184 | enumerate installed families for QFontDatabase |
| `GetGlyphOutline` | gdi32 | forward | src/platformsupport/fontdatabases/windows/qwindowsfontengine.cpp:454 | `res = GetGlyphOutline(hdc, glyph, format, &gm, 0, 0, &mat);` |
| `GetTextMetricsW` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontdatabase.cpp:1597 | font ascent/descent/avg width |
| `GetTextExtentPoint32W` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontengine.cpp:392 | `GetTextExtentPoint32(hdc, reinterpret_cast<const wchar_t *>(ch), chrLen, &size);` |
| `AddFontMemResourceEx` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontdatabase.cpp:1314 | load embedded application fonts (QFontDatabase::addApplicationFont) |
| `RemoveFontMemResourceEx` | gdi32 | forward | src/platformsupport/fontdatabases/windows/qwindowsfontdatabase.cpp:1317 | release AddFontMemResourceEx handles |
| `AddFontResourceExW` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontdatabase.cpp:1618 | install application fonts for the process |
| `RemoveFontResourceExW` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontdatabase.cpp:1642 | uninstall application fonts |
| `GetDeviceCaps` | gdi32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:293 | DPI (LOGPIXELSX/Y), bit depth, raster caps for the screen |
| `GetStockObject` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontdatabase.cpp:1688 | default pens/brushes/fonts used by the GDI engine |
| `DWriteCreateFactory` | dwrite | impl | src/platformsupport/fontdatabases/windows/qwindowsfontdatabase.cpp:104 | DirectWrite factory for the DirectWrite font engine (Qt uses it when DWrite is available) |

#### OpenGL / ANGLE / D3D (opengl32 / d3d11 / dxgi / d3d9 / dcomp)

| Win32 API | Wine DLL | Wine status | Qt source | What Qt expects |
|---|---|---|---|---|
| `wglCreateContext` | opengl32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:190 | WGL context creation for the desktop-GL path |
| `wglMakeCurrent` | opengl32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:195 | bind GL context; FALSE => Qt disables the GL path |
| `wglGetProcAddress` | opengl32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:194 | resolve GL entry points |
| `wglDeleteContext` | opengl32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:191 | `wglDeleteContext = reinterpret_cast<BOOL (WINAPI *)(HGLRC)>(resolve("wglDeleteContext"));` |
| `wglShareLists` | opengl32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:196 | `wglShareLists = reinterpret_cast<BOOL (WINAPI *)(HGLRC, HGLRC)>(resolve("wglShareLists"));` |
| `wglSwapBuffers` | opengl32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:197 | `wglSwapBuffers = reinterpret_cast<BOOL (WINAPI *)(HDC)>(resolve("wglSwapBuffers"));` |
| `wglSetPixelFormat` | opengl32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:198 | `wglSetPixelFormat = reinterpret_cast<BOOL (WINAPI *)(HDC, int, const PIXELFORMATDESCRIPTOR *)>(resolve("wglSetPixelFormat"));` |
| `wglDescribePixelFormat` | opengl32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:199 | `wglDescribePixelFormat = reinterpret_cast<int (WINAPI *)(HDC, int, UINT, PIXELFORMATDESCRIPTOR *)>(resolve("wglDescribePixelFormat"));` |
| `ChoosePixelFormat` | gdi32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:439 | select a pixel format for a window DC |
| `SetPixelFormat` | gdi32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:215 | apply pixel format; FALSE => context creation fails |
| `DescribePixelFormat` | gdi32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:220 | probe pixel format capabilities |
| `glGetString` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:193 | `glGetString = RESOLVE((const GLubyte * (APIENTRY *)(GLenum )), glGetString);` |
| `glGetIntegerv` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:608 | `{ "glGetIntegerv", (void *) ::glGetIntegerv },` |
| `glGetError` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:606 | `{ "glGetError", (void *) ::glGetError },` |
| `D3D11CreateDevice` | d3d11 | impl | src/gui/rhi/qrhid3d11.cpp:264 | hardware rasterizer for Qt Quick via ANGLE; failure => Qt falls back to software GL (opengl32sw) |
| `CreateDXGIFactory` | dxgi | impl | src/3rdparty/angle/src/gpu_info_util/SystemInfo_win.cpp:146 | legacy DXGI factory path |
| `Direct3DCreate9` | d3d9 | impl | src/3rdparty/angle/src/libANGLE/renderer/d3d/d3d9/Renderer9.cpp:209 | `mD3d9 = Direct3DCreate9(D3D_SDK_VERSION);` |
| `Direct3DCreate9Ex` | d3d9 | impl | src/3rdparty/angle/src/libANGLE/renderer/d3d/d3d9/Renderer9.cpp:192 *(dynamic)* | `reinterpret_cast<Direct3DCreate9ExFunc>(GetProcAddress(mD3d9Module, "Direct3DCreate9Ex"));` |
| `DCompositionCreateDevice` | dcomp | impl | src/3rdparty/angle/src/libANGLE/renderer/d3d/d3d11/win32/NativeWindow11Win32.cpp:80 *(dynamic)* | `GetProcAddress(dcomp, "DCompositionCreateDevice"));` |
| `D3DPERF_BeginEvent` | d3d9 | impl | src/3rdparty/angle/src/libANGLE/renderer/d3d/d3d9/DebugAnnotator9.cpp:18 | `D3DPERF_BeginEvent(0, eventName);` |
| `D3DPERF_EndEvent` | d3d9 | impl | src/3rdparty/angle/src/libANGLE/renderer/d3d/d3d9/DebugAnnotator9.cpp:23 | `D3DPERF_EndEvent();` |
| `D3DPERF_SetMarker` | d3d9 | impl | src/3rdparty/angle/src/libANGLE/renderer/d3d/d3d9/DebugAnnotator9.cpp:28 | `D3DPERF_SetMarker(0, markerName);` |
| `D3DPERF_GetStatus` | d3d9 | impl | src/3rdparty/angle/src/libANGLE/renderer/d3d/d3d9/DebugAnnotator9.cpp:33 | `return !!D3DPERF_GetStatus();` |

#### Clipboard, DnD, OLE, shell (ole32 / shell32 / comdlg32 / dwmapi)

| Win32 API | Wine DLL | Wine status | Qt source | What Qt expects |
|---|---|---|---|---|
| `OleInitialize` | ole32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:285 | COM/OLE for drag&drop and the platform clipboard |
| `OleUninitialize` | ole32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:332 | balance OleInitialize |
| `CoInitializeEx` | ole32 | forward | src/plugins/platforms/windows/qwindowsservices.cpp:62 | COM apartment init (Qt uses STA in the GUI thread) |
| `CoUninitialize` | ole32 | forward | src/plugins/platforms/windows/qwindowsservices.cpp:64 | balance CoInitializeEx |
| `CoCreateInstance` | ole32 | forward | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:706 | create OLE/shell objects (drag&drop, file dialogs, taskbar) |
| `DoDragDrop` | ole32 | impl | src/plugins/platforms/windows/qwindowsdrag.cpp:700 | QWindowsDrag::drag runs the OLE drag&drop loop |
| `RegisterDragDrop` | ole32 | impl | src/plugins/platforms/windows/qwindowswindow.cpp:1488 | register the Qt window as a drop target (IDropTarget) |
| `RevokeDragDrop` | ole32 | impl | src/plugins/platforms/windows/qwindowswindow.cpp:1493 | unregister the drop target |
| `OleGetClipboard` | ole32 | impl | src/plugins/platforms/windows/qwindowsclipboard.cpp:120 | paste via the OLE clipboard |
| `OleSetClipboard` | ole32 | impl | src/plugins/platforms/windows/qwindowsclipboard.cpp:332 | copy via the OLE clipboard |
| `OleIsCurrentClipboard` | ole32 | impl | src/plugins/platforms/windows/qwindowsclipboard.cpp:364 | clipboard ownership check |
| `OleFlushClipboard` | ole32 | impl | src/plugins/platforms/windows/qwindowsclipboard.cpp:298 | commit deferred rendering |
| `ReleaseStgMedium` | ole32 | impl | src/plugins/platforms/windows/qwindowsmime.cpp:346 | `ReleaseStgMedium(&s);` |
| `ShellExecuteW` | shell32 | impl | src/plugins/platforms/windows/qwindowsservices.cpp:63 | `result = ShellExecute(nullptr, nullptr, path, nullptr, nullptr, SW_SHOWNORMAL);` |
| `Shell_NotifyIcon` | shell32 | forward | src/plugins/platforms/windows/qwindowssystemtrayicon.cpp:295 | `Shell_NotifyIcon(NIM_MODIFY, &tnd);` |
| `Shell_NotifyIconGetRect` | shell32 | impl | src/plugins/platforms/windows/qwindowssystemtrayicon.cpp:244 | `const QRect result = SUCCEEDED(Shell_NotifyIconGetRect(&nid, &rect))` |
| `SHGetFileInfo` | shell32 | forward | src/plugins/platforms/windows/qwindowstheme.cpp:176 | `const bool result = SHGetFileInfo(reinterpret_cast<const wchar_t *>(fileName.utf16()),` |
| `SHGetKnownFolderIDList` | shell32 | impl | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:921 | `HRESULT hr = SHGetKnownFolderIDList(uuid, 0, nullptr, &idList);` |
| `SHGetPathFromIDList` | shell32 | forward | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:1789 | `const bool ok = SHGetPathFromIDList(reinterpret_cast<qt_LpItemIdList>(lParam), path)` |
| `SHGetStockIconInfo` | shell32 | impl | src/plugins/platforms/windows/qwindowstheme.cpp:782 | `if (SHGetStockIconInfo(stockId, SHGFI_ICON \| stockFlags, &iconInfo) == S_OK) {` |
| `SHCreateItemFromParsingName` | shell32 | impl | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:902 | shell item creation for QFileDialog/native menus |
| `SHBrowseForFolder` | shell32 | forward | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:1811 | `if (qt_LpItemIdList pItemIDList = SHBrowseForFolder(&bi)) {` |
| `SHFileOperation` | shell32 | forward | src/corelib/io/qfilesystemengine_win.cpp:1612 | `int result = SHFileOperation(&operation);` |
| `GetOpenFileNameW` | comdlg32 | impl | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:1722 *(dynamic)* | native file dialog (QFileDialog when not using the Qt dialog) |
| `GetSaveFileNameW` | comdlg32 | impl | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:1723 *(dynamic)* | native save dialog |
| `ChooseColorW` | comdlg32 | impl | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:2050 *(dynamic)* | native colour dialog |
| `DwmEnableBlurBehindWindow` | dwmapi | impl | src/plugins/platforms/windows/qwindowswindow.cpp:376 | `const bool result = DwmEnableBlurBehindWindow(hwnd, &blurBehind) == S_OK;` |
| `DwmSetWindowAttribute` | dwmapi | impl | src/plugins/platforms/windows/qwindowswindow.cpp:2939 | `SUCCEEDED(DwmSetWindowAttribute(hwnd, DwmwaUseImmersiveDarkMode, &darkBorder, sizeof(darkBorder)))` |
| `DwmIsCompositionEnabled` | dwmapi | impl | src/plugins/platforms/windows/qwindowswindow.cpp:362 | `if (DwmIsCompositionEnabled(&compositionEnabled) != S_OK)` |
| `DwmGetWindowAttribute` | dwmapi | impl | src/plugins/platforms/windows/qwindowswindow.cpp:2928 | `SUCCEEDED(DwmGetWindowAttribute(hwnd, DwmwaUseImmersiveDarkMode, &result, sizeof(result)))` |

#### Process, threads, files, pipes (kernel32)

| Win32 API | Wine DLL | Wine status | Qt source | What Qt expects |
|---|---|---|---|---|
| `CreateProcessW` | kernel32 | forward | src/plugins/platforms/windows/qwindowsservices.cpp:150 | QProcess start; FALSE => QProcess::FailedToStart with GetLastError |
| `CreateFileW` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:292 | open files, pipes (\\.\pipe\...), devices (\\.\DISPLAY1) and console handles; INVALID_HANDLE_VALUE => Qt error |
| `ReadFile` | kernel32 | forward | src/corelib/io/qfsfileengine_win.cpp:331 | read from pipe/file; FALSE+ERROR_BROKEN_PIPE => Qt treats as EOF (success) |
| `WriteFile` | kernel32 | forward | src/corelib/io/qfsfileengine_win.cpp:391 | write to pipe/file; FALSE+ERROR_NO_DATA => peer closed, Qt treats as EOF |
| `CreateNamedPipeW` | kernel32 | forward | src/corelib/io/qprocess_win.cpp:118 | QProcess/QLocalServer named pipes |
| `ConnectNamedPipe` | kernel32 | forward | src/corelib/io/qprocess_win.cpp:154 | accept a local socket connection; ERROR_PIPE_CONNECTED is success |
| `PeekNamedPipe` | kernel32 | forward | src/corelib/io/qwindowspipereader.cpp:274 | non-blocking pipe read availability |
| `CreateEventW` | kernel32 | forward | src/corelib/kernel/qeventdispatcher_win.cpp:884 | manual/auto-reset events for QEventDispatcherWin32's wakeup pipe and QThread |
| `CreateEventExW` | kernel32 | forward | src/corelib/thread/qthread_win.cpp:231 | event with explicit access for the dispatcher |
| `CreateSemaphoreW` | kernel32 | forward | src/corelib/kernel/qsystemsemaphore_win.cpp:93 | QSystemSemaphore |
| `CreateSemaphoreExW` | kernel32 | forward | src/corelib/kernel/qsystemsemaphore_win.cpp:89 | `semaphore = CreateSemaphoreEx(0, initialValue, MAXLONG,` |
| `CreateThread` | kernel32 | forward | src/corelib/thread/qthread_win.cpp:236 | QThread::start on the Win32 path (Qt uses _beginthreadex by preference) |
| `CloseHandle` | kernel32 | forward | src/plugins/platforms/windows/qwindowsclipboard.cpp:237 | balance every handle; failure puts Qt into a debug assertion |
| `DuplicateHandle` | kernel32 | forward | src/corelib/io/qprocess_win.cpp:186 | pass handles to child processes (QProcess pipe inheritance) |
| `CancelIoEx` | kernel32 | forward | src/corelib/io/qwindowspipereader.cpp:101 | abort overlapped I/O for QWindowsPipeReader |
| `GetOverlappedResult` | kernel32 | forward | src/network/socket/qlocalserver_win.cpp:290 | complete overlapped I/O for the pipe reader |
| `DeviceIoControl` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:304 | `if (::DeviceIoControl(handle, FSCTL_GET_REPARSE_POINT, 0, 0, rdb, bufsize, &retsize, 0)) {` |
| `FindFirstFileExW` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:417 | directory enumeration for QDirIterator/QFileSystemWatcher |
| `FindNextFileW` | kernel32 | forward | src/corelib/io/qfilesystemiterator_win.cpp:122 | continue FindFirstFileExW enumeration |
| `FindClose` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:420 | close enumeration handle |
| `FindFirstChangeNotificationW` | kernel32 | forward | src/corelib/io/qfilesystemwatcher_win.cpp:82 | `const HANDLE result = FindFirstChangeNotification(reinterpret_cast<const wchar_t *>(nativePath.utf16()),` |
| `FindNextChangeNotification` | kernel32 | forward | src/corelib/io/qfilesystemwatcher_win.cpp:648 | `str += QLatin1String("QFileSystemWatcher: FindNextChangeNotification failed for");` |
| `GetFileInformationByHandle` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:681 | QFileInfo identity (volume serial + file index) for QFileSystemEngine |
| `GetFileAttributesExW` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:1143 | QFileInfo attributes; FALSE => does not exist |
| `DeleteFileW` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:1531 | QFile::remove |
| `MoveFileExW` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:1504 | rename/replace, MOVEFILE_REPLACE_EXISTING |
| `CreateDirectoryW` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:1183 | already listed |
| `RemoveDirectoryW` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:1191 | QDir::rmdir |
| `GetModuleFileNameW` | kernel32 | forward | src/corelib/kernel/qcoreapplication_win.cpp:93 | locate the executable / plugin dirs (qApp->applicationDirPath) |
| `LoadLibraryW` | kernel32 | forward | src/plugins/platforms/windows/qwindowseglcontext.cpp:127 | load opengl32.dll/angle/dll plugins; NULL => Qt reports 'failed to load' |
| `GetProcAddress` | kernel32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:92 | resolve optional entry points; NULL => Qt uses a fallback implementation |
| `FreeLibrary` | kernel32 | forward | src/corelib/plugin/qlibrary_win.cpp:158 | unload a plugin DLL |
| `QueryPerformanceCounter` | kernel32 | forward | src/corelib/kernel/qelapsedtimer_win.cpp:89 | QElapsedTimer high-resolution clock |
| `QueryPerformanceFrequency` | kernel32 | forward | src/corelib/kernel/qelapsedtimer_win.cpp:58 | QElapsedTimer tick frequency |
| `FormatMessageW` | kernel32 | forward | src/plugins/platforms/windows/qwindowscontext.cpp:706 | human-readable text for qSystemError/qt_errorString |
| `SetErrorMode` | kernel32 | forward | src/corelib/plugin/qlibrary_win.cpp:68 | suppress Windows error dialogs (Qt sets SEM_FAILCRITICALERRORS) |
| `GetSystemInfo` | kernel32 | forward | src/corelib/io/qfsfileengine_win.cpp:912 | page size, processor count, architecture (QSettings/Random) |
| `GetLastError` | kernel32 | forward | src/plugins/platforms/windows/qwindowsbackingstore.cpp:121 | every failing Win32 call is decoded through this by Qt's qt_winerror/qSystemError |
| `WaitForSingleObject` | kernel32 | forward | src/corelib/kernel/qsystemsemaphore_win.cpp:130 | QSystemSemaphore::acquire |
| `WaitForMultipleObjects` | kernel32 | forward | src/corelib/io/qfilesystemwatcher_win.cpp:662 | wait on the dispatcher event + message queue |
| `CreateFileMappingW` | kernel32 | forward | src/corelib/kernel/qsharedmemory_win.cpp:143 | QSharedMemory |
| `MapViewOfFile` | kernel32 | forward | src/corelib/kernel/qsharedmemory_win.cpp:159 | QSharedMemory attach |
| `UnmapViewOfFile` | kernel32 | forward | src/corelib/kernel/qsharedmemory_win.cpp:184 | QSharedMemory detach |
| `OpenFileMappingW` | kernel32 | forward | src/corelib/kernel/qsharedmemory_win.cpp:107 | QSharedMemory attach to existing segment |

#### Registry, tokens (advapi32)

| Win32 API | Wine DLL | Wine status | Qt source | What Qt expects |
|---|---|---|---|---|
| `RegOpenKeyExW` | kernel32 | forward | src/corelib/kernel/qwinregistry.cpp:58 | QSettings registry backend |
| `RegQueryValueExW` | kernel32 | forward | src/corelib/kernel/qwinregistry.cpp:85 | QSettings value read |
| `RegSetValueExW` | kernel32 | forward | src/corelib/io/qsettings_win.cpp:737 | QSettings value write |
| `RegCreateKeyExW` | kernel32 | forward | src/corelib/io/qsettings_win.cpp:165 | QSettings key creation |
| `RegEnumKeyExW` | kernel32 | forward | src/corelib/io/qsettings_win.cpp:240 | QSettings child groups |
| `RegCloseKey` | kernel32 | forward | src/corelib/kernel/qwinregistry.cpp:72 | balance registry handles |
| `RegQueryInfoKeyW` | kernel32 | forward | src/corelib/io/qsettings_win.cpp:208 | QSettings key metadata |
| `OpenProcessToken` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:201 | TokenElevation query (IsUserAnAdmin replacement) |
| `GetTokenInformation` | kernelbase | impl | src/corelib/io/qfilesystemengine_win.cpp:207 | TokenElevation/TokenSessionId |

#### Network: sockets, interfaces, DNS, proxy (ws2_32 / iphlpapi / dnsapi / winhttp / netapi32)

| Win32 API | Wine DLL | Wine status | Qt source | What Qt expects |
|---|---|---|---|---|
| `WSASocketW` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:358 | create a socket with flags (WSA_FLAG_OVERLAPPED for Qt's select-based engine) |
| `WSAIoctl` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:406 | SIO_GET_EXTENSION_FUNCTION_POINTER etc. |
| `WSAAsyncSelect` | ws2_32 | impl | src/corelib/kernel/qeventdispatcher_win.cpp:455 | `WSAAsyncSelect(socket, internalHwnd, event ? int(WM_QT_SOCKETNOTIFIER) : 0, event);` |
| `WSAConnect` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:695 | `int connectResult = ::WSAConnect(socketDescriptor, &aa.a, sockAddrSize, 0,0,0,0);` |
| `WSAAccept` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:875 | `int acceptedDescriptor = WSAAccept(socketDescriptor, 0,0,0,0);` |
| `WSARecv` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:1158 | `recvResult = ::WSARecv(socketDescriptor, buf.data(), DWORD(buf.size()), &bytesRead, &flags, nullptr, nullptr);` |
| `WSASend` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:1441 | `int socketRet = ::WSASend(socketDescriptor, &buf, 1, &bytesWritten, flags, 0,0);` |
| `WSARecvFrom` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:1094 | `if (::WSARecvFrom(socketDescriptor, &buf, 1, &bytesReceived, &flags, 0,0,0,0) == SOCKET_ERROR) {` |
| `WSASendTo` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:1393 | `ret = ::WSASendTo(socketDescriptor, &buf, 1, &bytesSent, flags, msg.name, msg.namelen, 0,0);` |
| `WSAGetLastError` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:301 | socket error mapping; Qt translates WSAE* to QAbstractSocket::SocketError |
| `bind` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:793 | bind QAbstractSocket/QUdpSocket |
| `listen` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:843 | QLocalServer/TcpServer listen backlog |
| `closesocket` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:1632 | close a socket |
| `getpeername` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:604 | peer address/port |
| `getsockname` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:554 | local address/port |
| `getsockopt` | ws2_32 | impl | src/network/socket/qnativesocketengine.cpp:1078 | SO_ERROR/SO_TYPE |
| `setsockopt` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:527 | SO_REUSEADDR, TCP_NODELAY (Qt sets nodelay by default) |
| `getaddrinfo` | ws2_32 | impl | src/network/kernel/qhostinfo.cpp:462 | QHostInfo/QDnsLookup on Windows uses the OS resolver (ws2_32) |
| `freeaddrinfo` | ws2_32 | impl | src/network/kernel/qhostinfo.cpp:512 | `freeaddrinfo(res);` |
| `getnameinfo` | ws2_32 | impl | src/network/kernel/qhostinfo.cpp:426 | `if (sa && getnameinfo(sa, saSize, hbuf, sizeof(hbuf), nullptr, 0, 0) == 0)` |
| `WSAHtonl` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:1378 | `WSAHtonl(socketDescriptor, header.senderAddress.toIPv4Address(), &data->ipi_addr.s_addr);` |
| `WSANtohl` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:201 | `WSANtohl(socketDescriptor, sa4->sin_addr.s_addr, &addr);` |
| `WSANtohs` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:195 | `WSANtohs(socketDescriptor, sa6->sin6_port, port);` |
| `GetAdaptersAddresses` | iphlpapi | impl | src/network/kernel/qnetworkinterface_win.cpp:122 | QNetworkInterface enumeration (iphlpapi); ERROR_BUFFER_OVERFLOW means realloc and retry |
| `GetNetworkParams` | iphlpapi | impl | src/network/kernel/qnetworkinterface_win.cpp:258 | `if (GetNetworkParams(pinfo, &bufSize) == ERROR_BUFFER_OVERFLOW) {` |
| `ConvertInterfaceIndexToLuid` | iphlpapi | impl | src/network/kernel/qnetconmonitor_win.cpp:278 | map ifindex -> LUID |
| `ConvertInterfaceLuidToGuid` | iphlpapi | impl | src/network/kernel/qnetconmonitor_win.cpp:283 | map LUID -> interface GUID for QNetworkInterface |
| `ConvertInterfaceLuidToIndex` | iphlpapi | impl | src/network/kernel/qnetworkinterface_win.cpp:96 | `&& ConvertInterfaceLuidToIndex(&luid, &id) == NO_ERROR)` |
| `ConvertInterfaceLuidToNameW` | iphlpapi | impl | src/network/kernel/qnetworkinterface_win.cpp:106 | `if (ConvertInterfaceLuidToNameW(&luid, buf, sizeof(buf)/sizeof(buf[0])) == NO_ERROR)` |
| `ConvertInterfaceNameToLuidW` | iphlpapi | impl | src/network/kernel/qnetworkinterface_win.cpp:95 | `if (ConvertInterfaceNameToLuidW(reinterpret_cast<const wchar_t *>(name.constData()), &luid) == NO_ERROR` |
| `DnsQuery_W` | dnsapi | impl | src/network/kernel/qdnslookup_win.cpp:74 | direct DNS query path (dnsapi) |
| `DnsRecordListFree` | dnsapi | impl | src/network/kernel/qdnslookup_win.cpp:163 | `DnsRecordListFree(dns_records, DnsFreeRecordList);` |
| `WinHttpOpen` | winhttp | impl | src/network/kernel/qnetworkproxy_win.cpp:502 *(dynamic)* | `ptrWinHttpOpen = (PtrWinHttpOpen)lib.resolve("WinHttpOpen");` |
| `WinHttpGetProxyForUrl` | winhttp | impl | src/network/kernel/qnetworkproxy_win.cpp:504 *(dynamic)* | `ptrWinHttpGetProxyForUrl = (PtrWinHttpGetProxyForUrl)lib.resolve("WinHttpGetProxyForUrl");` |
| `WinHttpGetDefaultProxyConfiguration` | winhttp | impl | src/network/kernel/qnetworkproxy_win.cpp:505 *(dynamic)* | `ptrWinHttpGetDefaultProxyConfiguration = (PtrWinHttpGetDefaultProxyConfiguration)lib.resolve("WinHttpGetDefaultProxyConfiguration");` |
| `WinHttpGetIEProxyConfigForCurrentUser` | winhttp | impl | src/network/kernel/qnetworkproxy_win.cpp:506 *(dynamic)* | `ptrWinHttpGetIEProxyConfigForCurrentUser = (PtrWinHttpGetIEProxyConfigForCurrentUser)lib.resolve("WinHttpGetIEProxyConfigForCurrentUser");` |
| `WinHttpCloseHandle` | winhttp | impl | src/network/kernel/qnetworkproxy_win.cpp:503 *(dynamic)* | `ptrWinHttpCloseHandle = (PtrWinHttpCloseHandle)lib.resolve("WinHttpCloseHandle");` |
| `NetShareEnum` | netapi32 | impl | src/corelib/io/qfilesystemengine_win.cpp:533 | `res = NetShareEnum((wchar_t*)server.utf16(), 1, (LPBYTE *)&BufPtr, DWORD(-1), &er, &tr, &resume);` |
| `NetApiBufferFree` | netapi32 | forward | src/corelib/io/qfilesystemengine_win.cpp:542 | `NetApiBufferFree(BufPtr);` |
| `WTSQuerySessionInformationW` | wtsapi32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:855 | `if (WTSQuerySessionInformation(WTS_CURRENT_SERVER_HANDLE, sessionId,` |
| `WTSFreeMemory` | wtsapi32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:860 | free WTSQueryUserToken/WTS* buffers |
| `GetUserProfileDirectoryW` | userenv | impl | src/corelib/io/qfilesystemengine_win.cpp:1360 | QStandardPaths home dir (userenv) |

#### TLS / Schannel and crypto (secur32 / crypt32 / bcrypt)

| Win32 API | Wine DLL | Wine status | Qt source | What Qt expects |
|---|---|---|---|---|
| `AcquireCredentialsHandleW` | secur32 | impl | src/network/kernel/qauthenticator.cpp:1534 | SChannel/SSPI credential acquisition (qsslsocket_schannel.cpp) |
| `InitializeSecurityContextW` | secur32 | impl | src/network/kernel/qauthenticator.cpp:1583 | TLS handshake step |
| `QueryContextAttributesW` | secur32 | impl | src/network/ssl/qsslsocket_schannel.cpp:1053 | TLS stream sizes |
| `EncryptMessage` | secur32 | impl | src/network/ssl/qsslsocket_schannel.cpp:1276 | TLS record encryption |
| `DecryptMessage` | secur32 | impl | src/network/ssl/qsslsocket_schannel.cpp:1351 | TLS record decryption; SEC_E_INCOMPLETE_MESSAGE is normal |
| `FreeContextBuffer` | secur32 | impl | src/network/kernel/qauthenticator.cpp:1607 | free SSPI output buffers |
| `DeleteSecurityContext` | secur32 | impl | src/network/kernel/qauthenticator.cpp:1602 | release TLS contexts |
| `FreeCredentialsHandle` | secur32 | impl | src/network/kernel/qauthenticator.cpp:1601 | release credentials |
| `ApplyControlToken` | secur32 | impl | src/network/ssl/qsslsocket_schannel.cpp:1445 | TLS shutdown (SCHANNEL_SHUTDOWN) |
| `CompleteAuthToken` | secur32 | impl | src/network/kernel/qauthenticator.cpp:1596 | `secStatus = pSecurityFunctionTable->CompleteAuthToken(&ctx->sspiWindowsHandles->ctxHandle,` |
| `AcceptSecurityContext` | secur32 | impl | src/network/ssl/qsslsocket_schannel.cpp:870 | `auto status = AcceptSecurityContext(` |
| `InitSecurityInterfaceW` | secur32 | impl | src/network/kernel/qauthenticator.cpp:1509 *(dynamic)* | `reinterpret_cast<QFunctionPointer>(GetProcAddress(securityDLLHandle, "InitSecurityInterfaceW")));` |
| `CertOpenStore` | crypt32 | impl | src/network/ssl/qsslsocket_schannel.cpp:1739 | certificate store access (SChannel backend, qsslcertificate_winrt / TLS) |
| `CertOpenSystemStoreW` | crypt32 | impl | src/network/ssl/qsslsocket_openssl.cpp:889 | `hSystemStore = CertOpenSystemStoreW(0, L"ROOT");` |
| `CertFindCertificateInStore` | crypt32 | impl | src/network/ssl/qsslsocket_openssl.cpp:893 | certificate lookup |
| `CertFindChainInStore` | crypt32 | impl | src/network/ssl/qsslsocket_schannel.cpp:661 | `chainContext = CertFindChainInStore(localCertificateStore.get(),` |
| `CertGetCertificateChain` | crypt32 | impl | src/network/ssl/qsslsocket_schannel.cpp:1801 | `BOOL status = CertGetCertificateChain(nullptr, // hChainEngine, default` |
| `CertFreeCertificateChain` | crypt32 | impl | src/network/ssl/qsslsocket_schannel.cpp:641 | `CertFreeCertificateChain(chainContext);` |
| `CertFreeCertificateContext` | crypt32 | impl | src/network/ssl/qsslsocket_schannel.cpp:574 | free certificate contexts |
| `CertCloseStore` | crypt32 | impl | src/network/ssl/qsslsocket_openssl.cpp:901 | close certificate stores |
| `CertCreateCertificateContext` | crypt32 | impl | src/network/ssl/qwindowscarootfetcher.cpp:150 | `PCCERT_CONTEXT wincert = CertCreateCertificateContext(X509_ASN_ENCODING, (const BYTE *)der.constData(), der.length());` |
| `CertDuplicateCertificateContext` | crypt32 | impl | src/network/ssl/qsslcertificate_qt.cpp:213 | `certificateContext = CertDuplicateCertificateContext(certificateContext);` |
| `CertAddCertificateContextToStore` | crypt32 | impl | src/network/ssl/qwindowscarootfetcher.cpp:269 | `if (CertAddCertificateContextToStore(customStore.get(), winCert, CERT_STORE_ADD_ALWAYS, nullptr))` |
| `CertAddStoreToCollection` | crypt32 | impl | src/network/ssl/qsslsocket_schannel.cpp:1762 | `} else if (!CertAddStoreToCollection(tempCertCollection.get(), rootStore.get(), 0, 1)) {` |
| `CertVerifyTimeValidity` | crypt32 | impl | src/network/ssl/qsslsocket_schannel.cpp:1888 | `LONG result = CertVerifyTimeValidity(nullptr /*== now */, element->pCertContext->pCertInfo);` |
| `PFXImportCertStore` | crypt32 | impl | src/network/ssl/qsslsocket_schannel.cpp:1707 | `return QHCertStorePointer(PFXImportCertStore(&pfxBlob, passphrase, 0));` |
| `BCryptOpenAlgorithmProvider` | bcrypt | impl | src/network/ssl/qsslkey_schannel.cpp:71 | bcrypt hash/cipher (hash lib in Qt 5.15 was moved out of QtCore, but QtWebEngine/Chromium use it) |
| `BCryptCloseAlgorithmProvider` | bcrypt | impl | src/network/ssl/qsslkey_schannel.cpp:125 | balance BCryptOpenAlgorithmProvider |
| `BCryptSetProperty` | bcrypt | impl | src/network/ssl/qsslkey_schannel.cpp:103 | `status = BCryptSetProperty(` |
| `BCryptGenerateSymmetricKey` | bcrypt | impl | src/network/ssl/qsslkey_schannel.cpp:89 | `NTSTATUS status = BCryptGenerateSymmetricKey(` |
| `BCryptEncrypt` | bcrypt | impl | src/network/ssl/qsslkey_schannel.cpp:139 | `auto cryptFunction = encrypt ? BCryptEncrypt : BCryptDecrypt;` |
| `BCryptDecrypt` | bcrypt | impl | src/network/ssl/qsslkey_schannel.cpp:139 | `auto cryptFunction = encrypt ? BCryptEncrypt : BCryptDecrypt;` |
| `BCryptDestroyKey` | bcrypt | impl | src/network/ssl/qsslkey_schannel.cpp:111 | `BCryptDestroyKey(keyHandle);` |

#### Text input, tablet, accessibility (imm32 / wintab32 / uiautomationcore)

| Win32 API | Wine DLL | Wine status | Qt source | What Qt expects |
|---|---|---|---|---|
| `ImmGetContext` | imm32 | impl | src/plugins/platforms/windows/qwindowsinputcontext.cpp:90 | QWindowsInputContext IME |
| `ImmReleaseContext` | imm32 | impl | src/plugins/platforms/windows/qwindowsinputcontext.cpp:92 | `ImmReleaseContext(hwnd, himc);` |
| `ImmGetCompositionString` | imm32 | forward | src/plugins/platforms/windows/qwindowsinputcontext.cpp:418 | `const int length = ImmGetCompositionString(himc, dwIndex, buffer, bufferSize * sizeof(wchar_t));` |
| `ImmSetCompositionWindow` | imm32 | impl | src/plugins/platforms/windows/qwindowsinputcontext.cpp:388 | IME candidate window placement |
| `ImmSetCandidateWindow` | imm32 | impl | src/plugins/platforms/windows/qwindowsinputcontext.cpp:389 | `ImmSetCandidateWindow(himc, &candf);` |
| `ImmNotifyIME` | imm32 | impl | src/plugins/platforms/windows/qwindowsinputcontext.cpp:91 | IME state transitions |
| `ImmAssociateContext` | imm32 | impl | src/plugins/platforms/windows/qwindowsinputcontext.cpp:329 | IME enable/disable |
| `ImmAssociateContextEx` | imm32 | impl | src/plugins/platforms/windows/qwindowsinputcontext.cpp:326 | `ImmAssociateContextEx(platformWindow->handle(), nullptr, IACE_DEFAULT);` |
| `ImmGetDefaultIMEWnd` | imm32 | impl | src/plugins/platforms/windows/qwindowsinputcontext.cpp:407 | `const HWND imeWindow = ImmGetDefaultIMEWnd(m_compositionContext.hwnd);` |
| `ImmGetOpenStatus` | imm32 | impl | src/plugins/platforms/windows/qwindowsinputcontext.cpp:252 | `return ImmGetOpenStatus(himc);` |
| `ImmGetVirtualKey` | imm32 | impl | src/plugins/platforms/windows/qwindowskeymapper.cpp:1187 | `vk_key = ImmGetVirtualKey(reinterpret_cast<HWND>(window->winId()));` |
| `WTOpenW` | wintab32 | impl | src/plugins/platforms/windows/qwindowstabletsupport.cpp:185 *(dynamic)* | `wTOpen = (PtrWTOpen)library.resolve("WTOpenW");` |
| `WTClose` | wintab32 | impl | src/plugins/platforms/windows/qwindowstabletsupport.cpp:186 *(dynamic)* | `wTClose = (PtrWTClose)library.resolve("WTClose");` |
| `WTInfoW` | wintab32 | impl | src/plugins/platforms/windows/qwindowstabletsupport.cpp:187 *(dynamic)* | `wTInfo = (PtrWTInfo)library.resolve("WTInfoW");` |
| `WTGetW` | wintab32 | impl | src/plugins/platforms/windows/qwindowstabletsupport.cpp:191 *(dynamic)* | `wTGet = (PtrWTGet)library.resolve("WTGetW");` |
| `WTEnable` | wintab32 | impl | src/plugins/platforms/windows/qwindowstabletsupport.cpp:188 *(dynamic)* | `wTEnable = (PtrWTEnable)library.resolve("WTEnable");` |
| `WTOverlap` | wintab32 | impl | src/plugins/platforms/windows/qwindowstabletsupport.cpp:189 *(dynamic)* | `wTOverlap = (PtrWTEnable)library.resolve("WTOverlap");` |
| `WTPacketsGet` | wintab32 | impl | src/plugins/platforms/windows/qwindowstabletsupport.cpp:190 *(dynamic)* | `wTPacketsGet = (PtrWTPacketsGet)library.resolve("WTPacketsGet");` |
| `WTQueueSizeGet` | wintab32 | impl | src/plugins/platforms/windows/qwindowstabletsupport.cpp:192 *(dynamic)* | `wTQueueSizeGet = (PtrWTQueueSizeGet)library.resolve("WTQueueSizeGet");` |
| `WTQueueSizeSet` | wintab32 | impl | src/plugins/platforms/windows/qwindowstabletsupport.cpp:193 *(dynamic)* | `wTQueueSizeSet = (PtrWTQueueSizeSet)library.resolve("WTQueueSizeSet");` |
| `UiaClientsAreListening` | uiautomationcore | impl | src/platformsupport/windowsuiautomation/qwindowsuiawrapper.cpp:57 *(dynamic)* | `m_pUiaClientsAreListening = reinterpret_cast<PtrUiaClientsAreListening>(uiaLib.resolve("UiaClientsAreListening"));` |
| `UiaHostProviderFromHwnd` | uiautomationcore | impl | src/platformsupport/windowsuiautomation/qwindowsuiawrapper.cpp:53 *(dynamic)* | `m_pUiaHostProviderFromHwnd = reinterpret_cast<PtrUiaHostProviderFromHwnd>(uiaLib.resolve("UiaHostProviderFromHwnd"));` |
| `UiaRaiseAutomationEvent` | uiautomationcore | impl | src/platformsupport/windowsuiautomation/qwindowsuiawrapper.cpp:55 *(dynamic)* | `m_pUiaRaiseAutomationEvent = reinterpret_cast<PtrUiaRaiseAutomationEvent>(uiaLib.resolve("UiaRaiseAutomationEvent"));` |
| `UiaRaiseAutomationPropertyChangedEvent` | uiautomationcore | impl | src/platformsupport/windowsuiautomation/qwindowsuiawrapper.cpp:54 *(dynamic)* | `m_pUiaRaiseAutomationPropertyChangedEvent = reinterpret_cast<PtrUiaRaiseAutomationPropertyChangedEvent>(uiaLib.resolve("UiaRaiseAutomationPropertyChangedEvent"));` |
| `UiaRaiseNotificationEvent` | uiautomationcore | impl | src/platformsupport/windowsuiautomation/qwindowsuiawrapper.cpp:56 *(dynamic)* | `m_pUiaRaiseNotificationEvent = reinterpret_cast<PtrUiaRaiseNotificationEvent>(uiaLib.resolve("UiaRaiseNotificationEvent"));` |
| `UiaReturnRawElementProvider` | uiautomationcore | impl | src/platformsupport/windowsuiautomation/qwindowsuiawrapper.cpp:52 *(dynamic)* | `m_pUiaReturnRawElementProvider = reinterpret_cast<PtrUiaReturnRawElementProvider>(uiaLib.resolve("UiaReturnRawElementProvider"));` |

#### SQL drivers (odbc32 — indexed, but qsqlite-only install)

| Win32 API | Wine DLL | Wine status | Qt source | What Qt expects |
|---|---|---|---|---|
| `SQLAllocHandle` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:997 | ODBC driver (QSqlDatabase) driver/handle allocation |
| `SQLDriverConnect` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1968 | `r = SQLDriverConnect(d->hDbc,` |
| `SQLExecDirect` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1025 | `r = SQLExecDirect(d->hStmt,` |
| `SQLFetch` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1103 | ODBC row fetch |
| `SQLGetData` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:418 | `r = SQLGetData(hStmt,` |
| `SQLGetDiagRec` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:242 | `r = SQLGetDiagRec(handleType,` |
| `SQLDescribeCol` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:529 | ODBC metadata |
| `SQLNumResultCols` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1040 | ODBC column count |
| `SQLRowCount` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1322 | ODBC affected rows |
| `SQLSetConnectAttr` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:793 | ODBC attributes |
| `SQLSetEnvAttr` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1930 | `r = SQLSetEnvAttr(d->hEnv,` |
| `SQLFreeHandle` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:971 | ODBC handle release |
| `SQLDisconnect` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:2022 | ODBC disconnect |
| `SQLPrepare` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1373 | `r = SQLPrepare(d->hStmt,` |
| `SQLBindParameter` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1426 | `r = SQLBindParameter(d->hStmt,` |
| `SQLEndTran` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:2281 | `SQLRETURN r = SQLEndTran(SQL_HANDLE_DBC,` |
| `SQLMoreResults` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1794 | `SQLRETURN r = SQLMoreResults(d->hStmt);` |
| `SQLColumns` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:2540 | `r =  SQLColumns(hStmt,` |
| `SQLTables` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:2356 | `r = SQLTables(hStmt,` |
| `SQLPrimaryKeys` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:2438 | `r = SQLPrimaryKeys(hStmt,` |
| `SQLSpecialColumns` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:2450 | `r = SQLSpecialColumns(hStmt,` |
| `SQLGetTypeInfo` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:2236 | `r = SQLGetTypeInfo(hStmt, SQL_TIMESTAMP);` |
| `SQLGetInfo` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:752 | `int r = SQLGetInfo(hDbc,` |
| `SQLGetFunctions` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:2120 | `r = SQLGetFunctions(hDbc, reqFunc[i], &sup);` |
| `SQLGetStmtAttr` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1035 | `r = SQLGetStmtAttr(d->hStmt, SQL_ATTR_CURSOR_SCROLLABLE, &isScrollable, SQL_IS_INTEGER, 0);` |
| `SQLSetStmtAttr` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1008 | `r = SQLSetStmtAttr(d->hStmt,` |
| `SQLColAttribute` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:637 | `const SQLRETURN r = ::SQLColAttribute(hStmt, column + 1, SQL_DESC_AUTO_UNIQUE_VALUE,` |
| `SQLCloseCursor` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1400 | `SQLCloseCursor(d->hStmt);` |
| `SQLExecute` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1659 | `r = SQLExecute(d->hStmt);` |
| `SQLFetchScroll` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1078 | `r = SQLFetchScroll(d->hStmt,` |

<!--E:QT_CORE-->
### 2.3 Reading the `What Qt expects` column

Where the expectation is not from the curated table it is the first Qt source
line that references the API, verbatim, so you can jump to the real logic. The
generated table is deliberately mechanical: it tells you *where Qt calls the
function*, and the curated rows tell you *what Qt does with the result*.

### 2.4 Dynamic resolutions — the silent-degradation surface

Qt resolves a large part of the optional Win32 surface at runtime through
`QLibrary::resolve()` / `GetProcAddress()`. A `NULL` there does not fail loudly;
Qt either degrades or asserts later. The index records these separately — <!--B:STATS_DYN-->82 APIs have a dynamic (`resolve`/`GetProcAddress`) site, 38 of which are reached *only* dynamically<!--E:STATS_DYN-->:

| API | Qt site | Wine status |
|---|---|---|
| `SkipPointerFrameMessages` | `qwindowscontext.cpp:211` | **not exported by Wine** (see §3.1) |
| `GetPointerInfo`, `GetPointerTouchInfo`, `GetPointerFrameTouchInfo*`, `GetPointerPenInfo*`, `GetPointerType`, `GetPointerDeviceRects` | `qwindowscontext.cpp:202-210` | implemented in `user32` |
| `EnableMouseInPointer` | `qwindowscontext.cpp:202` | forward to `win32u.NtUserEnableMouseInPointer` |
| `AdjustWindowRectExForDpi`, `EnableNonClientDpiScaling`, `GetWindowDpiAwarenessContext`, `GetAwarenessFromDpiAwarenessContext`, `SystemParametersInfoForDpi` | `qwindowscontext.cpp:216-220` | implemented in `user32` |
| `GetDpiForMonitor`, `GetProcessDpiAwareness`, `SetProcessDpiAwareness` | `qwindowscontext.cpp:236-238` | implemented in `shcore` |
| `AddClipboardFormatListener`, `RemoveClipboardFormatListener` | `qwindowscontext.cpp:195-196` | implemented in `user32` |
| `SetProcessDPIAware` | `qwindowscontext.cpp:193` | implemented in `user32` |
| `GetDisplayAutoRotationPreferences`, `SetDisplayAutoRotationPreferences` | `qwindowscontext.cpp:198-199` | sett* is a **FIXME stub body**, getter implemented (§3.2) |
| `WT*` (7 entry points) | `qwindowstabletsupport.cpp:185-193` | implemented in Wine's `wintab32` |
| `wgl*` + `glGetError/GetIntegerv/GetString` | `qwindowsglcontext.cpp:190-203` | implemented in `opengl32` |
| `Direct3DCreate9` | `qwindowsopengltester.cpp:107` | implemented in `d3d9` |
| `DWriteCreateFactory` | `qwindowsfontdatabase.cpp:81,104` | implemented in `dwrite` |
| `GetOpenFileNameW`, `GetSaveFileNameW`, `ChooseColorW` | `qwindowsdialoghelpers.cpp:1722,1723,2050` | implemented in `comdlg32` |
| `Uia*` (5 entry points) | `qwindowsuiawrapper.cpp:52-57` | present, but events are **FIXME stubs** (§3.2) |
| `RoGetActivationFactory`, `WindowsCreateStringReference` | `qwin10helpers.cpp:122-124` | implemented in `combase` |
| `vkGetInstanceProcAddr` (+ the `vk*` table) | `qbasicvulkanplatforminstance.cpp:114` | implemented in `vulkan-1` (Wine `winevulkan`) |
| `eglGetDisplay`, `eglGetPlatformDisplayEXT` | `qwindowseglcontext.cpp:135,159` | **Qt-bundled ANGLE** `libEGL.dll`; Wine ships no `libEGL` (expected) |

`gl*`/`wgl*` **extension** entry points (`glCreateShader`, `glGetStringi`,
`wglCreateContextAttribsARB`, `wglChoosePixelFormatARB`, `wglSwapIntervalEXT`, …)
are not DLL exports on Windows either — they are fetched through
`wglGetProcAddress`. Wine's `opengl32` implements them in
`dlls/opengl32/thunks.c` and gates them on the reported extension string, so the
thing to inspect in a trace is `wglGetProcAddress` / `wglGetExtensionsStringARB`,
not the individual symbol.

### 2.5 Full generated index (appendix)

<!--B:QT_FULL-->
| Win32 API | Wine DLL | Status | Qt source (first site) | What Qt expects |
|---|---|---|---|---|
| `AcceptSecurityContext` | secur32 | impl | src/network/ssl/qsslsocket_schannel.cpp:870 | `auto status = AcceptSecurityContext(` |
| `AccessCheck` | kernelbase | impl | src/corelib/io/qfilesystemengine_win.cpp:876 | `if (::AccessCheck(pSD, currentUserImpersonatedToken, genericAccessRights,` |
| `AcquireCredentialsHandleW` | secur32 | impl | src/network/kernel/qauthenticator.cpp:1534 | SChannel/SSPI credential acquisition (qsslsocket_schannel.cpp) |
| `AddAccessAllowedAce` | kernelbase | impl | src/network/socket/qlocalserver_win.cpp:147 | `if (!AddAccessAllowedAce(acl, ACL_REVISION, FILE_ALL_ACCESS, pTokenUser->User.Sid)) {` |
| `AddClipboardFormatListener` | user32 | forward | src/plugins/platforms/windows/qwindowsclipboard.cpp:198 | `qErrnoWarning("AddClipboardFormatListener() failed.");` |
| `AddFontMemResourceEx` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontdatabase.cpp:1314 | load embedded application fonts (QFontDatabase::addApplicationFont) |
| `AddFontResourceExW` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontdatabase.cpp:1618 | install application fonts for the process |
| `AdjustWindowRectEx` | user32 | impl | src/plugins/platforms/windows/qwindowswindow.cpp:925 | convert client geometry to frame geometry; FALSE => geometry is wrong |
| `AdjustWindowRectExForDpi` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:216 | `adjustWindowRectExForDpi = (AdjustWindowRectExForDpi)library.resolve("AdjustWindowRectExForDpi");` |
| `AllocateAndInitializeSid` | kernelbase | impl | src/corelib/io/qfilesystemengine_win.cpp:233 | `if (AllocateAndInitializeSid(&worldAuth, 1, SECURITY_WORLD_RID, 0, 0, 0, 0, 0, 0, 0, &worldSID))` |
| `AlphaBlend` | msimg32 | forward | src/gui/painting/qpainter.cpp:141 | `\| QPaintEngine::AlphaBlend` |
| `AppendMenuW` | user32 | impl | src/plugins/platforms/windows/qwindowsmenu.cpp:477 | `AppendMenu(menu->menuHandle(), state(), m_id, qStringToWChar(text));` |
| `ApplyControlToken` | secur32 | impl | src/network/ssl/qsslsocket_schannel.cpp:1445 | TLS shutdown (SCHANNEL_SHUTDOWN) |
| `AttachThreadInput` | user32 | forward | src/plugins/platforms/windows/qwindowswindow.cpp:2554 | `attached = AttachThreadInput(foregroundThread, currentThread, TRUE) == TRUE;` |
| `BCryptCloseAlgorithmProvider` | bcrypt | impl | src/network/ssl/qsslkey_schannel.cpp:125 | balance BCryptOpenAlgorithmProvider |
| `BCryptDecrypt` | bcrypt | impl | src/network/ssl/qsslkey_schannel.cpp:139 | `auto cryptFunction = encrypt ? BCryptEncrypt : BCryptDecrypt;` |
| `BCryptDestroyKey` | bcrypt | impl | src/network/ssl/qsslkey_schannel.cpp:111 | `BCryptDestroyKey(keyHandle);` |
| `BCryptEncrypt` | bcrypt | impl | src/network/ssl/qsslkey_schannel.cpp:139 | `auto cryptFunction = encrypt ? BCryptEncrypt : BCryptDecrypt;` |
| `BCryptGenerateSymmetricKey` | bcrypt | impl | src/network/ssl/qsslkey_schannel.cpp:89 | `NTSTATUS status = BCryptGenerateSymmetricKey(` |
| `BCryptOpenAlgorithmProvider` | bcrypt | impl | src/network/ssl/qsslkey_schannel.cpp:71 | bcrypt hash/cipher (hash lib in Qt 5.15 was moved out of QtCore, but QtWebEngine/Chromium use it) |
| `BCryptSetProperty` | bcrypt | impl | src/network/ssl/qsslkey_schannel.cpp:103 | `status = BCryptSetProperty(` |
| `BeginPaint` | user32 | forward | src/plugins/platforms/windows/qwindowswindow.cpp:2095 | `BeginPaint(hwnd, &ps);` |
| `BitBlt` | gdi32 | impl | src/plugins/platforms/windows/qwindowsbackingstore.cpp:119 | blit backing store to the window DC |
| `BuildTrusteeWithSidW` | advapi32 | impl | src/corelib/io/qfilesystemengine_win.cpp:217 | `BuildTrusteeWithSid(&currentUserTrusteeW, currentUserSID);` |
| `CM_Get_Device_IDA` | setupapi | forward | src/3rdparty/angle/src/gpu_info_util/SystemInfo_win.cpp:96 | `if (CM_Get_Device_IDA(deviceData.DevInst, fullDeviceID, MAX_DEVICE_ID_LEN, 0) != CR_SUCCESS)` |
| `CallNextHookEx` | user32 | forward | src/corelib/kernel/qeventdispatcher_win.cpp:291 | `return d->getMessageHook ? CallNextHookEx(0, code, wp, lp) : 0;` |
| `CallWindowProcW` | user32 | impl | src/3rdparty/angle/src/libANGLE/renderer/d3d/SurfaceD3D.cpp:279 | `return CallWindowProc(prevWndFunc, hwnd, message, wparam, lparam);` |
| `CancelIoEx` | kernel32 | forward | src/corelib/io/qwindowspipereader.cpp:101 | abort overlapped I/O for QWindowsPipeReader |
| `CertAddCertificateContextToStore` | crypt32 | impl | src/network/ssl/qwindowscarootfetcher.cpp:269 | `if (CertAddCertificateContextToStore(customStore.get(), winCert, CERT_STORE_ADD_ALWAYS, nullptr))` |
| `CertAddStoreToCollection` | crypt32 | impl | src/network/ssl/qsslsocket_schannel.cpp:1762 | `} else if (!CertAddStoreToCollection(tempCertCollection.get(), rootStore.get(), 0, 1)) {` |
| `CertCloseStore` | crypt32 | impl | src/network/ssl/qsslsocket_openssl.cpp:901 | close certificate stores |
| `CertCreateCertificateContext` | crypt32 | impl | src/network/ssl/qwindowscarootfetcher.cpp:150 | `PCCERT_CONTEXT wincert = CertCreateCertificateContext(X509_ASN_ENCODING, (const BYTE *)der.constData(), der.length());` |
| `CertDuplicateCertificateContext` | crypt32 | impl | src/network/ssl/qsslcertificate_qt.cpp:213 | `certificateContext = CertDuplicateCertificateContext(certificateContext);` |
| `CertFindCertificateInStore` | crypt32 | impl | src/network/ssl/qsslsocket_openssl.cpp:893 | certificate lookup |
| `CertFindChainInStore` | crypt32 | impl | src/network/ssl/qsslsocket_schannel.cpp:661 | `chainContext = CertFindChainInStore(localCertificateStore.get(),` |
| `CertFreeCertificateChain` | crypt32 | impl | src/network/ssl/qsslsocket_schannel.cpp:641 | `CertFreeCertificateChain(chainContext);` |
| `CertFreeCertificateContext` | crypt32 | impl | src/network/ssl/qsslsocket_schannel.cpp:574 | free certificate contexts |
| `CertGetCertificateChain` | crypt32 | impl | src/network/ssl/qsslsocket_schannel.cpp:1801 | `BOOL status = CertGetCertificateChain(nullptr, // hChainEngine, default` |
| `CertOpenStore` | crypt32 | impl | src/network/ssl/qsslsocket_schannel.cpp:1739 | certificate store access (SChannel backend, qsslcertificate_winrt / TLS) |
| `CertOpenSystemStoreW` | crypt32 | impl | src/network/ssl/qsslsocket_openssl.cpp:889 | `hSystemStore = CertOpenSystemStoreW(0, L"ROOT");` |
| `CertVerifyTimeValidity` | crypt32 | impl | src/network/ssl/qsslsocket_schannel.cpp:1888 | `LONG result = CertVerifyTimeValidity(nullptr /*== now */, element->pCertContext->pCertInfo);` |
| `ChangeClipboardChain` | user32 | forward | src/plugins/platforms/windows/qwindowsclipboard.cpp:216 | `ChangeClipboardChain(m_clipboardViewer, m_nextClipboardViewer);` |
| `ChangeWindowMessageFilterEx` | user32 | impl | src/plugins/platforms/windows/qwindowssystemtrayicon.cpp:326 | `ChangeWindowMessageFilterEx(m_hwnd, MYWM_TASKBARCREATED, MSGFLT_ALLOW, nullptr);` |
| `CharNextExA` | user32 | forward | src/corelib/codecs/qwindowscodec.cpp:167 | `while ((next = CharNextExA(CP_ACP, mb, 0)) != mb) {` |
| `CheckRemoteDebuggerPresent` | kernel32 | forward | src/plugins/platforms/windows/qwindowsclipboard.cpp:236 | `CheckRemoteDebuggerPresent(processHandle, &debugged);` |
| `ChildWindowFromPointEx` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:804 | `const HWND child = ChildWindowFromPointEx(*hwnd, point, cwexFlags);` |
| `ChooseColorW` | comdlg32 | impl | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:2050 | native colour dialog |
| `ChoosePixelFormat` | gdi32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:439 | select a pixel format for a window DC |
| `CloseHandle` | kernel32 | forward | src/plugins/platforms/windows/qwindowsclipboard.cpp:237 | balance every handle; failure puts Qt into a debug assertion |
| `CloseTouchInputHandle` | user32 | impl | src/plugins/platforms/windows/qwindowsmousehandler.cpp:676 | `CloseTouchInputHandle(reinterpret_cast<HTOUCHINPUT>(msg.lParam));` |
| `CoCreateGuid` | ole32 | forward | src/platformsupport/fontdatabases/windows/qwindowsfontdatabase.cpp:1294 | `CoCreateGuid(&guid);` |
| `CoCreateInstance` | ole32 | forward | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:706 | create OLE/shell objects (drag&drop, file dialogs, taskbar) |
| `CoGetMalloc` | ole32 | forward | src/plugins/platforms/windows/qwindowsole.cpp:271 | `if (CoGetMalloc(MEMCTX_TASK, &pmalloc) == NOERROR) {` |
| `CoInitialize` | ole32 | impl | src/plugins/platforms/windows/qwindowstheme.cpp:918 | `static HRESULT comInit = CoInitialize(nullptr);` |
| `CoInitializeEx` | ole32 | forward | src/plugins/platforms/windows/qwindowsservices.cpp:62 | COM apartment init (Qt uses STA in the GUI thread) |
| `CoLockObjectExternal` | ole32 | forward | src/plugins/platforms/windows/qwindowswindow.cpp:1489 | `CoLockObjectExternal(m_dropTarget, true, true);` |
| `CoTaskMemFree` | ole32 | forward | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:640 | free shell-allocated strings |
| `CoUninitialize` | ole32 | forward | src/plugins/platforms/windows/qwindowsservices.cpp:64 | balance CoInitializeEx |
| `CombineRgn` | gdi32 | forward | src/plugins/platforms/windows/qwindowswindow.cpp:2496 | `if (CombineRgn(result, *winRegion, rectRegion, RGN_OR)) {` |
| `CompareStringEx` | kernel32 | forward | src/corelib/text/qcollator_win.cpp:116 | `const int ret = CompareStringEx(LPCWSTR(d->localeName.utf16()), d->collator,` |
| `CompareStringW` | kernel32 | forward | src/corelib/text/qcollator_win.cpp:112 | collation (QCollator) |
| `CompleteAuthToken` | secur32 | impl | src/network/kernel/qauthenticator.cpp:1596 | `secStatus = pSecurityFunctionTable->CompleteAuthToken(&ctx->sspiWindowsHandles->ctxHandle,` |
| `ConnectNamedPipe` | kernel32 | forward | src/corelib/io/qprocess_win.cpp:154 | accept a local socket connection; ERROR_PIPE_CONNECTED is success |
| `ConvertInterfaceIndexToLuid` | iphlpapi | impl | src/network/kernel/qnetconmonitor_win.cpp:278 | map ifindex -> LUID |
| `ConvertInterfaceLuidToGuid` | iphlpapi | impl | src/network/kernel/qnetconmonitor_win.cpp:283 | map LUID -> interface GUID for QNetworkInterface |
| `ConvertInterfaceLuidToIndex` | iphlpapi | impl | src/network/kernel/qnetworkinterface_win.cpp:96 | `&& ConvertInterfaceLuidToIndex(&luid, &id) == NO_ERROR)` |
| `ConvertInterfaceLuidToNameW` | iphlpapi | impl | src/network/kernel/qnetworkinterface_win.cpp:106 | `if (ConvertInterfaceLuidToNameW(&luid, buf, sizeof(buf)/sizeof(buf[0])) == NO_ERROR)` |
| `ConvertInterfaceNameToLuidW` | iphlpapi | impl | src/network/kernel/qnetworkinterface_win.cpp:95 | `if (ConvertInterfaceNameToLuidW(reinterpret_cast<const wchar_t *>(name.constData()), &luid) == NO_ERROR` |
| `ConvertSidToStringSidW` | advapi32 | forward | src/network/socket/qlocalserver_win.cpp:121 | `if (ConvertSidToStringSid(pTokenGroup->PrimaryGroup, &groupNameSid)) {` |
| `CopyFile2` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:1485 | `HRESULT hres = ::CopyFile2((const wchar_t*)source.nativeFilePath().utf16(),` |
| `CopyFileW` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:1479 | `bool ret = ::CopyFile((wchar_t*)source.nativeFilePath().utf16(),` |
| `CopyImage` | user32 | impl | src/gui/rhi/qrhivulkan.cpp:3134 | `cmd.cmd = QVkCommandBuffer::Command::CopyImage;` |
| `CopySid` | kernelbase | impl | src/corelib/io/qfilesystemengine_win.cpp:216 | `if (::CopySid(sidLen, currentUserSID, tokenSid))` |
| `CreateBitmap` | gdi32 | impl | src/plugins/platforms/windows/qwindowsinputcontext.cpp:172 | `m_transparentBitmap = CreateBitmap(2, 2, 1, 1, &bmpData);` |
| `CreateCaret` | user32 | forward | src/plugins/platforms/windows/qwindowsinputcontext.cpp:276 | `m_caretCreated = CreateCaret(platformWindow->handle(), m_transparentBitmap, 0, 0);` |
| `CreateCompatibleBitmap` | gdi32 | impl | src/plugins/platforms/windows/qwindowsscreen.cpp:218 | backing store bitmap |
| `CreateCompatibleDC` | gdi32 | forward | src/plugins/platforms/windows/qwindowsscreen.cpp:217 | memory DC for backing store / pixmaps |
| `CreateCursor` | user32 | impl | src/plugins/platforms/windows/qwindowscursor.cpp:163 | `return CreateCursor(GetModuleHandle(nullptr), hotSpot.x(), hotSpot.y(), width, height,` |
| `CreateDCW` | gdi32 | impl | src/plugins/platforms/windows/qwindowsscreen.cpp:94 | screen/display DC for GDI painting and font metrics |
| `CreateDIBSection` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsnativeimage.cpp:101 | top-down DIB for QImage on Windows (shared pixel memory) |
| `CreateDXGIFactory` | dxgi | impl | src/3rdparty/angle/src/gpu_info_util/SystemInfo_win.cpp:146 | legacy DXGI factory path |
| `CreateDXGIFactory1` | dxgi | impl | src/gui/rhi/qrhid3d11.cpp:189 | enumerate adapters for ANGLE/GL (and GPU blacklist checks) |
| `CreateDXGIFactory2` | dxgi | impl | src/gui/rhi/qrhid3d11.cpp:176 | `qWarning("CreateDXGIFactory2() failed to create DXGI factory: %s", qPrintable(comErrorMessage(hr)));` |
| `CreateDirectoryW` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:1183 | already listed |
| `CreateEventExW` | kernel32 | forward | src/corelib/thread/qthread_win.cpp:231 | event with explicit access for the dispatcher |
| `CreateEventW` | kernel32 | forward | src/corelib/kernel/qeventdispatcher_win.cpp:884 | manual/auto-reset events for QEventDispatcherWin32's wakeup pipe and QThread |
| `CreateFile2` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:739 | `CreateFile2((const wchar_t*)entry.nativeFilePath().utf16(), 0,` |
| `CreateFileMappingFromApp` | kernel32 | forward | src/corelib/kernel/qsharedmemory_win.cpp:140 | `hand = CreateFileMappingFromApp(INVALID_HANDLE_VALUE, 0, PAGE_READWRITE, size,` |
| `CreateFileMappingW` | kernel32 | forward | src/corelib/kernel/qsharedmemory_win.cpp:143 | QSharedMemory |
| `CreateFileW` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:292 | open files, pipes (\\.\pipe\...), devices (\\.\DISPLAY1) and console handles; INVALID_HANDLE_VALUE => Qt error |
| `CreateFontIndirectW` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontdatabase.cpp:923 | logical font creation in the GDI font engine |
| `CreateIconIndirect` | user32 | impl | src/plugins/platforms/windows/qwindowscursor.cpp:126 | QIcon -> HICON conversion (tray/taskbar) |
| `CreateMenu` | user32 | forward | src/plugins/platforms/windows/qwindowsmenu.cpp:495 | `QWindowsMenu::QWindowsMenu() : QWindowsMenu(nullptr, CreateMenu())` |
| `CreateNamedPipeW` | kernel32 | forward | src/corelib/io/qprocess_win.cpp:118 | QProcess/QLocalServer named pipes |
| `CreatePopupMenu` | user32 | forward | src/plugins/platforms/windows/qwindowsmenu.cpp:683 | context/native menus |
| `CreateProcessW` | kernel32 | forward | src/plugins/platforms/windows/qwindowsservices.cpp:150 | QProcess start; FALSE => QProcess::FailedToStart with GetLastError |
| `CreateRectRgn` | gdi32 | forward | src/plugins/platforms/windows/qwindowswindow.cpp:370 | `blurBehind.hRgnBlur = CreateRectRgn(0, 0, -1, -1);` |
| `CreateSemaphoreExW` | kernel32 | forward | src/corelib/kernel/qsystemsemaphore_win.cpp:89 | `semaphore = CreateSemaphoreEx(0, initialValue, MAXLONG,` |
| `CreateSemaphoreW` | kernel32 | forward | src/corelib/kernel/qsystemsemaphore_win.cpp:93 | QSystemSemaphore |
| `CreateThread` | kernel32 | forward | src/corelib/thread/qthread_win.cpp:236 | QThread::start on the Win32 path (Qt uses _beginthreadex by preference) |
| `CreateWindowExW` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:909 | create the native HWND; NULL => Qt aborts platform window creation (check class registration, DPI awareness, window station) |
| `D3D11CreateDevice` | d3d11 | impl | src/gui/rhi/qrhid3d11.cpp:264 | hardware rasterizer for Qt Quick via ANGLE; failure => Qt falls back to software GL (opengl32sw) |
| `D3DCompile` | d3dcompiler_43 | impl | src/gui/rhi/qrhid3d11.cpp:3652 | `qWarning("Unable to resolve function D3DCompile()");` |
| `D3DDisassemble` | d3dcompiler_43 | impl | src/3rdparty/angle/src/libANGLE/renderer/d3d/HLSLCompiler.cpp:181 | `mD3DDisassembleFunc = reinterpret_cast<pD3DDisassemble>(D3DDisassemble);` |
| `D3DPERF_BeginEvent` | d3d9 | impl | src/3rdparty/angle/src/libANGLE/renderer/d3d/d3d9/DebugAnnotator9.cpp:18 | `D3DPERF_BeginEvent(0, eventName);` |
| `D3DPERF_EndEvent` | d3d9 | impl | src/3rdparty/angle/src/libANGLE/renderer/d3d/d3d9/DebugAnnotator9.cpp:23 | `D3DPERF_EndEvent();` |
| `D3DPERF_GetStatus` | d3d9 | impl | src/3rdparty/angle/src/libANGLE/renderer/d3d/d3d9/DebugAnnotator9.cpp:33 | `return !!D3DPERF_GetStatus();` |
| `D3DPERF_SetMarker` | d3d9 | impl | src/3rdparty/angle/src/libANGLE/renderer/d3d/d3d9/DebugAnnotator9.cpp:28 | `D3DPERF_SetMarker(0, markerName);` |
| `DCompositionCreateDevice` | dcomp | impl | src/3rdparty/angle/src/libANGLE/renderer/d3d/d3d11/win32/NativeWindow11Win32.cpp:80 | `GetProcAddress(dcomp, "DCompositionCreateDevice"));` |
| `DWriteCreateFactory` | dwrite | impl | src/platformsupport/fontdatabases/windows/qwindowsfontdatabase.cpp:104 | DirectWrite factory for the DirectWrite font engine (Qt uses it when DWrite is available) |
| `DecryptMessage` | secur32 | impl | src/network/ssl/qsslsocket_schannel.cpp:1351 | TLS record decryption; SEC_E_INCOMPLETE_MESSAGE is normal |
| `DefWindowProcW` | user32 | forward | src/plugins/platforms/windows/qwindowsclipboard.cpp:145 | default handling of unhandled window messages; Qt relies on it for non-Qt classes |
| `DeleteDC` | gdi32 | impl | src/plugins/platforms/windows/qwindowsscreen.cpp:103 | `DeleteDC(hdc);` |
| `DeleteFileW` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:1531 | QFile::remove |
| `DeleteObject` | gdi32 | impl | src/plugins/platforms/windows/qwindowscursor.cpp:128 | `DeleteObject(ic);` |
| `DeleteSecurityContext` | secur32 | impl | src/network/kernel/qauthenticator.cpp:1602 | release TLS contexts |
| `DescribePixelFormat` | gdi32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:220 | probe pixel format capabilities |
| `DestroyCaret` | user32 | forward | src/plugins/platforms/windows/qwindowsinputcontext.cpp:303 | `DestroyCaret();` |
| `DestroyCursor` | user32 | impl | src/plugins/platforms/windows/qwindowscursor.cpp:791 | free loaded cursors |
| `DestroyIcon` | user32 | impl | src/plugins/platforms/windows/qwindowssystemtrayicon.cpp:223 | free loaded icons |
| `DestroyMenu` | user32 | forward | src/plugins/platforms/windows/qwindowsmenu.cpp:514 | `DestroyMenu(m_hMenu);` |
| `DestroyWindow` | user32 | forward | src/plugins/platforms/windows/qwindowsclipboard.cpp:219 | must succeed; failure is logged and leaked HWNDs accumulate |
| `DeviceIoControl` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:304 | `if (::DeviceIoControl(handle, FSCTL_GET_REPARSE_POINT, 0, 0, rdb, bufsize, &retsize, 0)) {` |
| `Direct3DCreate9` | d3d9 | impl | src/3rdparty/angle/src/libANGLE/renderer/d3d/d3d9/Renderer9.cpp:209 | `mD3d9 = Direct3DCreate9(D3D_SDK_VERSION);` |
| `Direct3DCreate9Ex` | d3d9 | impl | src/3rdparty/angle/src/libANGLE/renderer/d3d/d3d9/Renderer9.cpp:192 | `reinterpret_cast<Direct3DCreate9ExFunc>(GetProcAddress(mD3d9Module, "Direct3DCreate9Ex"));` |
| `DisconnectNamedPipe` | kernel32 | forward | src/network/socket/qlocalsocket_win.cpp:115 | `DisconnectNamedPipe(handle);` |
| `DispatchMessageW` | user32 | impl | src/corelib/kernel/qeventdispatcher_win.cpp:607 | deliver messages to the Qt window proc |
| `DnsQuery_W` | dnsapi | impl | src/network/kernel/qdnslookup_win.cpp:74 | direct DNS query path (dnsapi) |
| `DnsRecordListFree` | dnsapi | impl | src/network/kernel/qdnslookup_win.cpp:163 | `DnsRecordListFree(dns_records, DnsFreeRecordList);` |
| `DoDragDrop` | ole32 | impl | src/plugins/platforms/windows/qwindowsdrag.cpp:700 | QWindowsDrag::drag runs the OLE drag&drop loop |
| `DrawIconEx` | user32 | forward | src/gui/image/qpixmap_win.cpp:548 | `DrawIconEx(hdc, 0, 0, icon, w, h, 0, nullptr, DI_NORMAL);` |
| `DrawMenuBar` | user32 | forward | src/plugins/platforms/windows/qwindowsmenu.cpp:859 | native menu redraw |
| `DuplicateHandle` | kernel32 | forward | src/corelib/io/qprocess_win.cpp:186 | pass handles to child processes (QProcess pipe inheritance) |
| `DuplicateToken` | kernelbase | impl | src/corelib/io/qfilesystemengine_win.cpp:226 | `::DuplicateToken(token, SecurityImpersonation, &currentUserImpersonatedToken);` |
| `DwmEnableBlurBehindWindow` | dwmapi | impl | src/plugins/platforms/windows/qwindowswindow.cpp:376 | `const bool result = DwmEnableBlurBehindWindow(hwnd, &blurBehind) == S_OK;` |
| `DwmGetWindowAttribute` | dwmapi | impl | src/plugins/platforms/windows/qwindowswindow.cpp:2928 | `SUCCEEDED(DwmGetWindowAttribute(hwnd, DwmwaUseImmersiveDarkMode, &result, sizeof(result)))` |
| `DwmIsCompositionEnabled` | dwmapi | impl | src/plugins/platforms/windows/qwindowswindow.cpp:362 | `if (DwmIsCompositionEnabled(&compositionEnabled) != S_OK)` |
| `DwmSetWindowAttribute` | dwmapi | impl | src/plugins/platforms/windows/qwindowswindow.cpp:2939 | `SUCCEEDED(DwmSetWindowAttribute(hwnd, DwmwaUseImmersiveDarkMode, &darkBorder, sizeof(darkBorder)))` |
| `Ellipse` | gdi32 | impl | src/gui/painting/qregion.cpp:263 | `rgn = QRegion(r, id == QRGN_SETRECT ? Rectangle : Ellipse);` |
| `EnableMenuItem` | user32 | forward | src/plugins/platforms/windows/qwindowskeymapper.cpp:798 | `EnableMenuItem(menu, SC_MINIMIZE, (topLevel->flags() & Qt::WindowMinimizeButtonHint)?enabled:disabled);` |
| `EnableMouseInPointer` | user32 | forward | src/plugins/platforms/windows/qwindowscontext.cpp:202 | `enableMouseInPointer = (EnableMouseInPointer)library.resolve("EnableMouseInPointer");` |
| `EnableNonClientDpiScaling` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:168 | `qErrnoWarning(int(errorCode), "EnableNonClientDpiScaling() failed for HWND %p (%lu)",` |
| `EncryptMessage` | secur32 | impl | src/network/ssl/qsslsocket_schannel.cpp:1276 | TLS record encryption |
| `EndPaint` | user32 | forward | src/plugins/platforms/windows/qwindowswindow.cpp:2111 | `EndPaint(hwnd, &ps);` |
| `EnumAdapters` |  | not-an-export | src/3rdparty/angle/src/gpu_info_util/SystemInfo_win.cpp:153 | adapter enumeration for qwindowsopengltester GPU detection |
| `EnumDisplayDevicesA` | user32 | impl | src/3rdparty/angle/src/gpu_info_util/SystemInfo_win.cpp:45 | `for (int i = 0; EnumDisplayDevicesA(nullptr, i, &displayDevice, 0); ++i)` |
| `EnumDisplayDevicesW` | user32 | impl | src/plugins/platforms/windows/qwindowsopengltester.cpp:156 | `for (int dev = 0; EnumDisplayDevices(nullptr, dev, &dd, 0); ++dev) {` |
| `EnumDisplayMonitors` | user32 | forward | src/plugins/platforms/windows/qwindowsscreen.cpp:145 | enumerate QScreens |
| `EnumDynamicTimeZoneInformation` | kernelbase | impl | src/corelib/time/qtimezoneprivate_win.cpp:211 | `while (SUCCEEDED(EnumDynamicTimeZoneInformation(index++, &dtzInfo))) {` |
| `EnumFontFamiliesExW` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontdatabase.cpp:1184 | enumerate installed families for QFontDatabase |
| `EnumWindows` | user32 | impl | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:372 | `EnumWindows(findDialogEnumWindowsProc, reinterpret_cast<LPARAM>(&context));` |
| `ExitThread` | kernel32 | forward | src/corelib/thread/qthread_win.cpp:677 | `ExitThread(0);` |
| `ExpandEnvironmentStringsW` | kernel32 | forward | src/plugins/platforms/windows/qwindowsservices.cpp:118 | path expansion |
| `ExtTextOutW` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontengine.cpp:1048 | `ExtTextOut(hdc, 0, 0, options, 0, reinterpret_cast<LPCWSTR>(&glyph), 1, 0);` |
| `FileTimeToSystemTime` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:1663 | `FileTimeToSystemTime(time, &sTime);` |
| `FillPath` | gdi32 | impl | src/gui/painting/qpdf.cpp:390 | `case FillPath:` |
| `FindClose` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:420 | close enumeration handle |
| `FindCloseChangeNotification` | kernel32 | forward | src/corelib/io/qfilesystemwatcher_win.cpp:443 | `FindCloseChangeNotification(hit.value().handle);` |
| `FindFirstChangeNotificationW` | kernel32 | forward | src/corelib/io/qfilesystemwatcher_win.cpp:82 | `const HANDLE result = FindFirstChangeNotification(reinterpret_cast<const wchar_t *>(nativePath.utf16()),` |
| `FindFirstFileExW` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:417 | directory enumeration for QDirIterator/QFileSystemWatcher |
| `FindFirstFileW` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:415 | `HANDLE hFind = ::FindFirstFile((wchar_t*)path.utf16(), &findData);` |
| `FindNextChangeNotification` | kernel32 | forward | src/corelib/io/qfilesystemwatcher_win.cpp:648 | `str += QLatin1String("QFileSystemWatcher: FindNextChangeNotification failed for");` |
| `FindNextFileW` | kernel32 | forward | src/corelib/io/qfilesystemiterator_win.cpp:122 | continue FindFirstFileExW enumeration |
| `FindTextW` | comdlg32 | impl | src/plugins/platforms/windows/uiautomation/qwindowsuiatextrangeprovider.cpp:522 | `HRESULT QWindowsUiaTextRangeProvider::FindText(BSTR /* text */, BOOL /* backward */,` |
| `FindWindowA` | user32 | impl | src/plugins/platforms/windows/qwindowsinputcontext.cpp:228 | `return ::FindWindowA("IPTip_Main_Window", nullptr);` |
| `FlashWindowEx` | user32 | forward | src/plugins/platforms/windows/qwindowswindow.cpp:2854 | `FlashWindowEx(&info);` |
| `FlsAlloc` | kernel32 | forward | src/corelib/thread/qthread_win.cpp:70 | `return FlsAlloc(0);` |
| `FlsFree` | kernel32 | forward | src/corelib/thread/qthread_win.cpp:74 | `return FlsFree(dwTlsIndex);` |
| `FlsGetValue` | kernel32 | forward | src/corelib/thread/qthread_win.cpp:78 | `return FlsGetValue(dwTlsIndex);` |
| `FlsSetValue` | kernel32 | forward | src/corelib/thread/qthread_win.cpp:82 | `return FlsSetValue(dwTlsIndex, lpTlsValue);` |
| `FlushFileBuffers` | kernel32 | forward | src/corelib/io/qfsfileengine_win.cpp:219 | QFile::flush |
| `FormatMessageW` | kernel32 | forward | src/plugins/platforms/windows/qwindowscontext.cpp:706 | human-readable text for qSystemError/qt_errorString |
| `FreeContextBuffer` | secur32 | impl | src/network/kernel/qauthenticator.cpp:1607 | free SSPI output buffers |
| `FreeCredentialsHandle` | secur32 | impl | src/network/kernel/qauthenticator.cpp:1601 | release credentials |
| `FreeEnvironmentStringsW` | kernel32 | forward | src/corelib/io/qprocess_win.cpp:82 | free QProcess environment block |
| `FreeLibrary` | kernel32 | forward | src/corelib/plugin/qlibrary_win.cpp:158 | unload a plugin DLL |
| `FreeSid` | kernelbase | impl | src/corelib/io/qfilesystemengine_win.cpp:184 | `::FreeSid(worldSID);` |
| `GdiFlush` | gdi32 | forward | src/platformsupport/fontdatabases/windows/qwindowsnativeimage.cpp:127 | `GdiFlush();` |
| `GetAdaptersAddresses` | iphlpapi | impl | src/network/kernel/qnetworkinterface_win.cpp:122 | QNetworkInterface enumeration (iphlpapi); ERROR_BUFFER_OVERFLOW means realloc and retry |
| `GetAncestor` | user32 | forward | src/plugins/platforms/windows/qwindowswindow.cpp:1531 | `HWND parentHWND = GetAncestor(ww->handle(), GA_PARENT);` |
| `GetAsyncKeyState` | user32 | forward | src/plugins/platforms/windows/qwindowsmousehandler.cpp:169 | `if (GetAsyncKeyState(VK_LBUTTON) < 0)` |
| `GetAwarenessFromDpiAwarenessContext` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:219 | `getAwarenessFromDpiAwarenessContext = (GetAwarenessFromDpiAwarenessContext)library.resolve("GetAwarenessFromDpiAwarenessContext");` |
| `GetBitmapBits` | gdi32 | forward | src/plugins/platforms/windows/qwindowscursor.cpp:779 | `GetBitmapBits(iconInfo.hbmColor, colorBitsLength, colorBits);` |
| `GetCaretBlinkTime` | user32 | forward | src/plugins/platforms/windows/qwindowsintegration.cpp:534 | `if (const unsigned timeMS = GetCaretBlinkTime())` |
| `GetCharABCWidthsFloatW` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontengine.cpp:486 | `GetCharABCWidthsFloat(hdc, ch, ch, &abc);` |
| `GetCharABCWidthsI` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontengine.cpp:617 | `GetCharABCWidthsI(hdc, glyph, 1, 0, &abcWidths);` |
| `GetCharABCWidthsW` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontengine.cpp:653 | `GetCharABCWidths(hdc, tm.tmFirstChar, tm.tmLastChar, abc);` |
| `GetClassInfoW` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:638 | `const bool classExists = GetClassInfo(appInstance, reinterpret_cast<LPCWSTR>(cname.utf16()), &wcinfo) != FALSE` |
| `GetClientRect` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:1560 | client area size for backing store sizing |
| `GetClipboardFormatNameW` | user32 | forward | src/plugins/platforms/windows/qwindowsmime.cpp:1591 | reverse mapping of registered formats |
| `GetConsoleWindow` | kernel32 | forward | src/corelib/io/qprocess_win.cpp:561 | `DWORD dwCreationFlags = (GetConsoleWindow() ? 0 : CREATE_NO_WINDOW);` |
| `GetCurrencyFormatEx` | kernel32 | forward | src/corelib/text/qlocale_win.cpp:185 | `return GetCurrencyFormatEx(lcName, flags, value, format, data, size);` |
| `GetCurrencyFormatW` | kernel32 | forward | src/corelib/text/qlocale_win.cpp:183 | `return GetCurrencyFormat(lcid, flags, value, format, data, size);` |
| `GetCurrentDirectoryA` | kernel32 | forward | src/3rdparty/angle/src/common/system_utils_win.cpp:61 | `DWORD result = GetCurrentDirectoryA(static_cast<DWORD>(pathBuf.size()), pathBuf.data());` |
| `GetCurrentDirectoryW` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:1448 | QDir::currentPath |
| `GetCurrentProcess` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:199 | pseudo-handle used by many kernel32 calls |
| `GetCurrentProcessId` | kernel32 | forward | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:346 | logging/diagnostics |
| `GetCurrentThread` | kernel32 | forward | src/corelib/thread/qthread_win.cpp:156 | pseudo-handle for thread affinity calls |
| `GetCurrentThreadId` | kernel32 | forward | src/plugins/platforms/windows/qwindowswindow.cpp:2541 | QMutex/QThread identity |
| `GetCursor` | user32 | forward | src/plugins/platforms/windows/qwindowscursor.cpp:569 | `const HCURSOR currentCursor = GetCursor();` |
| `GetCursorInfo` | user32 | forward | src/plugins/platforms/windows/qwindowscursor.cpp:669 | `if (GetCursorInfo(&cursorInfo)) {` |
| `GetCursorPos` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:1149 | QCursor::pos |
| `GetDC` | user32 | forward | src/plugins/platforms/windows/qwindowscontext.cpp:292 | screen DC used to query OPENGL caps |
| `GetDIBits` | gdi32 | impl | src/gui/image/qpixmap_win.cpp:111 | read back GDI bitmap data into a QImage |
| `GetDateFormatEx` | kernel32 | forward | src/corelib/text/qlocale_win.cpp:194 | `return GetDateFormatEx(lcName, flags, date, format, data, size, NULL);` |
| `GetDateFormatW` | kernel32 | forward | src/corelib/text/qlocale_win.cpp:192 | QSystemLocale date formatting |
| `GetDesktopWindow` | user32 | impl | src/plugins/platforms/windows/qwindowsscreen.cpp:203 | parent for popups |
| `GetDeviceCaps` | gdi32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:293 | DPI (LOGPIXELSX/Y), bit depth, raster caps for the screen |
| `GetDiskFreeSpaceExW` | kernel32 | forward | src/corelib/io/qstorageinfo_win.cpp:173 | QStorageInfo bytes available |
| `GetDisplayAutoRotationPreferences` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:198 | `getDisplayAutoRotationPreferences = (GetDisplayAutoRotationPreferences)library.resolve("GetDisplayAutoRotationPreferences");` |
| `GetDoubleClickTime` | user32 | forward | src/plugins/platforms/windows/qwindowsintegration.cpp:552 | `if (const UINT ms = GetDoubleClickTime())` |
| `GetDpiForMonitor` | shcore | impl | src/plugins/platforms/windows/qwindowscontext.cpp:238 | per-monitor DPI (shcore); HRESULT failure falls back to GetDeviceCaps |
| `GetDriveTypeW` | kernel32 | forward | src/corelib/io/qfilesystemwatcher_win.cpp:302 | `if (GetDriveTypeW(devicePath + 4) != DRIVE_REMOVABLE)` |
| `GetDynamicTimeZoneInformation` | kernel32 | forward | src/corelib/time/qtimezoneprivate_win.cpp:321 | `if (SUCCEEDED(GetDynamicTimeZoneInformation(&dtzi)))` |
| `GetDynamicTimeZoneInformationEffectiveYears` | kernel32 | forward | src/corelib/time/qtimezoneprivate_win.cpp:605 | `if (GetDynamicTimeZoneInformationEffectiveYears(&dtzi, &firstYear, &lastYear)` |
| `GetEffectiveRightsFromAclW` | advapi32 | impl | src/corelib/io/qfilesystemengine_win.cpp:898 | `if (GetEffectiveRightsFromAclW(pDacl, &currentUserTrusteeW, &access_mask) != ERROR_SUCCESS)` |
| `GetEnvironmentStringsW` | kernel32 | forward | src/corelib/io/qprocess_win.cpp:70 | QProcess::systemEnvironment |
| `GetExitCodeProcess` | kernel32 | impl | src/corelib/io/qprocess_win.cpp:837 | QProcess exit status |
| `GetFileAttributesExW` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:1143 | QFileInfo attributes; FALSE => does not exist |
| `GetFileAttributesW` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:1202 | attributes/type (directory, reparse point, symlink) |
| `GetFileInformationByHandle` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:681 | QFileInfo identity (volume serial + file index) for QFileSystemEngine |
| `GetFileInformationByHandleEx` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:702 | `if (GetFileInformationByHandleEx(handle,` |
| `GetFileSize` | kernel32 | forward | src/platformsupport/fontdatabases/windows/qwindowsfontdatabase.cpp:390 | `HRESULT STDMETHODCALLTYPE GetFileSize(OUT UINT64 *fileSize);` |
| `GetFileType` | kernel32 | forward | src/corelib/io/qfsfileengine_win.cpp:438 | distinguish disk/pipe/char/file (Qt uses it for QFile) |
| `GetFileVersionInfoSizeW` | kernelbase | impl | src/corelib/kernel/qcoreapplication_win.cpp:139 | `DWORD versionInfoSize = GetFileVersionInfoSize(buffer.data(), nullptr);` |
| `GetFileVersionInfoW` | kernelbase | impl | src/corelib/kernel/qcoreapplication_win.cpp:142 | `if (GetFileVersionInfo(buffer.data(), 0, versionInfoSize, info.data())) {` |
| `GetFocus` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:1536 | current focus HWND |
| `GetFontData` | gdi32 | forward | src/platformsupport/fontdatabases/windows/qwindowsfontdatabase.cpp:937 | `DWORD bytes = GetFontData( hdc, name_tag, 0, 0, 0 );` |
| `GetForegroundWindow` | user32 | forward | src/plugins/platforms/windows/qwindowswindow.cpp:1595 | foreground window of the desktop |
| `GetFullPathNameW` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:606 | QDir::cleanPath/QFileInfo canonical path |
| `GetGeoInfoW` | kernel32 | forward | src/corelib/time/qtimezoneprivate_win.cpp:470 | `const int size = GetGeoInfo(id, GEO_ISO2, code, 3, 0);` |
| `GetGlyphIndicesW` | gdi32 | forward | src/platformsupport/fontdatabases/windows/qwindowsfontenginedirectwrite.cpp:425 | `HRESULT hr = m_directWriteFontFace->GetGlyphIndicesW(&ucs4, 1, &glyphIndex);` |
| `GetGlyphOutline` | gdi32 | forward | src/platformsupport/fontdatabases/windows/qwindowsfontengine.cpp:454 | `res = GetGlyphOutline(hdc, glyph, format, &gm, 0, 0, &mat);` |
| `GetIconInfo` | user32 | impl | src/plugins/platforms/windows/qwindowscursor.cpp:771 | HICON -> QPixmap conversion (drag images) |
| `GetKeyState` | user32 | forward | src/plugins/platforms/windows/qwindowskeymapper.cpp:958 | modifier state (Shift/Ctrl/Alt) for key events |
| `GetKeyboardLayout` | user32 | forward | src/plugins/platforms/windows/qwindowsinputcontext.cpp:102 | active layout; Qt caches per-thread layouts |
| `GetKeyboardLayoutList` | user32 | forward | src/plugins/platforms/windows/qwindowscontext.cpp:119 | enumerate layouts to detect layout switches |
| `GetKeyboardState` | user32 | forward | src/plugins/platforms/windows/qwindowskeymapper.cpp:693 | `GetKeyboardState(kbdBuffer);` |
| `GetLastError` | kernel32 | forward | src/plugins/platforms/windows/qwindowsbackingstore.cpp:121 | every failing Win32 call is decoded through this by Qt's qt_winerror/qSystemError |
| `GetLengthSid` | kernelbase | impl | src/corelib/io/qfilesystemengine_win.cpp:213 | `DWORD sidLen = ::GetLengthSid(tokenSid);` |
| `GetLocaleInfoEx` | kernel32 | forward | src/corelib/text/qlocale_win.cpp:212 | `return GetLocaleInfoEx(lcName, type, data, size);` |
| `GetLocaleInfoW` | kernel32 | forward | src/plugins/platforms/windows/qwindowskeymapper.cpp:669 | QLocale language/territory/number formats |
| `GetLogicalDrives` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:996 | `DWORD drivesBitmask = ::GetLogicalDrives();` |
| `GetLongPathNameW` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:1396 | QFileInfo canonical path |
| `GetMenu` | user32 | impl | src/plugins/platforms/windows/qwindowskeymapper.cpp:991 | `if (msgType == WM_SYSKEYDOWN && (nModifiers & AltAny) != 0 && GetMenu(msg.hwnd) != nullptr)` |
| `GetMenuItemInfoW` | user32 | impl | src/plugins/platforms/windows/qwindowsmenu.cpp:206 | menu item inspection |
| `GetMessageExtraInfo` | user32 | impl | src/plugins/platforms/windows/qwindowsmousehandler.cpp:308 | `const auto extraInfo = quint64(GetMessageExtraInfo());` |
| `GetMessageW` | user32 | impl | src/corelib/kernel/qeventdispatcher_win.cpp:476 | modal loop message pump |
| `GetModuleFileNameA` | kernel32 | forward | src/3rdparty/angle/src/common/system_utils_win.cpp:25 | `DWORD executablePathLen = GetModuleFileNameA(nullptr, executableFileBuf.data(),` |
| `GetModuleFileNameExW` | kernelbase | impl | src/corelib/io/qlockfile_win.cpp:157 | `reinterpret_cast<QFunctionPointer>(GetProcAddress(hPsapi, "GetModuleFileNameExW")));` |
| `GetModuleFileNameW` | kernel32 | forward | src/corelib/kernel/qcoreapplication_win.cpp:93 | locate the executable / plugin dirs (qApp->applicationDirPath) |
| `GetModuleHandleExA` | kernel32 | forward | src/3rdparty/angle/src/libANGLE/renderer/d3d/HLSLCompiler.cpp:130 | `if (GetModuleHandleExA(0, d3dCompilerNames[i], &mD3DCompilerModule))` |
| `GetModuleHandleExW` | kernel32 | forward | src/corelib/plugin/qlibrary_win.cpp:143 | already listed |
| `GetModuleHandleW` | kernel32 | forward | src/plugins/platforms/windows/qwindowscontext.cpp:636 | base address / module presence (GetModuleHandleExW for pinning) |
| `GetMonitorInfoW` | user32 | impl | src/plugins/platforms/windows/qwindowsscreen.cpp:84 | monitor work area / device name for QScreen |
| `GetNamedSecurityInfoW` | advapi32 | impl | src/corelib/io/qfilesystemengine_win.cpp:803 | `if (GetNamedSecurityInfo(reinterpret_cast<const wchar_t*>(entry.nativeFilePath().utf16()), SE_FILE_OBJECT,` |
| `GetNativeSystemInfo` | kernel32 | forward | src/corelib/io/qfsfileengine_win.cpp:914 | architecture under WOW64 (32-bit app on 64-bit Windows) |
| `GetNetworkParams` | iphlpapi | impl | src/network/kernel/qnetworkinterface_win.cpp:258 | `if (GetNetworkParams(pinfo, &bufSize) == ERROR_BUFFER_OVERFLOW) {` |
| `GetObjectW` | gdi32 | impl | src/plugins/platforms/windows/qwindowscursor.cpp:775 | `&& GetObject(iconInfo.hbmColor, sizeof(BITMAP), &bmColor)` |
| `GetOpenFileNameW` | comdlg32 | impl | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:1722 | native file dialog (QFileDialog when not using the Qt dialog) |
| `GetOutlineTextMetricsW` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontengine.cpp:114 | `const auto size = GetOutlineTextMetrics(hdc, 0, nullptr);` |
| `GetOverlappedResult` | kernel32 | forward | src/network/socket/qlocalserver_win.cpp:290 | complete overlapped I/O for the pipe reader |
| `GetParent` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:754 | parent HWND lookup |
| `GetPath` | gdi32 | forward | src/corelib/io/qfilesystemengine_win.cpp:377 | `if (psl->GetPath(szGotPath, MAX_PATH, &wfd, SLGP_UNCPRIORITY) == NOERROR)` |
| `GetPixelFormat` | gdi32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:1085 | `m_pixelFormat = GetPixelFormat(dc);` |
| `GetPointerDeviceRects` | user32 | forward | src/plugins/platforms/windows/qwindowscontext.cpp:205 | `getPointerDeviceRects = (GetPointerDeviceRects)library.resolve("GetPointerDeviceRects");` |
| `GetPointerFrameTouchInfo` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:207 | `getPointerFrameTouchInfo = (GetPointerFrameTouchInfo)library.resolve("GetPointerFrameTouchInfo");` |
| `GetPointerFrameTouchInfoHistory` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:208 | `getPointerFrameTouchInfoHistory = (GetPointerFrameTouchInfoHistory)library.resolve("GetPointerFrameTouchInfoHistory");` |
| `GetPointerInfo` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:204 | Win8 pointer input for touch/pen |
| `GetPointerPenInfo` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:209 | `getPointerPenInfo = (GetPointerPenInfo)library.resolve("GetPointerPenInfo");` |
| `GetPointerPenInfoHistory` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:210 | `getPointerPenInfoHistory = (GetPointerPenInfoHistory)library.resolve("GetPointerPenInfoHistory");` |
| `GetPointerTouchInfo` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:206 | touch/pen detail for QPointerEvent synthesis |
| `GetPointerType` | user32 | forward | src/plugins/platforms/windows/qwindowscontext.cpp:203 | `getPointerType = (GetPointerType)library.resolve("GetPointerType");` |
| `GetProcAddress` | kernel32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:92 | resolve optional entry points; NULL => Qt uses a fallback implementation |
| `GetProcessDpiAwareness` | shcore | impl | src/plugins/platforms/windows/qwindowscontext.cpp:236 | `getProcessDpiAwareness = (GetProcessDpiAwareness)library.resolve("GetProcessDpiAwareness");` |
| `GetProcessId` | kernel32 | forward | src/corelib/io/qprocess_win.cpp:907 | `*pid = qint64(GetProcessId(shellExecuteExInfo.hProcess));` |
| `GetPropW` | user32 | impl | src/3rdparty/angle/src/libANGLE/renderer/d3d/SurfaceD3D.cpp:271 | recover the Qt window from an HWND (ATOM-based lookup) |
| `GetQueueStatus` | user32 | forward | src/corelib/kernel/qeventdispatcher_win.cpp:266 | `if (HIWORD(GetQueueStatus(mask)) == 0)` |
| `GetSaveFileNameW` | comdlg32 | impl | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:1723 | native save dialog |
| `GetSidSubAuthority` | kernelbase | impl | src/corelib/io/qstandardpaths_win.cpp:122 | `DWORD integrity_level = *GetSidSubAuthority(token_info->Label.Sid, *GetSidSubAuthorityCount(token_info->Label.Sid) - 1);` |
| `GetSidSubAuthorityCount` | kernelbase | impl | src/corelib/io/qstandardpaths_win.cpp:122 | `DWORD integrity_level = *GetSidSubAuthority(token_info->Label.Sid, *GetSidSubAuthorityCount(token_info->Label.Sid) - 1);` |
| `GetStartupInfoW` | kernel32 | forward | src/corelib/kernel/qcoreapplication_win.cpp:178 | `GetStartupInfo(&startupInfo);` |
| `GetStdHandle` | kernel32 | forward | src/corelib/io/qprocess_win.cpp:184 | QProcess console handles |
| `GetStockObject` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontdatabase.cpp:1688 | default pens/brushes/fonts used by the GDI engine |
| `GetSysColor` | user32 | impl | src/plugins/platforms/windows/qwindowstheme.cpp:134 | system colours |
| `GetSysColorBrush` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:620 | system colours for QWindowsTheme palettes |
| `GetSystemInfo` | kernel32 | forward | src/corelib/io/qfsfileengine_win.cpp:912 | page size, processor count, architecture (QSettings/Random) |
| `GetSystemMenu` | user32 | forward | src/plugins/platforms/windows/qwindowskeymapper.cpp:791 | window system menu |
| `GetSystemMetrics` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:659 | screen metrics, virtual desktop, multi-monitor |
| `GetTempPathW` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:1393 | QDir::tempPath |
| `GetTextExtentPoint32W` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontengine.cpp:392 | `GetTextExtentPoint32(hdc, reinterpret_cast<const wchar_t *>(ch), chrLen, &size);` |
| `GetTextFaceW` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontdatabase.cpp:1991 | `GetTextFace(data->hdc, 64, n);` |
| `GetTextMetricsW` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontdatabase.cpp:1597 | font ascent/descent/avg width |
| `GetThreadPriority` | kernel32 | forward | src/corelib/thread/qthread_win.cpp:582 | QThread priority query |
| `GetTickCount64` | kernel32 | impl | src/corelib/kernel/qelapsedtimer_win.cpp:96 | monotonic QDeadlineTimer base |
| `GetTimeFormatEx` | kernel32 | forward | src/corelib/text/qlocale_win.cpp:203 | `return GetTimeFormatEx(lcName, flags, date, format, data, size);` |
| `GetTimeFormatW` | kernel32 | forward | src/corelib/text/qlocale_win.cpp:201 | QSystemLocale time formatting |
| `GetTimeZoneInformation` | kernel32 | forward | src/corelib/time/qtimezoneprivate_win.cpp:312 | QTimeZone Windows backend |
| `GetTimeZoneInformationForYear` | kernel32 | forward | src/corelib/time/qtimezoneprivate_win.cpp:248 | `*ok = GetTimeZoneInformationForYear(year, &dtzi, &tzi);` |
| `GetTokenInformation` | kernelbase | impl | src/corelib/io/qfilesystemengine_win.cpp:207 | TokenElevation/TokenSessionId |
| `GetTouchInputInfo` | user32 | impl | src/plugins/platforms/windows/qwindowsmousehandler.cpp:634 | `GetTouchInputInfo(reinterpret_cast<HTOUCHINPUT>(msg.lParam),` |
| `GetUpdateRect` | user32 | forward | src/plugins/platforms/windows/qwindowswindow.cpp:2086 | `if (!GetUpdateRect(m_data.hwnd, &updateRect, FALSE))` |
| `GetUserDefaultLCID` | kernel32 | forward | src/corelib/text/qlocale_win.cpp:174 | QLocale system locale |
| `GetUserDefaultLangID` | kernel32 | forward | src/platformsupport/fontdatabases/windows/qwindowsfontdatabase.cpp:1847 | `LANGID lid = GetUserDefaultLangID();` |
| `GetUserDefaultLocaleName` | kernel32 | forward | src/corelib/text/qlocale_win.cpp:176 | `GetUserDefaultLocaleName(lcName, LOCALE_NAME_MAX_LENGTH);` |
| `GetUserGeoID` | kernel32 | forward | src/corelib/time/qtimezoneprivate_win.cpp:468 | `const GEOID id = GetUserGeoID(GEOCLASS_NATION);` |
| `GetUserPreferredUILanguages` | kernel32 | forward | src/corelib/text/qlocale_win.cpp:649 | `if (!GetUserPreferredUILanguages(MUI_LANGUAGE_NAME, &cnt, buf.data(), &size)) {` |
| `GetUserProfileDirectoryW` | userenv | impl | src/corelib/io/qfilesystemengine_win.cpp:1360 | QStandardPaths home dir (userenv) |
| `GetVolumeInformationW` | kernel32 | forward | src/corelib/io/qfsfileengine_win.cpp:485 | QStorageInfo volume label/fs; FALSE => invalid drive |
| `GetVolumeNameForVolumeMountPointW` | kernel32 | forward | src/corelib/io/qstorageinfo_win.cpp:117 | `if (::GetVolumeNameForVolumeMountPoint(reinterpret_cast<const wchar_t *>(path.utf16()),` |
| `GetVolumePathNameW` | kernel32 | forward | src/corelib/io/qstorageinfo_win.cpp:88 | `if (::GetVolumePathName(reinterpret_cast<const wchar_t *>(path.utf16()), buffer, defaultBufferSize))` |
| `GetVolumePathNamesForVolumeNameW` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:339 | `if (GetVolumePathNamesForVolumeName(reinterpret_cast<LPCWSTR>(volumeName.utf16()), buffer, MAX_PATH, &len) != 0)` |
| `GetWindow` | user32 | impl | src/plugins/platforms/windows/qwindowswindow.cpp:1636 | `const HWND oldTransientParent = GetWindow(m_data.hwnd, GW_OWNER);` |
| `GetWindowDpiAwarenessContext` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:218 | `getWindowDpiAwarenessContext = (GetWindowDpiAwarenessContext)library.resolve("GetWindowDpiAwarenessContext");` |
| `GetWindowLongPtrW` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:819 | read GWLP_USERDATA / window style; Qt uses it to recover the QWindowsWindow |
| `GetWindowLongW` | user32 | impl | src/plugins/platforms/windows/qwindowswindow.cpp:400 | `const LONG exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);` |
| `GetWindowPlacement` | user32 | forward | src/plugins/platforms/windows/qwindowscontext.cpp:1661 | maximised/minimised state |
| `GetWindowRect` | user32 | impl | src/plugins/platforms/windows/qwindowsinputcontext.cpp:235 | query frame geometry |
| `GetWindowTextW` | user32 | impl | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:363 | `if (!GetWindowTextW(hwnd, buf, sizeof(buf)/sizeof(wchar_t)) \|\| wcscmp(buf, context->title.data()) != 0)` |
| `GetWindowThreadProcessId` | user32 | impl | src/plugins/platforms/windows/qwindowsclipboard.cpp:230 | identify the owning thread/process of an HWND |
| `GlobalAlloc` | kernel32 | forward | src/plugins/platforms/windows/qwindowsdrag.cpp:613 | `HGLOBAL hData = GlobalAlloc(0, sizeof(DWORD));` |
| `GlobalFree` | kernel32 | forward | src/network/kernel/qnetworkproxy_win.cpp:514 | `GlobalFree(ieProxyConfig.lpszAutoConfigUrl);` |
| `GlobalLock` | kernel32 | impl | src/plugins/platforms/windows/qwindowsdrag.cpp:615 | `auto *moveEffect = reinterpret_cast<DWORD *>(GlobalLock(hData));` |
| `GlobalSize` | kernel32 | impl | src/plugins/platforms/windows/qwindowsmime.cpp:343 | `data = QByteArray::fromRawData(reinterpret_cast<const char *>(val), int(GlobalSize(s.hGlobal)));` |
| `GlobalUnlock` | kernel32 | impl | src/plugins/platforms/windows/qwindowsdrag.cpp:617 | `GlobalUnlock(hData);` |
| `HideCaret` | user32 | forward | src/plugins/platforms/windows/qwindowsinputcontext.cpp:293 | `HideCaret(platformWindow->handle());` |
| `ImageLoad` | imagehlp | impl | src/gui/rhi/qrhi.cpp:2956 | `b.d.type = ImageLoad;` |
| `ImmAssociateContext` | imm32 | impl | src/plugins/platforms/windows/qwindowsinputcontext.cpp:329 | IME enable/disable |
| `ImmAssociateContextEx` | imm32 | impl | src/plugins/platforms/windows/qwindowsinputcontext.cpp:326 | `ImmAssociateContextEx(platformWindow->handle(), nullptr, IACE_DEFAULT);` |
| `ImmGetCompositionString` | imm32 | forward | src/plugins/platforms/windows/qwindowsinputcontext.cpp:418 | `const int length = ImmGetCompositionString(himc, dwIndex, buffer, bufferSize * sizeof(wchar_t));` |
| `ImmGetContext` | imm32 | impl | src/plugins/platforms/windows/qwindowsinputcontext.cpp:90 | QWindowsInputContext IME |
| `ImmGetDefaultIMEWnd` | imm32 | impl | src/plugins/platforms/windows/qwindowsinputcontext.cpp:407 | `const HWND imeWindow = ImmGetDefaultIMEWnd(m_compositionContext.hwnd);` |
| `ImmGetOpenStatus` | imm32 | impl | src/plugins/platforms/windows/qwindowsinputcontext.cpp:252 | `return ImmGetOpenStatus(himc);` |
| `ImmGetVirtualKey` | imm32 | impl | src/plugins/platforms/windows/qwindowskeymapper.cpp:1187 | `vk_key = ImmGetVirtualKey(reinterpret_cast<HWND>(window->winId()));` |
| `ImmNotifyIME` | imm32 | impl | src/plugins/platforms/windows/qwindowsinputcontext.cpp:91 | IME state transitions |
| `ImmReleaseContext` | imm32 | impl | src/plugins/platforms/windows/qwindowsinputcontext.cpp:92 | `ImmReleaseContext(hwnd, himc);` |
| `ImmSetCandidateWindow` | imm32 | impl | src/plugins/platforms/windows/qwindowsinputcontext.cpp:389 | `ImmSetCandidateWindow(himc, &candf);` |
| `ImmSetCompositionWindow` | imm32 | impl | src/plugins/platforms/windows/qwindowsinputcontext.cpp:388 | IME candidate window placement |
| `InitSecurityInterfaceW` | secur32 | impl | src/network/kernel/qauthenticator.cpp:1509 | `reinterpret_cast<QFunctionPointer>(GetProcAddress(securityDLLHandle, "InitSecurityInterfaceW")));` |
| `InitializeAcl` | kernelbase | impl | src/network/socket/qlocalserver_win.cpp:144 | `InitializeAcl(acl, aclSize, ACL_REVISION_DS);` |
| `InitializeSecurityContextW` | secur32 | impl | src/network/kernel/qauthenticator.cpp:1583 | TLS handshake step |
| `InitializeSecurityDescriptor` | kernelbase | impl | src/network/socket/qlocalserver_win.cpp:82 | `if (!InitializeSecurityDescriptor(pSD.data(), SECURITY_DESCRIPTOR_REVISION)) {` |
| `InsertMenuW` | user32 | impl | src/plugins/platforms/windows/qwindowsmenu.cpp:475 | `InsertMenu(menu->menuHandle(), idBefore, state(), m_id, qStringToWChar(text));` |
| `InterlockedDecrement` | kernel32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontdatabase.cpp:417 | `ULONG newCount = InterlockedDecrement(&m_referenceCount);` |
| `InterlockedIncrement` | kernel32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontdatabase.cpp:412 | `return InterlockedIncrement(&m_referenceCount);` |
| `InvalidateRect` | user32 | forward | src/plugins/platforms/windows/qwindowscontext.cpp:418 | `InvalidateRect(hwnd, nullptr, false);` |
| `IsChild` | user32 | impl | src/plugins/platforms/windows/qwindowswindow.cpp:1596 | `if (m_data.hwnd == activeHwnd \|\| IsChild(activeHwnd, m_data.hwnd))` |
| `IsEqualGUID` | ole32 | impl | src/corelib/io/qfilesystemwatcher_win.cpp:188 | `std::find_if(mapping, end, [&needle] (const VolumeUuidMapping &m) { return IsEqualGUID(m.uuid, needle); });` |
| `IsHungAppWindow` | user32 | impl | src/plugins/platforms/windows/qwindowsclipboard.cpp:247 | `if (IsHungAppWindow(m_nextClipboardViewer)) {` |
| `IsIconic` | user32 | impl | src/plugins/platforms/windows/qwindowswindow.cpp:1897 | `if (!IsIconic(m_data.hwnd) && !testFlag(WithinSetParent))` |
| `IsTouchWindow` | user32 | impl | src/plugins/platforms/windows/qwindowswindow.cpp:3051 | `const bool ret = IsTouchWindow(m_data.hwnd, &touchFlags);` |
| `IsValidSid` | kernelbase | impl | src/network/socket/qlocalserver_win.cpp:122 | `qDebug() << "primary group SID" << QString::fromWCharArray(groupNameSid) << "valid" << IsValidSid(pTokenGroup->PrimaryGroup);` |
| `IsWindow` | user32 | impl | src/plugins/platforms/windows/qwindowsintegration.cpp:377 | validate HWNDs before calling |
| `IsWindowEnabled` | user32 | impl | src/plugins/platforms/windows/qwindowsinputcontext.cpp:245 | `if (hwnd && ::IsWindowEnabled(hwnd) && ::IsWindowVisible(hwnd))` |
| `IsWindowVisible` | user32 | impl | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:1259 | window state |
| `IsZoomed` | user32 | impl | src/plugins/platforms/windows/qwindowskeymapper.cpp:799 | `bool maximized = IsZoomed(topLevelHwnd);` |
| `KillTimer` | user32 | forward | src/corelib/kernel/qeventdispatcher_win.cpp:160 | `KillTimer(hwnd, wp);` |
| `LCIDToLocaleName` | kernel32 | forward | src/corelib/text/qlocale_win.cpp:1179 | `LCIDToLocaleName(id, name, LOCALE_NAME_MAX_LENGTH, 0);` |
| `LCMapStringEx` | kernel32 | forward | src/corelib/text/qcollator_win.cpp:152 | `int size = LCMapStringEx(LPCWSTR(d->localeName.utf16()), LCMAP_SORTKEY \| d->collator,` |
| `LCMapStringW` | kernel32 | forward | src/corelib/text/qcollator_win.cpp:148 | case folding in QCollator/QLocale |
| `LineTo` | gdi32 | impl | src/gui/painting/qpaintengine_raster.cpp:262 | `"LineTo     ",` |
| `LoadCursorW` | user32 | impl | src/plugins/platforms/windows/qwindowscursor.cpp:769 | cursor loading for QCursor |
| `LoadIconW` | user32 | impl | src/plugins/platforms/windows/qwindowstheme.cpp:802 | `HICON iconHandle = LoadIcon(nullptr, iconName);` |
| `LoadImageW` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:657 | cursor/icon/bitmap loading |
| `LoadLibraryA` | kernel32 | forward | src/plugins/platforms/windows/qwindowsglcontext.cpp:177 | `m_lib = ::LoadLibraryA(openglDll.constData());` |
| `LoadLibraryW` | kernel32 | forward | src/plugins/platforms/windows/qwindowseglcontext.cpp:127 | load opengl32.dll/angle/dll plugins; NULL => Qt reports 'failed to load' |
| `LoadPackagedLibrary` | kernel32 | forward | src/corelib/plugin/qlibrary_win.cpp:106 | `hnd = LoadPackagedLibrary(reinterpret_cast<LPCWSTR>(path.utf16()), 0);` |
| `LocalFree` | kernel32 | forward | src/plugins/platforms/windows/qwindowscontext.cpp:711 | free CommandLineToArgvW |
| `LookupAccountSidW` | advapi32 | impl | src/corelib/io/qfilesystemengine_win.cpp:813 | `if (!LookupAccountSid(NULL, pOwner, (LPWSTR)owner.data(), &lowner,` |
| `MapGenericMask` | kernelbase | impl | src/corelib/io/qfilesystemengine_win.cpp:873 | `::MapGenericMask(&genericAccessRights, &mapping);` |
| `MapViewOfFile` | kernel32 | forward | src/corelib/kernel/qsharedmemory_win.cpp:159 | QSharedMemory attach |
| `MapViewOfFileFromApp` | kernel32 | forward | src/corelib/kernel/qsharedmemory_win.cpp:157 | `memory = (void *)MapViewOfFileFromApp(handle(), permissions, 0, 0);` |
| `MapVirtualKeyW` | user32 | impl | src/plugins/platforms/windows/qwindowskeymapper.cpp:1207 | translate VK codes to characters |
| `MessageBeep` | user32 | forward | src/plugins/platforms/windows/qwindowsintegration.cpp:634 | QApplication::beep |
| `MessageBoxW` | user32 | impl | src/gui/kernel/qguiapplication.cpp:1252 | QMessageBox native fallback / diagnostics |
| `ModifyMenuW` | user32 | impl | src/plugins/platforms/windows/qwindowsmenu.cpp:314 | `ModifyMenu(m_parentMenu->menuHandle(), oldId, MF_BYCOMMAND \| MF_POPUP,` |
| `MonitorFromPoint` | user32 | impl | src/plugins/platforms/windows/qwindowswindow.cpp:451 | `if (HMONITOR hMonitor = MonitorFromPoint(pt, MONITOR_DEFAULTTONULL)) {` |
| `MonitorFromWindow` | user32 | impl | src/plugins/platforms/windows/qwindowsscreen.cpp:597 | find the monitor for DPI/screen association |
| `MoveFileExW` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:1504 | rename/replace, MOVEFILE_REPLACE_EXISTING |
| `MoveFileW` | kernel32 | impl | src/corelib/io/qfilesystemengine_win.cpp:1501 | `bool ret = ::MoveFile((wchar_t*)source.nativeFilePath().utf16(),` |
| `MoveWindow` | user32 | forward | src/plugins/platforms/windows/qwindowswindow.cpp:2021 | resize path; FALSE => Qt keeps the old geometry |
| `MsgWaitForMultipleObjectsEx` | user32 | forward | src/corelib/kernel/qeventdispatcher_win.cpp:573 | the QEventDispatcherWin32 core wait (events + WM_* queue) |
| `MultiByteToWideChar` | kernel32 | forward | src/corelib/codecs/qwindowscodec.cpp:83 | QString<->QByteArray codec conversion |
| `NetApiBufferFree` | netapi32 | forward | src/corelib/io/qfilesystemengine_win.cpp:542 | `NetApiBufferFree(BufPtr);` |
| `NetShareEnum` | netapi32 | impl | src/corelib/io/qfilesystemengine_win.cpp:533 | `res = NetShareEnum((wchar_t*)server.utf16(), 1, (LPBYTE *)&BufPtr, DWORD(-1), &er, &tr, &resume);` |
| `OffsetRgn` | gdi32 | forward | src/plugins/platforms/windows/qwindowswindow.cpp:2527 | `OffsetRgn(winRegion, margins.left(), margins.top());` |
| `OleFlushClipboard` | ole32 | impl | src/plugins/platforms/windows/qwindowsclipboard.cpp:298 | commit deferred rendering |
| `OleGetClipboard` | ole32 | impl | src/plugins/platforms/windows/qwindowsclipboard.cpp:120 | paste via the OLE clipboard |
| `OleInitialize` | ole32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:285 | COM/OLE for drag&drop and the platform clipboard |
| `OleIsCurrentClipboard` | ole32 | impl | src/plugins/platforms/windows/qwindowsclipboard.cpp:364 | clipboard ownership check |
| `OleSetClipboard` | ole32 | impl | src/plugins/platforms/windows/qwindowsclipboard.cpp:332 | copy via the OLE clipboard |
| `OleUninitialize` | ole32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:332 | balance OleInitialize |
| `OpenFileMappingFromApp` | kernelbase | impl | src/corelib/kernel/qsharedmemory_win.cpp:105 | `hand = OpenFileMappingFromApp(FILE_MAP_ALL_ACCESS, FALSE, reinterpret_cast<PCWSTR>(nativeKey.utf16()));` |
| `OpenFileMappingW` | kernel32 | forward | src/corelib/kernel/qsharedmemory_win.cpp:107 | QSharedMemory attach to existing segment |
| `OpenProcess` | kernel32 | forward | src/plugins/platforms/windows/qwindowsclipboard.cpp:232 | query/terminate another process |
| `OpenProcessToken` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:201 | TokenElevation query (IsUserAnAdmin replacement) |
| `OutOfMemory` | setupapi | not-an-export | src/3rdparty/angle/src/libANGLE/renderer/d3d/HLSLCompiler.cpp:167 | `return gl::OutOfMemory() << "D3D compiler module not found.";` |
| `PFXImportCertStore` | crypt32 | impl | src/network/ssl/qsslsocket_schannel.cpp:1707 | `return QHCertStorePointer(PFXImportCertStore(&pfxBlob, passphrase, 0));` |
| `PeekMessageW` | user32 | impl | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:136 | drain the thread message queue |
| `PeekNamedPipe` | kernel32 | forward | src/corelib/io/qwindowspipereader.cpp:274 | non-blocking pipe read availability |
| `PlaySound` | winmm | forward | src/plugins/platforms/windows/uiautomation/qwindowsuiaaccessibility.cpp:123 | QSound (winmm) |
| `Polygon` | gdi32 | impl | src/gui/painting/qpaintengine_raster.cpp:1970 | `qWarning("Polygon too complex for filling.");` |
| `PostMessageW` | user32 | impl | src/plugins/platforms/windows/qwindowsclipboard.cpp:254 | async cross-thread notification (0 => queue full / invalid hwnd) |
| `PostThreadMessageW` | user32 | forward | src/corelib/io/qprocess_win.cpp:650 | wake the GUI thread from another thread |
| `QueryContextAttributesW` | secur32 | impl | src/network/ssl/qsslsocket_schannel.cpp:1053 | TLS stream sizes |
| `QueryPerformanceCounter` | kernel32 | forward | src/corelib/kernel/qelapsedtimer_win.cpp:89 | QElapsedTimer high-resolution clock |
| `QueryPerformanceFrequency` | kernel32 | forward | src/corelib/kernel/qelapsedtimer_win.cpp:58 | QElapsedTimer tick frequency |
| `RaiseException` | kernel32 | forward | src/corelib/thread/qthread_win.cpp:350 | structured-exception handling path used by the C++ runtime |
| `ReadFile` | kernel32 | forward | src/corelib/io/qfsfileengine_win.cpp:331 | read from pipe/file; FALSE+ERROR_BROKEN_PIPE => Qt treats as EOF (success) |
| `ReadFileEx` | kernel32 | forward | src/corelib/io/qwindowspipereader.cpp:233 | `if (!ReadFileEx(handle, ptr, bytesToRead, overlapped, &readFileCompleted)) {` |
| `RealGetWindowClass` | user32 | forward | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:361 | `if (!RealGetWindowClass(hwnd, buf, sizeof(buf)/sizeof(wchar_t)) \|\| buf[0] != L'#')` |
| `RectInRegion` | gdi32 | forward | src/gui/painting/qregion.cpp:2789 | `static bool RectInRegion(QRegionPrivate *region, int rx, int ry, uint rwidth, uint rheight)` |
| `Rectangle` | gdi32 | impl | src/gui/painting/qregion.cpp:263 | `rgn = QRegion(r, id == QRGN_SETRECT ? Rectangle : Ellipse);` |
| `RegCloseKey` | kernel32 | forward | src/corelib/kernel/qwinregistry.cpp:72 | balance registry handles |
| `RegCreateKeyExW` | kernel32 | forward | src/corelib/io/qsettings_win.cpp:165 | QSettings key creation |
| `RegDeleteKeyW` | advapi32 | impl | src/corelib/io/qsettings_win.cpp:298 | QSettings remove |
| `RegDeleteValueW` | kernel32 | forward | src/corelib/io/qsettings_win.cpp:623 | `res = RegDeleteValue(handle, reinterpret_cast<const wchar_t *>(keyName(rKey).utf16()));` |
| `RegEnumKeyExW` | kernel32 | forward | src/corelib/io/qsettings_win.cpp:240 | QSettings child groups |
| `RegEnumValueW` | kernel32 | forward | src/corelib/io/qsettings_win.cpp:238 | `res = RegEnumValue(parentHandle, i, reinterpret_cast<wchar_t *>(buff.data()), &l, 0, 0, 0, 0);` |
| `RegFlushKey` | kernel32 | forward | src/corelib/io/qsettings_win.cpp:807 | `RegFlushKey(writeHandle());` |
| `RegNotifyChangeKeyValue` | kernel32 | forward | src/network/kernel/qnetworkproxy_win.cpp:388 | `if (RegNotifyChangeKeyValue(openedKey, true, filter, handle, true) != ERROR_SUCCESS) {` |
| `RegOpenKeyExW` | kernel32 | forward | src/corelib/kernel/qwinregistry.cpp:58 | QSettings registry backend |
| `RegQueryInfoKeyW` | kernel32 | forward | src/corelib/io/qsettings_win.cpp:208 | QSettings key metadata |
| `RegQueryValueExA` | kernel32 | forward | src/3rdparty/angle/src/gpu_info_util/SystemInfo_win.cpp:62 | `if (RegQueryValueExA(key, valueName, nullptr, nullptr, reinterpret_cast<LPBYTE>(value.data()),` |
| `RegQueryValueExW` | kernel32 | forward | src/corelib/kernel/qwinregistry.cpp:85 | QSettings value read |
| `RegSetValueExW` | kernel32 | forward | src/corelib/io/qsettings_win.cpp:737 | QSettings value write |
| `RegisterClassExW` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:673 | register the Qt window class (QT_WINDOW_CLASS_NAME / Qt6Build...); 0 with ERROR_CLASS_ALREADY_EXISTS is tolerated by Qt |
| `RegisterClassW` | user32 | impl | src/plugins/platforms/windows/qwindowsopengltester.cpp:429 | `if (!RegisterClass(&wclass))` |
| `RegisterClipboardFormatW` | user32 | impl | src/plugins/platforms/windows/qwindowsdrag.cpp:623 | custom MIME formats for QWindowsMime |
| `RegisterDeviceNotificationW` | user32 | impl | src/corelib/io/qfilesystemwatcher_win.cpp:321 | `re.devNotify = RegisterDeviceNotification(winEventDispatcher->internalHwnd(),` |
| `RegisterDragDrop` | ole32 | impl | src/plugins/platforms/windows/qwindowswindow.cpp:1488 | register the Qt window as a drop target (IDropTarget) |
| `RegisterPowerSettingNotification` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:437 | `d->m_powerNotification = RegisterPowerSettingNotification(d->m_powerDummyWindow, &GUID_MONITOR_POWER_ON, DEVICE_NOTIFY_WINDOW_HANDLE);` |
| `RegisterTouchWindow` | user32 | impl | src/plugins/platforms/windows/qwindowswindow.cpp:3056 | enable WM_TOUCH; failure => Qt uses pointer/tablet path instead |
| `RegisterWaitForSingleObject` | kernel32 | impl | src/corelib/kernel/qwineventnotifier.cpp:273 | `if (RegisterWaitForSingleObject(&waitHandle, handleToEvent, wfsoCallback, this,` |
| `RegisterWindowMessageW` | user32 | impl | src/plugins/platforms/windows/qwindowsinputcontext.cpp:167 | `m_WM_MSIME_MOUSE(RegisterWindowMessage(L"MSIMEMouseOperation")),` |
| `ReleaseCapture` | user32 | forward | src/plugins/platforms/windows/qwindowswindow.cpp:2378 | balance SetCapture |
| `ReleaseDC` | user32 | forward | src/plugins/platforms/windows/qwindowscontext.cpp:336 | balance GetDC; failure leaks DCs |
| `ReleaseSemaphore` | kernel32 | forward | src/corelib/kernel/qsystemsemaphore_win.cpp:119 | QSystemSemaphore::release; FALSE => Qt reports out of range |
| `ReleaseStgMedium` | ole32 | impl | src/plugins/platforms/windows/qwindowsmime.cpp:346 | `ReleaseStgMedium(&s);` |
| `RemoveClipboardFormatListener` | user32 | forward | src/plugins/platforms/windows/qwindowscontext.cpp:196 | `removeClipboardFormatListener = (RemoveClipboardFormatListener)library.resolve("RemoveClipboardFormatListener");` |
| `RemoveDirectoryW` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:1191 | QDir::rmdir |
| `RemoveFontMemResourceEx` | gdi32 | forward | src/platformsupport/fontdatabases/windows/qwindowsfontdatabase.cpp:1317 | release AddFontMemResourceEx handles |
| `RemoveFontResourceExW` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontdatabase.cpp:1642 | uninstall application fonts |
| `RemoveMenu` | user32 | forward | src/plugins/platforms/windows/qwindowsmenu.cpp:343 | `RemoveMenu(parentMenuHandle(), m_id, MF_BYCOMMAND);` |
| `RemovePropW` | user32 | impl | src/3rdparty/angle/src/libANGLE/renderer/d3d/SurfaceD3D.cpp:342 | detach window data |
| `ResetEvent` | kernel32 | forward | src/corelib/kernel/qeventdispatcher_win.cpp:918 | re-arm auto-reset events |
| `ResumeThread` | kernel32 | forward | src/corelib/thread/qthread_win.cpp:590 | `if (ResumeThread(d->handle) == (DWORD) -1) {` |
| `RevokeDragDrop` | ole32 | impl | src/plugins/platforms/windows/qwindowswindow.cpp:1493 | unregister the drop target |
| `RoGetActivationFactory` | combase | impl | src/plugins/platforms/windows/qwin10helpers.cpp:108 | `typedef HRESULT (WINAPI *RoGetActivationFactory)(HSTRING, REFIID, void **);` |
| `SHBrowseForFolder` | shell32 | forward | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:1811 | `if (qt_LpItemIdList pItemIDList = SHBrowseForFolder(&bi)) {` |
| `SHCreateItemFromIDList` | shell32 | impl | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:926 | `hr = SHCreateItemFromIDList(idList, IID_IShellItem, reinterpret_cast<void **>(&result));` |
| `SHCreateItemFromParsingName` | shell32 | impl | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:902 | shell item creation for QFileDialog/native menus |
| `SHFileOperation` | shell32 | forward | src/corelib/io/qfilesystemengine_win.cpp:1612 | `int result = SHFileOperation(&operation);` |
| `SHGetFileInfo` | shell32 | forward | src/plugins/platforms/windows/qwindowstheme.cpp:176 | `const bool result = SHGetFileInfo(reinterpret_cast<const wchar_t *>(fileName.utf16()),` |
| `SHGetImageList` | shell32 | impl | src/plugins/platforms/windows/qwindowstheme.cpp:863 | `HRESULT hr = SHGetImageList(iImageList, iID_IImageList, reinterpret_cast<void **>(&imageList));` |
| `SHGetKnownFolderIDList` | shell32 | impl | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:921 | `HRESULT hr = SHGetKnownFolderIDList(uuid, 0, nullptr, &idList);` |
| `SHGetMalloc` | shell32 | impl | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:1817 | legacy shell allocator |
| `SHGetPathFromIDList` | shell32 | forward | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:1789 | `const bool ok = SHGetPathFromIDList(reinterpret_cast<qt_LpItemIdList>(lParam), path)` |
| `SHGetStockIconInfo` | shell32 | impl | src/plugins/platforms/windows/qwindowstheme.cpp:782 | `if (SHGetStockIconInfo(stockId, SHGFI_ICON \| stockFlags, &iconInfo) == S_OK) {` |
| `SQLAllocHandle` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:997 | ODBC driver (QSqlDatabase) driver/handle allocation |
| `SQLBindParameter` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1426 | `r = SQLBindParameter(d->hStmt,` |
| `SQLCloseCursor` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1400 | `SQLCloseCursor(d->hStmt);` |
| `SQLColAttribute` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:637 | `const SQLRETURN r = ::SQLColAttribute(hStmt, column + 1, SQL_DESC_AUTO_UNIQUE_VALUE,` |
| `SQLColumns` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:2540 | `r =  SQLColumns(hStmt,` |
| `SQLDescribeCol` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:529 | ODBC metadata |
| `SQLDisconnect` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:2022 | ODBC disconnect |
| `SQLDriverConnect` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1968 | `r = SQLDriverConnect(d->hDbc,` |
| `SQLEndTran` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:2281 | `SQLRETURN r = SQLEndTran(SQL_HANDLE_DBC,` |
| `SQLExecDirect` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1025 | `r = SQLExecDirect(d->hStmt,` |
| `SQLExecute` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1659 | `r = SQLExecute(d->hStmt);` |
| `SQLFetch` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1103 | ODBC row fetch |
| `SQLFetchScroll` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1078 | `r = SQLFetchScroll(d->hStmt,` |
| `SQLFreeHandle` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:971 | ODBC handle release |
| `SQLGetData` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:418 | `r = SQLGetData(hStmt,` |
| `SQLGetDiagRec` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:242 | `r = SQLGetDiagRec(handleType,` |
| `SQLGetFunctions` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:2120 | `r = SQLGetFunctions(hDbc, reqFunc[i], &sup);` |
| `SQLGetInfo` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:752 | `int r = SQLGetInfo(hDbc,` |
| `SQLGetStmtAttr` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1035 | `r = SQLGetStmtAttr(d->hStmt, SQL_ATTR_CURSOR_SCROLLABLE, &isScrollable, SQL_IS_INTEGER, 0);` |
| `SQLGetTypeInfo` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:2236 | `r = SQLGetTypeInfo(hStmt, SQL_TIMESTAMP);` |
| `SQLMoreResults` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1794 | `SQLRETURN r = SQLMoreResults(d->hStmt);` |
| `SQLNumResultCols` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1040 | ODBC column count |
| `SQLPrepare` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1373 | `r = SQLPrepare(d->hStmt,` |
| `SQLPrimaryKeys` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:2438 | `r = SQLPrimaryKeys(hStmt,` |
| `SQLRowCount` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1322 | ODBC affected rows |
| `SQLSetConnectAttr` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:793 | ODBC attributes |
| `SQLSetEnvAttr` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1930 | `r = SQLSetEnvAttr(d->hEnv,` |
| `SQLSetStmtAttr` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:1008 | `r = SQLSetStmtAttr(d->hStmt,` |
| `SQLSpecialColumns` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:2450 | `r = SQLSpecialColumns(hStmt,` |
| `SQLTables` | odbc32 | impl | src/plugins/sqldrivers/odbc/qsql_odbc.cpp:2356 | `r = SQLTables(hStmt,` |
| `SafeArrayCreateVector` | oleaut32 | impl | src/plugins/platforms/windows/uiautomation/qwindowsuiamainprovider.cpp:629 | `if ((*pRetVal = SafeArrayCreateVector(VT_I4, 0, 2))) {` |
| `SafeArrayPutElement` | oleaut32 | impl | src/plugins/platforms/windows/uiautomation/qwindowsuiamainprovider.cpp:631 | `SafeArrayPutElement(*pRetVal, &i, &rtId[i]);` |
| `Schannel` |  | not-an-export | src/network/ssl/qsslsocket_schannel.cpp:1279 | SSL backend |
| `SelectClipRgn` | gdi32 | impl | src/plugins/platforms/windows/qwindowswindow.cpp:2101 | `SelectClipRgn(ps.hdc, nullptr);` |
| `SelectObject` | gdi32 | impl | src/plugins/platforms/windows/qwindowsscreen.cpp:219 | `HGDIOBJ null_bitmap = SelectObject(bitmap_dc, bitmap);` |
| `SendMessageW` | user32 | impl | src/plugins/platforms/windows/qwindowsclipboard.cpp:256 | synchronous cross-thread call; Qt uses it for WM_QT_* internal messages |
| `SetBkMode` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontengine.cpp:1040 | `SetBkMode(hdc, TRANSPARENT);` |
| `SetCapture` | user32 | forward | src/plugins/platforms/windows/qwindowswindow.cpp:2608 | mouse capture during drag/resize; NULL => capture lost |
| `SetCaretPos` | user32 | forward | src/plugins/platforms/windows/qwindowsinputcontext.cpp:361 | `SetCaretPos(cursorRectangle.x(), cursorRectangle.y());` |
| `SetClipboardViewer` | user32 | forward | src/plugins/platforms/windows/qwindowsclipboard.cpp:202 | `m_nextClipboardViewer = SetClipboardViewer(m_clipboardViewer);` |
| `SetCurrentDirectoryA` | kernel32 | forward | src/3rdparty/angle/src/common/system_utils_win.cpp:71 | `return (SetCurrentDirectoryA(dirName) == TRUE);` |
| `SetCurrentDirectoryW` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:1440 | QDir::setCurrent |
| `SetCursor` | user32 | forward | src/plugins/platforms/windows/qwindowscursor.cpp:632 | QCursor::setShape / WM_SETCURSOR |
| `SetCursorPos` | user32 | forward | src/plugins/platforms/windows/qwindowscursor.cpp:685 | QCursor::setPos |
| `SetDisplayAutoRotationPreferences` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:199 | `setDisplayAutoRotationPreferences = (SetDisplayAutoRotationPreferences)library.resolve("SetDisplayAutoRotationPreferences");` |
| `SetEndOfFile` | kernel32 | forward | src/corelib/io/qfsfileengine_win.cpp:776 | truncate QFile |
| `SetEnvironmentVariableA` | kernel32 | forward | src/3rdparty/angle/src/common/system_utils_win.cpp:76 | `return (SetEnvironmentVariableA(variableName, value) == TRUE);` |
| `SetErrorMode` | kernel32 | forward | src/corelib/plugin/qlibrary_win.cpp:68 | suppress Windows error dialogs (Qt sets SEM_FAILCRITICALERRORS) |
| `SetEvent` | kernel32 | forward | src/corelib/kernel/qwineventnotifier.cpp:268 | wake the event dispatcher / signal QWaitCondition |
| `SetFilePointer` | kernel32 | forward | src/corelib/io/qprocess_win.cpp:281 | `SetFilePointer(channel.pipe[1], 0, NULL, FILE_END);` |
| `SetFilePointerEx` | kernel32 | forward | src/corelib/io/qfsfileengine_win.cpp:269 | 64-bit seek on QFile |
| `SetFileTime` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:786 | QFile::setFileTime |
| `SetFocus` | user32 | forward | src/plugins/platforms/windows/qwindowswindow.cpp:2567 | give keyboard focus; NULL => focus not set |
| `SetForegroundWindow` | user32 | forward | src/plugins/platforms/windows/qwindowssystemtrayicon.cpp:429 | activate a window; Windows may refuse (returns FALSE) — Qt falls back to AttachThreadInput |
| `SetGraphicsMode` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontengine.cpp:447 | `SetGraphicsMode(hdc, GM_ADVANCED);` |
| `SetHandleInformation` | kernel32 | forward | src/network/socket/qnativesocketengine_win.cpp:367 | make pipe handles inheritable/non-inheritable |
| `SetLastError` | kernel32 | forward | src/3rdparty/angle/src/libANGLE/renderer/d3d/SurfaceD3D.cpp:299 | `SetLastError(0);` |
| `SetLayeredWindowAttributes` | user32 | forward | src/plugins/platforms/windows/qwindowswindow.cpp:423 | `SetLayeredWindowAttributes(hwnd, 0, alpha, LWA_ALPHA);` |
| `SetLayout` | gdi32 | impl | src/plugins/platforms/windows/qwindowswindow.cpp:2040 | `SetLayout(m_hdc, 0); // Clear RTL layout` |
| `SetMenu` | user32 | forward | src/plugins/platforms/windows/qwindowsmenu.cpp:799 | attach a menu to a window |
| `SetMenuItemInfoW` | user32 | impl | src/plugins/platforms/windows/qwindowskeymapper.cpp:815 | `SetMenuItemInfo(menu, SC_CLOSE, FALSE, &closeItem);` |
| `SetParent` | user32 | forward | src/plugins/platforms/windows/qwindowswindow.cpp:1205 | reparent (native widgets/popups) |
| `SetPixelFormat` | gdi32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:215 | apply pixel format; FALSE => context creation fails |
| `SetProcessDPIAware` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:193 | Vista DPI awareness fallback; FALSE if already set is benign |
| `SetProcessDpiAwareness` | shcore | impl | src/plugins/platforms/windows/qwindowscontext.cpp:237 | Win8.1 process DPI awareness; failure => Qt falls back to SetProcessDPIAware |
| `SetPropW` | user32 | impl | src/3rdparty/angle/src/libANGLE/renderer/d3d/SurfaceD3D.cpp:307 | attach QWindowsWindow data to an HWND |
| `SetSecurityDescriptorDacl` | kernelbase | impl | src/network/socket/qlocalserver_win.cpp:169 | `if (!SetSecurityDescriptorDacl(pSD.data(), TRUE, acl, FALSE)) {` |
| `SetSecurityDescriptorGroup` | kernelbase | impl | src/network/socket/qlocalserver_win.cpp:168 | `SetSecurityDescriptorGroup(pSD.data(), pTokenGroup->PrimaryGroup, FALSE);` |
| `SetSecurityDescriptorOwner` | kernelbase | impl | src/network/socket/qlocalserver_win.cpp:167 | `SetSecurityDescriptorOwner(pSD.data(), pTokenUser->User.Sid, FALSE);` |
| `SetTextAlign` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontengine.cpp:1041 | `SetTextAlign(hdc, TA_BASELINE);` |
| `SetTextColor` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontengine.cpp:1039 | `SetTextColor(hdc, RGB(0,0,0));` |
| `SetThreadPriority` | kernel32 | forward | src/corelib/thread/qthread_win.cpp:586 | QThread priority mapping |
| `SetTimer` | user32 | impl | src/corelib/kernel/qeventdispatcher_win.cpp:288 | `d->sendPostedEventsTimerId = SetTimer(d->internalHwnd, SendPostedEventsTimerId,` |
| `SetWindowLongPtrW` | user32 | impl | src/plugins/platforms/windows/qwindowswindow.cpp:853 | install the Qt window proc and GWLP_USERDATA; 0 may mean previous value was 0 (check GetLastError) |
| `SetWindowLongW` | user32 | impl | src/plugins/platforms/windows/qwindowswindow.cpp:406 | `SetWindowLong(hwnd, GWL_EXSTYLE, exStyle \| WS_EX_LAYERED);` |
| `SetWindowPlacement` | user32 | forward | src/plugins/platforms/windows/qwindowswindow.cpp:1666 | `SetWindowPlacement(hwnd, &windowPlacement);` |
| `SetWindowPos` | user32 | forward | src/plugins/platforms/windows/qwindowscontext.cpp:1011 | move/resize/z-order; FALSE => Qt logs a warning |
| `SetWindowRgn` | user32 | forward | src/plugins/platforms/windows/qwindowswindow.cpp:2519 | `SetWindowRgn(m_data.hwnd, nullptr, true);` |
| `SetWindowTextW` | user32 | impl | src/plugins/platforms/windows/qwindowsdialoghelpers.cpp:1781 | `SetWindowText(hwnd, reinterpret_cast<const wchar_t *>(m_title.utf16()));` |
| `SetWindowsHookExW` | user32 | impl | src/corelib/kernel/qeventdispatcher_win.cpp:473 | `d->getMessageHook = SetWindowsHookEx(WH_GETMESSAGE, (HOOKPROC) qt_GetMessageHook, NULL, GetCurrentThreadId());` |
| `SetWorldTransform` | gdi32 | impl | src/platformsupport/fontdatabases/windows/qwindowsfontengine.cpp:448 | `SetWorldTransform(hdc, &xform);` |
| `SetupDiDestroyDeviceInfoList` | setupapi | impl | src/3rdparty/angle/src/gpu_info_util/SystemInfo_win.cpp:136 | `SetupDiDestroyDeviceInfoList(deviceInfo);` |
| `SetupDiEnumDeviceInfo` | setupapi | impl | src/3rdparty/angle/src/gpu_info_util/SystemInfo_win.cpp:91 | `while (SetupDiEnumDeviceInfo(deviceInfo, deviceIndex++, &deviceData))` |
| `SetupDiGetClassDevsW` | setupapi | impl | src/3rdparty/angle/src/gpu_info_util/SystemInfo_win.cpp:80 | `HDEVINFO deviceInfo = SetupDiGetClassDevsW(&displayClass, nullptr, nullptr, DIGCF_PRESENT);` |
| `SetupDiGetDeviceRegistryPropertyW` | setupapi | impl | src/3rdparty/angle/src/gpu_info_util/SystemInfo_win.cpp:110 | `if (!SetupDiGetDeviceRegistryPropertyW(deviceInfo, &deviceData, SPDRP_DRIVER, nullptr,` |
| `ShellExecuteW` | shell32 | impl | src/plugins/platforms/windows/qwindowsservices.cpp:63 | `result = ShellExecute(nullptr, nullptr, path, nullptr, nullptr, SW_SHOWNORMAL);` |
| `Shell_NotifyIcon` | shell32 | forward | src/plugins/platforms/windows/qwindowssystemtrayicon.cpp:295 | `Shell_NotifyIcon(NIM_MODIFY, &tnd);` |
| `Shell_NotifyIconGetRect` | shell32 | impl | src/plugins/platforms/windows/qwindowssystemtrayicon.cpp:244 | `const QRect result = SUCCEEDED(Shell_NotifyIconGetRect(&nid, &rect))` |
| `ShowCaret` | user32 | forward | src/plugins/platforms/windows/qwindowsinputcontext.cpp:291 | `ShowCaret(platformWindow->handle());` |
| `ShowWindow` | user32 | forward | src/plugins/platforms/windows/qwindowswindow.cpp:1223 | map QWindow::setVisible to Win32 show state |
| `SkipPointerFrameMessages` | user32 | **absent** | src/plugins/platforms/windows/qwindowscontext.cpp:211 | `skipPointerFrameMessages = (SkipPointerFrameMessages)library.resolve("SkipPointerFrameMessages");` |
| `Sleep` | kernel32 | forward | src/corelib/io/qwindowspipereader.cpp:353 | `Sleep(sleepTime);` |
| `SleepEx` | kernel32 | forward | src/corelib/io/qwindowspipereader.cpp:289 | `while (SleepEx(msecs == -1 ? INFINITE : msecs, TRUE) == WAIT_IO_COMPLETION) {` |
| `StringFromGUID2` | ole32 | forward | src/gui/kernel/qguiapplication.cpp:1541 | `StringFromGUID2(guid, guidstr, 40);` |
| `StrokePath` | gdi32 | impl | src/gui/painting/qpdf.cpp:393 | `case StrokePath:` |
| `SwapBuffers` | gdi32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:210 | present the GL frame |
| `SwitchToThread` | kernel32 | forward | src/corelib/thread/qthread_win.cpp:470 | `SwitchToThread();` |
| `SysAllocString` | oleaut32 | impl | src/plugins/platforms/windows/uiautomation/qwindowsuiautils.cpp:122 | `return SysAllocString(reinterpret_cast<const wchar_t *>(value.utf16()));` |
| `SysFreeString` | oleaut32 | impl | src/plugins/platforms/windows/uiautomation/qwindowsuiamainprovider.cpp:180 | `::SysFreeString(displayString);` |
| `SystemParametersInfoForDpi` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:220 | `systemParametersInfoForDpi = (SystemParametersInfoForDpi)library.resolve("SystemParametersInfoForDpi");` |
| `SystemParametersInfoW` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:1020 | theme/font/DPI settings, QWindowsTheme |
| `SystemTimeToFileTime` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:285 | `return ::SystemTimeToFileTime(&sTime, fileTime);` |
| `TerminateProcess` | kernel32 | forward | src/corelib/io/qprocess_win.cpp:657 | QProcess::kill |
| `TerminateThread` | kernel32 | forward | src/corelib/thread/qthread_win.cpp:608 | `TerminateThread(d->handle, 0);` |
| `TlsAlloc` | kernel32 | forward | src/corelib/thread/qthread_win.cpp:85 | `#define TlsAlloc qWinRTTlsAlloc` |
| `TlsFree` | kernel32 | forward | src/corelib/thread/qthread_win.cpp:86 | `#define TlsFree qWinRTTlsFree` |
| `TlsGetValue` | kernel32 | forward | src/corelib/thread/qthread_win.cpp:88 | `#define TlsGetValue qWinRTTlsGetValue` |
| `TlsSetValue` | kernel32 | forward | src/corelib/thread/qthread_win.cpp:87 | `#define TlsSetValue qWinRTTlsSetValue` |
| `ToAscii` | user32 | impl | src/plugins/platforms/windows/qwindowskeymapper.cpp:774 | `::ToAscii(VK_SPACE, 0, emptyBuffer, reinterpret_cast<LPWORD>(&buffer), 0);` |
| `ToUnicode` | user32 | impl | src/plugins/platforms/windows/qwindowskeymapper.cpp:612 | `int res = ToUnicode(vk, scancode, kbdBuffer, reinterpret_cast<LPWSTR>(unicodeBuffer), 5, 0);` |
| `TrackMouseEvent` | user32 | forward | src/plugins/platforms/windows/qwindowsmousehandler.cpp:447 | hover/leave tracking for QCursor::setPos + enter/leave events |
| `TrackPopupMenu` | user32 | impl | src/plugins/platforms/windows/qwindowsmenu.cpp:704 | context menus (QWindowsMenu fallback) |
| `TrackPopupMenuEx` | user32 | forward | src/plugins/platforms/windows/qwindowskeymapper.cpp:820 | `const int ret = TrackPopupMenuEx(menu,` |
| `TranslateMessage` | user32 | impl | src/corelib/kernel/qeventdispatcher_win.cpp:606 | `TranslateMessage(&msg);` |
| `TzSpecificLocalTimeToSystemTime` | kernel32 | forward | src/corelib/io/qfilesystemengine_win.cpp:268 | `if (!::TzSpecificLocalTimeToSystemTime(0, &lTime, &sTime))` |
| `UiaClientsAreListening` | uiautomationcore | impl | src/platformsupport/windowsuiautomation/qwindowsuiawrapper.cpp:57 | `m_pUiaClientsAreListening = reinterpret_cast<PtrUiaClientsAreListening>(uiaLib.resolve("UiaClientsAreListening"));` |
| `UiaHostProviderFromHwnd` | uiautomationcore | impl | src/platformsupport/windowsuiautomation/qwindowsuiawrapper.cpp:53 | `m_pUiaHostProviderFromHwnd = reinterpret_cast<PtrUiaHostProviderFromHwnd>(uiaLib.resolve("UiaHostProviderFromHwnd"));` |
| `UiaRaiseAutomationEvent` | uiautomationcore | impl | src/platformsupport/windowsuiautomation/qwindowsuiawrapper.cpp:55 | `m_pUiaRaiseAutomationEvent = reinterpret_cast<PtrUiaRaiseAutomationEvent>(uiaLib.resolve("UiaRaiseAutomationEvent"));` |
| `UiaRaiseAutomationPropertyChangedEvent` | uiautomationcore | impl | src/platformsupport/windowsuiautomation/qwindowsuiawrapper.cpp:54 | `m_pUiaRaiseAutomationPropertyChangedEvent = reinterpret_cast<PtrUiaRaiseAutomationPropertyChangedEvent>(uiaLib.resolve("UiaRaiseAutomationPropertyChangedEvent"));` |
| `UiaRaiseNotificationEvent` | uiautomationcore | impl | src/platformsupport/windowsuiautomation/qwindowsuiawrapper.cpp:56 | `m_pUiaRaiseNotificationEvent = reinterpret_cast<PtrUiaRaiseNotificationEvent>(uiaLib.resolve("UiaRaiseNotificationEvent"));` |
| `UiaReturnRawElementProvider` | uiautomationcore | impl | src/platformsupport/windowsuiautomation/qwindowsuiawrapper.cpp:52 | `m_pUiaReturnRawElementProvider = reinterpret_cast<PtrUiaReturnRawElementProvider>(uiaLib.resolve("UiaReturnRawElementProvider"));` |
| `UnhookWindowsHookEx` | user32 | forward | src/corelib/kernel/qeventdispatcher_win.cpp:1026 | `UnhookWindowsHookEx(d->getMessageHook);` |
| `UnmapViewOfFile` | kernel32 | forward | src/corelib/kernel/qsharedmemory_win.cpp:184 | QSharedMemory detach |
| `UnregisterClassW` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:690 | teardown of the Qt window class |
| `UnregisterDeviceNotification` | user32 | impl | src/corelib/io/qfilesystemwatcher_win.cpp:143 | `UnregisterDeviceNotification(e.devNotify);` |
| `UnregisterPowerSettingNotification` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:325 | `UnregisterPowerSettingNotification(d->m_powerNotification);` |
| `UnregisterTouchWindow` | user32 | impl | src/plugins/platforms/windows/qwindowswindow.cpp:1366 | `UnregisterTouchWindow(m_data.hwnd);` |
| `UnregisterWaitEx` | kernel32 | forward | src/corelib/kernel/qwineventnotifier.cpp:284 | `if (UnregisterWaitEx(waitHandle, INVALID_HANDLE_VALUE))` |
| `UpdateLayeredWindow` | user32 | impl | src/plugins/platforms/windows/qwindowswindow.cpp:421 | `UpdateLayeredWindow(hwnd, nullptr, nullptr, nullptr, nullptr, nullptr, 0, &blend, ULW_ALPHA);` |
| `UpdateLayeredWindowIndirect` | user32 | impl | src/plugins/platforms/windows/qwindowsbackingstore.cpp:106 | `const BOOL result = UpdateLayeredWindowIndirect(rw->handle(), &info);` |
| `VerQueryValueW` | kernelbase | impl | src/corelib/kernel/qcoreapplication_win.cpp:146 | `if (VerQueryValue(info.data(), __TEXT("\\"),` |
| `VirtualQuery` | kernel32 | forward | src/corelib/kernel/qsharedmemory_win.cpp:169 | `if (!VirtualQuery(memory, &info, sizeof(info))) {` |
| `WNetGetUniversalNameW` | mpr | impl | src/corelib/io/qstorageinfo_win.cpp:106 | `result = ::WNetGetUniversalName(reinterpret_cast<const wchar_t *>(path.utf16()),` |
| `WSAAccept` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:875 | `int acceptedDescriptor = WSAAccept(socketDescriptor, 0,0,0,0);` |
| `WSAAsyncSelect` | ws2_32 | impl | src/corelib/kernel/qeventdispatcher_win.cpp:455 | `WSAAsyncSelect(socket, internalHwnd, event ? int(WM_QT_SOCKETNOTIFIER) : 0, event);` |
| `WSAConnect` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:695 | `int connectResult = ::WSAConnect(socketDescriptor, &aa.a, sockAddrSize, 0,0,0,0);` |
| `WSAGetLastError` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:301 | socket error mapping; Qt translates WSAE* to QAbstractSocket::SocketError |
| `WSAHtonl` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:1378 | `WSAHtonl(socketDescriptor, header.senderAddress.toIPv4Address(), &data->ipi_addr.s_addr);` |
| `WSAIoctl` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:406 | SIO_GET_EXTENSION_FUNCTION_POINTER etc. |
| `WSANtohl` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:201 | `WSANtohl(socketDescriptor, sa4->sin_addr.s_addr, &addr);` |
| `WSANtohs` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:195 | `WSANtohs(socketDescriptor, sa6->sin6_port, port);` |
| `WSARecv` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:1158 | `recvResult = ::WSARecv(socketDescriptor, buf.data(), DWORD(buf.size()), &bytesRead, &flags, nullptr, nullptr);` |
| `WSARecvFrom` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:1094 | `if (::WSARecvFrom(socketDescriptor, &buf, 1, &bytesReceived, &flags, 0,0,0,0) == SOCKET_ERROR) {` |
| `WSASend` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:1441 | `int socketRet = ::WSASend(socketDescriptor, &buf, 1, &bytesWritten, flags, 0,0);` |
| `WSASendTo` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:1393 | `ret = ::WSASendTo(socketDescriptor, &buf, 1, &bytesSent, flags, msg.name, msg.namelen, 0,0);` |
| `WSASocketW` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:358 | create a socket with flags (WSA_FLAG_OVERLAPPED for Qt's select-based engine) |
| `WTClose` | wintab32 | impl | src/plugins/platforms/windows/qwindowstabletsupport.cpp:186 | `wTClose = (PtrWTClose)library.resolve("WTClose");` |
| `WTEnable` | wintab32 | impl | src/plugins/platforms/windows/qwindowstabletsupport.cpp:188 | `wTEnable = (PtrWTEnable)library.resolve("WTEnable");` |
| `WTGetW` | wintab32 | impl | src/plugins/platforms/windows/qwindowstabletsupport.cpp:191 | `wTGet = (PtrWTGet)library.resolve("WTGetW");` |
| `WTInfoW` | wintab32 | impl | src/plugins/platforms/windows/qwindowstabletsupport.cpp:187 | `wTInfo = (PtrWTInfo)library.resolve("WTInfoW");` |
| `WTOpenW` | wintab32 | impl | src/plugins/platforms/windows/qwindowstabletsupport.cpp:185 | `wTOpen = (PtrWTOpen)library.resolve("WTOpenW");` |
| `WTOverlap` | wintab32 | impl | src/plugins/platforms/windows/qwindowstabletsupport.cpp:189 | `wTOverlap = (PtrWTEnable)library.resolve("WTOverlap");` |
| `WTPacketsGet` | wintab32 | impl | src/plugins/platforms/windows/qwindowstabletsupport.cpp:190 | `wTPacketsGet = (PtrWTPacketsGet)library.resolve("WTPacketsGet");` |
| `WTQueueSizeGet` | wintab32 | impl | src/plugins/platforms/windows/qwindowstabletsupport.cpp:192 | `wTQueueSizeGet = (PtrWTQueueSizeGet)library.resolve("WTQueueSizeGet");` |
| `WTQueueSizeSet` | wintab32 | impl | src/plugins/platforms/windows/qwindowstabletsupport.cpp:193 | `wTQueueSizeSet = (PtrWTQueueSizeSet)library.resolve("WTQueueSizeSet");` |
| `WTSFreeMemory` | wtsapi32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:860 | free WTSQueryUserToken/WTS* buffers |
| `WTSGetActiveConsoleSessionId` | kernel32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:850 | session detection (wtsapi32/kernel32) |
| `WTSQuerySessionInformationW` | wtsapi32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:855 | `if (WTSQuerySessionInformation(WTS_CURRENT_SERVER_HANDLE, sessionId,` |
| `WaitForInputIdle` | user32 | impl | src/plugins/platforms/windows/uiautomation/qwindowsuiawindowprovider.cpp:95 | `HRESULT STDMETHODCALLTYPE QWindowsUiaWindowProvider::WaitForInputIdle(int milliseconds, __RPC__out BOOL *pRetVal) {` |
| `WaitForMultipleObjects` | kernel32 | forward | src/corelib/io/qfilesystemwatcher_win.cpp:662 | wait on the dispatcher event + message queue |
| `WaitForMultipleObjectsEx` | kernel32 | forward | src/corelib/thread/qthread_win.cpp:274 | `ret = WaitForMultipleObjectsEx(handlesCopy.count(), handlesCopy.constData(), false, INFINITE, false);` |
| `WaitForSingleObject` | kernel32 | forward | src/corelib/kernel/qsystemsemaphore_win.cpp:130 | QSystemSemaphore::acquire |
| `WaitForSingleObjectEx` | kernel32 | forward | src/corelib/kernel/qsystemsemaphore_win.cpp:127 | `if (WAIT_OBJECT_0 != WaitForSingleObjectEx(semaphore, INFINITE, FALSE)) {` |
| `WaitNamedPipeW` | kernel32 | forward | src/network/socket/qlocalsocket_win.cpp:170 | timeout on connecting to a local server |
| `WideCharToMultiByte` | kernel32 | forward | src/corelib/codecs/qwindowscodec.cpp:211 | QString<->QByteArray codec conversion |
| `WinHttpCloseHandle` | winhttp | impl | src/network/kernel/qnetworkproxy_win.cpp:503 | `ptrWinHttpCloseHandle = (PtrWinHttpCloseHandle)lib.resolve("WinHttpCloseHandle");` |
| `WinHttpGetDefaultProxyConfiguration` | winhttp | impl | src/network/kernel/qnetworkproxy_win.cpp:505 | `ptrWinHttpGetDefaultProxyConfiguration = (PtrWinHttpGetDefaultProxyConfiguration)lib.resolve("WinHttpGetDefaultProxyConfiguration");` |
| `WinHttpGetIEProxyConfigForCurrentUser` | winhttp | impl | src/network/kernel/qnetworkproxy_win.cpp:506 | `ptrWinHttpGetIEProxyConfigForCurrentUser = (PtrWinHttpGetIEProxyConfigForCurrentUser)lib.resolve("WinHttpGetIEProxyConfigForCurrentUser");` |
| `WinHttpGetProxyForUrl` | winhttp | impl | src/network/kernel/qnetworkproxy_win.cpp:504 | `ptrWinHttpGetProxyForUrl = (PtrWinHttpGetProxyForUrl)lib.resolve("WinHttpGetProxyForUrl");` |
| `WinHttpOpen` | winhttp | impl | src/network/kernel/qnetworkproxy_win.cpp:502 | `ptrWinHttpOpen = (PtrWinHttpOpen)lib.resolve("WinHttpOpen");` |
| `WindowFromDC` | user32 | forward | src/3rdparty/angle/src/libANGLE/renderer/d3d/d3d11/Renderer11.cpp:621 | `HWND hwnd           = WindowFromDC(mDisplay->getNativeDisplayId());` |
| `WindowFromPoint` | user32 | impl | src/plugins/platforms/windows/qwindowscontext.cpp:841 | `if (const HWND window = WindowFromPoint(screenPoint))` |
| `WindowsCreateStringReference` | combase | impl | src/plugins/platforms/windows/qwin10helpers.cpp:109 | `typedef HRESULT (WINAPI *WindowsCreateStringReference)(PCWSTR, UINT32, HSTRING_HEADER *, HSTRING *);` |
| `WriteFile` | kernel32 | forward | src/corelib/io/qfsfileengine_win.cpp:391 | write to pipe/file; FALSE+ERROR_NO_DATA => peer closed, Qt treats as EOF |
| `WriteFileEx` | kernel32 | forward | src/corelib/io/qwindowspipewriter.cpp:196 | `if (!WriteFileEx(handle, buffer.constData(), buffer.size(),` |
| `_beginthreadex` | msvcr100 | impl (CRT) | src/corelib/thread/qthread_win.cpp:533 | QThread/QThreadPool thread creation |
| `_endthreadex` | msvcr100 | impl (CRT) | src/corelib/thread/qthread_win.cpp:675 | thread exit path |
| `bind` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:793 | bind QAbstractSocket/QUdpSocket |
| `closesocket` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:1632 | close a socket |
| `eglGetDisplay` |  | not-an-export | src/plugins/platforms/windows/qwindowseglcontext.cpp:135 | EGL display for the ANGLE/libEGL path (uses DXGI under the hood) |
| `eglGetPlatformDisplayEXT` |  | not-an-export | src/plugins/platforms/windows/qwindowseglcontext.cpp:159 | `eglGetPlatformDisplayEXT = reinterpret_cast<EGLDisplay (EGLAPIENTRY *)(EGLenum, void *, const EGLint *)>(eglGetProcAddress("eglGetPlatformDisplayEXT"));` |
| `freeaddrinfo` | ws2_32 | impl | src/network/kernel/qhostinfo.cpp:512 | `freeaddrinfo(res);` |
| `getaddrinfo` | ws2_32 | impl | src/network/kernel/qhostinfo.cpp:462 | QHostInfo/QDnsLookup on Windows uses the OS resolver (ws2_32) |
| `getnameinfo` | ws2_32 | impl | src/network/kernel/qhostinfo.cpp:426 | `if (sa && getnameinfo(sa, saSize, hbuf, sizeof(hbuf), nullptr, 0, 0) == 0)` |
| `getpeername` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:604 | peer address/port |
| `getsockname` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:554 | local address/port |
| `getsockopt` | ws2_32 | impl | src/network/socket/qnativesocketengine.cpp:1078 | SO_ERROR/SO_TYPE |
| `glBindTexture` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:190 | `void (APIENTRY * glBindTexture)(GLenum target, GLuint texture) = RESOLVE((void (APIENTRY *)(GLenum , GLuint )), glBindTexture);` |
| `glBlendFunc` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:586 | `{ "glBlendFunc", (void *) ::glBlendFunc },` |
| `glClear` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:587 | `{ "glClear", (void *) ::glClear },` |
| `glClearColor` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:588 | `{ "glClearColor", (void *) ::glClearColor },` |
| `glClearStencil` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:589 | `{ "glClearStencil", (void *) ::glClearStencil },` |
| `glColorMask` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:590 | `{ "glColorMask", (void *) ::glColorMask },` |
| `glCopyTexImage2D` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:591 | `{ "glCopyTexImage2D", (void *) ::glCopyTexImage2D },` |
| `glCopyTexSubImage2D` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:592 | `{ "glCopyTexSubImage2D", (void *) ::glCopyTexSubImage2D },` |
| `glCreateShader` |  | not-an-export | src/plugins/platforms/windows/qwindowsopengltester.cpp:489 | `if (WGL_GetProcAddress("glCreateShader")) {` |
| `glCullFace` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:593 | `{ "glCullFace", (void *) ::glCullFace },` |
| `glDeleteTextures` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:594 | `{ "glDeleteTextures", (void *) ::glDeleteTextures },` |
| `glDepthFunc` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:595 | `{ "glDepthFunc", (void *) ::glDepthFunc },` |
| `glDepthMask` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:596 | `{ "glDepthMask", (void *) ::glDepthMask },` |
| `glDisable` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:597 | `{ "glDisable", (void *) ::glDisable },` |
| `glDrawArrays` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:598 | `{ "glDrawArrays", (void *) ::glDrawArrays },` |
| `glDrawElements` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:599 | `{ "glDrawElements", (void *) ::glDrawElements },` |
| `glEnable` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:600 | `{ "glEnable", (void *) ::glEnable },` |
| `glFinish` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:601 | `{ "glFinish", (void *) ::glFinish },` |
| `glFlush` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:602 | `{ "glFlush", (void *) ::glFlush },` |
| `glFrontFace` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:603 | `{ "glFrontFace", (void *) ::glFrontFace },` |
| `glGenTextures` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:604 | `{ "glGenTextures", (void *) ::glGenTextures },` |
| `glGetBooleanv` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:605 | `{ "glGetBooleanv", (void *) ::glGetBooleanv },` |
| `glGetError` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:606 | `{ "glGetError", (void *) ::glGetError },` |
| `glGetFloatv` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:607 | `{ "glGetFloatv", (void *) ::glGetFloatv },` |
| `glGetGraphicsResetStatusARB` |  | not-an-export | src/plugins/platforms/windows/qwindowsglcontext.cpp:1256 | `reinterpret_cast<QFunctionPointer>(QOpenGLStaticContext::opengl32.wglGetProcAddress("glGetGraphicsResetStatusARB")));` |
| `glGetIntegerv` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:608 | `{ "glGetIntegerv", (void *) ::glGetIntegerv },` |
| `glGetString` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:193 | `glGetString = RESOLVE((const GLubyte * (APIENTRY *)(GLenum )), glGetString);` |
| `glGetStringi` |  | not-an-export | src/plugins/platforms/windows/qwindowsglcontext.cpp:998 | `reinterpret_cast<QFunctionPointer>(QOpenGLStaticContext::opengl32.wglGetProcAddress("glGetStringi")));` |
| `glGetTexLevelParameterfv` | opengl32 | impl | src/3rdparty/angle/src/libGLESv2/libGLESv2.cpp:2508 | `void GL_APIENTRY glGetTexLevelParameterfv(GLenum target, GLint level, GLenum pname, GLfloat *params)` |
| `glGetTexLevelParameteriv` | opengl32 | impl | src/3rdparty/angle/src/libGLESv2/libGLESv2.cpp:2503 | `void GL_APIENTRY glGetTexLevelParameteriv(GLenum target, GLint level, GLenum pname, GLint *params)` |
| `glGetTexParameterfv` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:610 | `{ "glGetTexParameterfv", (void *) ::glGetTexParameterfv },` |
| `glGetTexParameteriv` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:611 | `{ "glGetTexParameteriv", (void *) ::glGetTexParameteriv },` |
| `glHint` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:612 | `{ "glHint", (void *) ::glHint },` |
| `glIsEnabled` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:613 | `{ "glIsEnabled", (void *) ::glIsEnabled },` |
| `glIsTexture` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:614 | `{ "glIsTexture", (void *) ::glIsTexture },` |
| `glLineWidth` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:615 | `{ "glLineWidth", (void *) ::glLineWidth },` |
| `glPixelStorei` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:616 | `{ "glPixelStorei", (void *) ::glPixelStorei },` |
| `glPointSize` | opengl32 | impl | src/3rdparty/angle/src/libANGLE/renderer/d3d/DynamicHLSL.cpp:389 | `if (builtins.glPointSize.enabled)` |
| `glPolygonOffset` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:617 | `{ "glPolygonOffset", (void *) ::glPolygonOffset },` |
| `glReadBuffer` | opengl32 | impl | src/3rdparty/angle/src/libGLESv2/libGLESv2.cpp:840 | `void GL_APIENTRY glReadBuffer(GLenum mode)` |
| `glReadPixels` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:618 | `{ "glReadPixels", (void *) ::glReadPixels },` |
| `glScissor` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:619 | `{ "glScissor", (void *) ::glScissor },` |
| `glStencilFunc` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:620 | `{ "glStencilFunc", (void *) ::glStencilFunc },` |
| `glStencilMask` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:621 | `{ "glStencilMask", (void *) ::glStencilMask },` |
| `glStencilOp` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:622 | `{ "glStencilOp", (void *) ::glStencilOp },` |
| `glTexImage2D` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:623 | `{ "glTexImage2D", (void *) ::glTexImage2D },` |
| `glTexParameterf` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:624 | `{ "glTexParameterf", (void *) ::glTexParameterf },` |
| `glTexParameterfv` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:625 | `{ "glTexParameterfv", (void *) ::glTexParameterfv },` |
| `glTexParameteri` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:626 | `{ "glTexParameteri", (void *) ::glTexParameteri },` |
| `glTexParameteriv` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:627 | `{ "glTexParameteriv", (void *) ::glTexParameteriv },` |
| `glTexSubImage2D` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:628 | `{ "glTexSubImage2D", (void *) ::glTexSubImage2D },` |
| `glViewport` | opengl32 | impl | src/plugins/platforms/windows/qwindowseglcontext.cpp:629 | `{ "glViewport", (void *) ::glViewport },` |
| `listen` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:843 | QLocalServer/TcpServer listen backlog |
| `qt_testability_init` |  | not-an-export | src/gui/kernel/qguiapplication.cpp:1666 | `TasInitialize initFunction = (TasInitialize)testLib.resolve("qt_testability_init");` |
| `setsockopt` | ws2_32 | impl | src/network/socket/qnativesocketengine_win.cpp:527 | SO_REUSEADDR, TCP_NODELAY (Qt sets nodelay by default) |
| `timeKillEvent` | winmm | impl | src/corelib/kernel/qeventdispatcher_win.cpp:418 | `timeKillEvent(t->fastTimerId);` |
| `timeSetEvent` | winmm | impl | src/corelib/kernel/qeventdispatcher_win.cpp:399 | `t->fastTimerId = timeSetEvent(interval, 1, qt_fast_timer_proc, DWORD_PTR(t),` |
| `vkAcquireNextImageKHR` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:1288 | `vkAcquireNextImageKHR = reinterpret_cast<PFN_vkAcquireNextImageKHR>(f->vkGetDeviceProcAddr(dev, "vkAcquireNextImageKHR"));` |
| `vkAllocateCommandBuffers` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:1822 | `VkResult err = df->vkAllocateCommandBuffers(dev, &cmdBufInfo, cb);` |
| `vkAllocateDescriptorSets` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:743 | `VkResult r = df->vkAllocateDescriptorSets(dev, allocInfo, result);` |
| `vkAllocateMemory` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:223 | `return globalVulkanInstance->deviceFunctions(device)->vkAllocateMemory(device, pAllocateInfo, pAllocator, pMemory);` |
| `vkBeginCommandBuffer` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:1837 | `err = df->vkBeginCommandBuffer(*cb, &cmdBufBeginInfo);` |
| `vkBindBufferMemory` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:253 | `return globalVulkanInstance->deviceFunctions(device)->vkBindBufferMemory(device, buffer, memory, memoryOffset);` |
| `vkBindImageMemory` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:258 | `return globalVulkanInstance->deviceFunctions(device)->vkBindImageMemory(device, image, memory, memoryOffset);` |
| `vkCmdBeginRenderPass` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:3629 | `df->vkCmdBeginRenderPass(cbD->cb, &cmd.args.beginRenderPass.desc,` |
| `vkCmdBindDescriptorSets` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:3643 | `df->vkCmdBindDescriptorSets(cbD->cb, cmd.args.bindDescriptorSet.bindPoint,` |
| `vkCmdBindIndexBuffer` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:3657 | `df->vkCmdBindIndexBuffer(cbD->cb, cmd.args.bindIndexBuffer.buf,` |
| `vkCmdBindPipeline` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:2291 | `df->vkCmdBindPipeline(cbD->secondaryCbs.last(), VK_PIPELINE_BIND_POINT_COMPUTE, psD->pipeline);` |
| `vkCmdBindVertexBuffers` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:3651 | `df->vkCmdBindVertexBuffers(cbD->cb, uint32_t(cmd.args.bindVertexBuffer.startBinding),` |
| `vkCmdBlitImage` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:3622 | `df->vkCmdBlitImage(cbD->cb, cmd.args.blitImage.src, cmd.args.blitImage.srcLayout,` |
| `vkCmdCopyBuffer` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:3591 | `df->vkCmdCopyBuffer(cbD->cb, cmd.args.copyBuffer.src, cmd.args.copyBuffer.dst,` |
| `vkCmdCopyBufferToImage` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:3595 | `df->vkCmdCopyBufferToImage(cbD->cb, cmd.args.copyBufferToImage.src, cmd.args.copyBufferToImage.dst,` |
| `vkCmdCopyImage` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:3601 | `df->vkCmdCopyImage(cbD->cb, cmd.args.copyImage.src, cmd.args.copyImage.srcLayout,` |
| `vkCmdCopyImageToBuffer` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:3606 | `df->vkCmdCopyImageToBuffer(cbD->cb, cmd.args.copyImageToBuffer.src, cmd.args.copyImageToBuffer.srcLayout,` |
| `vkCmdDispatch` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:2433 | `df->vkCmdDispatch(secondaryCb, uint32_t(x), uint32_t(y), uint32_t(z));` |
| `vkCmdDraw` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:3673 | `df->vkCmdDraw(cbD->cb, cmd.args.draw.vertexCount, cmd.args.draw.instanceCount,` |
| `vkCmdDrawIndexed` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:3677 | `df->vkCmdDrawIndexed(cbD->cb, cmd.args.drawIndexed.indexCount, cmd.args.drawIndexed.instanceCount,` |
| `vkCmdEndRenderPass` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:3633 | `df->vkCmdEndRenderPass(cbD->cb);` |
| `vkCmdExecuteCommands` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:3701 | `df->vkCmdExecuteCommands(cbD->cb, 1, &cmd.args.executeSecondary.cb);` |
| `vkCmdPipelineBarrier` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:1703 | `df->vkCmdPipelineBarrier(frame.cmdBuf,` |
| `vkCmdResetQueryPool` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:1653 | `df->vkCmdResetQueryPool(frame.cmdBuf, timestampQueryPool, uint32_t(timestampQueryIdx), 2);` |
| `vkCmdSetBlendConstants` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:3667 | `df->vkCmdSetBlendConstants(cbD->cb, cmd.args.setBlendConstants.c);` |
| `vkCmdSetScissor` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:3664 | `df->vkCmdSetScissor(cbD->cb, 0, 1, &cmd.args.setScissor.scissor);` |
| `vkCmdSetStencilReference` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:3670 | `df->vkCmdSetStencilReference(cbD->cb, VK_STENCIL_FRONT_AND_BACK, cmd.args.setStencilRef.ref);` |
| `vkCmdSetViewport` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:3661 | `df->vkCmdSetViewport(cbD->cb, 0, 1, &cmd.args.setViewport.viewport);` |
| `vkCmdWriteTimestamp` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:1655 | `df->vkCmdWriteTimestamp(frame.cmdBuf, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,` |
| `vkCreateBuffer` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:273 | `return globalVulkanInstance->deviceFunctions(device)->vkCreateBuffer(device, pCreateInfo, pAllocator, pBuffer);` |
| `vkCreateCommandPool` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:557 | `VkResult err = df->vkCreateCommandPool(dev, &poolInfo, nullptr, &cmdPool);` |
| `vkCreateComputePipelines` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:6459 | `err = rhiD->df->vkCreateComputePipelines(rhiD->dev, rhiD->pipelineCache, 1, &pipelineInfo, nullptr, &pipeline);` |
| `vkCreateDescriptorPool` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:736 | `return df->vkCreateDescriptorPool(dev, &descPoolInfo, nullptr, pool);` |
| `vkCreateDescriptorSetLayout` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:6104 | `VkResult err = rhiD->df->vkCreateDescriptorSetLayout(rhiD->dev, &layoutInfo, nullptr, &layout);` |
| `vkCreateDevice` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:543 | `err = f->vkCreateDevice(physDev, &devInfo, nullptr, &dev);` |
| `vkCreateFence` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:1471 | `df->vkCreateFence(dev, &fenceInfo, nullptr, &frame.imageFence);` |
| `vkCreateFramebuffer` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:6005 | `VkResult err = rhiD->df->vkCreateFramebuffer(rhiD->dev, &fbInfo, nullptr, &d.fb);` |
| `vkCreateGraphicsPipelines` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:6362 | `err = rhiD->df->vkCreateGraphicsPipelines(rhiD->dev, rhiD->pipelineCache, 1, &pipelineInfo, nullptr, &pipeline);` |
| `vkCreateImage` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:283 | `return globalVulkanInstance->deviceFunctions(device)->vkCreateImage(device, pCreateInfo, pAllocator, pImage);` |
| `vkCreateImageView` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:1031 | `err = df->vkCreateImageView(dev, &imgViewInfo, nullptr, views + i);` |
| `vkCreatePipelineCache` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:2486 | `VkResult err = df->vkCreatePipelineCache(dev, &pipelineCacheInfo, nullptr, &pipelineCache);` |
| `vkCreatePipelineLayout` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:6179 | `VkResult err = rhiD->df->vkCreatePipelineLayout(rhiD->dev, &pipelineLayoutInfo, nullptr, &layout);` |
| `vkCreateQueryPool` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:634 | `err = df->vkCreateQueryPool(dev, &timestampQueryPoolInfo, nullptr, &timestampQueryPool);` |
| `vkCreateRenderPass` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:1152 | `VkResult err = df->vkCreateRenderPass(dev, &rpInfo, nullptr, &rpD->rp);` |
| `vkCreateSampler` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:5677 | `VkResult err = rhiD->df->vkCreateSampler(rhiD->dev, &samplerInfo, nullptr, &sampler);` |
| `vkCreateSemaphore` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:1474 | `df->vkCreateSemaphore(dev, &semInfo, nullptr, &frame.imageSem);` |
| `vkCreateShaderModule` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:2470 | `VkResult err = df->vkCreateShaderModule(dev, &shaderInfo, nullptr, &shaderModule);` |
| `vkCreateSwapchainKHR` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:1284 | `if (!vkCreateSwapchainKHR) {` |
| `vkCreateWin32SurfaceKHR` | vulkan-1 | forward | src/plugins/platforms/windows/qwindowsvulkaninstance.cpp:91 | `qWarning("Failed to find vkCreateWin32SurfaceKHR");` |
| `vkDestroyBuffer` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:278 | `globalVulkanInstance->deviceFunctions(device)->vkDestroyBuffer(device, buffer, pAllocator);` |
| `vkDestroyCommandPool` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:703 | `df->vkDestroyCommandPool(dev, cmdPool, nullptr);` |
| `vkDestroyDescriptorPool` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:688 | `df->vkDestroyDescriptorPool(dev, pool.pool, nullptr);` |
| `vkDestroyDescriptorSetLayout` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:3418 | `df->vkDestroyDescriptorSetLayout(dev, e.shaderResourceBindings.layout, nullptr);` |
| `vkDestroyDevice` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:708 | `df->vkDestroyDevice(dev, nullptr);` |
| `vkDestroyFence` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:673 | `df->vkDestroyFence(dev, ofr.cmdFence, nullptr);` |
| `vkDestroyFramebuffer` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:1533 | `df->vkDestroyFramebuffer(dev, image.fb, nullptr);` |
| `vkDestroyImage` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:288 | `globalVulkanInstance->deviceFunctions(device)->vkDestroyImage(device, image, pAllocator);` |
| `vkDestroyImageView` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:1537 | `df->vkDestroyImageView(dev, image.imageView, nullptr);` |
| `vkDestroyPipeline` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:3414 | `df->vkDestroyPipeline(dev, e.pipelineState.pipeline, nullptr);` |
| `vkDestroyPipelineCache` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:683 | `df->vkDestroyPipelineCache(dev, pipelineCache, nullptr);` |
| `vkDestroyPipelineLayout` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:3415 | `df->vkDestroyPipelineLayout(dev, e.pipelineState.layout, nullptr);` |
| `vkDestroyQueryPool` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:693 | `df->vkDestroyQueryPool(dev, timestampQueryPool, nullptr);` |
| `vkDestroyRenderPass` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:3444 | `df->vkDestroyRenderPass(dev, e.renderPass.rp, nullptr);` |
| `vkDestroySampler` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:3404 | `df->vkDestroySampler(dev, e.sampler.sampler, nullptr);` |
| `vkDestroySemaphore` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:1517 | `df->vkDestroySemaphore(dev, frame.imageSem, nullptr);` |
| `vkDestroyShaderModule` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:6365 | `rhiD->df->vkDestroyShaderModule(rhiD->dev, shader, nullptr);` |
| `vkDestroySwapchainKHR` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:1286 | `vkDestroySwapchainKHR = reinterpret_cast<PFN_vkDestroySwapchainKHR>(f->vkGetDeviceProcAddr(dev, "vkDestroySwapchainKHR"));` |
| `vkDeviceWaitIdle` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:667 | `df->vkDeviceWaitIdle(dev);` |
| `vkEndCommandBuffer` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:1854 | `VkResult err = df->vkEndCommandBuffer(cb);` |
| `vkEnumerateDeviceExtensionProperties` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:482 | `f->vkEnumerateDeviceExtensionProperties(physDev, nullptr, &devExtCount, nullptr);` |
| `vkEnumerateDeviceLayerProperties` | vulkan-1 | forward | src/gui/vulkan/qvulkanwindow.cpp:729 | `VkResult err = f->vkEnumerateDeviceLayerProperties(physDev, &count, nullptr);` |
| `vkEnumeratePhysicalDevices` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:384 | `f->vkEnumeratePhysicalDevices(inst->vkInstance(), &physDevCount, nullptr);` |
| `vkFlushMappedMemoryRanges` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:243 | `return globalVulkanInstance->deviceFunctions(device)->vkFlushMappedMemoryRanges(device, memoryRangeCount, pMemoryRanges);` |
| `vkFreeCommandBuffers` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:678 | `df->vkFreeCommandBuffers(dev, cmdPool, 1, &ofr.cbWrapper.cb);` |
| `vkFreeMemory` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:228 | `globalVulkanInstance->deviceFunctions(device)->vkFreeMemory(device, memory, pAllocator);` |
| `vkGetBufferMemoryRequirements` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:263 | `globalVulkanInstance->deviceFunctions(device)->vkGetBufferMemoryRequirements(device, buffer, pMemoryRequirements);` |
| `vkGetDeviceProcAddr` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:643 | `vkCmdDebugMarkerBegin = reinterpret_cast<PFN_vkCmdDebugMarkerBeginEXT>(f->vkGetDeviceProcAddr(dev, "vkCmdDebugMarkerBeginEXT"));` |
| `vkGetDeviceQueue` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:566 | `df->vkGetDeviceQueue(dev, uint32_t(gfxQueueFamilyIdx), 0, &gfxQueue);` |
| `vkGetImageMemoryRequirements` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:268 | `globalVulkanInstance->deviceFunctions(device)->vkGetImageMemoryRequirements(device, image, pMemoryRequirements);` |
| `vkGetImageSubresourceLayout` | vulkan-1 | forward | src/gui/vulkan/qvulkanwindow.cpp:2201 | `devFuncs->vkGetImageSubresourceLayout(dev, frameGrabImage, &subres, &layout);` |
| `vkGetPhysicalDeviceFeatures` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:581 | `f->vkGetPhysicalDeviceFeatures(physDev, &physDevFeatures);` |
| `vkGetPhysicalDeviceFormatProperties` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:1056 | `f->vkGetPhysicalDeviceFormatProperties(physDev, optimalDsFormat, &fmtProp);` |
| `vkGetPhysicalDeviceMemoryProperties` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:218 | `globalVulkanInstance->functions()->vkGetPhysicalDeviceMemoryProperties(physicalDevice, pMemoryProperties);` |
| `vkGetPhysicalDeviceProperties` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:213 | `globalVulkanInstance->functions()->vkGetPhysicalDeviceProperties(physicalDevice, pProperties);` |
| `vkGetPhysicalDeviceQueueFamilyProperties` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:377 | `f->vkGetPhysicalDeviceQueueFamilyProperties(physDev, &queueCount, nullptr);` |
| `vkGetPhysicalDeviceSurfaceCapabilitiesKHR` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:1297 | `vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physDev, swapChainD->surface, &surfaceCaps);` |
| `vkGetPhysicalDeviceSurfaceFormatsKHR` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:6629 | `rhiD->vkGetPhysicalDeviceSurfaceFormatsKHR = reinterpret_cast<PFN_vkGetPhysicalDeviceSurfaceFormatsKHR>(` |
| `vkGetPhysicalDeviceSurfacePresentModesKHR` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:6631 | `rhiD->vkGetPhysicalDeviceSurfacePresentModesKHR = reinterpret_cast<PFN_vkGetPhysicalDeviceSurfacePresentModesKHR>(` |
| `vkGetPhysicalDeviceWin32PresentationSupportKHR` | vulkan-1 | forward | src/plugins/platforms/windows/qwindowsvulkaninstance.cpp:62 | `qWarning("Failed to find vkGetPhysicalDeviceWin32PresentationSupportKHR");` |
| `vkGetQueryPoolResults` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:1613 | `VkResult err = df->vkGetQueryPoolResults(dev, timestampQueryPool, uint32_t(frame.timestampQueryIndex), 2,` |
| `vkGetSwapchainImagesKHR` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:1287 | `vkGetSwapchainImagesKHR = reinterpret_cast<PFN_vkGetSwapchainImagesKHR>(f->vkGetDeviceProcAddr(dev, "vkGetSwapchainImagesKHR"));` |
| `vkInvalidateMappedMemoryRanges` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:248 | `return globalVulkanInstance->deviceFunctions(device)->vkInvalidateMappedMemoryRanges(device, memoryRangeCount, pMemoryRanges);` |
| `vkMapMemory` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:233 | `return globalVulkanInstance->deviceFunctions(device)->vkMapMemory(device, memory, offset, size, flags, ppData);` |
| `vkQueuePresentKHR` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:1289 | `vkQueuePresentKHR = reinterpret_cast<PFN_vkQueuePresentKHR>(f->vkGetDeviceProcAddr(dev, "vkQueuePresentKHR"));` |
| `vkQueueSubmit` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:1881 | `err = df->vkQueueSubmit(gfxQueue, 1, &submitInfo, cmdFence);` |
| `vkQueueWaitIdle` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:1996 | `df->vkQueueWaitIdle(gfxQueue);` |
| `vkResetDescriptorPool` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:752 | `df->vkResetDescriptorPool(dev, descriptorPools[i].pool, 0);` |
| `vkResetFences` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:1573 | `df->vkResetFences(dev, 1, &frame.imageFence);` |
| `vkUnmapMemory` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:238 | `globalVulkanInstance->deviceFunctions(device)->vkUnmapMemory(device, memory);` |
| `vkUpdateDescriptorSets` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:2617 | `df->vkUpdateDescriptorSets(dev, uint32_t(writeInfos.count()), writeInfos.constData(), 0, nullptr);` |
| `vkWaitForFences` | vulkan-1 | forward | src/gui/rhi/qrhivulkan.cpp:1504 | `df->vkWaitForFences(dev, 1, &frame.cmdFence, VK_TRUE, UINT64_MAX);` |
| `wglChoosePixelFormatARB` |  | not-an-export | src/plugins/platforms/windows/qwindowsglcontext.cpp:978 | `reinterpret_cast<QFunctionPointer>(QOpenGLStaticContext::opengl32.wglGetProcAddress("wglChoosePixelFormatARB")))),` |
| `wglCreateContext` | opengl32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:190 | WGL context creation for the desktop-GL path |
| `wglCreateContextAttribsARB` |  | not-an-export | src/plugins/platforms/windows/qwindowsglcontext.cpp:980 | `reinterpret_cast<QFunctionPointer>(QOpenGLStaticContext::opengl32.wglGetProcAddress("wglCreateContextAttribsARB")))),` |
| `wglDeleteContext` | opengl32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:191 | `wglDeleteContext = reinterpret_cast<BOOL (WINAPI *)(HGLRC)>(resolve("wglDeleteContext"));` |
| `wglDescribePixelFormat` | opengl32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:199 | `wglDescribePixelFormat = reinterpret_cast<int (WINAPI *)(HDC, int, UINT, PIXELFORMATDESCRIPTOR *)>(resolve("wglDescribePixelFormat"));` |
| `wglGetCurrentContext` | opengl32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:192 | `wglGetCurrentContext = reinterpret_cast<HGLRC (WINAPI *)()>(resolve("wglGetCurrentContext"));` |
| `wglGetCurrentDC` | opengl32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:193 | `wglGetCurrentDC = reinterpret_cast<HDC (WINAPI *)()>(resolve("wglGetCurrentDC"));` |
| `wglGetExtensionsStringARB` |  | not-an-export | src/plugins/platforms/windows/qwindowsglcontext.cpp:986 | `reinterpret_cast<QFunctionPointer>(QOpenGLStaticContext::opengl32.wglGetProcAddress("wglGetExtensionsStringARB"))))` |
| `wglGetPixelFormatAttribivARB` |  | not-an-export | src/plugins/platforms/windows/qwindowsglcontext.cpp:976 | `reinterpret_cast<QFunctionPointer>(QOpenGLStaticContext::opengl32.wglGetProcAddress("wglGetPixelFormatAttribivARB")))),` |
| `wglGetProcAddress` | opengl32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:194 | resolve GL entry points |
| `wglGetSwapIntervalEXT` |  | not-an-export | src/plugins/platforms/windows/qwindowsglcontext.cpp:984 | `reinterpret_cast<QFunctionPointer>(QOpenGLStaticContext::opengl32.wglGetProcAddress("wglGetSwapIntervalEXT")))),` |
| `wglMakeCurrent` | opengl32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:195 | bind GL context; FALSE => Qt disables the GL path |
| `wglSetPixelFormat` | opengl32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:198 | `wglSetPixelFormat = reinterpret_cast<BOOL (WINAPI *)(HDC, int, const PIXELFORMATDESCRIPTOR *)>(resolve("wglSetPixelFormat"));` |
| `wglShareLists` | opengl32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:196 | `wglShareLists = reinterpret_cast<BOOL (WINAPI *)(HGLRC, HGLRC)>(resolve("wglShareLists"));` |
| `wglSwapBuffers` | opengl32 | impl | src/plugins/platforms/windows/qwindowsglcontext.cpp:197 | `wglSwapBuffers = reinterpret_cast<BOOL (WINAPI *)(HDC)>(resolve("wglSwapBuffers"));` |
| `wglSwapIntervalEXT` |  | not-an-export | src/plugins/platforms/windows/qwindowsglcontext.cpp:982 | `reinterpret_cast<QFunctionPointer>(QOpenGLStaticContext::opengl32.wglGetProcAddress("wglSwapIntervalEXT")))),` |
<!--E:QT_FULL-->

---

## 3. Cross-check against Wine 11.18

### 3.1 `.spec`-level: exported, forwarded, `@ stub`, or absent

Every API referenced by Qt was looked up in the relevant Wine `.spec`
(user32, win32u, gdi32, kernel32, kernelbase, advapi32, shell32, ole32,
oleaut32, comdlg32, comctl32, shlwapi, uxtheme, dwmapi, winmm, ws2_32, mswsock,
crypt32, wintrust, secur32, bcrypt, ncrypt, winhttp, wininet, urlmon, dnsapi,
iphlpapi, netapi32, wtsapi32, psapi, userenv, version, setupapi, cfgmgr32,
rpcrt4, winspool, avrt, hid, powrprof, propsys, shcore, uiautomationcore, usp10,
oleacc, d3d*, dxgi, d2d1, dwrite, opengl32, vulkan-1, odbc32, imm32, wintab32,
dcomp, mf*, …; see `API_DLLS` in the tool).

Result: **<!--B:STATS_WINE_SPEC-->no Qt-referenced API sits behind a Wine `@ stub`; the single flagged symbol is `SkipPointerFrameMessages`, which has no named export at all (commented-out `@ stub`).<!--E:STATS_WINE_SPEC-->**

The only Qt-referenced API with **no named Wine export at all**:

| API | Qt site | Wine evidence |
|---|---|---|
| `SkipPointerFrameMessages` | `qwindowscontext.cpp:211` (dynamic) | `dlls/user32/user32.spec:1142: # @ stub SkipPointerFrameMessages` — the line is **commented out**, so Wine exports nothing |

Wine's own line records it as an intentional `@ stub`; Windows' `user32` exports
it (a pointer/touch helper). Qt resolves it dynamically and only calls it when
non-NULL, so this is a degradation, not a hard failure. **Candidate Wine patch:**
add a named export to `user32.spec` and forward it (Windows' semantics: discard
queued pointer frame messages for the HWND/pointer id).

Everything else Qt calls is either implemented in Wine or forwarded
(`@ stdcall Foo(...) win32u.Foo` etc.). Notably:

* `iphlpapi`: `GetAdaptersAddresses`, `GetNetworkParams`, all
  `ConvertInterface*` — implemented (used by `qnetworkinterface_win.cpp` and
  `qnetconmonitor_win.cpp`);
* `secur32`/Schannel: all of `AcquireCredentialsHandleW`, `InitializeSecurityContextW`,
  `QueryContextAttributesW`, `EncryptMessage`, `DecryptMessage`, … — implemented;
* `crypt32`/`bcrypt`: certificate store and AES paths — implemented except the
  body-level stub in §3.2;
* `ws2_32`: the native socket engine's calls (`WSASocketW`, `WSAIoctl`,
  `WSAAsyncSelect`, `WSARecv/WSASend`, `bind/listen/getsockopt/…`) — implemented;
* `wintab32`: Qt's whole tablet path resolves from Wine's builtin `wintab32.dll`.

`QLocalServer`/`QLocalSocket` and `QProcess` use `\\.\pipe\…` through
`kernel32` (`CreateNamedPipeW`, `ConnectNamedPipe`, `PeekNamedPipe`, …) — all
implemented. Qt's `QFileSystemWatcher` uses `FindFirstChangeNotificationW` +
`WaitForMultipleObjects` (**not** `ReadDirectoryChangesW`, which appears nowhere
in qtbase 5.15.1).

### 3.2 Body-level stubs — the interesting class

A `@ stdcall` line only means "exported". `patches/local/0102-*` exists because
`iphlpapi!NotifyIpInterfaceChange` was **declared as stdcall but implemented as a
no-op** (it registered nothing and never invoked the callback), so the `.spec`
was green while the behaviour was missing. `tools/wine_impl_audit.py` finds that
class of gap: for each API the app reaches, it locates the `WINAPI` definition in
the relevant Wine DLL and flags bodies whose only statements are
`FIXME/TRACE/WARN` plus a constant `return`.

Body-level stubs across the<!--B:WINE_BODY--> **Qt and Chromium** surfaces — **23 Wine functions are body-only stubs, 19 of them real gaps (the rest are unconditional-success no-ops)**:

| API | Wine implementation | Body (evidence) | Call site | Surface |
|---|---|---|---|---|
| `AllowSetForegroundWindow` | `dlls/user32/win.c:779` | `return TRUE;` | base/process/launch_win.cc:351 | Chromium (no-op, acceptable) |
| `CertFindChainInStore` | `dlls/crypt32/chain.c:3002` | `FIXME("(%p, %08lx, %08lx, %ld, %p, %p): stub\n", store, certEncodingType, findFlags, findType, findPara, prevC` | src/network/ssl/qsslsocket_schannel.cpp:661 | Qt |
| `ChangeWindowMessageFilterEx` | `dlls/user32/message.c:1215` | `FIXME( "%p %x %ld %p\n", hwnd, message, action, changefilter ); return TRUE;` | src/plugins/platforms/windows/qwindowssystemtrayicon.cpp:326 | Qt |
| `CreateAppContainerProfile` | `dlls/userenv/userenv_main.c:690` | `FIXME("(%s, %s, %s, %p, %ld, %p): stub\n", debugstr_w(container_name), debugstr_w(display_name), debugstr_w(de` | sandbox/win/src/app_container_profile_base.cc:21 | Chromium |
| `D3DPERF_GetStatus` | `dlls/d3d9/d3d9_main.c:244` | `FIXME("(void) : stub\n"); return 0;` | src/3rdparty/angle/src/libANGLE/renderer/d3d/d3d9/DebugAnnotator9.cpp:33 | Qt |
| `D3DPERF_SetMarker` | `dlls/d3d9/d3d9_main.c:271` | `FIXME("color 0x%08lx, name %s stub!\n", color, debugstr_w(name));` | src/3rdparty/angle/src/libANGLE/renderer/d3d/d3d9/DebugAnnotator9.cpp:28 | Qt |
| `DCompositionCreateDevice` | `dlls/dcomp/device.c:28` | `FIXME("%p, %s, %p.\n", dxgi_device, debugstr_guid(iid), device); return E_NOTIMPL;` | src/3rdparty/angle/src/libANGLE/renderer/d3d/d3d11/win32/NativeWindow11Win32.cpp:80 *(dynamic)* | Qt |
| `DwmEnableBlurBehindWindow` | `dlls/dwmapi/dwmapi_main.c:163` | `FIXME("%p %p\n", hWnd, pBlurBuf); return E_NOTIMPL;` | src/plugins/platforms/windows/qwindowswindow.cpp:376 | Qt |
| `GdiDllInitialize` | `dlls/gdi32/objects.c:1092` | `FIXME( "stub\n" ); return TRUE;` | sandbox/win/src/process_mitigations_win32k_dispatcher.cc:146 | Chromium (no-op, acceptable) |
| `GetColorSpace` | `dlls/gdi32/objects.c:730` | `FIXME( "stub\n" ); return 0;` | ui/gl/gl_surface_egl.cc:1224 | Chromium |
| `ImmReleaseContext` | `dlls/imm32/imm.c:2350` | `TRACE( "hwnd %p, himc %p\n", hwnd, himc ); return TRUE;` | src/plugins/platforms/windows/qwindowsinputcontext.cpp:92 | Qt (no-op, acceptable) |
| `IsTouchWindow` | `dlls/user32/input.c:667` | `FIXME( "hwnd %p, flags %p stub!\n", hwnd, flags ); return FALSE;` | src/plugins/platforms/windows/qwindowswindow.cpp:3051 | Qt |
| `NetShareEnum` | `dlls/netapi32/netapi32.c:388` | `FIXME("Stub (%s %ld %p %ld %p %p %p)\n", debugstr_w(servername), level, bufptr, prefmaxlen, entriesread, total` | src/corelib/io/qfilesystemengine_win.cpp:533 | Qt |
| `ProcessTrace` | `dlls/sechost/trace.c:134` | `FIXME("%p %lu %p %p: stub\n", handles, count, start_time, end_time); return ERROR_CALL_NOT_IMPLEMENTED;` | base/win/event_trace_consumer.h:126 | Chromium |
| `RegisterTouchWindow` | `dlls/user32/input.c:676` | `FIXME( "hwnd %p, flags %#lx stub!\n", hwnd, flags ); return TRUE;` | src/plugins/platforms/windows/qwindowswindow.cpp:3056 | Qt |
| `SetDisplayAutoRotationPreferences` | `dlls/user32/sysparams.c:1009` | `FIXME("(%d): stub\n", orientation); return TRUE;` | src/plugins/platforms/windows/qwindowscontext.cpp:199 | Qt |
| `Shell_NotifyIconGetRect` | `dlls/shell32/systray.c:299` | `FIXME("stub (%p) (%p)\n", identifier, icon_location); return E_NOTIMPL;` | src/plugins/platforms/windows/qwindowssystemtrayicon.cpp:244 | Qt |
| `UiaClientsAreListening` | `dlls/uiautomationcore/uia_main.c:265` | `TRACE("()\n"); return TRUE;` | src/platformsupport/windowsuiautomation/qwindowsuiawrapper.cpp:57 *(dynamic)* | Qt (no-op, acceptable) |
| `UiaRaiseAutomationPropertyChangedEvent` | `dlls/uiautomationcore/uia_main.c:304` | `FIXME("(%p, %d, %s, %s): stub\n", provider, id, debugstr_variant(&old), debugstr_variant(&new)); return S_OK;` | src/platformsupport/windowsuiautomation/qwindowsuiawrapper.cpp:54 *(dynamic)* | Qt |
| `UiaRaiseNotificationEvent` | `dlls/uiautomationcore/uia_main.c:343` | `FIXME("(%p, %d, %d, %s, %s): stub\n", provider, notification_kind, notification_processing, debugstr_w(display` | src/platformsupport/windowsuiautomation/qwindowsuiawrapper.cpp:56 *(dynamic)* | Qt |
| `UnregisterPowerSettingNotification` | `dlls/user32/misc.c:419` | `FIXME("(%p): stub\n", handle); return TRUE;` | src/plugins/platforms/windows/qwindowscontext.cpp:325 | Qt |
| `UnregisterTouchWindow` | `dlls/user32/input.c:685` | `FIXME( "hwnd %p stub!\n", hwnd ); return TRUE;` | src/plugins/platforms/windows/qwindowswindow.cpp:1366 | Qt |
| `UserHandleGrantAccess` | `dlls/user32/misc.c:401` | `FIXME("(%p,%p,%d): stub\n", handle, job, grant); return TRUE;` | sandbox/win/src/job.cc:91 | Chromium |
<!--E:WINE_BODY-->

Four of these are unconditional-success bodies rather than gaps and can be
ignored: `AllowSetForegroundWindow` (`return TRUE`), `GdiDllInitialize`
(`return TRUE`), `ImmReleaseContext` and `UiaClientsAreListening`
(TRACE + `return TRUE`).

Impact notes (what the trace will look like, and whether it matters):

* `CreateAppContainerProfile` (userenv) returns `E_NOTIMPL`, and its four
  companions (`DeriveAppContainerSidFromAppContainerName`,
  `DeleteAppContainerProfile`, `GetAppContainerFolderPath`,
  `GetAppContainerRegistryLocation`) have **no Wine export at all**. Chromium
  resolves all five with `GetProcAddress(GetModuleHandle(L"userenv"), …)` and
  returns `nullptr`/`false` when they fail (`sandbox/win/src/app_container_profile_base.cc:87-129`),
  so the AppContainer sandbox silently degrades to the restricted-token path.
  This is the biggest single Wine gap on the Chromium side.
* `UserHandleGrantAccess` (user32) returns TRUE without granting anything —
  Chromium's job-object sandbox expects it to make a user handle usable inside
  the job; a trace will look successful while the grant never happened.
* `ProcessTrace` (sechost) returns `ERROR_CALL_NOT_IMPLEMENTED` — ETW trace
  consumption is unavailable (Chromium's trace-event ETW path).
* `GetColorSpace` (gdi32) returns `0` — colour-management queries fail.
* `Shell_NotifyIconGetRect` returns `E_NOTIMPL`; Qt uses it for
  `QPlatformSystemTrayIcon::geometry()`, so tray-icon menu placement falls back.
  Visible.
* `RegisterTouchWindow` / `IsTouchWindow` / `UnregisterTouchWindow` return
  TRUE/FALSE without wiring WM_TOUCH. Qt only takes the touch path when the
  Windows-8 pointer API is unavailable; the pointer API *is* implemented, so
  impact is low.
* `ChangeWindowMessageFilterEx` returns TRUE and filters nothing — affects
  UIPI interaction with lower-integrity processes (e.g. WebEngine helpers);
  relevant if a message never arrives from a child process.
* `SetDisplayAutoRotationPreferences` returns TRUE and does nothing
  (tablet rotation); `UnregisterPowerSettingNotification` no-ops.
* `UiaClientsAreListening` / `UiaRaiseAutomationEvent` /
  `UiaRaiseAutomationPropertyChangedEvent` / `UiaRaiseNotificationEvent` —
  accessibility events are swallowed. Screen readers will not see the app
  (`UiaHostProviderFromHwnd` and `UiaReturnRawElementProvider` *are* implemented,
  so the bridge registers but never announces).
* `CertFindChainInStore` returns `NULL`; Qt's Schannel backend calls it in
  `qsslsocket_schannel.cpp:661` while building certificate chains — TLS with
  client certificates can fail to assemble a chain.
* `DCompositionCreateDevice` returns `E_NOTIMPL` (called from ANGLE's
  `NativeWindow11Win32.cpp:80` for a swap chain); ANGLE falls back.
* `DwmEnableBlurBehindWindow` returns `E_NOTIMPL` — translucent/blurred frameless
  windows are not blurred (Qt tolerates it).
* `NetShareEnum` returns `ERROR_NOT_SUPPORTED` — `QFileSystemEngine` network-share
  enumeration fails; local paths unaffected.
* `D3DPERF_GetStatus` / `D3DPERF_SetMarker` — D3D9 debug markers; cosmetic.

### 3.3 Already patched in this tree

`patches/local/0102-iphlpapi-notify-interface-changes.patch` (4 hunks,
`dlls/iphlpapi/iphlpapi_main.c`) rewrites `NotifyIpInterfaceChange` and
`NotifyUnicastIpAddressChange` to register with a `mib_notification_register`
dispatcher. The tree at `wine-11.18/` **has it applied** —
`iphlpapi_main.c:4356` calls `mib_notification_register(MIB_NOTIFICATION_INTERFACE, …)`.
That is why the body audit does not flag it here.

Worth knowing for the trace loop:

* qtbase 5.15.1 itself does **not** call `NotifyIpInterfaceChange` /
  `NotifyUnicastIpAddressChange` anywhere; it uses `GetAdaptersAddresses`
  polling and the COM Network List Manager (`qnetconmonitor_win.cpp`, via
  `CoCreateInstance(CLSID_NetworkListManager)` — Wine implements that in
  `dlls/netprofm/`).
* Chromium 80's network-change monitor uses the *legacy* `NotifyAddrChange`
  (`net/base/network_change_notifier_win.cc:293`), which Wine implements via
  `NsiRequestChangeNotification` → `\Device\Nsi`.
* So the 0102 patch matters for code that registers *interface-change callbacks*
  (newer Qt/Chromium, or the app's own code). If a trace shows
  `NotifyIpInterfaceChange` being registered and the app still polling/never
  updating, that is the patch's area.
* Note `NotifyRouteChange2` immediately below in the same file is still a FIXME
  stub in this tree (returns `NO_ERROR`, sets no handle) — the same bug class,
  not used by Qt or Chromium 80.

---

## 4. Chromium 80.0.3987.163

### 4.1 Fetch recipe (no clone)

The tree is multi-GB; fetch single files at the tag. Verified working:

```bash
TAG=80.0.3987.163
# one file (response body is base64 of the file contents)
curl -s "https://chromium.googlesource.com/chromium/src/+/$TAG/base/win/BUILD.gn?format=TEXT" \
  | base64 -d

# directory listing (HTML; entries appear as >name.cc</a>)
curl -s "https://chromium.googlesource.com/chromium/src/+/$TAG/sandbox/win/src" \
  | grep -oE '>[A-Za-z0-9_.-]+\.(cc|h)</a>'
```

Notes learned the hard way:

* **Do not append a trailing slash** to the directory URL — that path answers
  `429 Too Many Requests`. The bare path returns 200.
* googlesource throttles aggressively under parallel load; back off
  exponentially and keep concurrency ≤ 5.
* `?format=TEXT` is the only reliable whole-file form; the `?format=JSON`
  listing is *not* base64 (it is plain JSON behind an anti-XSSI prefix).

`tools/chromium_win32_index.py` automates this: it caches every fetched file
under `/run/media/asdf/Windows/chromium-src/<repo path>` (so a re-run is free),
scans the Windows-relevant files and applies the same Wine cross-check as §3.

### 4.2 Win32 surfaces Chromium 80 relies on

<!--B:CHROMIUM_TABLE-->
**Job objects / process launch**

| Win32 API | Wine DLL | Wine status | Chromium 80.0.3987.163 |
|---|---|---|---|
| `CreateJobObjectW` | kernel32 | impl | sandbox/win/src/job.cc:26 |
| `AssignProcessToJobObject` | kernel32 | impl | base/process/launch_win.cc:342 |
| `SetInformationJobObject` | kernel32 | impl | base/process/launch_win.cc:395 |
| `CreateProcessW` | kernel32 | forward | base/process/launch_win.cc:84 |
| `CreateProcessAsUserW` | kernel32 | forward | base/process/launch_win.cc:300 |
| `OpenProcess` | kernel32 | forward | base/debug/gdi_debug_util_win.cc:403 |
| `TerminateProcess` | kernel32 | forward | base/process/process_win.cc:96 |
| `GetExitCodeProcess` | kernel32 | impl | base/process/kill_win.cc:25 |
| `WaitForSingleObject` | kernel32 | forward | base/process/kill_win.cc:44 |
| `WaitForMultipleObjects` | kernel32 | forward | base/synchronization/waitable_event_win.cc:141 |
| `SetPriorityClass` | kernel32 | forward | base/process/launch_win.cc:425 |

**Sandbox: tokens, desktops, AppContainer**

| Win32 API | Wine DLL | Wine status | Chromium 80.0.3987.163 |
|---|---|---|---|
| `CreateRestrictedToken` | kernelbase | impl | sandbox/win/src/restricted_token.cc:108 |
| `SetTokenInformation` | kernelbase | impl | sandbox/win/src/acl.cc:81 |
| `GetTokenInformation` | kernelbase | impl | base/process/process_info_win.cc:32 |
| `OpenProcessToken` | kernel32 | forward | base/process/process_info_win.cc:21 |
| `DuplicateTokenEx` | kernelbase | impl | sandbox/win/src/restricted_token.cc:117 |
| `CreateWindowStationW` | user32 | impl | sandbox/win/src/window.cc:52 |
| `SetProcessWindowStation` | user32 | forward | sandbox/win/src/window.cc:96 |
| `GetProcessWindowStation` | user32 | forward | sandbox/win/src/window.cc:42 |
| `CreateDesktopW` | user32 | impl | sandbox/win/src/window.cc:103 |
| `CloseDesktop` | user32 | forward | sandbox/win/src/sandbox_policy_base.cc:261 |
| `CreateAppContainerProfile` | userenv | impl | sandbox/win/src/app_container_profile_base.cc:21 |
| `DeriveAppContainerSidFromAppContainerName` | userenv | absent | sandbox/win/src/app_container_profile_base.cc:23 |
| `DeleteAppContainerProfile` | userenv | absent | sandbox/win/src/app_container_profile_base.cc:26 |
| `GetAppContainerFolderPath` | userenv | absent | sandbox/win/src/app_container_profile_base.cc:28 |
| `GetAppContainerRegistryLocation` | userenv | absent | sandbox/win/src/app_container_profile_base.cc:31 |
| `UserHandleGrantAccess` | user32 | impl | sandbox/win/src/job.cc:91 |
| `SetProcessMitigationPolicy` | kernel32 | forward | sandbox/win/src/process_mitigations.cc:29 |
| `GetProcessMitigationPolicy` | kernel32 | forward | base/win/win_util.cc:606 |

**NT internals**

| Win32 API | Wine DLL | Wine status | Chromium 80.0.3987.163 |
|---|---|---|---|
| `NtQueryInformationProcess` | ntdll | impl | base/debug/gdi_debug_util_win.cc:108 |
| `NtQueryObject` | ntdll | impl | sandbox/win/src/handle_closer.cc:161 |
| `NtSetInformationThread` | ntdll | impl | sandbox/win/src/policy_broker.cc:101 |
| `NtQuerySystemInformation` | ntdll | impl | base/process/process_metrics_win.cc:272 |
| `NtOpenProcessTokenEx` | ntdll | impl | sandbox/win/src/policy_broker.cc:107 |
| `NtClose` | ntdll | impl | sandbox/win/src/registry_policy.cc:33 |
| `NtCreateFile` | ntdll | impl | sandbox/win/src/filesystem_dispatcher.cc:28 |

**D3D / DXGI / DWrite / dbghelp**

| Win32 API | Wine DLL | Wine status | Chromium 80.0.3987.163 |
|---|---|---|---|
| `CreateDXGIFactory` | dxgi | impl | gpu/config/gpu_info_collector_win.cc:86 |
| `DWriteCreateFactory` | dwrite | impl | ui/gfx/win/direct_write.cc:40 |
| `SymInitialize` | dbghelp | impl | base/debug/stack_trace_win.cc:134 |
| `StackWalk64` | dbghelp | impl | base/debug/stack_trace_win.cc:330 |
| `SymGetModuleBase64` | dbghelp | impl | base/debug/stack_trace_win.cc:332 |
| `SymFunctionTableAccess64` | dbghelp | impl | base/debug/stack_trace_win.cc:332 |

**WinHTTP / WinINet**

| Win32 API | Wine DLL | Wine status | Chromium 80.0.3987.163 |
|---|---|---|---|
| `WinHttpOpen` | winhttp | impl | net/proxy_resolution/proxy_resolver_winhttp.cc:193 |
| `WinHttpCloseHandle` | winhttp | impl | net/proxy_resolution/proxy_resolver_winhttp.cc:210 |
| `WinHttpGetProxyForUrl` | winhttp | impl | net/proxy_resolution/proxy_resolver_winhttp.cc:134 |

**IPC / handles / threads**

| Win32 API | Wine DLL | Wine status | Chromium 80.0.3987.163 |
|---|---|---|---|
| `CreateEventW` | kernel32 | forward | base/synchronization/waitable_event_win.cc:26 |
| `CreateMutexW` | kernel32 | forward | base/win/scoped_handle_test_dll.cc:31 |
| `CreateIoCompletionPort` | kernel32 | forward | sandbox/win/src/broker_services.cc:162 |
| `GetQueuedCompletionStatus` | kernel32 | forward | sandbox/win/src/broker_services.cc:236 |
| `RegisterWaitForSingleObject` | kernel32 | impl | base/win/object_watcher.cc:99 |
| `DuplicateHandle` | kernel32 | forward | base/files/file_win.cc:286 |
| `CreateNamedPipeW` | kernel32 | forward | sandbox/win/src/named_pipe_dispatcher.cc:30 |
| `CreateFileMappingW` | kernel32 | forward | base/files/memory_mapped_file_win.cc:35 |
| `MapViewOfFile` | kernel32 | forward | base/files/memory_mapped_file_win.cc:42 |
| `CreateThread` | kernel32 | forward | base/threading/platform_thread_win.cc:153 |
| `SetThreadPriority` | kernel32 | forward | base/threading/platform_thread_win.cc:356 |
| `GetCurrentThreadId` | kernel32 | forward | base/threading/platform_thread_win.cc:219 |
| `GetThreadInformation` | kernel32 | absent | base/threading/platform_thread_win.cc:197 |

**Files / paths / registry**

| Win32 API | Wine DLL | Wine status | Chromium 80.0.3987.163 |
|---|---|---|---|
| `CreateFileW` | kernel32 | forward | base/files/file_util_win.cc:449 |
| `ReadFile` | kernel32 | forward | base/files/file_util_win.cc:812 |
| `WriteFile` | kernel32 | forward | base/files/file_util_win.cc:828 |
| `GetFileAttributesExW` | kernel32 | forward | base/files/file_util_win.cc:767 |
| `GetModuleFileNameW` | kernel32 | forward | base/debug/stack_trace_win.cc:116 |
| `GetTempPathW` | kernel32 | forward | base/files/file_util_win.cc:469 |
| `RegOpenKeyExW` | kernel32 | forward | base/win/registry.cc:166 |
| `RegQueryValueExW` | kernel32 | forward | base/win/registry.cc:224 |
| `RegSetValueExW` | kernel32 | forward | base/win/registry.cc:415 |
| `RegCloseKey` | kernel32 | forward | base/win/registry.cc:202 |

#### Full generated Chromium table

| Win32 API | Wine DLL | Status | Chromium 80.0.3987.163 | What Chromium does |
|---|---|---|---|---|
| `AccessCheck` | kernelbase | impl | sandbox/win/src/app_container_profile.h:47 | `virtual bool AccessCheck(const wchar_t* object_name,` |
| `AcquireSRWLockExclusive` | kernel32 | forward | base/synchronization/lock_impl_win.cc:36 | `::AcquireSRWLockExclusive(reinterpret_cast<PSRWLOCK>(&native_handle_));` |
| `AllocConsole` | kernel32 | forward | base/process/launch_win.cc:167 | console allocation for tools |
| `AllowSetForegroundWindow` | user32 | impl | base/process/launch_win.cc:351 | `!AllowSetForegroundWindow(GetProcId(process_info.process_handle()))) {` |
| `AssignProcessToJobObject` | kernel32 | impl | base/process/launch_win.cc:342 | `!AssignProcessToJobObject(options.job_handle,` |
| `AttachConsole` | kernel32 | forward | base/process/launch_win.cc:154 | console paths for QProcess/QWinEventNotifier |
| `BeginPaint` | user32 | forward | ui/gl/gl_surface_wgl.cc:51 | `if (BeginPaint(window, &paint))` |
| `CM_Get_Device_IDW` | setupapi | forward | base/win/win_util.cc:336 | `CONFIGRET status = CM_Get_Device_ID(device_info_data.DevInst, device_id,` |
| `CancelIPChangeNotify` | iphlpapi | impl | net/base/network_change_notifier_win.cc:54 | `CancelIPChangeNotify(&addr_overlapped_);` |
| `CancelIo` | kernel32 | forward | device/gamepad/hid_writer_win.cc:61 | `if (::CancelIo(hid_handle_.Get())) {` |
| `ChoosePixelFormat` | gdi32 | impl | ui/gl/gl_surface_wgl.cc:123 | select a pixel format for a window DC |
| `CloseDesktop` | user32 | forward | sandbox/win/src/sandbox_policy_base.cc:261 | balance desktop handles |
| `CloseHandle` | kernel32 | forward | base/debug/gdi_debug_util_win.cc:429 | balance every handle; failure puts Qt into a debug assertion |
| `CloseTrace` | advapi32 | forward | base/win/event_trace_consumer.h:138 | `ULONG ret = ::CloseTrace(trace_handles_[i]);` |
| `CloseWindowStation` | user32 | forward | sandbox/win/src/sandbox_policy_base.cc:266 | `::CloseWindowStation(alternate_winstation_handle_);` |
| `CoCreateInstance` | ole32 | forward | base/win/com_init_check_hook.cc:170 | create OLE/shell objects (drag&drop, file dialogs, taskbar) |
| `CoInitializeEx` | ole32 | forward | base/win/scoped_com_initializer.cc:34 | COM apartment init (Qt uses STA in the GUI thread) |
| `CoSetProxyBlanket` | ole32 | forward | base/win/wmi.cc:46 | not used by Qt core; listed for completeness |
| `CoTaskMemFree` | ole32 | forward | base/win/scoped_co_mem.h:51 | free shell-allocated strings |
| `CoUninitialize` | ole32 | forward | base/win/scoped_com_initializer.cc:23 | balance CoInitializeEx |
| `ControlTraceW` | advapi32 | forward | base/win/event_trace_controller.cc:112 | `ULONG error = ::ControlTrace(session_, NULL, properties->get(),` |
| `ConvertSidToStringSidW` | advapi32 | forward | base/win/win_util.cc:382 | `if (!::ConvertSidToStringSid(user->User.Sid, &sid_string))` |
| `ConvertStringSecurityDescriptorToSecurityDescriptorW` | advapi32 | forward | sandbox/win/src/restricted_token_utils.cc:207 | `if (::ConvertStringSecurityDescriptorToSecurityDescriptorW(` |
| `ConvertStringSidToSidW` | advapi32 | forward | sandbox/win/src/restricted_token_utils.cc:256 | `if (!::ConvertStringSidToSid(integrity_level_str, &integrity_sid))` |
| `CopyFileW` | kernel32 | forward | base/files/file_util_win.cc:195 | `if (!::CopyFile(from_path.value().c_str(), dest, fail_if_exists)) {` |
| `CopySid` | kernelbase | impl | sandbox/win/src/sid.cc:56 | `::CopySid(SECURITY_MAX_SID_SIZE, sid_, sid);` |
| `CreateAppContainerProfile` | userenv | impl | sandbox/win/src/app_container_profile_base.cc:21 | `typedef decltype(::CreateAppContainerProfile) CreateAppContainerProfileFunc;` |
| `CreateDIBSection` | gdi32 | impl | base/debug/gdi_debug_util_win.cc:354 | top-down DIB for QImage on Windows (shared pixel memory) |
| `CreateDXGIFactory` | dxgi | impl | gpu/config/gpu_info_collector_win.cc:86 | legacy DXGI factory path |
| `CreateDesktopW` | user32 | impl | sandbox/win/src/window.cc:103 | desktop creation for sandboxed/service sessions |
| `CreateDirectoryW` | kernel32 | forward | base/files/file_util_win.cc:280 | already listed |
| `CreateEnvironmentBlock` | userenv | impl | base/process/launch_win.cc:291 | QProcess environment for a user token |
| `CreateEventW` | kernel32 | forward | base/synchronization/waitable_event_win.cc:26 | manual/auto-reset events for QEventDispatcherWin32's wakeup pipe and QThread |
| `CreateFileMappingW` | kernel32 | forward | base/files/memory_mapped_file_win.cc:35 | QSharedMemory |
| `CreateFileW` | kernel32 | forward | base/files/file_util_win.cc:449 | open files, pipes (\\.\pipe\...), devices (\\.\DISPLAY1) and console handles; INVALID_HANDLE_VALUE => Qt error |
| `CreateIoCompletionPort` | kernel32 | forward | sandbox/win/src/broker_services.cc:162 | `job_port_.Set(::CreateIoCompletionPort(INVALID_HANDLE_VALUE, nullptr, 0, 0));` |
| `CreateJobObjectW` | kernel32 | impl | sandbox/win/src/job.cc:26 | `job_handle_.Set(::CreateJobObject(nullptr,  // No security attribute` |
| `CreateMutexW` | kernel32 | forward | base/win/scoped_handle_test_dll.cc:31 | QSystemSemaphore/QSingleApplication; ERROR_ALREADY_EXISTS signals an existing instance |
| `CreateNamedPipeW` | kernel32 | forward | sandbox/win/src/named_pipe_dispatcher.cc:30 | QProcess/QLocalServer named pipes |
| `CreatePipe` | kernel32 | forward | base/process/launch_win.cc:52 | QProcess stdin/stdout/stderr channels; NULL => QProcess fails |
| `CreateProcessA` | kernel32 | forward | sandbox/win/src/process_thread_dispatcher.cc:161 | `INTERCEPT_EAT(manager, L"kernel32.dll", CreateProcessA,` |
| `CreateProcessAsUserW` | kernel32 | forward | base/process/launch_win.cc:300 | start a process in another session (used by session helpers) |
| `CreateProcessW` | kernel32 | forward | base/process/launch_win.cc:84 | QProcess start; FALSE => QProcess::FailedToStart with GetLastError |
| `CreateRemoteThread` | kernel32 | forward | sandbox/win/src/process_thread_policy.cc:256 | `::CreateRemoteThread(client_info.process, nullptr, stack_size,` |
| `CreateRestrictedToken` | kernelbase | impl | sandbox/win/src/restricted_token.cc:108 | `result = ::CreateRestrictedToken(` |
| `CreateServiceW` | advapi32 | forward | base/win/windows_types.h:243 | `#define CreateService CreateServiceW` |
| `CreateThread` | kernel32 | forward | base/threading/platform_thread_win.cc:153 | QThread::start on the Win32 path (Qt uses _beginthreadex by preference) |
| `CreateToolhelp32Snapshot` | kernel32 | impl | base/debug/gdi_debug_util_win.cc:315 | QProcess/child process enumeration (Task Manager style) |
| `CreateWellKnownSid` | kernelbase | impl | sandbox/win/src/sid.cc:65 | `bool result = ::CreateWellKnownSid(type, nullptr, sid_, &size_sid);` |
| `CreateWindowExW` | user32 | impl | ui/gfx/win/window_impl.cc:205 | create the native HWND; NULL => Qt aborts platform window creation (check class registration, DPI awareness, window station) |
| `CreateWindowStationW` | user32 | impl | sandbox/win/src/window.cc:52 | window station handling (Qt creates/opens for service sessions) |
| `D3D12CreateDevice` | d3d12 | impl | gpu/config/gpu_info_collector_win.cc:175 | `PFN_D3D12_CREATE_DEVICE D3D12CreateDevice =` |
| `DWriteCreateFactory` | dwrite | impl | ui/gfx/win/direct_write.cc:40 | DirectWrite factory for the DirectWrite font engine (Qt uses it when DWrite is available) |
| `DebugBreak` | kernel32 | impl | sandbox/win/src/policy_engine_opcodes.cc:375 | `::DebugBreak();` |
| `DefRawInputProc` | user32 | impl | device/gamepad/raw_input_data_fetcher_win.cc:346 | `return ::DefRawInputProc(&input, 1, sizeof(RAWINPUTHEADER));` |
| `DefWindowProcW` | user32 | forward | base/win/message_window.cc:162 | default handling of unhandled window messages; Qt relies on it for non-Qt classes |
| `DeleteAppContainerProfile` | userenv | **absent** | sandbox/win/src/app_container_profile_base.cc:26 | `typedef decltype(::DeleteAppContainerProfile) DeleteAppContainerProfileFunc;` |
| `DeleteCriticalSection` | kernel32 | forward | sandbox/win/src/sandbox_policy_base.cc:130 | QMutex teardown |
| `DeleteDC` | gdi32 | impl | base/win/scoped_hdc.h:58 | `return ::DeleteDC(handle) != FALSE;` |
| `DeleteFileW` | kernel32 | forward | base/files/file_util_win.cc:155 | QFile::remove |
| `DeleteObject` | gdi32 | impl | base/debug/gdi_debug_util_win.cc:357 | `DeleteObject(small_bitmap);` |
| `DeleteProcThreadAttributeList` | kernel32 | forward | base/win/startup_information.cc:18 | `::DeleteProcThreadAttributeList(startup_info_.lpAttributeList);` |
| `DeriveAppContainerSidFromAppContainerName` | userenv | **absent** | sandbox/win/src/app_container_profile_base.cc:23 | `typedef decltype(::DeriveAppContainerSidFromAppContainerName)` |
| `DestroyEnvironmentBlock` | userenv | impl | base/process/launch_win.cc:304 | free CreateEnvironmentBlock |
| `DestroyIcon` | user32 | impl | base/win/scoped_gdi_object.h:27 | free loaded icons |
| `DestroyWindow` | user32 | forward | base/win/message_window.cc:80 | must succeed; failure is logged and leaked HWNDs accumulate |
| `DispatchMessageW` | user32 | impl | base/win/windows_types.h:245 | deliver messages to the Qt window proc |
| `DrawTextW` | user32 | impl | base/win/windows_types.h:246 | `#define DrawText DrawTextW` |
| `DuplicateHandle` | kernel32 | forward | base/files/file_win.cc:286 | pass handles to child processes (QProcess pipe inheritance) |
| `DuplicateToken` | kernelbase | impl | sandbox/win/src/restricted_token.cc:181 | `if (!::DuplicateToken(restricted_token.Get(), SecurityImpersonation,` |
| `DuplicateTokenEx` | kernelbase | impl | sandbox/win/src/restricted_token.cc:117 | `result = ::DuplicateTokenEx(effective_token_.Get(), TOKEN_ALL_ACCESS,` |
| `DwmGetCompositionTimingInfo` | dwmapi | impl | ui/gl/vsync_provider_win.cc:51 | `HRESULT result = DwmGetCompositionTimingInfo(NULL, &timing_info);` |
| `EnableTrace` | advapi32 | impl | base/win/event_trace_controller.cc:98 | `ULONG error = ::EnableTrace(TRUE, flags, level, &provider, session_);` |
| `EnableWindow` | user32 | forward | ui/gl/child_window_win.cc:52 | `EnableWindow(window->hwnd(), FALSE);` |
| `EndPaint` | user32 | forward | ui/gl/gl_surface_wgl.cc:52 | `EndPaint(window, &paint);` |
| `EnterCriticalSection` | kernel32 | forward | sandbox/win/src/win_utils.h:32 | QMutex lock |
| `EnumAdapters` |  | not-an-export | gpu/config/gpu_info_collector_win.cc:96 | adapter enumeration for qwindowsopengltester GPU detection |
| `EnumDisplayDevicesA` | user32 | impl | sandbox/win/src/process_mitigations_win32k_dispatcher.cc:178 | `if (!INTERCEPT_EAT(manager, L"user32.dll", EnumDisplayDevicesA,` |
| `EnumDisplayDevicesW` | user32 | impl | ui/gfx/win/physical_size.cc:135 | `while (EnumDisplayDevices(nullptr, display_index++, &display_device,` |
| `EnumDisplayMonitors` | user32 | forward | sandbox/win/src/process_mitigations_win32k_dispatcher.cc:75 | enumerate QScreens |
| `EnumDisplaySettingsW` | user32 | impl | ui/gl/vsync_provider_win.cc:107 | probe display modes / refresh rate |
| `EnumProcessModules` | kernelbase | impl | base/debug/close_handle_hook_win.cc:239 | `if (!EnumProcessModules(GetCurrentProcess(), modules.get(),` |
| `EnumSystemLocalesEx` | kernel32 | forward | sandbox/win/src/target_services.cc:74 | `return ::EnumSystemLocalesEx(EnumLocalesProcEx, LOCALE_WINDOWS, 0, 0);` |
| `EqualSid` | kernelbase | impl | sandbox/win/src/app_container_profile_base.cc:239 | `if (::EqualSid(&ace->SidStart, any_package_sid.GetPSID())) {` |
| `ExitProcess` | kernel32 | impl | content/gpu/gpu_child_thread.cc:262 | `gpu_child_thread->viz_main_.ExitProcess(/*immediately=*/true);` |
| `ExpandEnvironmentStringsW` | kernel32 | forward | base/win/registry.cc:337 | path expansion |
| `FileTimeToSystemTime` | kernel32 | forward | base/time/time_win.cc:356 | `success = FileTimeToSystemTime(&utc_ft, &utc_st) &&` |
| `FindClose` | kernel32 | forward | base/files/file_enumerator_win.cc:101 | close enumeration handle |
| `FindCloseChangeNotification` | kernel32 | forward | base/files/file_path_watcher_win.cc:215 | `FindCloseChangeNotification(*handle);` |
| `FindFirstChangeNotificationW` | kernel32 | forward | base/files/file_path_watcher_win.cc:205 | `*handle = FindFirstChangeNotification(` |
| `FindFirstFileExW` | kernel32 | forward | base/files/file_enumerator_win.cc:126 | directory enumeration for QDirIterator/QFileSystemWatcher |
| `FindFirstFileW` | kernel32 | forward | base/win/windows_types.h:247 | `#define FindFirstFile FindFirstFileW` |
| `FindNextFileW` | kernel32 | forward | base/files/file_enumerator_win.cc:133 | continue FindFirstFileExW enumeration |
| `FindResourceW` | kernel32 | forward | base/win/resource_util.cc:24 | `HRSRC hres_info = FindResource(module, MAKEINTRESOURCE(resource_id),` |
| `FindWindowExW` | user32 | impl | base/win/message_window.cc:96 | `return FindWindowEx(HWND_MESSAGE, NULL, kMessageWindowClassName,` |
| `FindWindowW` | user32 | impl | base/win/message_window.cc:95 | `HWND MessageWindow::FindWindow(const string16& window_name) {` |
| `FlushFileBuffers` | kernel32 | forward | base/files/file_win.cc:442 | QFile::flush |
| `FreeEnvironmentStringsW` | kernel32 | forward | base/process/launch_win.cc:326 | free QProcess environment block |
| `FreeLibrary` | kernel32 | forward | base/win/com_init_check_hook.cc:220 | unload a plugin DLL |
| `FreeSid` | kernelbase | impl | sandbox/win/src/app_container_profile_base.cc:34 | `inline void operator()(void* ptr) const { ::FreeSid(ptr); }` |
| `GdiDllInitialize` | gdi32 | impl | sandbox/win/src/process_mitigations_win32k_dispatcher.cc:146 | `if (!INTERCEPT_EAT(manager, L"gdi32.dll", GdiDllInitialize,` |
| `GetAce` | kernelbase | impl | sandbox/win/src/app_container_profile_base.cc:227 | `if (!GetAce(dacl, index, &temp_ace))` |
| `GetActiveWindow` | user32 | impl | base/process/launch_win.cc:371 | active window for the thread |
| `GetAdaptersAddresses` | iphlpapi | impl | net/base/network_interfaces_win.cc:226 | QNetworkInterface enumeration (iphlpapi); ERROR_BUFFER_OVERFLOW means realloc and retry |
| `GetAncestor` | user32 | forward | ui/gfx/win/hwnd_util.cc:120 | `HWND top_window = ::GetAncestor(window, GA_ROOT);` |
| `GetAppContainerFolderPath` | userenv | **absent** | sandbox/win/src/app_container_profile_base.cc:28 | `typedef decltype(::GetAppContainerFolderPath) GetAppContainerFolderPathFunc;` |
| `GetAppContainerRegistryLocation` | userenv | **absent** | sandbox/win/src/app_container_profile_base.cc:31 | `::GetAppContainerRegistryLocation) GetAppContainerRegistryLocationFunc;` |
| `GetAutoRotationState` | user32 | impl | base/win/win_util.cc:292 | `typedef BOOL (WINAPI* GetAutoRotationState)(PAR_STATE state);` |
| `GetClassInfoExW` | user32 | impl | ui/gfx/win/window_impl.cc:228 | probe the Qt window class / foreign class |
| `GetClassNameW` | user32 | impl | ui/gfx/win/hwnd_util.cc:67 | `base::string16 GetClassName(HWND window) {` |
| `GetClientRect` | user32 | impl | ui/gl/child_window_win.cc:139 | client area size for backing store sizing |
| `GetColorSpace` | gdi32 | impl | ui/gl/gl_surface_egl.cc:1224 | `switch (format_.GetColorSpace()) {` |
| `GetComputerNameW` | kernel32 | impl | base/win/windows_types.h:249 | QSysInfo::machineHostName |
| `GetCurrentDirectoryW` | kernel32 | forward | base/files/file_util_win.cc:879 | QDir::currentPath |
| `GetCurrentProcess` | kernel32 | forward | base/debug/close_handle_hook_win.cc:239 | pseudo-handle used by many kernel32 calls |
| `GetCurrentProcessId` | kernel32 | forward | base/debug/close_handle_hook_win.cc:52 | logging/diagnostics |
| `GetCurrentProcessToken` |  | not-an-export | base/process/process_info_win.cc:19 | pseudo-handle for privilege queries |
| `GetCurrentProcessorNumber` | kernel32 | forward | sandbox/win/src/handle_closer_agent.cc:71 | `const DWORD original_proc_num = GetCurrentProcessorNumber();` |
| `GetCurrentThread` | kernel32 | forward | base/debug/stack_trace_win.cc:330 | pseudo-handle for thread affinity calls |
| `GetCurrentThreadId` | kernel32 | forward | base/threading/platform_thread_win.cc:219 | QMutex/QThread identity |
| `GetDC` | user32 | forward | base/win/scoped_hdc.h:24 | screen DC used to query OPENGL caps |
| `GetDesktopWindow` | user32 | impl | ui/gfx/win/hwnd_util.cc:206 | parent for popups |
| `GetEnvironmentStrings` | kernel32 | forward | base/process/launch_win.cc:319 | `wchar_t* old_environment = GetEnvironmentStrings();` |
| `GetExitCodeProcess` | kernel32 | impl | base/process/kill_win.cc:25 | QProcess exit status |
| `GetFileAttributesExW` | kernel32 | forward | base/files/file_util_win.cc:767 | QFileInfo attributes; FALSE => does not exist |
| `GetFileAttributesW` | kernel32 | forward | base/files/file_enumerator_win.cc:170 | attributes/type (directory, reparse point, symlink) |
| `GetFileInformationByHandle` | kernel32 | forward | base/files/file_win.cc:217 | QFileInfo identity (volume serial + file index) for QFileSystemEngine |
| `GetFileSizeEx` | kernel32 | forward | base/files/file_win.cc:161 | QFile::size |
| `GetFileType` | kernel32 | forward | sandbox/win/src/sandbox_policy_base.cc:67 | distinguish disk/pipe/char/file (Qt uses it for QFile) |
| `GetFinalPathNameByHandleW` | kernel32 | forward | base/files/file_util_win.cc:680 | `DWORD used_wchars = ::GetFinalPathNameByHandle(` |
| `GetForegroundWindow` | user32 | forward | ui/gfx/win/hwnd_util.cc:124 | foreground window of the desktop |
| `GetGuiResources` | user32 | impl | base/debug/gdi_debug_util_win.cc:368 | `DWORD num_gdi_handles = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);` |
| `GetKernelObjectSecurity` | kernelbase | impl | sandbox/win/src/restricted_token_utils.cc:35 | `::GetKernelObjectSecurity(handle, security_info, nullptr, 0, &length_needed);` |
| `GetLastError` | kernel32 | forward | base/debug/gdi_debug_util_win.cc:370 | every failing Win32 call is decoded through this by Qt's qt_winerror/qSystemError |
| `GetLengthSid` | kernelbase | impl | sandbox/win/src/restricted_token_utils.cc:263 | `DWORD size = sizeof(TOKEN_MANDATORY_LABEL) + ::GetLengthSid(integrity_sid);` |
| `GetLogicalDriveStringsW` | kernel32 | forward | base/files/file_util_win.cc:702 | `if (!::GetLogicalDriveStrings(kDriveMappingSize - 1, drive_mapping)) {` |
| `GetLongPathNameW` | kernel32 | forward | base/files/file_util_win.cc:561 | QFileInfo canonical path |
| `GetMessageW` | user32 | impl | base/win/windows_types.h:215 | modal loop message pump |
| `GetModuleFileNameW` | kernel32 | forward | base/debug/stack_trace_win.cc:116 | locate the executable / plugin dirs (qApp->applicationDirPath) |
| `GetModuleHandleA` | kernel32 | forward | base/debug/close_handle_hook_win.cc:227 | `EATPatch(GetModuleHandleA("kernel32.dll"), "CloseHandle",` |
| `GetModuleHandleExA` | kernel32 | forward | base/win/wrapped_window_proc.cc:20 | `if (!::GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS \\|` |
| `GetModuleHandleExW` | kernel32 | forward | sandbox/win/src/service_resolver_32.cc:258 | already listed |
| `GetModuleHandleW` | kernel32 | forward | base/debug/gdi_debug_util_win.cc:179 | base address / module presence (GetModuleHandleExW for pinning) |
| `GetMonitorInfoA` | user32 | impl | sandbox/win/src/process_mitigations_win32k_dispatcher.cc:186 | `if (!INTERCEPT_EAT(manager, L"user32.dll", GetMonitorInfoA,` |
| `GetMonitorInfoW` | user32 | impl | sandbox/win/src/process_mitigations_win32k_dispatcher.cc:79 | monitor work area / device name for QScreen |
| `GetNamedSecurityInfoW` | advapi32 | impl | sandbox/win/src/app_container_profile_base.cc:211 | `if (GetNamedSecurityInfo(` |
| `GetNativeSystemInfo` | kernel32 | forward | base/win/windows_version.cc:60 | architecture under WOW64 (32-bit app on 64-bit Windows) |
| `GetObjectType` | gdi32 | impl | base/win/scoped_select_object.h:29 | `DCHECK((GetObjectType(oldobj_) != OBJ_REGION && object != NULL) \\|\\|` |
| `GetObjectW` | gdi32 | impl | base/win/wmi.cc:68 | `wmi_services->GetObject(b_class_name, 0, nullptr, &class_object, nullptr);` |
| `GetOverlappedResult` | kernel32 | forward | device/gamepad/hid_writer_win.cc:56 | complete overlapped I/O for the pipe reader |
| `GetParent` | user32 | impl | ui/gfx/win/hwnd_util.cc:172 | parent HWND lookup |
| `GetPath` | gdi32 | forward | base/win/shortcut.cc:230 | `if (FAILED(i_shell_link->GetPath(temp, MAX_PATH, NULL, SLGP_UNCPRIORITY))) {` |
| `GetPerformanceInfo` | kernelbase | impl | base/process/process_metrics_win.cc:198 | `if (!GetPerformanceInfo(&info, sizeof(info))) {` |
| `GetPriorityClass` | kernel32 | forward | base/process/process_win.cc:249 | QProcess priority query |
| `GetProcAddress` | kernel32 | impl | base/debug/gdi_debug_util_win.cc:185 | resolve optional entry points; NULL => Qt uses a fallback implementation |
| `GetProcessDpiAwareness` | shcore | impl | base/win/win_util.cc:691 | `reinterpret_cast<decltype(::GetProcessDpiAwareness)*>(` |
| `GetProcessHandleCount` | kernel32 | forward | sandbox/win/src/handle_closer_agent.cc:172 | `if (!::GetProcessHandleCount(::GetCurrentProcess(), &handle_count))` |
| `GetProcessHeaps` | kernel32 | forward | sandbox/win/src/heap_helper.cc:99 | `DWORD number_of_heaps = ::GetProcessHeaps(0, nullptr);` |
| `GetProcessId` | kernel32 | forward | base/debug/close_handle_hook_win.cc:52 | `(GetProcessId(source_process) == ::GetCurrentProcessId())) {` |
| `GetProcessIoCounters` | kernel32 | impl | base/process/process_metrics_win.cc:169 | `return GetProcessIoCounters(process_.Get(), io_counters) != FALSE;` |
| `GetProcessMemoryInfo` | kernelbase | impl | base/debug/gdi_debug_util_win.cc:360 | `void NOINLINE GetProcessMemoryInfo(PROCESS_MEMORY_COUNTERS_EX* pmc) {` |
| `GetProcessMitigationPolicy` | kernel32 | forward | base/win/win_util.cc:606 | `GetProcessMitigationPolicy)* GetProcessMitigationPolicyType;` |
| `GetProcessTimes` | kernel32 | forward | base/process/process_metrics_win.cc:153 | QProcess/QThread CPU time |
| `GetProcessWindowStation` | user32 | forward | sandbox/win/src/window.cc:42 | query current station |
| `GetProductInfo` | kernel32 | forward | base/win/windows_version.cc:77 | `::GetProductInfo(version_info.dwMajorVersion, version_info.dwMinorVersion,` |
| `GetPropW` | user32 | impl | gpu/config/gpu_dx_diagnostics_win.cc:42 | recover the Qt window from an HWND (ATOM-based lookup) |
| `GetQueuedCompletionStatus` | kernel32 | forward | sandbox/win/src/broker_services.cc:236 | `if (!::GetQueuedCompletionStatus(port, &events, &key, &ovl, INFINITE)) {` |
| `GetRawInputData` | user32 | forward | device/gamepad/raw_input_data_fetcher_win.cc:320 | `UINT result = ::GetRawInputData(input_handle, RID_INPUT, nullptr, &size,` |
| `GetRawInputDeviceInfoW` | user32 | forward | device/gamepad/hid_writer_win.cc:17 | `::GetRawInputDeviceInfo(device, RIDI_DEVICENAME, nullptr, &size);` |
| `GetRawInputDeviceList` | user32 | forward | device/gamepad/raw_input_data_fetcher_win.cc:147 | `::GetRawInputDeviceList(nullptr, &count, sizeof(RAWINPUTDEVICELIST));` |
| `GetSecurityDescriptorSacl` | kernelbase | impl | sandbox/win/src/restricted_token_utils.cc:209 | `if (::GetSecurityDescriptorSacl(sec_desc, &sacl_present, &sacl,` |
| `GetSecurityInfo` | advapi32 | impl | sandbox/win/src/acl.cc:132 | `::GetSecurityInfo(object, object_type, DACL_SECURITY_INFORMATION, nullptr,` |
| `GetSidSubAuthority` | kernelbase | impl | base/process/process_info_win.cc:48 | `DWORD integrity_level = *::GetSidSubAuthority(` |
| `GetSidSubAuthorityCount` | kernelbase | impl | base/process/process_info_win.cc:50 | `static_cast<DWORD>(*::GetSidSubAuthorityCount(token_label->Label.Sid) -` |
| `GetStdHandle` | kernel32 | forward | base/process/launch_win.cc:74 | QProcess console handles |
| `GetStockObject` | gdi32 | impl | sandbox/win/src/process_mitigations_win32k_dispatcher.cc:154 | default pens/brushes/fonts used by the GDI engine |
| `GetSystemInfo` | kernel32 | forward | base/process/process_metrics_win.cc:195 | page size, processor count, architecture (QSettings/Random) |
| `GetSystemMetrics` | user32 | impl | base/win/win_util.cc:254 | screen metrics, virtual desktop, multi-monitor |
| `GetSystemPreferredUILanguages` | kernel32 | forward | base/win/i18n.cc:15 | `typedef decltype(::GetSystemPreferredUILanguages)* GetPreferredUILanguages_Fn;` |
| `GetSystemTimeAsFileTime` | kernel32 | forward | base/time/time_win.cc:74 | QDateTime current time; also the dispatcher's timeout base |
| `GetTempPathW` | kernel32 | forward | base/files/file_util_win.cc:469 | QDir::tempPath |
| `GetThreadDesktop` | user32 | forward | base/win/win_util.cc:777 | query thread desktop |
| `GetThreadId` | kernel32 | forward | base/threading/platform_thread_win.cc:303 | `thread_id = ::GetThreadId(thread_handle.platform_handle());` |
| `GetThreadInformation` | kernel32 | **absent** | base/threading/platform_thread_win.cc:197 | `reinterpret_cast<decltype(&::GetThreadInformation)>(::GetProcAddress(` |
| `GetThreadPreferredUILanguages` | kernel32 | forward | base/win/i18n.cc:64 | `::GetThreadPreferredUILanguages,` |
| `GetThreadPriority` | kernel32 | forward | base/threading/platform_thread_win.cc:435 | QThread priority query |
| `GetThreadTimes` | kernel32 | forward | base/time/time_win.cc:652 | QThread CPU time |
| `GetTickCount` | kernel32 | impl | base/process/kill_win.cc:93 | coarse QElapsedTimer fallback |
| `GetTokenInformation` | kernelbase | impl | base/process/process_info_win.cc:32 | TokenElevation/TokenSessionId |
| `GetTraceEnableFlags` | kernelbase | forward | base/win/event_trace_provider.cc:37 | `enable_flags_ = ::GetTraceEnableFlags(session_handle_);` |
| `GetTraceEnableLevel` | kernelbase | forward | base/win/event_trace_provider.cc:38 | `enable_level_ = ::GetTraceEnableLevel(session_handle_);` |
| `GetTraceLoggerHandle` | kernelbase | forward | base/win/event_trace_provider.cc:32 | `session_handle_ = ::GetTraceLoggerHandle(buffer);` |
| `GetUserDefaultLCID` | kernel32 | forward | sandbox/win/src/process_thread_interception.h:23 | QLocale system locale |
| `GetUserDefaultLangID` | kernel32 | forward | sandbox/win/src/target_services.cc:104 | `::GetUserDefaultLangID();` |
| `GetUserDefaultLocaleName` | kernel32 | forward | sandbox/win/src/target_services.cc:107 | `return (0 != ::GetUserDefaultLocaleName(localeName, LOCALE_NAME_MAX_LENGTH));` |
| `GetUserNameW` | advapi32 | impl | base/win/windows_types.h:254 | QSysInfo user name |
| `GetUserObjectInformationW` | user32 | forward | base/win/win_util.cc:758 | `::GetUserObjectInformation(handle, UOI_NAME, nullptr, 0, &size);` |
| `GetUserPreferredUILanguages` | kernel32 | forward | base/win/i18n.cc:57 | `return GetPreferredUILanguageList(::GetUserPreferredUILanguages, 0,` |
| `GetVersion` | kernel32 | forward | base/debug/invalid_access_win.cc:32 | `if (base::win::GetVersion() < base::win::Version::WIN10)` |
| `GetVersionExW` | kernel32 | forward | base/win/windows_version.cc:74 | deprecated; Qt no longer uses it for version detection |
| `GetVolumeInformationW` | kernel32 | forward | base/files/file_util_win.cc:910 | QStorageInfo volume label/fs; FALSE => invalid drive |
| `GetVolumePathNameW` | kernel32 | forward | base/files/file_util_win.cc:904 | `if (!GetVolumePathNameW(path.NormalizePathSeparators().value().c_str(),` |
| `GetWindowLongPtrW` | user32 | impl | base/win/message_window.cc:125 | read GWLP_USERDATA / window style; Qt uses it to recover the QWindowsWindow |
| `GetWindowLongW` | user32 | impl | ui/gfx/win/hwnd_util.cc:171 | `if (::GetWindowLong(window, GWL_STYLE) & WS_CHILD) {` |
| `GetWindowRect` | user32 | impl | ui/gfx/win/hwnd_util.cc:138 | query frame geometry |
| `GetWindowThreadProcessId` | user32 | impl | ui/gfx/win/hwnd_util.cc:109 | identify the owning thread/process of an HWND |
| `GlobalFree` | kernel32 | forward | net/proxy_resolution/proxy_resolver_winhttp.cc:26 | `GlobalFree(info->lpszProxy);` |
| `GlobalLock` | kernel32 | impl | base/win/scoped_hglobal.h:21 | `data_ = static_cast<T>(GlobalLock(glob_));` |
| `GlobalMemoryStatusEx` | kernel32 | forward | base/process/process_metrics_win.cc:218 | QStorageInfo/QSysInfo memory |
| `GlobalSize` | kernel32 | impl | base/win/scoped_hglobal.h:29 | `size_t Size() const { return GlobalSize(glob_); }` |
| `GlobalUnlock` | kernel32 | impl | base/win/scoped_hglobal.h:24 | `GlobalUnlock(glob_);` |
| `HeapAlloc` | kernel32 | forward | base/debug/invalid_access_win.cc:38 | `void* addr = ::HeapAlloc(heap, 0, 0x1000);` |
| `HeapCreate` | kernel32 | impl | base/debug/invalid_access_win.cc:34 | `HANDLE heap = ::HeapCreate(0, 0, 0);` |
| `HeapDestroy` | kernel32 | impl | base/debug/invalid_access_win.cc:45 | `HeapDestroy(heap);` |
| `HeapFree` | kernel32 | forward | base/debug/invalid_access_win.cc:44 | `HeapFree(heap, 0, addr);` |
| `HeapSetInformation` | kernel32 | forward | base/debug/invalid_access_win.cc:36 | `CHECK(HeapSetInformation(heap, HeapEnableTerminationOnCorruption, nullptr,` |
| `ImpersonateLoggedOnUser` | kernelbase | impl | sandbox/win/src/app_container_profile_base.cc:69 | `BOOL result = ::ImpersonateLoggedOnUser(token.Get());` |
| `InitPropVariantFromCLSID` | propsys | impl | base/win/win_util.cc:442 | `if (FAILED(InitPropVariantFromCLSID(property_clsid_value,` |
| `InitializeAcl` | kernelbase | impl | base/memory/platform_shared_memory_region_win.cc:258 | `if (!InitializeAcl(&dacl, sizeof(dacl), ACL_REVISION)) {` |
| `InitializeConditionVariable` | kernel32 | forward | base/synchronization/condition_variable_win.cc:24 | `InitializeConditionVariable(reinterpret_cast<PCONDITION_VARIABLE>(&cv_));` |
| `InitializeCriticalSection` | kernel32 | forward | sandbox/win/src/sandbox_policy_base.cc:114 | QMutex/global locks on Windows |
| `InitializeProcThreadAttributeList` | kernel32 | forward | base/process/launch_win.cc:228 | `if (!startup_info_wrapper.InitializeProcThreadAttributeList(1)) {` |
| `InitializeSecurityDescriptor` | kernelbase | impl | base/memory/platform_shared_memory_region_win.cc:262 | `if (!InitializeSecurityDescriptor(&sd, SECURITY_DESCRIPTOR_REVISION)) {` |
| `InitializeSid` | kernelbase | impl | sandbox/win/src/sid.cc:118 | `if (!::InitializeSid(sid.sid_, identifier_authority, sub_authority_count))` |
| `InterlockedCompareExchange` | kernel32 | impl | sandbox/win/src/sharedmem_ipc_client.cc:168 | `if (kFreeChannel == ::InterlockedCompareExchange(` |
| `InterlockedDecrement` | kernel32 | impl | sandbox/win/src/app_container_profile_base.cc:146 | `LONG ref_count = ::InterlockedDecrement(&ref_count_);` |
| `InterlockedExchange` | kernel32 | impl | sandbox/win/src/sharedmem_ipc_client.cc:76 | `LONG result = ::InterlockedExchange(&channel[num].state, kFreeChannel);` |
| `InterlockedIncrement` | kernel32 | impl | sandbox/win/src/app_container_profile_base.cc:142 | `::InterlockedIncrement(&ref_count_);` |
| `IsDebuggerPresent` | kernel32 | forward | base/debug/debugger_win.cc:20 | `return ::IsDebuggerPresent() != 0;` |
| `IsOS` | shlwapi | forward | base/win/win_util.cc:153 | `static bool state = IsOS(OS_DOMAINMEMBER);` |
| `IsRectEmpty` | user32 | impl | ui/gfx/win/hwnd_util.cc:141 | `if (::IsRectEmpty(&center_bounds)) {` |
| `IsValidSid` | kernelbase | impl | sandbox/win/src/app_container_profile_base.cc:236 | `if (!::IsValidSid(&ace->SidStart)) {` |
| `IsWindow` | user32 | impl | base/win/scoped_hdc.h:26 | validate HWNDs before calling |
| `IsWow64Process` | kernel32 | forward | base/win/windows_version.cc:250 | `if (!::IsWow64Process(process_handle, &is_wow64))` |
| `IsWow64Process2` | kernel32 | forward | sandbox/win/src/process_mitigations.cc:71 | `using IsWow64Process2Function = decltype(&IsWow64Process2);` |
| `LeaveCriticalSection` | kernel32 | forward | sandbox/win/src/win_utils.h:36 | QMutex unlock |
| `LoadCursorW` | user32 | impl | ui/gl/gl_surface_wgl.cc:95 | cursor loading for QCursor |
| `LoadIconW` | user32 | impl | base/win/windows_types.h:255 | `#define LoadIcon LoadIconW` |
| `LoadImageW` | user32 | impl | base/win/windows_types.h:256 | cursor/icon/bitmap loading |
| `LoadLibraryExW` | kernel32 | forward | base/win/core_winrt_util.cc:11 | load plugins with LOAD_WITH_ALTERED_SEARCH_PATH |
| `LoadLibraryW` | kernel32 | forward | base/win/com_init_check_hook.cc:140 | load opengl32.dll/angle/dll plugins; NULL => Qt reports 'failed to load' |
| `LoadResource` | kernel32 | forward | base/win/resource_util.cc:30 | `HGLOBAL hres = LoadResource(module, hres_info);` |
| `LocalFree` | kernel32 | forward | base/win/win_util.cc:387 | free CommandLineToArgvW |
| `LockFileEx` | kernel32 | forward | base/files/file_win.cc:255 | `LockFileEx(file_.Get(), LockFileFlagsForMode(mode), /*dwReserved=*/0,` |
| `LockResource` | kernel32 | forward | base/win/resource_util.cc:34 | `void* resource = LockResource(hres);` |
| `LookupPrivilegeValueW` | advapi32 | impl | sandbox/win/src/restricted_token.cc:289 | `::LookupPrivilegeValue(nullptr, (*exceptions)[j].c_str(), &luid);` |
| `MapGenericMask` | kernelbase | impl | sandbox/win/src/app_container_profile_base.cc:208 | `MapGenericMask(&desired_access, &generic_mapping);` |
| `MapViewOfFile` | kernel32 | forward | base/files/memory_mapped_file_win.cc:42 | QSharedMemory attach |
| `MapWindowPoints` | user32 | impl | ui/gfx/win/hwnd_util.cc:174 | coordinate translation between windows |
| `MonitorFromRect` | user32 | impl | ui/gfx/win/hwnd_util.cc:20 | `HMONITOR hmon = MonitorFromRect(&bounds, MONITOR_DEFAULTTONEAREST);` |
| `MonitorFromWindow` | user32 | impl | ui/gfx/win/hwnd_util.cc:143 | find the monitor for DPI/screen association |
| `MoveFileExW` | kernel32 | forward | base/files/file_util_win.cc:396 | rename/replace, MOVEFILE_REPLACE_EXISTING |
| `MoveFileW` | kernel32 | impl | base/files/file_util_win.cc:406 | `if (::MoveFile(from_path.value().c_str(), to_path.value().c_str()))` |
| `MoveWindow` | user32 | forward | ui/gl/gl_surface_wgl.cc:273 | resize path; FALSE => Qt keeps the old geometry |
| `NotifyAddrChange` | iphlpapi | impl | net/base/network_change_notifier_win.cc:293 | `DWORD ret = NotifyAddrChange(&handle, &addr_overlapped_);` |
| `NtClose` | ntdll | impl | sandbox/win/src/registry_policy.cc:33 | `NtCloseFunction NtClose = nullptr;` |
| `NtCreateEvent` | ntdll | impl | sandbox/win/src/sync_dispatcher.cc:39 | `return INTERCEPT_NT(manager, NtCreateEvent, CREATE_EVENT_ID, 24);` |
| `NtCreateFile` | ntdll | impl | sandbox/win/src/filesystem_dispatcher.cc:28 | `reinterpret_cast<CallbackGeneric>(&FilesystemDispatcher::NtCreateFile)};` |
| `NtCreateKey` | ntdll | impl | sandbox/win/src/registry_dispatcher.cc:51 | `reinterpret_cast<CallbackGeneric>(&RegistryDispatcher::NtCreateKey)};` |
| `NtCreateLowBoxToken` | ntdll | impl | sandbox/win/src/nt_internals.h:796 | `typedef NTSTATUS(WINAPI* NtCreateLowBoxToken)(` |
| `NtCreateSection` | ntdll | impl | sandbox/win/src/signed_dispatcher.cc:36 | `return INTERCEPT_NT(manager, NtCreateSection, CREATE_SECTION_ID, 32);` |
| `NtCurrentTeb` | ntdll | impl | base/win/com_init_util.cc:37 | `TEB* teb = NtCurrentTeb();` |
| `NtMapViewOfSection` | ntdll | impl | sandbox/win/src/interception.cc:369 | `ADD_NT_INTERCEPTION(NtMapViewOfSection, MAP_VIEW_OF_SECTION_ID, 44);` |
| `NtOpenDirectoryObject` | ntdll | impl | sandbox/win/src/sync_policy.cc:29 | `NtOpenDirectoryObjectFunction NtOpenDirectoryObject = nullptr;` |
| `NtOpenEvent` | ntdll | impl | sandbox/win/src/sync_dispatcher.cc:42 | `INTERCEPT_NT(manager, NtOpenEvent, OPEN_EVENT_ID, 16);` |
| `NtOpenFile` | ntdll | impl | sandbox/win/src/filesystem_dispatcher.cc:33 | `reinterpret_cast<CallbackGeneric>(&FilesystemDispatcher::NtOpenFile)};` |
| `NtOpenKey` | ntdll | impl | sandbox/win/src/registry_dispatcher.cc:55 | `reinterpret_cast<CallbackGeneric>(&RegistryDispatcher::NtOpenKey)};` |
| `NtOpenKeyEx` | ntdll | impl | sandbox/win/src/registry_dispatcher.cc:68 | `result &= INTERCEPT_NT(manager, NtOpenKeyEx, OPEN_KEY_EX_ID, 20);` |
| `NtOpenProcess` | ntdll | impl | sandbox/win/src/policy_broker.cc:96 | `!INTERCEPT_NT(manager, NtOpenProcess, OPEN_PROCESS_ID, 20) \\|\\|` |
| `NtOpenProcessToken` | ntdll | impl | sandbox/win/src/policy_broker.cc:97 | `!INTERCEPT_NT(manager, NtOpenProcessToken, OPEN_PROCESS_TOKEN_ID, 16))` |
| `NtOpenProcessTokenEx` | ntdll | impl | sandbox/win/src/policy_broker.cc:107 | `if (!INTERCEPT_NT(manager, NtOpenProcessTokenEx, OPEN_PROCESS_TOKEN_EX_ID,` |
| `NtOpenSymbolicLinkObject` | ntdll | impl | sandbox/win/src/sync_policy.cc:35 | `NtOpenSymbolicLinkObjectFunction NtOpenSymbolicLinkObject = nullptr;` |
| `NtOpenThread` | ntdll | impl | sandbox/win/src/policy_broker.cc:95 | `if (!INTERCEPT_NT(manager, NtOpenThread, OPEN_THREAD_ID, 20) \\|\\|` |
| `NtOpenThreadToken` | ntdll | impl | sandbox/win/src/policy_broker.cc:103 | `!INTERCEPT_NT(manager, NtOpenThreadToken, OPEN_THREAD_TOKEN_ID, 20))` |
| `NtOpenThreadTokenEx` | ntdll | impl | sandbox/win/src/policy_broker.cc:111 | `if (!INTERCEPT_NT(manager, NtOpenThreadTokenEx, OPEN_THREAD_TOKEN_EX_ID, 24))` |
| `NtQueryAttributesFile` | ntdll | impl | sandbox/win/src/filesystem_dispatcher.cc:38 | `&FilesystemDispatcher::NtQueryAttributesFile)};` |
| `NtQueryFullAttributesFile` | ntdll | impl | sandbox/win/src/filesystem_dispatcher.cc:44 | `&FilesystemDispatcher::NtQueryFullAttributesFile)};` |
| `NtQueryInformationProcess` | ntdll | impl | base/debug/gdi_debug_util_win.cc:108 | `using QueryInformationProcessFunc = decltype(NtQueryInformationProcess);` |
| `NtQueryObject` | ntdll | impl | sandbox/win/src/handle_closer.cc:161 | `static NtQueryObject QueryObject = nullptr;` |
| `NtQuerySymbolicLinkObject` | ntdll | impl | sandbox/win/src/sync_policy.cc:32 | `NtQuerySymbolicLinkObjectFunction NtQuerySymbolicLinkObject = nullptr;` |
| `NtQuerySystemInformation` | ntdll | impl | base/process/process_metrics_win.cc:272 | `reinterpret_cast<decltype(&::NtQuerySystemInformation)>(GetProcAddress(` |
| `NtSetInformationFile` | ntdll | impl | sandbox/win/src/filesystem_dispatcher.cc:50 | `&FilesystemDispatcher::NtSetInformationFile)};` |
| `NtSetInformationProcess` | ntdll | impl | sandbox/win/src/nt_internals.h:807 | `typedef NTSTATUS(WINAPI* NtSetInformationProcess)(IN HANDLE process_handle,` |
| `NtSetInformationThread` | ntdll | impl | sandbox/win/src/policy_broker.cc:101 | `if (!INTERCEPT_NT(manager, NtSetInformationThread, SET_INFORMATION_THREAD_ID,` |
| `NtUnmapViewOfSection` | ntdll | impl | sandbox/win/src/interception.cc:370 | `ADD_NT_INTERCEPTION(NtUnmapViewOfSection, UNMAP_VIEW_OF_SECTION_ID, 12);` |
| `OpenEventW` | kernel32 | forward | sandbox/win/src/sync_dispatcher.cc:30 | `reinterpret_cast<CallbackGeneric>(&SyncDispatcher::OpenEvent)};` |
| `OpenFile` | kernel32 | impl | base/files/file_util_win.cc:524 | `return OpenFile(*path, "wb+");` |
| `OpenProcess` | kernel32 | forward | base/debug/gdi_debug_util_win.cc:403 | query/terminate another process |
| `OpenProcessToken` | kernel32 | forward | base/process/process_info_win.cc:21 | TokenElevation query (IsUserAnAdmin replacement) |
| `OpenTraceW` | advapi32 | forward | base/win/event_trace_consumer.h:98 | `TRACEHANDLE trace_handle = ::OpenTrace(&logfile);` |
| `PathMatchSpecW` | kernelbase | impl | base/files/file_enumerator_win.cc:190 | `return PathMatchSpec(src.value().c_str(), pattern_.c_str()) == TRUE;` |
| `PostMessageW` | user32 | impl | base/win/windows_types.h:257 | async cross-thread notification (0 => queue full / invalid hwnd) |
| `PostQueuedCompletionStatus` | kernel32 | forward | sandbox/win/src/broker_services.cc:126 | `::PostQueuedCompletionStatus(tracker->iocp, 0, THREAD_CTRL_PROCESS_SIGNALLED,` |
| `PowerDeterminePlatformRoleEx` | powrprof | impl | base/win/win_util.cc:94 | `return PowerDeterminePlatformRoleEx(POWER_PLATFORM_ROLE_V2);` |
| `PrefetchVirtualMemory` | kernel32 | forward | base/files/file_util_win.cc:939 | `using PrefetchVirtualMemoryPtr = decltype(&::PrefetchVirtualMemory);` |
| `Process32First` | kernel32 | impl | base/debug/gdi_debug_util_win.cc:322 | `CHECK(Process32First(snapshot, proc_entry));` |
| `Process32Next` | kernel32 | impl | base/debug/gdi_debug_util_win.cc:427 | `} while (Process32Next(snapshot, &proc_entry));` |
| `ProcessIdToSessionId` | kernel32 | forward | base/win/win_util.cc:795 | session detection |
| `ProcessTrace` | advapi32 | forward | base/win/event_trace_consumer.h:126 | `ULONG err = ::ProcessTrace(&trace_handles_[0],` |
| `PropVariantClear` | ole32 | forward | base/win/scoped_propvariant.h:38 | `HRESULT result = PropVariantClear(&pv_);` |
| `QueryDosDeviceW` | kernel32 | forward | base/files/file_util_win.cc:719 | `if (QueryDosDevice(drive, device_path_as_string, MAX_PATH)) {` |
| `QueryPerformanceCounter` | kernel32 | forward | base/time/time_win.cc:135 | QElapsedTimer high-resolution clock |
| `QueryPerformanceFrequency` | kernel32 | forward | base/time/time_win.cc:534 | QElapsedTimer tick frequency |
| `QueryThreadCycleTime` | kernel32 | forward | base/time/time_win.cc:660 | `::QueryThreadCycleTime(thread_handle.platform_handle(), &thread_cycle_time);` |
| `QueryUnbiasedInterruptTime` | kernel32 | forward | gpu/ipc/service/gpu_watchdog_thread.cc:301 | `QueryUnbiasedInterruptTime(&arm_interrupt_time_);` |
| `RaiseException` | kernel32 | forward | base/process/memory_win.cc:52 | structured-exception handling path used by the C++ runtime |
| `RaiseFailFastException` | kernel32 | forward | base/debug/invalid_access_win.cc:22 | `RaiseFailFastException(&record, nullptr,` |
| `ReadFile` | kernel32 | forward | base/files/file_util_win.cc:812 | read from pipe/file; FALSE+ERROR_BROKEN_PIPE => Qt treats as EOF (success) |
| `ReadProcessMemory` | kernel32 | forward | sandbox/win/src/service_resolver_32.cc:229 | `if (!::ReadProcessMemory(process_, target_, &function_code,` |
| `RegCloseKey` | kernel32 | forward | base/win/registry.cc:202 | balance registry handles |
| `RegCreateKeyExW` | kernel32 | forward | base/win/registry.cc:128 | QSettings key creation |
| `RegDeleteKeyExW` | kernel32 | forward | base/win/registry.cc:281 | `return RegDeleteKeyEx(key_, name, wow64access_, 0);` |
| `RegDeleteValueW` | kernel32 | forward | base/win/registry.cc:288 | `LONG result = RegDeleteValue(key_, value_name);` |
| `RegDisablePredefinedCache` | advapi32 | impl | sandbox/win/src/target_services.cc:142 | `if (ERROR_SUCCESS != ::RegDisablePredefinedCache())` |
| `RegEnumKeyExW` | kernel32 | forward | base/win/registry.cc:460 | QSettings child groups |
| `RegEnumValueW` | kernel32 | forward | base/win/registry.cc:237 | `LONG r = ::RegEnumValue(key_, index, buf, &bufsize, NULL, NULL, NULL, NULL);` |
| `RegNotifyChangeKeyValue` | kernel32 | forward | base/win/registry.cc:80 | `LONG result = RegNotifyChangeKeyValue(key, TRUE, filter, watch_event_.Get(),` |
| `RegOpenKeyExW` | kernel32 | forward | base/win/registry.cc:166 | QSettings registry backend |
| `RegQueryInfoKeyW` | kernel32 | forward | base/win/registry.cc:229 | QSettings key metadata |
| `RegQueryValueExW` | kernel32 | forward | base/win/registry.cc:224 | QSettings value read |
| `RegSetValueExW` | kernel32 | forward | base/win/registry.cc:415 | QSettings value write |
| `RegisterClassExW` | user32 | impl | base/win/message_window.cc:54 | register the Qt window class (QT_WINDOW_CLASS_NAME / Qt6Build...); 0 with ERROR_CLASS_ALREADY_EXISTS is tolerated by Qt |
| `RegisterClassW` | user32 | impl | sandbox/win/src/process_mitigations_win32k_dispatcher.cc:162 | `if (!INTERCEPT_EAT(manager, L"user32.dll", RegisterClassW,` |
| `RegisterHotKey` | user32 | forward | ui/gfx/win/singleton_hwnd_hot_key_observer.cc:58 | `if (!RegisterHotKey(gfx::SingletonHwnd::GetInstance()->hwnd(), *hot_key_id,` |
| `RegisterRawInputDevices` | user32 | forward | device/gamepad/raw_input_data_fetcher_win.cc:83 | `if (!::RegisterRawInputDevices(devices.get(), base::size(DeviceUsages),` |
| `RegisterTraceGuidsW` | kernelbase | forward | base/win/event_trace_provider.cc:82 | `return ::RegisterTraceGuids(ControlCallback, this, &provider_name_,` |
| `RegisterWaitForSingleObject` | kernel32 | impl | base/win/object_watcher.cc:99 | `if (!RegisterWaitForSingleObject(&wait_object_, object, DoneWaiting,` |
| `ReleaseDC` | user32 | forward | base/win/scoped_hdc.h:39 | balance GetDC; failure leaks DCs |
| `ReleaseSRWLockExclusive` | kernel32 | forward | base/win/windows_types.h:212 | `ReleaseSRWLockExclusive(_Inout_ PSRWLOCK SRWLock);` |
| `RemoveDirectoryW` | kernel32 | forward | base/files/file_util_win.cc:151 | QDir::rmdir |
| `RemovePropW` | user32 | impl | base/win/win_util.cc:670 | detach window data |
| `ReplaceFile` | kernel32 | forward | base/files/file_util_win.cc:400 | `bool ReplaceFile(const FilePath& from_path,` |
| `ReplaceFileW` | kernel32 | forward | base/win/windows_types.h:259 | `#define ReplaceFile ReplaceFileW` |
| `ReportEventW` | advapi32 | impl | base/win/windows_types.h:260 | `#define ReportEvent ReportEventW` |
| `ResetEvent` | kernel32 | forward | base/synchronization/waitable_event_win.cc:43 | re-arm auto-reset events |
| `RevertToSelf` | kernelbase | impl | sandbox/win/src/app_container_profile_base.cc:74 | `BOOL result = ::RevertToSelf();` |
| `RoActivateInstance` | combase | impl | base/win/core_winrt_util.cc:29 | `decltype(&::RoActivateInstance) GetRoActivateInstanceFunction() {` |
| `RoGetActivationFactory` | combase | impl | base/win/core_winrt_util.cc:36 | `decltype(&::RoGetActivationFactory) GetRoGetActivationFactoryFunction() {` |
| `RoInitialize` | combase | impl | base/win/core_winrt_util.cc:15 | `decltype(&::RoInitialize) GetRoInitializeFunction() {` |
| `RoUninitialize` | combase | impl | base/win/core_winrt_util.cc:22 | `decltype(&::RoUninitialize) GetRoUninitializeFunction() {` |
| `RtlAllocateHeap` | ntdll | impl | sandbox/win/src/policy_broker.cc:61 | `INIT_GLOBAL_RTL(RtlAllocateHeap);` |
| `RtlAnsiStringToUnicodeString` | ntdll | impl | sandbox/win/src/policy_broker.cc:62 | `INIT_GLOBAL_RTL(RtlAnsiStringToUnicodeString);` |
| `RtlCompareUnicodeString` | ntdll | impl | sandbox/win/src/interception_agent.cc:78 | `!g_nt.RtlCompareUnicodeString(&current_name, full_path, case_insensitive))` |
| `RtlCreateHeap` | ntdll | impl | sandbox/win/src/policy_broker.cc:64 | `INIT_GLOBAL_RTL(RtlCreateHeap);` |
| `RtlCreateUserThread` | ntdll | impl | sandbox/win/src/policy_broker.cc:65 | `INIT_GLOBAL_RTL(RtlCreateUserThread);` |
| `RtlDestroyHeap` | ntdll | impl | sandbox/win/src/policy_broker.cc:66 | `INIT_GLOBAL_RTL(RtlDestroyHeap);` |
| `RtlFreeHeap` | ntdll | impl | sandbox/win/src/policy_broker.cc:67 | `INIT_GLOBAL_RTL(RtlFreeHeap);` |
| `RtlInitUnicodeString` | ntdll | impl | sandbox/win/src/process_mitigations_win32k_policy.cc:44 | `static RtlInitUnicodeStringFunction RtlInitUnicodeString;` |
| `SHChangeNotify` | shell32 | impl | base/win/shortcut.cc:189 | `SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, NULL, NULL);` |
| `SHGetFolderPathW` | shell32 | impl | base/files/file_util_win.cc:481 | legacy QStandardPaths fallback |
| `SafeArrayDestroy` | oleaut32 | impl | base/win/scoped_safearray.h:39 | `HRESULT hr = SafeArrayDestroy(safearray_);` |
| `SafeArrayGetVartype` | oleaut32 | impl | base/win/scoped_variant.cc:213 | `if (SUCCEEDED(::SafeArrayGetVartype(array, &var_.vt))) {` |
| `SearchPathW` | kernel32 | forward | sandbox/win/src/process_thread_dispatcher.cc:80 | executable lookup for QProcess |
| `SelectObject` | gdi32 | impl | base/win/scoped_select_object.h:21 | `oldobj_(SelectObject(hdc, object)) {` |
| `SendMessageCallbackW` | user32 | impl | base/win/windows_types.h:262 | `#define SendMessageCallback SendMessageCallbackW` |
| `SendMessageW` | user32 | impl | base/win/windows_types.h:261 | synchronous cross-thread call; Qt uses it for WM_QT_* internal messages |
| `SetColorSpace` | gdi32 | impl | ui/gl/gl_surface_egl_surface_control.cc:373 | `pending_transaction_->SetColorSpace(*surface_state.surface,` |
| `SetCurrentDirectoryW` | kernel32 | forward | base/files/file_util_win.cc:895 | QDir::setCurrent |
| `SetDefaultDllDirectories` | kernel32 | forward | sandbox/win/src/process_mitigations.cc:25 | `using SetDefaultDllDirectoriesFunction = decltype(&SetDefaultDllDirectories);` |
| `SetEndOfFile` | kernel32 | forward | base/files/file_win.cc:193 | truncate QFile |
| `SetEntriesInAclW` | advapi32 | impl | sandbox/win/src/acl.cc:56 | `if (ERROR_SUCCESS != ::SetEntriesInAcl(1, &new_access, old_dacl, new_dacl))` |
| `SetErrorMode` | kernel32 | forward | content/gpu/gpu_main.cc:244 | suppress Windows error dialogs (Qt sets SEM_FAILCRITICALERRORS) |
| `SetEvent` | kernel32 | forward | base/synchronization/waitable_event_win.cc:47 | wake the event dispatcher / signal QWaitCondition |
| `SetFileAttributesW` | kernel32 | forward | base/files/file_util_win.cc:139 | `::SetFileAttributes(` |
| `SetFileInformationByHandle` | kernel32 | forward | base/files/file_win.cc:301 | `return ::SetFileInformationByHandle(GetPlatformFile(), FileDispositionInfo,` |
| `SetFilePointerEx` | kernel32 | forward | base/files/file_win.cc:55 | 64-bit seek on QFile |
| `SetFileTime` | kernel32 | forward | base/files/file_win.cc:206 | QFile::setFileTime |
| `SetHandleInformation` | kernel32 | forward | base/process/launch_win.cc:62 | make pipe handles inheritable/non-inheritable |
| `SetInformationJobObject` | kernel32 | impl | base/process/launch_win.cc:395 | `return 0 != SetInformationJobObject(` |
| `SetKernelObjectSecurity` | kernelbase | impl | sandbox/win/src/restricted_token_utils.cc:317 | `if (!::SetKernelObjectSecurity(token, LABEL_SECURITY_INFORMATION,` |
| `SetLastError` | kernel32 | forward | base/files/file_util_win.cc:628 | `::SetLastError(ERROR_FILE_EXISTS);` |
| `SetMapMode` | gdi32 | impl | ui/gfx/win/scoped_set_map_mode.h:20 | `old_map_mode_(SetMapMode(hdc, map_mode)) {` |
| `SetParent` | user32 | forward | ui/gfx/win/rendering_window_manager.cc:56 | reparent (native widgets/popups) |
| `SetPixelFormat` | gdi32 | impl | ui/gl/gl_surface_wgl.cc:129 | apply pixel format; FALSE => context creation fails |
| `SetPriorityClass` | kernel32 | forward | base/process/launch_win.cc:425 | `SetPriorityClass(GetCurrentProcess(), HIGH_PRIORITY_CLASS);` |
| `SetProcessDEPPolicy` | kernel32 | impl | sandbox/win/src/process_mitigations.cc:146 | `if (!::SetProcessDEPPolicy(dep_flags) &&` |
| `SetProcessDPIAware` | user32 | impl | base/win/win_util.cc:721 | Vista DPI awareness fallback; FALSE if already set is benign |
| `SetProcessDpiAwareness` | shcore | impl | base/win/win_util.cc:107 | Win8.1 process DPI awareness; failure => Qt falls back to SetProcessDPIAware |
| `SetProcessDpiAwarenessContext` | user32 | impl | base/win/win_util.cc:138 | Win10 1703 per-monitor-v2 awareness; Qt selects the best available level |
| `SetProcessDpiAwarenessInternal` | user32 | impl | base/win/win_util.cc:114 | `<< "Access denied error from SetProcessDpiAwarenessInternal. "` |
| `SetProcessMitigationPolicy` | kernel32 | forward | sandbox/win/src/process_mitigations.cc:29 | `decltype(&SetProcessMitigationPolicy);` |
| `SetProcessWindowStation` | user32 | forward | sandbox/win/src/window.cc:96 | switch window station in QWindowsContext init |
| `SetPropW` | user32 | impl | base/win/win_util.cc:674 | attach QWindowsWindow data to an HWND |
| `SetSecurityDescriptorDacl` | kernelbase | impl | base/memory/platform_shared_memory_region_win.cc:266 | `if (!SetSecurityDescriptorDacl(&sd, TRUE, &dacl, FALSE)) {` |
| `SetSecurityInfo` | advapi32 | impl | sandbox/win/src/acl.cc:142 | `::SetSecurityInfo(object, object_type, DACL_SECURITY_INFORMATION, nullptr,` |
| `SetThreadAffinityMask` | kernel32 | impl | sandbox/win/src/handle_closer_agent.cc:74 | QThread affinity on Windows |
| `SetThreadDescription` | kernel32 | forward | base/threading/platform_thread_win.cc:52 | `typedef HRESULT(WINAPI* SetThreadDescription)(HANDLE hThread,` |
| `SetThreadInformation` | kernel32 | forward | sandbox/win/src/process_mitigations.cc:32 | `using SetThreadInformationFunction = decltype(&SetThreadInformation);` |
| `SetThreadPriority` | kernel32 | forward | base/threading/platform_thread_win.cc:356 | QThread priority mapping |
| `SetThreadToken` | kernel32 | forward | sandbox/win/src/target_process.cc:200 | `if (!::SetThreadToken(&temp_thread, impersonation_token)) {` |
| `SetTokenInformation` | kernelbase | impl | sandbox/win/src/acl.cc:81 | `bool ret = ::SetTokenInformation(token, TokenDefaultDacl, &new_token_dacl,` |
| `SetUnhandledExceptionFilter` | kernel32 | forward | base/debug/stack_trace_win.cc:274 | `g_previous_filter = SetUnhandledExceptionFilter(&StackDumpExceptionFilter);` |
| `SetWindowLongPtrW` | user32 | impl | base/win/message_window.cc:139 | install the Qt window proc and GWLP_USERDATA; 0 may mean previous value was 0 (check GetLastError) |
| `SetWindowPos` | user32 | forward | ui/gfx/win/hwnd_util.cc:31 | move/resize/z-order; FALSE => Qt logs a warning |
| `SetupDiDestroyDeviceInfoList` | setupapi | impl | ui/gfx/win/physical_size.cc:32 | `static void Free(HDEVINFO h) { SetupDiDestroyDeviceInfoList(h); }` |
| `SetupDiEnumDeviceInfo` | setupapi | impl | base/win/win_util.cc:331 | `if (!SetupDiEnumDeviceInfo(device_info, i, &device_info_data))` |
| `SetupDiEnumDeviceInterfaces` | setupapi | impl | ui/gfx/win/physical_size.cc:119 | `while (SetupDiEnumDeviceInterfaces(device_info_list.get(), nullptr,` |
| `SetupDiGetClassDevsW` | setupapi | impl | base/win/win_util.cc:318 | `SetupDiGetClassDevs(&KEYBOARD_CLASS_GUID, NULL, NULL, DIGCF_PRESENT);` |
| `SetupDiGetDeviceInterfaceDetailW` | setupapi | impl | ui/gfx/win/physical_size.cc:83 | `SetupDiGetDeviceInterfaceDetail(device_info_list, interface_data, nullptr, 0,` |
| `SetupDiOpenDevRegKey` | setupapi | impl | ui/gfx/win/physical_size.cc:39 | `base::win::RegKey reg_key(SetupDiOpenDevRegKey(` |
| `ShellExecuteEx` | shell32 | forward | base/process/launch_win.cc:379 | `if (!ShellExecuteEx(&shex_info)) {` |
| `ShellExecuteW` | shell32 | impl | base/win/shortcut.cc:364 | `intptr_t result = reinterpret_cast<intptr_t>(ShellExecute(` |
| `SignalObjectAndWait` | kernel32 | forward | sandbox/win/src/sharedmem_ipc_client.cc:29 | `return SignalObjectAndWait(object_to_signal, object_to_wait_on, millis,` |
| `SizeofResource` | kernel32 | forward | base/win/resource_util.cc:29 | `DWORD data_size = SizeofResource(module, hres_info);` |
| `Sleep` | kernel32 | forward | base/threading/platform_thread_win.cc:234 | `::Sleep(0);` |
| `SleepConditionVariableSRW` | kernel32 | forward | base/synchronization/condition_variable_win.cc:45 | `if (!SleepConditionVariableSRW(reinterpret_cast<PCONDITION_VARIABLE>(&cv_),` |
| `StackWalk64` | dbghelp | impl | base/debug/stack_trace_win.cc:330 | stack unwinding (dbghelp) |
| `StartServiceW` | advapi32 | forward | base/win/windows_types.h:264 | `#define StartService StartServiceW` |
| `StartTraceW` | advapi32 | forward | base/win/event_trace_controller.cc:138 | `ULONG err = ::StartTrace(session_handle, session_name, properties->get());` |
| `StrCatW` | shlwapi | impl | ui/gl/gl_surface_egl_surface_control.cc:38 | `return base::StrCat(` |
| `SwapBuffers` | gdi32 | impl | ui/gl/direct_composition_child_surface_win.cc:187 | present the GL frame |
| `SymCleanup` | dbghelp | impl | base/debug/stack_trace_win.cc:125 | `SymCleanup(GetCurrentProcess());` |
| `SymFromAddr` | dbghelp | impl | base/debug/stack_trace_win.cc:230 | `BOOL has_symbol = SymFromAddr(GetCurrentProcess(), frame,` |
| `SymFunctionTableAccess64` | dbghelp | impl | base/debug/stack_trace_win.cc:332 | `&SymFunctionTableAccess64, &SymGetModuleBase64, NULL) &&` |
| `SymGetLineFromAddr64` | dbghelp | impl | base/debug/stack_trace_win.cc:237 | `BOOL has_line = SymGetLineFromAddr64(GetCurrentProcess(), frame,` |
| `SymGetModuleBase64` | dbghelp | impl | base/debug/stack_trace_win.cc:332 | `&SymFunctionTableAccess64, &SymGetModuleBase64, NULL) &&` |
| `SymGetSearchPath` | dbghelp | impl | base/debug/stack_trace_win.cc:157 | `DLOG(WARNING) << "SymGetSearchPath failed: " << g_init_error;` |
| `SymGetSearchPathW` | dbghelp | impl | base/debug/stack_trace_win.cc:154 | `if (!SymGetSearchPathW(GetCurrentProcess(), symbols_path,` |
| `SymInitialize` | dbghelp | impl | base/debug/stack_trace_win.cc:134 | symbol handler init (dbghelp) |
| `SymSetOptions` | dbghelp | impl | base/debug/stack_trace_win.cc:131 | `SymSetOptions(SYMOPT_DEFERRED_LOADS \\|` |
| `SymSetSearchPath` | dbghelp | impl | base/debug/stack_trace_win.cc:165 | `DLOG(WARNING) << "SymSetSearchPath failed." << g_init_error;` |
| `SymSetSearchPathW` | dbghelp | impl | base/debug/stack_trace_win.cc:163 | `if (!SymSetSearchPathW(GetCurrentProcess(), new_path.c_str())) {` |
| `SysAllocString` | oleaut32 | impl | base/win/scoped_variant.cc:120 | `var_.bstrVal = ::SysAllocString(str);` |
| `SysAllocStringByteLen` | oleaut32 | impl | base/win/scoped_bstr.cc:30 | `BSTR result = ::SysAllocStringByteLen(nullptr, checked_cast<UINT>(bytes));` |
| `SysAllocStringLen` | oleaut32 | impl | base/win/scoped_bstr.cc:20 | `BSTR result = ::SysAllocStringLen(non_bstr.data(),` |
| `SysFreeString` | oleaut32 | impl | base/win/scoped_bstr.cc:43 | `::SysFreeString(bstr_);` |
| `SysStringByteLen` | oleaut32 | impl | base/win/scoped_bstr.cc:92 | `return ::SysStringByteLen(bstr_);` |
| `SysStringLen` | oleaut32 | impl | base/win/scoped_bstr.cc:88 | `return ::SysStringLen(bstr_);` |
| `SystemFunction036` | advapi32 | forward | sandbox/win/src/sandbox_rand.cc:12 | `#define SystemFunction036 NTAPI SystemFunction036` |
| `SystemTimeToFileTime` | kernel32 | forward | base/time/time_win.cc:321 | `SystemTimeToFileTime(&utc_st, &ft);` |
| `SystemTimeToTzSpecificLocalTime` | kernel32 | forward | base/time/time_win.cc:357 | `SystemTimeToTzSpecificLocalTime(nullptr, &utc_st, &st);` |
| `TerminateJobObject` | kernel32 | impl | sandbox/win/src/broker_services.cc:82 | `bool res = ::TerminateJobObject(job.Get(), sandbox::SBOX_ALL_OK);` |
| `TerminateProcess` | kernel32 | forward | base/process/process_win.cc:96 | QProcess::kill |
| `TlsAlloc` | kernel32 | forward | base/threading/thread_local_storage_win.cc:16 | `TLSKey value = TlsAlloc();` |
| `TlsFree` | kernel32 | forward | base/threading/thread_local_storage_win.cc:25 | `BOOL ret = TlsFree(key);` |
| `TlsGetValue` | kernel32 | forward | base/win/windows_types.h:221 | `WINBASEAPI LPVOID WINAPI TlsGetValue(_In_ DWORD dwTlsIndex);` |
| `TlsSetValue` | kernel32 | forward | base/threading/thread_local_storage_win.cc:30 | `BOOL ret = TlsSetValue(key, value);` |
| `TraceEvent` | kernelbase | forward | base/win/event_trace_provider.cc:109 | `return ::TraceEvent(session_handle_, &event.header);` |
| `TryAcquireSRWLockExclusive` | kernel32 | forward | base/synchronization/lock_impl_win.cc:19 | `return !!::TryAcquireSRWLockExclusive(` |
| `TzSpecificLocalTimeToSystemTime` | kernel32 | forward | base/time/time_win.cc:320 | `success = TzSpecificLocalTimeToSystemTime(nullptr, &st, &utc_st) &&` |
| `UnlockFileEx` | kernel32 | forward | base/files/file_win.cc:270 | `UnlockFileEx(file_.Get(), /*dwReserved=*/0,` |
| `UnmapViewOfFile` | kernel32 | forward | base/files/memory_mapped_file_win.cc:134 | QSharedMemory detach |
| `UnregisterClassW` | user32 | impl | base/win/message_window.cc:63 | teardown of the Qt window class |
| `UnregisterHotKey` | user32 | forward | ui/gfx/win/singleton_hwnd_hot_key_observer.cc:78 | `bool success = !!UnregisterHotKey(gfx::SingletonHwnd::GetInstance()->hwnd(),` |
| `UnregisterTraceGuids` | kernelbase | forward | base/win/event_trace_provider.cc:91 | `ULONG ret = ::UnregisterTraceGuids(registration_handle_);` |
| `UnregisterWait` | kernel32 | impl | sandbox/win/src/broker_services.cc:354 | `::UnregisterWait(tracker->wait_handle);` |
| `UnregisterWaitEx` | kernel32 | forward | base/win/object_watcher.cc:45 | `if (!UnregisterWaitEx(wait_object_, INVALID_HANDLE_VALUE)) {` |
| `UpdateProcThreadAttribute` | kernel32 | forward | base/process/launch_win.cc:233 | `if (!startup_info_wrapper.UpdateProcThreadAttribute(` |
| `UpdateResourceW` | kernel32 | impl | base/win/windows_types.h:265 | `#define UpdateResource UpdateResourceW` |
| `UserHandleGrantAccess` | user32 | impl | sandbox/win/src/job.cc:91 | `DWORD Job::UserHandleGrantAccess(HANDLE handle) {` |
| `VarCmp` | oleaut32 | impl | base/win/scoped_variant.cc:101 | `HRESULT hr = ::VarCmp(const_cast<VARIANT*>(&var_), const_cast<VARIANT*>(&var),` |
| `VariantClear` | oleaut32 | impl | base/win/scoped_variant.cc:22 | `::VariantClear(&var_);` |
| `VariantCopy` | oleaut32 | impl | base/win/scoped_variant.cc:95 | `::VariantCopy(&ret, &var_);` |
| `VariantInit` | oleaut32 | impl | gpu/config/gpu_dx_diagnostics_win.cc:31 | `VariantInit(&variant);` |
| `VirtualAllocEx` | kernel32 | forward | sandbox/win/src/interception.cc:375 | `BYTE* thunk_base = reinterpret_cast<BYTE*>(::VirtualAllocEx(` |
| `VirtualFree` | kernel32 | forward | sandbox/win/src/handle_closer_agent.cc:163 | `::VirtualFree(g_handles_to_close, 0, MEM_RELEASE);` |
| `VirtualFreeEx` | kernel32 | forward | sandbox/win/src/win_utils.cc:496 | `::VirtualFreeEx(child, remote_data, 0, MEM_RELEASE);` |
| `VirtualProtect` | kernel32 | forward | base/debug/close_handle_hook_win.cc:107 | `if (!VirtualProtect(address, bytes, protect, &old_protect_))` |
| `VirtualProtectEx` | kernel32 | forward | sandbox/win/src/interception.cc:421 | `::VirtualProtectEx(child, thunks, thunk_bytes, PAGE_EXECUTE_READ,` |
| `VirtualQuery` | kernel32 | forward | base/debug/close_handle_hook_win.cc:99 | `if (!VirtualQuery(address, &memory_info, sizeof(memory_info)))` |
| `VirtualQueryEx` | kernel32 | forward | sandbox/win/src/process_mitigations.cc:547 | `if (!::VirtualQueryEx(process, ptr, &memory_info, sizeof(memory_info)))` |
| `WSACloseEvent` | ws2_32 | impl | net/base/network_change_notifier_win.cc:57 | `WSACloseEvent(addr_overlapped_.hEvent);` |
| `WSACreateEvent` | ws2_32 | impl | net/base/network_change_notifier_win.cc:47 | `addr_overlapped_.hEvent = WSACreateEvent();` |
| `WSAGetLastError` | ws2_32 | impl | net/base/network_change_notifier_win.cc:141 | socket error mapping; Qt translates WSAE* to QAbstractSocket::SocketError |
| `WSALookupServiceBeginW` | ws2_32 | impl | net/base/network_change_notifier_win.cc:139 | `if (0 != WSALookupServiceBegin(&query_set, LUP_RETURN_ALL,` |
| `WSALookupServiceEnd` | ws2_32 | impl | net/base/network_change_notifier_win.cc:183 | `result = WSALookupServiceEnd(ws_handle);` |
| `WSALookupServiceNextW` | ws2_32 | impl | net/base/network_change_notifier_win.cc:156 | `int result = WSALookupServiceNext(` |
| `WaitForMultipleObjects` | kernel32 | forward | base/synchronization/waitable_event_win.cc:141 | wait on the dispatcher event + message queue |
| `WaitForSingleObject` | kernel32 | forward | base/process/kill_win.cc:44 | QSystemSemaphore::acquire |
| `WakeAllConditionVariable` | kernel32 | forward | base/synchronization/condition_variable_win.cc:62 | QWaitCondition::wakeAll |
| `WakeConditionVariable` | kernel32 | forward | base/synchronization/condition_variable_win.cc:66 | QWaitCondition::wakeOne |
| `WideCharToMultiByte` | kernel32 | forward | sandbox/win/src/process_mitigations_win32k_interception.cc:173 | QString<->QByteArray codec conversion |
| `WinHttpCloseHandle` | winhttp | impl | net/proxy_resolution/proxy_resolver_winhttp.cc:210 | `WinHttpCloseHandle(session_handle_);` |
| `WinHttpGetProxyForUrl` | winhttp | impl | net/proxy_resolution/proxy_resolver_winhttp.cc:134 | `BOOL ok = WinHttpGetProxyForUrl(` |
| `WinHttpOpen` | winhttp | impl | net/proxy_resolution/proxy_resolver_winhttp.cc:193 | `WinHttpOpen(nullptr, WINHTTP_ACCESS_TYPE_NO_PROXY, WINHTTP_NO_PROXY_NAME,` |
| `WinHttpSetTimeouts` | winhttp | impl | net/proxy_resolution/proxy_resolver_winhttp.cc:202 | `BOOL rv = WinHttpSetTimeouts(session_handle_, 10000, 10000, 5000, 5000);` |
| `WindowsCompareStringOrdinal` | combase | impl | base/win/hstring_compare.cc:16 | `using CompareStringFunc = decltype(&::WindowsCompareStringOrdinal);` |
| `WindowsCreateString` | combase | impl | base/win/scoped_hstring.cc:26 | `decltype(&::WindowsCreateString) GetWindowsCreateString() {` |
| `WindowsCreateStringReference` | combase | impl | base/win/hstring_reference.cc:20 | `decltype(&::WindowsCreateStringReference) GetWindowsCreateStringReference() {` |
| `WindowsDeleteString` | combase | impl | base/win/scoped_hstring.cc:33 | `decltype(&::WindowsDeleteString) GetWindowsDeleteString() {` |
| `WindowsGetStringRawBuffer` | combase | impl | base/win/scoped_hstring.cc:40 | `decltype(&::WindowsGetStringRawBuffer) GetWindowsGetStringRawBuffer() {` |
| `WriteFile` | kernel32 | forward | base/files/file_util_win.cc:828 | write to pipe/file; FALSE+ERROR_NO_DATA => peer closed, Qt treats as EOF |
| `WriteProcessMemory` | kernel32 | forward | sandbox/win/src/interception.cc:413 | `!!::WriteProcessMemory(child, thunks, &dll_data,` |
| `_snwprintf_s` | ntdll | impl | sandbox/win/src/window.cc:75 | `_snwprintf_s(buffer, sizeof(buffer) / sizeof(wchar_t), L"0x%X",` |
| `_strnicmp` | ntdll | impl | base/win/pe_image.cc:153 | `if (_strnicmp(reinterpret_cast<LPCSTR>(section->Name), section_name,` |
| `_wcsicmp` | ntdll | impl | base/process/process_iterator_win.cc:39 | `return !_wcsicmp(executable_name_.c_str(), entry().exe_file()) &&` |
| `_wcsnicmp` | ntdll | impl | sandbox/win/src/filesystem_policy.cc:94 | `if (_wcsnicmp(mod_name.c_str(), kNTDevicePrefix, kNTDevicePrefixLen)) {` |
| `eglGetDisplay` |  | not-an-export | ui/gl/gl_bindings_autogen_egl.cc:1047 | EGL display for the ANGLE/libEGL path (uses DXGI under the hood) |
| `glBindTexture` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:6259 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glBindTexture")` |
| `glBlendFunc` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:6313 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glBlendFunc")` |
| `glClear` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:6363 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glClear")` |
| `glClearColor` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:6400 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glClearColor")` |
| `glClearDepth` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:6405 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glClearDepth")` |
| `glClearStencil` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:6415 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glClearStencil")` |
| `glColorMask` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:6462 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glColorMask")` |
| `glCopyTexImage2D` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:6637 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glCopyTexImage2D")` |
| `glCopyTexSubImage2D` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:6650 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glCopyTexSubImage2D")` |
| `glCullFace` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:6751 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glCullFace")` |
| `glDeleteTextures` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:6855 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glDeleteTextures")` |
| `glDepthFunc` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:6870 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glDepthFunc")` |
| `glDepthMask` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:6875 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glDepthMask")` |
| `glDepthRange` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:6880 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glDepthRange")` |
| `glDisable` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:6895 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glDisable")` |
| `glDrawArrays` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:6929 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glDrawArrays")` |
| `glDrawBuffer` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:6958 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glDrawBuffer")` |
| `glDrawElements` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:6971 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glDrawElements")` |
| `glEnable` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:7032 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glEnable")` |
| `glFinish` | opengl32 | impl | gpu/ipc/service/gpu_channel_manager.cc:354 | `glFinish();` |
| `glFlush` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:7082 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glFlush")` |
| `glFrontFace` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:7155 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glFrontFace")` |
| `glGenTextures` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:7215 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glGenTextures")` |
| `glGetBooleanv` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:7326 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glGetBooleanv")` |
| `glGetError` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:7392 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glGetError")` |
| `glGetFloatv` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:7402 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glGetFloatv")` |
| `glGetIntegerv` | opengl32 | impl | gpu/config/gpu_info_collector.cc:235 | `glGetIntegerv(GL_MAX_SAMPLES, &max_samples);` |
| `glGetPointerv` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:7629 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glGetPointerv")` |
| `glGetString` | opengl32 | impl | gpu/config/gpu_info_collector.cc:88 | `reinterpret_cast<const char*>(glGetString(pname));` |
| `glGetTexLevelParameterfv` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:7971 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glGetTexLevelParameterfv")` |
| `glGetTexLevelParameteriv` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:7991 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glGetTexLevelParameteriv")` |
| `glGetTexParameterfv` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:8010 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glGetTexParameterfv")` |
| `glGetTexParameteriv` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:8050 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glGetTexParameteriv")` |
| `glHint` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:8235 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glHint")` |
| `glIsEnabled` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:8289 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glIsEnabled")` |
| `glIsTexture` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:8354 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glIsTexture")` |
| `glLineWidth` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:8369 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glLineWidth")` |
| `glPixelStorei` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:8543 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glPixelStorei")` |
| `glPolygonMode` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:8553 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glPolygonMode")` |
| `glPolygonOffset` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:8558 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glPolygonOffset")` |
| `glReadBuffer` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:8916 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glReadBuffer")` |
| `glReadPixels` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:8943 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glReadPixels")` |
| `glScissor` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:9096 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glScissor")` |
| `glStencilFunc` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:9171 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glStencilFunc")` |
| `glStencilMask` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:9184 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glStencilMask")` |
| `glStencilOp` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:9194 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glStencilOp")` |
| `glTexImage2D` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:9316 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glTexImage2D")` |
| `glTexParameterf` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:9383 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glTexParameterf")` |
| `glTexParameterfv` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:9390 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glTexParameterfv")` |
| `glTexParameteri` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:9404 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glTexParameteri")` |
| `glTexParameteriv` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:9429 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glTexParameteriv")` |
| `glTexSubImage2D` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:9494 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glTexSubImage2D")` |
| `glViewport` | opengl32 | impl | ui/gl/gl_bindings_autogen_gl.cc:9947 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceGLAPI::glViewport")` |
| `lstrcmpiA` | kernel32 | forward | base/win/iat_patch_function.cc:58 | `if (name && (0 == lstrcmpiA(name, intercept_information->function_name))) {` |
| `lstrlen` | kernel32 | forward | base/win/win_util.cc:456 | `DCHECK_LT(lstrlen(app_id), 64);` |
| `lstrlenW` | kernel32 | forward | sandbox/win/src/policy_engine_opcodes.cc:235 | `int length = lstrlenW(match_str);` |
| `timeBeginPeriod` | kernel32 | impl | base/time/time_win.cc:226 | `timeBeginPeriod(MinTimerIntervalHighResMs());` |
| `timeEndPeriod` | kernel32 | impl | base/time/time_win.cc:225 | `timeEndPeriod(MinTimerIntervalLowResMs());` |
| `timeGetTime` | kernel32 | impl | base/time/time_win.cc:386 | winmm fallback clock |
| `vkCreateInstance` | vulkan-1 | forward | gpu/config/gpu_info_collector_win.cc:248 | `PFN_vkCreateInstance* vkCreateInstance) {` |
| `vkDestroyInstance` | vulkan-1 | forward | gpu/config/gpu_info_collector_win.cc:273 | `PFN_vkDestroyInstance* vkDestroyInstance,` |
| `vkEnumerateDeviceExtensionProperties` | vulkan-1 | forward | gpu/config/gpu_info_collector_win.cc:276 | `vkEnumerateDeviceExtensionProperties) {` |
| `vkEnumeratePhysicalDevices` | vulkan-1 | forward | gpu/config/gpu_info_collector_win.cc:274 | `PFN_vkEnumeratePhysicalDevices* vkEnumeratePhysicalDevices,` |
| `vkGetInstanceProcAddr` | vulkan-1 | forward | gpu/config/gpu_info_collector_win.cc:247 | `PFN_vkGetInstanceProcAddr* vkGetInstanceProcAddr,` |
| `wglCopyContext` | opengl32 | impl | ui/gl/gl_bindings_autogen_wgl.cc:227 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceWGLAPI::wglCopyContext")` |
| `wglCreateContext` | opengl32 | impl | ui/gl/gl_bindings_autogen_wgl.cc:232 | WGL context creation for the desktop-GL path |
| `wglCreateLayerContext` | opengl32 | impl | ui/gl/gl_bindings_autogen_wgl.cc:245 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceWGLAPI::wglCreateLayerContext")` |
| `wglDeleteContext` | opengl32 | impl | ui/gl/gl_bindings_autogen_wgl.cc:260 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceWGLAPI::wglDeleteContext")` |
| `wglGetCurrentContext` | opengl32 | impl | ui/gl/gl_bindings_autogen_wgl.cc:270 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceWGLAPI::wglGetCurrentContext")` |
| `wglGetCurrentDC` | opengl32 | impl | ui/gl/gl_bindings_autogen_wgl.cc:275 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceWGLAPI::wglGetCurrentDC")` |
| `wglGetProcAddress` | opengl32 | impl | ui/gl/init/gl_initializer_win.cc:129 | resolve GL entry points |
| `wglMakeCurrent` | opengl32 | impl | ui/gl/gl_bindings_autogen_wgl.cc:295 | bind GL context; FALSE => Qt disables the GL path |
| `wglShareLists` | opengl32 | impl | ui/gl/gl_bindings_autogen_wgl.cc:312 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceWGLAPI::wglShareLists")` |
| `wglSwapLayerBuffers` | opengl32 | impl | ui/gl/gl_bindings_autogen_wgl.cc:322 | `TRACE_EVENT_BINARY_EFFICIENT0("gpu", "TraceWGLAPI::wglSwapLayerBuffers")` |
<!--E:CHROMIUM_TABLE-->
### 4.3 Wine status of the Chromium surface

<!--B:CHROMIUM_FLAGGED-->
562 APIs indexed from 203 Chromium files at tag 80.0.3987.163; status counts: 5 absent, 246 forward, 308 impl, 3 not-an-export. The rows below are the ones that need Wine work (missing exports and FIXME-only bodies); everything else resolves to an implemented or forwarded Wine export.

| API | Wine status | Evidence | Chromium call site |
|---|---|---|---|
| `AllowSetForegroundWindow` | body stub (no-op, acceptable) | `dlls/user32/win.c:779 return TRUE;` | base/process/launch_win.cc:351 |
| `CreateAppContainerProfile` | body stub | `dlls/userenv/userenv_main.c:690 FIXME("(%s, %s, %s, %p, %ld, %p): stub\n", debugstr_w(container_name), debugstr_w(display_name), debugstr_w(de` | sandbox/win/src/app_container_profile_base.cc:21 |
| `DeleteAppContainerProfile` | absent | `no export` | sandbox/win/src/app_container_profile_base.cc:26 |
| `DeriveAppContainerSidFromAppContainerName` | absent | `no export` | sandbox/win/src/app_container_profile_base.cc:23 |
| `GdiDllInitialize` | body stub (no-op, acceptable) | `dlls/gdi32/objects.c:1092 FIXME( "stub\n" ); return TRUE;` | sandbox/win/src/process_mitigations_win32k_dispatcher.cc:146 |
| `GetAppContainerFolderPath` | absent | `no export` | sandbox/win/src/app_container_profile_base.cc:28 |
| `GetAppContainerRegistryLocation` | absent | `no export` | sandbox/win/src/app_container_profile_base.cc:31 |
| `GetColorSpace` | body stub | `dlls/gdi32/objects.c:730 FIXME( "stub\n" ); return 0;` | ui/gl/gl_surface_egl.cc:1224 |
| `GetThreadInformation` | absent | `no export` | base/threading/platform_thread_win.cc:197 |
| `ProcessTrace` | body stub | `dlls/sechost/trace.c:134 FIXME("%p %lu %p %p: stub\n", handles, count, start_time, end_time); return ERROR_CALL_NOT_IMPLEMENTED;` | base/win/event_trace_consumer.h:126 |
| `UserHandleGrantAccess` | body stub | `dlls/user32/misc.c:401 FIXME("(%p,%p,%d): stub\n", handle, job, grant); return TRUE;` | sandbox/win/src/job.cc:91 |
<!--E:CHROMIUM_FLAGGED-->
### 4.4 Reading Chromium's GPU/WebEngine traces

* **Process model.** `QtWebEngineProcess.exe` is the Chromium child-process
  binary; it hosts the renderer, GPU, utility and network processes. The browser
  process is `Qt5WebEngineCore.dll` inside the app. A trace showing
  `CreateProcessW`/`CreateProcessAsUserW` + job-object calls for that binary is
  the normal launch path (`base/process/launch_win.cc`,
  `sandbox/win/src/target_process.cc`).
* **Sandbox.** Chromium's Windows sandbox creates a restricted token, an
  alternate window station/desktop and (optionally) an AppContainer, then
  configures mitigations (`SetProcessMitigationPolicy`) and starts the child
  suspended so the policy can be applied. `sandbox/win/src/` is the place to
  read. Note that in Wine the alternate-desktop/AppContainer path is where
  failures cluster; `CreateAppContainerProfile` is currently a **FIXME body stub
  in `dlls/userenv/userenv_main.c:690`** (see §4.3), so a trace with AppContainer
  enabled will fail there.
* **GPU process.** It collects adapter info from DXGI, then creates
  D3D11/ANGLE devices and talks to `d3dcompiler_47.dll` for shader compilation.
  `gpu/ipc/service/` + `ui/gfx/win/direct_write.cc` + `ui/gl/` are the sources.
  In this install the ANGLE DLLs appear to be absent, so expect the GPU process
  to fall back to software (see §1.1).
* **Network.** `net/base/network_change_notifier_win.cc` uses
  `NotifyAddrChange` (Wine: implemented via NSI); `net/proxy_resolution/`
  contains the `WinHttp*` proxy resolver, which is only used when the proxy
  configuration says so.
* **IPC.** Mojo channels on Windows are named pipes + shared memory
  (`CreateNamedPipeW`, `DuplicateHandle`, `CreateFileMappingW`, overlapped
  `ReadFile`/`WriteFile`, `CreateIoCompletionPort`, `GetQueuedCompletionStatus`)
  — all implemented in Wine.

---

## 5. When a trace shows a call failing

Workflow, in order:

1. **Find the caller.** Look the API up in the appendix (§2.5, or grep
   `docs/_qt_win32_index.json` / `docs/_chromium_win32_index.json`). You get
   `file:line` in Qt or Chromium.
   * Qt file → `/run/media/asdf/Windows/qt-src/qtbase/<file>`.
   * Chromium file → `/run/media/asdf/Windows/chromium-src/<file>` (fetch it with
     §4.1 if missing).
2. **Read what the caller expects.** Every Win32 call in Qt is followed by
   `GetLastError()` on failure (`qSystemError`, `qt_winerror`, `WIN_ERROR`), which
   determines whether the failure is fatal, retried, or ignored. Chromium uses
   `base::win::ScopedHandle` + `DPCHECK`/`CHECK` and `RecordFailure` — a failing
   call there is usually fatal for the child process.
3. **Classify with the Wine cross-check.**
   * `@ stub` in a `.spec` / absent → Wine has no export; expect
     `GetProcAddress == NULL` or an unresolved import. Candidate patch.
   * present but body is `FIXME(...); return X;` → Wine returns *something*
     plausible, so the trace will look "successful" while the behaviour is
     missing. This is the `NotifyIpInterfaceChange` class — check
     `docs/_wine_impl_audit_all.tsv` (§3.2).
   * implemented/forwarded → the failure is call-argument or state specific;
     read the Wine implementation at the recorded `.spec` DLL.
4. **Check the expected-value contract** in the table below before concluding.

### 5.1 Playbook by symptom

| Symptom in the trace | Read this | Expected behaviour / return |
|---|---|---|
| `CreateWindowExW` → NULL | `qwindowscontext.cpp` (`QWindowsContext::createWindow`), `qwindowswindow.cpp:809` | NULL is fatal for that window; Qt logs with `GetLastError` (`qSystemError`). Class registration must have happened first (`RegisterClassEx` `qwindowscontext.cpp:673`). |
| `RegisterClassExW` → 0, `ERROR_CLASS_ALREADY_EXISTS` | `qwindowscontext.cpp` | Qt treats "already exists" as success (shared class name). Other errors abort the plugin. |
| `GetDeviceCaps(LOGPIXELSX)` odd values | `qwindowsscreen.cpp`, `qwindowsscreen.cpp` DPI helpers | Qt derives screen DPI; per-monitor DPI comes from `GetDpiForMonitor` (shcore) with this as fallback. |
| `SetProcessDpiAwareness`/`SetProcessDPIAware` → FALSE | `qwindowscontext.cpp:193,237` | Often benign: awareness may already be set by the manifest. Qt only warns. |
| `LoadLibraryW("opengl32.dll")` → NULL | `qwindowsglcontext.cpp`, `qwindowseglcontext.cpp` | Qt disables the GL path (`QWindowsOpenGLTester`); Quick falls back to software. Check `wglGetProcAddress` next. |
| `D3D11CreateDevice` → failure HRESULT | ANGLE `Renderer11.cpp`, `qwindowsopengltester.cpp` | ANGLE falls back D3D11 → D3D9 → WARP; a failing HRESULT here means no GPU rasterisation. |
| `DWriteCreateFactory` → NULL | `qwindowsfontdatabase.cpp:81,104` | Qt falls back to the GDI font engine; text still renders. |
| `AddFontMemResourceEx` → NULL | `qwindowsfontdatabase.cpp:1314` | Application font install fails; Qt removes it from the font database. |
| `DoDragDrop` / `RegisterDragDrop` → failure | `qwindowsdrag.cpp:700`, `qwindowswindow.cpp:1488` | `RegisterDragDrop` must succeed when a window is created; `DoDragDrop` returning non-`DRAGDROP_S_*` means the drag was cancelled. |
| `OleGetClipboard` / `OleSetClipboard` → failure | `qwindowsclipboard.cpp` (OLE path) | Qt's Windows clipboard is **OLE-based**, not `OpenClipboard` — a trace lacking `OpenClipboard` is normal. |
| `Shell_NotifyIcon` → FALSE | `qwindowssystemtrayicon.cpp:295-377` | `NIM_ADD` FALSE aborts tray creation; `NIM_SETVERSION` returning FALSE is tolerated. |
| `Shell_NotifyIconGetRect` → `E_NOTIMPL` | `qwindowssystemtrayicon.cpp:51,244` | Wine stub; tray menu placement falls back. |
| `GetAdaptersAddresses` → `ERROR_BUFFER_OVERFLOW` | `qnetworkinterface_win.cpp:122` | **Normal**: Qt re-allocates with the returned size and retries. `ERROR_NO_DATA` means no adapters. |
| `NotifyIpInterfaceChange` registered but no callbacks | Wine `iphlpapi_main.c:4356` + `patches/local/0102-*` | Wine must invoke the callback on interface changes; pre-patch it did not. |
| `NotifyAddrChange` → non-zero | `net/base/network_change_notifier_win.cc:293` (Chromium) | Chromium retries after `kNotifyAddrChangeErrorDelayMs`; Wine implements it via NSI. |
| Socket call → `SOCKET_ERROR`/`WSAEWOULDBLOCK` | `qnativesocketengine_win.cpp` | **Normal** on non-blocking sockets; Qt waits via the dispatcher. Only other `WSAE*` codes are errors. |
| `ReadFile` on a pipe → FALSE + `ERROR_BROKEN_PIPE`/`ERROR_NO_DATA` | `qwindowspipereader.cpp`, `qprocess_win.cpp` | Qt treats these as EOF/success, not failure. |
| `ConnectNamedPipe` → FALSE + `ERROR_PIPE_CONNECTED` | `qlocalserver_win.cpp` | Treated as success (a client was already waiting). |
| `MsgWaitForMultipleObjectsEx` → `WAIT_FAILED` | `qeventdispatcher_win.cpp:573` | Fatal for the dispatcher loop; check the event handles created by `CreateEventW`. |
| `RegOpenKeyExW` → `ERROR_FILE_NOT_FOUND` | `qsettings_win.cpp` | Normal for a missing value; Qt supplies defaults. |
| `AcquireCredentialsHandleW`/`InitializeSecurityContextW` → `SEC_E_*` | `qsslsocket_schannel.cpp`, `qauthenticator.cpp` | `SEC_I_CONTINUE_NEEDED`/`SEC_E_INCOMPLETE_MESSAGE` are normal handshake states; `SEC_E_NO_CREDENTIALS` is a real failure. |
| `CertFindChainInStore` → NULL | `qsslsocket_schannel.cpp:661` | Wine stub; TLS chain building can fail. |
| `SetProcessMitigationPolicy` → failure | `sandbox/win/src/process_mitigations.cc` (Chromium) | Chromium downgrades or fails the sandbox init; check the requested mitigation. |
| `CreateAppContainerProfile` → failure | Chromium `sandbox/win/src/app_container_profile_base.cc:87` | Wine stub returning `E_NOTIMPL` (`userenv_main.c:690`); Chromium returns `nullptr` and the AppContainer sandbox degrades to the restricted-token path. |
| `GetProcAddress(userenv, "DeriveAppContainerSidFromAppContainerName"\|"DeleteAppContainerProfile"\|"GetAppContainerFolderPath"\|"GetAppContainerRegistryLocation")` → NULL | same file, lines 108-177 | No Wine export; handled (`if (!fn) return nullptr/false`). Candidate patch. |
| `GetThreadInformation` → NULL | `base/threading/platform_thread_win.cc:197` | Only called under `DCHECK_IS_ON()`; release builds ignore it (`if (!fn) return`). Cosmetic in a release build. |
| `UserHandleGrantAccess` → TRUE but no effect | Chromium `sandbox/win/src/` job-object setup | Wine stub; the grant never happens, so the sandboxed job cannot use the user handle. |
| `CreateWindowStation`/`CreateDesktop` failures | `qwindowscontext.cpp` (Qt), `sandbox/win/src/` (Chromium) | Qt only uses them in service/session scenarios; Chromium's sandbox requires the alternate desktop — a failure there blocks the child process. |
| `Uia*` events do nothing | `qwindowsuiawrapper.cpp:52-57`, Wine `uia_main.c` | Qt registers the bridge; Wine stubs the event raises, so accessibility clients see nothing. |

### 5.2 Reconstructing a trace symbol → source in one command

```bash
# Qt (case-sensitive exact API name)
python3 - <<'EOF'
import json; d=json.load(open('docs/_qt_win32_index.json'))
for s in d['CreateWindowExW']['qt_sites'][:3]: print(s['file'], s['line'], s['text'])
EOF
```

```bash
# Chromium: fetch the file the index points at, then read the line
python3 - <<'EOF'
import json; d=json.load(open('docs/_chromium_win32_index.json'))
for s in d['CreateProcessAsUserW']['sites'][:3]: print(s['file'], s['line'])
EOF
sed -n '120,140p' /run/media/asdf/Windows/chromium-src/sandbox/win/src/target_process.cc
```

---

## 6. What is *not* in this index

* **The app's own Win32 calls** (`*.exe` under the HogPC directory) — not open
  source. The index tells you which *library* call a trace entry belongs to;
  remaining calls are the app's or a third-party DLL's.
* **Qt modules outside qtbase**: `Qt5Multimedia` (FFmpeg `av*.dll` shipped in the
  app dir), `Qt5Pdf`, `Qt5Positioning`, `Qt5WebSockets`, `Qt5XmlPatterns`. Their
  Windows surface is mostly QtCore/QtGui, already indexed; vendor FFmpeg code is
  not.
* **Chromium files not fetched.** §4.1 is the recipe; §4.2 lists what was
  fetched. If a trace points at another file, fetch it with the same command.
* **Wine `win32u` internals.** `user32` forwards a lot to `win32u`; this index
  records the forward and the `win32u` export, not the NT-user implementation.

---

## 7. Regenerating

```bash
cd /home/asdf/projects/hog-wine

# 1. Qt source (already extracted, ~303 MiB)
ls /run/media/asdf/Windows/qt-src/qtbase/.qmake.conf   # MODULE_VERSION = 5.15.1

# 2. Qt index + Wine .spec cross-check
python3 tools/qt_win32_index.py \
    --out-json docs/_qt_win32_index.json \
    --out-md   docs/_qt_win32_table.md \
    --dump-stubs docs/_qt_win32_stubs.tsv

# 3. Chromium surface (cached; re-runs only fetch what is missing)
python3 tools/chromium_win32_index.py \
    --out-json docs/_chromium_win32_index.json \
    --out-md   docs/_chromium_win32_table.md

# 4. Wine body-level (FIXME) stub audit over the union of both API lists
python3 -c "import json;\
a=json.load(open('docs/_qt_win32_index.json'));\
b=json.load(open('docs/_chromium_win32_index.json'));\
open('/tmp/all_apis.txt','w').write('\n'.join(sorted(set(a)|set(b)))+'\n')"
python3 tools/wine_impl_audit.py --api-list /tmp/all_apis.txt \
    --out docs/_wine_impl_audit_all.tsv

# 5. Inline the generated tables into this document
python3 tools/assemble_doc.py
```

Tooling lives in `tools/`; the generated tables it produces are kept in
`docs/_*.md|json|tsv` (they are what `assemble_doc.py` reads). The generated
regions of this file are delimited by `<!--B:NAME-->` … `<!--E:NAME-->` HTML
comments (invisible when rendered); `tools/assemble_doc.py` rewrites the text
between those markers in place, so step 5 is idempotent and prose edits are safe.
Step 3 is cached: it re-fetches only files that are missing from
`/run/media/asdf/Windows/chromium-src/`, and `--paths-file` lets you reuse a
pre-computed file list (`chromium-src/_paths.txt`) instead of re-listing the
throttled directories.

