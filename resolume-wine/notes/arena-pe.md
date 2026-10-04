# Arena.exe — PE facts relevant to Wine failures

Target: `/home/asdf/projects/resolume-wine/installer/media_x/app/Arena.exe` (59,339,104 bytes)
All facts below are measured; commands are included. Scratch output kept under `state/tmp/`.

## 0. Commands used

```
file installer/media_x/app/Arena.exe
objdump -f installer/media_x/app/Arena.exe
objdump -h installer/media_x/app/Arena.exe
objdump -p installer/media_x/app/Arena.exe > state/tmp/arena-p.txt   # 870,354 lines (mostly .pdata function table)
strings -a installer/media_x/app/Arena.exe > state/tmp/strings.txt   # 635,976 lines
python3 (minimal PE parse: state/tmp/parse_imports.py, state/tmp/checkfinal.py for the export cross-check)
openssl pkcs7 -inform DER -in state/tmp/authenticode.p7b -print_certs -noout
```

## 1. Architecture / header / sections

`file`:
```
installer/media_x/app/Arena.exe: PE32+ executable for MS Windows 6.00 (GUI), x86-64, 8 sections
```

`objdump -f`:
```
architecture: i386:x86-64, flags 0x0000012f: HAS_RELOC, EXEC_P, HAS_LINENO, HAS_DEBUG, HAS_LOCALS, D_PAGED
start address 0x0000000141d16f6c
```

`objdump -p` header (lines 4–42):
```
Characteristics 0x22        executable, large address aware
Time/Date        Mon Sep 21 10:56:52 2026        (raw COFF TimeDateStamp = 0x6ab153c4 = 2026-09-21 15:56:52 UTC)
Magic            020b  (PE32+)
MajorLinkerVersion 14 / MinorLinkerVersion 44    => MSVC linker 14.44 (VS 2022 17.14)
AddressOfEntryPoint 0000000001d16f6c
ImageBase       0000000140000000
SectionAlignment 00001000 / FileAlignment 00000200
MajorSubsystemVersion 6 / MinorSubsystemVersion 0
SizeOfImage     03924000
Subsystem       00000002  (Windows GUI)
DllCharacteristics 00008160  HIGH_ENTROPY_VA, DYNAMIC_BASE, NX_COMPAT, TERMINAL_SERVICE_AWARE   (no GUARD_CF / CFG)
SizeOfStackReserve 0x100000 / SizeOfHeapReserve 0x100000
NumberOfRvaAndSizes 0x10
```

`objdump -h`:
```
Idx Name     Size       VMA                File off   Algn  Flags
 0  .text    0204e857   0000000140001000   00000400   2**4  CODE
 1  RT_CODE  00000815   0000000142050000   0204ee00   2**2  CODE
 2  .rdata   01434fc0   0000000142051000   0204f800   2**4  DATA
 3  .data    0025b400   0000000143486000   03484800   2**4  DATA
 4  .pdata   000f627c   000000014376d000   036dfc00   2**2  DATA  (.pdata x64 unwind, 868k function records)
 5  _RDATA   00000030   0000000143864000   037d6000   2**2
 6  .rsrc    00078500   0000000143865000   037d6200   2**2  (resources)
 7  .reloc   00045f1c   00000001438de000   0384e800   2**2
```

Data directories of interest (objdump -p):
```
Entry 1 Import Directory    0x347bda0 size 0x3e8   [.rdata]
Entry 2 Resource Directory  0x3865000 size 0x78500 [.rsrc]
Entry 4 Security Directory  0x3894800 size 0x2960  (Authenticode signature embedded)
Entry 6 Debug Directory     0x30f0af0 size 0x54    [.rdata]
Entry 9 TLS Directory       0x30f0b80 size 0x28    [.rdata]  (TLS data itself in .data)
Entry a Load Configuration   0x30f09b0 size 0x140
Entry b Bound Import       0 (none)
Entry d Delay Import       0 (NONE — see §5)
Entry e CLR Runtime Header 0 (native C++, not .NET)
```

## 2. Debug directory / PDB

