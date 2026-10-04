#!/usr/bin/env python3
"""Build the Qt5 -> Win32 call index used by docs/QT_CHROMIUM_SOURCE.md.

Inputs
  --qt-root      extracted qtbase 5.15.1 source root
  --wine-root    Wine source root (used for dlls/*/*.spec)
  --winapi-root  extracted winapi-rs crate root (src/um, src/shared: authoritative
                 Win32 name list, incl. APIs Wine may not implement)

Outputs
  --out-json     machine-readable index (api -> wine status + Qt call sites)
  --out-md       markdown appendix table

The scanner tokenises Qt sources and intersects the identifiers with the union of
(Wine .spec symbol names) and (winapi-rs canonical declarations), so APIs that Wine
does not export at all are still reported.
"""

import argparse
import json
import os
import re
import sys

# ---------------------------------------------------------------------------
# Scope: files/dirs of qtbase that the Hog PC Qt 5.15.1 build exercises on Windows.
# Paths are relative to the qtbase root.  Entries ending in "/" are recursive.
SCOPE = [
    # qwindows platform plugin: window creation, DPI, GL/EGL/Vulkan, fonts hooks,
    # drag&drop, mime, clipboard, session management, system tray, input, themes.
    "src/plugins/platforms/windows/",
    # Windows font database + DirectWrite engine (moved out of src/gui/painting in Qt5).
    "src/platformsupport/fontdatabases/windows/",
    # UI Automation accessibility bridge.
    "src/platformsupport/windowsuiautomation/",
    # Also the shared accessibility input context used by the plugin.
    "src/plugins/platforms/windows/uiautomation/",
    # corelib Windows back-ends.
    "src/corelib/kernel/qeventdispatcher_win.cpp",
    "src/corelib/kernel/qcoreapplication_win.cpp",
    "src/corelib/kernel/qsystemsemaphore_win.cpp",
    "src/corelib/kernel/qsharedmemory_win.cpp",
    "src/corelib/kernel/qwineventnotifier.cpp",
    "src/corelib/kernel/qwinregistry.cpp",
    "src/corelib/kernel/qelapsedtimer_win.cpp",
    "src/corelib/plugin/qlibrary_win.cpp",
    "src/corelib/io/qfilesystemengine_win.cpp",
    "src/corelib/io/qfilesystemiterator_win.cpp",
    "src/corelib/io/qfilesystemwatcher_win.cpp",
    "src/corelib/io/qfsfileengine_win.cpp",
    "src/corelib/io/qsettings_win.cpp",
    "src/corelib/io/qstandardpaths_win.cpp",
    "src/corelib/io/qstorageinfo_win.cpp",
    "src/corelib/io/qwindowspipereader.cpp",
    "src/corelib/io/qwindowspipewriter.cpp",
    "src/corelib/io/qprocess_win.cpp",
    "src/corelib/io/qlockfile_win.cpp",
    "src/corelib/thread/qthread_win.cpp",
    "src/corelib/thread/qmutex_win.cpp",
    "src/corelib/thread/qwaitcondition_win.cpp",
    "src/corelib/text/qcollator_win.cpp",
    "src/corelib/text/qlocale_win.cpp",
    "src/corelib/global/qoperatingsystemversion_win.cpp",
    "src/corelib/codecs/qwindowscodec.cpp",
    "src/corelib/time/qtimezoneprivate_win.cpp",
    # gui: QGuiApplication entry points and win pixmap handling.
    "src/gui/kernel/qguiapplication.cpp",
    "src/gui/kernel/qwindowsysteminterface.cpp",
    "src/gui/image/qpixmap_win.cpp",
    "src/gui/painting/",
    # Qt 5.15 RHI (D3D11 backend for Qt Quick) and the Vulkan wrapper.
    "src/gui/rhi/",
    "src/gui/vulkan/",
    # network: native socket engine, interfaces, DNS, proxy, SSL/Schannel, DTLS.
    "src/network/",
    # bundled ANGLE: Qt's official Windows build ships libEGL/libGLESv2 (D3D11).
    "src/3rdparty/angle/src/common/system_utils_win.cpp",
    "src/3rdparty/angle/src/gpu_info_util/SystemInfo_win.cpp",
    "src/3rdparty/angle/src/libANGLE/renderer/d3d/",
    "src/3rdparty/angle/src/libANGLE/renderer/gl/wgl/",
    "src/3rdparty/angle/src/libGLESv2/",
    "src/3rdparty/angle/src/libEGL/",
    # sql drivers shipped with qtbase.
    "src/plugins/sqldrivers/",
]

# winapi-rs module -> real DLL (only needed for presentation; Wine specs are
# authoritative for implementation status).
MODULE_DLL = {
    "winbase": "kernel32", "winuser": "user32", "wingdi": "gdi32",
    "winnls": "kernel32", "winreg": "advapi32", "errhandlingapi": "kernel32",
    "fileapi": "kernel32", "handleapi": "kernel32", "heapapi": "kernel32",
    "ioapiset": "kernel32", "jobapi": "kernel32", "jobapi2": "kernel32",
    "libloaderapi": "kernel32", "memoryapi": "kernel32", "namedpipeapi": "kernel32",
    "namespaceapi": "kernel32", "processenv": "kernel32",
    "processthreadsapi": "kernel32", "processtopologyapi": "kernel32",
    "profileapi": "kernel32", "realtimeapiset": "kernel32",
    "securitybaseapi": "advapi32", "synchapi": "kernel32", "sysinfoapi": "kernel32",
    "systemtopologyapi": "kernel32", "threadpoolapiset": "kernel32",
    "threadpoollegacyapiset": "kernel32", "timezoneapi": "kernel32",
    "utilapiset": "kernel32", "wow64apiset": "kernel32", "fibersapi": "kernel32",
    "interlockedapi": "kernel32", "consoleapi": "kernel32", "debugapi": "kernel32",
    "tlhelp32": "kernel32", "securityappcontainer": "kernel32",
    "dde": "user32", "dbt": "user32", "wincon": "kernel32",
    "objbase": "ole32", "ole2": "ole32", "combaseapi": "ole32",
    "objidl": "ole32", "objidlbase": "ole32", "oaidl": "oleaut32",
    "oleauto": "oleaut32", "oleidl": "ole32", "unknwnbase": "ole32",
    "shellapi": "shell32", "shlobj": "shell32", "shobjidl_core": "shell32",
    "shobjidl": "shell32", "shtypes": "shell32",
    "commdlg": "comdlg32", "prsht": "comctl32", "commctrl": "comctl32",
    "mmeapi": "winmm", "mmsystem": "winmm", "playsoundapi": "winmm",
    "wincrypt": "crypt32", "mincrypt": "crypt32", "mscat": "wintrust",
    "schannel": "secur32", "sspi": "secur32", "subauth": "advapi32",
    "urlmon": "urlmon", "mswsock": "mswsock", "winsock2": "ws2_32",
    "ws2tcpip": "ws2_32", "ws2spi": "ws2_32", "ws2bth": "ws2_32",
    "winhttp": "winhttp", "wininet": "wininet", "winineti": "wininet",
    "winnetwk": "mpr", "shellscalingapi": "shcore", "uxtheme": "uxtheme",
    "dwmapi": "dwmapi", "setupapi": "setupapi", "cfgmgr32": "cfgmgr32",
    "psapi": "psapi", "winsvc": "advapi32", "winsafer": "advapi32",
    "wintrust": "wintrust", "wintrust": "wintrust", "propsys": "propsys",
    "dwrite": "dwrite", "dwrite_1": "dwrite", "dwrite_2": "dwrite",
    "dwrite_3": "dwrite", "d2d1": "d2d1", "d2d1_1": "d2d1",
    "d3d11": "d3d11", "d3d11_1": "d3d11", "d3d11_2": "d3d11",
    "d3d11_3": "d3d11", "d3d11_4": "d3d11", "d3d10": "d3d10",
    "d3d10_1": "d3d10_1", "d3d9": "d3d9", "d3d12": "d3d12",
    "d3dcompiler": "d3dcompiler_47", "dxgi": "dxgi", "dxgidebug": "dxgidebug",
    "gl": "opengl32", "bcrypt": "bcrypt", "ncrypt": "ncrypt",
    "iphlpapi": "iphlpapi", "netioapi": "iphlpapi", "ipmib": "iphlpapi",
    "iptypes": "iphlpapi", "windns": "dnsapi", "wtsapi32": "wtsapi32",
    "userenv": "userenv", "avrt": "avrt", "powerbase": "powrprof",
    "powersetting": "powrprof", "powrprof": "powrprof", "pdh": "pdh",
    "restartmanager": "rstrtmgr", "usp10": "usp10", "wincodec": "windowscodecs",
    "shcore": "shcore", "sporder": "ws2_32", "winscard": "winscard",
}
DLL_MODULE = {}
for _m, _d in MODULE_DLL.items():
    DLL_MODULE.setdefault(_d, _m)

