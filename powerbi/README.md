# Running Power BI Desktop on Linux with Wine

Power BI is a registered trademark of Microsoft Corporation. This repository is not associated with, affiliated with, supported nor endorsed by Microsoft Corporation. No guarantees are made, as for the suitability of the content of this repository for any particular purpose.

This folder is self-contained enough to install and run Power BI Desktop on Linux: the Wine source with the
patches applied, the patches themselves, the scripts, and these instructions.

**What works at the end**: Power BI Desktop starts, opens a `.pbix`, and shows the **report page with its chart
rendered** — matching the Windows guest's own frame, verified bar for bar. What does *not* work yet is described
honestly under [Limits](#limits-and-what-does-not-work); read that section before planning around this.

Everything here was measured on Ubuntu 26.04, x86-64, Wine 11.18. Where a claim is a measurement, the finding
number is given — the full evidence is in the sibling checkout `/home/asdf/Downloads/powerbi-linux/FINDINGS.md`
(70 numbered milestones) and its `docs/` directory.

---

## 0. What you need first

| thing | where | why |
|---|---|---|
| Power BI Desktop installer | `/home/asdf/Downloads/PBIDesktopSetup_x64.exe` (694 MB) | the app itself |
| this folder | `/home/asdf/Downloads/powerbi/` | patched Wine source, patches, scripts |
| the working checkout | `/home/asdf/Downloads/powerbi-linux/` | the full tooling, the tested prefix, the evidence |
| disk | ~10 GB free | Wine source + build + prefix (a prefix with .NET 4.8 is several GB) |
| time | **1–2 hours**, mostly waiting | `dotnet48` alone is 30–60 minutes |
| a display | X11 (`:9` headless Xvfb, or `:2` VNC if you want to watch) | the app is a GUI app |

Wine **staging or a build of the patched tree**; a distro `wine` will not do — see §1.

## 1. Wine, with the patches

`wine/wine-11.18/` is Wine 11.18 **with the patch series already applied**. `patches/` holds the same six changes
individually, each with its reasoning:

| # | subject | why Power BI needs it |
|---|---|---|
| 0001 | wintypes: resolve Windows Runtime type metadata | without it .NET cannot bind WinRT types |
| 0002 | ntdll: implement `NtImpersonateAnonymousToken` | the Analysis Services engine of Power BI cannot start |
| 0003 | secur32/lsass: RFC 4178 SPNEGO in `Negotiate` | modern auth against the modelling engine |
| 0004 | secur32: `LsaFreeReturnBuffer` | auth stack contract |
| 0005 | secur32: `GetUserNameExW` `NameUserPrincipal`/`NameDnsDomain` | licence/identity probes |
| 0006 | **oledb32: `IDataConvert` `VARIANT → DBTYPE_I8`/`DBTYPE_BOOL`** | **the canvas data path**: `CanConvert` advertised these arms but `DataConvert` had none, so the provider's natively bound 64-bit and boolean columns failed to read. With it: `DataExtensionError` 9 → 0 and the chart produces the data shape the Windows guest does. |
| 0007 | tests: the series in Wine's own test suite | the regression tests for 0001–0006, in the suite of the module each patch touches; each one fails on a tree without its patch (see below) |

Verify the series is intact, then build:

```bash
cd /home/asdf/Downloads/powerbi
bash scripts/check_patch_series.sh     # confirms the series is intact against the source tree
cd wine/wine-11.18
./configure --enable-archs=x86_64   # 64-bit only; Power BI Desktop is x64
make -j"$(nproc)"                   # ~20-40 min on 8 cores
make install                        # into wine/install/ (configure's default prefix is /usr/local — pass
                                    # --prefix="$PWD/../install" to stage it here instead, as this setup does)
```

A 64-bit-only build produces `wine`, `wineserver`, `wineboot` … and **no `wine64` binary** — that only appears in
the older 32-on-64 layout. `--enable-win64` is the legacy flag ("build a Win64 emulator on AMD64"); the current
equivalent for an x86-64-only tree is `--enable-archs=x86_64`, which is what this setup was built with.

`scripts/check_patch_series.sh` re-verifies the tree against the pristine upstream tarball
(`/home/asdf/Downloads/wine-11.18.tar.xz`), which is **not** in this folder — the copy in `wine/wine-11.18/`
already has the patches applied. You only need the tarball if you want to re-check or re-apply the series; the
series is also recorded in `patches/`, and `MANIFEST.txt` says exactly what is and is not in the folder.

`patches/`, `wine/wine-11.18/` and `scripts/` in *this* folder are the source material: the six patches, the same
source with them applied, and the scripts these instructions use. The scripts expect a *checkout* layout for the
prefix and logs, so the commands in §2–§4 are run from `/home/asdf/Downloads/powerbi-linux/` (which has the
tested prefix, the fonts and the WebView2 runtime already staged); copy `scripts/` into its `tools/` if you prefer
to drive everything from one place.

### Running the suite's own tests

`patches/0007-tests-cover-the-series.patch` puts the series in Wine's own test suite —
`dlls/ntdll/tests/impersonate.c` (new), `dlls/secur32/tests/{secur32,negotiate}.c`,
`dlls/oledb32/tests/convert.c` and `dlls/wintypes/tests/wintypes.c` — one test per patch, each of which fails
on a tree with that patch reverted. `scripts/run_wine_tests.sh` runs the five programs:

```bash
cd wine/wine-11.18
./configure --enable-archs=x86_64 --prefix="$PWD/../install"   # do not pass --disable-tests
make -j"$(nproc)"
cd ../.. && bash scripts/run_wine_tests.sh   # or: WINEBUILD=<build dir>, WINEPREFIX=<prefix>
```

It creates and boots the test prefix once (default `wine/testprefix`), stages the `vmwinmd/*.winmd` set into
`%SystemRoot%\System32\WinMetadata` - the same files `pbi_fixups.sh` deploys, and without them the two
`wintypes` resolution tests skip themselves - and runs the five programs, exiting non-zero if one fails.

Measured on this tree as shipped: `RESULT: PASS` - `wintypes` 1253 tests, `secur32` 261, `negotiate` 68,
`impersonate` 22, `convert` 11361, **0 failures** (42 of them `todo_wine`, which are Windows' answers Wine
does not give yet).  Each program was also run with its patch reverted, and the failures are the ones the
patch is about - both runs are in the working checkout's `docs/WINE_TESTS.md`.

You need `wine`, `wineserver` and `wineboot` from **this** build on `PATH` (or referenced by absolute path). The
working checkout already has one at `powerbi-linux/wine/install/bin/wine` — use it to skip the build while
testing, but a distro Wine will fail: patches 0002 and 0006 are load-bearing.

Optional: keep the source on `/home/asdf/Downloads` (14 GB free when this was written). The source is a few
hundred MB; the build artifacts are what make a full tree multiple GB.

## 2. Create the prefix and install Power BI

The install is scripted, unattended, and re-runnable. From the working checkout:

```bash
cd /home/asdf/Downloads/powerbi-linux
tools/install_pbi.sh pbi2
```

It takes an empty **win64** prefix to an installed Power BI in five stages, each for a measured reason:

1. **prefix** — `wineboot -u`, win64.
2. **.NET Framework 4.8** — `winetricks -q dotnet48`. This is a *hard* requirement: the app is WPF/.NET 4.7.2+,
   and **wine-mono cannot run WPF** (the MSI's managed custom actions crash it with "domain required for stack
   walk"). Allow 30–60 minutes and do **not** kill it; it is NGEN-heavy.
3. **fonts** — Segoe UI and Segoe MDL2 Assets; Wine ships neither and WPF asks for both.
4. **WebView2 runtime** — the report canvas and the start page are HTML/JS in WebView2. **The Evergreen installer
   cannot run under Wine**; the runtime is deployed from the NuGet package `WebView2.Runtime.X64` version
   `153.0.4234.48` (a directory containing `msedgewebview2.exe`). Pass it with `--webview2 DIR` if it is not in the
   default location.
5. **Power BI MSI** — `msiexec /i <msi> /qn ACCEPT_EULA=1 PBI_enableWebView2Install=false`, then the fixups in
   §3.

Useful flags: `--skip-netfx` (if the prefix already has .NET 4.8 — saves the long step), `--msi PATH`,
`--webview2 DIR`, `--webview2-version X`, `--bootstrapper` (installs via `PBIDesktopSetup_x64.exe` instead of the
MSI directly; the MSI path is the tested one).

If you would rather drive it by hand: run `PBIDesktopSetup_x64.exe` in the prefix, then apply
`tools/pbi_fixups.sh` — the stages above are what it automates.

## 3. The fixups (do not skip these)

`tools/pbi_fixups.sh [prefix]` is idempotent and safe to re-run. It sets:

- **WinMetadata** — copies the guest's `C:\Windows\System32\WinMetadata\*.winmd` into the prefix. .NET Framework
  resolves WinRT types (`Windows.Storage.StorageFile` and friends) from there and Wine ships none.
- **`PBI_forceTracing=1`** — turns on the app's own trace log, which is how every diagnosis in `FINDINGS.md` was
  made. Keep it.
- **Culture values** — `SupportsMultiLanguage`, `UICulture`, `DefaultUICulture`, **with the correct registry
  kinds**. `SupportsMultiLanguage` must be `REG_DWORD`; written as a string the app dies at startup with
  `value 'SupportMultiLanguage' isn't the expected type`.
- **Browser-emulation keys** for `PBIDesktop.exe`.
- **It deliberately does *not* set `HKCU\Software\Wine\Version = win10`.** Measured, run by run: with `win10` the
  WebView2 process *dies* (`OnWebViewProcessFailed` 9–11) and the main window renders solid black. With Wine's
  default version the count is 0 and the start page renders. The cost is cosmetic — the app logs
  `warningId="DeprecatedOS"` and shows a small banner.
- **It no longer writes `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS`.** That channel is **dead under Wine**: with the
  value set in `HKCU\Environment` *and* exported into the app's environment, 82 samples of every
  `msedgewebview2.exe` command line showed **0 hits** for `--disable-gpu`, `--remote-debugging-port` and
  `CalculateNativeWinOcclusion`. The documented policy key
  (`HKCU\Software\Policies\Microsoft\Edge\WebView2\AdditionalBrowserArguments`) is no better — the runtime never
  even queries it (0 reads in a 17.9 MB `+reg` trace). **Do not spend time tuning Chromium flags here; they never
  arrive.** This also means CDP (`--remote-debugging-port=9222`) cannot be used as a debugging channel.

## 4. Run it

```bash
cd /home/asdf/Downloads/powerbi-linux
tools/run_pbi.sh pbi 240 'C:\samples\IbeRevUATEpamPerformance.pbix'
```

`run_pbi.sh <tag> <seconds> [document]` launches the app on the display, samples frames into `logs/<tag>/`, and
**starts the presentation shim for you**. Env knobs: `PBIPREFIX` (prefix name under `prefix/`), `PBIDISPLAY`
(`:9` headless Xvfb or `:2` VNC), `WINEDLLOVERRIDES` (defaults to `mshtml=`, see below).

### Why the shim exists, and what it does

Wine has no compositor. Power BI hosts its report/model/DAX/TMDL views in **separate WebView2 top-level windows**,
each hosting a Chromium **GPU process that presents its surface out of band** (you can see it as
`msedgewebview2.exe --type=gpu-process` with its own `DXGI device window`). So the screen shows *the last DXGI
surface pushed*, not Wine's window painting. Consequences, all measured:

- Power BI keeps the **report view** selected and topmost throughout (its own trace: `SetView` 0,
  `DeactivateView` 0, `ActivateView …ReportView` 1), and Wine agrees (`z0 … reportView.html`, hit-test says
  `reportView`) — **but** a secondary view can present its surface over it once during startup.
- Once that happens, **no Wine-side fix restores the page**: setting the z-order, `InvalidateRect`+`UpdateWindow`+
  `RedrawWindow(RDW_UPDATENOW)`, and raising the X window were each measured to change **37 pixels out of 1.3 M**.
- The lever that works is to **hide the other view panels**, because a hidden window's Chromium renderer stops
  producing frames at all.

That is what `tools/pbi_occl_report_shim.sh` does every 5 seconds: `wvexstyle.exe hide reportView` (hide every view
panel except the report view) followed by `wvexstyle.exe redraw reportView`. `wvexstyle.exe` is at
`tools/winapi/bin/wvexstyle.exe` in the checkout (source `tools/winapi/wvexstyle.c`; also copied to
`scripts/winapi/` in this folder), and the shim stages it into the prefix as `C:\winapi\wvexstyle.exe` on each
pass, so you never have to deploy it yourself. Measured effect: **161 of 175 frames
the report page, with the DAX editor in zero** — where the repaint alone left the DAX editor on screen for 132 of
173. You can undo the hiding at any time with `wvexstyle.exe showall`, and it only touches the *presentation* —
the app keeps its own selected view and its state is untouched.

If you want the *details* rather than a summary: `docs/OCCLUSION.md`, and findings M64–M71.

## 5. Troubleshooting

**"another application run is already using display :9"** — the run locks live in `/tmp/pbi-*-lock` and are taken
by a *holder process*, not by the runner. If a run was killed you can be left with a lock whose owner is gone: check
with `fuser /tmp/pbi-apprun-9.lock` and `pgrep -af PBIDesktop.exe`, and if nothing holds it, `rm -f /tmp/pbi-*.lock`.

**The app stays alive after the sampler exits** — that is expected (`run_pbi.sh` SIGTERMs the sampler, not the
app). Kill it cleanly, which also resets Wine's display metrics: `WINEPREFIX=prefix/pbi2 wineserver -k`.

**Black window / WebView2 processes dying** — check you did not set `HKCU\Software\Wine\Version = win10` (§3), and
that the WebView2 runtime was deployed from the NuGet tree rather than the Evergreen installer (§2, stage 4).

**Nothing renders in the report canvas, or an error overlay** — check `DataExtensionError` and
`CanvasVisualErrorOverlayShown` in the app's own trace. Both go to 0 with patch 0006; if they are non-zero, your
build is missing it.

**The gate reports FAIL for `A3.1`/`A3d.3`** — those compare against
`evidence/windows/ref/report_ref.png`, which was calibrated as **unachievable even for the Windows guest's own
chart** (M57). Judge the canvas against `docs/WINDOWS_CANVAS_REFERENCE.md` and the guest's own frames instead:
`evidence/windows/dashboard_live.png`, `evidence/windows/pbi_run1_t10.png` and `evidence/windows/ref/` (the
report-view reference is `main_ref_reportview.png`; `report_ref.png` is the one that cannot be matched), plus the
traced WebView frames under `logs/windows-view/`. The chart's own features are the signal — y-axis `Temps d'arrêt`
with ticks 0.0–20.0, x-axis `Service`, a date legend, ~30 columns, and per-column data labels.

**Where does my document go?** Put it under the prefix, e.g. `prefix/pbi2/drive_c/samples/`, and pass the Windows
path (`C:\samples\YourDashboard.pbix`). A sample is already there.

## Limits and what does not work

Stated plainly, because a claim is only worth the measurement behind it:

- **The presentation fix is a host-side mitigation, not a Wine fix.** It works (measured above), but the real fix
  belongs in Wine: refresh the stored `visible_rect`/`surface_rect` of windows that a z-order or visibility change
  *exposes*, and generate the expose/invalidate such a change implies (`server/win32u`). That is designed but
  **not implemented** — verifying it needs Wine's own test suite, which this environment does not run. The
  acceptance criterion is recorded in `FINDINGS.md` M67.
- **A repaint alone is not enough.** One 420 s run held the report page (126 of 172 frames) and another of the same
  length did not (10 of 173). That was my own over-claim, withdrawn in M68/M69 — the takeover is a race with two
  variants, and only the hide cures both.
- **Chromium flags cannot be tuned** through the documented channels (§3), so occlusion/backgrounding behaviour is
  not adjustable from outside.
- **Cosmetic**: the `DeprecatedOS` banner appears in every view because Wine reports an old Windows version — and
  reporting a newer one *breaks* the WebView2 process (§3).
- The app is x64-only here; patches and prefix are win64.

## Provenance

Six patches against unmodified upstream Wine 11.18; the series applies cleanly and is checked by
`check_patch_series.sh`. No Microsoft software is redistributed in this folder — the installer, the MSI, the
WebView2 runtime and the fonts must come from your own sources. This work is AI-assisted; every claim above names
its measurement, and the milestone log is the record of what was tried, including what failed.
