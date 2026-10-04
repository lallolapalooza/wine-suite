#!/usr/bin/env python3
"""Fill the generated tables into docs/QT_CHROMIUM_SOURCE.md."""
import csv
import json
import os
import sys

BASE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs")
DOC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(BASE, "QT_CHROMIUM_SOURCE.md")
QT = json.load(open(BASE + "/_qt_win32_index.json"))
CH = json.load(open(BASE + "/_chromium_win32_index.json"))
BODY = list(csv.DictReader(open(BASE + "/_wine_impl_audit_all.tsv"), delimiter="\t"))
# acceptable no-op bodies (not real gaps)
BENIGN = {"AllowSetForegroundWindow", "GdiDllInitialize", "ImmReleaseContext",
          "UiaClientsAreListening"}

QT_GROUPS = [
    ("Window, input, DPI (user32 / shcore)", [
        "CreateWindowExW", "RegisterClassExW", "DefWindowProcW", "DestroyWindow",
        "SetWindowLongPtrW", "GetWindowLongPtrW", "AdjustWindowRectEx",
        "SetWindowPos", "MoveWindow", "GetMonitorInfoW", "EnumDisplayMonitors",
        "GetSystemMetrics", "SystemParametersInfoW", "GetSysColorBrush",
        "SetCapture", "ReleaseCapture", "TrackMouseEvent", "GetKeyState",
        "MapVirtualKeyW", "ToUnicodeEx", "GetKeyboardLayout",
        "RegisterTouchWindow", "IsTouchWindow", "GetPointerInfo",
        "GetPointerTouchInfo", "GetDC", "ReleaseDC", "SetForegroundWindow",
        "AttachThreadInput", "MsgWaitForMultipleObjectsEx", "PeekMessageW",
        "DispatchMessageW", "PostMessageW", "SendMessageW", "PostQuitMessage",
        "GetMessageW", "GetDpiForMonitor", "SetProcessDpiAwareness",
        "SetProcessDPIAware", "GetProcessDpiAwareness",
        "SetDisplayAutoRotationPreferences", "UnregisterPowerSettingNotification",
        "ChangeWindowMessageFilterEx"]),
    ("GDI, fonts, DirectWrite (gdi32 / dwrite)", [
        "CreateDCW", "CreateCompatibleDC", "CreateCompatibleBitmap",
        "CreateDIBSection", "BitBlt", "GetDIBits", "SelectObject", "DeleteObject",
        "CreateFontIndirectW", "EnumFontFamiliesExW", "GetGlyphOutline",
        "GetTextMetricsW", "GetTextExtentPoint32W", "AddFontMemResourceEx",
        "RemoveFontMemResourceEx", "AddFontResourceExW", "RemoveFontResourceExW",
        "GetDeviceCaps", "GetStockObject", "DWriteCreateFactory"]),
    ("OpenGL / ANGLE / D3D (opengl32 / d3d11 / dxgi / d3d9 / dcomp)", [
        "wglCreateContext", "wglMakeCurrent", "wglGetProcAddress",
        "wglDeleteContext", "wglShareLists", "wglSwapBuffers",
        "wglSetPixelFormat", "wglDescribePixelFormat", "ChoosePixelFormat",
        "SetPixelFormat", "DescribePixelFormat", "glGetString", "glGetIntegerv",
        "glGetError", "D3D11CreateDevice", "CreateDXGIFactory",
        "Direct3DCreate9", "Direct3DCreate9Ex", "DCompositionCreateDevice",
        "D3DPERF_BeginEvent", "D3DPERF_EndEvent", "D3DPERF_SetMarker",
        "D3DPERF_GetStatus"]),
    ("Clipboard, DnD, OLE, shell (ole32 / shell32 / comdlg32 / dwmapi)", [
        "OleInitialize", "OleUninitialize", "CoInitializeEx", "CoUninitialize",
        "CoCreateInstance", "DoDragDrop", "RegisterDragDrop", "RevokeDragDrop",
        "OleGetClipboard", "OleSetClipboard", "OleIsCurrentClipboard",
        "OleFlushClipboard", "ReleaseStgMedium", "ShellExecuteW",
        "Shell_NotifyIcon", "Shell_NotifyIconGetRect", "SHGetFileInfo",
        "SHGetKnownFolderIDList", "SHGetPathFromIDList", "SHGetStockIconInfo",
        "SHCreateItemFromParsingName", "SHBrowseForFolder", "SHFileOperation",
        "GetOpenFileNameW", "GetSaveFileNameW", "ChooseColorW", "ChooseFontW",
        "DwmEnableBlurBehindWindow", "DwmSetWindowAttribute",
        "DwmIsCompositionEnabled", "DwmGetWindowAttribute"]),
    ("Process, threads, files, pipes (kernel32)", [
        "CreateProcessW", "CreateFileW", "ReadFile", "WriteFile",
        "CreateNamedPipeW", "ConnectNamedPipe", "PeekNamedPipe",
        "CreateEventW", "CreateEventExW", "CreateSemaphoreW", "CreateSemaphoreExW",
        "CreateThread", "CloseHandle", "DuplicateHandle", "CancelIoEx",
        "GetOverlappedResult", "DeviceIoControl", "FindFirstFileExW",
        "FindNextFileW", "FindClose", "FindFirstChangeNotificationW",
        "FindNextChangeNotification", "GetFileInformationByHandle",
        "GetFileAttributesExW", "DeleteFileW", "MoveFileExW",
        "CreateDirectoryW", "RemoveDirectoryW", "GetModuleFileNameW",
        "LoadLibraryW", "LoadLibraryExW", "GetProcAddress", "FreeLibrary",
        "GetSystemTimeAsFileTime", "QueryPerformanceCounter",
        "QueryPerformanceFrequency", "InitializeCriticalSection",
        "EnterCriticalSection", "LeaveCriticalSection",
        "SleepConditionVariableCS", "WakeAllConditionVariable",
        "WakeConditionVariable", "FormatMessageW", "SetErrorMode",
        "SetThreadErrorMode", "GetSystemInfo", "GlobalMemoryStatusEx",
        "GetEnvironmentVariableW", "SetEnvironmentVariableW", "GetLastError",
        "WaitForSingleObject", "WaitForMultipleObjects", "CreateFileMappingW",
        "MapViewOfFile", "UnmapViewOfFile", "OpenFileMappingW",
        "CreateToolhelp32Snapshot"]),
    ("Registry, tokens (advapi32)", [
        "RegOpenKeyExW", "RegQueryValueExW", "RegSetValueExW", "RegCreateKeyExW",
        "RegEnumKeyExW", "RegCloseKey", "RegGetValueW", "RegQueryInfoKeyW",
        "OpenProcessToken", "GetTokenInformation"]),
    ("Network: sockets, interfaces, DNS, proxy (ws2_32 / iphlpapi / dnsapi / winhttp / netapi32)", [
        "WSASocketW", "WSAIoctl", "WSAAsyncSelect", "WSAConnect", "WSAAccept",
        "WSARecv", "WSASend", "WSARecvFrom", "WSASendTo", "WSAGetLastError",
        "bind", "listen", "closesocket", "getpeername", "getsockname",
        "getsockopt", "setsockopt", "getaddrinfo", "freeaddrinfo", "getnameinfo",
        "WSAHtonl", "WSANtohl", "WSANtohs", "GetAdaptersAddresses",
        "GetNetworkParams", "ConvertInterfaceIndexToLuid",
        "ConvertInterfaceLuidToGuid", "ConvertInterfaceLuidToIndex",
        "ConvertInterfaceLuidToNameW", "ConvertInterfaceNameToLuidW",
        "DnsQuery_W", "DnsRecordListFree", "WinHttpOpen",
        "WinHttpGetProxyForUrl", "WinHttpGetDefaultProxyConfiguration",
        "WinHttpGetIEProxyConfigForCurrentUser", "WinHttpCloseHandle",
        "NetShareEnum", "NetApiBufferFree", "WTSQuerySessionInformationW",
        "WTSFreeMemory", "GetUserProfileDirectoryW"]),
    ("TLS / Schannel and crypto (secur32 / crypt32 / bcrypt)", [
        "AcquireCredentialsHandleW", "InitializeSecurityContextW",
        "QueryContextAttributesW", "EncryptMessage", "DecryptMessage",
        "FreeContextBuffer", "DeleteSecurityContext", "FreeCredentialsHandle",
        "ApplyControlToken", "CompleteAuthToken", "AcceptSecurityContext",
        "InitSecurityInterfaceW", "CertOpenStore", "CertOpenSystemStoreW",
        "CertFindCertificateInStore", "CertFindChainInStore",
        "CertGetCertificateChain", "CertFreeCertificateChain",
        "CertFreeCertificateContext", "CertCloseStore",
        "CertCreateCertificateContext", "CertDuplicateCertificateContext",
        "CertAddCertificateContextToStore", "CertAddStoreToCollection",
        "CertVerifyTimeValidity", "PFXImportCertStore",
        "BCryptOpenAlgorithmProvider", "BCryptCloseAlgorithmProvider",
        "BCryptSetProperty", "BCryptGenerateSymmetricKey", "BCryptEncrypt",
        "BCryptDecrypt", "BCryptDestroyKey"]),
    ("Text input, tablet, accessibility (imm32 / wintab32 / uiautomationcore)", [
        "ImmGetContext", "ImmReleaseContext", "ImmGetCompositionString",
        "ImmSetCompositionWindow", "ImmSetCandidateWindow", "ImmNotifyIME",
        "ImmAssociateContext", "ImmAssociateContextEx", "ImmGetDefaultIMEWnd",
        "ImmGetOpenStatus", "ImmGetVirtualKey", "WTOpenW", "WTClose", "WTInfoW",
        "WTGetW", "WTEnable", "WTOverlap", "WTPacketsGet", "WTQueueSizeGet",
        "WTQueueSizeSet", "UiaClientsAreListening", "UiaHostProviderFromHwnd",
        "UiaRaiseAutomationEvent", "UiaRaiseAutomationPropertyChangedEvent",
        "UiaRaiseNotificationEvent", "UiaReturnRawElementProvider"]),
    ("SQL drivers (odbc32 — indexed, but qsqlite-only install)", [
        "SQLAllocHandle", "SQLDriverConnect", "SQLExecDirect", "SQLFetch",
        "SQLGetData", "SQLGetDiagRec", "SQLDescribeCol", "SQLNumResultCols",
        "SQLRowCount", "SQLSetConnectAttr", "SQLSetEnvAttr", "SQLFreeHandle",
        "SQLDisconnect", "SQLPrepare", "SQLBindParameter", "SQLEndTran",
        "SQLMoreResults", "SQLColumns", "SQLTables", "SQLPrimaryKeys",
        "SQLSpecialColumns", "SQLGetTypeInfo", "SQLGetInfo", "SQLGetFunctions",
        "SQLGetStmtAttr", "SQLSetStmtAttr", "SQLColAttribute", "SQLCloseCursor",
        "SQLExecute", "SQLFetchScroll"]),
]


