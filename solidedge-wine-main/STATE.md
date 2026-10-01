# Solid Edge X (2026) on Wine — working state

Updated: 2026-10-01 00:50 (session 1). **Read `FINDINGS.md` next** — it holds the evidence; this
file holds the position.

## Goal
Make `Solid_Edge_X_Web_Installer_2026 (1).exe`'s payload install and run under Wine on Linux and
fix three defects, each evidenced by VNC observation + Wine logs + disassembly:

1. **Sketch 3D viewport flickers black continuously** — sketch mode unusable.
2. **Sketch cannot be closed** — Close Sketch logs
   `fixme:dwmapi:DwmGetWindowAttribute attribute 14 not implemented`.
3. **Solid Edge cannot be exited** — the top-right X is greyed out.

## Hard constraints
- **Memory**: 30 GiB total, 8 GiB held by the `win11` guest. `free -h` before every build/run;
  keep >= 5 GiB available; `tools/build_wine.sh` enforces this itself.
- Autonomous loop until the goal is met. OOM-avoidance is an explicit user requirement.

## Done and verified
| thing | evidence |
|---|---|
| Media obtained without the downloader | FINDINGS **M1**: the web installer's own `#US` heap carries 30 presigned CloudFront URLs + the bootstrapper EXE; `Expires=1793061009` = 2026-10-27. Chunks 001–026 = 199229440 B, 027 = 112075276 B; 028–030 are HTTP 403 and are not part of the package. `installer/media_x/Solid Edge/` is the extracted InstallShield layout. |
| Media inventoried, real names recovered | FINDINGS **M2**: cab entry names **are** the MSI `File` table keys → `tools/cabx.py` resolves them exactly (no size guessing). `msiinfo` came from `apt-get download msitools` + `dpkg-deb -x` (no sudo on this box). |
| The viewport is **OpenGL** | FINDINGS **M2**: `render.dll` imports `OPENGL32`/`GLU32`/`wglGetProcAddress`/`wglCreateContext`/`gluNewTess`; 14 modules import `opengl32`. `d3d11`/`dxgi` are imported only by `LicensingTool.exe`. |
| The DwmGetWindowAttribute contract on Windows | FINDINGS **M3**: measured with `tools/winapi/dwmprobe.exe` in the guest — attr 14 → `S_OK`, 0; unknown attrs → `E_INVALIDARG` (not `E_NOTIMPL`); RECT attrs → `E_NOT_SUFFICIENT_BUFFER` when small; `set 20`→`get 20` round-trips. |
| Who calls attribute 14 | FINDINGS **M5**: **.NET's `UIAutomationClient.dll`** `IsWindowCloaked()`/`IsWindowReallyVisible()`, reached from **DevExpress v24.1** WinForms controls (`DevExpress.Utils.v24.1.dll` is the only SE binary referencing `UIAutomationClient`/`AutomationElement`). `DevComponents.DotNetBar2.dll` declares the P/Invoke but never calls it; `ToolkitPro2410vc170x64U.dll` calls it with attribute **9**. |
| Vendor install command line + activation code | FINDINGS **M6**: `setup.exe /s /clone_wait /v"/qn" /v"INSTALLDIR=..." /v"USERFILESPEC=...\Preferences\SELicense.lic" /v"/l*v ..."`; `INI_PARAM_ACTIVATION_CODE = "7262936774378157"`; packaged demo licence `FEATURE SolidEdge sedemon 1.0 permanent uncounted 0 HOSTID=DEMO`; `SETUP.ini` says silent mode is `/S /v/qn`. |
| Windows guest under control | `tools/vm/vmcmd.sh '<powershell>'` works (guest `adsf`/`asdf`; launcher ISO attached as `D:`; poller `vmshare/se_svc.ps1`). QEMU left modifiers are `ctrl`/`alt`/`shift` — **not** `ctrl_l`/`alt_l` (FINDINGS M4). |
| Patch series in the working directory | `patches/series/0001..0022` (acad base 14 + powerbi 5 + revit graphics 3), `patches/sources/` (the untouched originals of all four sibling projects), `patches/SERIES.tsv` (provenance), `patches/README.md`. All 22 apply in order to pristine wine-11.18, and all 46 files they touch are byte-identical to the build tree. |
| VNC display | `Xtigervnc :2` 1600x1000x24 on port 5902, `-SecurityTypes None -localhost`. `openbox` started by `tools/run_se.sh`. |
| DWM patch written | `patches/local/0023-dwmapi-window-attributes.patch` — implements the M3 contract and stores `DwmSetWindowAttribute` values as window properties so they round-trip; adds `test_DWMWA_attributes()` to `dlls/dwmapi/tests/dwmapi.c`. Both files **compile clean** (cross-compiled standalone with the exact flags from the build log). Applies clean to the patched tree (`patch -p1 --dry-run` OK). **Not yet run.** |

## New since the last update
- The fork is **built and installed**: `wine-install/bin/wine --version` → `wine-11.18`. The build
  followed the Wine wiki's new-WoW64 recipe; `nasm` was absent and unnecessary.
- `patches/local/0023` is applied and **verified twice** (FINDINGS **M9**):
  `tools/run_wine_tests.sh dwmapi dwmapi` → `54 tests executed (0 marked as todo, 0 as flaky,
  0 failures)`; and the probe diff against the guest now matches on every status code and
  buffer-size rule.
