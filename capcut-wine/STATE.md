# CapCut on Wine — STATE (append-only log; newest at bottom of each section)

Updated: 2026-10-04T00:10 (host local)

## 0. Mission
Make `/home/asdf/Downloads/capcut_capcutpc_0_1.2.36_installer.exe` (CapCut PC, Windows x64) run on Wine
"like it does on Windows" (goal: real UI, open like Windows). Method: union of the existing AutoCAD and
Power BI Wine patch series as the base, then reverse-engineer the app, diff Wine vs Win32 API behavior,
and add CapCut-specific Wine patches. Document everything; separate app-exclusive patches at the end.

## 1. Environment (measured)
- Host: Ubuntu, kernel 7.0.0-34, Intel Core Ultra 7 155H, 22 CPUs, 30 GiB RAM (13 GiB used at start), swap 8 GiB (5.7 GiB used — watch it).
- Disk: `/` = 213 G, **39 G free** (81% used). `/run/media/asdf/Windows` = 33 G free (Windows partition). `/dev/shm` 16 G tmpfs (use for tmp).
- System wine = 10.0 (Ubuntu package) — NOT sufficient; we build our own from `wine-11.18.tar.xz`.
- Pristine Wine 11.18 source tarball: `/home/asdf/Downloads/wine-11.18.tar.xz`
- Prior patched trees (unbuilt, source-only, no .git):
  - `/home/asdf/projects/acad-wine-main/wine-11.18`  (AutoCAD series applied) — 418 M
  - `/home/asdf/projects/powerbi/wine/wine-11.18`    (Power BI series applied) — 417 M
  - Full evidence for those: `/home/asdf/projects/powerbi-linux/FINDINGS.md`, `/home/asdf/projects/autocad2027-private-main/FINDINGS.md`
- Patch series to union: `/home/asdf/projects/acad-wine-main/patches/` (0001–0017) and `/home/asdf/projects/powerbi/patches/` (0001–0007).

## 2. Target app (measured)
- `capcut_capcutpc_0_1.2.36_installer.exe` = 2.88 MB, **Nullsoft NSIS 3.04** self-extracting, PE32 i386, `asInvoker`.
- It is a **web/stub installer**: `$PLUGINSDIR/{downloader_nsis_plugin.dll, shell_downloader.dll, BgWorker.dll, System.dll, res.zip}`.
- Downloader queries ByteDance MCS config endpoints:
  `https://mcs-v2-boot.capcutapi.com/v1/json`, `https://mcs.zijieapi.com/v1/json`, `.../bytedance.net/...`.
  Config keys: `download_url`, `installer_download_cdn_info`, `download_total_size`, `downloader_config`.
- Inner installer UI is DuiLib (DuiLib XML in `res.zip/res/resource/install.xml`), fonts: Microsoft YaHei.
- Extracted stub: `/home/asdf/projects/capcut-wine/recon/ins/` (see recon/ins/$PLUGINSDIR).

## 3. Windows reference VM (measured)
- libvirt domain `win11` — ALREADY RUNNING (Id 1), qcow2 `/var/lib/libvirt/images/win11.qcow2`, spice on 127.0.0.1:5900, 8 GiB, 4 vCPU.
- Guest: Windows 11 Pro build **26200**, user **asdf\adsf** (NOT admin), .NET Framework 4.x present, PS 5.1, network OK.
- Guest agent (left running by an earlier project): PowerShell loop polling `http://192.168.122.1:8000/cmd.txt`
  every 3 s, executes via Invoke-Expression, uploads `guest_cmd_out.txt`. Host side = `tools/vm/vmserv.py`.
- Host helper for this project: `scripts/vmcmd.sh "ps-command"` (uses that channel). vmserv running on port 8000, share `capcut-wine/vmshare/`.
- VM input: `powerbi-linux/tools/vm/vmclick.py`, `vmkeys.py`, `vmtype.py` (QMP input-send-event; usb-tablet absolute 0..32767; guest screen 1280x800).
- VM view: `virsh screenshot win11 --file out.png`.
- **Caveat**: guest is not admin; CapCut installs per-user, so this should be fine.

## 4. Established method (from prior projects)
1. Build Wine 11.18 from source with the union patch series (`--enable-archs=x86_64`).
2. Prefix + dependencies (winetricks) installed into the working dir.
3. Capture Win32 reference behavior on the `win11` guest; capture Wine behavior; diff.
4. Patch Wine; add regression tests in Wine's own suite where possible; keep app-exclusive patches in `patches/capcut/`.

## 5. Current phase
PHASE 0 — recon complete enough to start. Next: capture real CapCut payload from the Windows guest;
merge the two patch series into a CapCut wine tree; start the Wine build.

## 6. Open questions / risks
- CapCut PC real payload size/stack unknown (Qt/C++? CEF? Electron? WebView2?) — determines difficulty.
- QXL guest GPU: does CapCut even render on the VM? Need to verify (reference validity).
- Disk: 39 G free may be tight for wine build + prefix + app. Monitor; consider /dev/shm and Windows partition.
- Memory: swap already 5.7 GiB used; cap build parallelism (`-j16`) and check free before builds.

## 7. USER-PROVIDED GROUND TRUTH (2026-10-04) — highest priority
The app ALREADY opens under some Wine build. Observed symptoms (user, treat as measured):
- Opening a project works, but **freezes after ~1 second**.
- Trying to open things for editing **just don't work**.
- **Crashes after 5–30 s.**
- **Menu can freeze and crash too.**
- Reference: https://appdb.winehq.org/objectManager.php?sClass=version&iId=43009
Goal therefore = fix freeze-on-open, non-working edit actions, and the crashes (not only "make it start").

## 8. PROGRESS LOG
### 2026-10-04 00:15 — payload obtained, build started
- **Found `/opt/wine-staging`**: a complete root-owned **wine-11.18 (Staging)** WoW64 build (1.7 G, i386-windows + x86_64-unix + x86_64-windows) at `/opt/wine-staging/bin/wine`. Use it for baseline reproduction; it can run the 32-bit NSIS stub too.
- Created prefix `capcut-wine/prefix` (2.1 G) with that build; ran the stub `work/capcut_setup.exe` under Wine:
  - The DuiLib installer UI **renders correctly** ("CapCut desktop installer", progress bar, More button).
  - It **downloaded the real payload fine under Wine** — no Windows needed for acquisition.
  - Payload lands at `prefix/drive_c/users/asdf/AppData/Local/app_shell_cache_562354/app_package_<hash>.exe` (PE32+ x86-64, >550 MB, still streaming).
  - Its own log: `prefix/drive_c/users/asdf/AppData/Local/Temp/installer_downloader.log` — records install dir `C:\users\asdf\AppData\Local\CapCut\Apps`, locale `en_US`, `capcutpc_0`, and `[IsWindows10OrGreaterImpl]: Windows10OrGreater= 0`.
- `scripts/watch_payload.sh` waits for the download to finish and copies it to `work/payload/app_package.exe` + `.sha256`.
- **Merge done** (`recon/MERGE.md`): union series of 22 patches (acad 15 + powerbi 7 + 2 recovered) in `patches/0001..0022`, tree `wine/wine-11.18` (git branch `merged`) reproduces HEAD exactly. Patch 0023 (bcrypt DEBUG ONLY) moved to `patches/debug-only/` and dropped from the tree.
- **Build started**: `scripts/build_wine.sh 16` → configure `--enable-archs=x86_64 --prefix=capcut-wine/wine-install`, make -j16 with ccache, then make install. Logs: `logs/{configure,make,make_install}.log`, driver `logs/build_driver.log`, sentinel `logs/.build_ok`.

## 9. REPRODUCTION + FIRST ROOT-CAUSE EVIDENCE (2026-10-04 00:25)

### The app under Wine (baseline build = /opt/wine-staging wine-11.18)
- Prefix `capcut-wine/prefix`. CapCut installs to
  `prefix/drive_c/users/asdf/AppData/Local/CapCut/Apps/{CapCut.exe,uninst.exe,Configure.ini,ProductInfo.xml,9.5.0.4050/}`
  → real app version **9.5.0.4050** (`ProductInfo.xml`: cid `capcutpc_0`, appver 9.5.0, full_appver 9.5.0.4050).
- Main entry `Apps/CapCut.exe` (4.97 MB launcher) → spawns `Apps/9.5.0.4050/CapCut.exe` (90 KB, loads Qt6 + VECreator).
- `Apps/9.5.0.4050/` = Qt6 (Core/Gui/Qml/Quick/Widgets/Network), VECreator.dll (235 MB), cef/ (libcef 207 MB, Chrome/121.0.6167.86),
  lynx.dll, lens.dll, cccreator.dll, videoeditor.dll, deepagents_capi.dll, openvino.dll, avcodec-61.dll, sscronet.dll,
  VEAngle/{libEGL.dll,libGLESv2.dll}, cef/{libEGL,libGLESv2}.dll, opengl32sw.dll, VESafeGuard.dll, parfait_crash_handler.exe.
- **Reproduced the user's symptom**: main process starts, creates windows (`CapCut` 1024x799, `DXGI device window`, …),
  prints rich init output (MMKV, bytenn, mobilecv2, EffectSDK), then **exits at ~45 s** (user: 5–30 s).

### Wine-side errors captured (run tags under logs/)
1. `logs/repro1/stdout.log` (WINEDEBUG=err+all,fixme-all):
   - `0148:err:sync:RtlpWaitForCriticalSection section 00006FFFFFC4C460 "dlls/ntdll/loader.c: loader_section" wait timed out in thread 0148, blocked by 0024, retrying (60 sec)`
     → **loader critical-section contention/stall** early in startup.
   - `[AGFX_TAG-22.0.0.1-lv]GPDevice::initEGLLibraryWithPath, FAILED to load EGL library!`
   - `[AGFX_TAG-22.0.0.1-lv]GPDevice::initGLESv2LibraryWithPath, FAILED to load GLESv2 library!`
   - `failed to load library: ve_detector/libEGL.dll` … `failed`
   - CEF: `network_change_notifier_win.cc(224) WSALookupServiceBegin failed with: 0` (also seen in the Power BI project — probably benign).
2. Crash artefacts (first run): `User Data/Crash/reports/<guid>.dmp` (209 MB) — the crash handler **deletes/consumes** it;
   `scripts/cc_run.sh` has a rescuer that copies it out; `scripts/dmp_summary.py` summarises it (needs `tools/venv` with `minidump`).
   `crash_metadata` (json tail) records: `render_engine=d3d11`, `qt_use_direct_composition=1`, `qsg_render_loop=threaded`,
   `process_type=main_process`, `driver_type=unknown`, `gpu="NVIDIA GeForce GTX 470"` (bogus — host GPU is Intel Meteor Lake iGPU),
   `gpu_driver_version=31.0.13.9135`, `resolution=1600*1000`, `os_version=Windows NT 10.0.19045`.
3. `VEDetector.exe` contains the strings `ve_detector` and `pc_libegl_libglesv2_dynamic_library_missing` (a tracking key).
   No `ve_detector` file/dir exists anywhere in the install.
4. Direct LoadLibrary probe under Wine (`work/tools/t_egl.c`, run from the version dir):
   `VEAngle\libEGL.dll` → OK, `VEAngle\libGLESv2.dll` → OK, `cef\libEGL.dll` → OK,
   `ve_detector/libEGL.dll` → NULL err=126 (ERROR_MOD_NOT_FOUND, expected — it does not exist).
   ANGLE DLL imports are only KERNEL32/USER32/dxgi (+delay d3d9). So the failure is **path resolution, not a broken dependency**.
5. Screenshot of the Wine root window is blank while the app's X windows exist → the app creates windows but nothing is presented.

### Windows reference (guest, agent-dispatched)
- CapCut installed and **launches to its full home UI on Windows** (`recon/win_install/capcut_launch_t60s.png`: "Create project"
  home screen + Terms of Service dialog). That is the target end state.
- Agent uploads so far: `vmshare/alog{0,1,2}.bin`, `vmshare/vedet.png`, `vmshare/shot.png`, `vmshare/winmove.ps1`, `vmshare/capture.ps1`.

### Tooling built
- `scripts/vmcmd.sh` (guest command channel), `scripts/vm/*` (vmclick/vmkeys/vmtype/vmserv),
  `scripts/cc_run.sh` (run + screenshot + dmp rescue + log collection), `scripts/run_capcut.sh`, `scripts/watch_payload.sh`,
  `scripts/dmp_summary.py`, `scripts/build_wine.sh`, `tools/venv` (minidump).
- `tools/ghidra` = `/var/tmp/asdf-ghidra/ghidra_12.1.4_PUBLIC`.
- Wine build running: `logs/build_driver.log` → `wine-install/` (sentinel `logs/.build_ok`).

## 10. ROOT-CAUSE MAP (2026-10-04 00:30)

### Confirmed facts
- **Upstream wine-11.18's `dlls/dcomp` is a stub** (47-line device.c, `@ stub` for everything; the three
  `DCompositionCreateDevice*` return E_NOTIMPL). Verified against the pristine tarball.
- **`/opt/wine-staging` is the packaged wine-staging 11.18** (full patchset): it has a real dcomp
  (`dlls/dcomp/{surface,target,visual}.c`) and its `dcomp.dll` exports 21 functions.
- **`Qt6Gui.dll` loads DirectComposition dynamically** (`DCompositionCreateDevice`, "Unable to resolve
  DCompositionCreateDevice, perhaps dcomp.dll is missing?", "Failed to create DirectComposition visual: %s",
  "DXGI 1.2 = %s, FLIP_DISCARD swapchain supported = %s, DirectComposition supported = %s").
  So Qt Quick's D3D11 RHI uses dcomp when the symbol resolves — **Wine's dcomp stub resolves the symbol but
  fails E_NOTIMPL**, and staging's dcomp fails with real errors:
  `err:dcomp:create_bgra_surface_from_rgba Failed to create a SRV, hr 0x80070057` +
  `err:dcomp:do_composite_dxgi_surface Failed to convert DXGI_FORMAT_R8G8B8A8_UNORM surface to DXGI_FORMAT_B8G8R8A8_UNORM, hr 0x80070057`
  → **the composited output is never produced: window exists, nothing is painted (the "freeze")**.
