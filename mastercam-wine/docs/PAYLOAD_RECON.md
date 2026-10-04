# Mastercam 2027 payload — static reconnaissance

Read-only analysis of the extracted installer payload at
`/run/media/asdf/Windows/mastercam-media`. No build, no install, no app run was performed.

Every claim below is paired with the command that produced it. Anything derived rather than
directly observed is marked `[INFERENCE]`.

---

## 0. Inventory and tooling

```
$ find . -maxdepth 2 -printf '%y %10s %p\n' | sort -k3
d        ./SetupPrerequisites
d        ./mastercam
d        ./support
f     465 ./ProductCodes.dat
f     144 ./datapaths.ini
f 11869528 ./setup.exe
f 1188374016 ./mastercam/Mastercam_Installer.msi
f 2969600 ./mastercam/1028.mst … (15 *.mst total)
f 195231744 ./SetupPrerequisites/CodeMeterRuntime64.msi
f 460780776 ./SetupPrerequisites/MastercamLicensing/MastercamLicensingSetup.exe
f   2664960 ./SetupPrerequisites/msxml6_x64.msi
f   1521152 ./SetupPrerequisites/msxml6_x86.msi
f 121307088 ./SetupPrerequisites/ndp48-x86-x64-allos-enu.exe
f  25633440 ./SetupPrerequisites/VC2022/VC_redist.x64.exe
f  13959768 ./SetupPrerequisites/VC2022/VC_redist.x86.exe
f 182057816 ./support/languagepacks/2027_en_language_pack_mastercam.exe
f  31363936 ./support/updater/mastercam2027-updater.exe
f   3956496 ./support/uninstaller/uninstaller.exe
f   3747160 ./support/NHaspX.exe
f  16758616 ./support/nethaspserver/lmsetup.exe
f   1816152 ./support/nethaspmonitor/aksmon32_setup.exe
+ per-language  support/resources/<lang>/{DvdSetupRes.dll, NHaspXRes.DLL, license/}
+                 support/resources/en/documentation/mastercam/AdministratorGuide.pdf
```

Tools actually used: `7z`, `msiinfo`/`msidump` (msitools), `file`, `objdump`, `strings`, `grep`,
`python3`, `read` (PDF).

The two cabinet streams were extracted once into scratch and analyzed there:

```
$ 7z x -y Mastercam_Installer.msi 'Data1.cab' 'Data11.cab'   # → 629,145,600 + 524,537,360 bytes
$ 7z l Data1.cab   →  2617 files
$ 7z l Data11.cab  →  1118 files
```
(Scratch under `state/tmp/payload/` has since been deleted; only the numbers above were recorded.)

---

## 1. Bootstrapper — `setup.exe`

```
$ file setup.exe
setup.exe: PE32+ executable for MS Windows 6.00 (GUI), x86-64, 6 sections

$ objdump -p setup.exe | grep -E 'DLL Name|Subsystem |MajorSubsystem|MinorLinker'
	DLL Name: msi.dll            ← imported by ordinal only
	DLL Name: OPENGL32.dll
	DLL Name: UxTheme.dll
	DLL Name: KERNEL32.dll, USER32.dll, GDI32.dll, MSIMG32.dll, WINSPOOL.DRV, ADVAPI32.dll,
	           SHELL32.dll, COMCTL32.dll, SHLWAPI.dll, ole32.dll, OLEAUT32.dll, oledlg.dll,
	           gdiplus.dll, UIAutomationCore.DLL, OLEACC.dll, IMM32.dll, WINMM.dll, COMDLG32.dll
	Subsystem 00000002 (Windows GUI)
	MinorLinkerVersion 44        ← MSVC 2022 toolset
```

Version resource (`7z l setup.exe`, which decodes the PE `VS_VERSIONINFO`):

```
Comment = { FileVersion: 29.0.10172.0 ; ProductVersion: 2.0.100.0
            CompanyName: CNC Software, LLC
            FileDescription: Mastercam Installer
            ProductName:  Mastercam Installer
            InternalName: setup.exe ; OriginalFilename: setup.exe
            LegalCopyright: © 1983-2026 CNC Software, LLC. All Rights Reserved. }
```

**Framework: not InstallShield/WiX.** `strings -a setup.exe | grep -iE 'InstallShield|Flexera|Acresso|WiX|Burn|Bootstrapper'`
returns nothing; the strings are MFC/ATL/BCGSoft (`?AVCComObjectRootEx@…ATL@@`,
`?AVCCommandLineInfo@@`, `CBCGP*`, `CStringT`). It is CNC's own native C++ "DvdSetup" frontend that
drives `msi.dll` directly and shells out to `msiexec.exe`. [INFERENCE: statically linked MFC/ATL —
the import table contains no `mfc*.dll`.]

Embedded manifest (`strings -a setup.exe`, one long `<assembly …>` blob):

```xml
<assemblyIdentity type="win32" name="Microsoft.Windows.Common-Controls" version="6.0.0.0"
                  processorArchitecture="amd64" publicKeyToken="6595b64144ccf1df"/>
<trustInfo><security><requestedPrivileges>
   <requestedExecutionLevel level="requireAdministrator" uiAccess="false"/>
</requestedPrivileges></security></trustInfo>
<windowsSettings><dpiAware …>true</dpiAware></windowsSettings>
```
→ **requires elevation**; a Wine prefix that is not "admin" will get a UAC-style failure.

