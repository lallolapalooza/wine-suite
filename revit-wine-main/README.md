# revit2027-wine

Revit is a registered trademark of Autodesk, Inc. This repository is not associated with, affiliated with, supported nor endorsed by Autodesk, Inc. No guarantees are made, as for the suitability of the content of this repository for any particular purpose.

Wine with the patches that let Autodesk **Revit 2027** install and run on Linux.

This is a sibling of the AutoCAD fork (`acad-wine-main`). It starts from the same base — Wine
11.18 with that project's 14 patches, which cover the Autodesk ODIS installer, the
`AdskLicensing` service, signatures, the Windows hosts file, `actctx` `privatePath` probing and
the rest — and adds whatever Revit itself turns out to need.

`wine-11.18/` is a pristine `wine-11.18.tar.xz` (dl.winehq.org) with `patches/0001`..`NNNN`
applied — nothing else. Every patch is against unmodified upstream source and the series applies
cleanly in order:

```
tar -xf wine-11.18.tar.xz && cd wine-11.18
for p in ../patches/*.patch; do patch -p1 -i "$p"; done
```

No Autodesk software is redistributed here. The install media must come from your own Autodesk
account.

This is not wine upstream ready: tests were not created and this repository is ai-assisted.

## Status

| stage | state |
|---|---|
| raw `Setup.exe` from unmodified media | **works** (patch 0016: `ntdll/actctx` reads `<exe>.config`'s `<probing privatePath>`; no media-side DLL staging) |
| ODIS bootstrap: manifest, auth, downloads | **works** (2.0 GB in ~1 min) |
| third-party runtimes (.NET 10 desktop + ASP.NET Core, WebView2, VC++ 2022) | **work** — Microsoft's own installers run under this build |
| `AdskLicensing 16.6.0.16341` install + service RUNNING | **works** |
| the bundle's ADIX/MSIX packages | **work**; their three PowerShell-hosted post-install actions are dropped by `tools/neutralize_postinstall.py` (see "Post-install actions") |
| Revit payload install to completion | **works** with `tools/fetch_missing_packages.py` — ODIS installs its queue (135 `HandleInstallSuccess`, 3 `ignoreFailure` failures), then the install manager aborts (`CERWrapperImpl::HandleCrash`) with 13 packages *never downloaded*; the tool installs those (24,051 files, incl. `RCPCOMEXT` and the 21,159-file unit schema package) |
| `Revit.exe` runs with the Windows UI | **starts, paints, and the licensing dialog renders** — with `0100`+`0101`+`0102`: window `Autodesk Revit 2027` (860x500) up, splash painted, `License initialization complete / 10.0.1.66`, and the licensing dialog (`AdskLicensingAgent.exe`, 860x500) **paints its page**: `colors=5085`, OCR `Let's Get Started / Sign in with your Autodesk ID / Other license types / Enter a serial number / Use a network license` — three consecutive runs verified, plus the control reproducer (`WV2 WINDOWED OK`). Signing in still needs an Autodesk account |

Three failure modes were diagnosed and are fixed:

1. **The ADIX post-install step that needs PowerShell** — see "ADIX packages" below.
2. **A patched ODIS download cache** — see the warning in the same section. Never modify
   `<prefix>/drive_c/Autodesk/WI/*`; DLM checksums it and reports a mismatch as a fatal `-113` for
   the whole application.
3. **Packages the aborted install manager never downloaded** — see "Packages ODIS never downloads"
   below; `tools/fetch_missing_packages.py` installs them and `tools/verify_revit.sh` fails if any
   ADIX package is still missing.

Known **latent** Wine gap that Autodesk's `plugins/msihandler.dll` calls and Wine stubs:
`MsiDatabaseGenerateTransform` (`ERROR_CALL_NOT_IMPLEMENTED`) and `MsiCreateTransformSummaryInfo`
(`ERROR_FUNCTION_FAILED`) — the installer logs

```
MsiHandler::GenerateMSTFile  Failed to generate transform for msi: …\x64\RVT\RVT.msi
MsiHandler::DoTransform      GenerateMSTFile failed with error code 120
MsiHandler::Install          Required transform property cannot be applied on input MSI file!
```

but then installs with the package's *embedded* transforms and the package still reports success, so
this is not what blocks the install. It is a real missing feature with existing (todo) tests in
`dlls/msi/tests/db.c` (`generate_transform`, `MsiDatabaseGenerateTransform … ERROR_NO_DATA`).

## Post-install actions — why installs roll back, and the fix

Revit 2027's bundle (`manifest/app.RVT.xml`) has 60 packages, and only **7 are MSI**. **37 are
`type="ADIX"`**: Autodesk's MSIX container (root `AppxManifest.xml`, `AppxBlockMap.xml`,
`AppxSignature.p7x`) whose payload lives in a `VFS/<KnownFolder>/…` tree plus an `.admeta` file list.
`RVT` (the product) is a 4.1 MB MSI stub; the *program* is an ADIX package:

