# CapCut PC on Wine

CapCut is a registered trademark of ByteDance Ltd. This repository is not associated with, affiliated with, supported nor endorsed by ByteDance Ltd. No guarantees are made, as for the suitability of the content of this repository for any particular purpose.

Wine 11.18 with the patches that let **CapCut PC (Windows x64, app version 9.5.0.4050,
installer `capcutpc_0_1.2.36`)** install and run on Linux, plus the environment fixups the app
needs that are not Wine patches at all.

No CapCut/ByteDance software is redistributed here. The installer payload is fetched by the
vendor's own stub at run time; `recon/win_install/` holds only measurements.

Read **`STATE.md`** first if you are resuming work: it is the append-only record of every
measurement, decision and dead end.

---

## 1. What the app is (measured, not guessed)

`…\AppData\Local\CapCut\Apps\{CapCut.exe, uninst.exe, Configure.ini, ProductInfo.xml, 9.5.0.4050\}`

* **Not Electron.** No `electron`, no `node*.dll`, no `app.asar`, no `v8` anywhere in the install.
* The UI shell is **Qt 6 / Qt Quick (QML)** — `Qt6Quick`, `Qt6QuickControls2`, `Qt6Qml*`,
  `Qt6Widgets`, and QML embedded in `VECreator.dll` (235 MB; ~870 `.qml` references).
* **CEF (Chromium 121.0.6167.86)** — `libcef.dll` (207 MB) + `lynx.dll` (ByteDance's RN-like
  runtime) render the commerce/account/web surfaces, not the editor.
* Native video engines: `videoeditor.dll`, `cccreator.dll`, `lens.dll`, `deepagents_capi.dll`,
  a custom FFmpeg (`avcodec-61.dll`), `openvino.dll`, `sscronet.dll`.
* Rendering: the app stores `qt6RenderEngine=d3d11`, `hardwareRenderEnable=true`; Qt's **D3D11
  RHI** drives **DirectComposition** (`Qt6Gui.dll` resolves `DCompositionCreateDevice`
  dynamically). `VEAngle\{libEGL,libGLESv2}.dll` and `cef\{libEGL,libGLESv2}.dll` are ANGLE.
* `VEDetector.exe` (Qt Widgets) is the "Environment testing" window the app shows first, and it
  is what decides the renderer.

## 2. How CapCut is obtained

`capcut_capcutpc_0_1.2.36_installer.exe` is a 2.9 MB **NSIS web installer** (DuiLib UI) whose
`downloader_nsis_plugin.dll` fetches the real payload from ByteDance's MCS/config services
(`mcs-v2-boot.capcutapi.com`, `editor-api-v2-boot.capcutapi.com`, app id `423531`).
**The stub runs fine under Wine** and downloads the payload itself:
`…\AppData\Local\app_shell_cache_562354\app_package_<hash>.exe` (~534 MB), which then installs
CapCut. The stub is 32-bit, so use a WoW64-capable Wine for the *install* step (see §4).

Its own log is `…\AppData\Local\Temp\installer_downloader.log`.

## 3. The Wine patches

`patches/series/` — the shared base series, applied in order to pristine `wine-11.18.tar.xz`
(`dl.winehq.org`). `patches/SERIES.tsv` records where each patch came from.

| # | what it fixes |
|---|---|
| 0001–0014 | the AutoCAD series: `wintrust` RFC 3161 + `WTD_CHOICE_BLOB`, `kernelbase` regf hives, `urlmon` empty-host zones, service session 0, the Windows hosts file, group-policy/enterprise cert stores, completion ports on non-overlapped handles, fd-backed pipe semantics, missing exports, NLA lookups, winex11 stale-window errors, `GetUserNameExW` domain answers, `msiexec` command line, `actctx` `privatePath` |
| 0015 | the series' own tests, in Wine's test suite |
| 0016–0021 | the Power BI series: `wintypes` WinRT metadata, `NtImpersonateAnonymousToken`, SPNEGO in `Negotiate`, `LsaFreeReturnBuffer`, `oledb32` `VARIANT`→`I8`/`BOOL`, tests |
| 0022 | `msxml3` `IVBMXNamespaceManager::reset` |
| **0023** | **`dcomp`: a real DirectComposition implementation** — device/target/visual objects, `Commit`, the composition surface path (upstream 11.18's `dlls/dcomp` is a 47-line `E_NOTIMPL` stub) |
| **0024** | **`dxgi`: `CreateSwapChainForComposition` + per-present compositing + a GDI-compatible back buffer that survives `ResizeBuffers`** |
| 0025 | `ncrypt`: import ECC key blobs |

`patches/local/` — CapCut's **own** patches (`0023+` numbering continues from the series; see
`patches/README.md`).

