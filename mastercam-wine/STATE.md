# Mastercam 2027 on Wine — working state

Updated: 2026-10-03 (session 1). **Read `FINDINGS.md` next** — it holds the measured evidence; this
file holds the position and how to resume.

## Goal
Make `mastercam2027-web.exe` install and **open like on Windows** under a locally built, patched
Wine 11.18. Reference behaviour comes from the `win11` libvirt guest (already running). Wine patches
start from the **AutoCAD-on-Wine series (14) + Power BI-on-Wine series (5)** — the user's
instruction — and grow with whatever Mastercam needs.

## Deliverable
`/home/asdf/projects/mastercam-wine/` — the new working dir for this project. It must end up
containing (a) every Wine patch used, (b) any font/prefix/setup fix as a reproducible script,
(c) the evidence (logs, screenshots) and (d) state docs.

## Layout
| path | what it is |
|---|---|
| `wine-11.18/` | **pristine** Wine 11.18 (hardlink copy of the resolume project's pristine tree) |
| `wine/wine-11.18/` | the tree that gets built: pristine + `patches/series/*` + `patches/local/*` |
| `wine-install/` | `make install` output; `wine-install/bin/wine` |
| `patches/series/` | `0001..0019` — AutoCAD-on-Wine (14) + Power BI-on-Wine (5), the exact user-requested base |
| `patches/sources/` | the untouched patch directories of those two projects (+ `resolume-local/` kept only as a reference, **not applied**) |
| `patches/local/` | this project's patches (empty at start) |
| `tools/` | build / prefix / run / probe / VM tooling (copied from the resolume project, adapted) |
| `tools/vm/vmcmd.sh` | guest command channel (uses this project's `vmshare`) |
| `vmshare/` | HTTP-shared dir with the guest; `mastercam2027-web.exe` is symlinked here |
| `installer/` | reserved (payload actually lives in `$MCW_MEDIA`, see below) |
| `state/work/prefix` | the Wine prefix the app is installed in |
| `state/tmp/` | disk-backed scratch; also holds `rar/unrar` 7.12 (RAR7-capable) |
| `logs/` | build logs, run logs, evidence |

**Extracted payload**: `/run/media/asdf/Windows/mastercam-media` (NTFS partition, 2.2 GiB) — kept off
`/` because `/` is tight (≈33 GiB free). `$MCW_MEDIA` points there.

## STATUS
- [x] Project skeleton created; tools + 19-patch series copied.
- [x] Installer payload extracted with **unrar 7.12** (`state/tmp/rar/unrar`); 7-Zip 26 *cannot*
      decode this RAR7 `m3` payload (see FINDINGS M1).
- [x] Payload reverse-engineered — see `docs/PAYLOAD_RECON.md`. App profile: **native MFC/C++ +
      C++/CLI (`ijwhost`) + a WPF ManagedUI targeting `net10.0` (runtime NOT bundled)**, **OpenGL +
      D3D9** (no Vulkan/CEF), **CodeMeter** runtime required at startup (`WIBUCM64.dll` is a static
      import of `MastercamLauncher.exe`), MSI install ≈3.3 GB, default dir `C:\Program Files\Mastercam 2027`.
- [x] Patch-series relevance map written: `docs/PATCH_SERIES.md`.
- [x] Guest HTTP command channel **rebuilt and hardened**: the original poller wedged on a long
      `curl`; it is now `C:\seref\poller.ps1` + `C:\seref\runner.ps1` (the poller launches the runner
      as a separate process, so a slow command can never block the channel). Bootstrap from the guest
      GUI with `vmshare/mc_svc.bat`. See FINDINGS M3.
- [x] Guest GUI control path works: `virsh screenshot` + `virsh send-key`; typing with
      `tools/vm/vmtype2.py` / `tools/vm/vmkeys.py` (model has no vision → OCR with `tesseract`).
- [x] Wine 11.18 **built with the 19-patch series + our two local patches**
      (`patches/local/0100-msi-class-registry-view.patch`, `patches/local/0101-services-service-logon-token.patch`);
      `wine-install/bin/wine --version` → `wine-11.18`.
- [x] Mastercam installed in the `win11` guest; reference captured (M11): Windows reaches the licence
      splash + `No Mastercam license found.` — it cannot license it either, because **no licence,
      dongle or licence server exists in this environment**.
- [x] Mastercam **installed under the patched Wine** (`state/work/prefix`, 7.5 GB) together with core
  fonts, .NET 10.0.12 Desktop, .NET Framework 4.8, VC++ 2022, CodeMeter and the English Language Pack.
- [x] **The app runs**: `Mastercam.exe` 240 s with zero exceptions, real viewable windows, then the
  hard no-licence exit (`Warning` + `Exiting... No Valid Mastercam License found`); the launcher shows
  `No license found`. No main window — the licence gate fires first (M13).
- [x] Wine patches written for the two real bugs found (MSI registry view `0100`; service-logon token
  `0101`), both verified end-to-end on our build.
- [x] Licensing verdict measured and documented: `docs/LICENSING_VERDICT.md` — local licensing is
  blocked by the absent Wibu/HASP **kernel driver and device surface**; no Wine patch exists
  because no Wine call is on the failing path.

**Stopped here under the owner's rule** — the app can run, but cannot be licensed because Wine lacks
kernel-level APIs. Everything is documented in `README.md`, `FINDINGS.md` (M1–M13),
`docs/LICENSING_VERDICT.md` and the eight other `docs/*.md` evidence files, and reproducible from
`tools/`.

## Guest facts
- Windows 11 (kernel 10.0.26200), PowerShell 5.1, user `adsf`/`asdf`.
- **C: has only ~5.4 GiB free** — likely too little for a Mastercam install; VMReference-2 installs
  from a read-only media ISO (`state/mc_media.iso`) instead of staging the 2 GB SFX. Grow
  `/var/lib/libvirt/images/win11.qcow2` (libvirt-qemu-owned; `qemu-img` needs root) if needed.
- Recover the channel if it dies: Win key → type `cmd` → Enter → run
  `curl -s -o %TEMP%\m.bat http://192.168.122.1:8000/mc_svc.bat && %TEMP%\m.bat`.

## Environment facts
- Host: 22 cores, 30 GiB RAM, `win11` guest holds 8 GiB → ~15 GiB available. **Check `free` before
  any build/run**; `tools/build_wine.sh` has a 5000 MiB guard and caps `-j` to avail/1000.
- Disk: `/` (ext4) ≈33 GiB free; `/run/media/asdf/Windows` (ntfs3) ≈39 GiB free.
- Wine display: TigerVNC `:2` (port 5902, 1600x1000). Screenshot: `tools/host/shot.sh`, or
  `import -display :2 -window root out.png`.
- Guest: libvirt domain `win11`, user `adsf`/`asdf`, SPICE display (5900). Screenshot:
  `virsh screenshot win11 out.ppm`. Command channel: `tools/vm/vmcmd.sh '<powershell>' [timeout]`
  (host HTTP server `tools/vm/vmserv.py 8000 vmshare` must be running — currently is).
- The installer SFX is a WinRAR SFX whose own decoder handles RAR7; running it under Wine is a
  valid fallback if we ever need it, but `unrar` gives us the payload directly.

## Reproduce from scratch
```sh
source env.sh
tools/apply_patches.sh wine-11.18     # already applied implicitly by build_wine.sh's SRC tree? see note
tools/build_wine.sh --jobs 8          # configure --enable-archs=i386,x86_64 && make && make install
tools/mkprefix.sh                     # prefix, win10, fonts, prereqs, vendor installer
tools/run_mastercam.sh <tag>          # run on DISP=:2 with screenshots (to be written)
```

## Hard constraints / lessons
- **Memory**: never start a `make -j` or the app without checking `free` first (guest takes 8 GiB).
- **Temp must be disk-backed**: `TMPDIR=$MCW/state/tmp`.
- Subagents may hit `402 Insufficient account funds`; re-spawn with `model: "@default"`.
- Python's `SimpleHTTPRequestHandler` in `vmserv.py` **ignores HTTP Range**; never `curl -r` a large
  file from it (it streams the whole file).
- 7-Zip 26 reports `Unsupported Method` for this RAR7 payload; use the bundled `unrar`.

## Owner's decision rule (2026-10-03)
> If the app cannot run, or can run but cannot be licensed because Wine lacks kernel-level APIs,
> then say so, document it, and stop.

Current state against that rule: the **local** licensing paths (CodeMeter software container, dongle)
are blocked because CodeMeter's and Aladdin's **kernel drivers cannot load under Wine** and the
CodeMeter client reaches the service through a device/driver-gated channel (`Global\CmApiCallIn` is
never published). The only Wine-hostable path would be a **network licence server** (`hasplms` runs
under Wine and listens on 1947; the Mastercam client is plain TCP/UDP via `nethasp.ini`), which
cannot be tested here because **no licence, dongle or licence server exists in this environment at
all**. One non-kernel lead (advapi32 mandatory-label SDDL `S:(ML;;NW;;;LW)`) is being closed out
before this is declared architectural.

Consequences: finish the install + launch comparison with Windows, document exactly how far the app
gets and why licensing fails, and only then consider stopping.

## Workstreams / subagents
Every subagent MUST be spawned with `model: "@default"` — the default subagent model returns
`402 Insufficient account funds` (this is the sibling projects' documented workaround too).

| agent | owns | status |
|---|---|---|
| me (main) | build, prefix, run harness, patches, docs, guest GUI when needed | active |
| `VMReference-2` | install Mastercam in `win11`, capture the Windows reference | running |
| `DotnetProbe` | can a .NET desktop runtime (ideally 10.0 WindowsDesktop) run under our Wine? | running |
| `CodeMeterProbe` | CodeMeter / licensing runtime + service + `WIBUCM64.dll` under Wine | running |
| `McInstallWine` | run the product MSI under Wine and characterise blockers | running |
| `PayloadRecon-2` | static payload analysis → `docs/PAYLOAD_RECON.md` | done |
| `SeriesRecon-2` | 19-patch relevance map → `docs/PATCH_SERIES.md` | done |

Key risk register:
1. ~~**.NET 10 WPF ManagedUI**~~ — **RESOLVED (M6)**: the 10.0.12 WindowsDesktop runtime installs and
   WPF paints a real window (tier 2) under our patched Wine. .NET Framework 4.8 is a separate
   requirement and also works (`winetricks -q dotnet48`). Install **both** into the Mastercam prefix.
2. **CodeMeter** — `WIBUCM64.dll` is a static import of the launcher and loads once CodeMeter is on
   disk; the MSI needs a `CmWebAdmin.exe` stand-in (or a Wine SCM fix) to install; the service starts
   but its `Global\CmApiCallIn` API channel is never created and the kernel driver cannot load (M5).
   Licensing is therefore only Wine-hostable via HASP/NetHASP (`hasplms` runs and listens on 1947).
3. **MSI install** — the blocker is the InstallShield CA `ISLockPermissionsInstall`
   (`E_NOINTERFACE`, 1603 → rollback), **not** services and **not** msiexec's parser (M4).
4. **Graphics** — OpenGL + D3D9; WPF already renders via wined3d→GL (tier 2). No Vulkan/CEF, so no
   `dcomp`/WebView2 path is required for first light.
