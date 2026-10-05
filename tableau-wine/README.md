# Tableau Desktop 2026.2.3 on Wine

Tableau is a registered trademark of Salesforce, Inc. This repository is not associated with, affiliated with, supported nor endorsed by Salesforce, Inc. No guarantees are made, as for the suitability of the content of this repository for any particular purpose.

No Salesforce or Tableau software is redistributed here. The install media must come from your own Tableau download or licence account; the scripts take it from `$APP_EXE` (see `env.sh`).

Make `/home/asdf/Downloads/TableauDesktop-64bit-2026-2-3.exe` (Tableau Desktop 2026.2.3, 64-bit;
743 872 856 B) install and open under Wine 11.18 "like on Windows".

Method: start from the union of the existing AutoCAD + Power BI Wine patch series, then trace what
Wine still lacks against a Windows 11 guest, patch Wine, and document every step. Acceptance is
**parity, not activation**: where the Windows reference stops at a sign-in / licence screen with no
account or key, Wine stopping at the same screen is success (`STATE.md` §5b). All work is
AI-assisted and is **not** intended for upstream submission (`STATE.md`).

The repository is self-contained with respect to Wine changes: the complete set of patches applied
to the Wine tree lives in `patches/` (the 20-patch union series `0001`–`0020`, plus two post-union
generic patches `0021`/`0022`), and `patches/app-exclusive/` is reserved for Tableau-only patches.
See `docs/PATCHES.md`.

## Acceptance status

**Reached** (`STATE.md` 2026-10-04T04:52Z). The real installer installed the app into a clean prefix,
`tableau.exe` stayed alive (150 s, 36 frames), and Wine shows the same activation screen the Windows
reference shows — same heading, same three activation choices, same "Learn more about licensing and
activation" link, same Exit button. Side-by-side: `evidence/windows_vs_wine_activate.png` (Windows
`logs/win-reftab/frame_026.png` vs Wine `logs/run-inst/frame_030.png`); pixel metrics between the two
frames: AE 506 185 (0.494), RMSE 0.212, mean absolute difference 16.1 — the residual is window
chrome/desktop, not content. Activation itself was never attempted, on either platform: the Windows
reference is unlicensed too, which is why parity, not activation, is the criterion (`STATE.md` §5b).

## Measured state

State of record is `STATE.md` (append-only status log). Last entry `2026-10-04T04:52Z`.