| package | type | packed |
|---|---|---|
| `RCPCOM` Core Package Component for Revit 2027 | ADIX | 1496.1 MB |
| `SCC` Steel Connections Content | MSI | 1498.2 MB |
| `dwgshared` RealDWG Shared 2027 | ADIX | 255.6 MB |
| `RCPRVT` Core-RVT Package Component | ADIX | 23.8 MB |
| `RVT` Revit 2027 | MSI | 4.1 MB |

Deploying one is `install_manager`'s ADIX handler (`MsixCoreLib`) writing the `VFS` files to their
real locations; that part works under Wine.

What ruins an install are the packages' **`<CustomCommands>` post-install actions**. Three of them
run a **PowerShell-hosted .NET launcher**, and a Wine prefix has no working PowerShell —
`programs/powershell` is a 147 kB stub that Wine places at exactly
`C:\windows\system32\WindowsPowerShell\v1.0\powershell.exe`, and wine-mono has no
`System.Management.Automation` assembly:

| package | action | what Windows would do |
|---|---|---|
| `RCPCOM` | `Revit_DictionaryPermissions.exe` (postInstall) | run `Revit_DictionaryPermissions.ps1`: ACLs on Revit's dictionary files |
| `RCPCOM` | `powershell -Command Remove-Item …` (preUninstall) | delete the Worksharing Monitor shortcut |
| `RCLRVTSMPL` | `Revit2027_SamplesAttributes.exe` (postInstall) | run a script marking the shipped samples/attributes read-only |

`RCPCOM` is the 1.5 GB package that *is* the program (name `CORE`, `installAs="core-addon"`) and its
manifest carries **no `ignoreFailure`** — unlike `RCLERUS` and `RCLRVTSMPL`, which do
(`<Attributes … ignoreFailure="true"/>`). So the exit code of that one action decides the whole
install:

```
18:48:05.396  CommandHandler::HandleRequest  Executing package install command: …\x64\RCPCOM\ODISActions.exe CreateShortcut …
18:48:06.064  PluginManager::PerformOperation  Starting Installation of (name: Core Package Component for Revit 2027)
18:48:06.084  CommandHandler::HandleRequest  Executing package install command: …\x64\RCPCOM\Revit_DictionaryPermissions.exe
18:48:06.917  PluginManager::PerformOperation  Fail when performing Installation of (… Core Package Component …)   Exit Status: 2
18:49:42.090  IMRequestParser::ParseRollbackPackagesRequest        <- Installer.exe asks for the rollback of the bundle
18:49:46.7…   PluginManager::PerformOperation  Starting UnInstallation of … (12 packages)
18:49:48.681  CERWrapperImpl::HandleCrash  CRASH HAPPENED!          <- the install manager dies during that rollback
```

That rollback is what leaves a prefix looking "installed but broken": the program directory is partly
deleted, `Install.db` keeps no record of the packages that did succeed, and the packages that were
still queued are never even downloaded (see the next section).

`tools/neutralize_postinstall.py` removes exactly those three actions from the *package manifests*
and leaves the working ones alone — notably `RCPCOM`'s `ODISActions.exe CreateShortcut …`, which runs
fine. Editing the manifest is what makes this work: `Installer.exe` takes the command's program from
`<CustomCommands>` and only *then* hands it to `command_handler.dll`, which validates the program's
Authenticode signature — so a removed action is never checked at all, while replacing the
*executable* is rejected (`SignatureUtils::VerifyCertificate … -2146762496` =
`TRUST_E_NOSIGNATURE`; the expected-subject check `IsSignedBySubjectName` is only applied to the ODIS
plugin DLLs and the MSI/MSIX/EXE payloads). Backups are kept as `<manifest>.orig`; `--restore` undoes
it, `--watch SECS` keeps the manifests patched while a fresh install runs (the download phase writes
them, the install phase reads them).

