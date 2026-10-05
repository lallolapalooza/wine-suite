# Steinberg Download Assistant 1.40.1 on Linux with a locally built, patched Wine

Steinberg and Steinberg Download Assistant are registered trademarks of Steinberg Media Technologies GmbH. This repository is not associated with, affiliated with, supported nor endorsed by Steinberg Media Technologies GmbH. No guarantees are made, as for the suitability of the content of this repository for any particular purpose.

No Steinberg software is redistributed here. The install media must come from your own Steinberg account; the scripts take it from `$SDA_MEDIA` (see `env.sh`).

Subject: `/home/asdf/Downloads/Steinberg_Download_Assistant_1.40.1_Installer_win.exe`
(Steinberg Download Assistant 1.40.1, BitRock/VMware InstallBuilder 26.5.1 self-extracting
installer, PE32, 125 MiB) on **Wine 11.18 built from source** with the AutoCAD-on-Wine +
Power BI-on-Wine patch series plus one SDA-specific patch.

## Result

| step | outcome | evidence |
|---|---|---|
| install on Windows (reference) | **PASS** — `--mode unattended --unattendedmodeui none`, exit 0 in 33 s, 237 MB / 230 files | `logs/`, `FINDINGS.md` §4.1 |
| run on Windows (reference) | **PASS** — JavaFX window `GlassWndClass-GlassWindowClass-3`, 586x239, login form `Sign in` / `Remember me`; `aria2c` child | `evidence/win_sda_app.log`, `docs/ACCEPTANCE.md` |
| install under Wine | **PASS** — clean-room: fresh prefix → `wine <installer> --mode unattended --unattendedmodeui none` → **rc 0**, 247 MB / full `app/` + `runtime/` in place; only benign fixmes (`wineusb`, `propertystore` stubs, `GetCurrentPackageId` stubs) | `logs/sda_install_wine.log` |
| run under Wine | **PASS** — same window title, same startup log **step for step** including the benign `[1168] Element not found` credential warning and the JavaFX font load; `aria2c` spawned with byte-identical arguments | `logs/sda_fixed.app.log`, `logs/sda_run2.wine.log` |
| login form text on Wine | **PASS — OCR-identical to Windows** (`Sign in`, `Remember me`; 247 vs 227 unique colours) in **both** the pre-installed and the clean-room prefix | `evidence/wine_sda_login.png`, `evidence/wine_sda_login_cleanroom.png`, `evidence/sda_login_compare.png` |
| OS-detection parity | **PASS** — `buildLabEx '19045.1.amd64fre…'`, `WinBuild '19045'`, `isWin64OS=true`, `Windows platform was determined as WIN64`, UA `OSName "Windows 10 Pro"` | `logs/sda_run2.app.log` |
| AppDB v42981 (Dorico 6.x) issues | **BLOCKED — needs a Dorico 6 installation.** Analysis and candidate patches in `docs/APPDB_42981.md`; nothing claimed or guessed | `docs/APPDB_42981.md` |

Start here: [`FINDINGS.md`](FINDINGS.md) for the reverse engineering and the measurements,
[`docs/ACCEPTANCE.md`](docs/ACCEPTANCE.md) for the Windows reference milestone list this build is
diffed against, [`patches/README.md`](patches/README.md) for which patches are SDA-specific,
[`STATE.md`](STATE.md) for the running log.

## What the application actually is

Not Qt, not Electron, not .NET. SDA is a **Java/Kotlin desktop application**:

* `Steinberg Download Assistant.exe` — a **jpackage** launcher (PE32 i386) beside its own
  `packager.dll` (jpackage's native library: `start_launcher` plus the
  `jdk.packager.services.userjvmoptions.LauncherUserJvmOptions` JNI entry points).
* `app/Steinberg Download Assistant.jar` — a **Spring Boot 2.7.18 fat JAR**,
  `Start-Class: net.steinberg.elicenser.download.ApplicationKt` (Kotlin), 35 MB, 1,524 app classes.
* `runtime/` — **Azul Zulu "JDK FX" 8 (1.8.0_492), 32-bit**: `glass.dll` (windowing),
  `prism_d3d|es2|sw.dll` (rendering), `awt.dll`, `fontmanager.dll`, `jfxwebkit.dll` (89 MB WebKit).
* `3rd Party/optional/aria2/aria2c.exe` — the download engine (aria2 1.37.0).

The Win32 surface the *application* calls is small: the Windows Credential Manager
(`CredRead`/`CredWrite`/`CredDelete`/`CredEnumerate`), `SHGetKnownFolderPath`, `IsWow64Process2`,
JNA registry reads, `rundll32 url.dll,FileProtocolHandler`, `java.util.prefs`, and child processes
(`aria2c.exe`, `Steinberg Install Helper.exe`, `Steinberg Install Assistant.exe`).
So the porting problem is "run the bundled 32-bit Zulu JDK FX 8 + JavaFX natives correctly under
Wine", not "implement a large piece of Win32" — and that turned out to need exactly one Wine patch.

