# Hog PC 5.2.1.31 on Wine — working state

Updated: 2026-10-03 (session 1). **Read `FINDINGS.md` next** — it holds the measured evidence; this file
holds the position and how to resume.

## Goal
Make `Hog_PC_5.2.1.31.msi` (High End Systems / **ETC**, "Hog PC") install and **open like on Windows**
under a locally built, patched Wine 11.18, with the reference taken from the `win11` libvirt guest.
Owner's note: *additional functionality unlocks when connected to lighting hardware* (which itself
carries a licence dongle), the same selective-licensing pattern as the sibling products — so the base
application should run without any hardware or key.

## Deliverable
`/home/asdf/projects/hog-wine/` — the new working dir: every Wine patch used, any font/prefix/setup fix
as a reproducible script, the evidence, and the state docs.

## Layout
| path | what it is |
|---|---|
| `wine-11.18/` | Wine 11.18 source **with `patches/series/*` + `patches/local/*` applied** |
| `wine/wine-11.18/` | the build tree (created on first build) |
| `wine-install/` | `make install` output, **copied from the `eos-wine` project** (identical patch base) |
| `patches/series/` | `0001..0019` — AutoCAD-on-Wine (14) + Power BI-on-Wine (5), as the owner asks |
| `patches/local/` | **`0100` MSI class registry view, `0101` service-logon token, `0102` iphlpapi change notifications** — all three written in the sibling projects and reused here, as the owner suggested |
| `patches/sources/` | untouched copies of the two source series |
| `tools/` | build / prefix / run / probe / VM tooling, plus `tools/apitrace` (IAT API tracer) and `tools/relaydiff.py` |
| `vmshare/` | HTTP share with the Windows guest |
| `state/work/prefix` | the Wine prefix Hog PC is installed in |
| `state/tmp/` | disk-backed scratch |
| `docs/`, `logs/`, `evidence/` | evidence documents, run logs, screenshots |

**Payload**: `/run/media/asdf/Windows/hog-media/Hog_PC_5.2.1.31.msi` (NTFS, keeps `/` free).

## STATUS
- [x] Project skeleton; the 19-patch series + all three carried patches (`0100`, `0101`, `0102`) applied
      to **this project's own** `wine-11.18` (22 patches, all `OK`); `patches/README.md` documents every
      one with provenance; the tree is self-contained (no symlinks out; `wine-install/` is a real copy).
- [x] Payload reverse-engineered (M1/M2): WiX 3.14, **Intel (32-bit) package**, a **Qt 5.15.1 / QML
      application with QtWebEngine = Chromium 80.0.3987.163**, HASP licensing, USB drivers, features
      `DefaultFeature` / `Install_x64` / `Install_ARM64` / `VizFeature`.
- [x] Windows reference captured (`docs/VM_REFERENCE.md`): install rc 0, launcher `Hog Start` 792x338,
      **no licence/HASP/hardware prompt**, New Show → Console Startup → server/critical/desktop →
      `Hog PC - Primary Screen`; Windows renders Qt/QML in software (no GPU needed).
- [x] Hog PC installed under Wine (MSI **rc 0**, 577 MB) and **running**: launcher `Hog Start` 792x338,
      New Show dialog, show files created, `server-win32-golden` **listening on 6600**,
      `desktop-win32-golden`, console window `Hog PC - Primary Screen` rendering; **zero `err:` lines**.
- [x] Call-level parity measured (`docs/API_DIFF.md`): *start-up diverges nowhere that stops, blocks or
      corrupts it; show-store locking identical (1574 Windows vs 1584 Wine `LockFileEx`/`NtLockFile`,
      all success); no start-up-critical call missing.* The tracer itself had to be **ported to 32-bit**
      for this i386 app. Remaining divergences are cosmetic/degradation only.
- [x] Qt5/Chromium source index built (`docs/QT_CHROMIUM_SOURCE.md`): 820 Qt + 562 Chromium Win32 APIs
      mapped to Wine with `.spec`/body-level stub evidence (Qt 5.15.1 + Chromium 80.0.3987.163 sources
      on the NTFS partition) — the owner's "open source, trace instead of disassemble" instruction.
- [x] Behaviour comparison written: `docs/PARITY.md`.
- [x] Licensing verdict document (`docs/LICENSING_VERDICT.md`) — the app runs and needs **no** licence,
      same as Windows; nothing is blocked by kernel-level APIs.
- [x] **One real Wine bug found and patched**: `monitor-win32-golden.exe`'s `Processor` window was
      created correctly but **never painted** under Wine (Windows delivers `BeginPaint`+`EndPaint`;
      Wine delivered neither, with the window's whole client area in its update region and the app
      painting instantly when handed a `WM_PAINT`). Root cause: the monitor's message queue never
      drains, and Wine only synthesises `WM_PAINT` when the queue is otherwise empty, so the queued
      paint is never produced. Fix: `patches/local/0103-win32u-initial-client-paint.patch`
      (`dlls/win32u/window.c` `set_window_pos()` — force the first client paint on the hidden→visible
      transition, as Windows observably does); reasoning in `docs/INITIAL_PAINT_PATCH.md`, evidence in
      `docs/MONITOR_RENDER_RE.md`. Rebuild + verification in progress.

Known Wine fidelity gap observed (documented, not blocking): after a Hog window is **occluded and then
uncovered** it does not repaint (renders white) — Wine has no compositor/DWM (the same gap the sibling
Power BI project hit). On a clean run with nothing overlapping, the launcher and console render
correctly.

**Every window Hog PC shows on Windows now appears and renders under Wine** — launcher `Hog Start`,
`New Show` dialog, console `Hog PC - Primary Screen`, and the offline `Processor` — with **zero `err:`
lines** and a full-flow run that spawns all four processes on the patched build.

Deliverable complete: `patches/` (23 patches + `README.md` manifest), `docs/` (IMPORTS_RECON,
QT_CHROMIUM_SOURCE, VM_REFERENCE, API_DIFF, PARITY, MONITOR_RENDER_RE, INITIAL_PAINT_PATCH,
LICENSING_VERDICT), `FINDINGS.md` (M1–M5), `evidence/`, `logs/`.

## Environment facts
- Host: 22 cores, 30 GiB RAM; the `win11` guest holds 8 GiB. Check `free -m` before a build or a run
  (`tools/build_wine.sh` enforces a 5000 MiB guard; CPU may be saturated as long as memory is fine).
- Disk: `/` ≈34 GiB free, NTFS ≈33 GiB free — the guest's C: is usually the tighter one.
- Wine display: TigerVNC `:2` (1600x1000). The model has **no vision** → read screenshots with
  `tesseract` OCR and `xwininfo`/UI-Automation text, never by eye.
- Guest: libvirt domain `win11`, user `adsf`/`asdf`, PowerShell 5.1; command channel
  `tools/vm/vmcmd.sh '<powershell>'` (needs `tools/vm/vmserv.py 8000 vmshare` running — it is);
  keyboard `tools/vm/vmtype2.py`; screenshots `virsh screenshot win11 out.ppm` (wake with a key first).
- Never use `curl -r` against `tools/vm/vmserv.py` (it ignores HTTP `Range`).

## Method (the owner's loop)
Install under Wine → run on the VNC display → capture what the app asks Windows for and what it asks
Wine for → diff → patch Wine to match the expectation. Tooling: `tools/apitrace` (Windows x64/x86 IAT
tracer, runs in the guest *and* under Wine, driven by a `.cfg` pattern file) + `tools/relaydiff.py`
(normalises Wine `+relay` logs and tracer logs and diffs them). `WINEDEBUG=+relay` for Wine's own trace.