- Wine's `d3d11_device_CheckFormatSupport` is a FIXME "partial-stub" (it does real but partial flag mapping).
- Other Wine-side errors: `err:ole:com_get_class_object` for CLSID `{47dfbe54-cf76-11d3-b38f-00105a1f473a}`;
  `fixme:winsock:WSALookupServiceBeginW Stub!`; `fixme:wlanapi:WlanEnumInterfaces semi-stub`;
  `[lv_detect] dx_hw Adapter 0:Intel(R) HD Graphics 4000` (Wine's generic adapter description).
- Started main process **exits cleanly with code 0 at 30–45 s** (not an exception). No minidump from the later runs;
  `VECrashHandler` logs "crash handle switch disabled!" so it does not process dumps by default.
- VEDetector.exe is a **Qt Widgets** app (`VEDecectorWindowClassWindow`), used for GPU/hardware detection.
- The app *is* able to run its Qt/QML/CEF init: MMKV, bytenn, mobilecv2, EffectSDK, CEF renderers all come up.

### Strategy change (user direction, 2026-10-04)
Use **DXVK** (D3D9/10/11 + DXGI → Vulkan) instead of reimplementing Wine's d3d11/dxgi, and vkd3d if D3D12 is needed.
Installed DXVK **v3.1.1** into the prefix (`scripts/install_dxvk.sh`, DLL overrides native for
d3d8/d3d9/d3d10core/d3d11/dxgi; x64 into system32, x32 into syswow64).
Rationale: DXVK replaces exactly the components that are failing (`CheckFormatSupport`, the dcomp
RGBA→BGRA SRV creation path runs through d3d11/dxgi).
Host has Vulkan ICDs: intel_icd (ANV), lvp_icd (lavapipe software), nouveau, radeon, virtio, asahi, gfxstream.
Run harness now forces `DISPLAY=:9` (an earlier harness inherited `:0` and drove the real desktop).

## 11. WINDOWS REFERENCE FACTS (measured on the win11 guest by agent GuestCapCutCapture)

**These are decisive and supersede speculation:**
1. **There is NO `ve_detector` file or directory anywhere under the Windows CapCut install.** The string
   `ve_detector/libEGL.dll` is therefore *not* a Windows install layout — it is produced only under Wine.
2. The **Windows VeDetector log contains ZERO matches for `EGL|GLES|AGFX|GPDevice|ve_detector`** — i.e. the
   ANGLE/EGL initialisation that fails on Wine **succeeds on Windows**. So the Wine failure is a real defect
   on the path that loads `libEGL.dll`, not an app bug and not a missing directory.
3. Windows layout of ANGLE: `…\9.5.0.4050\VEAngle\{libEGL.dll 220072, libGLESv2.dll 5672360}` and
   `…\9.5.0.4050\cef\{libEGL.dll 486824, libGLESv2.dll 7657896}` — two *different* builds (the cef one is
   bigger, i.e. Chromium's own ANGLE).
4. **CapCut stays running and fully renders on Windows** (7 processes; main window title "CapCut",
   Responding=True; home screen after ~60 s; first run shows a ToS/Privacy modal — "Agree and continue" —
   after which the full editor home loads; **no login needed** for the home screen).
5. Windows environment values: `hw_render=0`, `qt6_render_engine=d3d11`, `angle_device=auto`;
   GPU = **Microsoft Basic Display Adapter** (QXL, vendor 1B36 device 0100) — so on Windows it renders
   through d3d11 with *no hardware GPU*, and it still paints. Wine must match that.
6. Windows screenshots: `recon/win_install/capcut_launch_t{10,30,60,120}s.png`,
   `capcut_after_agree.png`, `probe2_state.png`, `step3b_vedetector.png`.
7. Wine-side workaround that made the EGL error disappear (creates a non-Windows layout): a `ve_detector/`
   directory next to the exe containing `VEAngle`'s ANGLE DLLs. Keep as a fallback, but since (1)+(2) show
   Windows needs no such directory, the *correct* fix is on the Wine side; see §12.

## 12. TREE / SERIES STATE
- `wine/wine-11.18` = pristine 11.18 + 25 commits, branch `merged`, `git status` clean.
  Commits: acad(15) + powerbi(7) + revit-derived dcomp/dxgi/ncrypt(3):
  `6d73e29` dcomp, `8c85433` dxgi composition swapchain, `eeb3172` ncrypt ECC key blobs.
- `patches/` holds `0001..0025` + `base-roles.tsv` + `debug-only/` (bcrypt debug patch, deliberately excluded).
- Donor series discovered on this machine and their structure — **adopt this layout for our deliverable**:
  `patches/series/` (shared base), `patches/local/` (app-exclusive, numbered from the next free number),
  `patches/sources/` (untouched copies of the donor patch dirs), plus `patches/README.md`/`SERIES.tsv`.
  Precedents: `solidedge-wine-main` (has the same dcomp patch, byte-identical: 71896 bytes),
  `tableau-wine`, `resolume-wine`, `eos-wine`, `mastercam-wine`, `sda-wine`.
- **Only `revit-wine-main` (and `solidedge-wine-main`'s patch copy) have a real dcomp**; every other sibling
  tree still has the 47-line stub. `revit-wine-main/README.md` records that with 0100+0101+0102 its
  WebView2/Chromium licensing window went from blank to fully painted.
- `solidedge-wine-main/patches/local/` has two more candidate patches (`0023-dwmapi-window-attributes`,
  `0024-uiautomationcore-conditional-navigation`) — **not needed by CapCut**: our logs contain zero
  `dwmapi`/`uiautomation` fixmes. `resolume-wine/patches/local/0100-dxgi-output-WaitForVBlank.patch` is
  also available if a vblank wait turns out to be needed.

## 13. DISPLAY / ENVIRONMENT HYGIENE
- Rendering happens on **Xvfb `:9` (1600x1000)**. `openbox` now runs on `:9` (a window manager was missing;
  an earlier attempt accidentally started openbox on `:2`). `import -window root` on `:9` works.
- Every Wine run prints `libEGL warning: DRI3 error: Could not get DRI3 device` — Xvfb has **no DRI3**.
  That is a real risk for DXVK's Vulkan presentation path (which wants X Present/DRI3), while Wine's own
  wined3d→GLX path works on Xvfb. Test both with and without DXVK before concluding anything.
- Build: `scripts/rebuild.sh` re-runs configure (needed because the dcomp patch adds
  `WINE_CONFIG_MAKEFILE(dlls/dcomp/tests)` to configure.ac) then make+install; sentinel `logs/.build_ok`.
  `dlls/dcomp/tests/` will not be built until `configure` itself is regenerated (autoconf is available at
  `~/.local/bin/autoconf`, automake/aclocal are not) — do that when running the regression tests.

## 14. DELIVERABLE LAYOUT (adopted from the sibling projects) — DONE
`patches/` is now:
- `series/`   — the shared base series that applies to pristine wine-11.18 in order: `0001..0025`
                (`base-roles.tsv` kept here; the donor copies of the donor series live below).
- `local/`    — **this project's own (CapCut-exclusive) patches**; empty until we add them.
- `sources/`  — untouched copies of every donor patch directory: `acad-wine-main`,
                `autocad2027-private-main`, `powerbi`, `revit-wine-main`, `solidedge-wine-main`,
                `resolume-wine`.
- `SERIES.tsv` — provenance of the whole series (new no. -> origin -> source patch -> subject).
- `debug-only/` — the bcrypt key-dump patch from `autocad2027-private-main` (`0005`), deliberately NOT
                in the tree: it prints secrets and changes no behaviour.
- scripts: `scripts/restructure_patches.sh` (reproducible), `scripts/build_wine.sh`,
  `scripts/rebuild.sh`, `scripts/install_dxvk.sh`, `scripts/cc_run.sh`, `scripts/run_capcut.sh`,
  `scripts/watch_payload.sh`, `scripts/vmcmd.sh`, `scripts/dmp_summary.py`, `scripts/vm/*`.

## 15. GPU EXPOSURE (Proton-style) — prepared, under test
Wine's wined3d card table invents the adapter (`Intel(R) HD Graphics 4000`, `NVIDIA GeForce GTX 470`
in the crash metadata) while the Windows guest reports **Microsoft Basic Display Adapter** with
`hw_render=0`. DXVK gives us Proton-like control through `dxgi.customVendorId`, `dxgi.customDeviceId`,
`dxgi.customDeviceDesc` (keys verified present in `third_party/dxvk-3.1.1/x64/dxgi.dll`), plus
`dxgi.enableDummyCompositionSwapchain`.
- `third_party/dxvk.conf` — mode A: adapter reported as `Microsoft Basic Display Adapter` (1b36/0100),
  i.e. *match the Windows reference*; mode B (commented out): DXVK's default, the real Vulkan device.
  Install it **next to `CapCut.exe`** (DXVK reads `dxvk.conf` from the application directory).
- Wine-side alternative if DXVK is not used: `HKCU\Software\Wine\Direct3D` `VideoPciVendorID` /
  `VideoPciDeviceID` / `VideoMemorySize` (read in `dlls/wined3d/wined3d_main.c`) — changes the ids but
  *not* the description, so DXVK's keys are the better lever.

## 16. BREAKTHROUGH — our build paints (2026-10-04 00:50)
`logs/ours_builtin` (our `wine-install/bin/wine`, DXVK off, `:9`, openbox, 100 s):
- At ~t=37 s the root capture stops being black (10 KB): it is CapCut's **"Environment testing"**
  window, painted — CapCut mark in the title bar, title text, spinner, "Testing environment..."
  (`recon/ours_builtin/root_37s.png` … `root_99s.png`, `win_0xc00003_*.png`). Windows shows the same
  window (`recon/win_install/step3b_vedetector.png`).
- The main process **no longer exits at 30–45 s**; it ran the full 100 s.
- Wine error surface shrank to two sites: `fixme:seh:WerRegisterRuntimeExceptionModule` and
  `err:sync:RtlpWaitForCriticalSection`. All the dcomp / d3d11 `CheckFormatSupport` / font fixmes are gone.
- **The dcomp+dxgi port (patches 0023/0024) is what unblocked the first paint.** Control reproducer
  `work/tools/t_d3d11dcomp.cpp`: our build passes every path on `:10`; with DXVK it fails at
  `CreateSwapChainForComposition` (`0x80004001`, not implemented in DXVK's DXGI, `enableDummy…` does not help).

## 17. REMAINING BLOCKER (current focus)
The **main** `capcut.exe` creates its windows — including `DXGI device window` — but leaves them
**`IsUnMapped`**, so the home screen never appears. Two concrete observations:
1. `VEDetector.exe` spawns a child **`VEDetector.exe -cmd_qt6render_dx_hw_support`** that **spins at
   ~95–99 % CPU**. That child is the app's "does Qt6 + D3D11 hardware rendering work here?" probe — the
   exact path the app then relies on. A busy loop there would stall the startup sequence.
2. Wine reports the adapter as `Intel(R) HD Graphics 4000 (8086:0162)` (wined3d's card table,
   `dlls/wined3d/directx.c`; newest Intel entry is UHD 630) and the app concludes
   `dx_hw Adapter support hardware render` / `qt6 support dx hw render!` → `hw_render=1`. The Windows guest
   concludes `sequence_check_result:0`, `page_name:unknow_vendor_card`, `hw_render=0` — i.e. the two machines
   take **different renderer branches**.

## 18. WINDOWS↔WINE LOG DIFF (same app, same phase)
| | Windows guest | Wine (our build) |
|---|---|---|
| adapter | `1B36:0100` Microsoft Basic Display Adapter | `8086:0162` "Intel(R) HD Graphics 4000" |
| `onDetectorManagerCheckFinished` | `sequence_check_result:0 independent_check_result:1` | `sequence_check_result:1 independent_check_result:1` |
| page reported | `unknow_vendor_card` | `success` |
| `EnvDetect.json` | `final_hw_enable=0, hw_render=0, qt6_render_engine=d3d11` | `final_hw_enable=1, hw_render=1, qt6_render_engine=d3d11` |
| `request settings timeout` | present (1×, benign) | present (1×, benign) |
| main app UI | home screen while VEDetector still running (~t=10-60 s) | windows created, never mapped |

Windows logs are extracted at `recon/winlog/` (`winlog.zip` from the guest); the Wine-side counterparts are
`logs/<tag>/VeDetector_*.log`.

## 19. THE APP RENDERS ITS REAL UI (2026-10-04 01:00) — reproduction recipe
Configuration that works: **our build** (`wine-install/bin/wine`, wine-11.18 + the 25-patch series),
**DXVK off** (d3d11/dxgi = builtin), on the **DRI3 display `:10`** (`scripts/start_display.sh :10`),
window manager present (openbox), prefix `capcut-wine/prefix`.

Result: at t≈22–32 s the main process' windows become viewable —
`0xc00010 "CapCut" 1440x994+0+0 → +80+4` (the app window) and
`0xc00012 "CapCut" 352x161+0+0 → +624+433` (the modal) — and the modal renders CapCut's
**"Terms of Service and Privacy Policy"** dialog
(`recon/ours_d10_builtin/win_0xc00012_22s.png`), byte-for-byte the same surface as the Windows reference
`recon/win_install/capcut_launch_t60s.png`.

To continue past it: **click "Agree and continue" at absolute ≈ (783, 560)** on `:10`
(the dialog's absolute origin is (624,433); the button centre inside the 352x161 dialog image is ≈(159,127)).
Keyboard alternative: activate the window (`xdotool windowactivate <id>`) then `xdotool key Return`.
On Windows, "Agree and continue" leads to the home screen ("Create project" + start page) — that is the
acceptance shot.

Note: this run was killed at t=46 s with `exit_code=137` (SIGKILL) — cause not yet established; check
whether it is the harness's own cleanup, memory pressure, or a real crash.

## 20. WHAT IS STILL OPEN
1. Get past the ToS dialog and capture the home screen (in progress by the render agent).
2. Reproduce the click/keyboard acceptance run and screenshot it.
3. Confirm the app is stable (no crash) for several minutes.
4. Decide which of our changes are **CapCut-exclusive** and put them in `patches/local/` (currently the
   series is 100% shared base — 0023/0024/0025 came from the sibling revit project).
5. Run the series' own regression tests (needs `configure` regenerated for `dlls/dcomp/tests`:
   autoconf is at `~/.local/bin/autoconf`, automake/aclocal are absent).
6. Write `patches/README.md` and finish `patches/local/` (empty so far).

## 21. STATUS SNAPSHOT (2026-10-04 01:05)
**Works:** the installer stub downloads the payload under Wine; CapCut 9.5.0.4050 installs; our patched
wine-11.18 launches it; on `:10` with DXVK off the app paints its "Environment testing" window and then
its real **"Terms of Service and Privacy Policy"** dialog — the same surface Windows shows.

**Not yet:** the main window (`0xc00010`, 1440x994 → 1168x648) renders **white with a single black
rectangle** instead of its QML/CEF content (`recon/ours_d10_click2/win_0xc00010_30s.png`), so the home
screen has not been reached; and every harness run ends with the launcher **SIGKILLed at t≈46–49 s**,
which truncates observation. Both are with the render agent.

**Open work items**
1. Why the main window draws white (dialog draws fine) — render agent.
2. Who sends the SIGKILL at ~46 s (not OOM as far as measurable) — render agent.
3. Acceptance shot: click "Agree and continue" at ≈(783,560) on `:10`, then capture the home screen.
4. `patches/local/0026` — `SWbemDateTime` (CLSID `{47DFBE54-CF76-11D3-B38F-00105A1F473A}`) is unregistered
   in Wine and CapCut's `CoCreateInstance` fails on it; agent `SWbemDateTime` is implementing it with a
   Wine-suite test. `recon/RE_VEDETECTOR.md` §5 has the class identity and the proof it is absent.
5. Decide whether the manual `ve_detector/` directory (a copy of `VEAngle/`'s ANGLE DLLs, created 00:22) is
   actually needed now that dcomp works — if the app renders without it, delete it so the tree is clean.
   `recon/RE_VEDETECTOR.md` proves it is not installer output.
6. The series' own regression tests need `configure` regenerated for `dlls/dcomp/tests`
   (`~/.local/bin/autoconf` exists; automake/aclocal do not) — do it in a scratch copy, not the live tree.
7. Optional Wine improvement, measured but not yet acted on: Wine reports the adapter as
   `Intel(R) HD Graphics 4000` (`dlls/wined3d/directx.c` card table; newest Intel entry UHD 630) while the
   machine is Meteor Lake `8086:7d55`, so CapCut takes a different renderer branch than on Windows
   (`sequence_check_result` 1 vs 0, `hw_render` 1 vs 0 — see §18).

## 22. THE PAYLOAD IS DIRECTLY DOWNLOADABLE FROM LINUX (2026-10-04 01:10)
The Windows-guest agent recovered the stub's download URL from a user-mode **minidump of the running
downloader** (its own `auto_updater.cc(1952)` log line in memory), and it is a plain CDN object:

```
https://sf16-web-tos-buz.capcutstatic.com/obj/capcut-web-buz-sg/packages/CapCut_9_5_0_4050_capcutpc_0_creatortool.exe
559,656,336 bytes   sha256 e3755d1798fdea572e4a781e5b39f759b3f2c32cc5d590e71006df7b6f00664f
```

Verified from the host: `HTTP/2 200`, `content-length: 559656336` — byte-identical in size to the payload the
stub downloaded here under Wine, whose sha256 is the same value. `scripts/fetch_payload.sh` fetches and
hash-checks it. **So neither Windows nor the stub is needed to obtain or reproduce CapCut.**

Other endpoints the stub uses (for the record): config
`https://mcs-v2-boot.capcutapi.com/v1/json`, `https://mcs.zijieapi.com/v1/json`; app settings
`https://editor-api-v2-boot.capcutapi.com` (app_id `423531`, key `windows_update_oversea`); UI banners
`lf16-beecdn.ibytedtos.com`. The Windows guest's full tree is also archived at
`recon/win_install/capcut_payload.zip` (836 MB, sha256 `4d282da0…`, 4084 files / 1,665,551,280 bytes) with a
file listing at `recon/win_install/capcut_listing.txt`.

Windows reference (guest) facts confirmed by that agent: interactive stub launch is what works (`/S` exits
after creating a 0-byte log); CapCut auto-launches `Apps\CapCut.exe` on install; the home screen needs no
login and appears after the ToS "Agree and continue".

## 23. ACCEPTANCE REACHED — CAPCUT'S HOME SCREEN RENDERS UNDER WINE (2026-10-04 01:15)
`recon/ours_d10_winconf/HOME_SCREEN.png` is CapCut's **full home screen** running under our patched
wine-11.18: "Create project" banner, "Sign in"/"Join Pro", Home/Library, EditPilot "How can I help you edit
today?", "AI-powered creative suite", "Projects", "Invite friends", the CapCut promo card. Verified by me
directly. Same window state at t=20 s and t=38 s (12,879 colours, mean 0.057 — the hardware-branch runs were
uniformly white, mean 0.865).

**Working configuration**
- Wine: `wine-install/bin/wine` = wine-11.18 + the 25-patch series (dcomp 0023 + dxgi 0024 are the load-bearing pair)
- DXVK: **off** (`d3d11`/`dxgi` = builtin)
- Display: `:10` (Xwayland, **DRI3**) with a window manager (openbox)
- Prefix: `prefix/`
- **Config fixup (documented, not a Wine patch):** the app must take its **software/no-hardware** branch,
  which is exactly the branch the Windows reference guest takes. The render agent backed up the Wine config
  to `recon/config_wine_backup/` and copied the Windows values from `recon/winlog/Config/`
  (`EnvDetect.json`, `EnvDetectSimulate.json`, `ve_hw_check.ini`), and for `globalSetting` used the Windows
  flags (`hardwareRenderEnable=false`, `hardwareRenderForbid=true`, `prerenderEnable=0`,
  `renderIndexTrackModeDefault=false`) while keeping Wine's own cache *paths*.
- In the **hardware** branch Wine reports a capable adapter so the app picks hardware rendering — and the main
  window then stays uniformly white. So the remaining render defect is in the hardware/hardware-render path,
  most likely tied to the EffectSDK's AGFX GL/ANGLE initialisation (the `ve_detector/libEGL.dll` failure,
  `recon/RE_VEDETECTOR.md`), which the software branch never exercises. Windows avoids that branch too
  (`hw_render=0`), so the software branch is the faithful reproduction, not a workaround.

**Correction from the render agent:** the "white window with a black rectangle" was *not* a render artefact —
the black rectangle is exactly the ToS dialog's occluded area measured inside the main window
(`352x161+544+429`); `import` of an occluded window reads the covered region as black. The hardware-branch
main window was simply uniformly white.

**Also created:** `…/CapCut/User Data/Projects/com.lveditor.draft/` — the app shows a
"Project saved path not found" modal when it is missing.

## 24. THE ~100 s CRASH — ROOT CAUSE LOCALISED (2026-10-04 01:25)
Full write-up: `recon/CRASH100S.md`. From the rescued crashpad dump of the solo run that reached the home
screen (`logs/ours_d10_final/crash.dmp`, 201,663,272 bytes; parse with `scripts/dmp_threads.py` +
`tools/venv/bin/python` — the app's own `minidump_stackwalk.exe` is 32-bit and cannot run on our
x86_64-only build):

```
EXCEPTION_ACCESS_VIOLATION   read from address 0xFFFFFFFFFFFFFFFF (-1)
ExceptionAddress 0x6fffc3619943  ->  metasecml.dll + 0x29943      (tid 0x45c)
```

`metasecml.dll` is CapCut's own VMProtect-packed security module (`.text` size 0; real code in `.z+[`,
`.9~W`, `.Qw<`), so the instruction cannot be disassembled statically. Reading `-1` is the signature of a
**handle sentinel used as a pointer** — `INVALID_HANDLE_VALUE` and `GetCurrentProcess()` are both `-1`.
Its imports narrow the search to `CreateToolhelp32Snapshot` / `FindFirstFileExW` / `FindFirstVolumeA` /
`GetCurrentProcess` (KERNEL32) and `CM_Get_DevNode_Status*`, `WlanEnumInterfaces`, `GetAdaptersAddresses`,
`OpenSCManagerA`, `ImageLoad`, `WinVerifyTrust`. Wine stubs observed in the same window:
`fixme:setupapi:CM_Get_DevNode_Status_Ex`, `fixme:wlanapi:WlanEnumInterfaces semi-stub`,
`fixme:iphlpapi:GetPerTcpConnectionEStats stub`, `fixme:process:GetProcessMitigationPolicy stub`.
Two of those are on metasecml's import list — that is the short list to answer next, by probe against the
Windows guest, exactly as was done for `t_d3d11dcomp.cpp`.

## 25. SECOND PATCH ADDED (2026-10-04 01:20)
`patches/series/0026-wbemdisp-implement-SWbemDateTime.patch` — Wine did not register/implement
`CLSID_SWbemDateTime {47DFBE54-CF76-11D3-B38F-00105A1F473A}`, so CapCut's `CoCreateInstance` failed with
`REGDB_E_CLASSNOTREG` (`recon/RE_VEDETECTOR.md` §5). Implemented in `dlls/wbemdisp` (new `datetime.c` +
IDL + tests) by the `SWbemDateTime` agent: commit `d460abf`, probe `80040154` → `S_OK`, Wine test
`test_datetime` 225 tests/1 failure before → **267 tests/0 failures** after, and the conversions were
checked against the **real `wbemdisp.dll` on the Windows guest** (both UTC and offset timestamps, intervals,
component out of range, malformed input). Classified honestly as a **general Wine gap found via CapCut**,
not app-exclusive, so it lives in `series/` (26/26) and `patches/local/` is still empty.
The series still reproduces the tree byte-for-byte from pristine (re-verified for 26).

## 26. INDEPENDENT VERIFICATION BY MAIN (2026-10-04 01:25)
Ran the acceptance myself with the documented configuration, nothing else on the machine:
`WINELOADER_BIN=$CCWS/wine-install/bin scripts/cc_run.sh verify3 200 "err+all,fixme-all"` on `:10`.
`recon/verify3/root_37s.png` (155 KB, versus 332-byte black frames before the dcomp port) is CapCut's full
home screen: CapCut mark, Sign in / Join Pro, Home / Templates, **Create with AI** (Video Studio, Design
Studio, More tools), the "Create project" banner, EditPilot "How can I help you edit today?", "AI-powered
creative suite", Projects with its search/filter/Trash/Project sync bar, Invite friends, the promo card.
The "Project saved path not found" modal is still shown even though
`…/User Data/Projects/com.lveditor.draft/` exists — cosmetic, still to chase.

Two confounders worth remembering: an earlier identical run stalled at "Environment testing" purely because
another agent was running `make -j20` at the same time (`uptime` showed load 34 on 22 cores; the stall
surfaced as four `err:sync:RtlpWaitForCriticalSection … loader_section` timeouts). **Check `uptime` before
judging a run.** And `scripts/cc_run.sh` holds `logs/.cc_run.lock`; a second run refuses to start rather
than killing the first.

**Where the project stands**: CapCut opens like Windows under Wine (this §), on a 26-patch series whose
dcomp+dxgi pair is what makes any paint possible, with documented non-patch fixups (DRI3 display, WM,
software render branch, `ve_detector/` ANGLE layout, projects dir). The remaining defects are the ~100 s
`metasecml.dll` access violation (§24, agent `Crash100s` on it) and the hardware-render branch staying
white. `patches/local/` is still empty — every patch so far is a general Wine gap, which is the honest
answer to "which patches are exclusive to this app".

## 27. RUN-LIFECYCLE NOTE (important for whoever resumes)
`scripts/cc_run.sh`'s start-up step kills every pre-existing process in the prefix, so **starting a run ends
whatever the previous run was observing** — my `verify3` acceptance run was cut at t=39 s exactly when the
next run started (its home-screen frames at t=20–37 s are the proof that matters and they survived). The
`logs/.cc_run.lock` only prevents a second run from starting while the first harness is *alive*; once a
harness has exited (or been killed) the next one is free to clean up. Before starting a run, check
`pgrep -fa cc_run.sh`, and read `logs/<tag>/timeline.log` for `LAUNCHER EXITED` / `procs_left` rather than
trusting a single exit code.

Also: the `Killed` message in a driver log is a SIGKILL of the *launched* process, which is normal at
hand-off — the app's real processes continue (the timeline's `procs_left` / `last_time_app_proc_seen_s`
follow them). Do not read it as the app crashing.

## 28. THE ~100 s CRASH: ROOT CAUSE FOUND AND FIXED — `EnumServicesStatusEx` buffer layout
The `metasecml.dll` access violation (§24) is **not** in CapCut's packed code; it is caused by a Wine bug in
`EnumServicesStatusEx` (agent `Crash100s`):

* Windows anchors the enumerated service **strings at the end of the caller's buffer** and zeroes the space
  between the array of `ENUM_SERVICE_STATUS_PROCESS` entries and that string block.
* Wine packed the strings **immediately after the array**, so the entry right after the last returned service
  held the first service name (e.g. `"Eventlog"`) instead of a `NULL` terminator.
* CapCut's `metasecml.dll` (its machine-fingerprinting / anti-tamper module) walks that array until a `NULL`
  entry and treats the next entry's string field as a pointer — so it dereferenced those characters, which is
  exactly the dump's `EXCEPTION_ACCESS_VIOLATION` read from `0xFFFFFFFFFFFFFFFF` at `metasecml.dll+0x29943`
  (tid 0x45c) about 100 s into every run.

Evidence: a probe of the same calls against Windows 11 (`work/tools/svcenum_probe*.c`) shows Wine *before* →
`entry[returned] == "Eventlog"`, and Windows / Wine *after* → `NULL` with the string block anchored to the
buffer end. `dlls/advapi32/tests/service.c` asserts the layout for both the A and the W call: **2 failures
without the fix, 766 tests / 0 failures with it**.

Files: `dlls/sechost/service.c`, `dlls/advapi32/service.c`, `dlls/advapi32/tests/service.c`. Patch:
`patches/series/0027-*.patch` — a **general** Wine gap (any `EnumServicesStatusEx` caller is affected), found
via CapCut, so it goes in `series/` and `patches/local/` remains empty. Commit `c94f44e` on `merged`;
27/27 reproducibility re-verified (`git worktree` of `2ca2d8f` + `patch -p1` for all 27, `diff -rq` against
`git archive HEAD` = empty). The test now pins the anchor as well as the terminator for both the A and the W
call: 6 failures without the fix, **769 tests / 0 failures** with it.

Acceptance: **`logs/fix330` — a solo run on `:10` lived the full 330 s**, home screen up at t=328 s
(`recon/fix330/root_328s.png`), `last_time_app_proc_seen_s=328`, `launcher_alive_at_end=yes`, no `.dmp`
anywhere. Two attempts at 600 s were aborted by factors unrelated to this crash and with no
`metasecml.dll+0x29943` fault: `logs/fix600` (t=292 s) died when display `:10` was closed externally
(`XIO: fatal IO error 104`), and `logs/fix600b` (t=40 s) crashed in **`Qt6Core.dll+0x162b52`** — a different
module and a different defect, recorded as an open intermittent failure. A clean 600 s run is therefore
still outstanding.

## 29. CRASH FIX ACCEPTED (2026-10-04 02:05) — agent `Crash100s` complete
* Identified call: **`EnumServicesStatusExA`** (after `OpenSCManagerA(NULL,NULL,SC_MANAGER_ENUMERATE_SERVICE)`),
  called twice by `metasecml.dll` (size query, then fill) and then walked with a 0x38 stride until
  `lpServiceName`/`lpDisplayName` is NULL. Found by disassembling the faulting RIP **out of the crashpad dump**
  (crashpad stores memory around the faulting RIP + full thread context: `work/tools/dmp_fault.py`) — the
  packed bytes `42 80 3c 02 00` = `cmpb $0,(%rdx,%r8,1)` are the inline `strlen` — and by `+relay` restricted
  to `metasecml` (`RelayFromInclude`) to see the two calls on the same thread.
* Commit **`c94f44e`** (3 files, +133/−3): `dlls/sechost/service.c` (W: anchor strings at `size-string_bytes`,
  zero the gap), `dlls/advapi32/service.c` (A: same, plus a real `ERROR_INSUFFICIENT_BUFFER` instead of an
  unsigned underflow of `n`), `dlls/advapi32/tests/service.c` (`test_enum_svc_ex`).
* Tests: `advapi32_test.exe service` **769 tests, 6 failures → 0 failures**; the three assertions per call pin
  the gap, the NULL entry after the last service, and the end-anchored string block, for A *and* W.
* Reproducibility re-verified at **27/27**: pristine worktree + `patch -p1` for all of `series/` +
  `diff -rq -x .git` against `git archive HEAD` = identical.
* Acceptance (**verified by me**): `logs/fix330` — solo run, app alive to t=328 s, 8 app processes, **no `.dmp`
  anywhere**, frames 246 KB at t=69/104/232 s. The prefix's `Crash/reports` holds only empty dirs.
* Still open: (a) a clean **600 s** run — the first attempt died because display `:10` was closed externally
  (`XIO: fatal IO error 104 … on X server ":10"`; restarted), the second (`logs/fix600b`) died at t=40 s with
  a dump whose `ExceptionAddress` is **`Qt6Core.dll+0x162b52`** — a *different* module and a different defect
  (no `metasecml.dll+0x29943` fault has occurred in any post-fix run); (b) the hardware-render branch still
  paints white; (c) the "Project saved path not found" modal.

## 30. THE SECOND, RARER CRASH (from `logs/fix600b`, t≈40 s) — characterised, not yet rooted
```
EXCEPTION_ACCESS_VIOLATION  read from 0xFFFFFFFFFFFFFFFF (-1)   tid 0x558
ExceptionAddress 0x6ffffbfa2b52 -> Qt6Core.dll + 0x162b52
```
`Qt6Core.dll` is not packed, so the site disassembles statically:
```
180162b52:  66 39 02        cmp %ax,(%rdx)          ; inline wcslen loop
180162b60:  49 ff c0        inc %r8
180162b63:  66 42 39 04 42  cmp %ax,(%rdx,%r8,2)
180162b68:  75 f6           jne 180162b60
```
i.e. `wcslen(rdx)` with `rdx == 0xFFFFFFFFFFFFFFFF` — Qt was handed a `wchar_t*` of **-1** with a negative
length (the preceding `test %r8,%r8 / jns` shows the length is an argument and -1 means "measure"), so in Qt
terms this is `QString::fromWCharArray((wchar_t *)-1, -1)`.

Same **`-1` sentinel used as a pointer** signature as §28 — the two faults share a *shape*, not a site. What
differs: this one is in the app's Qt layer, occurs far more rarely (once, at t≈40 s of a 600 s attempt,
where the same build had just run 330 s clean, and no `metasecml` fault has recurred), and the crashpad dump
does **not** contain the faulting bytes here (`Address not in memory range` from `work/tools/dmp_fault.py`).
The run's own stdout shows the app's crash handler then running `minidump_stackwalk` and failing to read its
own streams (`minidump.cc:6319 ReadUTF8String string length … exceeds maximum`), plus
`err:ole:com_get_class_object apartment not initialised`.

