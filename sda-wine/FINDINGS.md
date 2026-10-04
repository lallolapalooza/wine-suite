# SDA 1.40.1 — what it is, and what has to work on Wine

All statements below are measured, not inferred, unless marked `[INFERENCE]`.
Evidence paths are relative to `/home/asdf/projects/sda-wine/`.

## 1. The installer

`/home/asdf/Downloads/Steinberg_Download_Assistant_1.40.1_Installer_win.exe`, 130,419,088 bytes.

| property | value | how measured |
|---|---|---|
| format | PE32 i386, GUI, 10 sections, Authenticode-signed | `objdump -p` |
| vendor | `Steinberg Media Technologies GmbH`, ProductName `Steinberg Download Assistant`, FileDescription `Steinberg Download Assistant Installer`, OriginalFilename `Setup.exe` | guest `VersionInfo` |
| build tool | **BitRock / VMware InstallBuilder 26.5.1** (`project.buildTag: 'IB: 26.5.1-202606111432'`) | guest `%TEMP%\installbuilder_installer.log` |
| GUI toolkit | **Tcl/Tk** — the running installer's window class is `TkTopLevel` | guest `EnumWindows` |
| layout | PE stub ends at file offset `0x2A8344`; Authenticode at `0x07C5DF40`+`0x2A50`; ~127.6 MB overlay | `objdump -h`, `grep -abo` |
| payload | CookFS/Metakit VFS `[INFERENCE]` + a **stored deflate ZIP with 10,826 local headers and NO central directory** | `tools/carve_vfs.py` |
| min OS | Windows 8 (`minimum_required_system_version_windows: '6.2'`, exit code 101 if too old) | installbuilder log |
| unattended | `--mode unattended --unattendedmodeui none` → exit 0 | guest run (33 s) |
| components | `component_programfilesfolder_32_sda`, `component_ariafolder`, `component_startmenu`, `component_applicationsupportfolder`, `component_installerversionfile` | installbuilder log |
| languages | en de es es_AR fr it ja pt pt_BR zh_CN zh_TW ru | installbuilder log |

`tools/extract_vfs.py` carves the embedded ZIP → **10,672 files / 68 MB** at `state/vfs/`
(`state/vfs_list.txt`). Its content is the JRE + libraries only (jdk/nashorn,
`sun/security/pkcs11`, `javafx/*`, `com/sun/webkit`, `kotlin/*`, `tornadofx/*`,
`org/springframework/*`, `ch/qos/logback`, `com/sun/jna`, `impl/org/controlsfx`);
`META-INF/MANIFEST.MF` = "Java Runtime Environment", Implementation-Version **1.8.0_492**,
Created-By 1.8.0_282 (Azul Systems). **No `net/steinberg` classes are in it** — the application
itself ships as a Spring Boot fat JAR (see §2).

## 2. The installed application (Windows reference)

Unattended install into the guest landed at
`C:\Program Files (x86)\Steinberg\Download Assistant` — **237 MB, 230 files**
(copied back to `state/win_sda/`, analysed at `state/sda_jar/`).

This is a **jpackage app-image**, 32-bit:

```
Steinberg Download Assistant.exe      171072   PE32 i386, vendor Steinberg Media Technologies GmbH
packager.dll                          247320   PE32 i386 — jpackage native lib
app/Steinberg Download Assistant.cfg      727
app/Steinberg Download Assistant.jar 35383968   Spring Boot fat JAR
app/jnidispatch.dll                   177696
runtime/                                     Zulu "JDK FX" **32-bit** JRE (lib/i386/jvm.cfg)
  runtime/bin/client/jvm.dll         3948048
  runtime/bin/server/jvm.dll         6375952
  runtime/bin/jfxwebkit.dll         89716760   JavaFX WebView (WebKit)
  runtime/bin/{glass,prism_d3d,prism_es2,prism_sw,awt,fontmanager,freetype,javafx_font}.dll
  runtime/lib/{rt.jar 63579149, jfxrt.jar 9148041, ...}
3rd Party/optional/aria2/aria2c.exe  5649408   download engine (aria2 1.37.0)
Uninstaller/Uninstall ...exe         6466340
msvcp140*.dll ucrtbase.dll vcruntime140.dll api-ms-win-*.dll  (VC++ 2015+ redist, self-contained)
Installer.ini                             23   "STR:1.40.1"
```