# Curated expectations for the APIs that matter most for the Hog PC trace loop.
# The machine-generated appendix carries the raw call site for everything else.
EXPECT = {
    "CreateWindowExW": "create the native HWND; NULL => Qt aborts platform window creation (check class registration, DPI awareness, window station)",
    "RegisterClassExW": "register the Qt window class (QT_WINDOW_CLASS_NAME / Qt6Build...); 0 with ERROR_CLASS_ALREADY_EXISTS is tolerated by Qt",
    "DestroyWindow": "must succeed; failure is logged and leaked HWNDs accumulate",
    "DefWindowProcW": "default handling of unhandled window messages; Qt relies on it for non-Qt classes",
    "GetWindowLongPtrW": "read GWLP_USERDATA / window style; Qt uses it to recover the QWindowsWindow",
    "SetWindowLongPtrW": "install the Qt window proc and GWLP_USERDATA; 0 may mean previous value was 0 (check GetLastError)",
    "AdjustWindowRectEx": "convert client geometry to frame geometry; FALSE => geometry is wrong",
    "GetClientRect": "client area size for backing store sizing",
    "MonitorFromWindow": "find the monitor for DPI/screen association",
    "GetMonitorInfoW": "monitor work area / device name for QScreen",
    "EnumDisplayMonitors": "enumerate QScreens",
    "EnumDisplaySettingsW": "probe display modes / refresh rate",
    "GetDeviceCaps": "DPI (LOGPIXELSX/Y), bit depth, raster caps for the screen",
    "GetDpiForMonitor": "per-monitor DPI (shcore); HRESULT failure falls back to GetDeviceCaps",
    "GetDpiForWindow": "per-window DPI; Qt prefers this when available (Win10 1607+)",
    "SetProcessDpiAwareness": "Win8.1 process DPI awareness; failure => Qt falls back to SetProcessDPIAware",
    "SetProcessDPIAware": "Vista DPI awareness fallback; FALSE if already set is benign",
    "SetProcessDpiAwarenessContext": "Win10 1703 per-monitor-v2 awareness; Qt selects the best available level",
    "CreateDCW": "screen/display DC for GDI painting and font metrics",
    "GetDC": "screen DC; NULL => GDI path unusable",
    "ReleaseDC": "balance GetDC; failure leaks DCs",
    "GetGlyphOutlineW": "font rasterisation for the GDI font engine; GDI_ERROR => Qt falls back",
    "GetTextMetricsW": "font ascent/descent/avg width",
    "EnumFontFamiliesExW": "enumerate installed families for QFontDatabase",
    "GetStockObject": "default pens/brushes/fonts used by the GDI engine",
    "CreateCompatibleDC": "memory DC for backing store / pixmaps",
    "CreateCompatibleBitmap": "backing store bitmap",
    "BitBlt": "blit backing store to the window DC",
    "StretchBlt": "scaled blit for high-DPI/format conversion",
    "CreateDIBSection": "top-down DIB for QImage on Windows (shared pixel memory)",
    "GetDIBits": "read back GDI bitmap data into a QImage",
    "SetDIBitsToDevice": "raw blit path used by the raster backing store",
    "TrackMouseEvent": "hover/leave tracking for QCursor::setPos + enter/leave events",
    "SetCapture": "mouse capture during drag/resize; NULL => capture lost",
    "ReleaseCapture": "balance SetCapture",
    "GetKeyState": "modifier state (Shift/Ctrl/Alt) for key events",
    "MapVirtualKeyW": "translate VK codes to characters",
    "ToUnicodeEx": "keyboard layout translation via the Qt keyboard mapper",
    "GetKeyboardLayout": "active layout; Qt caches per-thread layouts",
    "GetKeyboardLayoutList": "enumerate layouts to detect layout switches",
    "RegisterTouchWindow": "enable WM_TOUCH; failure => Qt uses pointer/tablet path instead",
    "GetPointerInfo": "Win8 pointer input for touch/pen",
    "GetPointerTouchInfo": "touch/pen detail for QPointerEvent synthesis",
    "CreateFontIndirectW": "logical font creation in the GDI font engine",
    "AddFontMemResourceEx": "load embedded application fonts (QFontDatabase::addApplicationFont)",
    "RemoveFontMemResourceEx": "release AddFontMemResourceEx handles",
    "AddFontResourceExW": "install application fonts for the process",
    "RemoveFontResourceExW": "uninstall application fonts",
    "DWriteCreateFactory": "DirectWrite factory for the DirectWrite font engine (Qt uses it when DWrite is available)",
    "D3D11CreateDevice": "hardware rasterizer for Qt Quick via ANGLE; failure => Qt falls back to software GL (opengl32sw)",
    "CreateDXGIFactory1": "enumerate adapters for ANGLE/GL (and GPU blacklist checks)",
    "CreateDXGIFactory": "legacy DXGI factory path",
    "EnumAdapters": "adapter enumeration for qwindowsopengltester GPU detection",
    "GetDC": "screen DC used to query OPENGL caps",
    "wglCreateContext": "WGL context creation for the desktop-GL path",
    "wglMakeCurrent": "bind GL context; FALSE => Qt disables the GL path",
    "wglGetProcAddress": "resolve GL entry points",
    "ChoosePixelFormat": "select a pixel format for a window DC",
    "SetPixelFormat": "apply pixel format; FALSE => context creation fails",
    "DescribePixelFormat": "probe pixel format capabilities",
    "SwapBuffers": "present the GL frame",
    "eglGetDisplay": "EGL display for the ANGLE/libEGL path (uses DXGI under the hood)",
    "LoadLibraryW": "load opengl32.dll/angle/dll plugins; NULL => Qt reports 'failed to load'",
    "GetProcAddress": "resolve optional entry points; NULL => Qt uses a fallback implementation",
    "FreeLibrary": "unload a plugin DLL",
    "CreateEventW": "manual/auto-reset events for QEventDispatcherWin32's wakeup pipe and QThread",
    "CreateEventExW": "event with explicit access for the dispatcher",
    "SetEvent": "wake the event dispatcher / signal QWaitCondition",
    "ResetEvent": "re-arm auto-reset events",
    "WaitForSingleObject": "block the thread; WAIT_FAILED => Qt considers the wait broken",
    "WaitForMultipleObjects": "wait on the dispatcher event + message queue",
    "MsgWaitForMultipleObjectsEx": "the QEventDispatcherWin32 core wait (events + WM_* queue)",
    "PeekMessageW": "drain the thread message queue",
    "GetMessageW": "modal loop message pump",
    "DispatchMessageW": "deliver messages to the Qt window proc",
    "PostMessageW": "async cross-thread notification (0 => queue full / invalid hwnd)",
    "PostThreadMessageW": "wake the GUI thread from another thread",
    "SendMessageW": "synchronous cross-thread call; Qt uses it for WM_QT_* internal messages",
    "PostQuitMessage": "terminate the dispatcher loop",
    "CreateWindowStationW": "window station handling (Qt creates/opens for service sessions)",
    "OpenWindowStationW": "attach to an existing window station",
    "SetProcessWindowStation": "switch window station in QWindowsContext init",
    "GetProcessWindowStation": "query current station",
    "CreateDesktopW": "desktop creation for sandboxed/service sessions",
    "OpenInputDesktop": "attach to the interactive desktop",
    "CloseDesktop": "balance desktop handles",
    "GetThreadDesktop": "query thread desktop",
    "SetThreadDesktop": "assign thread desktop",
    "CreateProcessW": "QProcess start; FALSE => QProcess::FailedToStart with GetLastError",
    "CreateProcessAsUserW": "start a process in another session (used by session helpers)",
    "GetExitCodeProcess": "QProcess exit status",
    "TerminateProcess": "QProcess::kill",
    "OpenProcess": "query/terminate another process",
    "DuplicateHandle": "pass handles to child processes (QProcess pipe inheritance)",
    "CreatePipe": "QProcess stdin/stdout/stderr channels; NULL => QProcess fails",
    "SetHandleInformation": "make pipe handles inheritable/non-inheritable",
    "CreateFileW": "open files, pipes (\\\\.\\pipe\\...), devices (\\\\.\\DISPLAY1) and console handles; INVALID_HANDLE_VALUE => Qt error",
    "ReadFile": "read from pipe/file; FALSE+ERROR_BROKEN_PIPE => Qt treats as EOF (success)",
    "WriteFile": "write to pipe/file; FALSE+ERROR_NO_DATA => peer closed, Qt treats as EOF",
    "CancelIoEx": "abort overlapped I/O for QWindowsPipeReader",
    "GetOverlappedResult": "complete overlapped I/O for the pipe reader",
    "CreateNamedPipeW": "QProcess/QLocalServer named pipes",
    "ConnectNamedPipe": "accept a local socket connection; ERROR_PIPE_CONNECTED is success",
    "WaitNamedPipeW": "timeout on connecting to a local server",
    "PeekNamedPipe": "non-blocking pipe read availability",
    "SetNamedPipeHandleState": "switch a pipe to message/byte mode",
    "GetFileInformationByHandle": "QFileInfo identity (volume serial + file index) for QFileSystemEngine",
    "GetFileAttributesExW": "QFileInfo attributes; FALSE => does not exist",
    "GetFileAttributesW": "attributes/type (directory, reparse point, symlink)",
    "FindFirstFileExW": "directory enumeration for QDirIterator/QFileSystemWatcher",
    "FindNextFileW": "continue FindFirstFileExW enumeration",
    "FindClose": "close enumeration handle",
    "ReadDirectoryChangesW": "QFileSystemWatcher change notifications (overlapped)",
    "GetVolumeInformationW": "QStorageInfo volume label/fs; FALSE => invalid drive",
    "GetDiskFreeSpaceExW": "QStorageInfo bytes available",
    "SetFilePointerEx": "64-bit seek on QFile",
    "SetEndOfFile": "truncate QFile",
    "FlushFileBuffers": "QFile::flush",
    "DeleteFileW": "QFile::remove",
    "MoveFileExW": "rename/replace, MOVEFILE_REPLACE_EXISTING",
    "CreateDirectoryW": "QDir::mkdir; ERROR_ALREADY_EXISTS is mapped to success by Qt",
    "RemoveDirectoryW": "QDir::rmdir",
    "GetTempPathW": "QDir::tempPath",
    "GetModuleFileNameW": "locate the executable / plugin dirs (qApp->applicationDirPath)",
    "GetModuleHandleW": "base address / module presence (GetModuleHandleExW for pinning)",
    "GetModuleHandleExW": "pin a DLL while resolving symbols",
    "GetSystemInfo": "page size, processor count, architecture (QSettings/Random)",
    "GetNativeSystemInfo": "architecture under WOW64 (32-bit app on 64-bit Windows)",
    "GlobalMemoryStatusEx": "QStorageInfo/QSysInfo memory",
    "QueryPerformanceCounter": "QElapsedTimer high-resolution clock",
    "QueryPerformanceFrequency": "QElapsedTimer tick frequency",
    "GetTickCount": "coarse QElapsedTimer fallback",
    "GetTickCount64": "monotonic QDeadlineTimer base",
    "timeGetTime": "winmm fallback clock",
    "GetSystemTimeAsFileTime": "QDateTime current time; also the dispatcher's timeout base",
    "GetLocalTime": "QDateTime local time",
    "GetTimeZoneInformation": "QTimeZone Windows backend",
    "RegOpenKeyExW": "QSettings registry backend",
    "RegQueryValueExW": "QSettings value read",
    "RegSetValueExW": "QSettings value write",
    "RegCreateKeyExW": "QSettings key creation",
    "RegDeleteKeyW": "QSettings remove",
    "RegEnumKeyExW": "QSettings child groups",
    "RegCloseKey": "balance registry handles",
    "RegGetValueW": "typed registry read",
    "RegQueryInfoKeyW": "QSettings key metadata",
    "InitializeCriticalSection": "QMutex/global locks on Windows",
    "EnterCriticalSection": "QMutex lock",
    "LeaveCriticalSection": "QMutex unlock",
    "DeleteCriticalSection": "QMutex teardown",
    "SleepConditionVariableCS": "QWaitCondition on Vista+ (Qt prefers this over events)",
    "WakeAllConditionVariable": "QWaitCondition::wakeAll",
    "WakeConditionVariable": "QWaitCondition::wakeOne",
    "CreateSemaphoreW": "QSystemSemaphore",
    "ReleaseSemaphore": "QSystemSemaphore::release; FALSE => Qt reports out of range",
    "WaitForSingleObject": "QSystemSemaphore::acquire",
    "CreateMutexW": "QSystemSemaphore/QSingleApplication; ERROR_ALREADY_EXISTS signals an existing instance",
    "OpenMutexW": "open an existing semaphore/mutex by name",
    "GetLastError": "every failing Win32 call is decoded through this by Qt's qt_winerror/qSystemError",
    "FormatMessageW": "human-readable text for qSystemError/qt_errorString",
    "LocalFree": "free FormatMessageW buffers and SIDs",
    "WSAGetLastError": "socket error mapping; Qt translates WSAE* to QAbstractSocket::SocketError",
    "WSAStartup": "initialise Winsock; nonzero => QTcpSocket unusable",
    "WSACleanup": "balance WSAStartup",
    "WSASocketW": "create a socket with flags (WSA_FLAG_OVERLAPPED for Qt's select-based engine)",
    "WSAIoctl": "SIO_GET_EXTENSION_FUNCTION_POINTER etc.",
    "closesocket": "close a socket",
    "ioctlsocket": "FIONBIO/FIONREAD for the native socket engine",
    "select": "the Qt Windows event dispatcher's socket polling",
    "recv": "socket read; SOCKET_ERROR with WSAEWOULDBLOCK is normal (Qt waits)",
    "send": "socket write; WSAEWOULDBLOCK is normal",
    "connect": "WSAEWOULDBLOCK means connect in progress on non-blocking sockets",
    "accept": "accept a pending connection",
    "bind": "bind QAbstractSocket/QUdpSocket",
    "listen": "QLocalServer/TcpServer listen backlog",
    "getsockname": "local address/port",
    "getpeername": "peer address/port",
    "getsockopt": "SO_ERROR/SO_TYPE",
    "setsockopt": "SO_REUSEADDR, TCP_NODELAY (Qt sets nodelay by default)",
    "WSAEnumNetworkEvents": "Qt's select-based engine maps events back to socket state",
    "WSAEventSelect": "register socket events with the dispatcher's event object",
    "WSAResetEvent": "reset the socket event object",
    "WSAWaitForMultipleEvents": "wait for socket events in the dispatcher",
    "getaddrinfo": "QHostInfo/QDnsLookup on Windows uses the OS resolver (ws2_32)",
    "GetAddrInfoExW": "QHostInfo asynchronous resolver path on Windows 8+",
    "FreeAddrInfoExW": "free GetAddrInfoExW results",
    "DnsQuery_W": "direct DNS query path (dnsapi)",
    "DnsFree": "free DnsQuery_W results",
    "GetAdaptersAddresses": "QNetworkInterface enumeration (iphlpapi); ERROR_BUFFER_OVERFLOW means realloc and retry",
    "GetAdaptersInfo": "legacy interface enumeration",
    "GetIfTable2": "newer interface table (iphlpapi)",
    "NotifyIpInterfaceChange": "QNetworkInterface/QNetConMonitor interface-change callback registration; we patch this in Wine (patches/local/0102)",
    "NotifyUnicastIpAddressChange": "address-change notification (same patch; Wine had a no-op)",
    "CancelMibChangeNotify2": "unregister the change notification",
    "ConvertInterfaceLuidToGuid": "map LUID -> interface GUID for QNetworkInterface",
    "ConvertInterfaceIndexToLuid": "map ifindex -> LUID",
    "ConvertInterfaceAliasToLuid": "map friendly name -> LUID",
    "if_nametoindex": "Qt fallback interface index lookup",
    "WSAAddressToStringW": "stringify QHostAddress",
    "WSAStringToAddressW": "parse QHostAddress",
    "inet_pton": "QHostAddress parse",
    "inet_ntop": "QHostAddress stringify",
    "GetUserDefaultLCID": "QLocale system locale",
    "GetLocaleInfoW": "QLocale language/territory/number formats",
    "EnumSystemLocalesW": "QLocale locale list",
    "GetNumberFormatW": "QSystemLocale number formatting",
    "GetDateFormatW": "QSystemLocale date formatting",
    "GetTimeFormatW": "QSystemLocale time formatting",
    "LCMapStringW": "case folding in QCollator/QLocale",
    "CompareStringW": "collation (QCollator)",
    "GetStringTypeW": "character classification",
    "MultiByteToWideChar": "QString<->QByteArray codec conversion",
    "WideCharToMultiByte": "QString<->QByteArray codec conversion",
    "IsValidCodePage": "QTextCodec availability",
    "GetACP": "default codec",
    "OleInitialize": "COM/OLE for drag&drop and the platform clipboard",
    "OleUninitialize": "balance OleInitialize",
    "CoInitializeEx": "COM apartment init (Qt uses STA in the GUI thread)",
    "CoUninitialize": "balance CoInitializeEx",
    "CoCreateInstance": "create OLE/shell objects (drag&drop, file dialogs, taskbar)",
    "CoGetObject": "resolve shell objects by display name",
    "CoTaskMemFree": "free shell-allocated strings",
    "CoSetProxyBlanket": "not used by Qt core; listed for completeness",
    "DoDragDrop": "QWindowsDrag::drag runs the OLE drag&drop loop",
    "RegisterDragDrop": "register the Qt window as a drop target (IDropTarget)",
    "RevokeDragDrop": "unregister the drop target",
    "OleGetClipboard": "paste via the OLE clipboard",
    "OleSetClipboard": "copy via the OLE clipboard",
    "OleIsCurrentClipboard": "clipboard ownership check",
    "OleFlushClipboard": "commit deferred rendering",
    "DragQueryFileW": "extract file paths from an HDROP drop",
    "DragQueryPoint": "drop coordinates from HDROP",
    "DragFinish": "release an HDROP",
    "DragAcceptFiles": "enable WM_DROPFILES on a window",
    "ShellExecuteExW": "open URLs/files from QDesktopServices; FALSE => Qt returns false",
    "Shell_NotifyIconW": "QSystemTrayIcon add/modify/delete",
    "SHGetKnownFolderPath": "QStandardPaths known folders",
    "SHGetFolderPathW": "legacy QStandardPaths fallback",
    "SHGetFileInfoW": "file type/icon info",
    "SHCreateItemFromParsingName": "shell item creation for QFileDialog/native menus",
    "SHGetMalloc": "legacy shell allocator",
    "IsUserAnAdmin": "QStandardPaths/QSysInfo privilege query (Qt prefers TokenElevation)",
    "SetCurrentProcessExplicitAppUserModelID": "taskbar grouping for the app",
    "GetCurrentProcess": "pseudo-handle used by many kernel32 calls",
    "GetCurrentProcessId": "logging/diagnostics",
    "GetCurrentThread": "pseudo-handle for thread affinity calls",
    "GetCurrentThreadId": "QMutex/QThread identity",
    "OpenThreadToken": "impersonation/privilege checks",
    "OpenProcessToken": "TokenElevation query (IsUserAnAdmin replacement)",
    "GetTokenInformation": "TokenElevation/TokenSessionId",
    "CreateToolhelp32Snapshot": "QProcess/child process enumeration (Task Manager style)",
    "Process32FirstW": "child process enumeration for QProcess::processId",
    "Process32NextW": "child process enumeration",
    "GetVersionExW": "deprecated; Qt no longer uses it for version detection",
    "RtlGetVersion": "actual OS version (ntdll); Qt's QOperatingSystemVersion backend on Win8+",
    "IsWindowsVersionOrGreater": "qoperatingsystemversion_win.cpp version probes",
    "IsWindows10OrGreater": "Qt's Win10 detection",
    "VerifyVersionInfoW": "legacy version probe",
    "GetSystemMetrics": "screen metrics, virtual desktop, multi-monitor",
    "SystemParametersInfoW": "theme/font/DPI settings, QWindowsTheme",
    "GetSysColorBrush": "system colours for QWindowsTheme palettes",
    "GetSysColor": "system colours",
    "GetSystemMenu": "window system menu",
    "TrackPopupMenu": "context menus (QWindowsMenu fallback)",
    "CreatePopupMenu": "context/native menus",
    "InsertMenuItemW": "native menu construction",
    "SetMenu": "attach a menu to a window",
    "DrawMenuBar": "native menu redraw",
    "GetMenuItemInfoW": "menu item inspection",
    "MessageBoxW": "QMessageBox native fallback / diagnostics",
    "MessageBeep": "QApplication::beep",
    "PlaySound": "QSound (winmm)",
    "ImmGetContext": "QWindowsInputContext IME",
    "ImmSetCompositionWindow": "IME candidate window placement",
    "ImmNotifyIME": "IME state transitions",
    "ImmAssociateContext": "IME enable/disable",
    "GetPropW": "recover the Qt window from an HWND (ATOM-based lookup)",
    "SetPropW": "attach QWindowsWindow data to an HWND",
    "RemovePropW": "detach window data",
    "GetClassInfoExW": "probe the Qt window class / foreign class",
    "UnregisterClassW": "teardown of the Qt window class",
    "GetGUIThreadInfo": "query the GUI thread's capture/active window (Qt uses it for popup handling)",
    "GetWindowThreadProcessId": "identify the owning thread/process of an HWND",
    "IsWindow": "validate HWNDs before calling",
    "IsWindowVisible": "window state",
    "ShowWindow": "map QWindow::setVisible to Win32 show state",
    "SetWindowPos": "move/resize/z-order; FALSE => Qt logs a warning",
    "MoveWindow": "resize path; FALSE => Qt keeps the old geometry",
    "GetWindowRect": "query frame geometry",
    "GetWindowPlacement": "maximised/minimised state",
    "ShowWindowAsync": "used by the session/console paths",
    "SetForegroundWindow": "activate a window; Windows may refuse (returns FALSE) — Qt falls back to AttachThreadInput",
    "SetActiveWindow": "focus handling in dialogs",
    "SetFocus": "give keyboard focus; NULL => focus not set",
    "GetFocus": "current focus HWND",
    "GetActiveWindow": "active window for the thread",
    "GetForegroundWindow": "foreground window of the desktop",
    "GetDesktopWindow": "parent for popups",
    "GetParent": "parent HWND lookup",
    "SetParent": "reparent (native widgets/popups)",
    "MapWindowPoints": "coordinate translation between windows",
    "ScreenToClient": "map global -> client coords",
    "ClientToScreen": "map client -> global coords",
    "GetCursorPos": "QCursor::pos",
    "SetCursorPos": "QCursor::setPos",
    "SetCursor": "QCursor::setShape / WM_SETCURSOR",
    "LoadCursorW": "cursor loading for QCursor",
    "LoadImageW": "cursor/icon/bitmap loading",
    "DestroyCursor": "free loaded cursors",
    "DestroyIcon": "free loaded icons",
    "CreateIconIndirect": "QIcon -> HICON conversion (tray/taskbar)",
    "GetIconInfo": "HICON -> QPixmap conversion (drag images)",
    "OpenClipboard": "clipboard ownership; FALSE => Qt retries/times out",
    "CloseClipboard": "balance OpenClipboard",
    "EmptyClipboard": "clear before setting new clipboard data",
    "SetClipboardData": "publish CF_* formats (delayed rendering for images)",
    "GetClipboardData": "read a CF_* format",
    "IsClipboardFormatAvailable": "format probe before paste",
    "EnumClipboardFormats": "list available formats (MIME mapping)",
    "RegisterClipboardFormatW": "custom MIME formats for QWindowsMime",
    "GetClipboardFormatNameW": "reverse mapping of registered formats",
    "CountClipboardFormats": "clipboard content probe",
    "GetOpenFileNameW": "native file dialog (QFileDialog when not using the Qt dialog)",
    "GetSaveFileNameW": "native save dialog",
    "ChooseColorW": "native colour dialog",
    "ChooseFontW": "native font dialog",
    "PrintDlgExW": "native print dialog",
    "InitCommonControlsEx": "initialise comctl32 for native widgets/dialogs",
    "PathFindFileNameW": "shlwapi path helpers used by Qt's file engine",
    "PathIsRelativeW": "path classification",
    "PathCanonicalizeW": "path normalisation",
    "SHGetSpecialFolderLocation": "legacy known-folder lookup",
    "GetUserDefaultUILanguage": "translation/locale probe",
    "GetSystemDefaultLCID": "locale probe",
    "GetThreadLocale": "QLocale per-thread locale",
    "SetThreadLocale": "test-only",
    "CreateThread": "QThread::start on the Win32 path (Qt uses _beginthreadex by preference)",
    "_beginthreadex": "QThread/QThreadPool thread creation",
    "_endthreadex": "thread exit path",
    "GetCurrentThreadStackLimits": "Qt's stack bounds query on Win8+ (QThread)",
    "SetThreadStackGuarantee": "reserve stack for exception handling (QThread/Chromium)",
    "GetThreadTimes": "QThread CPU time",
    "GetProcessTimes": "QProcess/QThread CPU time",
    "GetProcessAffinityMask": "QThread::idealThreadCount / affinity",
    "SetThreadAffinityMask": "QThread affinity on Windows",
    "SetThreadPriority": "QThread priority mapping",
    "GetThreadPriority": "QThread priority query",
    "GetPriorityClass": "QProcess priority query",
    "LoadLibraryExW": "load plugins with LOAD_WITH_ALTERED_SEARCH_PATH",
    "GetModuleHandleExW": "already listed",
    "SetErrorMode": "suppress Windows error dialogs (Qt sets SEM_FAILCRITICALERRORS)",
    "SetThreadErrorMode": "per-thread error mode for Qt internals",
    "RaiseException": "structured-exception handling path used by the C++ runtime",
    "GetEnvironmentStringsW": "QProcess::systemEnvironment",
    "FreeEnvironmentStringsW": "free QProcess environment block",
    "GetEnvironmentVariableW": "qEnvironmentVariable",
    "SetEnvironmentVariableW": "QProcess::setProcessEnvironment",
    "ExpandEnvironmentStringsW": "path expansion",
    "CreateDirectoryW": "already listed",
    "GetFullPathNameW": "QDir::cleanPath/QFileInfo canonical path",
    "GetLongPathNameW": "QFileInfo canonical path",
    "GetShortPathNameW": "8.3 name handling",
    "SearchPathW": "executable lookup for QProcess",
    "GetCommandLineW": "qApp arguments (parsed by QCoreApplication)",
    "CommandLineToArgvW": "shell argument parsing",
    "LocalFree": "free CommandLineToArgvW",
    "SetConsoleCtrlHandler": "console ctrl handling for QCoreApplication",
    "AttachConsole": "console paths for QProcess/QWinEventNotifier",
    "AllocConsole": "console allocation for tools",
    "GetConsoleMode": "console detection",
    "GetStdHandle": "QProcess console handles",
    "WriteConsoleW": "QTextStream to console",
    "GetCurrentDirectoryW": "QDir::currentPath",
    "SetCurrentDirectoryW": "QDir::setCurrent",
    "CreateFileMappingW": "QSharedMemory",
    "MapViewOfFile": "QSharedMemory attach",
    "UnmapViewOfFile": "QSharedMemory detach",
    "OpenFileMappingW": "QSharedMemory attach to existing segment",
    "CloseHandle": "balance every handle; failure puts Qt into a debug assertion",
    "GetHandleInformation": "verify inheritance flags on handles",
    "GetFileType": "distinguish disk/pipe/char/file (Qt uses it for QFile)",
    "GetFileSizeEx": "QFile::size",
    "GetFileTime": "QFileInfo timestamps",
    "SetFileTime": "QFile::setFileTime",
    "GetTempFileNameW": "QTemporaryFile fallback naming",
    "GetComputerNameW": "QSysInfo::machineHostName",
    "GetUserNameW": "QSysInfo user name",
    "GetComputerNameExW": "QSysInfo host name",
    "GetUserProfileDirectoryW": "QStandardPaths home dir (userenv)",
    "GetProfilesDirectoryW": "profile path enumeration",
    "CreateEnvironmentBlock": "QProcess environment for a user token",
    "DestroyEnvironmentBlock": "free CreateEnvironmentBlock",
    "WTSGetActiveConsoleSessionId": "session detection (wtsapi32/kernel32)",
    "WTSQueryUserToken": "session helper for spawning in the interactive session",
    "ProcessIdToSessionId": "session detection",
    "GetCurrentProcessToken": "pseudo-handle for privilege queries",
    "WTSFreeMemory": "free WTSQueryUserToken/WTS* buffers",
    "RtlCaptureStackBackTrace": "Qt debug/backtrace support",
    "MiniDumpWriteDump": "crash dumps (dbghelp)",
    "SymInitialize": "symbol handler init (dbghelp)",
    "StackWalk64": "stack unwinding (dbghelp)",
    "CryptAcquireContextW": "legacy crypto provider (Qt Windows crypto backend / QRandom)",
    "CryptGenRandom": "QRandomGenerator system entropy (legacy CryptoAPI path)",
    "CryptReleaseContext": "balance CryptAcquireContextW",
    "BCryptGenRandom": "QRandomGenerator preferred entropy source (bcrypt)",
    "BCryptOpenAlgorithmProvider": "bcrypt hash/cipher (hash lib in Qt 5.15 was moved out of QtCore, but QtWebEngine/Chromium use it)",
    "BCryptCloseAlgorithmProvider": "balance BCryptOpenAlgorithmProvider",
    "BCryptGetProperty": "query algorithm params",
    "BCryptCreateHash": "hash creation",
    "BCryptHashData": "hash input",
    "BCryptFinishHash": "hash output",
    "NCryptOpenStorageProvider": "Windows certificate-store key operations",
    "CertOpenStore": "certificate store access (SChannel backend, qsslcertificate_winrt / TLS)",
    "CertFindCertificateInStore": "certificate lookup",
    "CertGetCertificateContextProperty": "certificate properties",
    "CertFreeCertificateContext": "free certificate contexts",
    "CertCloseStore": "close certificate stores",
    "Schannel": "SSL backend",
    "AcquireCredentialsHandleW": "SChannel/SSPI credential acquisition (qsslsocket_schannel.cpp)",
    "InitializeSecurityContextW": "TLS handshake step",
    "QueryContextAttributesW": "TLS stream sizes",
    "ApplyControlToken": "TLS shutdown (SCHANNEL_SHUTDOWN)",
    "EncryptMessage": "TLS record encryption",
    "DecryptMessage": "TLS record decryption; SEC_E_INCOMPLETE_MESSAGE is normal",
    "FreeContextBuffer": "free SSPI output buffers",
    "DeleteSecurityContext": "release TLS contexts",
    "FreeCredentialsHandle": "release credentials",
    "QuerySecurityPackageInfoW": "probe Schannel capabilities",
    "SQLAllocHandle": "ODBC driver (QSqlDatabase) driver/handle allocation",
    "SQLDriverConnectW": "ODBC connect",
    "SQLExecDirectW": "ODBC statement execution",
    "SQLFetch": "ODBC row fetch",
    "SQLGetDiagRecW": "ODBC error details",
    "SQLBindCol": "ODBC result binding",
    "SQLDescribeCol": "ODBC metadata",
    "SQLDisconnect": "ODBC disconnect",
    "SQLFreeHandle": "ODBC handle release",
    "SQLNumResultCols": "ODBC column count",
    "SQLRowCount": "ODBC affected rows",
    "SQLSetConnectAttr": "ODBC attributes",
    "SQLGetInfoW": "ODBC driver info",
    "sqlite3_open": "SQLite driver (bundled)",
}

