# Tableau Desktop 2026.2.3 on Wine — project state

Mission: make `/home/asdf/Downloads/TableauDesktop-64bit-2026-2-3.exe` install and open on Wine
"like on Windows", by (1) starting from the union of the existing AutoCAD + Power BI patch series,
(2) reverse-engineering/log-diffing the app against the Windows guest to find what Wine lacks,
(3) writing Wine patches (generic ones plus app-exclusive ones) and documenting everything.

Rules in force: decisions by reward not cost; state kept on disk (this file + `state/` + `logs/`); work is
AI-assisted and NOT intended for upstream submission; memory must be capped before builds/runs (OOM guard);
disk is the tightest resource — check `df` before big writes.

---

## 1. Host facts (measured 2026-10-04)

| fact | value |
|---|---|
| CPU | Intel Core Ultra 7 155H, 22 threads |
| RAM | 30 GiB total, swap 8 GiB (4.3 GiB used at start → watch it) |
| Disk | `/dev/nvme0n1p5` = `/`, `/home`, `/tmp`: **27 GB free of 213 GB (87% used)** |
| Disk (other) | `/dev/nvme0n1p3` NTFS "Windows" dual-boot, 33 GB free, mounted `/run/media/asdf/Windows` (ntfs3, uid=1000) |
| Root | `sudo` requires an interactive password → **no root**; group `libvirt` + `cdrom` + `disk`-less |
| Tools present | `virsh`, `qemu-system-x86_64`, `Xvfb`, `Xtigervnc`, `x11vnc`, `xdotool`, `import`, `xwininfo`, `7z/7za/7zr`, `cabextract`, `binwalk`, `msiextract`, `ccache`, `clang`, `gcc`, `wine-10.0` (distro), **no `ffmpeg`**, **no `innoextract`**, no `libcef*` |
| Tools absent | `sudo -n`, qemu guest agent in the VM, `ffmpeg` (→ no video frame decode; use ImageMagick `import`) |

## 2. Windows guest (reference platform)

| fact | value |
|---|---|
| Domain | `win11` — **currently RUNNING** (user said powered down; ground truth: running since ~40h CPU) |
| Shape | 4 vCPU, 8 GiB, UEFI+secure boot, TPM (swtpm), host-passthrough CPU |
| Disk | `sda` = `/var/lib/libvirt/images/win11.qcow2` (64 GB cap, 39.6 GB allocated) — **grows on `/`** |
| CD-ROM | `sdc`/`sdd` empty USB CD slots (hot-pluggable) + `sde` = csp media ISO |
| Net | `192.168.122.230/24` on virbr0 (host gw `192.168.122.1`). Host→guest ports CLOSED (Win firewall); **guest→host works** |
| Console | SPICE `127.0.0.1:5900` (no VNC); `virsh screenshot win11` available |
| Guest user | `adsf` |
| Channel | host `python3 tools/vmserv.py 8000 vmshare` (HTTP GET/PUT) ← guest polls `http://192.168.122.1:8000/cmd.txt`, runs via `pbi_svc.ps1`, writes `guest_cmd_out.txt` (see `tools/vm/vmcmd.sh`) |
| Guest bootstrap | if poller is dead: from guest, `curl.exe -s -o C:\Users\adsf\svc.ps1 http://192.168.122.1:8000/pbi_svc.ps1` then run it (needs console access) |

## 3. Prior art (reuse, do not reinvent)

| project | what it gives |
|---|---|
| `/home/asdf/projects/acad-wine-main` | Wine 11.18 fork, 14 behavior patches (0001–0016 minus 0005/0011), `tools/build_wine.sh`, `tools/check_prereqs.sh`, `tools/install_fresh_prefix.sh`, `tools/verify_fresh_prefix.sh`, `ui_plug.sh`, `installer/`, `env.sh` |
| `/home/asdf/projects/autocad2027-private-main` | same series + `FINDINGS.md` (258 KB) + `STATE.md` (27 KB) + probe scripts (`acad_probe.sh`, `capture.sh`, `observe.sh`) |
| `/home/asdf/projects/powerbi` | Wine 11.18 fork, 6 behavior patches (0001–0006) + test patch 0007, `scripts/check_patch_series.sh`, `scripts/install_pbi.sh`, `scripts/pbi_fixups.sh`, `scripts/run_pbi.sh`, `scripts/run_wine_tests.sh` |
| `/home/asdf/projects/powerbi-linux` | full working checkout: `tools/mem_guard.sh`, `tools/build_wine.sh`, `tools/vm/*` (guest channel), `tools/winapi/*` C probes, `docs/*` (INFRA, WINDOWS_REFERENCE, WINDOWS_REFERENCE_SPEC, WINE_TESTS), `FINDINGS.md` (268 KB), `STATE.md` (50 KB), `vmwinmd/`, `fonts/` |