def qsite(d):
    if d["qt_sites"]:
        s = d["qt_sites"][0]
        return "%s:%d" % (s["file"], s["line"]), s["text"]
    if d["dynamic_sites"]:
        s = d["dynamic_sites"][0]
        return "%s:%d *(dynamic)*" % (s["file"], s["line"]), s["text"]
    return "-", ""


def status(d):
    st = d["wine_status"]
    if st == "absent":
        st = "**absent**"
    elif st == "stub":
        st = "**stub**"
    if d.get("crt_fallback"):
        st += " (CRT)"
    return st


def esc(s):
    return s.replace("|", "\\|")


out = []
for title, keys in QT_GROUPS:
    rows = []
    for k in keys:
        d = QT.get(k)
        if not d:
            continue
        loc, text = qsite(d)
        exp = d["expect"] or ("`" + text + "`")
        rows.append("| `%s` | %s | %s | %s | %s |" %
                    (k, d["wine_dll"] or ",".join(d["wine_dlls"]), status(d),
                     loc, esc(exp)))
    if rows:
        out.append("#### " + title + "\n")
        out.append("| Win32 API | Wine DLL | Wine status | Qt source | What Qt expects |")
        out.append("|---|---|---|---|---|")
        out.extend(rows)
        out.append("")
QT_CORE_TABLE = "\n".join(out)