| area | measured status | evidence |
|---|---|---|
| End result | Wine reaches the Windows "Activate Tableau" screen | `evidence/windows_vs_wine_activate.png`; `logs/run-inst/{run.log,frame_030.png,windows_036.txt}`; `STATE.md` 04:52Z |
| Wine build | patched Wine 11.18 built in place and installed to `wine-install/` (marker `wine-install/.wine-build-complete`, `wine --version` → `wine-11.18`). Built from the 20-patch union; the two later patches `0021`/`0022` are in the source tree but **not yet in this binary** (incremental rebuild pending) | `logs/wine-build.log`; `STATE.md` 04:45Z |
| Patch series | 22 patches in `patches/`: union `0001`–`0020` (AutoCAD + Power BI) + `0021`/`0022` (post-union, generic). `patches/app-exclusive/` is empty | `patches/SERIES.md`, `docs/PATCHES.md`, `logs/union/union-check.log` |
| Installer (Burn + MSI) | **works**: WiX Burn bundle ran the whole chain (VC2022Redist ExePackage → Tableau MSI → `InstallFinalize`) in **63 s, exit 0x0**, zero `Return value 3`, no Wine `err:` lines; 5425/5425 files / exactly 2 208 240 220 B (= the MSI `InstallSize`) and md5-identical to the `msiextract` reference; `HKLM\SOFTWARE\Tableau\*` written; Start-Menu shortcut created; `FlexNet Licensing Service 64` created and **RUNNING**. Direct `msiexec /i` also succeeds (40 s) | `recon/INSTALLER_WINE.md`; `logs/install-wine-burntest/{burn.log,burn_001_Tableau.log,direct_msi.log}`; `STATE.md` 04:48Z |
| Why no elevation is needed under Wine | `dlls/msi/package.c:737-741` hard-codes `Privileged`/`MsiRunningElevated` = 1, and `programs/sc/sc.c:430-433` fakes success for `sc sdset` (the MSI's DACL custom action is a no-op) | `recon/INSTALLER_WINE.md` §4 |
| App install | clean prefix `prefix/tableau-inst` installed by the bundle: 5425 files, `mfc140u.dll` in `system32` installed by the bundle's own `VC2022Redist` package, `HKLM\SOFTWARE\Tableau\{Directories,FlexNetUsers,Tableau 2026.2}` present | `STATE.md` 04:48Z; `recon/INSTALLER_WINE.md` §3 |
| App runtime | `tableau.exe` starts and **stays alive** (150 s, 36 frames); X window tree contains `0x1400013 "Activate Tableau"` (650x478) | `logs/run-inst/run.log`, `logs/run-inst/windows_036.txt` |
| Licensing/identity path | executes under Wine: Qt WebEngine/Chromium starts, cert-store activity, and `Tbsi_GetDeviceInfo` (TPM) is reached — as Wine's stub | `logs/run-inst/run.log`; `STATE.md` 04:52Z |
| Patch classification | **no app-exclusive patch was needed.** The activation window was reached with the 20-patch union on pristine Wine 11.18 and no Tableau-specific Wine change; what Tableau additionally needed was *configuration* installed by its own bundle (VC++ 2022 runtime, registry, the FlexNet service). Per-patch necessity for Tableau was **not** bisected | `STATE.md` 04:52Z; `docs/PATCHES.md` |

Nothing above is a promise; each row names its measurement.

### Windows reference (what "like in Windows" means)

The verified silent line is
`/quiet /norestart /log C:\tableau_burn.log ACCEPTEULA=1` (`ACCEPTEULA=1` is mandatory; without it
the bootstrapper exits `0x80070057` before doing anything). The bundle is a WiX Burn bundle that
chains an ExePackage `VC2022Redist` (`/install /quiet /norestart`) and one MSI `Tableau`
(ProductCode `{D5C4243D-E35D-4F26-A837-EDB5C3AA3739}`). Full procedure: `docs/REPRODUCE_WINDOWS.md`.
The Windows reference is unlicensed, so with the real MSI install it stops at the same
"Activate Tableau" window (`recon/LICENSE_RISK.md`; `logs/win-reftab/frame_026.png`).

Installer static analysis: `recon/INSTALLER.md` (container layering, MSI tables, unattended command
lines, risk list), `recon/INSTALLER_WINE.md` (the measured Wine run). Components and the Wine-risk
import scan: `recon/TABLEAU_STACK.md`. Licensing mechanism and the identity/hostid APIs FlexNet
uses: `recon/LICENSE_RISK.md`, `recon/HOSTID_PROBES.md`, `recon/hostid_probe_wine.txt`. Open-source
components' Win32 surface and Wine's status per call: `recon/OPENSOURCE_TRACE.md`.

## Layout

```
STATE.md                 state of record (append-only status log; survives compaction)
README.md                this file
docs/                    METHOD.md, REPRODUCE_WINDOWS.md, PATCHES.md
patches/                 0001..0022 (+ SERIES.md, app-exclusive/, from-autocad/, from-powerbi/)
src/                     pristine wine-11.18.tar.xz (upstream, unmodified)
wine-11.18/              patched Wine source, built in place (source of truth; no second copy - disk)
wine-install/            installed Wine 11.18 build used for every run
prefix/                  Wine prefixes (tableau-inst/ = the verified end-to-end prefix)
app/                     extracted installer payload (a0 = VC++ redist, a1 = MSI, msi_root/ = 5425-file tree)
tools/                   build / prefix / install / run / diagnose helpers, tools/vm/ guest channel, tools/winapi/ probes
recon/                   recon reports + raw evidence (msi_tables/, evidence/, imports_raw.json, ...)
evidence/                side-by-side acceptance frame (windows_vs_wine_activate.png)
logs/                    every measured run (union/, install-wine-*, run-*, diag-*, win*, wine-build.log)
state/                   working copies of guest-harvested Windows state
vmshare/                 host<->Windows-guest HTTP share
```

Conventions: every patch file carries symptom → Windows behaviour → how verified; every claim in
these docs names its measurement; logs go to `logs/<tag>/`.

## Build the patched Wine

```sh
$P=/home/asdf/projects/tableau-wine
"$P/tools/mem_guard.sh" &            # supervised RAM ceiling (85%); required during builds
JOBS=4 "$P/tools/build_tableau.sh"          # configure once + make + make install
JOBS=4 "$P/tools/build_tableau.sh" --inc    # incremental rebuild after a patch (ccache on)
"$P/tools/build_tableau.sh" --check         # print state, build nothing
```

* Source tree `wine-11.18/` is configured `--enable-archs=i386,x86_64 --disable-tests` and built
  **in place** (the outer Burn stub is 32-bit i386, the product is x86-64; `recon/INSTALLER.md` §3).
* Install prefix defaults to `wine-install/`; `wine-install/.wine-build-complete` marks a finished
  install (`tools/build_tableau.sh`). The current `wine-install/` is the 20-patch-union build;
  rebuild (`--inc`) to compile in `0021`/`0022` (`STATE.md` 04:45Z).
* Resource limits in force: `-j4` max and >= 8 GiB free RAM before any run; an OOM (92–96 % used) was
  already recorded from stale `wineserver`/`winedevice.exe` processes left by other projects, not by
  this build (`STATE.md` 04:30Z). `tools/mem_guard.sh` enforces the ceiling.

## Install and run the app under Wine (the verified path)

```sh
$P=/home/asdf/projects/tableau-wine
"$P/tools/make_prefix.sh" "$P/prefix/tableau-inst"    # fresh win64 prefix (fonts + .winmd + wineboot)
export WINEPREFIX=$P/prefix/tableau-inst DISPLAY=:11
export WINE=$P/wine-install/bin/wine

# the real WiX Burn bundle, same command line as the verified Windows run:
"$P/tools/install_tableau_wine.sh" final      # resolves the installer path itself
# or directly:
"$WINE" /home/asdf/Downloads/TableauDesktop-64bit-2026-2-3.exe \
        /quiet /norestart /log 'C:\tableau_burn.log' ACCEPTEULA=1

# run it, with frames + window tree:
PREFIX=$P/prefix/tableau-inst "$P/tools/run_tableau.sh" inst 150
```

* Measured result of the bundle run: 63 s, exit 0x0, 5425/5425 files, 2 208 240 220 B,
  FlexNet service RUNNING (`recon/INSTALLER_WINE.md`).
* `tools/install_tableau_wine.sh` takes the installer path from `$TABLEAU_INSTALLER`, then
  `src/TableauDesktop-64bit-2026-2-3.exe`, then `/home/asdf/Downloads/...`; the earlier wrong
  `$ROOT/../Downloads/...` path has been fixed (`STATE.md` 04:48Z).
* Uninstall: `wine ... /uninstall` (bundle) or
  `msiexec /x {D5C4243D-E35D-4F26-A837-EDB5C3AA3739} /qn` (`recon/INSTALLER.md` §7.2).

### Alternative: run without the installer (runtime-only)

To test "does the app run" independently of the installer (`docs/METHOD.md` §1 phase A):

```sh
"$P/tools/make_prefix.sh"                             # default prefix/tableau
"$P/tools/deploy_tree.sh"                             # C:\Program Files\Tableau -> msi_root/Tableau (symlink)
```

That tree has no MSI install state, so it needs the VC++ 2022 runtime by hand (the bundle's own
prerequisite package `app/tableau_exe/a0`, 14.44.35211.0; `recon/INSTALLER.md` §6):

```sh
WINEPREFIX=$P/prefix/tableau "$P/wine-install/bin/wine" \
    "$P/app/tableau_exe/a0" /install /quiet /norestart
```

If Wine's builtin `msvcp140`/`vcruntime140` shadow the native ones, force the redistributable's
(`STATE.md` 04:29Z):

```sh
export WINEDLLOVERRIDES='msvcp140,msvcp140_1,msvcp140_2,vcruntime140,vcruntime140_1,mfc140u,mfc140=n'
```

Without the MSI's registry + `FNPLicensingService64` state the app stops at the FlexNet gate
(`The licensing service is too old.` / "could not access Trusted Storage"; `STATE.md` 03:54Z),
whereas the bundle install above provides that state itself.

## Run and diagnose

```sh
export WINEPREFIX=$P/prefix/tableau-inst DISPLAY=:11     # VNC display :11 (localhost:5911)

# GUI twin with frames + window tree (what produced the acceptance evidence)
PREFIX=$P/prefix/tableau-inst "$P/tools/run_tableau.sh" inst 150

# console twin: prints the app's own reason for refusing to start on stdout/stderr
"$P/wine-install/bin/wine" 'C:\Program Files\Tableau\Tableau 2026.2\bin\tableau.com'

# Wine's own channels, deduped err/warn histogram and backtrace
CHANNELS='err+all,fixme-all,seh' \
    "$P/tools/wine_diag.sh" t1 'C:\Program Files\Tableau\Tableau 2026.2\bin\tableau.exe'

# compare a Wine frame with the Windows reference frame
"$P/tools/cmp_frames.sh" logs/win-reftab/frame_026.png logs/run-inst/frame_030.png
```

* `tools/wine_diag.sh` writes `logs/diag-<tag>/{stderr.log,errs.txt,tail.txt,backtrace.txt}`;
  `errs.txt` (deduped `err:`/`warn:`) usually names the missing API outright.
* `+relay` on a Qt/Chromium app emits gigabytes; narrow it in the registry instead of grepping
  afterwards: `wine reg add 'HKCU\Software\Wine\Debug' /v RelayInclude /t REG_SZ /d 'ntdll,kernelbase,secur32' /f`
  (`tools/wine_diag.sh` header).
* `tools/cmp_frames.sh` prints AE/RMSE and writes a labelled side-by-side montage. Windows frames
  come from `tools/win_frame_sampler.sh` (one sampler at a time).
* `tools/collect_logs.sh <tag>` pulls the app's own logs from both platforms for diffing.
* The app's own tracing knobs (`-DLogLevel=Debug`, `QT_LOGGING_RULES`, `QTWEBENGINE_CHROMIUM_FLAGS`,
  the `C:\ProgramData\FLEXnet` licensing log) are documented in `recon/TABLEAU_STACK.md` §7.