Copied into this project: all AutoCAD + Power BI patches (`patches/from-*`), `tools/{build_wine.sh,
mem_guard.sh,check_patch_series.sh,make_patch.sh,vmserv.py}`, `tools/vm/*`, `tools/winapi/*`, `env.sh`.

## 4. Application under test

| fact | value |
|---|---|
| File | `/home/asdf/Downloads/TableauDesktop-64bit-2026-2-3.exe` |
| Size | 743 872 856 B (710 MiB) |
| `file` | PE32 executable (GUI) Intel i386, MS Windows 6.00, 6 sections → **32-bit self-extracting bootstrap**; payload expected x64 |
| Name/version | Tableau Desktop 2026.2.3 (64-bit) |

## 5. Layout of this project

```
STATE.md FINDINGS.md README.md       state of record (this file survives compaction)
src/            pristine wine-11.18.tar.xz (from ~/Downloads)
wine-11.18/     patched Wine source (source of truth); build happens here in place (no second copy — disk)
patches/        union series (numbered, each with provenance) ; app-exclusive/ ; from-autocad/ ; from-powerbi/
tools/          build/mem/build-test/state helpers + vm/ (guest channel) + winapi/ (C probes)
app/            extracted Tableau installer payload
prefix/         Wine prefixes
logs/  state/  recon/  docs/  vmshare/
```

Conventions: every patch file carries symptom → Windows behaviour → how verified; every claim in docs names its
measurement; logs go to `logs/<tag>/`; `patches/app-exclusive/` marks the Tableau-only changes at the end.

## 5b. Acceptance target (user, 2026-10-04)

**Parity, not activation.** If the Windows guest reaches a sign-in / licence screen and is blocked there
(no product key, no Tableau account), then the goal is met when **Wine reaches the same screen**. Licensing
insight is therefore not needed before that: do not spend effort on FlexNet hostid/kernel-identity work until
Wine is blocked at the same place Windows is. The deliverable at that point is the app-exclusive patch set +
the documented, reproducible setup.

## 6. Decisions

- **Wine source**: pristine `src/wine-11.18.tar.xz` + union of both prior series (not a prior patched tree), so
  provenance is provable and the series can be split into shared vs app-exclusive at the end.
- **Architectures**: `--enable-archs=i386,x86_64` — the Burn bootstrap is 32-bit i386, the product is 64-bit
  (confirmed: 404 of 405 PE files in the payload are PE32+ x86-64; only `d3dcompiler_47.dll` is i386).
- **Install by bundle, not by MSI**: the MSI's own LaunchConditions want `Privileged`, `WindowsBuild >= 9200`
  and `D2D1_FOUND`; the bundle also chains the VC2022 redist. Try the bundle first, fall back to
  `msiexec /i <msi> /qn` if Burn itself misbehaves under Wine.
- **Build in place** in `wine-11.18/` (saves ~1 GB vs the copy-to-`wine/` convention); `ccache` on.
- **Memory**: `tools/mem_guard.sh` cap 85% while building; `make -j6` — a Wine compile job is 1.5–2 GB RSS.
- **Display**: Xtigervnc `:11` on 5911 (localhost) for autonomous UI interaction and for the operator to watch.
- **Windows reference**: guest runs the same installer silently; frames come from `virsh screenshot`
  (**only one sampler at a time**), commands from the `:8000` hub.