qstat = {}
for d in QT.values():
    qstat[d["wine_status"]] = qstat.get(d["wine_status"], 0) + 1
STATS_QT = ("%d APIs referenced from 386 Qt files, resolved against Wine: %s; "
            "%d APIs also have a dynamic (`resolve`/`GetProcAddress`) site, "
            "%d are reached only dynamically."
            % (len(QT),
               ", ".join("%d %s" % (v, k) for k, v in sorted(qstat.items())),
               sum(1 for d in QT.values() if d["dynamic_sites"]),
               sum(1 for d in QT.values() if d["dynamic_sites"] and not d["qt_sites"])))

STATS_WINE_SPEC = ("no Qt-referenced API sits behind a Wine `@ stub`; the single "
                   "flagged symbol is `SkipPointerFrameMessages`, which has no "
                   "named export at all (commented-out `@ stub`).")

real_body = [b for b in BODY if b["api"] not in BENIGN]
STATS_WINE_BODY = ("%d Wine functions are body-only stubs, %d of them real gaps "
                   "(the rest are unconditional-success no-ops)" %
                   (len(BODY), len(real_body)))

rows = ["| API | Wine implementation | Body (evidence) | Call site | Surface |",
        "|---|---|---|---|---|"]
for b in BODY:
    api = b["api"]
    if api in QT:
        loc, _ = qsite(QT[api])
        surface = "Qt"
    elif api in CH:
        s = CH[api]["sites"][0]
        loc = "%s:%d" % (s["file"], s["line"])
        surface = "Chromium"
    else:
        loc, surface = "-", "?"
    if api in BENIGN:
        surface += " (no-op, acceptable)"
    rows.append("| `%s` | `%s:%s` | `%s` | %s | %s |" %
                (api, b["file"], b["line"], esc(" ".join(b["body"].split())[:110]),
                 loc, surface))