```
Type  Size     Rva      Offset
  2   CodeView 0000006d 03290180 0328e980
(format RSDS signature d1fa2b88b0be43b09ade587346eb38be age 1
 pdb C:\GitLab-Runner\builds\PvzR3vKgH\0\resolume\software\build\RelWithDebInfo\Arena.pdb)
 12  Feature 00000014 ...
 13  CoffGrp 0000045c ...
```
→ Built on a GitLab CI runner, RelWithDebInfo, PDB name `Arena.pdb`; PDB not shipped next to the exe.

## 3. Compiler / C++ runtime

- Linker 14.44 (`objdump -p`) and embedded toolchain string:
  ```
  $ strings -a ... | grep 'COMPILER='
  COMPILER=msvc-1944        # line 476893 (this literal is SQLite's compile-options banner, but confirms the MSVC 19.44 toolset used for at least part of the build)
  ```
- C++ runtime imported by name: `MSVCP140.dll` (223 functions), `VCRUNTIME140.dll` (27), `VCRUNTIME140_1.dll` (1). No `MSVCP140_1/2`, no `MSVCIRT`.
- Rich header present (key 0xfc6c384c); product ids high word 0x0100–0x0109 (VS 2022 17.14 toolset family). Rich header is not a Wine-runtime issue.
- Authenticode signature embedded (Security dir 0x2960): signer `O=Resolume B.V., CN=Resolume B.V.` (DigiCert Trusted G4 Code Signing Europe RSA4096 SHA384 2023 CA1). Relevant because the exe imports `WINTRUST.WinVerifyTrust` + `CRYPT32.CryptQueryObject/CryptMsgGetParam` — self-signature verification of plugins/updates.

## 4. Imported DLLs (49) and function counts

Total imported functions: **1224** across **49** DLLs. Sorted by count (from `state/tmp/imports.txt`):

```
KERNEL32.dll (229)              MSVCP140.dll (223)            USER32.dll (125)
api-ms-win-crt-math-l1-1-0.dll (52)   OPENGL32.dll (42)     GDI32.dll (36)
api-ms-win-crt-string-l1-1-0.dll (35) api-ms-win-crt-stdio-l1-1-0.dll (32)
avutil-59.dll (30)              api-ms-win-crt-runtime-l1-1-0.dll (29)
WSOCK32.dll (29)                ADVAPI32.dll (29)             VCRUNTIME140.dll (27)
Processing.NDI.Lib.x64.dll (27) avformat-61.dll (24)          WINMM.dll (24)
avcodec-61.dll (21)             Artnet.dll (16)               ole32.dll (14)
SHELL32.dll (14)                api-ms-win-crt-convert-l1-1-0.dll (13)
WININET.dll (13)                WS2_32.dll (11)               api-ms-win-crt-time-l1-1-0.dll (10)
api-ms-win-crt-filesystem-l1-1-0.dll (10)  WinSparkle.dll (10)  OLEAUT32.dll (10)
api-ms-win-crt-heap-l1-1-0.dll (9)  SETUPAPI.dll (8)          swscale-8.dll (7)
MFPlat.DLL (7)                  IMM32.dll (7)                 libltc.dll (6)
IPHLPAPI.DLL (6)                api-ms-win-crt-locale-l1-1-0.dll (5)
api-ms-win-crt-environment-l1-1-0.dll (5)  MF.dll (5)         api-ms-win-crt-utility-l1-1-0.dll (4)
api-ms-win-core-synch-l1-2-0.dll (3)  VERSION.dll (3)         dxgi.dll (2)
SHLWAPI.dll (2)                 MSWSOCK.dll (2)               CRYPT32.dll (2)
COMDLG32.dll (2)                d3d11.dll (1)                 WINTRUST.dll (1)
VCRUNTIME140_1.dll (1)          COMCTL32.dll (1)
```

Full DLL list in link order: Artnet, Processing.NDI.Lib.x64, avformat-61, avcodec-61, swscale-8, avutil-59,
SETUPAPI, SHLWAPI, WINMM, WSOCK32, CRYPT32, WS2_32, OPENGL32, KERNEL32, USER32, GDI32, COMDLG32, ADVAPI32,
COMCTL32, SHELL32, ole32, OLEAUT32, d3d11, dxgi, VERSION, api-ms-win-core-synch-l1-2-0, WinSparkle, libltc,
MSVCP140, MSWSOCK, WININET, IMM32, MFPlat, MF, WINTRUST, VCRUNTIME140_1, VCRUNTIME140,
api-ms-win-crt-{heap,runtime,stdio,math,string,convert,environment,time,locale,utility,filesystem}-l1-1-0,
IPHLPAPI.