TOKEN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
STUB_ANN = {"stub"}
PROC_ANN = {"stdcall", "cdecl", "thiscall", "fastcall", "varargs", "stdcall2", "extern"}

# Windows DLLs whose exported symbols form the candidate API set.  CRT/compiler
# runtime DLLs and Wine-internal helper DLLs are deliberately excluded: matching
# their short generic exports (time, abs, Lock, Delete, ...) against Qt prose
# produces nothing but noise.
API_DLLS = {
    "user32", "win32u", "gdi32", "kernel32", "kernelbase", "ntdll", "advapi32",
    "sechost", "shell32", "ole32", "combase", "oleaut32", "comdlg32", "comctl32",
    "shlwapi", "uxtheme", "dwmapi", "winmm", "ws2_32", "mswsock", "wsock32",
    "crypt32", "wintrust", "secur32", "bcrypt", "ncrypt", "bcryptprimitives",
    "winhttp", "wininet", "urlmon", "dnsapi", "iphlpapi", "netapi32", "wtsapi32",
    "psapi", "userenv", "version", "setupapi", "cfgmgr32", "rpcrt4", "winspool",
    "avrt", "hid", "powrprof", "propsys", "shcore", "uiautomationcore", "usp10",
    "oleacc", "d3d9", "d3d10", "d3d10_1", "d3d11", "d3d12", "d3dcompiler_43",
    "d3dcompiler_47", "dxgi", "dxgidebug", "d2d1", "dwrite", "opengl32", "glu32",
    "vulkan-1", "odbc32", "gdiplus", "windowscodecs", "mpr", "credui", "wincred",
    "wlanapi", "bluetoothapis", "imm32", "twinapi", "dcomp", "dsound", "dinput8",
    "xinput", "msimg32", "winusb", "hhctrl", "mqrt", "ncryptsslp", "normaliz",
    "wintab32", "dbghelp", "imagehlp", "dxva2", "opmapi", "d3dcompiler",
}

