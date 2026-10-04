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