### What it installs / orchestrates

Strings are UTF-16; extracted with `strings -el setup.exe`:

```
Mastercam_Installer.msi            mastercam_installer.msi          Path to installer:
TRANSFORMS                         MastercamTransforms              Set transforms:
msiexec.exe                        msiexec.exe /i "
\SetupPrerequisites\
CodeMeterRuntime64.msi             MastercamLicensingSetup.exe      VC2022
ndp48-x86-x64-allos-enu.exe        vc_redist.x64.exe                vc_redist.x86.exe
\support\nethaspserver\lmsetup.exe \support\nethaspmonitor\aksmon32_setup.exe
\support\uninstaller\uninstaller.exe        nhsrvice.exe
%1!s!\SetupPrerequisites\%2!s!\%3!s!        #Unable to find %s
Running frontend in silent mode.
```

Command lines it builds (verbatim format strings):

```
msiexec.exe /i "                          ← builds  msiexec /i "<msi>" TRANSFORMS="<mst>" <props>
 /clone_wait /S /v"REBOOT=ReallySuppress /L*V "%s" /qn"    ← InstallShield prereq launchers (silent)
 /S /V"ARPSYSTEMCOMPONENT="1" REBOOT=ReallySuppress /L*V "%s" /qn"
 /q /norestart                            ← VC_redist.x64/x86.exe
 /x %s /L*V "%s" /qn                      ← uninstall path
targetdir   TARGETDIR="   adminlog   /LV "   /qb   admin mode: cmd =   ← administrative-install mode
silent                                    ← frontend silent flag
```

**Silent/unattended switches.** `setup.exe` has its own "silent" frontend mode (string
`Running frontend in silent mode.`). No `/s`, `/silent`, `/qn`, `/quiet`, `/help` literal was found
in its strings (`strings -el setup.exe | grep -Fxc '/s'` → `0`, etc.), so the trigger is not a
documented long switch; the parser recognises named parameters (`ParseParam: Cannot find logpath`,
plus the keys `silent`, `targetdir`, `adminlog`, `logpath`, `username`, `companyname`, `action`)
and the shipped config files are read before launch. The prereq launchers it spawns **do** take the
standard InstallShield silent form `/S /v"… /qn"` (see §5).

### Config files it reads (all UTF-16 literals in `setup.exe`)

```
%s\datapaths.ini
%s\support\mcim.ini
\productcodes.dat
\englishOnly.txt
\showsysreq.txt
```

```
$ cat datapaths.ini
[DestinationDirectory]
PROGRAMFILESFOLDER\Mastercam 2027
[SharedDefaultsFolder]
PUBLICDOCUMENTS\Shared Mastercam 2027
```

```
$ cat ProductCodes.dat
ProDrill {4DBC2C37-…}  Onshape {9F079DB3-…}  languagepack_mastercam {C253C79A-…}
Updater {1E59AE7A-…}   MastercamLicensing {6FCF92EF-…}  AutomatedTesting {FEE52672-…}
Mastercam {E3A7A159-C187-44D3-93E8-5EF961F4E0DD}  SDK {3CD7F1B7-…}  EverPath {D6A97C1A-…}
```

So `datapaths.ini` supplies the destination roots:
`%ProgramFiles%\Mastercam 2027` and `%PUBLIC%\Documents\Shared Mastercam 2027`. These agree with the
shipped Administrator Guide (see §4/§5).

---

## 2. The MSI — `mastercam/Mastercam_Installer.msi` (1,188,374,016 bytes)

```
$ msiinfo suminfo Mastercam_Installer.msi
Title: Installation database
Subject: MASTER~3|Mastercam
Author: CNC Software, LLC
Template: AMD64;0,2052,1028,1029,1033,1035,1036,1031,1040,1041,1042,1045,1046,3082,1053,1055
Last author: InstallShield
Created / Last saved: Fri Jun  5 20:59:32 2026
Version: 300 (12c)
Security: 1 (1)
Application: InstallShield® 2024 - Professional Edition 30
```

Identity (`msiinfo export … Property | grep -E '^(Product…)`):

```
ProductName      Mastercam 2027
ProductVersion   29.0.10172.0
Manufacturer     CNC Software, LLC
ProductLanguage  1033
ProductCode      {E3A7A159-C187-44D3-93E8-5EF961F4E0DD}     ← matches ProductCodes.dat "Mastercam"
UpgradeCode      {B6D1AAFC-5EB8-4859-ABB8-AE9489F6FCC4}
ALLUSERS         1
SetupType        Typical
INSTALLLEVEL     100
CNC_UNIT_TYPE    I
```

Package is **AMD64 only** (Template `AMD64;…`) and **signed**:
`7z l Mastercam_Installer.msi` lists `[5]DigitalSignature` (12,139 B),
`MsiDigitalCertificate.ReleaseCertificate1` (1,988 B) and `[5]MsiDigitalSignatureEx` (32 B).