# C runtime identifiers that Wine's ntdll.spec re-exports by name.  Qt calls these
# thousands of times as ordinary code; they carry no Win32 tracing value.
DENY = {
    "abs", "atan", "atof", "atoi", "bsearch", "calloc", "ceil", "cos", "div",
    "exit", "fabs", "floor", "free", "isdigit", "isprint", "labs", "log",
    "longjmp", "malloc", "mbstowcs", "memchr", "memcmp", "memcpy", "memmove",
    "memset", "pow", "qsort", "rand", "realloc", "setjmp", "sin", "sprintf",
    "sprintf_s", "srand", "sscanf", "strcat", "strchr", "strcmp", "strcpy",
    "strlen", "strncmp", "strncpy", "strrchr", "strstr", "tan", "tolower",
    "toupper", "wcschr", "wcscmp", "wcslen", "wcsncmp", "wcstombs", "wcscpy",
    "_snwprintf", "_snprintf", "vsnprintf", "swprintf", "strtoul", "strtol",
}

# Names that are legitimately *not* Wine DLL exports: Win32 header inlines, COM
# vtable methods, GL/WGL extension entry points fetched through wglGetProcAddress,
# vendor DLLs the app ships itself, and prose false positives.  Kept explicit so
# the stub list stays honest.
NOT_WINE = {
    "EnumAdapters": "DXGI COM method IDXGIFactory::EnumAdapters (Wine implements it in dlls/dxgi/factory.c) - not an export",
    "GetCurrentProcessToken": "winnt.h inline returning pseudo-handle (HANDLE)-4; winapi-rs has it commented out - not an import",
    "OutOfMemory": "ANGLE-local helper gl::OutOfMemory(); the identically named setupapi stub is unrelated prose (false positive)",
    "Schannel": "prose inside a QSslConfiguration doc comment",
    "eglGetDisplay": "Qt-bundled ANGLE libEGL.dll (Wine deliberately ships no libEGL)",
    "eglGetPlatformDisplayEXT": "Qt-bundled ANGLE libEGL.dll (EGL_EXT_platform_base)",
    "glCreateShader": "GL 2.0 entry point fetched via wglGetProcAddress (Wine opengl32 thunks.c dispatch table)",
    "glGetStringi": "GL 3.0 entry point fetched via wglGetProcAddress",
    "glGetGraphicsResetStatusARB": "GL_ARB_robustness entry point fetched via wglGetProcAddress",
    "wglChoosePixelFormatARB": "WGL_ARB_pixel_format, via wglGetProcAddress (Wine thunks.c)",
    "wglCreateContextAttribsARB": "WGL_ARB_create_context, via wglGetProcAddress (Wine thunks.c)",
    "wglGetExtensionsStringARB": "WGL_ARB_extensions_string, via wglGetProcAddress (Wine thunks.c)",
    "wglGetPixelFormatAttribivARB": "WGL_ARB_pixel_format, via wglGetProcAddress",
    "wglGetSwapIntervalEXT": "WGL_EXT_swap_control, via wglGetProcAddress",
    "wglSwapIntervalEXT": "WGL_EXT_swap_control, via wglGetProcAddress (Wine thunks.c)",
    "qt_testability_init": "Qt-internal optional symbol (QT_TESTABILITY), not Win32",
}
# CRT/compiler-runtime DLLs: consulted only to classify APIs Qt calls directly
# (_beginthreadex, _endthreadex, ...), never used as scan candidates.
SECONDARY_DLLS = {
    "ucrtbase", "msvcrt", "msvcr80", "msvcr90", "msvcr100", "msvcr110",
    "msvcr120", "vcruntime140", "vcruntime140_1",
}
# Preference when one symbol appears in several specs (Windows forwards a lot).
DLL_PREFERENCE = ["user32", "gdi32", "kernel32", "kernelbase", "advapi32",
                  "shell32", "ole32", "oleaut32", "comdlg32", "comctl32",
                  "shlwapi", "uxtheme", "dwmapi", "winmm", "ws2_32", "mswsock",
                  "crypt32", "secur32", "bcrypt", "ncrypt", "winhttp", "wininet",
                  "urlmon", "dnsapi", "iphlpapi", "wtsapi32", "userenv",
                  "setupapi", "winspool", "d3d11", "d3d9", "dxgi", "dwrite",
                  "d2d1", "opengl32", "odbc32", "imm32", "uiautomationcore",
                  "combase", "win32u", "ntdll"]

