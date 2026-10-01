# The verified workspace

The install these notes describe is `$REVIT_WORK/prefix3` (default
`/home/asdf/projects/revit/prefix3`). It is **not** part of this repository (~43 GB); this file
records what it is, how it was produced and what state it is in, so it can be rebuilt and checked.

## How it was produced

1. prefix, created by hand with the fork's own Wine (`wine-install/`) rather than by
   `tools/install_revit_prefix.sh`:
   * `wineboot -u` — win64 prefix reporting Windows 10;
   * `(cd installer && Setup.exe -q)` with `WINEDLLOVERRIDES="mshtml="` (mscoree left enabled,
     see README "How this fork differs");
   * the four environment fixups (Arial/`arialbd`/`micross` + their `Fonts` entries, the
     `installed-components.autodesk` hosts line, `RpcSs`/`SamSs` `Start=2`, and
     `HKCU\Environment\WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--disable-gpu`);
   * `tools/fetch_missing_packages.py prefix3` — installs the 13 bundle packages ODIS never
     downloaded (24,051 files, `RCPCOMEXT` and the unit-schema package among them);
   * `tools/neutralize_postinstall.py prefix3` — drops the three PowerShell-hosted post-install
     actions from the package manifests;
   * a second `Setup.exe -q` over the same prefix: no rollback this time, `rc=0`, and it installed
     what was still missing (`Revit 2027.3 Update`, `Personal Accelerator`, the developer toolset):
     144 `HandleInstallSuccess` in total.
2. `wine-install/`, built from `wine/wine-11.18` with the whole series applied — including this
   fork's own patch `0100` (`ncrypt` ECC key import), without which Revit aborts at startup.

## State

* `Program Files/Autodesk/Revit 2027` — 5.0 GB, `Revit.exe` present together with the DLLs
  `DesktopMFC.dll` imports (`Qt6Core.dll`, `Qt6Gui.dll`, `QtSolutions_MFCMigrationFramework.dll`,
  `RWUXThemeSU2015.dll`, `sfl400asu.dll`, `ot1000asu.dll`, `og1100asu.dll`, `Ecotect.dll`).
* Support stacks install and run: `AdskLicensing 16.6.0.16341` (service running), .NET 10.0.9
  desktop runtime, WebView2 runtime 143.0.3650.66, VC++ 2022.
* ODIS `Install.db`: 49 package rows, 144 `HandleInstallSuccess`, the 3 `HandleInstallFailure`
  entries are the `ignoreFailure` ones (`Essential RUS Content`, `Core Content Samples`, and one
  more content package) recorded before the manifests were neutralized.
* `Revit.exe` **starts, paints and reaches the licensing stage**:
  * window `Autodesk Revit 2027` (860x500) up, alive for a full 150 s sample window, splash painted
    (capture with 13.8k distinct colours, OCR `AUTODESK`);
  * journal: `License initialization complete / License version: 10.0.1.66`, `loadAllDB`,
    `Primary Revit session detected during initializeWebBrowserControl`, `manage licensing`;
  * `AdskLicensingAgent.exe` creates its own 860x500 licensing window and WebView2 comes up
    (`WebView2 Manager`, `Utility: Network/Storage Service`, `WebView2: AdskLicensingWebPlatform…`).
* **The licensing dialog paints** (patches `0101`/`0102` in this tree): the page owned by
  `AdskLicensingAgent.exe` renders its content — `colors=5085`, OCR `Let's Get Started / Sign in with your Autodesk ID /
  Other license types / Enter a serial number / Use a network license` — verified on three consecutive runs, with the
  control reproducer (`C:\wv2\wv2test.exe` → `WV2 WINDOWED OK`) and `dlls/dcomp/tests/dcomp.c` (24/24) green.
* **Historical limit, now fixed** (kept for context): before `0101`/`0102` the licensing page's pixels never appeared. The agent's window
  captures as a blank white rectangle (1 distinct colour, mean 65535), and when Chromium's GPU
  process is allowed to start it blanks the whole X screen. With
  `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--disable-gpu` no GPU process starts
  (`pgrep msedgewebview2` → 0) but the surface stays blank. The AutoCAD fork documents the same
  behaviour ("webview areas stay blank rectangles"). Signing in would also need an Autodesk account.

## Evidence

| path (under `$REVIT_WORK`) | what it is |
|---|---|
| `logs/prefix3-state/system.reg`, `user.reg` | the prefix registry at the verified state |
| `logs/prefix3-state/Install.db`, `Package.db` | ODI​S's own record of the install |
| `logs/prefix3-state/Install.log` | the full install manager log of both passes |
| `logs/prefix3-state/journal_licensing_stage.txt` | the journal of a run that reaches `manage licensing` |
| `logs/prefix3-state/odis_state.json` | package inventory extracted from `Install.db` |
| `logs/ui/<tag>/` | per-run window captures and the window-tree samples (`out.txt`) |
| `logs/log_<tag>.txt` | each run's stdout/stderr (Wine debug output included) |
| `NOTES.md` | the running investigation log, with the evidence behind each fix |

## Reproducing from an empty prefix — not run here

`tools/install_revit_prefix.sh <empty-prefix>` performs the whole pipeline (prefix, unattended
install, post-install action watcher, the 13 skipped packages, the fixups). It needs **~40 GB free**
because a full prefix is 38-43 GB. This machine had 7.6 GB free at the end of this work, so that
end-to-end gate is still to be run where there is room; everything above was verified on `prefix3`
plus the Wine test suite (`tools/run_wine_tests.sh ncrypt` → 445 tests, 0 failures).

## Re-running what was verified

```
export WINEPREFIX=…/revit/prefix3 DISP=:3        # any working X display
wine-install/bin/wine "<prefix>/drive_c/Program Files/Autodesk/Revit 2027/Revit.exe"
tools/run_revit.sh revit_check 150 15            # samples the window tree + captures
tools/verify_revit.sh …/revit/prefix3 240        # PASS/FAIL gate, incl. install completeness
```