`msiinfo tables` → 88 tables including the InstallShield set
(`ISComponentExtended`, `ISCustomActionReference`, `ISSetupFile`, `ISLockPermissions`,
`ISDRMFileAttribute`, …) plus `MsiAssembly`, `MsiDigitalCertificate`, `MsiPatchCertificate`.

### Cabinets / media

```
$ msiinfo export … Media
1  2617  1  #Data1.cab   DISK1
2  3734  1  #Data11.cab  DISK1
```
Both cabinets are **embedded streams** inside the MSI:

```
$ 7z l Mastercam_Installer.msi | grep -i cab
  524537360  Data11.cab
  629145600  Data1.cab
```

`msiinfo export … File | wc -l` → **3734 files**, total **3,331,433,571 bytes**
(sum of the `FileSize` column of the File table); `Directory` = 851 rows, `Component` = 1141 rows.

### Features

```
$ msiinfo export … Feature
Feature                     Parent                Title
Mastercam                   (root)                MASTER~3|Mastercam
MachSim                     Mastercam             MachSim SubFolders and Files
ATPComponents               Mastercam             ATP Components
Apps                        Mastercam             APPS Components
AutodeskInventorAddins      Mastercam             MCInventor Addin Components
CHooks                      Mastercam             CHooks Components
CimcoEditorComponents       Mastercam             Cimco Editor Components
CommonSupportFiles          Mastercam             Common Support Files
  LegacyDependencies        CommonSupportFiles    Legacy Dependencies
  Redistributables          CommonSupportFiles    Redistributables
  SharedDlls                CommonSupportFiles    Shared Dlls components
CrashService                Mastercam             Crash Service
Extensions                  Mastercam             Mastercam Extensions Components
ImportExport                Mastercam             Import Export Components
ManagedUI                   Mastercam             ManagedUI Components
PowerSurface                Mastercam             PowerSurface Components
RegistryComponents          Mastercam             Common Registry Components
Simulator                   Mastercam             Simulator Components
UninstallFeatureMCAM        Mastercam             Add/Remove Programs Entry
```
All Level 1 → a default (`INSTALLLEVEL=100`) install installs everything.

### Directories (install paths)

```
$ msiinfo export … Directory | grep -E '^(TARGETDIR|ProgramFiles64Folder|MCAM|INSTALLDIR|COMMON|SHAREDDEFAULTS|USERDEFAULTS|CommonFiles64Folder|COMMON64MASTERCAM)'
TARGETDIR             (root)               SourceDir
ProgramFiles64Folder  TARGETDIR            .:Prog64~1|Program Files 64
MCAM                  ProgramFiles64Folder mcam
INSTALLDIR            MCAM                 .
COMMON                INSTALLDIR           common
SHAREDDEFAULTS        COMMON               SHARED~1|SharedDefaults
USERDEFAULTS          COMMON               USERDE~1|UserDefaults
CommonFiles64Folder   TARGETDIR            .:Common64
COMMON64MASTERCAM     CommonFiles64Folder  MASTER~1|Mastercam
```

Resolving `File ⇄ Component ⇄ Directory` (python join of the three exported tables) gives the
MSI's **default** program root `SourceDir\Program Files 64\mcam\.` — i.e.
`C:\Program Files\mcam`. That default is overridden at runtime: `INSTALLDIR` and
`SHAREDDEFAULTS` are both listed in `SecureCustomProperties` (Property export), and the bootstrapper
feeds them from `datapaths.ini`, which names **`Mastercam 2027`** (see §1, §5). The shipped
Administrator Guide confirms the real paths (§4).

Biggest payload directories (same python join, summed per directory):

| bytes | directory (relative to INSTALLDIR = `C:\Program Files\Mastercam 2027`) |
|---|---|
| 1,031,163,612 | `simulator\` |
| 741,252,224 | `.` (root) |
| 142,379,862 | `common\SharedDefaults\Mill Turn\machines\` |
| 142,220,080 | `importexport\` |
| 141,178,493 | `ManagedUI\` |
| 89,010,632 | `common\SharedDefaults\Mill Turn\tools\` |
| 85,176,540 | `common\reports\` |
| 80,649,250 | `Extensions\` |
| 79,806,440 | `common\Editors\CIMCOEdit\Dll\` |

### Main application executables / install paths

```
$ msiinfo export … File   (joined against Component/Directory)
     226,136  C:\Program Files\Mastercam 2027\Mastercam.exe
  11,815,768  C:\Program Files\Mastercam 2027\MastercamLauncher.exe
  10,971,480  C:\Program Files\Mastercam 2027\McamAdvConfig.exe
      38,744  C:\Program Files\Mastercam 2027\common\AcadData\InventorDrawingConverter.exe
     106,840  C:\Program Files\Mastercam 2027\Cnc.Math.GridCompute.Server.Windows.exe
     194,904  C:\Program Files\Mastercam 2027\MCLogr.exe
   1,097,560  C:\Program Files\Mastercam 2027\common\reports\ActiveReports_Viewer.exe
     359,768  C:\Program Files\Mastercam 2027\Extensions\CodeExpert.exe
   2,025,304  C:\Program Files\Common Files\Mastercam\McamVersionSelector.exe
   1,321,304  C:\Program Files\Mastercam 2027\crashservice\crashpad_handler.exe
