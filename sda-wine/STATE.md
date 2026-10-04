# SDA on Wine — STATE (authoritative running log; survives compaction)

Task: `/home/asdf/Downloads/Steinberg_Download_Assistant_1.40.1_Installer_win.exe` must install and
open on a locally built Wine 11.18 exactly as it does on Windows, using the Wine patches already
produced in the `autocad`/`powerbi` work plus new Wine patches for whatever SDA still needs.

## User acceptance criteria
1. Apply the Wine patches from the autocad and powerbi folders, then make SDA run on Wine until it
   opens like on Windows.
2. Check against the Windows VM (libvirt domain `win11`).
3. Working directory = `sda-wine/`; must contain every Wine patch used, reproducibly;
   app-exclusive patches in a `local` folder inside the patches directory.
4. Also fix the WineHQ AppDB v42981 issues (Dorico 6.x): stuck dialogs in file-open/settings menus;
   error dialog on close; new-project playback lock-up.
5. Not for submission to Wine (no LLM-disclosure requirement); otherwise follow WineHQ gitlab wiki
   best practice.
6. If the app needs kernel-level APIs Wine cannot provide, say so, document it and stop.

## Environment (measured 2026-10-03)
- Host: Linux 7.0.0-34 x64, 22 CPUs, 30 GiB RAM, `/` ~45 GB free. Display `:22` = Xvfb + openbox +
  x11vnc on 127.0.0.1:5922. Helpers: `tools/uix.py`, `tools/vmclick.py`, `tools/run_sda.sh`.
- Windows VM `win11` RUNNING: Windows 11 25H2 (10.0.26200), 192.168.122.230, spice 127.0.0.1:5900.
  Channel: `tools/vmcmd.sh` (normal), `tools/vmcmda.sh` (elevated, verified), `tools/vmrun.sh
  <script.ps1> [timeout] [--admin]`, `virsh screenshot win11 out.png`.
  Guest-side pollers live at `C:\seref\se_svc.ps1` and `C:\seref\vm_admin.ps1`.
- Subagents: provider account unfunded → always pass `model: "@default"`; then they work.

## Deliverable layout
```
sda-wine/
  patches/series/   0001..0019  shared base (AutoCAD 14 + Power BI 5), verified 19/19 OK
  patches/local/    0100-wine.inf-BuildLabEx-BuildLab.patch  (SDA-exclusive; see below)
  patches/sources/  provenance copies: acad-wine-main, autocad2027-private-main, powerbi
  sources/wine/wine-11.18   pristine 11.18 + series + local applied
  wine/wine-11.18           build tree      wine-install/   make install output
  state/prefix              WINEPREFIX      state/tmp       disk-backed TMPDIR
  state/vfs, state/win_sda, state/sda_jar    RE artefacts (see FINDINGS.md)
  tools/ logs/ evidence/ docs/ vmshare/
```

## What SDA actually is (RE, high confidence — details in FINDINGS.md)
- Installer: BitRock/VMware **InstallBuilder 26.5.1** self-extracting image, Tcl/Tk-stub PE32
  (window class `TkTopLevel`), CookFS/Metakit payload containing a stored deflate ZIP with 10,826
  local headers and no central directory. `tools/extract_vfs.py` carves it → `state/vfs/` (JRE +
  libraries). Needs **Windows >= 6.2**; silent: `--mode unattended --unattendedmodeui none`.
- Installed app = **jpackage app-image, 32-bit**: `Steinberg Download Assistant.exe` +
  `packager.dll` (jpackage's own DLL: `start_launcher` + `jdk.packager.services.userjvmoptions`
  JNI), `app/Steinberg Download Assistant.jar` = **Spring Boot 2.7.18 fat JAR**, Start-Class
  `net.steinberg.elicenser.download.ApplicationKt` (Kotlin), `runtime/` = **Azul Zulu JDK FX 8
  (1.8.0_492), 32-bit** with JavaFX (`glass.dll`, `prism_d3d|es2|sw.dll`, `jfxwebkit.dll` 89 MB),
  `3rd Party/optional/aria2/aria2c.exe` (aria2 1.37.0).
