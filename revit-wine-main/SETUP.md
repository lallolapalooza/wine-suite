# SETUP — Revit 2027 on Linux with the patched Wine

This is the walkthrough: what the fork changes, what the machine needs, how to build it, how to
install Revit into a prefix and how to run it. Everything is driven by `env.sh`, so the paths
below follow the checkout; the prefix, the logs and the evidence live in `$REVIT_WORK`.

```
export REVIT_WORK=~/revit            # optional; this is the default (sibling of the checkout)
```

## 1. Media

Revit 2027 comes from your own Autodesk account as an ODIS web installer. Extract its payload
into `installer/` — the web-installer stub is a PE with an embedded 7z archive:

```
7z x -o installer Autodesk_Revit_2027_3_ML_setup_webinstall.exe
```

That leaves the layout the installer expects (`Setup.exe`, `Setup.exe.config`, `ODIS/`,
`SetupRes/`; 31 files / 147 MB). Two things NOT to do:

* do not copy the `ODIS/odis.bs.win/*` DLLs next to `Setup.exe`. The web-installer's manifest
  declares those as SxS assemblies resolved through `<probing privatePath="ODIS">` in
  `Setup.exe.config`; patch 0016 teaches Wine's `actctx` to read that file, exactly as Windows
  does. Staging the DLLs was a workaround for the pre-0016 fork and is unnecessary (and hides
  whether the patch works).
* do not run the outer stub (`Autodesk_Revit_2027_3_ML_setup_webinstall.exe`) under Wine: it
  extracts to `%TEMP%\7z*`, launches the inner `Setup.exe` and **exits 0 even if the child
  fails**, so its exit code says nothing. Run the extracted `Setup.exe` directly.

## 2. Machine prerequisites

Wine's build needs `make`, `m4`, `patch`, `pkg-config`, `python3`, `flex >= 2.5.33`,
`bison >= 3.0`, a C compiler, `clang` (the PE side is built with clang/lld) and
`x86_64-w64-mingw32-gcc`. The runtime side needs an X display and, for the UI evidence,
`xwininfo`/`import` (ImageMagick) and `xdotool`. `tools/check_prereqs.sh` checks all of it and
prints the fix for each gap.

```
tools/check_prereqs.sh --media installer
```

## 3. Build

The vendored `wine-11.18/` is never built in place: `tools/build_wine.sh` copies it to
`wine/wine-11.18/`, configures it with `--enable-archs=i386,x86_64` (the 32-bit PE DLLs matter:
part of the Autodesk licensing stack is 32-bit) and installs into `wine-install/`.

```
source env.sh
JOBS=8 tools/build_wine.sh            # first build, ~45 min at JOBS=8 on 22 cores
```

After the first build, iterate with `run_build.sh` (incremental `make` + `make install`):

```
JOBS=8 ./run_build.sh
```

Memory: a full `-j22` build of both architectures is the single biggest consumer on this machine
(and it is why the scripts default to a low job count). Raise `JOBS` deliberately.

## Which patches

`patches/0001`–`patches/0016` are the base series copied from the AutoCAD fork, plus this fork's own
`patches/0100-ncrypt-import-ecc-key-blobs.patch`: Revit's startup crypto self-test imports a
hard-coded ECDSA P-256 key through the CNG API and aborts with `Assertion failed: line 47 of …
DataIntegrity.cpp` when that fails; Wine's `ncrypt` knew only the RSA blob magics while its `bcrypt`
already implemented the ECC import. Without `0100` Revit paints its splash and then dies. Its
evidence is the test run `tools/run_wine_tests.sh ncrypt` (445 tests, 0 failures) and the journal of
a run that reaches `manage licensing`.

## 4. Install into an empty prefix

```
tools/install_revit_prefix.sh $REVIT_WORK/prefix
```

What it does, in order:

1. `wineboot -u` — win64 prefix, Windows 10 (Windows 10 is what the ODIS manifest request
   reports; the guest used for the reference is 10.0.19045).