```

The **user-facing entry point is `MastercamLauncher.exe`** (it is the licence-checking launcher;
`Mastercam.exe` is a 226 KB MFC stub that only imports `Mastercam.dll` — see §3).

### Custom actions (InstallShield)

```
$ msiinfo export … CustomAction
StartCodeMeterService / StartCodeMeterServiceOnRollback / StopCodeMeterService   → ISSetup.dll f29/f34/f15
RegisterMastercamFiles / UnregisterMastercamFiles            → ISSetup.dll f33/f20  (3073 = deferred)
RunNGEN / UninstallNGEN                                      → ISSetup.dll f19/f30  (1025)
ISJITCompileActionAtInstall → 1138  ISJITNGENPROPERTY  /nologo /silent "[#codeexpert.exe]"
ISJITCompileActionAtUnInstall → 1138  ISJITNGENPROPERTY /nologo /silent /delete "[#codeexpert.exe]"
LaunchBatchFile  → ISSetup.dll f7
SetInstallDirectory / SetSharedDefaultsProperty / SetReleaseName → ISSetup.dll f3/f8/f10
ISSetupFilesExtract (257/ISSetupFilesHelper, seq 23) ; ISLockPermissions* ; SetAllUsers.dll
ISPreventDowngrade ; SxsInstallCA (SxsUninstallCA)
```
Install order highlights (`msiinfo export … InstallExecuteSequence`):
`ISSetupFilesExtract@23 … SetInstallDirectory@1026 … StopCodeMeterService@1300 …
SetSharedDefaultsProperty … RunNGEN@4180 … RegisterMastercamFiles@6445 … StartCodeMeterService@6604
… LaunchBatchFile@6607`.

Launch condition (`msiinfo export … LaunchCondition`):
```
(Not Version9X) And (Not VersionNT=400) And … (Not (VersionNT=600 And (MsiNTProductType=1)))
  → "The operating system is not adequate for running [ProductName] [RELEASE_CYCLE]."
