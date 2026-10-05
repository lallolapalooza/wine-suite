# RESUME HERE

Read this first; `STATE.md` is the full append-only record (§1–§48) and `README.md` the deliverable
description. This file is the short version.

## Goal
Make CapCut PC (Windows x64, app 9.5.0.4050, installer `capcut_capcutpc_0_1.2.36_installer.exe`) run on Wine
like it does on Windows, by patching Wine. Working dir `/home/asdf/projects/capcut-wine` = `$CCWS`.

## Status (2026-10-04 13:15)
**Achieved and verified.** CapCut installs under Wine, opens its real UI (ToS dialog → home screen), runs
600 s with no crash, and paints in **both** renderer branches. One cosmetic item remains, with an agent on it.

* **31 patches** in `patches/series/`, verified to reproduce the tree byte-for-byte from pristine (30/30 verified by me, then 31/31 by the agent after series/0031).
  `patches/local/` (app-exclusive) is **empty and that is the honest answer** — every patch is a general Wine
  gap. Provenance: `patches/SERIES.tsv`; donor series copied into `patches/sources/`.
* The CapCut-gating patches: **0023** dcomp (upstream 11.18's is a 47-line `E_NOTIMPL` stub), **0024** DXGI
  composition swapchain, **0027** `EnumServicesStatusEx` buffer layout (the 100 s crash), **0028** d3d11
  GDI-compat flag, **0029** dxgi RGBA8 composition readback, **0030** dcomp committing through dxgi
  (`ba18ed4`). Plus 0026 `SWbemDateTime` and the AutoCAD/Power BI base series.
* Evidence: `recon/RENDER.md`, `recon/CRASH100S.md`, `recon/RE_VEDETECTOR.md`, `recon/GUEST_CAPTURE.md`,
  `recon/SWBEMDATETIME.md`, `recon/ours_d10_final/HOME_SCREEN_CLEAN.png`, `recon/hwdcomp1/`,
  `logs/final600b` (the clean 600 s run).

## Open
1. **"Project saved path not found" modal** — Wine-only (the guest does not show it). Measured to the field:
   Wine `serial=43000000 flags=0100008a` vs Windows `926618ac` / `03e72eff`; the **empty volume label is NOT
   the difference** (Windows returns `""` too). Agent `VolumeInfo` is implementing it as series/0031.
2. Guest still has Steinberg Download Assistant + WPTx64 (~286 MB); their uninstallers reject silent flags.
   Cosmetic, 15 GB free.

## The environment rules that make results reproducible
* **Display: `DISPLAY=:11`** — headless DRI3, from `scripts/start_headless_dri3.sh` (sway headless → Xwayland
  → openbox). The app **needs DRI3**: Xwayland works, **Xvfb (`:9`) cannot render it**, and `:10` is a window
  on the user's desktop that they can close mid-run (it cost one 600 s attempt). `:0` was never tested.
* **Wine: `$CCWS/wine-install/bin/wine`** (wine-11.18 + the 30-patch series). **DXVK must stay off** — its DXGI
  has no `CreateSwapChainForComposition`. Rebuild with `scripts/rebuild.sh` (re-runs configure, needed because
  the dcomp patch adds `dlls/dcomp/tests` to configure.ac).
* **The app rewrites its own config during startup**, so the software-render branch must be re-applied
  immediately before every run: `work/tools/cc_cfg.sh`. Without it a run silently starts in the hardware
  branch and is not comparable. This is why several early "software" runs were misread.
* **Run CapCut only through `scripts/cc_run.sh`** with `WINELOADER_BIN=$CCWS/wine-install/bin`. It holds
  `logs/.cc_run.lock`, and starting a run kills the previous run's processes, so serialise. Check `df -h /`
  (host was at 100 % once) and `uptime` first — a concurrent build stalled a run for no other reason.
* **Guest**: edit `vmshare/g.bat`, then `virsh send-key win11 KEY_LEFTMETA KEY_R` + `KEY_ENTER` (re-runs the
  Run-dialog history entry that loads it via `vp.bat`), read `vmshare/g_out.txt`. `vmkeys.py "{WIN}r"` does
  NOT open the dialog. Guest failures were a **full disk** (`curl` rc=23, 0-byte files), not the network.
* Crash dumps: `$CCWS/tools/venv/bin/python` + `scripts/dmp_threads.py` / `work/tools/dmp_fault.py` (the app's
  own `minidump_stackwalk.exe` is 32-bit and cannot run on our x86_64-only build). Keep
  `logs/ours_d10_final/crash.dmp` and `logs/fix600b/crash.dmp`; delete other 200 MB dumps to save space.

## Habits this project has already been burned by (twice each, both recorded)
* **An API-level test is not evidence that pixels appear.** `t_d3d11dcomp` reported `ALL PATHS OK` while the
  app stayed white — it only exercised the API, and only with `B8G8R8A8`. It now reads the window pixel back
  for both formats. Same class of error: a symbol difference between two dcomp builds was read as "the code
  path is missing" when ours simply failed on the format.
* **Never promote an inference to a measured row.** The "`:0` works" row was my inference and the user had
  never tested it. State what was measured, and **name the display** beside every rendering result.
* Both of the above are why the remaining claims in this repo cite a run tag and a file.

## Next steps, in order
1. Let `VolumeInfo` finish series/0031 (see its brief: report the drive's real identity rather than
   hard-coding Windows' constants; probe both sides; re-run on `:11` and screenshot the modal's absence).
2. Re-verify the series at 31/31 and update `patches/README.md`/`SERIES.tsv`.
3. Refresh `README.md` §6 (Status) if anything changes; it currently states the software branch as the working
   configuration — that is still where the acceptance shot came from.
4. Nothing else is outstanding.

## Note on STATE.md's numbering
Two sections are numbered `§48` — the hardware-branch closure (written by the `QtDcompPath` agent, ~line 1039)
and the guest-disk result (mine, at the end). `STATE.md` is append-only and renumbering is not worth the
churn; cite by subject when it matters. Section order in the file is also not strictly numeric: the agent
appended §48 between §44 and §45. Read by heading, not by number.