The only effect the removed actions had on Windows is a convenience: the read-only attribute on
the shipped `Samples` files and ACLs on Revit's dictionary files. On Linux the file modes govern
and nothing in Revit depends on either, so the tool does not try to reproduce them.

**Do not patch ODIS's download cache.** Repacking
`<prefix>/drive_c/Autodesk/WI/*/pkg.*.tar*` changes its checksum, and DLM verifies every cached
archive against the manifest (`[error] Checksum … does not match with downloaded file …` →
`NOTIFY errorCode -113`), which the DDA treats as fatal for the whole application. The package
*manifests* under `…/RVT_2027_en-US/x64/<PKG>/pkg.<PKG>.xml` are not part of that checksum set — that
is why the fix edits those and nothing else.


## WebView2 / DirectComposition — why the licensing window was blank

Every WebView2 window (Revit's startup page and the licensing dialog owned by `AdskLicensingAgent.exe`) renders
through **DirectComposition**, on Windows and therefore here. Chromium switches do not avoid that path — five sets
were tried (`--disable-gpu`, `--disable-direct-composition`, `--disable-gpu-compositing` and combinations) and the
window stayed black in all of them. Three Wine gaps had to be closed, each pinned with `WINEDEBUG` traces of a
controlled reproducer (`C:\wv2\wv2test.exe`: a 10 s mingw build of a windowed WebView2 host showing a blue page that
reads `WV2 WINDOWED OK`):

1. **`dcomp.dll` was three stubs** (`DCompositionCreateDevice{,2,3}` → `E_NOTIMPL`, no visual/target objects) while
   both the Autodesk host (`browser_native.dll`) and the runtime (`msedge.dll` 143) drive DComp themselves
   (`DCompositionCreateDevice(NULL, IID_IDCompositionDevice)` → `CreateTargetForHwnd(hwnd, topmost=…)` →
   `CreateVisual`/`AddVisual` → `SetRoot` → `SetContent` → `Commit`, and Chromium's `CheckedCastToVisual3()` is a
   `CHECK_EQ` that kills the GPU process if `IDCompositionVisual3` is not answered). → patch **`0101`**.
2. **`IDXGIFactory2::CreateSwapChainForComposition` was a stub** — the very next call after `SetRoot`, after which
   Chromium's GPU process died and relaunched six times. → patch **`0102`** (hidden-window composition swapchain).
3. **`IDXGISurface1::GetDC` was a semi-stub.** Chromium's software compositor rasterises the page with GDI into the
   composition swapchain's back buffer, so with the stub the buffers read back as zeros
   (`… centre pixel 000000`) and the compositor faithfully blitted zeros. `dxgi_surface_GetDC` already routed into
   `wined3d_texture_get_dc`, so the DC path was made to work for composition buffers. → patch **`0102`**.

That last one also owned a **flake** worth remembering: `IDXGISwapChain::ResizeBuffers(flags=0)` — issued only when the
layout ordering differs (an initial 953x1080 pass, then 860x500) — replaced the swapchain's flags inside wined3d
(`wined3d_swapchain_resize_buffers()` overwrites `desc->flags` whenever the caller passes any), dropping
`WINED3D_TEXTURE_GET_DC` from the recreated back buffers. From then on `GetDC` returned
`WINED3DERR_INVALIDCALL (0x8876086c)` and every later present composited an empty buffer. Black runs showed exactly
one `ResizeBuffers` followed by nine `Failed to get a DC for the composition buffer`; painting runs had none.
`d3d11_swapchain_ResizeBuffers()` now keeps `DXGI_SWAP_CHAIN_FLAG_GDI_COMPATIBLE` for composition swapchains.

Result: the reproducer paints (`colors=345`, OCR `WV2 WINDOWED OK if you can read this, WebView2 renders under Wine`)
and the licensing dialog paints its page (`colors=5085`, OCR `Let's Get Started / Sign in with your Autodesk ID / …`),
three consecutive runs plus regression runs. Evidence and the full trace chain: the work directory's
`LICENSING-UI.md` and `NOTES.md`; the regression test is `dlls/dcomp/tests/dcomp.c`
(`tools/run_wine_tests.sh dcomp`, 24 tests, 0 failures — regenerate `configure` first, see `SETUP.md`).

**Measurement caveat** (cost me two false "black" readings): killed Wine processes leave **orphan X windows** that
keep their last contents and capture as black. A capture harness that picks the first matching window id can therefore
report a false black; start each run on a fresh display or check that the owning PID is alive before trusting a
capture, and confirm the *live* window's colour count (the painting dialog reads `colors=5085`).

## How this fork differs from the AutoCAD one

Same base series (patches `0001`–`0016`), three behavioural differences that Revit needs, plus one
Wine fix Revit turned out to require (`0100`):

1. **`mscoree` stays enabled.** Installs run with `WINEDLLOVERRIDES="mshtml="` only. The AutoCAD
   recipe uses `"mscoree,mshtml="`, and an empty load order means *disabled* in Wine
   (`parse_load_order("") → LO_DISABLED`), which makes every IL-only .NET executable in Revit's
   bundle fail with `fixup_imports_ilonly mscoree.dll not found` (e.g. `RegisterCOM.exe`,
   `Revit2027_SamplesAttributes.exe`). Wine-mono must be present in the prefix for those to run.
2. **Post-install actions are neutralized** (`tools/neutralize_postinstall.py`) — 37 of Revit's 60
   packages are ADIX/MSIX, three of their post-install actions need PowerShell, and one of those
   lives in the package that *is* the program (`RCPCOM`, no `ignoreFailure`), so its failure rolls
   the whole bundle back. See "Post-install actions" above.
3. **Revit's own licensing identity** — prodKey **829S1**, version `2027.0.0.F`, `.pit`
   `RevitConfig.pit`; `tools/fix_licensing_registration.sh` is the fallback registration (the
   AutoCAD one uses 001S1/AutoCADConfig.pit).
4. **`0100` — `ncrypt` can import ECC key blobs.** Revit's startup crypto self-test imports a
   hard-coded ECDSA P-256 key through the CNG API and aborts ("unrecoverable error") when that
   fails; Wine's `ncrypt` only handled RSA magics while its `bcrypt` already implemented the ECC
   import. See "Post-install actions" and the patch header.

## Packages ODIS never downloads

The bundle is 57 ODIS packages (`x64/<DIR>/pkg.*.xml`, each naming its own `<UPI2>` and payload
files). ODIS's install manager fetches and installs them in turn; when it aborts — it can, with
`CERWrapperImpl::HandleCrash` at the end of a long run — the packages still queued are left
**not downloaded at all**: their staging directory under
`%TEMP%\<bundle-guid>\x64\<DIR>` does not exist, so nothing can be repaired from the staging tree.

Measured on the reference run here: 44 of the 57 packages were staged, and these 13 never were —
`AGS`, `Access`, `OpenStudio`, `OpenUSD`, `PACR`, `RCLECSY`, `RCLEENG`, `RCLEITA`, `RCLEKOR`,
`RCLEPLK`, `RCPCOMSHRNDR`, `RCPDYNSMPL`, `RS`. One of them is not optional: `RCPCOMEXT`
("Core Extension Package Component") carries 323 files into the Revit program directory, among them
`Qt6Core.dll`, `Qt6Gui.dll`, `Qt6Network.dll`, `QtSolutions_MFCMigrationFramework.dll`,
`RWUXThemeSU2015.dll`, `sfl400asu.dll`, `ot1000asu.dll`, `og1100asu.dll` and `Ecotect.dll` — every
one of which `DesktopMFC.dll` imports. Without that package the program directory cannot load, and
no amount of redeploying the staged archives can help, because the files are not in them.

`tools/fetch_missing_packages.py <prefix>` closes exactly that gap. For each package whose staging
directory is absent it reads the package's own manifest, downloads the named payloads from
Autodesk's CDN (`https://trial2.autodesk.com/<path from the manifest>` — the payload URLs need no
token, they answer `200`/`206` to a plain request) and deploys the `VFS/<KnownFolder>/…` members of
the `.adix` inside into the prefix, skipping files that already exist at the right size. It is
idempotent, does not delete anything and does not touch ODIS's database, so a later repair run can
still install the same package through the normal path. Payloads are cached
(`/tmp/autodesk-missing-payloads` by default, `--cache`).