## Patches

`patches/` holds every Wine patch used for this port: the 20-patch union of the AutoCAD and Power BI
series (`0001`–`0020`, ordered low-level → dlls → programs → tests) plus two post-union patches
(`0021` userenv AppContainer SID, `0022` user32 pointer-frame) that came from the Qt/Chromium source
trace; both are generic Wine gaps, and neither is required to reach the activation screen. No
app-exclusive patch exists: `patches/app-exclusive/` is empty (verified), because the activation
window was reached with the generic union alone. `patches/SERIES.md` is the authoritative series
record; `docs/PATCHES.md` is the catalogue with apply order, verification and the app-exclusive
section. `patches/from-autocad/` and `patches/from-powerbi/` retain the original input patches; no
other `*.patch` files exist in the working directory (checked with `find` outside `patches/` and
`wine-11.18/`).

## Limits and what does not work yet

* **Not bisected.** The app was run with the whole 20-patch union; which individual patches are
  strictly necessary for Tableau was not determined (that would be N rebuilds) — `STATE.md` 04:52Z.
* **Activation.** Never attempted on either platform; the criterion is parity with the unlicensed
  Windows reference (`STATE.md` §5b, `recon/LICENSE_RISK.md`).
* **GPU / WebEngine.** Wine's log shows `Failed to create GLES3 context, fallback to GLES2` and
  `Failed to create shared context for virtualization` (`logs/run-inst/run.log:397-398`; ANGLE/D3D11
  through Wine's wined3d/vkd3d), as predicted by `recon/OPENSOURCE_TRACE.md`; the activation window
  renders despite it, but heavier WebEngine content was not exercised (`STATE.md` 04:52Z).
* **Identity / hostid.** `Tbsi_GetDeviceInfo` (TPM) is Wine's stub; Wine's
  `IOCTL_STORAGE_QUERY_PROPERTY` returns a faked descriptor (`mountmgr:query_property Faking
  StorageDeviceProperty data`), where Windows reports `product="QEMU HARDDISK"`, `serial="QM00001"`
  for the same device — `recon/HOSTID_PROBES.md`, `recon/hostid_probe_wine.txt`,
  `recon/hostid_probe_wine_debug.txt`.
* **`AF_UNIX` unsupported** by Wine's `ws2_32` (`socket(AF_UNIX,…)` → `WSAEAFNOSUPPORT`), which
  matters for gRPC/UDS endpoints; the two genuine missing exports from the payload load-time audit
  are now patched by `0021`/`0022` (`recon/OPENSOURCE_TRACE.md` §2, §9).
* **`sc sdset` is a fake success** under Wine (`programs/sc/sc.c:430-433`), so the FlexNet service
  DACL is not applied; harmless because Wine does not enforce it (`recon/INSTALLER_WINE.md` §4).
* **Not upstream-ready.** Patches carry no upstream-polish guarantee; this is a research port
  (`STATE.md`). `STATE.md` cites a scout report `recon/WINDOWS_METHOD.md` that is **not present**
  under `recon/`; the local copy of that method is `docs/METHOD.md` §5.