## 5. Exact imports for the requested system DLLs

(Exact, from objdump -p; ordinal imports are annotated with the name resolved from Wine's `.spec`.)

### OPENGL32.dll (42) — excludes wgl extension lookups done via wglGetProcAddress
```
glEnable, glGetString, glViewport, glFlush, glClearColor, glClear, glClearDepth, glColorMask,
glDepthFunc, glScissor, glBlendFunc, glFrontFace, glDisable, glPolygonMode, glBindTexture,
glGetTexImage, glCopyTexSubImage2D, glTexSubImage2D, glPixelStorei, glTexImage2D, glTexParameteriv,
glTexParameteri, glGenTextures, glReadPixels, glGetTexParameteriv, wglGetCurrentDC,
glGetTexLevelParameteriv, glTexParameterf, glDrawBuffer, glGetError, glReadBuffer, glDrawElements,
glGetIntegerv, glDrawArrays, wglCreateContext, wglMakeCurrent, wglGetProcAddress, wglShareLists,
wglGetCurrentContext, wglDeleteContext, glDeleteTextures, glDepthMask
```
Note: only OpenGL 1.x fixed-function entry points are statically imported; everything modern is via
`wglGetProcAddress` (extension string `glMaxShaderCompilerThreadsARB/KHR`, `glReleaseShaderCompiler`
seen in `strings`). Uses `wglCreateContext`/`wglMakeCurrent` (legacy WGL, not `wglCreateContextAttribsARB`).
`SwapBuffers`/`ChoosePixelFormat`/`SetPixelFormat` come from GDI32, not OPENGL32.

### MF.dll (5)
```
MFCreateTopology, MFGetService, MFCreateMediaSession, MFCreateTopologyNode, MFCreateSampleGrabberSinkActivate
```

### MFPlat.DLL (7)
```
MFCreateAttributes, MFPutWorkItemEx, MFCreateSourceResolver, MFCreateMediaType, MFStartup, MFShutdown, MFCreateAsyncResult
```

### SETUPAPI.dll (8)
```
SetupDiGetDeviceInterfaceDetailA, SetupDiGetClassDevsA, CM_Request_Device_EjectA, CM_Get_Parent,
CM_Get_Device_IDA, SetupDiDestroyDeviceInfoList, SetupDiEnumDeviceInterfaces, CM_Get_Device_ID_Size
```

### WINTRUST.dll (1)
```
WinVerifyTrust
```

### CRYPT32.dll (2)
```
CryptQueryObject, CryptMsgGetParam
```

### WININET.dll (13)
```
InternetSetFilePointer, HttpQueryInfoW, InternetOpenW, HttpEndRequestW, HttpSendRequestExW,
InternetCloseHandle, InternetConnectW, InternetSetOptionW, HttpOpenRequestW, InternetReadFile,
InternetCrackUrlW, FtpOpenFileW, InternetWriteFile
```

### IPHLPAPI.DLL (6)
```
ConvertInterfaceLuidToNameA, ConvertInterfaceIndexToLuid, if_indextoname, GetAdaptersInfo,
GetAdaptersAddresses, ConvertLengthToIpv4Mask
```

### MSWSOCK.dll (2)
```
AcceptEx, GetAcceptExSockaddrs
```

### WS2_32.dll (11)
```
WSAAddressToStringW, WSASocketW, WSASendTo, WSASend, WSARecvFrom, WSAStringToAddressW,
getaddrinfo, inet_ntop, freeaddrinfo, WSAIoctl, WSARecv
```

### WSOCK32.dll (29) — imported purely BY ORDINAL (winsock 1.1)
```
ord8=htonl, ord9=htons, ord20=sendto, ord12=ioctlsocket, ord21=setsockopt, ord111=WSAGetLastError,
ord116=WSACleanup, ord2=bind, ord3=closesocket, ord1=accept, ord151=__WSAFDIsSet, ord112=WSASetLastError,
ord14=ntohl, ord57=gethostname, ord22=shutdown, ord18=select, ord13=listen, ord5=getpeername,
ord10=inet_addr, ord6=getsockname, ord19=send, ord23=socket, ord15=ntohs, ord4=connect, ord11=inet_ntoa,
ord7=getsockopt, ord17=recvfrom, ord16=recv, ord115=WSAStartup
(ordinal→name mapping from wine/wine-11.18/dlls/wsock32/wsock32.spec)
```

### GDI32.dll (36)
```
BitBlt, SaveDC, CreateDIBSection, StretchDIBits, CreateRectRgnIndirect, CreateRectRgn, GetRegionData,
GetObjectW, ExcludeClipRect, RestoreDC, CreateSolidBrush, CreateBitmap, SwapBuffers, GetStockObject,
GetTextExtentPoint32A, ChoosePixelFormat, GetDIBits, CombineRgn, AddFontMemResourceEx, SelectObject,
GetKerningPairsW, CreateCompatibleDC, EnumFontFamiliesExW, GetDeviceCaps, GetTextMetricsW, DeleteDC,
SetMapperFlags, GetGlyphIndicesW, GetGlyphOutlineW, DeleteObject, RemoveFontMemResourceEx, SetMapMode,
CreateFontIndirectW, GetOutlineTextMetricsW, CreateCompatibleBitmap, SetPixelFormat
```

### IMM32.dll (7)
```
ImmGetContext, ImmReleaseContext, ImmNotifyIME, ImmAssociateContextEx, ImmSetCandidateWindow,
ImmAssociateContext, ImmGetCompositionStringW
```

### COMCTL32.dll (1) — BY ORDINAL
```
ord345 = TaskDialogIndirect
(resolved from wine-11.18/dlls/comctl32_v6/comctl32_v6.spec line "345 stdcall -ordinal TaskDialogIndirect(ptr ptr ptr ptr)"
 and wine-11.18/dlls/comctl32/tests/taskdialog.c:888 which asserts ordinal 345 == pTaskDialogIndirect)
```

### COMDLG32.dll (2)
```
GetSaveFileNameW, GetOpenFileNameW
```

### SHLWAPI.dll (2) — one by ordinal
```
ord219 = QISearch,  PathStripToRootW
(ord219→QISearch from wine/wine-11.18/dlls/shlwapi/shlwapi.spec line 219)
```

### VERSION.dll (3)
```
GetFileVersionInfoA, GetFileVersionInfoSizeA, VerQueryValueA
```

### WINMM.dll (24)
```
midiInOpen, midiInUnprepareHeader, midiInMessage, timeGetTime, timeBeginPeriod, timeEndPeriod,
midiOutGetDevCapsW, midiOutOpen, midiInStop, midiOutClose, midiOutLongMsg, midiOutGetNumDevs,
midiOutShortMsg, midiInGetNumDevs, midiOutMessage, midiInAddBuffer, midiInClose, midiInStart,
midiInGetDevCapsW, midiOutUnprepareHeader, timeGetDevCaps, midiInReset, midiOutPrepareHeader,
midiInPrepareHeader
```
(Timecode/MIDI sync path only.)

### OLEAUT32.dll (10) — BY ORDINAL
```
ord417=OleCreatePropertyFrame, ord8=VariantInit, ord6=SysFreeString, ord9=VariantClear,
ord16=SafeArrayDestroy, ord2=SysAllocString, ord26=SafeArrayPutElement, ord23=SafeArrayAccessData,
ord411=SafeArrayCreateVector, ord24=SafeArrayUnaccessData
(ordinal→name from wine/wine-11.18/dlls/oleaut32/oleaut32.spec)
```

### ADVAPI32.dll (29)
```
RegQueryValueExW, MapGenericMask, DuplicateToken, RegOpenKeyExW, OpenProcessToken, RegSetValueExW,
GetNamedSecurityInfoW, AccessCheck, RegCloseKey, SetNamedSecurityInfoW, AllocateAndInitializeSid,
EqualSid, ConvertStringSecurityDescriptorToSecurityDescriptorW, RegOpenKeyW, RegEnumKeyW, GetAce,
RegGetValueA, RegDeleteKeyA, RegFlushKey, RegDeleteValueA, RegSetValueExA, RegCreateKeyExA,
RegQueryValueExA, RegOpenKeyExA, SetSecurityDescriptorDacl, InitializeSecurityDescriptor, RegGetValueW,
SetEntriesInAclA, GetUserNameW
```

### SHELL32.dll (14)
```
ShellExecuteW, SHGetSpecialFolderPathW, CommandLineToArgvW, DragQueryFileW, SHCreateShellItem,
SHGetMalloc, ExtractAssociatedIconW, SHBrowseForFolderW, SHGetKnownFolderPath, SHParseDisplayName,
SHGetPathFromIDListW, ShellExecuteExW, ShellExecuteExA, ShellExecuteA
```

### USER32.dll (125)
```
EndPaint, BeginPaint, GetCursorPos, SetCursorPos, DestroyWindow, InvalidateRect, ReleaseCapture,
GetParent, SendInput, SetWindowLongPtrW, CreateWindowExW, GetMessageW, RegisterClassExW,
DispatchMessageW, PeekMessageW, EnumWindows, SetFocus, SendNotifyMessageW, TranslateMessage,
GetWindowTextW, GetWindowThreadProcessId, AttachThreadInput, GetDC, ReleaseDC, DefWindowProcW,
PostMessageW, SendMessageTimeoutW, GetWindowLongPtrW, SystemParametersInfoW, EnableMenuItem,
GetDesktopWindow, ShowCaret, DrawIconEx, UpdateLayeredWindow, GetClientRect, SetWindowLongW,
SetCursor, ToUnicode, SetClipboardData, SetWindowsHookExW, SetCapture, DestroyCaret, LoadCursorW,
GetFocus, GetAncestor, UnregisterClassW, GetWindow, ShowCursor, LoadIconW, LoadImageA, GetWindowLongA,
SetWindowTextA, EnumDisplaySettingsA, SendMessageA, GetWindowLongPtrA, IsIconic, CreateWindowExA,
wsprintfW, FindWindowA, GetWindowTextA, EnumDisplayDevicesA, MessageBoxA, UnregisterDeviceNotification,
RegisterDeviceNotificationW, FindWindowW, LoadStringW, WindowFromDC, AdjustWindowRectEx, SetRect,
EnumDisplaySettingsExW, EnumDisplayDevicesW, FindWindowExA, CallWindowProcW, MoveWindow, SetParent,
SetForegroundWindow, GetWindowLongW, RegisterClipboardFormatW, GetSystemMenu, GetMessageExtraInfo,
GetUpdateRgn, GetMessagePos, MapVirtualKeyW, GetWindowRect, IsWindowVisible, SetWindowPos, MessageBoxW,
MonitorFromWindow, EnumChildWindows, EnumDisplayMonitors, FillRect, GetIconInfo, SendMessageW,
CallNextHookEx, EndDialog, SetWindowTextW, MessageBeep, WindowFromPoint, GetWindowPlacement,
DestroyCursor, GetKeyboardState, SetCaretPos, GetActiveWindow, ShowWindow, IsWindow, GetAsyncKeyState,
OpenClipboard, GetCapture, RedrawWindow, DestroyIcon, GetWindowInfo, GetMonitorInfoW, CreateIconIndirect,
CloseClipboard, EmptyClipboard, IsChild, CreateCaret, MapWindowPoints, TrackMouseEvent,
GetForegroundWindow, UnhookWindowsHookEx, GetMessageTime, SetLayeredWindowAttributes, BringWindowToTop,
GetClipboardData
```

(KERNEL32.dll 229 funcs is not in the requested set; full list in `state/tmp/imports.txt`.)

## 6. Delay imports

**None.** objdump -p Data Directory Entry 13 (Delay Import Directory) = RVA 0 size 0:
```
Entry d 0000000000000000 00000000 Delay Import Directory
```
and `grep -c "Delay Import" state/tmp/arena-p.txt` finds no interpreted delay-import section.
Bound Import Directory is also 0. All 1224 imports are in the regular static import table.

## 7. Embedded manifest (RT_MANIFEST, resource type 0x18)

Resource tree (`objdump -p`): type 0x18 (RT_MANIFEST) id 1 lang 0x409, leaf RVA 0x38dcf18 size 0x5e2.
Extracted bytes: `state/tmp/manifest.xml` (1503 chars). Full content:

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
<assemblyIdentity type="win32" name="Resolume Arena" version="7.28.0.0">
</assemblyIdentity>
<description>Resolume Arena</description>
<dependency>
<dependentAssembly>
<assemblyIdentity type="Win32" name="Microsoft.Windows.Common-Controls" version="6.0.0.0" processorArchitecture="*" publicKeyToken="6595b64144ccf1df" language="*">
</assemblyIdentity>
</dependentAssembly>
</dependency>
<trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
<security>
<requestedPrivileges>
<requestedExecutionLevel level="asInvoker" uiAccess="false">
</requestedExecutionLevel>
</requestedPrivileges>
</security>
</trustInfo>
<application xmlns="urn:schemas-microsoft-com:asm.v3">
<windowsSettings>
<dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true</dpiAware>
<heapType xmlns="http://schemas.microsoft.com/SMI/2020/WindowsSettings">SegmentHeap</heapType>
</windowsSettings>
</application>
<ms_compatibility:compatibility xmlns:ms_compatibility="urn:schemas-microsoft-com:compatibility.v1" xmlns="urn:schemas-microsoft-com:compatibility.v1">
<ms_compatibility:application xmlns:ms_compatibility="urn:schemas-microsoft-com:compatibility.v1">
<ms_compatibility:supportedOS xmlns:ms_compatibility="urn:schemas-microsoft-com:compatibility.v1" Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}">
</ms_compatibility:supportedOS>
</ms_compatibility:application>
</ms_compatibility:compatibility>
</assembly>
```
(Verbatim bytes from `state/tmp/manifest.xml`; line breaks inserted after every `>` of the original
single-line file, no bytes dropped outside the BOM.)

- `requestedExecutionLevel level="asInvoker" uiAccess="false"` → no elevation/UAC.
- `dpiAware = true` (2005 SMI). **No `dpiAwareness` element** and no PerMonitorV2 setting.
- `heapType = SegmentHeap` (SMI/2020).
- `supportedOS` GUID `{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}` = Windows 10/11 only (no Win7/8/8.1 GUIDs).
- Dependency `Microsoft.Windows.Common-Controls` v6.0.0.0, token `6595b64144ccf1df` → this is what makes
  the `COMCTL32 ordinal 345` import (TaskDialogIndirect) resolvable (see §9).

## 8. Version info (RT_VERSION, resource type 0x10)

Leaf RVA 0x3865610 size 0x2e8; extracted to `state/tmp/version.bin`. StringFileInfo 040904e4:
```
CompanyName      Resolume B.V.
FileDescription  Resolume Arena
FileVersion      7.28.0.24303
InternalName     arena
LegalCopyright   Copyright (c) 2001-2026 Resolume B.V.
OriginalFilename Arena.exe
ProductName      Resolume Arena
ProductVersion   7.28.0
```
(ProductVersion here is "7.28.0" while the manifest assembly version is "7.28.0.0".)

## 9. Wine export cross-check (failure prediction, measured against wine-11.18 specs)

Method: for each imported (by name or ordinal), verified presence in
`wine/wine-11.18/dlls/<stem>/<stem>.spec` (definitive script `state/tmp/checkfinal.py`; ordinals mapped via
spec). Result — output of `python3 state/tmp/checkfinal.py`:
```
SETUPAPI OK   SHLWAPI OK   WINMM OK   WSOCK32 OK   CRYPT32 OK   WS2_32 OK   OPENGL32 OK
KERNEL32 OK   USER32 OK    GDI32 OK   COMDLG32 OK  ADVAPI32 OK  SHELL32 OK  ole32 OK
OLEAUT32 OK   d3d11 OK     dxgi OK    VERSION OK   MSVCP140 OK  MSWSOCK OK  WININET OK
IMM32 OK      MFPlat OK    MF OK      WINTRUST OK  VCRUNTIME140 OK  VCRUNTIME140_1 OK
api-ms-win-crt-* (11 apisets -> ucrtbase) all OK      IPHLPAPI OK
COMCTL32.dll   MISSING(1): ord345
```
i.e. **every import resolves against Wine 11.18 except `COMCTL32.dll` ordinal 345.**

- OPENGL32/MF/MFPlat/SETUPAPI/WINTRUST/CRYPT32/WININET/IPHLPAPI/MSWSOCK/WS2_32/WSOCK32/IMM32/GDI32/
  USER32/COMCTL32(names)/COMDLG32/SHLWAPI/VERSION/WINMM/OLEAUT32/ADVAPI32/SHELL32/ole32/d3d11/dxgi:
  all names present.
  - `MF.dll`/`MFPlat.DLL` functions are real `stdcall` implementations in
    `wine-11.18/dlls/mf/mf.spec` / `mfplat.spec` (not stubs) — MF (media session / sample grabber) exists.
- **COMCTL32 ordinal 345**: absent from the baseline `dlls/comctl32/comctl32.spec`. That spec pins ordinals
  `...320-342, 350-377, 382-421...` — it omits 344, 345, 380, 381. Ordinal 345 is present only in
  `dlls/comctl32_v6/comctl32_v6.spec` line `345 stdcall -ordinal TaskDialogIndirect(ptr ptr ptr ptr)`
  (v6 also adds 344, 380, 381). This patched Wine tree builds a separate `comctl32_v6.dll`
  (PARENTSRC=../comctl32, version 6.0.2600.2982, `VER_INTERNALNAME_STR=comctl32.dll`) carrying
  `comctl32.manifest` that advertises `Microsoft.Windows.Common-Controls` v6.0.2600.2982 token
  6595b64144ccf1df — matching the app manifest.
  → Ordinal 345 resolution depends on Wine's SxS/activation-context selecting comctl32_v6; if it does,
  TaskDialogIndirect loads. [INFERENCE on the selection path; the export is measured present in comctl32_v6.]
- UCRT apisets (`api-ms-win-crt-*`) and `api-ms-win-core-synch-l1-2-0`: no separate `.spec`; Wine resolves
  these via the apiset schema. All 11 crt apisets' names verified present in `dlls/ucrtbase/ucrtbase.spec`
  (e.g. `sinf`, `malloc`, `__stdio_common_vfprintf`, `_register_onexit_function`), and the 3 synch names
  (`WaitOnAddress`, `WakeByAddressAll`, `WakeByAddressSingle`) in `dlls/kernelbase/kernelbase.spec`.
- `MSVCP140.dll`/`VCRUNTIME140.dll`/`VCRUNTIME140_1.dll`: Wine ships builtins
  (`dlls/msvcp140`, `dlls/vcruntime140`); all imported C++/runtime symbols verified present, including data
  exports `?cout@std@@3V...`, `?cerr@...`, locale `?id@?$numpunct@D@std@@2V0locale@2@A`,
  `?id@?$ctype@_W@std@@2V0locale@2@A`, `__C_specific_handler` and `__CxxFrameHandler4`. The 223-entry
  MSVCP140 import (STL std::string/iostream/regex/locale) is the largest non-system consumer.
- Bundled DLLs (must be loaded native, no Wine builtin): `Artnet.dll`, `Processing.NDI.Lib.x64.dll`,
  `avformat-61/avcodec-61/avutil-59/swscale-8.dll`, `WinSparkle.dll`, `libltc.dll` — all present in
  `installer/media_x/app/` next to Arena.exe.

## 10. Additional Wine-relevant header facts

- Windows version gating imports: `KERNEL32.VerifyVersionInfoW`, `VerSetConditionMask`, `GetVersion`,
  `IsProcessorFeaturePresent`, `GetNativeSystemInfo`, `GetSystemPowerStatus` (Wine will report its configured
  Windows version; min supported OS is Win10 per manifest).
- `KERNEL32` also imports `WerRegisterRuntimeExceptionModule`/`WerUnregisterRuntimeExceptionModule` (crash
  reporting via BugSplat).
- `K32EnumProcesses`, `CreateToolhelp32Snapshot`, `Process32First/Next`, `OpenProcess` (process enumeration).
- `SetThreadStackGuarantee`, `RtlVirtualUnwind`, `RtlLookupFunctionEntry`, `RtlCaptureContext` (x64 SEH/unwind)
  are in Wine kernel32 forwarded to ntdll.
- `DllCharacteristics` has no `GUARD_CF`: the Load Config directory is present (0x140) but CFG is not enabled.
- Authenticode security directory is non-empty (0x2960) — Wine's `WinVerifyTrust` on its own image will
  matter for the WINTRUST/CRYPT32 calls.