# Qt source files for other platforms: Qt ships them next to the Windows ones and
# they contain the same POSIX API names (select, connect, bind...).
EXCLUDE_FILE = re.compile(
    r"(_unix\.(cpp|cc|h|mm)|_mac\.(cpp|mm)|_mac_shared|_winrt\.(cpp|h)|"
    r"_android\.|_linux\.|_uikit\.|_wasm\.|_darwin\.|_haiku\.|_integrity\.|"
    r"_qnx\.|_vxworks\.|_bsdfb|/doc/|/tests?/|/examples/|qdnslookup_unix|"
    r"socks5|/sqldrivers/(db2|mysql|psql|ibase)/)")

# Lower-case names that are also ordinary identifiers in Qt/C++ code.  These are
# only trusted when called with explicit global qualification (::name), which is
# how Qt calls Winsock.
AMBIG = {
    "bind", "connect", "accept", "send", "recv", "select", "listen", "shutdown",
    "socket", "close", "closesocket", "getpeername", "getsockname", "getsockopt",
    "setsockopt", "ioctlsocket", "recvfrom", "sendto", "htonl", "htons", "ntohl",
    "ntohs", "inet_addr", "inet_ntoa", "inet_pton", "inet_ntop", "gethostname",
    "gethostbyname", "getservbyname", "lock", "unlock", "delete", "next", "put",
    "clone", "free", "read", "write", "open", "time", "close", "abort", "exit",
}