WINE_BODY_TABLE = "\n".join(rows)

# ---- Chromium -------------------------------------------------------------
chstat = {}
for d in CH.values():
    chstat[d["wine_status"]] = chstat.get(d["wine_status"], 0) + 1

CH_FAMILIES = {
    "Job objects / process launch": ["CreateJobObjectW", "AssignProcessToJobObject",
        "SetInformationJobObject", "QueryInformationJobObject", "IsProcessInJob",
        "CreateProcessW", "CreateProcessAsUserW", "OpenProcess", "TerminateProcess",
        "GetExitCodeProcess", "WaitForSingleObject", "WaitForMultipleObjects",
        "ResumeThread", "SetPriorityClass"],
    "Sandbox: tokens, desktops, AppContainer": ["CreateRestrictedToken",
        "SetTokenInformation", "GetTokenInformation", "OpenProcessToken",
        "DuplicateTokenEx", "CreateWindowStationW", "OpenWindowStationW",
        "SetProcessWindowStation", "GetProcessWindowStation", "CreateDesktopW",
        "OpenDesktopW", "SetThreadDesktop", "OpenInputDesktop", "CloseDesktop",
        "CreateAppContainerProfile", "DeriveAppContainerSidFromAppContainerName",
        "DeleteAppContainerProfile", "GetAppContainerFolderPath",
        "GetAppContainerRegistryLocation", "CheckTokenMembership",
        "UserHandleGrantAccess", "SetProcessMitigationPolicy",
        "GetProcessMitigationPolicy"],
    "NT internals": ["NtQueryInformationProcess", "NtQueryObject",
        "NtSetInformationThread", "NtQuerySystemInformation",
        "NtQueryInformationThread", "NtOpenProcessTokenEx",
        "NtQueryVirtualMemory", "NtClose", "NtCreateFile"],
    "D3D / DXGI / DWrite / dbghelp": ["D3D11CreateDevice",
        "D3D11CreateDeviceAndSwapChain", "CreateDXGIFactory", "CreateDXGIFactory1",
        "CreateDXGIFactory2", "DWriteCreateFactory", "D3DCompile", "D3DCompile2",
        "Direct3DCreate9", "SymInitialize", "SymFromAddrW", "StackWalk64",
        "SymGetModuleBase64", "SymFunctionTableAccess64"],
    "Crypto (bcrypt/ncrypt/crypt32)": ["BCryptGenRandom",
        "BCryptOpenAlgorithmProvider", "BCryptCloseAlgorithmProvider",
        "BCryptGetProperty", "BCryptSetProperty", "BCryptCreateHash",
        "BCryptHashData", "BCryptFinishHash", "BCryptDestroyHash",
        "BCryptEncrypt", "BCryptDecrypt", "BCryptGenerateSymmetricKey",
        "BCryptDestroyKey", "BCryptImportKey", "BCryptExportKey",
        "NCryptOpenStorageProvider", "NCryptOpenKey", "NCryptDecrypt",
        "NCryptEncrypt", "NCryptFreeObject", "CryptGenRandom"],
    "WinHTTP / WinINet": ["WinHttpOpen", "WinHttpConnect", "WinHttpOpenRequest",
        "WinHttpSendRequest", "WinHttpReceiveResponse", "WinHttpQueryHeaders",
        "WinHttpReadData", "WinHttpWriteData", "WinHttpSetOption",
        "WinHttpQueryOption", "WinHttpCloseHandle", "WinHttpGetProxyForUrl",
        "InternetOpenW", "InternetConnectW", "InternetOpenUrlW"],
    "IPC / handles / threads": ["CreateEventW", "CreateEventExW", "CreateMutexW",
        "CreateSemaphoreW", "CreateIoCompletionPort", "GetQueuedCompletionStatus",
        "RegisterWaitForSingleObject", "DuplicateHandle", "CreateNamedPipeW",
        "ConnectNamedPipe", "CreateFileMappingW", "MapViewOfFile", "CreateThread",
        "SetThreadPriority", "GetCurrentThreadId", "GetThreadInformation"],
    "Files / paths / registry": ["CreateFileW", "ReadFile", "WriteFile",
        "GetFileAttributesExW", "GetFileInformationByHandleEx",
        "GetModuleFileNameW", "GetTempPathW", "RegOpenKeyExW", "RegQueryValueExW",
        "RegSetValueExW", "RegCloseKey"],
}