Next: reproduce it (a clean solo 600 s run is still outstanding — the first 600 s attempt died only because
display `:10` was closed externally, `XIO: fatal IO error 104`), and if it recurs, find the caller of that
`fromWCharArray` (the app passes -1 from somewhere) rather than guessing.

## 31. OPEN ITEM: "Project saved path not found" modal
The modal reads "Project under path C:\users\asdf\AppData\Local\CapCut\User Data\Projects\com.lveditor.draft
is not found. Check if a disk is inserted or a disk path is specified." — but the directory **does exist**
and even contains a `.recycle_bin` the app created itself at install time:
```
prefix/.../CapCut/User Data/Projects/com.lveditor.draft/           (drwxrwxr-x)
  └── .recycle_bin/                                                (drwxrwxr-x+, ACL marker)
prefix/.../CapCut/User Data/Projects/com.lveditor.textTemplate.draft/
```
So the app's existence check is failing on something else — the message's own wording points at a *volume*
probe ("Check if a disk is inserted or a disk path is specified"), e.g. `GetDiskFreeSpaceExW` /
`GetVolumeInformationW` / drive-type checks on the C: the path resolves to under Wine, or a write probe that
the `+`-ACL'd directory defeats. `User Data/Config/globalSetting` is where the app stores the path. The
Windows reference guest does not show this modal. Cosmetic for "opens like Windows", but it is a Wine-vs-
Windows difference of exactly the kind this project exists to fix, so it is on the list.

