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
