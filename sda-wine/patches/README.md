# Wine patches used to run Steinberg Download Assistant 1.40.1 on Linux

Base: **Wine 11.18** (`/home/asdf/Downloads/wine-11.18.tar.xz`, dl.winehq.org).

```
patches/
  series/      shared base — AutoCAD-on-Wine (14) + Power BI-on-Wine (5) = 0001..0019
  local/       patches that exist *because of this app* (Steinberg Download Assistant)
  sources/     provenance copies of the imported patch sets (unmodified)
```

Applied in this order by `tools/apply_patches.sh`, then verified by
`tools/apply_patches.sh --check` (extracts a pristine tarball into `state/scratch/` and applies
the whole series for real, because a cumulative series cannot be validated patch-by-patch).

## `patches/series/` — shared base, NOT specific to SDA

Nineteen patches carried over from the AutoCAD-on-Wine and Power BI-on-Wine work. They are
general Wine-API fixes and are applied on request as the common base for this project; removing
them would not be expected to break SDA specifically.

| # | subject |
|---|---|
| 0001 | wintrust: accept `WTD_CHOICE_BLOB` and RFC3161 timestamp signatures |
| 0002 | kernelbase: `RegLoadAppKey` over a regf hive file |
| 0003 | urlmon: keep the `res` scheme out of the empty-host `URLZONE_INVALID` rule |
| 0004 | services: run the service manager and started services in session 0 |
| 0005 | ws2_32: resolve names through the Windows hosts file |
| 0006 | crypt32: provide the group-policy and enterprise system certificate stores |
| 0007 | server: allow non-overlapped handles to be associated with a completion port |
| 0008 | ntdll: make handles on fd-backed Unix pipes behave like Windows pipes |
| 0009 | kernel32/kernelbase/ntdll/dnsapi: export the APIs the licensing/browser stacks probe for |
| 0010 | ws2_32: answer Network Location Awareness (NS_LNA) lookups |
| 0011 | winex11: ignore `BadWindow`/`BadDrawable` X errors on every display connection |
| 0012 | secur32: `GetUserNameExW` `NameUserPrincipal`/`NameDnsDomain` from the domain |
| 0013 | msiexec: parse the command line with the Windows rules |
| 0014 | ntdll: activation-context probing `privatePath` |
| 0015 | wintypes: resolve Windows Runtime type metadata |
| 0016 | ntdll: implement `NtImpersonateAnonymousToken` |
| 0017 | secur32/lsass: RFC 4178 SPNEGO in `Negotiate` |
| 0018 | secur32: `LsaFreeReturnBuffer` |
| 0019 | oledb32: `IDataConvert` `VARIANT` -> `DBTYPE_I8`/`DBTYPE_BOOL` |

Provenance: `patches/sources/acad-wine-main/` and `patches/sources/powerbi/`; the union also
exists as `patches/sources/autocad2027-private-main/` (which additionally carries two
debug-only patches that are deliberately **not** applied).

## `patches/local/` — exclusive to Steinberg Download Assistant

### `0100-wine.inf-BuildLabEx-BuildLab.patch` — **required by SDA**

Wine's `loader/wine.inf.in` `[VersionInfo]` sets `CurrentVersion`, `CurrentMajorVersionNumber`,
`CurrentMinorVersionNumber`, `CurrentBuild`, `CurrentBuildNumber`, `UBR`, `CurrentType`,
`EditionId`, `InstallationType` and `ProductName` — but **no `BuildLab` and no `BuildLabEx`**
(tree-wide grep is empty). Windows sets both; on Windows 11 they read e.g.
`26100.1.amd64fre.ge_release.240331-1435`.

SDA reads `BuildLabEx` and uses it three ways
(`net.steinberg.elicenser.download.common.system.WindowsOsHelper`):
1. it logs it;
2. it puts it in the HTTP User-Agent as `OSVersion`;
3. **it decides `isWin64OS` from `buildLabEx.contains("amd64"|"arm64"|"wow64")` AND the presence
   of the `ProgramFiles(x86)` environment variable.**

With the value missing the app logs `Could not determine BuildLabEx from registry!`, computes
`isWin64OS = false`, determines its platform as `WIN32`, reports `OSBits:"32"`, marks the Windows
install helper `notAvailable` and *skips every runtime component gated on `[WIN64, WINARM64]`*.
This is also the still-unfixed WineHQ **bug 47598** ("Steinberg Download Assistant crashes" —
after the `packager` workaround the reporter lands on exactly this error).

The patch adds both values to `[VersionInfo]`, shaped exactly like Windows':
`BuildLab` = `19045.vb_release.191206-1406`, `BuildLabEx` = `19045.1.amd64fre.vb_release.191206-1406`
(consistent with Wine's own hardcoded `CurrentBuild` = 19045 / `ProductName` = "Windows 10 Pro").
Wine's INF engine resolves `AddReg=…,VersionInfo` against the arch-decorated `VersionInfo.NTamd64`
/`NTx86`/`NTarm64` first (`dlls/setupapi/devinst.c`, `NtPlatformExtension`), and applies the plain
`[VersionInfo]` to **both** the 64-bit and the `Wow6432Node` registry views, which is why the
32-bit app sees the value.

**Caveat recorded honestly:** the `amd64` token is hardcoded, matching how Wine already hardcodes
the neighbouring values. On a 32-bit-only Wine build that value would be inaccurate — but the app's
check is an AND with `ProgramFiles(x86)`, which does not exist on a 32-bit Wine, so `isWin64OS`
still comes out false there.

**Is it exclusive?** It is *required by this app* and was added for it; the change itself is a
general Wine improvement (any app that reads `BuildLabEx` benefits), so it is filed under `local/`
as "added because of SDA", not as "meaningful only for SDA".

### Investigated and **not** needed

* `packager.dll` shadowing (WineHQ 43472 / 57125 / 47598's first crash): Wine 11.18 prefers the
  app's native DLL — `dlls/ntdll/unix/loadorder.c:version_heuristics()` returns `LO_NATIVE_BUILTIN`
  for a candidate whose `CompanyName` is not Microsoft, and `loader.c:load_builtin()` then replies
  `STATUS_IMAGE_ALREADY_LOADED`. No patch, and no `WINEDLLOVERRIDES` needed.
* JavaFX losing its text glyphs on the `d3d`/`es2` pipelines: worked around with the documented
  `-Dprism.order=j2d -Dsun.java2d.d3d=false` (WineHQ 37048) via `tools/apply_jvm_options.sh`,
  **not** by a Wine patch — see `FINDINGS.md` §4.4 for why a d3d9 patch was not attempted.