`patches/sources/` — untouched copies of every donor patch directory, so the provenance of the
series is auditable offline.

### Why 0023/0024 are the ones that matter

CapCut's Qt D3D11 RHI uses DirectComposition for its top-level windows. With them absent, the
windows are created but never painted and the app exits within 30–45 s. With them, the app
paints its "Environment testing" window and keeps running. Control reproducer
`work/tools/t_d3d11dcomp.cpp` demonstrates both halves directly:
`DCompositionCreateDevice → CreateTargetForHwnd → CreateVisual → CreateSwapChainForComposition →
SetContent → SetRoot → Commit → 30 presented frames`.

## 4. Environment fixups (not Wine patches)

* **A display with DRI3.** `Xvfb` has **no DRI3**, so Mesa cannot hand GPU buffers to the X
  server: GL falls back to `llvmpipe` and DXVK cannot present at all. Use a second **Xwayland**
  instance on the session's Wayland compositor (`scripts/start_display.sh`):

  ```
  xdpyinfo -display :9  -> Present            (no DRI3)   # Xvfb
  xdpyinfo -display :10 -> DRI3, Present                  # Xwayland -> real iGPU
  ```

  Plus a **window manager** (`openbox`), which the app expects for window activation.
* **Build with WoW64** (`--enable-archs=i386,x86_64`) if you need to run the 32-bit stub
  installer with the same Wine. The 64-bit app itself needs only `x86_64`.
* **DXVK** is *not* required, and is currently counter-productive: its DXGI has no
  composition swapchain (`CreateSwapChainForComposition` → `E_NOTIMPL`, even with
  `dxgi.enableDummyCompositionSwapchain = True`), so Wine's dcomp cannot obtain content.
  `third_party/dxvk.conf` documents the Proton-style adapter overrides
  (`dxgi.customVendorId/customDeviceId/customDeviceDesc`) for the day that changes.

## 5. Build and run

```bash
bash scripts/build_wine.sh                # first build: copy tree, configure, make, make install
bash scripts/rebuild.sh                   # after adding patches (re-runs configure, make, install)
bash scripts/fetch_payload.sh             # the CapCut payload itself (CDN, hash-checked)
bash scripts/start_display.sh :10         # Xwayland + openbox  (DRI3 -> real GPU)
bash scripts/cc_run.sh <tag> 300 "err+all,fixme-all"
```

### The configuration that renders (measured, `recon/ours_d10_winconf/HOME_SCREEN.png`)

| | |
|---|---|
| Wine | `wine-install/bin/wine` = wine-11.18 + the 25-patch series (**0023 dcomp + 0024 dxgi** are load-bearing) |
| DXVK | **off** — `d3d11`/`dxgi` overrides `builtin` (`scripts/dll_overrides.sh builtin`, or the render agent's script) |
| Display | `:10` — Xwayland, i.e. **DRI3**; `:9` (Xvfb) has none |
| WM | `openbox` (the app expects window activation) |
| Prefix | `prefix/` |
| App config | the app must take its **software/no-hardware** branch — `hardwareRenderEnable=false`, `hardwareRenderForbid=true` in `User Data/Config/globalSetting`, with `EnvDetect*.json` / `ve_hw_check.ini` matching the Windows guest |

With that, CapCut paints its "Environment testing" window, then the "Terms of Service and Privacy Policy"
dialog, then the full home screen (Create project / EditPilot / AI-powered creative suite / Projects).

**Why the software branch is the faithful reproduction, not a workaround:** the Windows reference guest also
takes it — its adapter is a "Microsoft Basic Display Adapter" and its `EnvDetect.json` says
`hw_render=0`, `final_hw_enable=0`, while Wine reports a *capable* adapter and the app then picks hardware
rendering and leaves the main window uniformly white. The remaining defect is therefore in the
hardware-render path (most likely the EffectSDK's AGFX GL/ANGLE initialisation — see §4 and
`recon/RE_VEDETECTOR.md`), not in the software one.

Also needed once: `User Data/Projects/com.lveditor.draft/` must exist, or the app opens a
"Project saved path not found" modal.

`scripts/cc_run.sh` is the observer: it detects the app's processes (never by name — Wine's
`argv[0]` is a Windows path), samples screenshots only while the app is alive, records the exit
code, rescues any crash `.dmp` and copies the app's own logs.

