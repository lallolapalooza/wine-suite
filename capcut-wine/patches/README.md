# Patches

```
series/    the shared base series, applied in order 0001..0025 to pristine wine-11.18
local/     CapCut-exclusive patches, numbered from 0026 (empty so far — see below)
sources/   untouched copies of every donor patch directory, so provenance is auditable offline
SERIES.tsv new number -> origin -> source patch -> subject
debug-only/ the bcrypt key-dump patch, deliberately NOT applied (it prints secrets, changes no behaviour)
```

## Applying

```bash
tar -xf wine-11.18.tar.xz && cd wine-11.18
for p in ../patches/series/*.patch; do patch -p1 -i "$p" || exit 1; done   # 31/31, verified
```

**Verified property:** applying all 31 patches to the pristine tarball reproduces
`wine/wine-11.18` byte-for-byte (checked with a `git worktree` of the pristine commit plus
`patch -p1` for every file in `series/`, then `diff -rq` against the working tree: no differences).
Last re-verified for 31 patches (pristine `2ca2d8f` worktree + `patch -p1` for all of `series/`,
`diff -rq --exclude=.git` against `git archive HEAD` = empty).

## The series

| # | origin | subject |
|---|---|---|
| 0001 | acad-wine-main | wintrust: `WTD_CHOICE_BLOB` buffers and RFC 3161 timestamp verification |
| 0002 | acad-wine-main | kernelbase: load binary regf hive files in `RegLoadAppKey` |
| 0003 | acad-wine-main | urlmon: keep the `res` scheme out of the empty-host `URLZONE_INVALID` rule |
| 0004 | acad-wine-main | wineserver: run the service manager and the services it starts in session 0 |
| 0005 | acad-wine-main | ws2_32: resolve names through the Windows hosts file |
| 0006 | acad-wine-main | crypt32: provide the group-policy and enterprise system certificate stores |
| 0007 | acad-wine-main | server: allow associating non-overlapped handles with a completion port |
| 0008 | acad-wine-main | ntdll: make handles on fd-backed Unix pipes behave like Windows pipes |
| 0009 | acad-wine-main | kernel32/kernelbase/ntdll/dnsapi: export the APIs the licensing and browser stacks probe |
| 0010 | acad-wine-main | ws2_32: answer Network Location Awareness (`NS_NLA`) lookups |
| 0011 | acad-wine-main | winex11: ignore `BadWindow`/`BadDrawable` X errors on every display connection |
| 0012 | acad-wine-main (+ powerbi 0005, identical hunks) | secur32: answer `GetUserNameExW`'s `NameUserPrincipal`/`NameDnsDomain` |
| 0013 | acad-wine-main | msiexec: parse the command line with the Windows rules |
| 0014 | acad-wine-main | ntdll/actctx: honour `<probing privatePath="...">` |
| 0015 | acad-wine-main (+ a `ntdll/tests/file.c` recovery) | tests: cover the series with Wine's own test suite |
| 0016 | powerbi | wintypes: resolve Windows Runtime type metadata |
| 0017 | powerbi | ntdll: implement `NtImpersonateAnonymousToken` |
| 0018 | powerbi | secur32: implement RFC 4178 SPNEGO in the `Negotiate` package |
| 0019 | powerbi | secur32: return an NTSTATUS from `LsaFreeReturnBuffer` |
| 0020 | powerbi | oledb32: convert `VARIANT` to `DBTYPE_I8`/`DBTYPE_BOOL` |
| 0021 | powerbi (+ union with acad 0017) | tests: cover the series with Wine's own test suite |
| 0022 | powerbi (reference tree only) | msxml3: implement `IVBMXNamespaceManager::reset` |
| **0023** | **revit-wine-main** | **dcomp: implement the device/target/visual objects, `Commit`, and the composition surface path** |
| **0024** | **revit-wine-main** | **dxgi: `CreateSwapChainForComposition` + per-present compositing + a GDI-compatible back buffer that survives `ResizeBuffers`** |
| 0025 | revit-wine-main | ncrypt: import ECC key blobs |
| 0026 | capcut-wine (general Wine gap found via CapCut) | wbemdisp: implement the SWbemDateTime scripting object |
| 0027 | capcut-wine (general Wine gap found via CapCut) | advapi32/sechost: place `EnumServicesStatusEx` strings at the end of the caller's buffer |
| **0028** | **capcut-wine (general D3D11 gap found via CapCut)** | **d3d11: only advertise `GDI_COMPATIBLE` for formats that support it, so an `R8G8B8A8` composition swap chain can be created** |
| 0029 | capcut-wine (extends the in-tree dxgi composition port, 0024) | dxgi: read a composition swap chain's buffer back through a staging texture when its format has no DDI format |
| **0030** | **capcut-wine (extends the in-tree dcomp/dxgi composition port, 0023/0024/0029)** | **dcomp: composite a composition swap chain through dxgi, including `R8G8B8A8`** |
| **0031** | **capcut-wine (general Wine gap found via CapCut)** | **ntdll/mountmgr: report the NTFS capabilities the emulation actually implements, and make the directory-handle and drive-root replies agree** |

