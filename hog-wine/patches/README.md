# Wine patches used by this project

Every Wine patch used to make Hog PC run under Wine is in this directory, and all of them are applied to
`../wine-11.18` (verified: `patch -p1 -N --dry-run` reports "already applied" for each). The build tree
`../wine/wine-11.18` mirrors it, and `../wine-install` is the built result.

## Applied, in order

### `series/0001..0019` — the requested AutoCAD-on-Wine + Power BI-on-Wine base
Untouched copies of the two upstream patch directories are kept under `sources/`:
`sources/acad-wine-main/` (14 patches) and `sources/powerbi/` (5 patches). These are the patches the
owner asked to be applied, renumbered 0001–0019 in application order.

| # | file | touches | fixes |
|---|---|---|---|
| 0001 | `0001-wintrust-WTD_CHOICE_BLOB-and-RFC3161-timestamp.patch` | `dlls/wintrust/softpub.c` | `WinVerifyTrust(WTD_CHOICE_BLOB)` + RFC3161 counter-signature time extraction |
| 0002 | `0002-kernelbase-regf-hive-RegLoadAppKey.patch` | `dlls/kernelbase/registry.c` | `RegLoadAppKey` + a binary `regf` hive reader |
| 0003 | `0003-urlmon-MapUrlToZone-res-scheme-empty-host.patch` | `dlls/urlmon/sec_mgr.c` | `MapUrlToZone` for `res://` with an empty host |
| 0004 | `0004-services-session-0.patch` | `server/mapping.c`, `server/process.c` | services.exe and its children run in session 0 |
| 0005 | `0005-ws2_32-windows-hosts-file.patch` | `dlls/ws2_32/protocol.c` | resolver reads the *Windows* hosts file |
| 0006 | `0006-crypt32-group-policy-enterprise-stores.patch` | `dlls/crypt32/store.c` | group-policy / enterprise certificate stores exist |
| 0007 | `0007-server-completion-info-non-overlapped.patch` | `server/fd.c` | `NtSetInformationFile(FileCompletionInformation)` on non-overlapped handles |
| 0008 | `0008-ntdll-fd-backed-pipe-semantics.patch` | `dlls/ntdll/unix/file.c` | Windows pipe semantics on inherited fd-backed pipes |
| 0009 | `0009-missing-exports-fls-cet-longpaths-zt.patch` | `kernelbase`, `ntdll`, `dnsapi` | exported symbols Windows has (`FlsGetValue2`, `IsUserCetAvailableInEnvironment`, …) |
| 0010 | `0010-ws2_32-NS_NLA-lookups.patch` | `dlls/ws2_32/protocol.c` | `WSALookupService*` for `NS_NLA` |
| 0011 | `0011-winex11-ignore-stale-window-errors.patch` | `dlls/winex11.drv/x11drv_main.c` | ignore stale `BadWindow` instead of aborting |
| 0012 | `0012-secur32-GetUserNameExW-NameUserPrincipal-NameDnsDomain.patch` | `dlls/secur32/secur32.c` | `GetUserNameExW` `NameUserPrincipal`/`NameDnsDomain` |
| 0013 | `0013-msiexec-Windows-command-line-parsing.patch` | `programs/msiexec/msiexec.c` | Windows-rule command-line/property parsing |
| 0014 | `0014-ntdll-actctx-probing-privatePath.patch` | `dlls/ntdll/actctx.c` | SxS `<probing privatePath>` from `<exe>.config` |
| 0015 | `0015-wintypes-winrt-metadata-resolution.patch` | `dlls/wintypes/main.c` | `RoResolveNamespace` / `RoGetMetaDataFile` |
| 0016 | `0016-ntdll-NtImpersonateAnonymousToken.patch` | `dlls/ntdll/unix/security.c` | `NtImpersonateAnonymousToken` |
| 0017 | `0017-secur32-negotiate-spnego.patch` | `programs/lsass/negotiate.c` | RFC 4178 SPNEGO in the `Negotiate` SSP |
| 0018 | `0018-secur32-LsaFreeReturnBuffer.patch` | `dlls/secur32/lsa.c` | `LsaFreeReturnBuffer` returns `STATUS_SUCCESS` |
| 0019 | `0019-oledb32-DataConvert-VARIANT-I8-and-BOOL.patch` | `dlls/oledb32/convert.c` | `DataConvert` for `VARIANT → DBTYPE_I8/BOOL` |

### `local/0100..0103` — `0100`–`0102` written in the sibling projects and reused here (as the owner suggested), `0103` written here
| file | touches | fixes | first written & verified in |
|---|---|---|---|
| `0100-msi-class-registry-view.patch` | `dlls/msi/classes.c` | `ACTION_RegisterClassInfo`/`UnregisterClassInfo` chose the registry view from the **package** platform instead of the **per-component** `msidbComponentAttributes64bit` flag, so a 32-bit component overwrote — and the rollback deleted — the system's 64-bit proxy-stub class (`{00020420-…}`), breaking InstallShield's `ISLockPermissionsInstall` (1603 → rollback). | `mastercam-wine` (observed `ISLockPermissionsInstall` failing, root-caused by decompiling the CA) |
| `0101-services-service-logon-token.patch` | `server/token.c`, `server/security.h`, `server/process.c`, `programs/services/services.c` | SCM-started services got the ordinary **interactive** token, so Go's `svc.IsAnInteractiveSession()` reported "interactive" and the service never called `StartServiceCtrlDispatcherW` (→ 1053 → MSI rollback). Gives session-0 children a service logon token (drop `S-1-5-4`, add `S-1-5-6`); also aligns `service_pipe_timeout` 10 s → 30 s. | `mastercam-wine` (CodeMeter's `CmWebAdmin.exe`) |
| `0102-iphlpapi-notify-interface-changes.patch` | `dlls/iphlpapi/iphlpapi_main.c` | `NotifyIpInterfaceChange` was a **stub** (`NO_ERROR`, `*handle = NULL`, callback never fired) and `NotifyUnicastIpAddressChange` a semi-stub that only delivered when `init_notify != 0`. Implemented on Wine's existing NSI change-notification plumbing, with `CancelMibChangeNotify2`. | `eos-wine` (Eos registers for network changes during ACN discovery) |
| `0103-win32u-initial-client-paint.patch` | `dlls/win32u/window.c` | A newly shown window only got `WM_NCPAINT`/`WM_ERASEBKGND`; the client `WM_PAINT` is synthesised by the server only when the thread's queue is otherwise empty, so an app with a busy event loop never receives its first paint (Hog's `Processor` window stayed at the class background). Invalidates the whole client area and updates it during the show transition. | `hog-wine` (this project; see `docs/INITIAL_PAINT_PATCH.md`) |

## Not applied — reference only
`sources/resolume-local/0100-dxgi-output-WaitForVBlank.patch` — the Resolume project's `IDXGIOutput::
WaitForVBlank` fix. Kept for reference because it is a real Wine bug and a plausible future need, but it
is **not** part of this project's series and is not applied.

## Reproduce
```sh
cd ..            # project root
tools/apply_patches.sh wine-11.18        # series + local, in filename order, forward-only (-N)
tools/apply_patches.sh wine/wine-11.18   # after the build tree exists
tools/build_wine.sh --jobs 8             # configure --enable-archs=i386,x86_64 && make && make install
```