Four of the packages are not `.adix` at all — `AGS` (`Autodesk Genuine Service.msi`), `PACR`
(`PACR.msi`), `OpenStudio` (`OpenStudio-CLI-4r.msi`) and `Access` (`AdAccess-installer.exe`) — they
carry an installer payload that ODIS feeds to `msiexec`. The tool extracts those into the staging
directory too and, when given `--wine <path to wine>`, installs them
(`msiexec /i … /qn /norestart`); without it, it lists them so they can be installed separately.

```
tools/fetch_missing_packages.py <prefix> [--dry-run] [--cache DIR] [--host URL] [--wine PATH]
```

## Layout

| path | what it is |
|---|---|
| `wine-11.18/` | the fork: Wine 11.18 source with the patches applied (no build output) |
| `patches/` | the same changes as individual patches, each with its reasoning and evidence |
| `env.sh` | build/test environment; paths follow the checkout, prefix/logs go to `$REVIT_WORK` |
| `WORKSPACE.md` | the verified `prefix3` install: how it was produced, its state, its evidence |
| `run_build.sh` | incremental build of `wine/wine-11.18` into `wine-install/` |
| `tools/build_wine.sh` | first-time build: copy, configure, `make`, install into `wine-install/` |
| `tools/check_prereqs.sh` | what this machine still needs, with the fix for each gap |
| `tools/install_revit_prefix.sh` | empty prefix → installed Revit (prefix, `Setup.exe -q`, ADIX fix, fixups, report) |
| `tools/neutralize_postinstall.py` | drops the three PowerShell-hosted post-install actions from the package manifests (the rollback fix) |
| `tools/fetch_missing_packages.py` | installs the bundle packages ODIS never downloaded (see "Packages ODIS never downloads") |
| `tools/run_revit.sh` / `tools/verify_revit.sh` | launch Revit and sample/verify its UI |
| `tools/fix_licensing_registration.sh` | fallback: register prodKey 829S1/2027.0.0.F with AdskLicensing |
| `tools/run_wine_tests.sh` | build + run a Wine test-suite module against this fork (evidence for every patch) |
| `installer/` | the extracted ODIS media (your own download) |