## 6. Status — what works, what does not

**Works** (all measured; each claim cites a run tag or a file):
* the payload is fetched by the vendor's own stub **under Wine**, and CapCut installs;
* CapCut launches under our patched Wine, paints its **"Environment testing"** window, its
  **"Terms of Service and Privacy Policy"** dialog, and its **full home screen**
  (`recon/ours_d10_final/HOME_SCREEN_CLEAN.png`, `recon/verify3/root_37s.png`);
* **both renderer branches paint** — the software branch and, after series/0030, the **hardware branch**
  (`recon/hwdcomp1/root_24s.png`). The hardware branch had been uniformly white because dcomp's commit-time
  blit used `IDXGISurface1::GetDC` + `StretchBlt`, which cannot read the `R8G8B8A8` composition swap chain the
  app asks for; see `STATE.md` §42/§48 (`§48` is the agent's closure report for series/0030);
* **stability**: a solo 600 s run with the app alive at t=598 s, 8 processes and **no crash dump**
  (`logs/final600b`, §34). The earlier "killed at t≈42–57 s" was the harness's own start-up cleanup killing a
  previous run's processes — it now takes a lock and refuses a second owner.

**Does not work yet / not tested:**
* **editing** — no project has been opened and no edit made; the acceptance target is "opens like Windows",
  which is met;
* a **"Project saved path not found"** modal appears although the directory exists (`STATE.md` §33/§44). It is
  Wine-only — the Windows guest does not show it — and it is cosmetic: the home screen renders behind it. The
  differing fields are measured (volume serial and attribute flags; the empty volume label is *not* a
  difference, Windows returns `""` too);
* one rarer crash was seen once, before the 100 s crash was fixed: `EXCEPTION_ACCESS_VIOLATION` reading `-1`
  at `Qt6Core.dll+0x162b52`, an inline `wcslen` of a `(wchar_t *)-1` (`logs/fix600b`, `STATE.md` §30). It has
  not recurred in any post-fix run.

**Known environment requirements** (not Wine patches): a **DRI3 display** — the app does not render on Xvfb,
so use `scripts/start_headless_dri3.sh` (`:11`); a window manager; and the app's own config in the
software-render branch, re-applied immediately before each run because the app rewrites it (`STATE.md` §32).
`User Data/Projects/com.lveditor.draft/` must exist.

## 7. Layout

| path | what it is |
|---|---|
| `STATE.md` | the resumable record: every measurement, decision and dead end |
| `patches/` | `series/` (shared base), `local/` (CapCut-exclusive), `sources/` (donor copies), `SERIES.tsv` |
| `wine/wine-11.18/` | the patched tree (pristine + series + local), git branch `merged` |
| `wine-install/` | `make install` output; `wine-install/bin/wine` |
| `prefix/` | the working Wine prefix with CapCut installed |
| `prefix-test/`, `prefix-test2/` | throwaway prefixes for the D3D11/DComp control reproducer |
| `scripts/` | build, display, run, observe, guest-channel and analysis tooling |
| `work/tools/` | the control reproducers (`t_d3d11dcomp.cpp`, `t_egl.c`, `t_dllsearch.c`) |
| `work/payload/` | the fetched `app_package*.exe` payload and its hash |
| `third_party/dxvk-*` | DXVK v3.1.1 and its configuration |
| `recon/` | findings: `MERGE.md`, `RENDER.md`, `GUEST_CAPTURE.md`, `RE_VEDETECTOR.md`, screenshots |
| `logs/` | per-run logs (`logs/<tag>/`), Wine debug output, timelines |
| `vmshare/` | the host↔Windows-guest file channel |