def _spec_line_kind(line):
    """Return (symbol, kind, forwarding) for one non-comment spec line.

    Handles both Wine spec dialects:
        @ stdcall Foo(args) [dll.target]        (modern)
        123 stdcall Foo(args) [dll.target]      (legacy, ordinal-first)
    A line opening with '#' is a comment and therefore NOT an export (Wine uses
    commented-out lines to record functions it intentionally does not implement).
    """
    s = line.split("#", 1)[0].strip()
    if not s:
        return None
    parts = s.split()
    if s.startswith("@"):
        if len(parts) < 2:
            return None
        ann = parts[1].lstrip("-")
        rest = parts[2:]
    else:
        if re.match(r"^\d+$", parts[0]):
            parts = parts[1:]
        if not parts:
            return None
        ann = parts[0].lstrip("-")
        rest = parts[1:]
    flags = []
    while rest and rest[0].startswith("-"):
        flags.append(rest.pop(0))
    name = ""
    if rest and not rest[0].startswith("@"):
        tok = rest[0]
        if "(" in tok:
            name = tok.split("(", 1)[0]
        elif re.match(r"^\d+$", tok):
            flags.append("-ordinal " + tok)
            rest.pop(0)
            if rest:
                name = rest[0].split("(", 1)[0]
        else:
            name = tok
    if not name:
        return ("", "stub" if ann in STUB_ANN else "ordinal", "", False)
    if ann in STUB_ANN:
        return (name, "stub", "", "-noname" in flags)
    forwarding = ""
    if "-import" in flags:
        forwarding = "-import"
    else:
        # a token after the closing paren of the prototype is a dll.func target
        m = re.search(r"\)\s+(\S+)", s)
        if m:
            forwarding = m.group(1)
    return (name, "forward" if forwarding else "impl", forwarding,
            "-noname" in flags)