The Wine prefix, the ODIS logs and the run evidence live in the **work directory**
(`$REVIT_WORK`, default the sibling `../revit`), not in this repository — `WORKSPACE.md` records
what the verified install there contains and what state it reached.

## Requirements

* A licensed Revit 2027 install: the ODIS web-installer
  (`Autodesk_Revit_2027_3_ML_setup_webinstall.exe`), extracted into `installer/`:
  ```
  7z x -o installer Autodesk_Revit_2027_3_ML_setup_webinstall.exe    # 31 files, 147 MB
  ```
* A build toolchain — `bison`, `flex`, `m4`, `pkg-config`, `make`, `python3`,
  `pkg-config --exists freetype2`, `clang` (21.x, used for the PE side with `lld`) and
  `x86_64-w64-mingw32-gcc`. `tools/check_prereqs.sh` reports every gap.
* An X display for the UI runs. The project used an Xvfb/VNC display `:2` (`DISP=:2`).

## Build

Build out of the tracked tree, so the vendored source stays clean:

```
mkdir -p wine && cp -a wine-11.18 wine/wine-11.18
source env.sh
tools/build_wine.sh            # JOBS=8 tools/build_wine.sh to cap parallelism
```

This produces `wine-install/bin/wine`.

## Install into an empty prefix

```
tools/install_revit_prefix.sh $REVIT_WORK/prefix
```