## The two fixes that mattered

1. **`patches/local/0100-wine.inf-BuildLabEx-BuildLab.patch`** — Wine never set `BuildLab`/
   `BuildLabEx`; SDA derives `isWin64OS` from `BuildLabEx.contains("amd64")` and otherwise decides
   it is on a 32-bit OS, marks 64-bit runtime components unavailable and reports the wrong
   User-Agent. (Also the open WineHQ bug 47598.)
2. **A registry fix, documented not patched:** winetricks rewrites the *static* HKLM
   `CurrentVersion` values to Windows 7 — in the **WOW6432Node** view a 32-bit process reads — and
   SDA then refuses to start ("The version of the operating system is not supported").
   `tools/mkprefix.sh` pins both views to Windows 10 / build 19045.
3. **A documented JVM option for JavaFX text:** the Windows-default `d3d` pipeline (and `es2`)
   draw SDA's layout but no glyphs under Wine, so the login button is a blank block.
   `tools/apply_jvm_options.sh` sets the upstream-documented
   `-Dprism.order=j2d -Dsun.java2d.d3d=false` (WineHQ bug 37048) in the app's own
   `[JVMOptions]`; after that the login form is OCR-identical to Windows.

## Layout

| path | what it is |
|---|---|
| `sources/wine/wine-11.18/` | pristine Wine 11.18 + `patches/series` + `patches/local` applied |
| `wine/wine-11.18/` | build tree (out-of-tree copy) |
| `wine-install/` | `make install` output; `wine-install/bin/wine` |
| `patches/series/` | shared base: AutoCAD-on-Wine (14) + Power BI-on-Wine (5) = `0001..0019` |
| `patches/local/` | **SDA-specific**: `0100-wine.inf-BuildLabEx-BuildLab.patch` |
| `patches/sources/` | provenance copies of the imported AutoCAD/Power BI patch sets |
| `tools/` | build, prefix, install, run, JVM-option and automation scripts |
| `state/` | prefix, disk-backed tmp/scratch, carved installer payload, Windows reference tree |
| `logs/`, `evidence/` | build/run logs; screenshots and reference captures |
| `docs/` | acceptance checklist, AppDB plan |
| `vmshare/` | the Windows-guest command channel |

## Quick start

```bash
source env.sh
tools/apply_patches.sh              # series (19) + local (1), idempotent; --check re-verifies 20/20
tools/build_wine.sh                 # configure --enable-archs=i386,x86_64, OOM-aware make, install
tools/mkprefix.sh                   # win64 prefix, corefonts/tahoma, vcrun2019, win10 + pinned CurrentVersion
tools/install_sda_wine.sh           # wine <installer> --mode unattended --unattendedmodeui none
tools/apply_jvm_options.sh          # -Dprism.order=j2d -Dsun.java2d.d3d=false into [JVMOptions]
tools/run_sda.sh run 120            # launch on the project display, harvest the app's own log
tools/verify_series.sh              # prove patches/series is the AutoCAD+PowerBI union (by hash)
```

Display (Xvfb + openbox + x11vnc, so the app is watchable and scriptable):

```bash
Xvfb :22 -screen 0 1920x1080x24 +extension GLX +extension RANDR +extension Composite +render -listen tcp &
DISPLAY=:22 openbox --sm-disable &                 # nb: openbox only takes DISPLAY from the env
env -u WAYLAND_DISPLAY XDG_SESSION_TYPE=x11 x11vnc -display :22 -rfbport 5922 -forever -shared -nopw -localhost &
# drive it with tools/uix.py (shot, ocr, find, click, clickxy, key, type, windows, pixel, diff)
```

Windows reference: libvirt domain `win11` (Windows 11 25H2, 192.168.122.230, spice
127.0.0.1:5900). Channel helpers: `tools/vmcmd.sh`, `tools/vmcmda.sh` (elevated),
`tools/vmrun.sh <script.ps1> [timeout] [--admin]`, `tools/vmclick.py x y`,
`virsh screenshot win11 out.png` + `tesseract`.

## Which patches are exclusive to this application

`patches/local/0100-wine.inf-BuildLabEx-BuildLab.patch` — added because of SDA (it reads
`BuildLabEx`), though the change is a general Wine improvement. The shared `patches/series/` set
(AutoCAD + Power BI) is a general Wine-API base and is **not** SDA-specific. Full reasoning and
what was investigated-but-not-needed: [`patches/README.md`](patches/README.md).