```
i.e. requires **Windows 7 or newer** (excluding XP/2003 and Vista Home Basic).

`MsiAssembly` installs ~20 .NET assemblies into the **GAC** (`CrashServiceManaged.dll`,
`Sentry_Managed.dll`, `ActiveReports_Common.dll`, `BouncyCastle.Crypto.dll`,
`DocumentFormat.OpenXml.dll`, `NETHook3_0.dll`, `NETAppStaticAPI.dll`, `RestApi.dll`,
`IOF.MC.dll`, `MCOReaderCLR.DLL`, …).

`Registry` (912 rows) mostly registers **VC80/VC90 SxS** manifests under
`SOFTWARE\Microsoft\Windows\CurrentVersion\SideBySide\Installations\amd64_Microsoft.VC80.*` /
`*.VC90.*` → the MSI carries legacy MSVC 2005/2008 runtimes itself.

### Language transforms (`mastercam/*.mst`, 15 files)

```
$ msiinfo suminfo 1033.mst
Subject: MASTER~3|Mastercam   Template: AMD64;0,2052,1028,1029,1033,1035,1036,1031,1040,1041,
                                              1042,1045,1046,3082,1053,1055
$ 7z l 1041.mst
  !_StringData   1,884,643     ← localized UI strings
  ISSetupFile.SetupFile2  1,199,960
  !Property      (4 bytes, empty)
```
The 15 file names are exactly the 15 LCIDs in the MSI `Template`. Each transform carries a large
`!_StringData` and an **empty** `!Property` stream → they are **UI/localization transforms**
(selected with `TRANSFORMS=<lcid>.mst`), not feature/behaviour transforms.

---

## 3. Main application stack

`file` + `objdump -p` on the central binaries (extracted from the cabinets by their File-table keys):

| file (size) | `file` | CLR | notable imports |
|---|---|---|---|
| `Mastercam.exe` (226,136) | PE32+ GUI x86-64 | no | `Mastercam.dll`, `mfc140u.dll`, `MSVCP140/VCRUNTIME140*`, ucrt api-sets |
| `Mastercam.dll` (16,249,176) | PE32+ DLL x86-64 | no | **`OPENGL32.dll`, `glew64.dll`**, `Cnc.Modules.Core*`, `Cnc.Utilities.Core*`, `gaf*.dll`, `JobSetupCore.dll`, `WININET`, `CRYPT32` |
| `MastercamLauncher.exe` (11,815,768) | PE32+ GUI x86-64 | no | **`WIBUCM64.dll`**, `Cnc.Utilities.Core.Windows.dll` |
| `McamAdvConfig.exe` (10,971,480) | PE32+ GUI x86-64 | no | `XmlLite.dll`, `Cnc.Utilities.Core.Windows.dll` |
| `MCCore.dll` (26,814,296) | PE32+ DLL x86-64 | no | **`OPENGL32.dll`, `GLU32.dll`**, `MCCAD/MCMill/MCLathe/MCMultiax/MCPost/MCMachineDef…`, `Mastercam.dll`, `TlCore.dll` |
| `TLCore.dll` (48,422,744) | PE32+ DLL x86-64 | no | `mfc140u`, `Cnc.Tool.Core.dll`, `Cnc.Math.*` |
| `pskernel.dll` (72,927,760) | PE32+ DLL x86-64 | no | MSVC 14 CRT only — **Siemens Parasolid 38.00.185** (`strings -el` version) |
| `MCDatakit.dll` (78,196,568) | PE32+ DLL x86-64 | no | `PSKERNEL.dll`, `psbodyshop.dll`, `BCGCBPRO3220u143.dll`, `MCCore.dll` |
| `McAutoCAD.dll` (54,460,248) | PE32+ DLL x86-64 | no | `MCCAD.dll`, `MCGeomSld.dll`, `bcrypt.dll`, `ncrypt.dll`, `mfc140u` |
| `mwInterop.dll` (116,179,040) | PE32+ CUI x86-64 **Mono/.Net assembly** | **yes** | **`mscoree.dll`, `OPENGL32.dll`, `GLU32.dll`, `d3d9.dll`**, `mfc140u` (mixed C++/CLI, ModuleWorks "CLI Wrapper") |
| `machsim.dll` (31,482,976) | PE32+ DLL x86-64 | no | Mastercam engines + `mwMSim*`, `mfc140u`, `bcrypt`, `IPHLPAPI` |
| `mwcncsim.dll` (29,334,624) | PE32+ DLL x86-64 | no | `mwVerifier.dll`, `WS2_32`, `bcrypt`, `VCOMP140.DLL` (OpenMP) |
| `glew64.dll` (344,920) | PE32+ DLL x86-64 | no | `OPENGL32.dll` (GLEW 1.7.0.0) |
| `ManagedUI.Interop.dll` (5,643,096) | PE32+ GUI x64 .NET **mixed** | **yes** | `ijwhost.dll`, `mscoree` path |
| `ManagedUI.Controllers.dll` (849,752) | PE32+ GUI x64 .NET mixed | **yes** | `ijwhost.dll` |
| `ManagedUI.MyMastercam.dll` (822,616) | PE32 **i386** .NET (AnyCPU, imports only `mscoree`) | **yes** | `mscoree.dll` |

### .NET vs native — it is a **mix**

* Native C++ (MFC 14 / MSVC 2022) core: `Mastercam.exe/.dll`, `MCCore.dll`, `TLCore.dll`,
  `MCDatakit.dll`, `McAutoCAD.dll`, all `mw*` simulator DLLs, `machsim.dll`, `mwcncsim.dll`.
* C++/CLI mixed-mode: `mwInterop.dll`, `ManagedUI.Interop.dll`, `ManagedUI.Controllers.dll`
  (both import `ijwhost.dll` — the .NET host shim).
* Pure IL/WPF: the whole `ManagedUI` tree (~80 assemblies, e.g. `MCCAD.ViewModels.dll`
  15.6 MB, `MCCore.UI.dll`, `MCTool.UI.dll`), plus `NETHook3_0.dll`, `CodeExpert.exe`,
  `ActiveReports*`, Roslyn (`Microsoft.CodeAnalysis*.dll`), `BouncyCastle.Crypto.dll`.

`ManagedUI` targets **.NET 10**, evidenced by its shipped `*.runtimeconfig.json`:

```
$ 7z e … Data1.cab 'crashservicemanaged.runtimec' && cat crashservicemanaged.runtimec
{ "runtimeOptions": { "tfm": "net10.0",
    "frameworks": [ { "name": "Microsoft.NETCore.App",       "version": "10.0.0" },
                    { "name": "Microsoft.WindowsDesktop.App", "version": "10.0.0" } ] } }
```

A `.NET 10 Desktop Runtime` is **not bundled** — `grep -iE 'hostfxr|coreclr|hostpolicy|clrjit'`
over the File table finds nothing; only the shim `ijwhost.dll` (10.0.25.52411) is shipped.
The installer ships the classic **.NET Framework 4.8** offline installer
(`ndp48-x86-x64-allos-enu.exe`, `Microsoft .NET Framework 4.8 Setup`,
`FileVersion 4.8.4115.0`) — this covers the GAC assemblies and `RunNGEN`/`CodeExpert.exe`.
[INFERENCE] .NET 10 Desktop Runtime must be supplied separately (the installer does not include it),
and it is required to run the ManagedUI/WPF layer.

### Browser embedding — **WebView2** (not CEF)

```
$ grep -iE 'webview|cef|chrome' cablist.txt
  microsoft.web.webview2.core.1    = File key "Microsoft.Web.WebView2.Core.dll.ManagedUI"   v1.0.2849.39
  microsoft.web.webview2.wpf.d1    = File key "Microsoft.Web.WebView2.Wpf.dll.ManagedUI"    v1.0.2849.39
  webview2loader.dll1              = File key "WebView2Loader.dll.ManagedUI"                v1.0.2849.39
```
No `libcef.dll`, `chrome_elf.dll`, `msedgewebview2.exe` or WebView2 *runtime* is present
(`grep -iE 'libcef|cef|chrome_elf|msedgewebview2|EdgeUpdate'` → nothing). [INFERENCE] the
**Microsoft Edge WebView2 Evergreen Runtime** must be installed on the machine for the
"My Mastercam" web panel; only the loader + managed wrapper ship in the MSI.

### Graphics APIs

* **OpenGL is the primary renderer**: `Mastercam.dll` imports `OPENGL32.dll` + `glew64.dll`;
  `MCCore.dll` imports `OPENGL32.dll` + `GLU32.dll`; `mwInterop.dll` imports
  `OPENGL32.dll` + `GLU32.dll`.
* **D3D9** only: `mwInterop.dll` imports `d3d9.dll`.
* **No** `vulkan-1.dll`, `d3d11.dll`, `d3d12.dll`, `dxgi.dll` or `d3dcompiler_*`
  (`grep -iE 'vulkan|d3d11|d3d12|dxgi|d3dcompiler|libcef|chrome_elf|nvapi' cablist.txt` → empty).
* GPU requirement: a GL 3.x-capable driver (GLEW 1.7 loads modern extensions); software
  rendering is unlikely to be sufficient for the simulator.
* Crash reporting: **Sentry + Crashpad** (`sentry.dll` 5.16.2.0 native,
  `crashpad_handler.exe` 0.11.3.0, `CrashService.dll`, `CrashServiceManaged.dll`).

---

## 4. Licensing

### Shipped components

| component | identity / evidence |
|---|---|
| `SetupPrerequisites/CodeMeterRuntime64.msi` (195 MB) | `msiinfo suminfo` → Author **WIBU-SYSTEMS AG**, Subject *"CodeMeter Runtime Installer"*, ProductName **`CodeMeter Runtime Kit v8.40a`**, ProductVersion `8.40.7120.501`, built with **WiX Toolset 3.14.1.8722**, Template `x64;1033,1031,1036,1040,1034,1041,2052,1049` |
| `SetupPrerequisites/MastercamLicensing/MastercamLicensingSetup.exe` (460.8 MB) | `file` → PE32 GUI i386; `7z l` Comment → `FileDescription: Setup Launcher Unicode`, `ProductName: Mastercam Licensing Utilities`, FileVersion `29.0.10172.0`; `strings -el` → **InstallShield** (`C:\CodeBases\isdev\Src\Runtime\MSI\…\IsSetup.cpp`), embeds **`Mastercam Licensing Utilities.msi`**, supports `cmdlinesilent` |
| `support/NHaspX.exe` (3.75 MB) | PE32 i386; version res → `FileDescription: NetHASP control program`, `ProductName: NHaspX Application`, `FileVersion 29.0.0.0` |
| `support/nethaspserver/lmsetup.exe` (16.8 MB) | PE32 i386; `strings` → `HASP License Manager Installation`; `readme.html` → **HASP License Manager 8.32.5.40 (Aladdin, May 2008)**, installs `C:\Program Files\Aladdin\HASP LM\nhsrvw32.exe`, optionally as a service, cfg `nhsrv.ini` |
| `support/nethaspmonitor/aksmon32_setup.exe` (1.8 MB) | PE32 i386 — Aladdin "AKS Monitor" (per AdministratorGuide §License Monitoring) |
| `support/nethasp.ini` | NetHASP client config template (IPX / NetBIOS / TCP-IP keywords) |

### Services / drivers installed by CodeMeter

```
$ msiinfo export CodeMeterRuntime64.msi ServiceInstall
CodeMeter64…   CodeMeter.exe   "CodeMeter Runtime Server"  ServiceType=16  StartType=2 (auto)
               Dependencies=[CM_WINMGMT_RUNNING][~][CM_TCPIP_RUNNING][~][~]
SI_CmWebAdmin_64… CmWebAdmin.exe  "CmWebAdmin"  ServiceType=16  StartType=2  as NT AUTHORITY\LocalService

$ msiinfo export … ServiceControl → Start/Stop for CodeMeter.exe, CmWebAdmin.exe
$ msiinfo export … CustomAction  → WixFirewallCA (firewall exceptions), WixUI*
$ msiinfo export … Registry | grep WIBU-SYSTEMS
SOFTWARE\WIBU-SYSTEMS\CodeMeter\Server\CurrentVersion  IsNetworkServer / HTTP\RemoteRead
Windows shell extension: CmRmtAct32.dll, rundll32 … ,CmShellGetRemoteContext "%1"
$ msiinfo export … Directory | grep -i codemeter
APPLICATIONFOLDER = ProgramFiles64Folder\CodeMeter  (+ Runtime\), CommonAppData\CodeMeter\{CmAct,CmCloud,Logs,Backup}
```
* Install path `C:\Program Files\CodeMeter` (`Runtime\`), plus `%ProgramData%\CodeMeter`.
* **No `.sys` driver file is in the File table** (`grep -iE '\.sys'` → empty) → the kernel driver
  (WibuCM) is installed/extracted by `CodeMeter.exe` itself when the service starts.
  [INFERENCE, but standard for CodeMeter 8.x — `CodeMeter.exe` is 51,652,088 B.]
* CodeMeter MSI guard: `CA_OSBelowWinVerX  NOT (Installed OR (VersionNT=603 AND OS_CURRENTBUILD>9600) OR ALLOW_BELOW)`
  → refuses to install below **Windows 8.1** unless `ALLOW_BELOW=1`.
  `ALLUSERS=2` (per-machine if elevated, else per-user).

### What the licence actually is

The shipped **Administrator Guide** (`support/resources/en/documentation/mastercam/AdministratorGuide.pdf`,
read via the `read` PDF extractor) states:

> "Mastercam 2027 uses one of three license types to run: **HASP, NetHASP, or software**. HASPs and
> NetHASPs are hardware licenses … The software license is digital and is managed by **CodeMeter**."
> Installation locations: `C:\Program Files\Mastercam 2027`, `C:\Program Files\Common Files\Mastercam`,
> `C:\Users\Public\Public Documents\Shared Mastercam 2027`.
> NetHASP server program: `C:\windows\sysWOW64\nhsrvice.exe`, firewall **port 475**.
> Error text: "No Mastercam license found." / "SIM Not Found".

The launcher contains the licence plumbing (`strings -a MastercamLauncher.exe`):
`?AVCodeMeterInterface@@`, `?AVCodeMeterIo@@`, `?AVHaspIOHardwareLayer@@`, `?AVHaspIo@@`,
`?AVNetHaspIo@@`, `?AVMcamLicense@@`, `?AVAddOnLicenseChecker@@`, and embedded XML
(`<hasp type="HASP-HL"/>`, `<license_manager hostname="localhost">`).

### Start vs. licensed

* **To start** the launcher: `MastercamLauncher.exe` **statically imports `WIBUCM64.dll`**
  (`objdump -p`), so the **CodeMeter runtime must be installed before the launcher can even load**.
  Beyond that: VC++ 2022 CRT (x64), .NET 4.8, .NET 10 Desktop (ManagedUI), a GL driver,
  and (for the panel) the WebView2 runtime.
* **To be licensed**: either a hardware HASP/NetHASP (kernel HASP driver + `nhsrvice.exe` for
  network) **or** a CodeMeter software licence container (service running, `.WibuCmRaU` imported).
  Without a licence Mastercam starts, fails its licence check, prints "No Mastercam license found."
  and exits. The MSI itself only *starts the CodeMeter service*
  (`StartCodeMeterService` custom action) — it does **not** activate a licence.

---

## 5. Unattended install recipe (ranked)

All paths are relative to the media root. `%M%` = `Z:\run\media\asdf\Windows\mastercam-media`
(the extracted payload; `setup.exe` runs `<dir>\mastercam\Mastercam_Installer.msi`).

### Rank 1 — bypass the frontend, drive the MSI directly (most controllable)

The MSI is a plain InstallShield MSI and the bootstrapper itself invokes
`msiexec.exe /i "<msi>" TRANSFORMS="…"` with the properties below (string literals in `setup.exe`).
Call Wine's msiexec directly:

```bash
PT="Z:\\run\\media\\asdf\\Windows\\mastercam-media"
wine msiexec /i "$PT\\mastercam\\Mastercam_Installer.msi" \
     TRANSFORMS="$PT\\mastercam\\1033.mst" \
     INSTALLDIR="C:\\Program Files\\Mastercam 2027" \
     SHAREDDEFAULTS="C:\\Users\\Public\\Documents\\Shared Mastercam 2027" \
     CNC_UNIT_TYPE=I CNC_INSTALL_MACHSIM=Y \
     CNC_INSTALL_CORE_MACHINES_AND_POSTS=Y CNC_AUS_AUTOCHECK=1 \
     REBOOT=ReallySuppress /qn /l*v C:\\mc-install.log
```
Reasoning: `INSTALLDIR`/`SHAREDDEFAULTS` are in `SecureCustomProperties` (so they are settable);
`1033.mst` is the en-US UI transform matching `ProductLanguage=1033`; all features are Level 1 so no
`ADDLOCAL` is needed. `RunNGEN` (`ISJITCompileActionAtInstall ... /nologo /silent`) and the
`ISSetup.dll` custom actions (InstallShield helper DLLs are embedded in the `Binary` table) must
work under Wine's msiexec.

### Rank 2 — the frontend's own silent mode

`setup.exe` contains `silent` / `Running frontend in silent mode.` and a parameter parser
(`ParseParam: Cannot find logpath`, `. Command Line:`, `Additional parameters were passed:`).
It reads `\datapaths.ini` + `support\mcim.ini` for destinations/options, then builds
`msiexec.exe /i "…" TRANSFORMS="…"` and launches the InstallShield prerequisites with
`/S /v"… /qn"`. Because the exact switch token is not present as a literal, try, in order:

```bash
wine setup.exe silent=1            # first guess: named param, mirrors logpath/targetdir parser
wine setup.exe /s                  # InstallShield-style; only if the above is ignored
```
Reasoning is weaker here (undocumented), which is why it is ranked below Rank 1.

### Rank 3 — individual prerequisites (needed by either of the above)

```bash
# .NET Framework 4.8                       (string literal in setup.exe: "/q /norestart")
wine ndp48-x86-x64-allos-enu.exe /q /norestart
# VC++ 2022 redistributables (x64, x86)    (same "/q /norestart")
wine VC2022/VC_redist.x64.exe /q /norestart
wine VC2022/VC_redist.x86.exe /q /norestart
# msxml6 (x64 + x86), standard MSI
wine msiexec /i msxml6_x64.msi /qn ; wine msiexec /i msxml6_x86.msi /qn
# CodeMeter runtime 8.40a  (ALLOW_BELOW needed if Wine's winver < Win8.1)
wine msiexec /i CodeMeterRuntime64.msi ALLOW_BELOW=1 /qn /l*v C:\\cm.log
# Mastercam Licensing Utilities (InstallShield launcher)
wine MastercamLicensing/MastercamLicensingSetup.exe /S /v"REBOOT=ReallySuppress /L*V \"C:\\lic.log\" /qn"
```
Exact silent lines are the literals the frontend itself uses:
`/clone_wait /S /v"REBOOT=ReallySuppress /L*V "%s" /qn"` and `/q /norestart`.

Verified order is enforced by the frontend (strings): CodeMeter / Licensing / VC2022 / ndp48 /
msxml6 are run from `\SetupPrerequisites\` **before** the main MSI.

---

## 6. Wine-compatibility notes

1. **Architecture**: MSI is **AMD64-only**; but several prerequisites are **32-bit**
   (`MastercamLicensingSetup.exe`, `NHaspX.exe`, `lmsetup.exe`, `aksmon32_setup.exe`,
   `uninstaller.exe`, `mastercam2027-updater.exe`, `ndp48` box stub, `VC_redist.x86.exe`).
   A **WoW64-capable prefix** (32+64) is therefore required, and Wine's 32-bit msiexec must work.
2. **Elevation**: `setup.exe` embeds `requestedExecutionLevel level="requireAdministrator"`.
   Use an admin/`winecfg`-Windows-7+ prefix.
3. **Windows version reported**: MSI `LaunchCondition` requires ≥ Win7; CodeMeter requires
   ≥ Win8.1 (`CA_OSBelowWinVerX`) → run Wine at Win10 (default) or pass `ALLOW_BELOW=1`.
4. **Windows Installer version / signing**: `CodeMeterRuntime64.msi` has
   `CA_ErrOldMsiOnSystem` requiring MSI ≥ 300 (i.e. Windows Installer 3.0) — Wine reports a modern
   version, fine. The Mastercam MSI is **signed** (`[5]DigitalSignature`,
   `MsiDigitalCertificate.ReleaseCertificate1`) — Wine ignores signature validation, so no problem,
   but a *strict* installer check on real Windows would need the release cert present.
5. **.NET**: three distinct requirements — classic **.NET Framework 4.8** (`ndp48`, plus
   `RunNGEN`/`CodeExpert.exe` and ~20 GAC assemblies via `MsiAssembly`; Wine's GAC support is
   partial), **.NET 10 Desktop Runtime** for the `ManagedUI` WPF layer (net10.0 runtimeconfig,
   **not bundled**), and C++/CLI host `ijwhost.dll`. Any .NET work by the MSI (ngen, assembly
   install) is a likely friction point.
6. **Kernel drivers cannot load under Wine** — this is the big licensing blocker:
   * CodeMeter: the `CodeMeter.exe` service installs/loads a **WibuCM kernel driver** at start
     (no `.sys` in the MSI). The Windows service may start in user mode, but dongle access and
     device binding will fail without the driver. Software licences (`.WibuCmRaU` container) also
     depend on the running CodeMeter service.
   * HASP/NetHASP: `lmsetup.exe` installs the Aladdin HASP driver / `nhsrvice.exe` service —
     likewise non-functional without driver support.
   [INFERENCE] consider a **network licence server on a real Windows host** and a client-side
   `nethasp.ini` pointing at it (AdministratorGuide §Using Mastercam Licenses Remotely) as the most
   Wine-friendly licensing path, or a CodeMeter network server.
7. **GPU / graphics**: OpenGL 3.x via GLEW + D3D9 (no Vulkan/D3D11/12/DXGI). Needs a working
   GL driver in the prefix; `Mastercam.dll` imports `glew64.dll` directly.
8. **WebView2**: only the loader/wrapper ship — the **Edge WebView2 Evergreen Runtime** must be
   present for the "My Mastercam" panel. Installing it under Wine is another known-hard item.
9. **Services/firewall**: CodeMeter installs two auto-start services + firewall rules
   (`WixFirewallCA`). Wine's service manager can create the services, but the firewall CA is a no-op.
10. **Install size**: ~3.33 GB of files (`File` table total), dominated by the ModuleWorks
    `simulator\` tree (1.03 GB) — budget disk and a large Wine prefix.
11. **32-bit managed assembly**: `ManagedUI.MyMastercam.dll` is PE32/i386 IL (imports only
    `mscoree.dll`) — it is an AnyCPU assembly, so it loads in the 64-bit .NET runtime; no separate
    32-bit .NET is implied by it alone.