### `packager.dll` — the important detail
Exports (measured, `objdump -p`):
```
_Java_jdk_packager_services_userjvmoptions_LauncherUserJvmOptions__1getUserJvmOptionDefaultKeys@8
_Java_jdk_packager_services_userjvmoptions_LauncherUserJvmOptions__1getUserJvmOptionDefaultValue@12
_Java_jdk_packager_services_userjvmoptions_LauncherUserJvmOptions__1getUserJvmOptionKeys@8
_Java_jdk_packager_services_userjvmoptions_LauncherUserJvmOptions__1getUserJvmOptionValue@12
_Java_jdk_packager_services_userjvmoptions_LauncherUserJvmOptions__1setUserJvmKeysAndValues@16
start_launcher
```
It is **jpackage's** native library. `Steinberg Download Assistant.exe` does
`LoadLibraryW("packager.dll")` then `GetProcAddress(..., "start_launcher")`.

**Wine ships a builtin `dlls/packager/packager.dll` that is a completely different DLL** — the OLE
packaging COM server, exporting only `DllCanUnloadNow`, `DllGetClassObject`,
`DllRegisterServer`, `DllUnregisterServer` (`dlls/packager/packager.spec`). If it shadows the
app's copy, `GetProcAddress("start_launcher")` returns NULL and the launcher jumps to address 0 —
exactly WineHQ bug 47598 (`raise_exception code=c0000005 ip=00000000`).

Whether it still shadows in 11.18 depends on `dlls/ntdll/unix/loadorder.c`: for a DLL found
**outside** the system dir, `version_heuristics()` maps `CompanyName` → `Microsoft` = builtin-first,
`Twin Working Group` = builtin, **everything else (incl. Steinberg / Oracle) = `LO_NATIVE_BUILTIN`**.
So 11.18 should prefer the app's native DLL. **To be verified by running it.**
Fallback (documented setup fix, not a patch): `WINEDLLOVERRIDES=packager=n`.

### `.cfg` (the launcher's JVM options, verbatim)
```
[Application]
app.name=Steinberg Download Assistant
app.mainjar=Steinberg Download Assistant.jar
app.version=1.40.1
app.preferences.id=org/springframework/boot/loader
app.mainclass=org/springframework/boot/loader/JarLauncher
app.runtime=$APPDIR\runtime
app.identifier=org.springframework.boot.loader

[JVMOptions]
-Dapplication.year=2026
-Dspring.config.additional-location=optional:file:${APPDATA}\steinberg-download-assistant\application.properties
-Dlogging.file.name=${LOCALAPPDATA}\Steinberg Download Assistant\logs\Steinberg-Download-Assistant_${sda.startup_time}.log
-Daria2c.tool=..\3rd-party\optional\aria2\aria2c.exe
-Djava.net.useSystemProxies=true
```

### JAR identity
```
Manifest: Implementation-Title Steinberg Download Assistant, Implementation-Version 1.40.1
          Start-Class  net.steinberg.elicenser.download.ApplicationKt   (Kotlin)
          Main-Class   org.springframework.boot.loader.JarLauncher
          Spring-Boot-Version 2.7.18, Build-Jdk-Spec 1.8
1,524 classes under BOOT-INF/classes/net/steinberg; 1,767 jar entries
Notable app packages: install, licenseactivation, category, ipc, clientaccessgateway,
  singleinstance, beta, common/{conditional/{windows,macos},system,api,command}, windowscredentialsaccess
```