## 32. WHY LATER RUNS BEHAVED DIFFERENTLY — the config fixup is NOT STICKY
`User Data/Config/globalSetting` is **rewritten by the app** from its own environment detection: after the
successful 330 s acceptance (`logs/fix330`) the file came back as `hardwareRenderEnable=true` /
`hardwareRenderForbid=false` even though it had been set to the Windows values. So every later run
(`fix600`, `fix600b`, `final600`) started in the **hardware-render branch**, not the one that renders — which
explains the run-to-run inconsistency (white window, a different crash at t≈40 s, and `final600` exiting with
an empty stdout at t=2 s while a manual launch of the same exe produced the normal fixme output and ran).

**Consequence for the fixups:** editing `globalSetting` is only ever good for one run. The durable levers are
1. `User Data/Config/EnvDetectSimulate.json`, which the app *replays* (`VEDetector.exe -detect_simulate_check`)
   — the agent's working recipe used it alongside the Windows `EnvDetect.json`/`ve_hw_check.ini`; and/or
2. making Wine's adapter report the way the Windows guest's does, so the app's own detection concludes
   `hw_render=0` — the Windows guest reports "Microsoft Basic Display Adapter" (QXL 1b36:0100) with
   `hw_render=0`, while Wine reports `Intel(R) HD Graphics 4000` (8086:0162) and the app picks hardware.

Either way the *real* fix is the hardware-render branch (a video editor wants acceleration, and the user asked
for the real GPU to be exposed), so item 3 of the Hardening list is the one that matters most: make the
hardware branch paint. Until it does, every acceptance run must re-apply the software-branch config
immediately before launching, and that must be stated in the run recipe.

Also confirmed while checking: `Configure.ini last_version=9.5.0.4050` is intact, `ve_detector/` is present,
`Crash/reports/` holds only empty dirs, load 4.4 — i.e. the prefix itself is healthy.