def load_wine_specs(wine_root):
    """symbol -> list of dicts(dll,kind,file,line,raw) for Windows API DLLs."""
    out = {}
    dlls_dir = os.path.join(wine_root, "dlls")
    for entry in sorted(os.listdir(dlls_dir)):
        spec = os.path.join(dlls_dir, entry, entry + ".spec")
        if not os.path.isfile(spec):
            continue
        dll = entry.lower()
        if dll.endswith(".exe"):
            continue
        if dll not in API_DLLS:
            continue
        with open(spec, "r", errors="replace") as fh:
            for lineno, raw in enumerate(fh, 1):
                parsed = _spec_line_kind(raw)
                if not parsed:
                    continue
                name, kind, fwd, noname = parsed
                if not name:
                    continue
                out.setdefault(name, []).append({
                    "dll": dll, "kind": kind, "file": os.path.relpath(spec, wine_root),
                    "line": lineno, "raw": raw.rstrip(), "forward": fwd,
                    "noname": noname,
                })
    return out


def load_winapi(winapi_root):
    """symbol -> set of module names (um/shared)."""
    out = {}
    for sub in ("um", "shared", "vc", "winrt"):
        d = os.path.join(winapi_root, "src", sub)
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".rs"):
                continue
            mod = fn[:-3]
            path = os.path.join(d, fn)
            with open(path, "r", errors="replace") as fh:
                for raw in fh:
                    m = re.match(r"^\s+pub fn ([A-Za-z_][A-Za-z0-9_]*)", raw)
                    if m:
                        out.setdefault(m.group(1), set()).add(mod)
    return out


def iter_scope(qt_root):
    for entry in SCOPE:
        p = os.path.join(qt_root, entry)
        if os.path.isdir(p):
            for root, _dirs, files in os.walk(p):
                for fn in sorted(files):
                    if fn.endswith((".cpp", ".cc", ".c")):
                        yield os.path.join(root, fn)
        elif os.path.isfile(p):
            yield p


def _in_string_literal(line, m):
    """True when the token is the *contents* of a quoted string literal."""
    return (m.start() > 0 and line[m.start() - 1] == '"'
            and m.end() < len(line) and line[m.end()] == '"')


def _is_hit(line, m, tok):
    """Accept an occurrence only in a plausible API-use context.

    - string literal     : rejected here (captured instead by scan_resolved).
    - `::Foo(` / `::Foo` : Qt's Winsock and Win32 calls are `::`-qualified.
    - `Foo(`             : a call, unless the name is in AMBIG (member call noise).
    - anything else      : only for long, unambiguous names (address-of, tables).
    """
    if _in_string_literal(line, m):
        return False
    i = m.start()
    tail = line[m.end():]
    is_call = tail.lstrip(" \t").startswith("(")
    qualified = line[max(0, i - 2):i] == "::"
    if qualified:
        before = line[i - 3] if i >= 3 else " "
        qualified = not (before.isalnum() or before in "_:>.")
    if tok in AMBIG:
        return qualified
    if is_call or qualified:
        return True
    return len(tok) >= 6


def strip_comment(line, state):
    """Remove `//` and `/* */` comments from one line, tracking block state.

    A naive "skip lines starting with *" test silently drops real code such as
    `*winsta = ::CreateWindowStationW(` — which is how Chromium creates its
    sandbox window station.
    """
    out = []
    i = 0
    n = len(line)
    while i < n:
        if state["block"]:
            j = line.find("*/", i)
            if j < 0:
                return "".join(out)
            state["block"] = False
            i = j + 2
            continue
        j = line.find("//", i)
        k = line.find("/*", i)
        if j >= 0 and (k < 0 or j < k):
            out.append(line[i:j])
            return "".join(out)
        if k >= 0:
            out.append(line[i:k])
            state["block"] = True
            i = k + 2
            continue
        out.append(line[i:])
        break
    return "".join(out)


def build_lookup(names):
    """token -> canonical export name.

    Qt is compiled with UNICODE defined, so it writes the *base* macro name
    (`CreateWindowEx`, `RegisterClassEx`, `SQLDriverConnect`) which resolves to
    the `...W` export at the preprocessor level.  Map those back to the export
    Wine actually has to implement.
    """
    lookup = {n: n for n in names}
    for n in names:
        if n.endswith("W") and len(n) > 2:
            lookup.setdefault(n[:-1], n)
    return lookup


def scan(qt_root, names):
    lookup = build_lookup(names)
    hits = {}
    files = 0
    for path in iter_scope(qt_root):
        if not os.path.isfile(path):
            continue
        rel = os.path.relpath(path, qt_root)
        if EXCLUDE_FILE.search(rel):
            continue
        files += 1
        state = {"block": False}
        try:
            with open(path, "r", errors="replace") as fh:
                for lineno, raw in enumerate(fh, 1):
                    code = strip_comment(raw, state)
                    if not code.strip():
                        continue
                    for m in TOKEN.finditer(code):
                        tok = m.group(0)
                        api = lookup.get(tok)
                        if api and _is_hit(code, m, tok):
                            hits.setdefault(api, []).append({
                                "file": rel, "line": lineno,
                                "text": raw.strip(), "token": tok})
        except OSError:
            pass
    return hits, files