- App's own Win32 surface is small: `CredRead/Write/Delete/Enumerate/Free` (advapi32, own JNA
  mapping, target `Steinberg Download Assistant`), `SHGetKnownFolderPath` (FOLDERID_Downloads),
  `IsWow64Process2`, JNA `Advapi32Util` registry reads, `rundll32 url.dll,FileProtocolHandler` for
  opening the browser, `java.util.prefs` (registry-backed), child processes `aria2c.exe`,
  `Steinberg Install Helper.exe`, `Steinberg Install Assistant.exe --list-installed`.

## Windows reference (the thing to match) — full detail in docs/ACCEPTANCE.md
Unattended install into the guest → `C:\Program Files (x86)\Steinberg\Download Assistant` (237 MB).
Launched: process `Steinberg Download Assistant` (144 MB), `aria2c` running, window class
**`GlassWndClass-GlassWindowClass-3`**, title `Steinberg Download Assistant`, 586x239, showing the
**login form (`Sign in`, `Remember me`)**. Log: `evidence/win_sda_app.log`.

## Findings that drive the patches

### F1. `packager.dll` name collision — ALREADY FIXED in Wine, no patch needed
Wine ships a builtin `dlls/packager/packager.dll` (OLE packaging COM server) exporting only
`DllCanUnloadNow/DllGetClassObject/DllRegisterServer/DllUnregisterServer`. Bug 47598/43472/57125
show Wine loading the builtin and `GetProcAddress("start_launcher")` returning NULL → crash.
Upstream **bug 43472 is CLOSED FIXED** (`74239c9853a08083137917d3184e52dd25ef4c25`), and Wine
11.18's `dlls/ntdll/unix/loadorder.c:version_heuristics()` prefers **native** for any candidate
whose `CompanyName` is not Microsoft (Steinberg/Oracle included) or that has no version resource.
`loader.c:load_builtin()` then returns `STATUS_IMAGE_ALREADY_LOADED` for `LO_NATIVE_BUILTIN`, i.e.
keeps the app's DLL. Fallback if ever needed: `WINEDLLOVERRIDES=packager=n`.

### F2. `BuildLabEx` missing → SDA mis-detects the platform — **patch 0100**
`n.s.e.d.common.system.WindowsOsHelper` reads `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion`
values `BuildLabEx`, `CurrentBuildNumber`, `ProductName`, `CurrentVersion`,
`CurrentMajor/MinorVersionNumber`, plus env `ProgramFiles(x86)`, `ProgramW6432`,
`PROCESSOR_ARCHITECTURE`, `PROCESSOR_ARCHITEW6432`, plus `IsWow64Process2`.
It computes `isWin64OS = buildLabEx.contains("amd64"|"arm64"|"wow64") && ProgramFiles(x86) exists`.
Wine's `loader/wine.inf.in` `[VersionInfo]` sets `CurrentBuild`/`UBR`/`EditionId`/`ProductName` but
**no `BuildLab`/`BuildLabEx`** anywhere in the tree. Consequences on Wine: `isWin64OS=false` →
`getWindowsPlatform()` = WIN32 → `getOsBits()`="32", the Windows install helper is marked
`notAvailable`, and runtime components gated on `[WIN64,WINARM64]` are skipped. This is also the
still-open WineHQ **bug 47598**. Patch `patches/local/0100-wine.inf-BuildLabEx-BuildLab.patch`
adds both values to `[VersionInfo]` (values shaped exactly like Windows'.
`BuildLab`=`19045.vb_release.191206-1406`, `BuildLabEx`=`19045.1.amd64fre.vb_release.191206-1406`).
Caveat documented in the patch: the `amd64` token is hardcoded, matching how Wine already hardcodes
`ProductName`/`CurrentBuild`; the app's AND with `ProgramFiles(x86)` keeps 32-bit-only Wine correct.