ch_rows = []
for title, keys in CH_FAMILIES.items():
    sub = []
    for k in keys:
        d = CH.get(k)
        if not d:
            continue
        s = d["sites"][0]
        sub.append("| `%s` | %s | %s | %s:%d |" %
                   (k, d["wine_dll"] or ",".join(d["wine_dlls"]),
                    d["wine_status"], s["file"], s["line"]))
    if sub:
        ch_rows.append("**" + title + "**\n")
        ch_rows.append("| Win32 API | Wine DLL | Wine status | Chromium 80.0.3987.163 |")
        ch_rows.append("|---|---|---|---|")
        ch_rows.extend(sub)
        ch_rows.append("")
CH_FULL = open(BASE + "/_chromium_win32_table.md").read().strip()
CH_TABLE = "\n".join(ch_rows) + "\n#### Full generated Chromium table\n\n" + CH_FULL

flagged = {k: d for k, d in CH.items() if d["wine_status"] in ("stub", "absent")}
for b in BODY:
    if b["api"] in CH and b["api"] not in flagged:
        flagged[b["api"]] = dict(CH[b["api"]])
        flagged[b["api"]]["wine_status"] = "body stub"
        flagged[b["api"]]["wine_raw"] = " ".join(b["body"].split())[:110]
        flagged[b["api"]]["wine_spec"] = "%s:%s" % (b["file"], b["line"])
        flagged[b["api"]]["wine_spec_line"] = ""