- Two control experiments killed two candidate causes of bug 1 (FINDINGS **M10**): a GL child window
  in Wine does **not** flicker black in any of seven shapes (plain, ±`WS_CLIPCHILDREN`, ±double
  buffer, layered, rounded region, both), and the ~900 ms `SwapBuffers` seen on the VNC display is
  a **native** X client behaviour too — `tools/native/glxswap` blocks identically without Wine — so
  it is Xtigervnc's present path, not a Wine defect. Run Solid Edge with
  `LIBGL_ALWAYS_SOFTWARE=1` (measured 0.50 ms at swap interval 1) when judging presentation.
- `Win+R` + `d:\g.bat` bootstrapped the guest command channel; the controller is
  `tools/vm/vmcmd.sh` (now with `-f` for a script file).
- **Solid Edge install is in progress**: `tools/install_se_prefix.sh state/work/prefix` is running
  `winetricks dotnet48` (started 00:49; dotnet40 stage done). Watch it: winetricks' dotnet verbs
  raise **modal dialogs** that block an unattended install — a `.NET Framework Initialization
  Error` ("Unable to find a version of the runtime to run this application.") appeared and had to
  be clicked; `tools/host/dismiss_dialogs.py` now runs alongside (log
  `logs/dismiss_dialogs.log`). The prefix must end on **win10**: the MSI's `LaunchCondition`
  rejects `VersionNT` 400..602, and winetricks switches the version around while installing .NET —
  the script re-asserts win10 afterwards.
- Media size check: the MSI's `File` table sums to **11.36 GB** for all languages, and all 30
  `Media` cabs are present in `installer/media_x/Solid Edge/`. The guest has 13.27 GB free, so a
  guest install is not affordable without freeing space — reference work stays with the differential
  probes.

## In flight
- `make -j8` of the whole tree (`logs/build.log`) — started 23:13, has built `tools/`, `libs/`, the
  spec-export pass for all dlls and is working through `dlls/` objects (at `dlls/dpnet` at 00:00).
  Writes to `wine/wine-11.18/`, installs to `wine-install/` (`make install` not yet run).

## Next actions, in order
1. Wait for `make`; run `make install` (`tools/build_wine.sh --inc` does it).
2. Apply `patches/local/0023` to `wine/wine-11.18`, then `make -j8` (only dwmapi + a relink) and
   `make install`.
3. `tools/run_wine_tests.sh dwmapi dwmapi` → the fork's test run is 0023's evidence.
4. `tools/install_se_prefix.sh state/work/prefix` — win10 prefix, .NET 4.8 (winetricks cache warm),
   then the vendor `setup.exe` line. Watch for: the InstallShield prerequisite stage wanting to run
   `ndp48`/`VC_redist` itself, and the licensing stage.
5. `tools/run_se.sh <tag>` on `:2`, then reproduce each of the three defects with `WINEDEBUG`.
6. Bug 2/3 diagnosis: instrument (`+dwmapi`, temporary WARNs) and correlate with a ProcMon capture of
   the same clicks on the Windows guest (differential method). UIA's `IsWindowReallyVisible` also
   depends on `IsWindowVisible`, `GetWindowRect` and `GetAncestor` — check all three on the window
   SE is asking about before blaming DWM.
7. Bug 1 diagnosis: OpenGL. `tools/host/flicker.py` measures it (`black_fraction`); then look at the
   WGL path (`wglChoosePixelFormatARB`, `wglCreateContextAttribsARB`, double buffering, `SwapBuffers`
   and the parent's `WM_ERASEBKGND`) and at whether SE expects DWM composition to hide the erase.

## Open questions / risks
- **Licensing.** The media ships a demo licence (`HOSTID=DEMO`) and `SELicense.ini` lists "Free 2D
  Drafting" and "Viewer Mode" as licence-free modes. `LicensingTool.exe`/`SELicWiz.exe` may need the
  Siemens licensing service — if that cannot come up under Wine, the escape hatch is one of the
  licence-free modes; it still reaches the viewport and the sketch environment (to be confirmed).
- **WebView2.** `control.dll` and `Microsoft.Web.WebView2.*` are in the install; the Evergreen
  installer cannot run under Wine (sibling project's finding). Fallback that is known to work: deploy
  the runtime tree from the *guest* (`C:\Program Files (x86)\Microsoft\EdgeWebView\Application\<ver>`)
  through the file channel and place it at the same path in the prefix.
- **Guest disk**: re-measured at 00:16 — `C:` now has **13.27 GB free** (Windows finished an
  update and cleaned up), Autodesk 3.6 GB, Power BI 2.7 GB, user Temp 1.9 GB.  That is enough for a
  Solid Edge install on the guest if a Windows reference becomes necessary (Femap/Keyshot/languages
  can be deselected), and the media is already on the host.  The qcow2 itself is not writable as
  this user (`-rw------- libvirt-qemu:kvm`), so it cannot be grown with `qemu-img resize`; a second
  USB-attached disk is the alternative.
- **The guest is not an OpenGL reference** (FINDINGS M7): it has no GPU driver, so its OpenGL is
  Microsoft's `GDI Generic` 1.1 with every pixel format `GENERIC_FORMAT`, while Wine on `:2` gets
  Mesa on the Intel Arc GPU with `GL 4.6` and the full WGL extension set.  The guest is still the
  reference for *window state* (bugs 2 and 3) and for ProcMon-style differential captures.
- The user asked that the Wine build follow the Wine wiki's instructions — it does:
  `./configure --enable-archs=i386,x86_64 && make -j` ("new WoW64 build"). `tools/build_wine.sh`
  embeds that recipe.