## 33. "Project saved path not found" — what it is NOT
The app's own config matches the Windows reference for every path key, so the message is not about the string:
```
Wine                                              Windows reference
currentCustomDraftPath=…\User Data\Projects\com.lveditor.draft    (identical, only the drive letter case differs)
customMaterialPath=…\User Data\Cloud files
currentCachePath=…\User Data\Cache
customPresetPath=…\User Data\Presets
```
and the directory itself exists (`…\Projects\com.lveditor.draft\` with the app's own `.recycle_bin`, plus
`…\Projects\com.lveditor.textTemplate.draft\`). So the failing check is a *volume* probe on the drive the path
resolves to (its own wording: "Check if a disk is inserted or a disk path is specified") — e.g.
`GetDriveTypeW`/`GetVolumeInformationW`/`GetDiskFreeSpaceExW`, or a write probe that the `+`-ACL'd directory
defeats. Next measurement: probe those three calls on `C:\users\asdf\AppData\Local\CapCut\User Data\Projects`
under Wine and on the guest and diff them — the same method that found the `EnumServicesStatusEx` defect.
Low severity (the home screen renders behind it); it is a genuine Wine-vs-Windows difference and is listed
as such rather than papered over.

## 34. CLEAN 600 s ACCEPTANCE RUN — PASSED (2026-10-04 02:25)
`logs/final600b`, solo, `WINELOADER_BIN=$CCWS/wine-install/bin`, `:10`, DXVK off, software-render branch
config re-applied immediately before launch:
```
FIRST SEEN app at t=0s
sample t=598s  procs=8  capcut_windows=43  launcher_alive=1     <- last sample
exit_code=137 elapsed_at_exit=604s launcher_alive_at_end=yes    <- 137 is the harness's own end-of-run kill
screenshots=2001
```
* **No crash dump anywhere**: 0 `.dmp` in `logs/final600b` and the prefix's `Crash/reports/` holds only empty
  dirs. Earlier runs always produced one (metasecml at ~98–130 s before the fix, Qt6Core once after).
* `n_app_procs_left=8`, `last_time_app_proc_seen_s=598` — the app was still up when the run ended.
* Frames to `root_604s_b.png` (94 KB).

This closes the stability item: **CapCut now stays up for 10+ minutes on our patched Wine and does not
crash**, i.e. the `EnumServicesStatusEx` fix (series/0027) holds, and the only remaining defects are the
hardware-render branch painting white and the cosmetic "Project saved path not found" modal.

**The one operational rule that makes this reproducible:** the software-branch config is transient (§32) —
the app rewrites `User Data/Config/globalSetting` from its own detection, so it MUST be re-applied
immediately before every acceptance launch (`EnvDetect.json`, `EnvDetectSimulate.json`, `ve_hw_check.ini`
from `recon/winlog/Config/` + `hardwareRenderEnable=false` / `hardwareRenderForbid=true`). Without that, the
run starts in the hardware branch and the results are not comparable.

## 35. HARDWARE BRANCH: ONE REAL DEFECT FOUND AND FIXED, THE WHITE WINDOW REMAINS (2026-10-04 12:05)

Agent `HardwareBranch`. Series is now **0028 + 0029** (29 patches), reproducibility re-verified at
**29/29** (pristine worktree `2ca2d8f` + `patch -p1` for every `series/*.patch`, `diff -rq` against
`git archive HEAD` = empty). `patches/local/` is still empty — both new patches are general Wine
gaps, not app-exclusive ones.

### 35.1 The measurable defect: an RGBA8 composition swap chain could not be created

The probe `work/tools/t_compositionsurface.exe` and a `+dxgi` trace of a hardware-branch run both
show what the app asks for:

```
trace:dxgi:dxgi_factory_CreateSwapChainForComposition desc: 1440x994 format 0x1c
        buffers 2 effect 0x4 alpha 0x1 flags 0        (pid 384, a CEF --type=gpu-process)
```
`0x1c` = `DXGI_FORMAT_R8G8B8A8_UNORM`, `0x4` = `FLIP_DISCARD`, `0x1` = `DXGI_ALPHA_MODE_PREMULTIPLIED`.

`dlls/dxgi`'s composition port (series/0024) forces `DXGI_SWAP_CHAIN_FLAG_GDI_COMPATIBLE` on every
composition swap chain, and `dlls/d3d11/device.c:dxgi_device_parent_register_swapchain_texture`
then unconditionally added `D3D11_RESOURCE_MISC_GDI_COMPATIBLE` to the back-buffer texture's
description. D3D11 only permits that flag for `B8G8R8` formats, so wrapping an RGBA8 back buffer
failed:

```
warn:d3d11:validate_texture2d_desc Incompatible description used to create GDI compatible texture.
warn:d3d11:d3d_texture2d_create Failed to validate texture desc.
err:dxgi:d3d11_swapchain_create_d3d11_textures Failed to create parent swapchain texture, hr 0x80070057.
err:dxgi:d3d11_swapchain_init Failed to create d3d11 textures, hr 0x80070057.
warn:dxgi:dxgi_factory_CreateSwapChainForComposition Failed to create swapchain, hr 0x80070057.
```

Measured consequences, same prefix and build otherwise unchanged:

| run | build | result |
|---|---|---|
| `hwprobe1`, `hw2` | before 0028 | app gone at t=12–38 s, crash handler processing a dump; no window ever mapped |
| `hwfix1`, `hwfix2`, `hwtrace3`, `hwpid`, `hwrb1`, `hwrb3` | after 0028 | app alive to t=70–160 s with the main window `0xc00010` (1440x994) **mapped** |

`test_create_swapchain_for_composition` (new, `dlls/dxgi/tests/dxgi.c`) pins it: it creates a
composition swap chain with `R8G8B8A8_UNORM` + `DXGI_ALPHA_MODE_PREMULTIPLIED` and reads back buffer 0.

* without 0028: `dxgi.c:5117: Test failed: d3d10: Got unexpected hr 0x80070057` —
  `20446 tests executed (332 todo, 1 failure)`
* with 0028: **`20460 tests executed (332 marked as todo, 2 as flaky, 0 failures)`**, 36 skipped
  (`logs/dxgi_test_pre.log`, `logs/dxgi_test_post.log`)

### 35.2 The remaining white window is NOT the compositor (measured)

`patches/series/0029` adds a staging-texture readback to `dlls/dxgi`'s per-present compositing,
because the existing path cannot read an RGBA8 back buffer at all (see 35.3). It builds and the
`dxgi` suite is green with it, **but it was never exercised by the app**: in every post-0028
hardware-branch run the app creates the 1440x994 RGBA8 swap chain and then never composites
anything — there is no `DCompositionCreateDevice`, no `SetContent`, no `Commit`, i.e. no
`__wine_dxgi_set_composition_target` / `d3d11_swapchain_composite` at all
(`grep -c "now composites into" logs/hwtrace3/stdout.log logs/hwrb3/stdout.log` → 0). The only run
that did composite was `hwfix2` (two CEF GPU processes, two dcomp targets, windows `0x70112` and
`0x40212`), and it also ended with a white main window. So **the white main window is not our
compositing being called and failing**; whatever creates that swap chain never asks Wine to show it.

Windows reference calls for comparison: on the guest the same app also creates no hardware-branch
composition swap chain (`hw_render=0`), so this state has no Windows counterpart to match.

### 35.3 Why the composition readback needed a new path

`work/tools/t_compositionsurface.cpp` (Wine, our build, `:10`):

```
=== R8G8B8A8_UNORM ===
CreateSwapChainForComposition(RGBA/premultiplied)          ok
      back buffer: format 28 64x64  BindFlags 0x20  MiscFlags 0        <- no GDI_COMPATIBLE
  IDXGISurface1::GetDC                                     FAIL (8876086c = WINED3DERR_INVALIDCALL)
  IDXGISurface::Map(DXGI_MAP_READ)                         FAIL (80070057)
=== B8G8R8A8_UNORM ===
      back buffer: format 87 64x64  BindFlags 0x20  MiscFlags 0x200 (GDI_COMPATIBLE)
  IDXGISurface1::GetDC                                     ok
```
and `warn:d3:dined3d_texture_create_dc Cannot create a DC for format WINED3DFMT_R8G8B8A8_UNORM`
(`work/tools/t_compositionsurface_wine_after.txt`): wined3d has no DDI format for RGBA8, so
`wined3d_texture_create_dc` cannot build a DC for it and `IDXGISurface::Map` is refused because the
swap-chain texture has no `MAP_R` access. 0029 therefore copies the back buffer into a
`D3D11_USAGE_STAGING` texture and blits it with `StretchDIBits`, whose `BI_BITFIELDS` masks carry
the channel order. Adding a DDI format mapping instead was rejected: Wine's own
`dlls/gdi32/tests/bitmap.c:test_D3DKMTCreateDCFromMemory` records that Windows rejects
`D3DDDIFMT_A8B8G8R8`.

### 35.4 What is ruled out, and the next experiment

* **Not the adapter identity.** The hardware branch is white with both fabricated adapters seen in
  the logs (`Intel(R) HD Graphics 4000` 8086:0162 and `NVIDIA GeForce GTX 470` 10DE:06CD), so the
  white window is not caused by one wrong card entry; matching the guest's "Microsoft Basic Display
  Adapter" would only move the app into the branch Windows itself takes, which README §5 already
  documents as a workaround, not a fix.
* **Not DXVK** (off, `d3d11`/`dxgi` = builtin in every run above), **not the display** (`:9` and
  `:10` behave the same), **not the `ve_detector/` ANGLE directory** (present throughout).
* **Not our composite** — it is never called for the white window (35.2).
* **Next experiment:** identify the creator of the 1440x994 RGBA8 composition swap chain and check
  why it is never given to a compositor. Two candidate leads, both cheap:
  1. `dcomp.spec` still has **`@ stub DCompositionCreateSurfaceHandle`** — Chromium's
     GPU/browser split uses it to pass a composition surface between processes, and our dcomp
     cannot accept such a surface in `IDCompositionVisual::SetContent`. This is the most likely
     missing piece for the CEF-rendered part of the UI.
  2. Trace `GetCurrentProcessId()` alongside the swap chain description (the trace added by 0029
     already prints the process id of `CreateSwapChainForComposition` callers) and match it to the
     timeline's process list, to say whether the swap chain belongs to the app's Qt layer or to CEF.

### 35.5 Defect B ("Project saved path not found") — NOT STARTED

No measurement was taken for it in this pass; the volume probe
(`GetDriveTypeW`/`GetVolumeInformationW`/`GetDiskFreeSpaceExW` + write probe, Wine vs guest) is
still the next step and is unchanged from §33.

## 36. OPERATIONAL: THE DISK FILLED TO 100% (2026-10-04 12:05) — and it was visible from inside Wine
`/` was at **201/213 GB, 1.2 GB free**. That is the direct explanation of what `work/tools/volprobe.exe`
reported from inside the prefix:

```
GetDiskFreeSpEx : ok=1 avail=1149 MB total=217615 MB
```

i.e. Wine was reporting the *host's* real free space, and there was almost none. Captured by the volume probe
written for the "Project saved path not found" item (`work/tools/volprobe.c`, Wine output in
`work/tools/volprobe_wine.txt`); the other Wine answers look correct — `GetDriveTypeW=3 (FIXED)`,
`GetVolumeInformationW ok=1 fs="NTFS" serial=43000000 flags=0100008a` (note: **empty volume label**),
`GetFileAttributesW=00000010 dir=1`, and a write probe into the directory **succeeds**.

**Freed ~6.4 GB, none of it irreplaceable:**
* 2.2 GB of duplicate `crash.dmp.saved` copies (the crashpad dumps were stored twice per run);
* the payload copies — `vmshare/capcut_payload.zip`, `recon/win_install/capcut_payload.zip`,
  `work/payload/app_package.exe` (2.2 GB) — all three are re-creatable and hash-checked:
  `scripts/fetch_payload.sh` re-downloads the 559,656,336-byte payload from the CDN and verifies
  `e3755d17…`, and the Windows tree's listing survives as `recon/win_install/capcut_listing.txt`;
* my throwaway `prefix-test2` (1.2 GB) — recreatable with `wineboot -u` + `scripts/install_dxvk.sh`;
* the superseded crash dumps, **keeping the two the write-ups cite**: `logs/ours_d10_final/crash.dmp`
  (the `metasecml` crash, §24/§28) and `logs/fix600b/crash.dmp` (the `Qt6Core` one, §30).

Now **7.6 GB free (97%)** — still tight, so: **anyone running CapCut or building Wine must check `df -h /`
first**, and capcut runs must be told to stop producing 200 MB dumps where possible. This also invalidates
nothing in the earlier findings, but it is a plausible contributor to the erratic behaviour seen after the
330 s acceptance (runs that exit oddly, files that fail to be written) and it must be checked before blaming
Wine for anything new.

## 37. MODAL ITEM — Wine half measured; Windows half blocked on guest access (2026-10-04 12:10)
Instrument: `work/tools/volprobe.c` (built, staged to `vmshare/volprobe.exe`). Wine output in
`work/tools/volprobe_wine.txt`:
```
GetDriveTypeW   : 3 (FIXED)
GetVolumeInfoW  : ok=1 err=0 vol="" fs="NTFS" serial=43000000 flags=0100008a
GetDiskFreeSpEx : ok=1 err=0 avail=1149 MB total=217615 MB      <- was the host's real free space; see §36
GetDiskFreeSpW  : ok=1 err=0 sec=8 bps=512 nfree=294208 ntotal=55709576
GetFileAttrs    : 00000010 dir=1
CreateFileW     : write probe into the directory SUCCEEDS
```
So Wine's answers are self-consistent and the write probe passes; the two candidates that could still make
CapCut say "not found" are the **empty volume label** (`vol=""`) and the volume **serial `0x43000000`**.
Deciding between them (and against "none of these") needs the same binary run on the guest.

**Blocked:** the `win11` domain is `running` but the guest is currently unreachable — `ping 192.168.122.230`
100 % loss, SMB 445 closed, and `scripts/vmcmd.sh` returns an empty `guest_cmd_out.txt` (its PowerShell agent
is not answering). Guest access was working earlier in the session (the whole Windows reference in
`recon/GUEST_CAPTURE.md` came through it), so this is a guest-side state problem, not the host channel: the
host `vmserv.py` is still listening on 8000 and `vmshare/cmd.txt` is being written. Recovery is either to
wake/reconnect the guest (its desktop session may be asleep or its network down) or to restart
`pbi_svc.ps1`-style agent inside it. **Nothing else in the project needs the guest**, so this only blocks this
one measurement.

### 35.6 Follow-up measurements (agent `HardwareBranch`, same day)

**A1 — who owns the 1440x994 RGBA8 composition swap chain?** The 0029 trace prints the caller's
process id: `desc: 1440x994 format 0x1c buffers 2 effect 0x4 alpha 0x1 flags 0 (pid 348)`
(`logs/hwattr/stdout.log`). In that run's timeline, **348 is CapCut's main process**: it is the
`--parent-process-id=348` of every CEF renderer, and `parfait_crash_handler` carries
`--annotation=main_pid=348` (Unix pid 1248253, `CapCut.exe`). So the swap chain is created by the
process that hosts Qt **and** CEF's browser side — *not* by a CEF `--type=gpu-process`. The natural
reading is that it is Qt's RHI, and that whatever Qt then does with it (`DCompositionCreateSurfaceHandle`
is still `@ stub` in `dcomp.spec`, and nothing in the app's runs ever reaches
`DCompositionCreateDevice`/`SetContent`/`Commit`) silently fails, leaving the window white.
Attributing it *definitively* needs a Qt-side trace (the composition swap chain description plus
whichever dcomp entry point Qt calls next), which is the next experiment — not yet done.

**B — does Windows show the modal?** **No.** `recon/win_install/capcut_after_agree.png` shows the
guest's home screen with a "Get started with our professional and AI-powered video editor" tooltip
and **no** "Project saved path not found" modal, so the modal is a genuine Wine-only difference.

**B — guest half of the volume diff: blocked.** The guest command channel did not answer:
`vmshare/cmd.txt` is written and `vmserv.py` (pid 298237, port 8000) is running, but
`vmshare/guest_cmd_out.txt` stays at 0 bytes for `Write-Output "hello-from-guest"` and for
`echo guest-alive & vol C:` (two attempts, 2026-10-04 ~12:07–12:09), so the PowerShell poll loop in
the guest looks dead. The host-side answers from Main's probe (`work/tools/volprobe_wine.txt`) are in
the interjection: `GetDriveTypeW` 3 (FIXED), `GetVolumeInfoW` ok `vol="" fs="NTFS"
serial=43000000 flags=0100008a`, `GetDiskFreeSpaceExW` ok, `GetFileAttrs` 0x10 dir, `CreateFileW`
write probe succeeds. The two fields to compare first are the **empty volume label** and the volume
**serial 0x43000000**; the guest run needs the agent restarted first.

**Disk note (from Main's interjection):** `/` was 97 % full (1.2 GB free) during several of the runs
above and is now 7.6 GB free after Main deleted superseded dumps; the two dumps cited in STATE §24
(`logs/ours_d10_final/crash.dmp`) and §30 (`logs/fix600b/crash.dmp`) were kept. Anything concluded
from a run made in that window should be re-checked, which is why the runs in §35.1/§35.2 are all
post-cleanup and re-runnable with `scripts/cc_run.sh`.

## 38. CORRECTION: the guest channel is ALIVE — it is the upload path that fails
§37 said the guest was unreachable. That was wrong, and the evidence is in the server log
(`logs/vmserv.log`, last entry 12:07):
```
192.168.122.230 - "GET /cmd.txt HTTP/1.1" 200 -
192.168.122.230 - "GET /cmd3.txt?t=639267304553653699-2028092801 HTTP/1.1" 200 -
192.168.122.230 - "GET /cmd_admin.txt HTTP/1.1" 404 -
```
So **at least two guest-side pollers are running** (the original `cmd.txt` loop from the Power BI project, and a
`cmd3.txt` loop with a timestamp cache-buster) and `virsh screenshot win11` captures the screen fine. What
fails is the *return* path: `scripts/vmcmd.sh` writes `cmd.txt` and waits for the guest to upload
`guest_cmd_out.txt`, and that file arrives **0 bytes**. With several channels in play (cmd.txt, cmd3.txt,
cmd_admin.txt) they are very likely clobbering a shared output filename. `ping`/445 being closed is normal
for this guest (its firewall), not a symptom — the channel is guest-initiated outbound HTTP.
**To use it:** pick a channel that is actually polled (`cmd3.txt` is live) and confirm which output filename
its poller uploads before trusting it, or start a fresh single-purpose poller in the guest. Note
`GuestCapCutCapture` also reported being unable to push `volprobe.exe` to the guest, so the file-transfer
direction needs the same check.

## 39. ROOT CAUSE OF SERIES/0028 (recorded from the agent's final report)
`series/0024` (the DXGI composition swap chain) forces `DXGI_SWAP_CHAIN_FLAG_GDI_COMPATIBLE` on **every**
composition swap chain, and `dlls/d3d11/device.c`'s `dxgi_device_parent_register_swapchain_texture` then
unconditionally added `D3D11_RESOURCE_MISC_GDI_COMPATIBLE` — which D3D11 permits only for `B8G8R8` formats.
The app asks for `R8G8B8A8_UNORM` + `PREMULTIPLIED` + `FLIP_DISCARD` at 1440x994, so
`CreateSwapChainForComposition` failed `E_INVALIDARG` and the hardware branch died at t=12–38 s with the
crash handler running. `0028` gates the flag on the format; `0029` adds a staging-texture readback (with
per-format DIB masks) so the RGBA8 composition buffer can be read at all, since wined3d has no DDI format for
`R8G8B8A8` (`GetDC` fails `8876086c`, `Map` fails `80070057` for RGBA8; BGRA8 works). New test:
`dlls/dxgi/tests/dxgi.c:test_create_swapchain_for_composition`; suite 20446/1 failure → **20460/0**.
**Still open** (now with agent `QtDcompPath`): in every post-fix hardware run the app creates that swap chain
and then never composites — but "no compositor is involved" was inferred from Wine's `dcomp` debug channel,
which is only emitted with `WINEDEBUG=+dcomp`; that run had it off. The agent's first job is to settle that
with `+dcomp,+dxgi` before anything is implemented, since the app swallows Qt's own warnings (it installs its
own message handler) so absent Qt logging proves nothing. `DCompositionCreateSurfaceHandle` remains `@ stub`
with nothing in `dlls/dcomp` referencing it — deliberately **not** implemented speculatively.

## 40. GUEST CHANNEL: diagnosed, still not fixed (2026-10-04 12:20)
Attempted fixes and what each showed.

**The pollers fetch but do not execute.** The server log resolves it:
```
20354 GET /cmd_admin.txt   13783 GET /cmd.txt   9616 GET /cmd3.txt   9 GET /cmd2.txt
160 PUTs, the recent ones 0 bytes: "PUT guest_cmd_out3.txt (0 bytes)" / "PUT guest_cmd_out.txt (0 bytes)"
```
Three concurrent poll loops are fetching their command files roughly every 3 s, yet the only successful
transfers *back* are 0-byte outputs. Earlier in the session the same guest did fetch and run files
(`svcenum_probe.exe` ×4, `svcenumw_probe.exe` ×2, `facts.ps1`, `capture.ps1`, `winmove.ps1` — the
`Crash100s` agent's `vmcmd3.sh`/`cmd3.txt` path worked), so the machinery exists; what is broken now is the
execute+upload half, most likely because several pollers share one output filename and/or one of them is
stuck mid-`Invoke-Expression`.

**Fixes attempted, in order:**
1. A dedicated single-purpose poller (`vmshare/cc_svc.ps1`, own `cc_cmd.txt`/`cc_out.txt` pair) started by
   writing its launcher into `cmd.txt` **and** `cmd3.txt` — the host saw **no** `GET /cc_svc.ps1`, i.e. the
   pollers read the command without running it.
2. The keyboard route, to bypass the pollers entirely: `vmshare/vp.bat` does the whole job guest-side
   (download `volprobe.exe`, run it on the project path, `curl -T` the output back). Driving it needs the
   guest's Run dialog, and that is where it failed: `scripts/vm/vmkeys.py "{WIN}r"` did not open it (the
   script taps Meta and then types `r` separately rather than sending the chord), and after
   `virsh send-key win11 KEY_LEFTMETA KEY_R` the screen did change to the desktop
   (`recon/vm_run2.png`, 1.09 MB vs the previous 354 KB) but the typed command still produced no
   `GET /vp.bat`. The guest is also still covered by the CapCut instance the Windows reference capture
   deliberately left running, which is where the first attempt's keystrokes went.
   **Correct technique for next time:** `virsh send-key win11 KEY_LEFTMETA KEY_R` for the chord, then
   confirm the dialog is up from a screenshot *before* typing, and use `virsh send-key` for any other chord.

**What this blocks, and what it does not.** It blocks only the Windows half of the modal comparison. It does
**not** change the item's substance: the guest **does not show the modal at all**
(`recon/win_install/capcut_after_agree.png` — home screen plus a "Get started…" tooltip, no modal), so the
modal is Wine-only, and Wine's side is already measured (`work/tools/volprobe_wine.txt`): the path exists,
the write probe succeeds, and the two oddities are `GetVolumeInformationW` returning an **empty volume
label** and volume **serial `0x43000000`**. Making Wine return a plausible label is therefore a candidate fix
that needs no guest at all — and it is the cheapest remaining item in the project.

## 41. THE LIKELY REMAINING GAP: OUR dcomp LACKS THE DXGI-SURFACE COMPOSITION PATH (2026-10-04 12:30)
Compared the two dcomp implementations on this machine byte-for-byte by symbol:

```
                                   staging  ours   (wine-install)
exports (ordinals)                    42      42
create_bgra_surface_from_rgba          2       0
do_composite_dxgi_surface              2       0
DCompositionCreateSurfaceHandle        3       3     (only the spec/stub string in both)
```
`/opt/wine-staging/lib/wine/x86_64-windows/dcomp.dll` contains **`create_bgra_surface_from_rgba`** and
**`do_composite_dxgi_surface`**; the dcomp our tree builds (ported from the sibling `revit-wine-main` project,
series/0023) has the device/target/visual object model but **neither of those functions** — i.e. it presents
the API surface and never does the D3D11 work that turns a DXGI surface into composited BGRA pixels.

That fits every measurement we have: the app's call sequence succeeds, our control reproducer
(`work/tools/t_d3d11dcomp.cpp`) reports `ALL PATHS OK` including 30 "presented" frames — because it only
exercises the API, not the pixels — and the agent's trace shows the app creates the composition swap chain and
then nothing composites, leaving the window uniformly white. **Our reproducer was too weak a test and that is
now clear.**

Cross-check with the very first runs: staging's implementation *does* run and produces exactly these errors on
this app's format —
`err:dcomp:create_bgra_surface_from_rgba Failed to create a SRV, hr 0x80070057` and
`err:dcomp:do_composite_dxgi_surface Failed to convert DXGI_FORMAT_R8G8B8A8_UNORM surface to DXGI_FORMAT_B8G8R8A8_UNORM`
— i.e. staging has the path but it fails on `R8G8B8A8`, which is the format the app asks for and for which
wined3d has no DDI format (the very thing series/0029 addressed). So the two halves may be complementary:
**staging's composition path + our 0028/0029 fixes.**

Next step (agent `QtDcompPath`, or whoever picks this up): obtain the source of that path and port it, in the
style of 0023/0024, rather than reimplementing from scratch — the reference implementations are
(i) the wine-staging source for `dlls/dcomp` (the Ubuntu `wine-staging` package on this machine is the
compiled artefact; its patchset is public), and (ii) **Proton / ValveSoftware's wine fork**, which the user
points at for exactly this reason — Proton must deal with hardware acceleration and composition on the same
D3D11/DXGI/DComp stack, so its branches are the natural upstream for this work. Prove any port with a
reproducer that checks **pixels** (read back the composited surface and assert a non-blank colour), not just
API success — that is the mistake to avoid repeating.

**Guest note:** the win11 guest is at **0 bytes free** (`dir` reports `0 bytes free`, `curl` returns rc=23
write errors, its own "Low disk space" toast is up), which is what broke the command channel's uploads
(0-byte PUTs) and file transfers. Freeing guest space is required before any further Windows reference work —
the Run-dialog route works for issuing commands there (`virsh send-key win11 KEY_LEFTMETA KEY_R`, confirm from
a screenshot, then type, then `KEY_ENTER`), and the user has authorised uninstalling non-runtime apps.

## 42. CORRECTION TO §41 — OUR dcomp DOES COMPOSITE; IT FAILED ON THE FORMAT (measured, run `hwdcomp1`)
§41 was wrong and the agent's measurement replaces it. With `WINEDEBUG=+dcomp,+dxgi` (the previous agent had
only ever enabled `+dxgi`, which is why it concluded "no compositor is involved") the app's whole chain is
visible and present:
```
DCompositionCreateDevice(NULL, IID_IDCompositionDevice) -> dcomp_device1_CreateTargetForHwnd hwnd 0x60122
  -> dcomp_device1_CreateVisual -> dcomp_visual_SetContent <the 1440x994 RGBA8 swapchain>
  -> dcomp_target_SetRoot -> Commit -> dcomp_target_blit_swapchain
  -> __wine_dxgi_set_composition_target -> d3d11_swapchain_composite
```
**and the home screen paints in that run** (`root_24s_b.png` / `root_29s_b.png`, mean 0.124, 254 colours).

So the composition path is in our dcomp; the defect is narrower and now measured exactly:
* `dcomp_target_blit_swapchain` read the content with `IDXGISurface1::GetDC` + `StretchBlt`, which **cannot read
  `R8G8B8A8`** — wined3d has no DDI format for it — so every frame logged `Blit of content … returned 0` and
  `WARN "not a blittable composition swapchain"`.
* `work/tools/t_d3d11dcomp.cpp` only ever used `B8G8R8A8` (where `GetDC` works), which is precisely why it
  reported `ALL PATHS OK` while the app stayed white. Qt's swap chain is `format 0x1c` = `R8G8B8A8`.
* **Ordering makes it fatal:** Qt does `Present` and *then* `Commit`, while our present-path composite needs
  `composition_window`, which only `Commit` sets — so a scene that renders once (`Present`=1, no further
  `Present`) is never composited. Measured: `hwrb3` = 1 Present / 0 composites (white) vs `hwattr` = 1079
  Presents (painted).

**My §41 inference was wrong**: seeing `create_bgra_surface_from_rgba`/`do_composite_dxgi_surface` in staging's
dcomp and not ours does **not** mean the path is missing — ours is a different implementation that covers the
same step by another route. And porting staging's version would not have helped anyway: it fails on `RGBA8`
itself (`Failed to create a SRV, hr 0x80070057`). Recorded because the wrong inference is instructive: a symbol
difference between two builds is not evidence of a missing code path, and an API-only reproducer is not
evidence that pixels appear.

**Fix (agent `QtDcompPath`)**: series/0029 already added a staging-texture readback for `RGBA8` in dxgi, so the
commit path is routed through it — a new dxgi private export `__wine_dxgi_composite_swapchain` (sets the target
and composites, reusing the tested fallback) with dcomp calling it. One patch, **series/0030**, commit message
`dcomp: composite a composition swap chain through dxgi, including R8G8B8A8` (approved).
`t_d3d11dcomp.cpp` was strengthened per §41's point 2: it now renders a solid colour, Presents+Commits and
**reads the window pixel back**, for both `B8G8R8A8` and `R8G8B8A8` — the test that should have existed first.

## 43. GUEST CHANNEL: fixed, and the guest inventory (2026-10-04 12:22)
The user freed space by deleting files in the guest, and **the channel works again** — the stage-2 loader
returned `ginv.txt` (5,332 bytes) intact. Two things make this reusable and are worth keeping:
* **Wine-side lesson:** the guest's failures were `curl` **rc=23 (write error)** and files landing **0 bytes**,
  i.e. a full disk, *not* a network problem. `ping`/445 failing against this guest is normal (its firewall);
  the channel is guest-initiated outbound HTTP.
* **Working technique for the guest:** the Run dialog is the reliable entry point —
  `virsh send-key win11 KEY_LEFTMETA KEY_R`, confirm the dialog from a screenshot, type
  `cmd /c curl.exe -s -o C:\Users\adsf\vp.bat http://192.168.122.1:8000/vp.bat && C:\Users\adsf\vp.bat`,
  then `virsh send-key win11 KEY_ENTER`. `vmkeys.py "{WIN}r"` does **not** open it (it taps Meta then types
  `r`, not a chord). `vp.bat` is a stage-1 loader that fetches `g.bat` and runs it, so from then on a new task
  is just "edit `vmshare/g.bat`, Win+R, Enter" — no typing.
* **Piping works when the disk is full**: `... | curl.exe -s -T - http://192.168.122.1:8000/x` uploads without
  writing a file first.

Installed products on the guest, by size (`EstimatedSize`):
```
Microsoft Edge WebView2 Runtime        3505 MB   <- RUNTIME, keep
Microsoft Edge                         2811 MB   <- kept (system browser)
Tableau 2026.2 (two entries)     2798 + 2120 MB   <- APP, removable
Microsoft Windows Desktop Runtime 10.0.9  287 MB  <- runtime, keep
Steinberg Download Assistant            239 MB   <- APP, removable
Microsoft Windows Desktop Runtime - 10.0.9 95 MB  <- runtime
Microsoft .NET Runtime 10.0.9            76 MB   <- runtime
Microsoft ASP.NET Core Runtime 10.0.9  50 + 29 MB <- runtime
WPTx64                                   47 MB   <- APP, removable
Microsoft Visual C++ v14 Redistributable 21 + 18 MB <- runtime, keep
```
**CapCut, AutoCAD 2027, Hog PC and LaunchBox are absent from the uninstall keys** — CapCut installs per-user
(so it was never in `HKLM`), and the others are the apps the user just deleted. A silent-uninstall task for
Tableau/Steinberg/WPTx64 was issued through the loader; its report had not returned when this was written
(Tableau's uninstaller is slow), so the guest's free space should be re-checked before relying on it.

## 44. MODAL ITEM — WINE vs WINDOWS, SIDE BY SIDE (measured, 2026-10-04 12:26)
Same binary (`work/tools/volprobe.exe`), same path, run under Wine and on the guest (the guest channel works
again after the user freed space; 49 GB used / **14 GB free** now).

| call | Wine | Windows guest |
|---|---|---|
| `GetDriveTypeW` | `3` FIXED | `3` FIXED |
| `GetVolumeInformationW` | `ok=1`, `vol=""`, `fs="NTFS"`, serial `43000000`, flags `0100008a` | `ok=1`, `vol=""`, `fs="NTFS"`, serial `926618ac`, flags `03e72eff` |
| `GetFileAttributesW` | `00000010` (directory) | — (not reached in this run) |
| write probe (`CreateFileW` into the directory) | **succeeds** | — |
| `GetDiskFreeSpaceExW` | ok (was 1149 MB when the *host* was full) | ok, 14 GB free now |

**Two findings, one of which kills a hypothesis:**
1. **The empty volume label is NOT a Wine difference** — Windows returns `vol=""` for this drive too. So that
   candidate is dead, and it is good that we measured it rather than "fixed" it.
2. The real differences are the **volume serial** (`43000000` vs `926618ac` — and the guest's own `dir` prints
   `9266-18AC`, so Windows' value is the machine truth while Wine invents one) and the **flags**
   (`0100008a` vs `03e72eff`). Wine sets only `CASE_PRESERVED_NAMES|PERSISTENT_ACLS|REPARSE_POINTS|
   OPEN_BY_FILE_ID`; Windows additionally sets `CASE_SENSITIVE_SEARCH`, `UNICODE_ON_DISK`, `FILE_COMPRESSION`,
   `VOLUME_QUOTAS`, `SUPPORTS_SPARSE_FILES`, `HARD_LINKS`, `EXTENDED_ATTRIBUTES`, `SUPPORTS_TRANSACTIONS`,
   `SUPPORTS_USN_JOURNAL`, `SUPPORTS_INTEGRITY_STREAMS` and more. A volume-attribute capability check is exactly
   the kind of thing an app gates a "can I put projects on this volume" decision on, and it fits the modal's
   own wording ("Check if a disk is inserted or a disk path is specified").

**Next (unstarted):** make Wine's `GetVolumeInformationW` report the drive's real serial and Windows-like
attribute flags, prove each field against the guest with this same probe, and re-run to see whether the modal
disappears. That is a *general* Wine improvement (it belongs in `patches/series/`), and it needs no guest
measurement beyond what is already captured. Still cosmetic — the home screen renders behind the modal.

## 48. HARDWARE BRANCH CLOSED: series/0030, MEASURED BEFORE/AFTER, AND THE ACCEPTANCE RUN (2026-10-04 12:38)

### Displays (measured), the software-branch fallback, and the intermittent §30 crash

Display properties, measured in this session with `xdpyinfo -display $DISPLAY | grep -E 'dimensions|resolution'`
plus an extension grep:

| display | what it is | dimensions | DPI | DRI3 | app |
|---|---|---|---|---|---|
| `:9` | Xvfb (invisible) | 1600x1000 | 100x100 | no | renders, then dies at t≈35 s |
| `:10` | Xwayland — a window in the user's session | 1600x1000 | 96x96 | yes | **renders** (`logs/hwaccept`) |
| `:11` | sway headless → Xwayland + openbox (invisible) | 1916x1173 | 96x96 | yes | **renders** (`logs/hwaccept11b`) |
| `:0` | the user's own session | 1920x1200 | 96x96 | yes | not measured here, and not cited as a result |

The requirement the app has is **DRI3**: `:10` and `:11` have it and the app renders; `:9` does not, and there
the app renders the home screen once and then dies at t≈35 s (see below). `:11` is the durable choice among the
DRI3 displays — `scripts/start_headless_dri3.sh` builds it from `sway` (`WLR_BACKENDS=headless`) → Xwayland →
openbox, so it is invisible and cannot be closed by accident.

**`:10` is fragile by construction**: it is an **Xwayland** display, so it is a window in the user's desktop
session and the user closed it mid-task. Every run that died that way did so with `x11drv: Can't open display:
:10` / `XIO: fatal IO error` (`swaccept` t≈39 s, `swaccept2` t=13 s, `swaccept3` t=18 s); `scripts/start_display.sh
:10` brings it back. A lost display is reported as such, not blamed on the app — `xdpyinfo` was checked before
and after each acceptance run below.

**Correction to "Xvfb renders white".** On `:9` the post-0030 build **does paint the full home screen**
(`recon/hwaccept9/root_22s_b.png`, mean 0.123 — Sign in / Join Pro, Create project, EditPilot, "AI-powered
creative suite", Projects …); so does the software branch there (`swaccept9b`, t=15–30 s, mean 0.123). What
happens next on `:9` is a **death at t≈35 s with the `Qt6Core.dll+0x162b52` dump of §30**, not a white window.
There is no pre-0030 `:9` run in this session, so whether 0030 changed `:9` cannot be said; what can be said is
that the "uniformly white main window" this ticket is about was measured on `:10` and is closed there, and
that the `:9` failure mode (crash) is a different, pre-existing thing. **The two facts are separate:** 0030 is
the compositing fix; DRI3 is a property the *display* must have.

**The intermittent §30 crash is not this change.** `Qt6Core.dll+0x162b52` — `QString::fromWCharArray((wchar_t*)-1, -1)`
— is §30's open item, and every dump seen in this session carries the identical signature and
`information [0, 0xffffffffffffffff]`: hit by `hwdcomp1`/`hwdcomp2` (pre-0030, t≈28–35 s), `fix600b` (pre-0030,
software branch, t≈40 s) and `hwaccept9`/`hwaccept9c`/`swaccept9b` (post-0030, t=35 s); **not** hit by `hwattr`
(136 s), `hwdcomp3` (241 s, pre-0030) or `hwaccept` (245 s, post-0030). It is therefore intermittent and older
than 0030, and still open.

**Software branch (documented fallback), post-0030 — not regressed.** It painted the full home screen twice
after the change: `logs/swaccept` on `:10` (`recon/swaccept/HOME_SCREEN.png`, t=31 s, mean 0.124, 254 grey
levels) and `logs/swaccept9b` on `:9` (t=15–30 s, mean 0.123). Later software re-runs (`swaccept10`) hit the
same `LAUNCHER EXITED at t=13s` early exit that the hardware runs hit — pre-existing erratic behaviour (§32),
not a regression: the branch differs from the hardware branch only in `hw_render`/`hardwareRenderEnable`, and
0030's delta (routing dcomp's commit through dxgi, and unlinking a released target) is only reachable on the
composition path.



Agent `QtDcompPath` (continues §42). **Series is now 30 patches, reproducibility re-verified 30/30**
(pristine `2ca2d8f` worktree + `patch -p1` for every file in `series/*.patch`, `diff -rq` against
`git archive HEAD` = empty). `patches/local/` is still empty — 0030 is a general Wine gap like 0028/0029.

### 48.1 The measurement the ticket asked for (step 1), with the dcomp channel on

With `WINEDEBUG=+dcomp,+dxgi` and the hardware config, our dcomp **is** reached and composites for the
main window. One thread, the main CapCut process (the same process the 0029 trace tags `pid 348`), run
`hwdcomp1`:
```
trace:dcomp:DCompositionCreateDevice 0000000000000000, {c37ea93a-e7aa-450d-b16f-9746cb0407f3}
trace:dcomp:dcomp_device_create rendering_device 0000000000000000, iid {c37ea93a-...}
trace:dcomp:dcomp_device1_CreateTargetForHwnd iface ..., hwnd 0000000000060122, topmost 0, target ...
trace:dcomp:dcomp_target_create Created target ... for hwnd 0000000000060122
trace:dcomp:dcomp_device1_CreateVisual ... / trace:dcomp:dcomp_visual_create Created visual ...
trace:dxgi:dxgi_factory_CreateSwapChainForComposition desc: 1440x994 format 0x1c buffers 2 effect 0x4 alpha 0x1 flags 0 (pid 348).
trace:dcomp:dcomp_visual_SetContent iface ..., content 00007BBDA6988670.
trace:dcomp:dcomp_target_SetRoot iface ..., visual ...
trace:dcomp:dcomp_target_blit_swapchain Blit of content ... returned 0.
warn:dcomp:dcomp_target_present Content 00007BBDA6988670 is not a blittable composition swapchain.
trace:dxgi:__wine_dxgi_set_composition_target Swapchain ... now composites into window 0000000000060122 at 0,0.
trace:dxgi:d3d11_swapchain_composite Compositing swapchain ... into window 0000000000060122.
```
**Called:** `DCompositionCreateDevice`, `CreateTargetForHwnd`, `CreateVisual`, `SetContent`, `SetRoot`,
`Commit` (it is `dcomp_device_commit`, which has no trace of its own — its effects are the two lines
after it), `CreateSwapChainForComposition`. **Never called in any run, before or after:** 
`DCompositionCreateSurfaceHandle` and the `IDCompositionDevice{,1,3}::CreateSurface*` family — so there is
no measurement that justifies implementing them, and §35.4's "next experiment" #1 is withdrawn.
`hwrb3` (a *white* run) shows the same `CreateDevice`/`CreateTargetForHwnd`/`SetContent`/`SetRoot` once
`+dcomp` is enabled, so this is not a property of the good runs.

§35.2's "the compositor is never called" was a **measurement artefact**: `hwtrace3` ran with `+dxgi` but
not `+dcomp`, and `now composites into` is dxgi's channel; the "no `DCompositionCreateDevice`" conclusion
was inferred from a channel that was never on. The lesson is in §42: absence of output from a channel you
did not enable is not evidence of absence.

### 48.2 The defect and the fix (series/0030, commit `ba18ed4`)

`dcomp_target_blit_swapchain` composited with `IDXGISurface1::GetDC` + `StretchBlt`. `GetDC` cannot read
`R8G8B8A8` — wined3d has no DDI format for it (§35.3) — so **every** commit logged `returned 0` and the
WARN above, for the only format the app asks for (`format 0x1c`). The same readback had already been added
to dxgi's per-present path by series/0029, so 0030 routes dcomp's commit through it rather than adding a
second engine: dxgi gains a private `__wine_dxgi_composite_swapchain` (set the composition target, then
`d3d11_swapchain_composite`, including 0029's staging fallback) and `dcomp` calls that.

That the *commit* path must work is the ordering point: Qt does `Present` **then** `Commit`, and dxgi's
per-present composite needs `composition_window`, which only `Commit` sets — so a scene that presents one
frame and then goes static was shown nothing. Measured on the same build: `hwrb3` 1 present / 0 composites
/ white window vs `hwattr` 1079 presents / painted.

Found and fixed in the same patch: `dcomp_target_Release` never `list_remove(&target->entry)`d, leaving a
dangling entry in the device's target list; the next `CreateTargetForHwnd` reused the freed block and the
list became self-referential, so the following `Commit` **looped** (the control probe hung for its full
60 s on the second case until this was fixed). `dcomp_device_release` now lets each target unlink itself.

### 48.3 Before/after with pixels, not just API results

`work/tools/t_d3d11dcomp.cpp` now renders a solid colour, **commits, and reads the window pixel back**,
for both formats (`PROBE_ONLY=bgra8|rgba8`). It runs in `prefix-test`, which has DXVK installed, so it must
be launched with `WINEDLLOVERRIDES="d3d10core,d3d11,dxgi,d3d8,d3d9=b"` — otherwise DXVK's dxgi answers
`CreateSwapChainForComposition` with `0x80004001`.

| composition swap chain, render → Commit | before 0030 | after 0030 |
|---|---|---|
| `B8G8R8A8_UNORM` | window `RGB(230,51,13)` | window `RGB(230,51,13)` |
| `R8G8B8A8_UNORM` | **window `RGB(255,255,255)`** — the app's white window, in 40 lines | window `RGB(13,51,230)` |

`RESULT: FAIL (1 failure)` before → `RESULT: ALL PATHS OK (0 failures)` after. Outputs:
`work/tools/t_d3d11dcomp_rgba8_before_fix.txt`, `…_wine_before_fix.txt`, `…_wine_after_fix.txt`. The old
probe reported `ALL PATHS OK` while the app stayed white because it only used `B8G8R8A8` **and** never
looked at a pixel — an API sequence that succeeds says nothing about whether the pixels arrive.

**Wine suite** (`dxgi_test.exe`, our build on `:10`, `d3d11`/`dxgi` builtin): 
`20448 tests executed (332 marked as todo, 0 as flaky, 0 failures), 36 skipped` (`logs/dxgi_test_0030.log`);
§35.1's number before 0030 was `20460 (332 todo, 2 flaky, 0 failures)` — the delta is the flaky-rerun
accounting, 0 failures both times. **`dlls/dcomp/tests` is not in this tree's build** (`grep -c dcomp/tests
Makefile` → 0, no generated `Makefile` in that directory), so the dcomp suite that arrived with 0023 has
never been run here — a pre-existing gap, not one 0030 introduces. The behavioural regression test for 0030
is the pixel-checking probe.

### 48.4 Acceptance — hardware branch, solo, no debug (display `:10`, repeated on the headless DRI3 `:11`)

`logs/hwaccept`. `cc_run.sh hwaccept 240 'err+all,fixme-all'`, `WINELOADER_BIN=…/wine-install/bin`,
`CC_DISPLAY=:10`, DXVK off, with `cc_cfg.sh hw` applied immediately before the launch
(`hardwareRenderEnable=true`, `hardwareRenderForbid=false`, `EnvDetect hw_render=1`).
```
exit_code=137 elapsed_at_exit=245s launcher_alive_at_end=yes      <- 137 = the harness's own end-of-run kill
last_time_app_proc_seen_s=237   n_app_procs_left=8   capcut_windows=36 at every late sample
screenshots=623       0 .dmp in logs/hwaccept (prefix Crash/reports/ has no report)
root_46s_b.png … root_235s_b.png    mean 0.142, 256 colours
```
`recon/hwaccept/HOME_SCREEN.png` is the shot: the full home screen ("Create project", EditPilot, "AI-powered
creative suite", Projects, the "Recommended" tooltip) — **the main window is not white**.

**Acceptance repeated on the durable DRI3 display `:11`** (sway headless → Xwayland → openbox; 1916x1173,
DPI 96x96, DRI3 present — checked before *and* after the run). `logs/hwaccept11b`, solo
`cc_run.sh hwaccept11b 240 'err+all,fixme-all'`, same hardware config, DXVK off:
```
exit_code=137 elapsed_at_exit=243s launcher_alive_at_end=yes
last_time_app_proc_seen_s=235   n_app_procs_left=7   capcut_windows=36
screenshots=574       0 .dmp in logs/hwaccept11b
root_33s_b.png … root_243s_b.png   mean 0.101 (1916x1173 screen, so the 1440x994 window is ~58 % of it)
```
`recon/hwaccept11b/HOME_SCREEN.png` is the shot (same home screen, "Recommended" tooltip). **This is the
acceptance run to cite** — `:11` is invisible and cannot be closed out from under a run, unlike `:10`.



## 45. THE DISPLAY REQUIREMENT, SETTLED BY THE USER: **Xwayland (DRI3) works, Xvfb does not** (2026-10-04 12:50)
The user reports — and this is the decisive datum — that CapCut **works on Xwayland but not on the Xvfb
display**. That corrects §45-predecessor hypotheses (resolution/DPI) and my earlier statement that `:9` was
fine because "Wine's own d3d11 does not need DRI3":

```
                                     :9 Xvfb        :10 Xwayland     :0 the user's
dimensions                          1600x1000       1600x1000        1920x1200
DPI                                 100x100          96x96           96x96
DRI3                                  NO             yes             yes
XFree86-VidMode                       NO             yes             yes
app outcome                        white/fails       WORKS           WORKS
```
So the app requires a display with **DRI3** — i.e. real GPU buffers — and Xvfb cannot provide it. Note the
distinction that misled us: our *control reproducer* (`t_d3d11dcomp.cpp`) passed on `:9` because it only
exercises the D3D11/DComp **API** through wined3d; the **app** needs the GPU-backed presentation path, so an
API-level green on Xvfb was not evidence that the app would render there. That is the same "an API-only test
is not evidence of pixels" lesson as §41/§42, in a second place.

**Consequence for how this must be run:** the working configuration is **Xwayland**, which on this machine
exists only as a window inside the user's Wayland session (`:10`, or the session's own `:0`). There is no
headless DRI3 option installed — `weston`, `sway`, `labwc`, `wayfire`, `cage`, `gamescope` are all absent and
there is no sudo to add one — so `:11` (which I created at 1920x1200 on Xvfb) is useless for this purpose and
the "match the user's geometry" idea is dead. Two practical notes: closing the Xwayland window kills the X
server and every run on it (it happened once, losing a 600 s attempt), and `vmkeys`-style automation of the
*virtual* displays still works fine, it is only the app's rendering that needs DRI3.

**This is worth a patch later**: if the app truly fails without DRI3, the Wine-side question is *what it does
differently when DRI3 is absent* (ANGLE's EGL init, `WGL_EXT_swap_control`, llvmpipe's reported caps, DXGI
adapter/format support) rather than "the compositor is broken". Not started, and lower priority than the
series/0030 closure, since the app does work on a DRI3 display.

## 46. CORRECTION TO §45: `:0` was never tested
The user clarifies they **never tested the `:0` display — only the Xwayland one** (`:10`). So the only measured
facts are:

* **Xwayland `:10` (DRI3): the app works.**
* **Xvfb `:9` (no DRI3): it does not.**

The "`:0` works" row in §45's table was my inference from the fact that the user runs it there, not a
measurement — §45 should be read with that row struck out. `:0` remains *available* (it is the session's own
Xwayland, 1920x1200, DRI3 present) but we have no result for the app on it, and the geometry/DPI hypothesis
that row was supporting is dead anyway.

Nothing else changes: the requirement is DRI3 (Xwayland yes, Xvfb no), `:10` is the display to use until the
headless-DRI3 setup the user offered (`sway` or `weston` via `pkexec`) exists, and the agent has been told to
record each display's properties with every result so this class of inference cannot creep in again. Twice now
a claim of mine in this project has been stronger than its evidence — the dcomp "path is missing" inference
(§41, corrected in §42) and this one — so: **state what was measured, name the display, and do not promote an
inference to a row in a table.**

## 47. HEADLESS DRI3 DISPLAY `:11` — the display problem solved (2026-10-04 13:05)
The user installed `sway`; I built a **headless DRI3** X display from it, which has the property the app needs
(DRI3) *and* the property automation needs (invisible — no window on the user's desktop that can be closed
mid-run, which is what killed one 600 s attempt):

```
sway (WLR_BACKENDS=headless, WLR_LIBINPUT_NO_DEVICES=1, `sway -c /dev/null`)
  -> wayland-1  ->  Xwayland :11 -geometry 1920x1200  ->  openbox
measured on :11: 1916x1173, DPI 96x96, DRI3 present, Present present, WM present
```
Recreate with **`scripts/start_headless_dri3.sh [display] [WxH]`** (default `:11 1920x1200`); it is controlled
via `SWAYSOCK=/run/user/1000/sway-ipc.<pid>.sock`, e.g. `swaymsg output HEADLESS-1 resolution 1920x1200`.
Notes for whoever runs this: `sway --socket` is not a flag (it takes the socket name from the instance and
creates `wayland-1` here); the X screen is a few pixels smaller than the output (1916x1173 for 1920x1200) and
that is normal; `Xwayland` must be given `WAYLAND_DISPLAY` explicitly to attach to the headless compositor.

**From now on: `:11` is the display of record for CapCut runs.** `:9` cannot render the app (no DRI3), `:10`
works but is fragile and intrusive. The agent has been told to take the series/0030 acceptance shot on `:11`
and to record the display's properties beside every result.

## 48. GUEST DISK TASK: done to the extent it matters (2026-10-04 13:10)
Ran the silent-uninstall task through the working loader (`vp.bat` -> `g.bat`). Measured result:
```
BEFORE  FreeGB : 11
UNINSTALL: Tableau 2026.2 (…)        <- both entries
UNINSTALL: Steinberg Download Assistant
UNINSTALL: WPTx64
AFTER   FreeGB : 15
```
**Tableau — the weight (4.9 GB across two entries) — is gone** and both entries have disappeared from the
uninstall list. **Steinberg Download Assistant and WPTx64 are still installed**: their `UninstallString`s did
not take a silent flag (`/S` on a non-NSIS uninstaller, or a GUI-only uninstaller) and the task reports no
error for them, which is why the earlier attempt also looked like it "did nothing". Together they are ~286 MB,
against 15 GB free, so this is left as-is rather than spending more time on it. The guest is now:
runtimes (WebView2, .NET/ASP.NET/Windows Desktop, VC++), Microsoft Edge, the application-compatibility
database, Steinberg Download Assistant, WPTx64 — and **CapCut, which is the reference and was never in
`HKLM`** (it installs per-user, so it never appeared among the removable products).

## 49. INDEPENDENT RE-VERIFICATION BY MAIN: series reproduces the tree at 30/30 (2026-10-04 13:32)
Checked by me, not taken from an agent's report: `git worktree add` of the pristine root commit `2ca2d8f1`
plus `patch -p1` for **every** file in `patches/series/` (30 of them) then `diff -rq --exclude=.git` against
`wine/wine-11.18`:

```
applied 30, failures 0
(no differences)
```

So the deliverable's central property holds for the full 30-patch series, not just the 27 I had verified by
hand earlier. Also re-confirmed in the same pass: the wine tree is clean, `git log` has 31 commits
(pristine + one per patch), `patches/local/` is empty, `recon/` holds six reports, `:11` (headless DRI3) is up,
and the host has 20 GB free. Worktree removed afterwards; no state left behind.

## 50. THE MODAL DOES NOT REPRODUCE, AND THE VOLUME SERIAL MUST NOT BE "FIXED" (agent `VolumeInfo`, 2026-10-04 13:35)
Two findings that change the status of the last item, both from the agent's measurements:

**1. The "Project saved path not found" modal did not reproduce in any run on the unpatched build.** It was
seen twice on 2026-10-04 (`recon/ours_d10_winconf`, `recon/verify3`) — i.e. before
`User Data/Projects/com.lveditor.draft/` existed and while the Windows-matching config was being applied by
hand — and not since. So it is best explained as a first-run/state artefact, not a Wine defect, and the item
should be closed as **not reproducible** rather than as fixed. §44's Wine-vs-Windows field diff (serial
`43000000` vs `926618ac`, flags `0100008a` vs `03e72eff`) remains a real measurement of a real difference; it
just is not the cause of anything we can still observe.

**2. Do NOT change the reported volume serial — CapCut uses it as the machine id.** Measured: with `hid` edited
to a different serial, **3/3 runs stopped at the first-run "Environment testing → Confirm" dialog** and the home
screen was never reached until it was dismissed; with the original value, **3/3 runs reached the home screen**.
So "fixing" the serial to match the guest would have *introduced* a regression and re-triggered the app's
first-run flow. That is why series/0031 is **flags-only**.

series/0031 (`ntdll,mountmgr: report the NTFS capabilities the emulation actually implements`, approved): adds
`FILE_CASE_SENSITIVE_SEARCH`, `FILE_UNICODE_ON_DISK`, `FILE_SUPPORTS_HARD_LINKS` to what Wine advertises on
NTFS, and fixes the drift between `ntdll`'s directory-handle path and `mountmgr`'s drive-root path on
`FILE_SUPPORTS_REPARSE_POINTS`. It deliberately does **not** advertise capability bits for features Wine does
not implement (compression, quotas, sparse files, object ids, encryption, transactions, USN journal, integrity
streams). It is a **general correctness fix measured via CapCut — not the modal fix**, and must be labelled as
such; the commit body is to carry the `hid` reasoning so nobody later "improves" the serial and breaks the app.

## 49. MODAL ITEM CLOSED AS NOT REPRODUCIBLE; series/0031 IS A GENERAL FLAGS FIX (2026-10-04 14:05)

Agent `VolumeInfo`. Two results, and the first one changes the item's status, so it comes first.

### 49.1 The modal does not reproduce — and its own text names the reason

Six CapCut runs today on the durable DRI3 display `:11` (`1916x1173`, 96x96 DPI, **DRI3 present,
Present present** — checked before the acceptance run, `xdpyinfo`), software branch re-applied
immediately before each launch, screenshots every 5 s and OCR of **every** frame:

| run | build | what it shows |
|---|---|---|
| `logs/modalbase` (13:13, 157 s) | unpatched (0030) | full home screen, **no modal** (`recon/modalbase/`: 22 root frames at 5–10 s intervals, 0 s/5 s/…/157 s, none shows it) |
| `logs/modalmissing` (13:25, 112 s) | unpatched | `Projects/com.lveditor.draft` renamed away → app recreates the directory, **no modal** |
| `logs/modalvol` (13:20) | unpatched, `+volume` | stalled at "Environment testing" (profiling run, see 49.2) |
| `logs/modalhid*` (13:29–13:38) | unpatched | first-run flow re-entered, see 49.2, **no modal** |
| `logs/accept0031`/`accept0031b` | patched | first-run "Confirm" dialog (state left by 49.2), no modal |
| `logs/accept0031c` (14:03, 207 s) | **patched** | full home screen, **no modal** — `recon/accept0031c/HOME_SCREEN.png` |

OCR of `accept0031c`'s 56 root frames found the modal text in **zero** frames (the run's 490
screenshots include one capture per CapCut window per sample). Caveat, because it bit earlier in
this task: tesseract does **not** reliably read this dialog — it found nothing in
`recon/verify3/root_37s.png`, where the modal is plainly visible — so the OCR is a secondary check
only and the primary evidence is the frames themselves (viewed at 5 s intervals: 0 s … 207 s, no
modal at any point, and `recon/accept0031c/HOME_SCREEN.png` is the shot). So the modal is not
reproducible in the current prefix state, on either build.

Where it *was* seen, and what it actually was: `recon/ours_d10_winconf/HOME_SCREEN.png` (01:00) and
`recon/verify3/root_37s.png` (01:16) — the fresh-prefix window, while the Windows reference's config
was being applied by hand. That screenshot settles it. The modal's own body text reads

```
Project under path C:\Users\adsf\AppData\Local\CapCut\User Data\Projects\com.lveditor.draft
is not found. Check if a disk is inserted or a disk path is specified.
```

`adsf` is the **Windows guest's** user name; this prefix's user is `asdf`, so that directory never
existed here. The app had been handed the guest's draft path — it is still in the reference,
`recon/winlog/Config/globalSetting`:
`currentCustomDraftPath=C:\\Users\\adsf\\AppData\\Local\\CapCut\\User Data\\Projects\\com.lveditor.draft`
— and was **correctly** reporting it missing. The prefix's own config now says
`C:\users\asdf\...`, which exists, and the modal is gone (`work/tools/cc_cfg.sh sw` copies the
Windows *flags* but deliberately keeps Wine's *paths*: `"globalSetting: take the Windows flags but
keep Wine's own cache paths"`). The stale `oldCustomDraftPathList` registry value
(`HKCU\Software\Bytedance\CapCut\GlobalSettings\History`, still `C:\Users\adsf\...`) is the only
remaining trace.

**Conclusion: not a Wine defect and not a volume-info defect — a path copied from the Windows
reference that does not exist in the Wine prefix. Closed as *not reproducible*, not as fixed.**
The recorded §35.5/§37/§44 hypotheses (volume label, serial, flags) were all measurements of a
genuine Wine-vs-Windows difference, but none of them is what the modal was about.

### 49.2 The field the app keys on: the **volume serial** (`hid`), measured

`WINEDEBUG=+volume` on a run shows the app's draft-path volume helper being called in **two**
processes (VEDetector and the main app), in this order:

```
GetVolumePathNameW(L"...\CapCut\User Data\") -> L"C:\"
GetVolumeInformationByHandleW
GetDriveTypeW L"C:\\" -> 3
GetVolumeNameForVolumeMountPointW(L"C:\\", buf, 0x33) -> L"\\?\Volume{00000000-0000-0000-0000-000000000043}\"
GetDiskFreeSpaceExW L"C:\" / L"C:"
```

and the app **stores the serial**: `HKCU\Software\Bytedance\CapCut` `"hid"="43000000"` — Wine's C:
serial exactly (`mountmgr`'s `get_default_uuid()` puts `'A'+letter` in `Data4[7]`, and the serial is
those four bytes). The flag bits are read by the same helper but **no measurement shows the app
gating on them**, and the label is `""` on both sides.

The experiment (edit `"hid"`, run 200 s, read it back):

| `hid` value | runs | result |
|---|---|---|
| `926618ac` (a different serial) | `modalhid`, `modalhid2`, `modalhid4` | 2 stalled at the app's first-run "Environment testing → Confirm" dialog, 1 had the launcher exit at t=1 s — home screen **not** reached |
| `926618ac`, `CC_AUTOCLICK=1` | `modalhid5` | reached the home screen (after the dialog was dealt with), **no modal** |
| `43000000` (the original) | `modalbase`, `modalmissing`, `modalhid3` | 3/3 reached the home screen |

Read back from `prefix/user.reg` after each changed-`hid` run: the value was **still `926618ac`** —
the app does *not* regenerate `hid` from the current serial, so a serial mismatch persists across
starts. That makes "report the drive's real serial" a **regression**, not a fix: it would re-trigger
CapCut's first-run flow for every existing prefix. The constant is therefore left exactly as it is —
the ticket's "if a constant is genuinely required, say so and why" case — and the reasoning is in
the commit body so a later reader does not remove it as an obvious improvement. (A drive letter
mapped to a directory has no serial on the volume to read anyway; the host filesystem's identity is
available but is a kernel device number, not an on-volume value, and is *less* stable than the
constant across device renumbering.)

Because the flag experiment could not be run A/B (the modal does not fire), the ticket's step 1 is
answered for the serial only, by this measurement.

**Operational side effect, worth knowing:** the changed-`hid` runs left the prefix in a state where
the app re-ran its first-run flow at every start (`accept0031`, `accept0031b` stalled at the
"Confirm" dialog; VEDetector then runs the real detection instead of
`VEDetector.exe -detect_simulate_check`). Restoring the pre-existing config snapshot —
`work/tools/cc_cfg.sh load prefix_now` (the 02:16 state) — put it back, and `accept0031c` then
reached the home screen on the first try. `cc_cfg.sh sw` is not enough to undo that state.

### 49.3 series/0031 — the flags

`ntdll,mountmgr: report the NTFS volume capabilities the emulation actually implements`
(commit `73d2b20`, `patches/series/0031-…-the-emulation-has.patch`). This is a **general
correctness fix, not the modal fix**, and the commit body says so.

Two places answer `FileFsAttributeInformation` and they had drifted apart:

| | before | after | Windows guest |
|---|---|---|---|
| drive root (`mountmgr.sys/device.c`) | `0100008a` | `0140008f` | `03e72eff` |
| directory handle (`ntdll/unix/file.c`) | `0100000a` | `0140008f` | — |

Added, verified in the source as actually implemented: `FILE_CASE_SENSITIVE_SEARCH`,
`FILE_UNICODE_ON_DISK`, `FILE_SUPPORTS_HARD_LINKS`, and `FILE_SUPPORTS_REPARSE_POINTS` now in both
paths (it was only in the drive-root reply). Deliberately **not** advertised because Wine does not
implement them: compression, quotas, sparse files (`FSCTL_SET_SPARSE` is "Ignoring request"),
object ids (`FileObjectIdInformation` → `STATUS_INVALID_INFO_CLASS`), encryption, transactions, USN
journal, integrity streams, block refcounting, sparse VDL, extended attributes (`EaSize` is always
0). The serial is untouched — see 49.2.

Tests, our build, before → after:
* `ntdll_test.exe file`: 2955 tests, **3 failures → 0** (`work/tools/ntdll_file_flags_{before,after}.log`)
* `kernel32_test.exe volume`: 619 tests, **3 failures → 0** (`work/tools/kernel32_volume_flags_{before,after}.log`)
The three failures in each are exactly the new assertions (`FILE_CASE_SENSITIVE_SEARCH`,
`FILE_UNICODE_ON_DISK`, `FILE_SUPPORTS_HARD_LINKS`).

### 49.4 The probe, both sides, the same binary

`work/tools/volprobe.c` extended with `GetVolumePathNameW`, `GetVolumeNameForVolumeMountPointW` and
a flag decode; `volprobe.exe` sha256 `68a6ad3a2df5de904c9f0b2bc91199bd53a99c81e8a2874203139e2a894f45a0`
on both sides. Wine: `work/tools/volprobe_wine.txt`; guest: `vmshare/g_out.txt` →
`work/tools/volprobe_windows.txt`; side by side: **`work/tools/volprobe_compare.txt`**. The guest's
own `dir C:\` prints the serial it reports, `9266-18AC`. Wine's volume GUID
(`…-000000000043`) is still the synthetic letter-derived one; it is stable, and the app only reads
it, so it is left alone too.

### 49.5 Acceptance run and series reproducibility

`logs/accept0031c`: solo `cc_run.sh accept0031c 200 'err+all,fixme-all'`,
`WINELOADER_BIN=…/wine-install/bin`, `:11`, software branch (`cc_cfg.sh load prefix_now`
immediately before), DXVK off.

```
FIRST SEEN app at t=0s
sample t=199s  procs=8  capcut_windows=36  launcher_alive=1
exit_code=137 elapsed_at_exit=207s launcher_alive_at_end=yes   <- 137 = the harness's own kill
n_app_procs_left=8      0 .dmp in logs/accept0031c
screenshots=490         recon/accept0031c/HOME_SCREEN.png = the home screen, no modal
```

`hid` before/after the run: unchanged (`43000000`), and the whole `user.reg` diff is the app's usual
per-run writes — so the patch changed nothing the app depends on.

Series reproducibility **re-verified at 31/31**: pristine `2ca2d8f` worktree + `patch -p1` for all 31
files in `patches/series/` (31 applied, 0 failures) + `diff -rq` against `git archive HEAD` = only
`/tmp/repr31/.git` (the worktree's own git dir), i.e. no content differences. `patches/SERIES.tsv`
and `patches/README.md` updated; **`patches/local/` is still empty** — 0031 is a general Wine gap,
not a CapCut-exclusive one.

## 51. PROJECT CLOSED — all items done (2026-10-04 13:45)
series/0031 committed (`73d2b20`), series = **31 patches**, verified reproducible from pristine. Wine-suite
tests after it: `kernel32_test.exe volume` 619 tests **0 failures**, `ntdll_test.exe file` 2955 tests
**0 failures** (each had 3 failures before). Wine now advertises `0140008f` where it advertised `0100008a`,
and `ntdll`'s directory-handle path and `mountmgr`'s drive-root path agree again.

### The modal's real cause, confirmed — it was a mistake of mine, not a Wine defect
```
prefix now : currentCustomDraftPath=C:\users\asdf\...\Projects\com.lveditor.draft   (exists)
guest ref  : currentCustomDraftPath=C:\Users\adsf\...\Projects\com.lveditor.draft   (adsf = the GUEST's user)
```
When I applied the Windows reference config by hand (§32/§33 era) I copied `EnvDetect*.json` **and** the
reference `globalSetting`, which carries the **guest's** draft path — and `adsf` is the guest's user name while
this prefix's user is `asdf`. CapCut was then **correctly** reporting that a directory which never existed here
was not found. Nothing to fix in Wine; the item closes as **not reproducible** (6 runs on `:11` in the software
branch, 5 s screenshots + OCR of every root frame, no modal). `work/tools/cc_cfg.sh sw` copies the Windows
*flags* but keeps Wine's *paths*, which is why it no longer appears. Residual trace worth knowing:
`oldCustomDraftPathList` in the registry.

### The volume serial must never be "corrected" — measured, and it would be a regression
CapCut stores the volume serial as `HKCU\Software\Bytedance\CapCut` `"hid"` (= `43000000`, Wine's C: serial).
With `hid` set to the guest's real serial `926618ac`: **3/3 runs did not reach the home screen** (2 stalled at
the first-run "Environment testing → Confirm" dialog); with the original value **3/3 reached it**, and one
autoclicked run with the changed value reached the home screen but still showed no modal. Read back from
`user.reg` afterwards: `hid` stays `926618ac`, so **the app does not regenerate it** and a mismatch persists
across starts. Hence "report the drive's real serial" would re-trigger CapCut's first-run flow for every
existing prefix; a directory-backed drive letter has no on-volume serial to read anyway. The reasoning is in
the commit body so a later reader does not remove it.