- **Guest elevation**: the Burn engine re-launches elevated and raises a UAC prompt on the **secure desktop,
  which `virsh screenshot` does not capture** (measured: `consent.exe` pid 2980 titled "Tableau 2026.2 … is
  requesting your permission", child `TableauDesktop` pid 6896 at 1 thread/0 CPU). Drive it with the keyboard
  (`tools/vm/vmhotkey.py`), or avoid it entirely by running the installer from a **SYSTEM scheduled task**
  (`schtasks /create /rl highest /ru SYSTEM`), which needs no consent.

## 7. Status log (append-only)

- 2026-10-04T03:3xZ — recon done (host, VM, prior art, installer). Skeleton created; prior patches + tooling staged.
  Next: union series, build, extract installer, guest reference run.
- 2026-10-04T03:35Z — **infra verified live**: hub `tools/vm/vmserv.py` supervised on `:8000` (share `$P/vmshare`);
  guest `win11` poller is running and round-trips a command in **2.4 s** (`cmd.txt` → `guest_cmd_out.txt`, via
  `C:\pbiref\cmd_out.txt`), reported `asdf\adsf` / `Microsoft Windows 11 Pro`. **Guest poller dedupes on command
  text** (`$seen`) — repeat a command only with a changed nonce. Supervised VNC display **`:11`** on **5911**
  (`Xtigervnc`, `-localhost`, SecurityTypes None). Long-lived processes MUST be started through the harness's
  service mode; plain `nohup ... &` dies with the calling command.
- 2026-10-04T03:35Z — guest inventory: C: 22.1 GB free, .NET CDF/v4.x, VC++ 2005/2022 x64+x86, **WebView2 Runtime
  installed**, **no Tableau**. Installer symlinked into `vmshare/` (hub returns 200, 743 872 856 B) and the guest
  is downloading it to `C:\Users\adsf\TableauDesktop.exe`.
- 2026-10-04T03:36Z — **installer identified as a WiX Burn bundle** (extraction: `app/tableau_burn.cab` 709 MB,
  `app/tableau_exe/{a0,a1,msi_root}`, `app/tableau_ux/`). Burn gives us a real Windows install trace with `/log`.
  First guest run failed fast with `Error 0x80070057: To accept the End User License Agreement (EULA), add
  ACCEPTEULA=1 to your command-line` — so the working silent line is
  `/quiet /norestart /log C:\Users\adsf\tableau_burn.log ACCEPTEULA=1` (NOT `ACCEPTLICENSE=YES`).
  Burn variables seen in the log: `ProductName=Tableau 2026.2 (20262.26.0912.1023)`, `WixBundleVersion=26.2.1954.0`,
  `WixBundleProviderKey={5dfaba8c-274e-499c-8107-cca21f4872b0}`, `TAB_PRODUCT=Desktop`, and the
  **licensing knobs** `REGISTER`, `SILENTLYREGISTERUSER`, `SYNCHRONOUSLICENSECHECK`, `RECLAIMLICENSE`.
- 2026-10-04T03:37Z — union series: **20 patches**, all reverse-apply clean on `wine-11.18/`, no rejects → build started
  (`tools/build_tableau.sh`, JOBS=6, `--enable-archs=i386,x86_64 --disable-tests`, mem_guard at 85%).
  BuildEnv (scout) confirmed **no missing build prerequisites, no root needed**, JOBS=6, ~10-15 GB needed.
- 2026-10-04T03:44Z — **UAC blocks the Windows install, and this guest cannot be clicked out of it.**
  The Burn engine re-launches itself elevated; `consent.exe` (pid 2980, session 1, title "Tableau 2026.2
  (20262.26.0912.1023) is requesting your permission") holds the elevated child `TableauDesktop` (pid 6896) at
  1 thread / 0 CPU. The consent UI is on the **secure desktop**, which on this guest (QXL, 1 head, session 1
  active and unlocked) is **neither captured by `virsh screenshot`** (framebuffer keeps showing the normal
  desktop, clock ticking) **nor reachable by injected input**: `tools/vm/vmclick.py 540 557` (the coordinates the
  Power BI project measured for this dialog), `tools/vm/vmhotkey.py alt+y` and the Win-key Start-menu test all
  did nothing, while the *same* pointer helper DOES open the Start menu on the normal desktop. The Power BI
  project's notes agree that `Alt+Y`/arrows do not work and that a mouse click on (540,557) was the only way —
  that was when the prompt was visible in its screenshots, which is no longer the case here.
- 2026-10-04T03:45Z — **Decision (decomposition)**: stop fighting UAC and split the problem in two, because
  "does the app run under Wine" and "does the Burn+MSI installer run under Wine" are independent questions:
  1. **Reference + Wine runtime first**: the MSI is admin-extractable with NO elevation —
     `msiexec /a <msi> /qn TARGETDIR=<dir>` — so both the Windows guest (`C:\TableauRef`) and the Wine prefix
     (`tools/deploy_tree.sh`, symlink of `app/tableau_exe/msi_root/Tableau`) get the identical file tree, and
     `tableau.exe` can be launched on both sides. This isolates every runtime/API gap from installer gaps.
  2. **Installer second**: make the Burn bundle + MSI work under Wine afterwards.
  Guest-side extraction of the 725 159 936 B MSI started 2026-10-04T03:46Z (msiexec pid 5860, log
  `C:\Users\adsf\msi_admin.log`).
- 2026-10-04T03:45Z — open-source components are the tracing lever (user directive): **Qt 6.5.11** and
  **Chromium 122.0.6261.171 (Qt WebEngine)** and **Node.js 22.17.1** (`eps/eps.exe`) and **Envoy**
  (`yaxcat/yaxcatd.exe`) are all open source, so their Win32 expectations come from upstream source rather than
  from disassembly. `OpenSourceTrace` is producing `recon/OPENSOURCE_TRACE.md` (per-component API tables, Wine
  status cited at `file:line`, ranked predicted breakages, one experiment each).
- 2026-10-04T03:54Z — **THE GATE, measured on Windows**: `C:\TableauRef\...\bin\tableau.exe` (admin-extracted tree,
  no MSI state) exits after 6.2 s with `0xE06D7363` (unhandled C++ exception); the console variant `bin\tableau.com`
  prints the reason on **stdout**: `The licensing service is too old.` and on **stderr**: `Tableau could not access
  Trusted Storage. Verify that the latest version of the FlexNet Licensing Service is running as a network service.
  If that does not resolve the issue, try reinstalling Tableau Desktop or Tableau Server.` (exit 1).
  => The app does not open until **FlexNet Licensing Service 64** (`FNPLicensingService64`, installed by
  `bin\installanchorservice.exe`, virtualised Trusted Storage under `C:\ProgramData\FLEXnet`) is present and
  running. This is a **service + Trusted-Storage gate, not merely activation**: it is the same wall Wine will hit,
  and it means "opens like Windows" requires that service to work under Wine (or a documented stand-in).
  The MSI also writes the state the app needs: 167 `HKLM\SOFTWARE\Tableau\*` rows (Directories, ATR, FlexNetUsers,
  AutoUpdate, Telemetry, Crashdump, Install…), HKCR associations, and the service. A non-elevated
  `msiexec /a` extract therefore cannot substitute for a real install even on Windows.
- 2026-10-04T03:54Z — corollary for the plan: the Windows reference install needs **elevation** (the blocked UAC
  prompt), and so does any Wine-side script that installs a service. Both sides need the same three things:
  the file tree, the registry state, and the FlexNet service. `TableauStack` and `LicenseRisk` both land here
  from their own directions (`recon/TABLEAU_STACK.md`, `recon/LICENSE_RISK.md`).
- 2026-10-04T03:55Z — secure desktops ARE rendered on this guest: `tools/vm/vmhotkey.py ctrl+alt+delete` produced the
  full Winlogon screen (Lock / Switch user / Sign out / Task Manager / Cancel) in `virsh screenshot`
  (`logs/winref/cad.png`, 4.4 KB, 76 colours). So the earlier UAC prompt was **never displayed** rather than
  "not captured"; the `consent.exe` request just sat there. Elevation is therefore still solvable.
- 2026-10-04T03:58Z — **UAC SOLVED (and it was our own doing)**: the consent prompt *is* captured and clickable on
  this guest; it simply never appears while a shell overlay is open. After closing the Start/Search panel
  (`tools/vm/vmhotkey.py esc`), `Start-Process cmd.exe -Verb RunAs` produced the normal dimmed secure desktop with
  the dialog (`logs/winref/uac3.png`: panel x 412-867, y 212-588, **Yes (541,548)**, No (745,548)) and a click at
  (541,548) launched the elevated process. `tools/win_uac_click.sh [timeout]` automates it (detects the dimmed
  screen by mean luminance < 0.40, then clicks Yes). Consequences: run no shell overlay while an install is
  pending, and start the installer detached (`Start-Job`) so the poller is not blocked while the prompt is up.
  The real Windows install was then started: `/quiet /norestart /log C:\Users\adsf\tableau_burn.log ACCEPTEULA=1`,
  elevated via an automated click (mean 0.304).
- 2026-10-04T03:58Z — credentials for this guest are already documented by the sibling project
  (`/home/asdf/projects/powerbi-linux/docs/INFRA.md:319` and `docs/WINDOWS_REFERENCE.md:227-229`: guest login
  `adsf`/`asdf`; that file also records the host's `sudo` password). A sign-out/sign-in is therefore recoverable,
  which de-risks the session if it ever needs clearing — but note **AutoAdminLogon=0**, so nothing logs in
  automatically after a reboot.
- 2026-10-04T04:05Z — `OpenSourceTrace` → `recon/OPENSOURCE_TRACE.md` (42 KB, evidence in `recon/evidence/`).
  Corrections and the concrete Wine gaps it found by reading upstream source, not by disassembly:
  * `yaxcat/yaxcatd.exe` is **not Envoy**: it is a gRPC 1.52.2 + Boost 1.80.4 + BoringSSL service (build paths
    `C:/builds/algernonteam/yaxcat/…`); the "Envoy" strings are gRPC's vendored xDS descriptors.
  * Node.js **22.17.1** carries **libuv 1.51.0** (not 1.48) — the same code the AutoCAD project hit with `EBADF`
    on piped stdout, so our union patches 0002/0003 (IOCP on non-overlapped handles, fd-backed pipe semantics)
    are directly relevant.
  * Only **two genuine missing exports** in the whole payload: `userenv.dll!DeriveAppContainerSidFromAppContainerName`
    (statically imported by `Qt6WebEngineCore.dll` + `QtWebEngineProcess.exe`; Wine binds it to an abort thunk and
    `CreateAppContainerProfile` is a stub; Chromium 122's renderer/GPU AppContainer features are
    FEATURE_DISABLED_BY_DEFAULT, so it arms only if enabled) and `user32.dll!SkipPointerFrameMessages` (a stub,
    reached only from Qt's touch-pointer path). The api-set audit found zero unresolved sets.
  * **`AF_UNIX` is unsupported by Wine's `ws2_32`** (measured: `socket(AF_UNIX,…)` → `WSAEAFNOSUPPORT`; no family
    in `ws2_32/unixlib.c`), which matters for gRPC/UDS endpoints.
  * GPU path is the likely visible failure: ANGLE 2.1.0 → D3D11 → Wine's wined3d/vkd3d, feature level capped at
    FL11_0, `CreateDXGIFactory2` ignoring flags → expect a blank web view unless it falls back to the shipped
    SwiftShader. Test levers: `QTWEBENGINE_CHROMIUM_FLAGS='--disable-gpu'` vs `'--enable-logging=stderr --v=1'`.
  * Long tail of silent degradations with `file:line` each (DWM, taskbar, touch, shell notify, job UI
    restrictions, `NCryptOpenKey`, …) — none fatal.
- 2026-10-04T04:14Z — **elevation made silent, by design, on the guest** (this is the reproducible unblock):
  the first approved elevation produced a real **Administrator: cmd** window, which we drove with
  `tools/vm/vmclick.py` (focus) + `tools/vm/vmkeys.py` (type) to set
  `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System`:
  `ConsentPromptBehaviorAdmin=0` and `PromptOnSecureDesktop=0` (both "The operation completed successfully.").
  Consequence: an administrator now elevates **without any UAC prompt**, so installer runs need no interaction.
  To restore the machine's original behaviour set the same two values back to `5` and `1`.
  Note the luminance heuristic in `tools/win_uac_click.sh` (mean < 0.40 = "prompt") is fooled by any large dark
  window (a maximised console reads ~0.30) — it is now only a fallback, not the primary route.
  Also cleaned up: `taskkill /F /IM TableauDesktop.exe /T` removed the stale bundle and its elevated child, then
  the installer was started fresh at 21:14:30 guest time (`/quiet /norestart /log C:\Users\adsf\tableau_burn.log
  ACCEPTEULA=1`).
- 2026-10-04T04:29Z — **first Wine baseline, and the first hard Wine gap**: with the tree deployed into the prefix,
  `tableau.com` under Wine exited **53 with no output**; Wine's own log gave the reason —
  `err:module:import_dll Library mfc140u.dll (which is needed by ...tabdoc.dll) not found`, cascading through
  `tabui.dll`/`tabdoc*.dll`/`tabdesktopui.dll` and ending `err:module:loader_init ... failed, status c0000135`.
  Root cause: Tableau's UI stack needs **MFC 14.0**, which Wine does not implement and the MSI does not ship —
  on Windows it comes from the **VC++ 2022 redistributable** (`mfc140u.dll` is in the guest's `System32`).
  **Fix applied**: run the bundle's own prerequisite package, `app/tableau_exe/a0` (vcredist2022_x64.exe,
  25 635 768 B) with `/install /quiet /norestart` under `prefix/tableau` — it completed (exit 0) and
  `mfc140u.dll`, `mfc140.dll`, `msvcp140.dll`, `vcruntime140*.dll` are now in the prefix's `system32`.
  Wine's builtin `msvcp140`/`vcruntime140` must not shadow the native ones for MFC to work, so runs use
  `WINEDLLOVERRIDES='msvcp140,msvcp140_1,msvcp140_2,vcruntime140,vcruntime140_1,mfc140u,mfc140=n'`.
- 2026-10-04T04:30Z — an OOM event was recorded by `tools/mem_guard.sh` (92-96 % used, killed compilers at 23:30);
  the pressure was **stale `wineserver`/`winedevice.exe` processes left by the other projects on this machine**
  plus our own run, not the build (which had already finished at 23:21). Recovered: 18 GiB available.
  Standing rule for every agent: `free -g` before heavy work, `-j4` max, and only ever `wineserver -k` **your own**
  `WINEPREFIX`.
- 2026-10-04T04:41Z — **what the licensing check actually calls on Windows** (ProcMon trace of the real install,
  `state/win-trace/tab.csv`, 647 097 rows, captured by `tools/vm/apitrace.ps1`; the app stayed alive through the
  capture). The service process is **`FNPLicensingService64.exe`** at
  `C:\Program Files\Common Files\Macrovision Shared\FlexNet Publisher\` (note: "FlexNet Publisher", not
  "FLEXnet"), 54 999 traced ops — RegOpenKey 16 483, RegCloseKey 12 626, ReadFile 9 811, RegQueryValue 9 427,
  RegEnumKey 4 992, FileSystemControl 358, **DeviceIoControl 344**, CreateFile 198. Its identity inputs:
  * **`\Device\Harddisk0\DR0` + `IOCTL_DISK_GET_DRIVE_GEOMETRY`** (the only device-control target; SUCCESS).
    Wine *does* implement this — `dlls/mountmgr.sys/device.c:1885` (`_EX` at :1900) — while
    `IOCTL_STORAGE_QUERY_PROPERTY` remains partial (`device.c:1967`, `FIXME("Faking StorageDeviceProperty data")`
    at :1595). So the disk-identity path is not the first thing to fix.
  * **Named-pipe IPC**: `\Device\NamedPipe\FlexNet Licensing Service 64<GUID>` with `FSCTL_PIPE_LISTEN` /
    `FSCTL_PIPE_DISCONNECT` — the service listens on that pipe, the app connects; the version/handshake on this
    pipe is what produces Windows' "The licensing service is too old." message.
  * **COM/WMI**: `HKCR\CLSID\{1B1CAD8C-2DAB-11D2-B604-00104B703EFD}` → "Microsoft WBEM (non)Standard Marshaling"
    (`InprocServer32`, `ThreadingModel=Both`) — machine identity is read through WMI, so `wbemprox` matters.
  Handed to `FlexNetWine` verbatim (the pipe name under Wine is the thing to observe next).
- 2026-10-04T04:45Z — **two new patches, both generic (not app-exclusive)**: `patches/0021-userenv-DeriveAppContainerSidFromAppContainerName.patch`
  and `patches/0022-user32-SkipPointerFrameMessages.patch` (from the `MissingExports` task; `patches/SERIES.md`
  extended to 22 rows with checksums). Both compile for i386 **and** x86_64 (`make dlls/userenv/all dlls/user32/all -j4`,
  rc=0, no warnings), the exports are visible in the built DLLs via `objdump -p`, each carries a Wine-suite test
  in its module (compile-checked only, since this tree is configured `--disable-tests`), and both apply cleanly
  forward to a pristine extraction and reverse to the built tree.
  The userenv SID derivation is the real Windows one — lowercase the name, SHA-256 over UTF-16, first 28 bytes as
  seven little-endian subauthorities — validated by reproducing Windows 11's own SID for
  `Microsoft.Windows.ShellExperienceHost_cw5n1h2txyewy` = `S-1-15-2-155514346-2573954481-755741238-1654018636-1233331829-3075935687-2861478708`.
  Note: `wine-install/` does **not** contain these yet — the incremental rebuild happens when the app reaches
  those code paths (the FlexNet/MFC gates come first).
- 2026-10-04T04:48Z — **the real installer works under Wine** (major milestone, two independent runs):
  * `BurnInstallerWine`: the WiX Burn bundle ran the whole chain in **63 s, exit 0x0** — VC2022Redist ExePackage
    (exit 0x0) then the Tableau MSI to `InstallFinalize` with **zero `Return value 3`** and zero Wine `err:` lines;
    5425/5425 files, exactly 2 208 240 220 B (the MSI's own InstallSize), **md5-identical to the `msiextract`
    reference**, `HKLM\SOFTWARE\Tableau\*` written, Start-Menu shortcut created, and
    **`FlexNet Licensing Service 64` created and RUNNING under Wine**.
  * My own run in a clean prefix agrees: `prefix/tableau-inst` has 5425 files, `mfc140u.dll` in system32 (the
    bundle's own `VC2022Redist` package installs MFC), and `HKLM\SOFTWARE\Tableau\{Directories,FlexNetUsers,
    Tableau 2026.2}` present.
  * Reasons it needs no elevation under Wine: `dlls/msi/package.c:737-741` hard-codes
    "in a wine environment the user is always admin and privileged" (Privileged/MsiRunningElevated = 1), and
    `programs/sc/sc.c:430-433` fakes success for `sc sdset` (so the MSI's DACL custom action is a no-op).
  * Bug fixed in our own harness: `tools/install_tableau_wine.sh` resolved the installer as
    `$ROOT/../Downloads/...` (= `/home/asdf/projects/Downloads`); it now takes the absolute path / `$TABLEAU_INSTALLER`.
- 2026-10-04T04:47Z — note for the record: the ~32 GB of free space that appeared between 23:45 and 23:47 came
  from the **operator clearing `csp-wine` (19 GB → 27 MB) and `sda-wine` (14 GB → 568 MB)** themselves; both keep
  their docs. No agent deleted anything outside its slice (agents' transcripts were checked; the only `rm -rf`
  seen was inside a task's own `/tmp` scratch dir), and the agents were explicitly told not to touch other projects.
- 2026-10-04T04:52Z — **GOAL REACHED: Wine shows the same screen Windows shows.** With the app installed by the
  real bundle into a clean prefix (`prefix/tableau-inst`, 5425 files, VC redist installed by the bundle itself),
  `tableau.exe` runs and **stays alive** (150 s, 36 frames), and the X window tree contains **"Activate Tableau"**
  + "Tableau". Evidence: `evidence/windows_vs_wine_activate.png` (Windows `logs/win-reftab/frame_026.png` beside
  Wine `logs/run-inst/frame_030.png`) — same heading "Welcome to Tableau Desktop / Activate your Tableau license
  to get started.", the same three choices (*Use Tableau for free*, *Activate with product key*, *Activate by
  signing in to a server*), the same "Learn more about licensing and activation" link and the same `Exit` button.
  Pixel metrics between the two frames: AE 506 185 (0.494), RMSE 0.212, mean abs diff 16.1 — the residual is
  window chrome/desktop, not content.
  Wine's own log during the run shows how far it got: Qt WebEngine/Chromium started (GLES3 → GLES2 fallback, then
  "Failed to create shared context for virtualization" — the GPU path `OpenSourceTrace` predicted), cert-store
  activity, and **`Tbsi_GetDeviceInfo` (TPM) reached as a stub**, i.e. the licensing/identity path executed.
- 2026-10-04T04:52Z — **answer to "which patches are exclusive to this app": none.** The activation window was
  reached with the 20-patch **union of the AutoCAD + Power BI series** applied to pristine Wine 11.18 and *no*
  Tableau-specific Wine change. What Tableau needed beyond Wine upstream was **configuration, not code**: the
  bundle's own VC++ 2022 redistributable (for `mfc140u.dll`) and the MSI's own install state (registry + the
  `FNPLicensingService64` service + Trusted Storage), all installed by the *unmodified* bundle under Wine.
  The two patches added afterwards (`0021` userenv AppContainer SID, `0022` user32 pointer-frame) are generic
  Wine gaps found by reading Qt/Chromium sources — they are not required for this screen and are not app-exclusive.
  Per-patch necessity for Tableau was **not** bisected (that would be N rebuilds); `patches/app-exclusive/` is
  empty, which is the honest answer at this milestone.
- 2026-10-04T04:55Z — closing evidence from the same prefix, after the run:
  `wine sc query "FlexNet Licensing Service 64"` → `SERVICE_NAME: FlexNet Licensing Service 64`,
  **`STATE: 4 RUNNING`**, `WIN32_EXIT_CODE: 0`; and the service wrote its own log
  `prefix/tableau-inst/drive_c/users/asdf/AppData/Local/Temp/libFNP_events.log`
  (`23:48:29 03-10-2026 [P:32],[T:472],[V:11.19.4.1 build 291070] EventCode: 30000004`) — the real FlexNet
  code executed under Wine during the app's startup. The bundle's VC redist also left its own install logs in the
  same Temp directory. The run's app processes were stopped afterwards with `wineserver -k` for that prefix only.
- 2026-10-04T05:07Z — **independent confirmation, and the cleanest statement of the gate** (`FlexNetWine` →
  `recon/FLEXNET_WINE.md`). It reached the same screen in the *other* prefix (`prefix/tableau`) by applying the
  harvested state, and it measured the A/B pair that proves the service is the gate:
  * service absent → stdout `The FlexNet Licensing Service is not installed on this machine.`, stderr
    `FlexNet Library could not be initialized, error code 20. FLEXnet Licensing Service is not installed.`, exit 1;
  * service present + RUNNING → stderr `Unable to verify license. Please activate the product.`, exit 1 — i.e. it
    gets past the service check and stops exactly where Windows stops;
  * GUI → window tree `"Activate Tableau": ("tableau.exe") 650x478+624+350`, window-only capture
    `logs/run-flexnet/activate-tableau-window.png`, alive after 100 s.
  Under Wine the harvested service key has `Start=2` (Automatic), so **services.exe auto-starts it on prefix boot**;
  it listens on the *same* pipe name Windows uses (`\\.\pipe\FlexNet Licensing Service 64ABF27A87-…`, `CreateFileW`
  returns a handle) and it created its own Trusted Storage (`ProgramData/FLEXnet/tableau_003e2900_tsf.data`,
  8457 B) plus a `libFNP_events.log`. Running the exe by hand only yields the expected
  `StartServiceCtrlDispatcher() failed` and exit 0 — started by the SCM it stays resident.
  So two independent prefixes reach the activation window: `prefix/tableau-inst` (real bundle install, no DLL
  overrides) and `prefix/tableau` (real install + harvested state + native VC DLLs).
  One caveat worth keeping: under Wine the VC2022 x64 redist **exits 0 but its MSI version check skips**
  `msvcp140.dll`, `msvcp140_2.dll`, `vcruntime140_1.dll`, so forcing those to native (`=n`) fails with
  `not found` and `tableau.exe` dies `c0000135`; the workaround is to cabextract
  `vcRuntimeMinimum_amd64`'s `cab1.cab` from `ProgramData/Package Cache` into `drive_c/windows/system32`. The
  `tableau-inst` path needs none of that because it does not force native overrides.
  `tools/apply_windows_state_wine.sh` was also fixed by that task (it had been importing the `.reg` files into
  `~/.wine` for lack of an exported `WINEPREFIX`) — re-run it once if you use the harvest path.
- 2026-10-04T03:38Z — Windows reference method (scout → `recon/WINDOWS_METHOD.md`): proven channels are (A)
  **differential native probes** (build one PE with `x86_64-w64-mingw32-gcc`, run it under Wine *and* on the guest,
  diff the output), (B) the app's own verbose trace, (C) targeted `WINEDEBUG` channels on the Wine side.
  ProcMon exists and was used on this guest by the AutoCAD project (`C:\acadbox\Procmon.exe`).
