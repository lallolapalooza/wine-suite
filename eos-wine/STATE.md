# ETC Eos Family v3.3.10.28 on Wine — working state

Updated: 2026-10-03 (session 1). **Read `FINDINGS.md` next** — it holds the measured evidence; this
file holds the position and how to resume.

## Goal
Make `ETC_EosFamily_v3.3.10.28.exe` install and **open like on Windows** under a locally built,
patched Wine 11.18, with the reference behaviour taken from the `win11` libvirt guest. The owner notes
the product **supports a licence key but should still have some functionality without one** — so the
unlicensed offline editor is the target.
Wine patches start from the **AutoCAD-on-Wine series (14) + Power BI-on-Wine series (5)** — the owner's
instruction — **plus the two patches written in the mastercam-wine project** (`0100` MSI class registry
view, `0101` service-logon token), which are proven Wine bug fixes and are applied here too.

## Deliverable
`/home/asdf/projects/eos-wine/` — the new working dir. It must end up containing every Wine patch used,
any font/prefix/setup fix as a reproducible script, the evidence (logs, screenshots) and state docs.

## Layout
| path | what it is |
|---|---|
| `wine-11.18/` | Wine 11.18 source **with `patches/series/*` + `patches/local/*` applied** |
| `wine/wine-11.18/` | the build tree (not created yet — see "Wine build" below) |
| `wine-install/` | `make install` output, **copied from `mastercam-wine`** because the patch base is identical (19 + 0100 + 0101); `wine --version` → `wine-11.18` |
| `patches/series/` | `0001..0019` — AutoCAD-on-Wine (14) + Power BI-on-Wine (5) |
| `patches/local/` | `0100-msi-class-registry-view.patch`, `0101-services-service-logon-token.patch` (both verified in the mastercam project) |
| `patches/sources/` | untouched copies of the two source series |
| `tools/` | build / prefix / run / probe / VM tooling (adapted from the mastercam project) |
| `vmshare/` | HTTP share with the Windows guest |
| `state/work/prefix` | the Wine prefix Eos is installed in |
| `state/tmp/` | disk-backed scratch |
| `logs/`, `docs/`, `evidence/` | build/run logs, evidence documents |

**Payload**: `/run/media/asdf/Windows/eos-media` (NTFS, keeps `/` free) — the expanded zip is
`ETC_EosFamily_v3.3.10.28.exe` (NSIS, PE32 i386) and its inner pieces in
`msi/$PLUGINSDIR/`: `ETC_EosFamily_v3.3.10.28.msi` (306 MB, the product), `ETC_Augment3d_v1.4.10.3.msi`
(200 MB, the 3D visualiser), `haspdinst.exe`, `VC_redist.{x64,x86}.exe`.

## STATUS
- [x] Project skeleton; the 19-patch series + the two carried patches (`0100`, `0101`) applied to
      `wine-11.18`; our own Wine build is running.
- [x] Payload expanded and reverse-engineered (see `FINDINGS.md` M1/M2): the product is a **WiX 3.11,
      x64-only MSI** installing a **Qt5** application; main binary `Eos.exe`; features `Shell`,
      `ShellOffline`, `DefaultFeature`; install root `C:\Program Files\ETC\EosFamily\v3`; Sentinel HASP
      licensing (optional).
- [x] Windows reference captured (`docs/VM_REFERENCE.md`): no licence key needed, editor reached via
      `ETC_LaunchOffline.exe` → *Offline* → `Eos.exe`; Windows' start-up transient self-heals in 10.1 s;
      Windows has the `slpd` SLP service.
- [x] Eos installed and **running** under Wine: MSI exit 0, editor window `Eos : 1` (1600x1000) with a
      rendering UI (`evidence/eos_editor_wine.png`).
- [x] Root cause of the ~48 s extra start-up: the SLP path (`docs/API_DIFF.md`, `docs/EOS_STALL_RE.md`).
      Fixed reproducibly: ETC SLP component + `pkexec sysctl -w net.ipv4.ip_unprivileged_port_start=0`
      (`docs/SLP_PORT_FIX.md`) → **0 `SLPReg()` failures, `CreateComponent handle=80000000` (Windows'
      value), stall 18.67 s vs Windows 10.10 s** (M7).
- [x] Wine patch written for the one genuine stub on the path:
      `patches/local/0102-iphlpapi-notify-interface-changes.patch` (`docs/IPHLPAPI_NOTIFY.md`).
- [ ] Rebuild with `0102` and re-verify.
- [x] Licensing verdict: `docs/LICENSING_VERDICT.md` — the app runs and needs **no** licence, same as
      Windows; the owner's stop-rule does not trigger.

## Wine build
`wine-install/` began as a copy of the mastercam project's identical build; `tools/build_wine.sh
--jobs 6` then built this project's own tree with the full patch set (necessary because `0102` changes a
native DLL). `/` had ~41 GiB free, so the build fits comfortably.

## Method: Wine-vs-Windows API diff (the owner's loop)
When the app misbehaves under Wine: **capture what it asks Windows for, capture the same under Wine,
diff, patch Wine to match the expectation.** Tooling already in the tree:

| tool | what it does |
|---|---|
| `tools/apitrace/build/{apihook.dll,apitrace.exe}` | Windows x64 **IAT-hooking API tracer**; runs in the `win11` guest *and* under Wine. Patterns come from a `.cfg` file (grammar in `tools/apitrace/test.cfg`: `[~]dll!func[@argc[/argwidths][:retwidth]]`); see `tools/apitrace/notes/`. |
| `tools/relaydiff.py` | normalises Wine `WINEDEBUG=+relay` logs and the tracer's own log grammar, then diffs them. Subcommands include `wine-log`, `wine-log --errors`, `--tail N`, `--modules a,b`, and a diff mode. |
| `WINEDEBUG=+relay` | Wine's own call trace (heavy — scope it with `WINEDEBUG=+relay:<module>` style filters or `--modules`). |

Workstreams use it in parallel: `EosApiDiff` owns the call-level diff, `EosDeadlockRE` owns the
thread-stack/lock analysis of the same hang, `EosImportsRecon` produced the static import map
(`docs/IMPORTS_RECON.md`), `EosVMReference` owns the Windows guest install/reference.

## Environment facts
- Host: 22 cores, 30 GiB RAM; the `win11` guest holds 8 GiB. Check `free -m` before a build or a run
  (`tools/build_wine.sh` enforces a 5000 MiB guard). Disk: `/` ≈49 GiB free, NTFS ≈36 GiB free.
- Wine display: TigerVNC `:2` (1600x1000). The model has **no vision** → read screenshots with
  `tesseract` OCR and `xwininfo`/UI-Automation text, never by eye.
- Guest: libvirt domain `win11`, user `adsf`/`asdf`, PowerShell 5.1. Command channel:
  `tools/vm/vmcmd.sh '<powershell>'`; keyboard injection `tools/vm/vmtype2.py`/`vmkeys.py`;
  screenshots `virsh screenshot win11 out.ppm` (send a key first if the frame is black).
- Never use `curl -r` against `tools/vm/vmserv.py` (it ignores HTTP `Range` and streams the whole file).