### Windows API surface the app itself asks for (small!)
From the app classes: `CredRead`, `CredWrite`, `CredDelete`, `CredFree`, `CredEnumerate`
(advapi32, via its own `Advapi32_Credentials` JNA mapping), `SHGetKnownFolderPath` (shell32),
and JNA `Advapi32Util` registry reads (e.g. `BuildLabEx`, which Wine does not set — a logged
ERROR, not fatal). Everything else the app needs comes from the bundled JRE / JavaFX natives.

## 3. Consequence for the Wine port

The blocker surface is not "a Windows app" but **"the bundled 32-bit Zulu JDK FX 8 + JavaFX
natives running on Wine"**:

1. the jpackage launcher (`Steinberg Download Assistant.exe` + `packager.dll`),
2. `runtime/bin/java.dll`/`jvm.dll` (client or server VM) and `awt.dll` + `fontmanager.dll`
   (AWT/Java2D),
3. JavaFX `glass.dll` (windowing/event loop) + `prism_d3d.dll` | `prism_es2.dll` | `prism_sw.dll`
   (rendering) + `javafx_font.dll`,
4. `jfxwebkit.dll` (89 MB WebKit) for the WebView views (login page),
5. `aria2c.exe` for downloads,
6. `sunmscapi.dll` (CryptoAPI) and `net.dll` (winsock) for TLS.

Fallbacks worth trying early if rendering misbehaves: `-Dprism.order=sw` (software pipeline) and
`-Dprism.verbose=true`.

---

# 4. Measured results

## 4.1 Install

| platform | command | result |
|---|---|---|
| Windows 11 VM | `SDA_setup.exe --mode unattended --unattendedmodeui none` | **exit 0 in 33 s**; 237 MB, 230 files in `C:\Program Files (x86)\Steinberg\Download Assistant` |
| Windows VM, GUI | installer shows a Tcl/Tk wizard (`TkTopLevel`); "License Agreement" page reached | `evidence/win_sda_inst_0*.png` |

## 4.2 The application on Windows (reference)

`Steinberg Download Assistant.exe` → process 144 MB, `aria2c` child, window class
**`GlassWndClass-GlassWindowClass-3`**, title `Steinberg Download Assistant`, 586x239, showing the
login form. Full log `evidence/win_sda_app.log`; milestone list in `docs/ACCEPTANCE.md`.

## 4.3 The application on Wine (after the fixes below)

Startup log matches the Windows reference step for step, including the *same* benign credential
warning:

```
Windows OS Information: buildLabEx '19045.1.amd64fre.vb_release.191206-1406', WinBuild '19045'
isWow64Process = true, processMachine = 332, nativeMachine = 34404 => isArm64OS = false
buildLabEx contains amd64, ProgramFiles(x86) environment variable exists => isWin64OS=true
Windows platform was determined as WIN64
User Agent: ... "OSName":"Windows 10 Pro", "OSVersion":"10.0 (19045.1.amd64fre...) x86", "OSBits":"64"
Started application in 16.054 seconds
start() - Start JFX scene
SelfUpdate completed ... there is no newer version available...
WARN WindowsCredentialManagerAccess : Read received an error: [1168] Element not found.
Font loaded '/fonts/AkzidGroCFFBol.otf' -> 'Akzidenz Grotesk BE Bold'
```

Window: title `Steinberg Download Assistant`, 570x200; `aria2c` spawned with byte-identical
arguments to Windows (same flags, `--dir=C:\users\asdf\Downloads\Steinberg`,
`--stop-with-process=<pid>`). Wine stderr for the whole run is 5 lines, all benign:

```
libEGL warning: DRI3 error: Could not get DRI3 device        (Xvfb has no DRI3 - expected)
2 err:ole:com_get_class_object ... {597d4fb0-47fd-4aff-89b9-c6cfae8cf08e} not registered
1 fixme:file:NtLockFile I/O completion on lock not implemented yet
```

OCR of the Wine window vs the Windows window: **both read `Sign in` and `Remember me`**
(`evidence/wine_sda_login.png`, `evidence/sda_login_compare.png`).

## 4.4 Rendering-pipeline measurement (the text-glyph bug)