Runs `wineboot -u` (win64, Windows 10), `Setup.exe -q` from `installer/` against the prefix,
then applies the four environment fixups a Wine prefix needs (Arial/arialbd/micross + their
`Fonts` registry entries, the `installed-components.autodesk` hosts line, `RpcSs`/`SamSs`
`Start=2`, `HKCU\Environment\WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--disable-gpu`) and reports
the end state. Logs: `$REVIT_LOGS/<prefix-name>/`.

### Difference from the AutoCAD recipe

The AutoCAD install runs with `WINEDLLOVERRIDES="mscoree,mshtml="`. In Wine an **empty** load
order means *disabled* (`dlls/ntdll/unix/loadorder.c`: `parse_load_order("") → LO_DISABLED`),
so that recipe disables `mscoree` outright. Revit's bundle contains IL-only .NET executables
(`Program Files/Common Files/Autodesk Shared/Structural/COM/2027/RegisterCOM.exe` fails with
`fixup_imports_ilonly mscoree.dll not found` under it), so this fork installs with **only
`mshtml=`** disabled and leaves `mscoree` at its default load order.

## Patches

Base series (from the AutoCAD fork — see each patch's own header for symptom, the Windows
behaviour it restores and how it was verified):

| # | subject |
|---|---|
| 0001 | wintrust: accept `WTD_CHOICE_BLOB` and RFC3161 timestamp signatures |
| 0002 | kernelbase: `RegLoadAppKey` over a regf hive file |
| 0003 | urlmon: keep the `res` scheme out of the empty-host `URLZONE_INVALID` rule |
| 0004 | wineserver: run the service manager and the services it starts in session 0 |
| 0006 | ws2_32: resolve names through the Windows hosts file |
| 0007 | crypt32: provide the group-policy and enterprise system certificate stores |
| 0008 | server: allow associating non-overlapped handles with a completion port |
| 0009 | ntdll: make handles on fd-backed Unix pipes behave like Windows pipes |
| 0010 | kernel32/kernelbase/ntdll/dnsapi: export the APIs the licensing and browser stacks probe for |
| 0012 | ws2_32: answer Network Location Awareness (NS_LNA) lookups |
| 0013 | winex11: ignore `BadWindow`/`BadDrawable` X errors on every display connection |
| 0014 | secur32: answer `GetUserNameExW`'s `NameUserPrincipal` and `NameDnsDomain` |
| 0015 | msiexec: parse the command line with the Windows rules |
| 0016 | ntdll: actctx probing `privatePath` (upstream MR !10753) — what lets the raw ODIS `Setup.exe` start |

Revit-specific patch (the series continues from `0100`, see `patches/README.md`):

| # | subject |
|---|---|
| 0100 | ncrypt: import ECC key blobs — Revit's startup crypto self-test |
| 0101 | dcomp: implement the device/target/visual objects, `Commit`, and the composition surface path |
| 0102 | dxgi: `CreateSwapChainForComposition` + per-present compositing and a GDI-compatible back buffer that survives `ResizeBuffers` |

Revit aborts seconds into startup without it: `PersistenceDB.dll` imports a hard-coded ECDSA P-256
private key through the CNG API and treats a failure as fatal
(`Assertion failed: line 47 of …\PersistenceDB\Pipeline\DataIntegrity.cpp`, `ExceptionCode=0xe06d7363`
→ the "An unrecoverable error has occurred" box). Wine's `ncrypt` handled only the three RSA magics
(`fixme:ncrypt:NCryptImportKey Unhandled key magic 0x32534345`, then `NTE_INVALID_PARAMETER`), while
its `bcrypt` already implements the ECC import (`import_ecc_key`, `BCRYPT_ECCPRIVATE_BLOB`). The
patch header carries the decompiled call site; the regression test is
`dlls/ncrypt/tests/ncrypt.c::test_key_import_ecc` (`tools/run_wine_tests.sh ncrypt`).

The installer's two other blockers are *not* Wine defects:

* the ADIX post-install actions that need PowerShell (a Wine prefix has no working PowerShell) —
  handled by removing those actions from the package manifests, `tools/neutralize_postinstall.py`;
* ODIS's own error handling around a failed package (whole-bundle rollback, then a crash) —
  Autodesk code, the same on Windows.

Anything that does turn out to be a Wine defect goes in as `0100+` **with a test in the matching
suite**, per `patches/README.md`.