### F3. JavaFX rendering on Wine — documented workaround exists
WineHQ **bug 37048** "Apps using JavaFX fail to show the GUI" (UNCONFIRMED, open since 2014):
JavaFX content is not drawn, though it responds to mouse. Comment 5 workaround:
**`-Dprism.order=j2d`** (plus `-Dsun.java2d.d3d=false`). Our first choice is
`_JAVA_OPTIONS="-Dprism.order=sw -Dprism.verbose=true"`, falling back to `j2d`.
Also relevant: bug 8060 (fontmanager.dll faults without Arial → install `corefonts`).

### F4. Missing `Downloads\Steinberg` directory
WineHQ **bug 57136** (CLOSED FIXED in 9.18) notes SDA complains it cannot create
`c:\users\<user>\Downloads\Steinberg`; creating it manually unblocks the download path. Keep as a
documented setup step if it recurs.

### F5. AppDB 42981 (Dorico 6.x) — different application
Dorico is a **Qt 6 native** app (Steinberg dev blog), not JavaFX; the four reported symptoms map
onto layered-window/popup presentation (WineHQ 60173/60259/50495), Qt+D3D11 present (60366, where
the reporter's own workaround is DXVK), audio/ASIO (PipeWire quantum) and close-time error paths.
Fixing these needs a Dorico installation (media + licence) that is not present on this host. Plan
and candidate patches: `docs/APPDB_42981.md` (from `Appdb42981Plan`).

## Status: SDA runs on Wine and matches the Windows reference

- [x] skeleton + provenance; series = **14 AutoCAD + 5 Power BI**, verified by content hash
      (`tools/verify_series.sh`); unused source patches are the test/debug-only ones
- [x] `sources/wine/wine-11.18` patched: `tools/apply_patches.sh --check` → **20 OK / 0 FAIL**
      (19 shared + `patches/local/0100-wine.inf-BuildLabEx-BuildLab.patch`)
- [x] Wine built: `wine-11.18`, `make` rc=0, `make install` OK
- [x] prefix provisioned; both registry views pinned to Windows 10 / build 19045
- [x] app runs under Wine, window + login form OCR-identical to Windows
      (`evidence/wine_sda_login.png`, `evidence/sda_login_compare.png`)
- [x] **clean-room end-to-end**: fresh prefix `state/prefix-inst` → `tools/mkprefix.sh` →
      `tools/install_sda_wine.sh` (**installer rc=0**, 247 MB, `app/` + 108 runtime DLLs) →
      `tools/apply_jvm_options.sh` → launch → window 570x200, 247 colours, OCR
      `Sign in` / `Remember me` (`evidence/wine_sda_login_cleanroom.png`)

### What made it work (in order of discovery)

1. `packager.dll` — **no action needed**; Wine 11.18 prefers the native DLL (bug 43472 fixed).
2. **Win7 registry values in the WOW6432Node view** (winetricks) → the app refused to start
   ("The version of the operating system is not supported"). Fixed by pinning both views in
   `tools/mkprefix.sh`; documented setup fix, not a patch.
3. **`BuildLabEx` absent from Wine** → `isWin64OS=false`, platform `WIN32`, wrong User-Agent,
   64-bit runtime components skipped. Fixed by patch 0100. Also WineHQ bug 47598.
4. **JavaFX glyphs missing on `d3d`/`es2`** → login button drawn as a blank block. Fixed with the
   upstream-documented `-Dprism.order=j2d -Dsun.java2d.d3d=false` in the app's `[JVMOptions]`
   (`tools/apply_jvm_options.sh`); WineHQ bug 37048. Not a Wine patch — see `FINDINGS.md` §4.4.

### Open / not done

- The AppDB v42981 (Dorico 6.x) issues are **not** fixed: they need a Dorico 6 installation
  (free Dorico SE suffices) which is not present on this host. Analysis + candidate patches in
  `docs/APPDB_42981.md`; nothing claimed without a reproduction.
- A Wine patch for the JavaFX `d3d`/`es2` glyph loss was deliberately **not** attempted: it needs
  frame-level d3d9 debugging, and the documented JVM option already produces a Windows-identical
  result. `FINDINGS.md` §4.4 records the measurements if someone wants to pursue it.
- `Download\Steinberg` was pre-created; WineHQ bug 57136's complaint did not recur in these runs.