Same build, same prefix, only `-Dprism.order` varied; OCR of the window, unique colours in it:

| pipeline | OCR | unique colours | verdict |
|---|---|---|---|
| `d3d` (the Windows default) | *(none)* | 44 | panel + red accent draw, **no glyphs** — button is a filled block |
| `es2` | *(none)* | 44 | same failure |
| `sw` | `ign in` (partial) | 44 | glyphs appear |
| **`j2d`** | **`Sign in` / `Remember me`** | **247** | **matches Windows exactly** |

Because the CPU pipelines rasterise the same glyphs that the GPU ones fail to draw, the fault is
in the *textured glyph-quad* path (prism's glyph cache texture) rather than in font loading —
`javafx_font.dll` is demonstrably fine, since the app logs the font family/name and the `j2d`/`sw`
pipelines render with it. Both `d3d` (Wine d3d9 → GL) and `es2` (Wine opengl32 → host GL) are
affected, so this is not a single wined3d format issue. `dlls/d3d9/device.c` does map
`D3DFMT_A8` ↔ `WINED3DFMT_A8_UNORM`, and `dlls/d3d9/tests/device.c` even asserts
`TEST_FMT(D3DFMT_A8, D3DERR_INVALIDCALL)` for one usage, so a targeted patch would need real
frame-level d3d9 debugging; it is **not** attempted here.

This is WineHQ **bug 37048** "Apps using JavaFX fail to show the GUI" (open, UNCONFIRMED); its
comment-5 workaround is exactly `-Dprism.order=j2d -Dsun.java2d.d3d=false`. `tools/apply_jvm_options.sh`
applies that to the app's own config; the result is verified above.

## 4.5 Where a JVM option has to go (measured)

| location | effect |
|---|---|
| `_JAVA_OPTIONS` in the environment | works |
| `[JVMOptions]` in `app/Steinberg Download Assistant.cfg` | **works** (the app's own `-Dlogging.file.name`, `-Daria2c.tool` prove the block is read) |
| `[JVMUserOptions]` in the same file | **no effect** (measured: same option, identical 44-colour result) |

So `tools/apply_jvm_options.sh` writes into `[JVMOptions]`. Note the `.cfg` is CRLF and is rewritten
by an SDA self-update, so the tool re-runs after any update.

# 5. Two fixes were required, and only one of them is a Wine patch

1. **`patches/local/0100-wine.inf-BuildLabEx-BuildLab.patch`** — Wine sets
   `CurrentBuild`/`UBR`/`EditionId`/`ProductName` in `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion`
   but no `BuildLab`/`BuildLabEx` anywhere in the tree. This is also the open WineHQ bug 47598.
   Without it the app logs `Could not determine BuildLabEx from registry!`, computes
   `isWin64OS = false` (its test is `buildLabEx.contains("amd64"|"arm64"|"wow64")` **and**
   `ProgramFiles(x86)` present), reports itself as WIN32/`OSBits:32`, and marks 64-bit-only runtime
   components unavailable. The INF engine applies `[VersionInfo]` to both the 64-bit and the
   WOW6432Node views, so the 32-bit app sees it too.
2. **A prefix setup fix, not a patch:** winetricks rewrites the *static* HKLM `CurrentVersion`
   values to **Windows 7** (build 7601, `ProductName "Microsoft Windows 7"`,
   `CSDVersion "Service Pack 1"`) when it normalises the prefix, and it does so in the
   **WOW6432Node** view that a 32-bit process reads. SDA refuses to start on that ("The version of
   the operating system is not supported"). `tools/mkprefix.sh`'s `regs` stage pins both views to
   Windows 10 / build 19045. This is documented and reproducible because it is a registry fix, not
   a code change.

`WINEDLLOVERRIDES=packager=n` was **not** needed: Wine 11.18 keeps the app's native `packager.dll`
(`version_heuristics` -> `LO_NATIVE_BUILTIN` for a non-Microsoft vendor), so bug 47598's original
`start_launcher` crash no longer occurs.