0023/0024 are the load-bearing pair for CapCut: upstream wine-11.18's `dlls/dcomp` is a 47-line
`E_NOTIMPL` stub, and CapCut's Qt 6 D3D11 RHI renders its top-level windows through
DirectComposition. Without them the app's windows are created but never painted and the process exits
inside 30–45 s; with them the app paints its "Environment testing" window and then its real
"Terms of Service and Privacy Policy" dialog. `revit-wine-main` is the donor: it needed the same pair
for Chromium/WebView2, which drives DirectComposition itself and `CHECK_EQ`s on `IDCompositionVisual3`.

`0026` and `0027` were written for this project: both are **general Wine gaps** that CapCut was the first
to expose. `0027` fixes the crash that ended every run ~100 s after the home screen appeared. CapCut's
`metasecml.dll` enumerates the services with `EnumServicesStatusExA` and then walks the returned
`ENUM_SERVICE_STATUS_PROCESSA` array with a 0x38 stride until an entry's `lpServiceName`/`lpDisplayName`
is NULL. Windows anchors the strings at the **end** of the caller's buffer and zeroes the space after the
array, so that walk stops at the terminator entry; Wine packed the strings immediately after the array, so
entry[returned] was the first service name ("Eventlog"), whose characters were then dereferenced as a
pointer (`strlen` on ASCII text) — `EXCEPTION_ACCESS_VIOLATION` at `metasecml.dll+0x29943`. The fix makes
`dlls/sechost`'s `EnumServicesStatusExW` and `dlls/advapi32`'s `EnumServicesStatusExA` place the strings at
the end of the caller's buffer and zero the gap, and Wine's `dlls/advapi32/tests/service.c` now pins both
the anchor and the zeroed gap for the A and the W call. Full evidence: `recon/CRASH100S.md`.

`0031` is also a general Wine gap, and it is **not** a fix for the "Project saved path not found" modal —
that modal did not reproduce on any run made while this patch was written, so it is closed as *not
reproducible* rather than fixed (`STATE.md` §49). What `0031` fixes is measurable on its own:
`GetVolumeInformationW` on an NTFS volume reported four capability bits (Windows reports 21), and the two
places that answer `FileFsAttributeInformation` — `dlls/ntdll/unix/file.c` for a directory handle and
`dlls/mountmgr.sys/device.c` for a drive root — did not even agree with each other
(`FILE_SUPPORTS_REPARSE_POINTS` was set only for a drive root). The patch adds the three capabilities the
NTFS emulation actually implements (`FILE_CASE_SENSITIVE_SEARCH`, `FILE_UNICODE_ON_DISK`,
`FILE_SUPPORTS_HARD_LINKS`) and makes the two replies equal; the bits Windows sets for features Wine does
not implement (compression, quotas, sparse files, object ids, encryption, transactions, USN journal,
integrity streams, …) are deliberately left unset. The volume **serial** in the same reply is deliberately
unchanged — see the commit body and `STATE.md` §49: CapCut stores it as its `hid` machine id and re-runs
its first-run flow when the value changes. Wine's own tests pin the flags in both paths
(`dlls/ntdll/tests/file.c` and `dlls/kernel32/tests/volume.c`: 3 failures each before, 0 after).

## local/ — CapCut-exclusive patches

**Empty, and that is still the honest result:** every patch so far, including 0028/0029/0030/0031, is a
general Wine gap (0028 is a D3D11 rule about `D3D11_RESOURCE_MISC_GDI_COMPATIBLE`, 0029 and 0030
extend the dxgi/dcomp composition port that revit-wine-main donated as 0023/0024, and 0031 is the NTFS
capability bitmap of `FileFsAttributeInformation`).  See `STATE.md` §35 and §38 for the measurements.
A patch belongs here only once an app-exclusive defect is measured. (The `SWbemDateTime` gap was
found via CapCut but is a **general Wine gap** — every WMI-scripting consumer hits it — so it lives
in `series/0026`, not here; the same is true of `series/0027`, the `EnumServicesStatusEx` string
placement.) Candidates, with their evidence:

* the EffectSDK's failure to load ANGLE as `ve_detector/libEGL.dll` under Wine, while the Windows
  guest loads it with **no `ve_detector` directory anywhere** and logs no EGL error at all
  (`recon/GUEST_CAPTURE.md` items 1–3; `recon/RE_VEDETECTOR.md`) — mechanism still open;
* the adapter identity Wine reports (`Intel(R) HD Graphics 4000` / `NVIDIA GeForce GTX 470` from
  `dlls/wined3d/directx.c`'s card table, newest Intel entry UHD 630) against the real
  Meteor Lake `8086:7d55`, which makes CapCut take a different renderer branch than on Windows
  (`sequence_check_result` 1 vs 0, `hw_render` 1 vs 0).

Both are recorded in `STATE.md` §16–§20 with the measurements behind them.
