# Resolume Arena 7 on Wine — working state

Updated: 2026-10-03 (session 1). **Read `FINDINGS.md` next** — it holds the evidence; this file holds the position.

## Goal
Make `Resolume_Arena_7_28_0_rev_24303_Installer.exe` install and **open like on Windows** under a
locally built, patched Wine 11.18, with the reference behaviour taken from the `win11` libvirt guest.

## STATUS: the app opens. Two fixes were needed.
Arena 7.28.0 installs under Wine, completes startup and renders its **full UI** — composition grid,
`Composition - 1280x720` + Preview monitors, transport, panels, effects, Files browser, status bar
`Resolume Arena 7.28.0`. Evidence: `logs/runs/ui1_root.png` (vision-checked) and
`logs/runs/wine-final/` from `tools/run_arena.sh`.

| fix | what | where |
|---|---|---|
| **1. `dxgi` `WaitForVBlank`** | Wine returned `E_NOTIMPL` from `IDXGIOutput::WaitForVBlank`, which Arena calls on its display/output path; startup then went idle with a black window and never reached the UI. Now paced at the output's refresh rate. **This is what unblocked startup.** | `patches/local/0100-dxgi-output-WaitForVBlank.patch`, built into `wine-install/` |
| **2. Core fonts in the prefix** | Wine substitutes Arial/Verdana for `CreateFont` but does not *enumerate* them, so Arena's `Find default fonts` failed with `Default fonts not available`. | `tools/install_corefonts.sh` (wired into `tools/mkprefix.sh`) + `docs/FONT_REQUIREMENT.md` |

Both are required: the `dxgi` patch lets startup progress, the fonts let it pass `Find default fonts`.

## Reproduce from scratch
```sh
source env.sh
tools/build_wine.sh --jobs 8          # pristine 11.18 + patches/series (0001..0019) + patches/local
tools/mkprefix.sh                     # wineboot, win10, core fonts, VC++ 2022 + Vulkan, then the vendor installer
tools/run_arena.sh <tag> --secs 180 --iv 30    # runs Arena on DISP=:2 with screenshots
```
Wine sources: `wine-11.18/` pristine (tarball), `wine/wine-11.18/` = pristine + `patches/series/*`
(acad-wine-main 14 + powerbi 5) + `patches/local/0100-…`; `wine-install/` is `make install` output.

## Hard constraints
- **Memory**: 30 GiB total, 8 GiB held by the `win11` guest; check `free` before build/run.
- **Disk**: `/` shared; ~40 GiB free after the build.
- **Temp must be disk-backed**: `TMPDIR=$RW/state/tmp` (env.sh).
- Subagents hit `402 Insufficient account funds`; re-spawn with `model: "@default"` (parent model)
  — that worked for `ApiTracer2-2` / `GlProbe2-2` / `LogDiffFinish-2`.

## Tooling (all verified this session)
| tool | purpose |
|---|---|
| `tools/build_wine.sh` / `tools/apply_patches.sh` | configure+make+install (wiki new-WoW64 recipe), apply the series |
| `tools/mkprefix.sh` | prefix, Windows 10, core fonts, prerequisites, vendor installer |
| `tools/run_arena.sh <tag>` | run + sample windows/screenshots into `logs/runs/<tag>/` |
| `tools/apitrace/` | Windows x64 **API tracer** (`apihook.dll` + `apitrace.exe`, IAT hooking) — runs in the guest *and* under Wine; config `tools/apitrace/res.cfg` |
| `tools/relaydiff.py` | normalise/diff Wine `+relay` logs vs tracer logs (`wine-log --errors`, `--tail`, `--modules`, `diff`) |
| `tools/winapi/` | probes: `glprobe` (GL/WGL), `winspy` (window tree), `fontprobe` (font families), `glclear` (X capture control), `layeredfix`, `memtext` (reads the app's *buffered* log out of its memory) |
| `tools/install_corefonts.sh` | install Arial/Verdana/… into a prefix (`--check` re-runs fontprobe) |
| `tools/vm/` | guest channel: `vmcmd.sh`, `vmserv.py` (HTTP PUT), `vmtype2.py`, `elev.sh` (UAC → Alt+Y) |

## Reading Arena's progress (learned the hard way)
- Arena's **log file is buffered**; it can sit at 3 lines for minutes, then flush in a burst, and
  unflushed lines are lost on kill. Use the **X window list** as the progress signal, or
  `tools/winapi/memtext.exe 'INFO:' --pid N` to read the still-buffered text from memory.
- Wine names an app process after its main thread (`Main Thread`), so `pgrep -x Arena.exe` finds
  nothing — match on the command line (`pgrep -f`) instead.
- X capture **does** see Wine GL content (`glclear.exe` clears magenta and shows in a root shot), so a
  black Arena window is real, not a capture artifact.
- `winedbg <winepid>` works (`info threads`, `thread <hex tid>`, `bt`) — Wine attaches through the
  wineserver, so `ptrace_scope=1` does not block it.

## Remaining rough edges (not blocking the UI)
- `WARNING: Failed writing CompositionInfoCache to …\CompositionsInfoCache.json` once at startup.
- Wine still stubs/`fixme`s: `RegisterSuspendResumeNotification`/`Unregister` (handle `0xDEADBEEF`),
  `RoGetActivationFactory(UIViewSettings)` semi-stub, `RegisterTouchWindow`, and
  `CLSID_VirtualDesktopManager` ({aa509086-…}) is missing (JUCE probes it; its fallback is benign).
  None of them stopped the app.
- The app imports no directly-stubbed Wine function (checked against the specs).

## Housekeeping
- `installer/media_x/` is 3.1 GB (re-extractable; FINDINGS M1).
- `state/tmp/` holds the Mesa Windows build, JUCE 7.0.7 source and the font set.
- `logs/` holds every run; `logs/vm-baseline/` the Windows reference screenshots.