# Qt resolves a large part of the optional Win32 surface at runtime:
#   library.resolve("SkipPointerFrameMessages")
#   ::GetProcAddress(mod, "D3DCompile")
# A missing Wine export here is silent (Qt degrades or asserts) — so these names
# are indexed separately even though `_is_hit` ignores string literals.
RESOLVE_RE = re.compile(
    r'(?:\bresolve|GetProcAddress)\s*\(\s*(?:[^,()"]+,\s*)?"([A-Za-z_][A-Za-z0-9_@?]*)"')


def scan_resolved(qt_root):
    dyn = {}
    for path in iter_scope(qt_root):
        if not os.path.isfile(path):
            continue
        rel = os.path.relpath(path, qt_root)
        if EXCLUDE_FILE.search(rel):
            continue
        for pattern in (RESOLVE_RE,):
            state = {"block": False}
            try:
                with open(path, "r", errors="replace") as fh:
                    for lineno, raw in enumerate(fh, 1):
                        code = strip_comment(raw, state)
                        for m in pattern.finditer(code):
                            dyn.setdefault(m.group(1), []).append(
                                {"file": rel, "line": lineno,
                                 "text": raw.strip(), "token": m.group(1)})
            except OSError:
                pass
    return dyn


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--qt-root", default="/run/media/asdf/Windows/qt-src/qtbase")
    ap.add_argument("--wine-root", default="/home/asdf/projects/hog-wine/wine-11.18")
    ap.add_argument("--winapi-root",
                    default="/run/media/asdf/Windows/qt-src/winapi/winapi-0.3.9")
    ap.add_argument("--out-json", default="")
    ap.add_argument("--out-md", default="")
    ap.add_argument("--dump-stubs", default="")
    args = ap.parse_args()

    specs = load_wine_specs(args.wine_root)
    winapi = load_winapi(args.winapi_root)
    # `-noname` spec entries are ordinal-only exports (no name on Windows), so a
    # same-named member call in Qt code is not evidence of a Win32 call.
    named_specs = {n for n, es in specs.items()
                   if any(not e.get("noname") for e in es)}
    names = (named_specs | set(winapi) | set(EXPECT)) - DENY
    hits, nfiles = scan(args.qt_root, names)
    dyn = scan_resolved(args.qt_root)

    # CRT / compiler-runtime exports used directly by Qt (_beginthreadex, ...).
    # They are not part of the Win32 surface but the trace loop still needs them.
    crt = {}
    dlls_dir = os.path.join(args.wine_root, "dlls")
    for entry in sorted(os.listdir(dlls_dir)):
        if entry not in SECONDARY_DLLS:
            continue
        spec = os.path.join(dlls_dir, entry, entry + ".spec")
        if not os.path.isfile(spec):
            continue
        with open(spec, "r", errors="replace") as fh:
            for lineno, raw in enumerate(fh, 1):
                parsed = _spec_line_kind(raw)
                if not parsed or not parsed[0]:
                    continue
                crt.setdefault(parsed[0], []).append({
                    "dll": entry, "kind": parsed[1],
                    "file": os.path.relpath(spec, args.wine_root),
                    "line": lineno, "raw": raw.rstrip(), "forward": parsed[2]})

    rank = {d: i for i, d in enumerate(DLL_PREFERENCE)}

    def pick(entries):
        return sorted(entries, key=lambda e: (rank.get(e["dll"], 999),
                                              e["kind"] == "ordinal"))[0]

    result = {}
    stubs = []
    for api in sorted(set(hits) | set(dyn)):
        w = specs.get(api)
        secondary = False
        if w:
            primary = pick(w)
            status = primary["kind"]
            dll = primary["dll"]
            dlls = sorted({e["dll"] for e in w}, key=lambda d: rank.get(d, 999))
            # A symbol that is a stub in its preferred DLL but implemented by a
            # forward elsewhere is still usable; only report 'stub' if every
            # DLL that carries it stubs it.
            if status == "stub" and any(e["kind"] != "stub" for e in w):
                status = "forward" if any(e["kind"] == "forward" for e in w) else "impl"
        elif api in crt:
            w = crt[api]
            primary = w[0]
            status = primary["kind"]
            dll = primary["dll"]
            dlls = sorted({e["dll"] for e in w})
            secondary = True
        else:
            primary, status, dll, dlls = {}, "absent", "", []
            mods = winapi.get(api, set())
            dlls = sorted({MODULE_DLL.get(m, m) for m in mods})
        if status in ("absent", "stub") and api in NOT_WINE:
            status = "not-an-export"
        sites = hits.get(api, [])
        dsites = dyn.get(api, [])
        result[api] = {
            "wine_dll": dll,
            "wine_dlls": dlls,
            "wine_status": status,
            "wine_spec": primary.get("file", ""),
            "wine_spec_line": primary.get("line", 0),
            "wine_raw": primary.get("raw", ""),
            "wine_all_entries": [{"dll": e["dll"], "kind": e["kind"],
                                  "file": e["file"], "line": e["line"],
                                  "raw": e["raw"]} for e in (w or [])],
            "winapi_modules": sorted(winapi.get(api, [])),
            "qt_sites": sites,
            "dynamic_sites": dsites,
            "crt_fallback": secondary,
            "expect": EXPECT.get(api, ""),
        }
        if status in ("stub", "absent"):
            stubs.append(api)

    def first_site(d):
        if d["qt_sites"]:
            return d["qt_sites"][0]
        if d["dynamic_sites"]:
            return d["dynamic_sites"][0]
        return None

    agg = {}
    for api, d in result.items():
        status = d["wine_status"]
        if status in ("stub", "absent"):
            agg[api] = {"status": status, "dll": d["wine_dll"] or ",".join(d["wine_dlls"]),
                        "spec": d["wine_spec"], "line": d["wine_spec_line"],
                        "raw": d["wine_raw"],
                        "sites": len(d["qt_sites"]) + len(d["dynamic_sites"]),
                        "dynamic": bool(d["dynamic_sites"]) and not d["qt_sites"],
                        "first": first_site(d)}

    if args.out_json:
        with open(args.out_json, "w") as fh:
            json.dump(result, fh, indent=1, sort_keys=True)
    if args.out_md:
        with open(args.out_md, "w") as fh:
            fh.write("| Win32 API | Wine DLL | Status | Qt source (first site) | What Qt expects |\n")
            fh.write("|---|---|---|---|---|\n")
            for api in sorted(result):
                d = result[api]
                s = first_site(d)
                st = d["wine_status"]
                if st == "absent":
                    st = "**absent**"
                elif st == "stub":
                    st = "**stub**"
                if d["crt_fallback"]:
                    st += " (CRT)"
                site = "%s:%d" % (s["file"], s["line"]) if s else "-"
                exp = d["expect"].replace("|", "\\|")
                if not exp and s:
                    exp = "`" + s["text"].replace("|", "\\|") + "`"
                fh.write("| `%s` | %s | %s | %s | %s |\n" %
                         (api, d["wine_dll"] or ",".join(d["wine_dlls"]), st,
                          site, exp))
    if args.dump_stubs:
        with open(args.dump_stubs, "w") as fh:
            for api in sorted(agg):
                a = agg[api]
                fh.write("%s\t%s\t%s\t%s:%s\t%s\t%s\n" %
                         (api, a["status"], a["dll"], a["spec"], a["line"], a["raw"],
                          (a["first"] or {}).get("file", "") + ":" + str((a["first"] or {}).get("line", ""))))

    print("qt files scanned: %d" % nfiles)
    print("apis referenced: %d" % len(result))
    print("stub/absent apis referenced: %d" % len(agg))
    from collections import Counter
    print("status counts:", dict(Counter(d["wine_status"] for d in result.values())))
    print("top dlls:", Counter(d["wine_dll"] for d in result.values() if d["wine_dll"]).most_common(15))


if __name__ == "__main__":
    sys.exit(main())