2. `(cd installer && Setup.exe -q)` — the unattended ODIS install. It downloads ~2 GB of ODIS +
   product payload, then runs `Installer.exe -q --install_mode install --manifest …` from
   `%TEMP%\odis_download_dest\<id>\`. Media is extracted to
   `C:\Autodesk\WI\{8CA3AC7D-FAD3-34CE-B228-4EE1B50E2D3E}\RVT_2027_en-US\`.
   The post-install action watcher runs alongside (step 2b).
2b. `tools/neutralize_postinstall.py <prefix> --watch` — started automatically for the
   duration of the install. It removes the three PowerShell-hosted `<CustomCommands>` actions
   (`RCPCOM`'s `Revit_DictionaryPermissions.exe` and its `powershell` preUninstall,
   `RCLRVTSMPL`'s `Revit2027_SamplesAttributes.exe`) from the package manifests as the download
   phase writes them. Without it the first of those fails (no PowerShell in a Wine prefix),
   `RCPCOM` has no `ignoreFailure`, and ODIS rolls the whole bundle back mid-install. See README
   "Post-install actions" for the log evidence.
2c. `tools/fetch_missing_packages.py <prefix>` — installs the bundle packages ODIS never downloaded.
   When the install manager aborts it leaves the rest of its queue unfetched, and files that only
   live in those packages are then missing from the program directory — `RCPCOMEXT` alone carries
   the `Qt6Core.dll`/`Qt6Gui.dll`/`QtSolutions_MFCMigrationFramework.dll`/`RWUXThemeSU2015.dll`/
   `sfl400asu.dll`/`ot1000asu.dll`/`og1100asu.dll`/`Ecotect.dll` set that `DesktopMFC.dll` imports.
   See README "Packages ODIS never downloads". `REVIT_FETCH_MISSING=0` skips this step.
3. Four environment fixups (Wine-vs-Windows only, none of them an installer workaround):
   * Arial / Arial Bold / Microsoft Sans Serif fonts + their `Fonts` registry entries;
   * `127.0.0.1 installed-components.autodesk` in the prefix's hosts file;
   * `RpcSs` and `SamSs` `Start=2` (autostart);
   * `HKCU\Environment\WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--disable-gpu`.
4. Report: `Revit.exe` present? package counts, payload size.

`WINEDLLOVERRIDES`: **only** `mshtml` is disabled. The AutoCAD fork additionally disables
`mscoree` (`WINEDLLOVERRIDES="mscoree,mshtml="`) because an empty load order means *disabled* in
Wine (`dlls/ntdll/unix/loadorder.c`, `parse_load_order("") → LO_DISABLED`). Revit's bundle
contains IL-only .NET executables — e.g. `Program Files/Common Files/Autodesk Shared/Structural/
COM/2027/RegisterCOM.exe` — which cannot load at all with `mscoree` disabled
(`err:module:fixup_imports_ilonly mscoree.dll not found`). Leave `mscoree` at its default.


## WebView2 / DirectComposition (patches `0101`, `0102`)

Revit's WebView2 windows — the startup page and the licensing dialog owned by `AdskLicensingAgent.exe` — render through
DirectComposition, which stock Wine did not provide: `dcomp.dll` was three stubs and
`IDXGIFactory2::CreateSwapChainForComposition` plus `IDXGISurface1::GetDC` on composition buffers were missing/broken
(the DC path is how Chromium's software compositor writes the page into the swapchain). Patches `0101`/`0102` add the
dcomp object model, the composition swapchain with per-present compositing, and keep
`DXGI_SWAP_CHAIN_FLAG_GDI_COMPATIBLE` across `ResizeBuffers` (dropping it made the dialog blank in some runs and
painted in others). `--disable-gpu` is still set in the prefix (it selects the software path that this implementation
serves), but Chromium switches cannot avoid DirectComposition.

The dcomp patch ships a test, which needs one extra step because the test was added to `configure.ac`:

```
cd wine/wine-11.18 && PATH=$HOME/.local/bin:$PATH autoconf -o configure configure.ac   # needs GNU autoconf
make -C dlls/dcomp/tests
cd .. && DISP=:3 ./tools/run_wine_tests.sh dcomp      # expect "24 tests executed, 0 failures"
```

## 5. What the installer installs

The bundle (`manifest/app.RVT.xml`) has 60 packages: `RVT` (the product, `launchApp`), the
`RCL*`/`RSEN`/`RAIM` add-ons, material libraries (`Content/ADSKMaterials/*`), and third-party
runtimes it downloads from Microsoft:

| package | installer | note |
|---|---|---|
| .NET Windows Desktop Runtime 10.0.9 (x64) | `windowsdesktop-runtime-10.0.9-win-x64.exe /install /quiet /norestart` | `ignoreFailure` — a failure does not abort the bundle |
| ASP.NET Core Runtime 10.0.9 (x64) | `aspnetcore-runtime-…-win-x64.exe` | |
| .NET Framework Runtime 4.8 (+ language packs) | `ndp48-…` | |
| Microsoft Edge WebView2 Runtime | `MicrosoftEdgeWebView2RuntimeInstallerX64.exe` | the licensing/AppHome surfaces are WebView2 |
| Microsoft SQL Server 2019 LocalDB | `SqlLocalDB.msi` | |
| Microsoft Visual C++ 2022 Redistributable | `VC_redist.x64.exe` | |

Revit 2027 is a .NET 10 application; the Wine prefix therefore needs a working .NET layer. Wine
11.18 installs **wine-mono 11.3.0** into every new prefix automatically: `wineboot` fetches
`wine-mono-11.3.0-x86.msi` on demand and caches it in `~/.cache/wine/` (verify with
`ls <prefix>/drive_c/windows/mono` after creating the prefix — that directory is the installed
mono). The version Wine expects is in `dlls/appwiz.cpl/addons.c:MONO_VERSION`.

For a machine without network access, put the msi in the cache (or install it by hand) before
creating the prefix:

```
curl -O https://dl.winehq.org/wine/wine-mono/11.3.0/wine-mono-11.3.0-x86.msi
mkdir -p ~/.cache/wine && cp wine-mono-11.3.0-x86.msi ~/.cache/wine/
# already created the prefix without it:
WINEPREFIX=$REVIT_WORK/prefix wine msiexec /i wine-mono-11.3.0-x86.msi
```

This matters: the bundle contains IL-only .NET executables (`RegisterCOM.exe`,
`Revit2027_SamplesAttributes.exe`) that cannot load at all without mono — and the samples one
failing is what rolls the whole bundle back (see the README's ADIX section).

## 6. Run

```
tools/run_revit.sh <tag> [seconds] [interval]
```

Launches `Revit.exe` from the prefix on `$DISP` and samples: the window tree (main window up?
assertion dialogs?), the process count, a window capture and a root-window capture every
`interval` seconds. Evidence lands in `$REVIT_LOGS/ui/<tag>/` and `$REVIT_LOGS/log_<tag>.txt`.

To check the end state in one shot:

```
tools/verify_revit.sh $REVIT_WORK/prefix 240
```

## 7. Known limits

* **The install stalls mid-pipeline** — see the README status section; this is the open work.
* Revit is a 3D application: the drawing canvas needs a working D3D stack. The project runs on an
  Xvfb/VNC display (`:2`, 1920x1080x24) with the software renderer; a GPU surface is not needed
  to prove the UI loads, but 3D performance on a virtual display is untested.
* No Autodesk software is redistributed with this repository; the media comes from the user's own
  Autodesk account, and the license/entitlement side is the user's own.