rows = ["| API | Wine status | Evidence | Chromium call site |", "|---|---|---|---|"]
for k, d in sorted(flagged.items()):
    ev = d.get("wine_raw") or "no export"
    spec = d.get("wine_spec") or ""
    ev = (spec + " " + ev).strip() if spec else ev
    st = d["wine_status"]
    if k in BENIGN and st == "body stub":
        st = "body stub (no-op, acceptable)"
    rows.append("| `%s` | %s | `%s` | %s:%d |" %
                (k, st, esc(ev),
                 d["sites"][0]["file"], d["sites"][0]["line"]))
CH_FLAGGED = ("%d APIs indexed from %d Chromium files at tag 80.0.3987.163; "
              "status counts: %s. The rows below are the ones that need Wine work "
              "(missing exports and FIXME-only bodies); everything else resolves to "
              "an implemented or forwarded Wine export.\n\n"
              % (len(CH), len(set(s["file"] for d in CH.values() for s in d["sites"])),
                 ", ".join("%d %s" % (v, k) for k, v in sorted(chstat.items())))
              + "\n".join(rows))

QT_FULL = open(BASE + "/_qt_win32_table.md").read().strip()

# Content keyed by region name; `None` means "inline, no surrounding newlines".
REGIONS = {
    "QT_CORE": "\n" + QT_CORE_TABLE + "\n",
    "QT_FULL": "\n" + QT_FULL + "\n",
    "WINE_BODY": (" **Qt and Chromium** surfaces — **%s**:\n\n%s\n"
                  % (STATS_WINE_BODY, WINE_BODY_TABLE)),
    "CHROMIUM_TABLE": "\n" + CH_TABLE + "\n",
    "CHROMIUM_FLAGGED": "\n" + CH_FLAGGED + "\n",
    "STATS_QT": STATS_QT,
    "STATS_DYN": ("%d APIs have a dynamic (`resolve`/`GetProcAddress`) site, "
                  "%d of which are reached *only* dynamically"
                  % (sum(1 for d in QT.values() if d["dynamic_sites"]),
                     sum(1 for d in QT.values()
                         if d["dynamic_sites"] and not d["qt_sites"]))),
    "STATS_WINE_SPEC": STATS_WINE_SPEC,
}
# placeholders used when the document is still a pristine template
PLACEHOLDERS = {
    "QT_CORE": "{{QT_CORE_TABLE}}", "QT_FULL": "{{QT_FULL_TABLE}}",
    "WINE_BODY": "{{WINE_BODY_TABLE}}", "CHROMIUM_TABLE": "{{CHROMIUM_TABLE}}",
    "CHROMIUM_FLAGGED": "{{CHROMIUM_FLAGGED}}", "STATS_QT": "{{STATS_QT}}",
    "STATS_WINE_SPEC": "{{STATS_WINE_SPEC}}",
}

doc = open(DOC).read()
for name, content in REGIONS.items():
    b, e = "<!--B:%s-->" % name, "<!--E:%s-->" % name
    if b in doc and e in doc:
        i = doc.index(b) + len(b)
        j = doc.index(e)
        doc = doc[:i] + content + doc[j:]
    elif PLACEHOLDERS[name] in doc:
        doc = doc.replace(PLACEHOLDERS[name], content)
    else:
        raise SystemExit("no marker or placeholder for region %s" % name)
open(DOC, "w").write(doc)
print("assembled %s; size=%d" % (DOC, len(doc)))
print(STATS_QT)
print(STATS_WINE_BODY)
