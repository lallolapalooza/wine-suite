# Tableau Desktop 2026.2.3 — install stack and Windows API surface

Recon by `TableauStack` (2026-10-04). All claims carry the command that produced them; anything not directly
observed is tagged **INFERENCE**. Raw dumps live beside this file:

- `recon/msi_tables/*.idt` — every MSI table exported with `msiinfo export app/tableau_exe/a1 <table>`
- `recon/msi_file_summary.txt` — File-table roll-up
- `recon/imports_raw.json` — pefile import sets for 26 key PEs
- `recon/bin_listing.txt` — `ls` of the product `bin/`
- `app/msi_extract/tableau-26.2.1954-licensing/` — 6 licensing binaries extracted with `7z x`

---

## 1. Container layout (WiX Burn bundle)

The installer `TableauDesktop-64bit-2026-2-3.exe` is a WiX Burn/`wixstdba` bundle. Its embedded UX container was
extracted to `app/tableau_burn.cab`; the Burn manifest is the cab member `0` (XML, 27,570 B).

```
$ 7z l app/tableau_burn.cab
Type = Cab / Method = MSZip / Physical Size = 593235 / Tail Size = 742760101
25 files: "0" (XML BurnManifest) + u0..u23 (UX resources, 1,543,634 B)
```

```
$ python3 -c "…parse app/tableau_ux/0…"        # BurnManifest
<Container Id="WixAttachedContainer" FileSize="742749502" Attached="yes"
           FilePath="tableau-setup-std-262-tableau-2026-2.26.0912.1023-x64.exe"/>
<MsiPackage Id="Tableau" ... ProductCode="{D5C4243D-E35D-4F26-A837-EDB5C3AA3739}"
            Version="26.2.1954" Size="725159936" InstallSize="2208240220" PerMachine="yes" Vital="yes"/>
<ExePackage Id="VC2022Redist" ... Size="25635768"
            InstallCondition="(NOT VC2022_FOUND) OR (VC2022X64_MAJ_VER < 14 OR (VC2022X64_MAJ_VER = 14 AND VC2022X64_MIN_VER < 44))"
            InstallArguments="/install /quiet /norestart"/>
Payloads: 26  (u0..u23 = UX, a0 = VC redist, a1 = the MSI)
```

So the bundle contains **exactly two packages**:

| package | attached file | bytes | what it is |
|---|---|---|---|
| `Tableau` (MsiPackage, vital) | `app/tableau_exe/a1` | 725,159,936 | the whole product MSI |
| `VC2022Redist` (ExePackage, vital) | `app/tableau_exe/a0` | 25,635,768 | Microsoft Visual C++ 2022 redistributable bootstrapper |

No MsuPackage, no BundlePackage, no chained third-party MSIs. `WixBundleLog` prefix is
`Tableau_2026.2_(20262.26.0912.1023)`. Related-bundle IDs (detect only) are listed in the manifest
(`{E454F01E-…}`, `{DCDDFB38-…}`, …).

**Nested MSIs:** none. `find app/tableau_exe/msi_root -iname '*.msi' -o -iname '*.cab' -o -iname '*.msp'` → empty.
`a1` is itself the one and only MSI (`file app/tableau_exe/a1` → *Composite Document File V2 Document …
MSI Installer, Subject: Tableau 2026.2 (20262.26.0912.1023), Author: Salesforce, Inc, x64;1033*).
`app/tableau_exe/msi_root/` **is** the extraction of `a1` (verified: 5,425 files, 2.1 GB, identical count to
`Media`/`File` table).

---

## 2. MSI inventory

### 2.1 `Tableau 2026.2 (20262.26.0912.1023)` — `app/tableau_exe/a1`

```
$ msiinfo suminfo app/tableau_exe/a1
Title: Installation Database ; Subject: Tableau 2026.2 (20262.26.0912.1023)
Author: Salesforce, Inc ; Template: x64;1033
Application: Windows Installer XML Toolset (3.14.1.8722)
$ msiinfo export app/tableau_exe/a1 Property | grep -E 'Product(Name|Version|Code)|UpgradeCode|Manufacturer'
Manufacturer    Salesforce, Inc
ProductCode     {D5C4243D-E35D-4F26-A837-EDB5C3AA3739}
ProductName     Tableau 2026.2 (20262.26.0912.1023)
ProductVersion  26.2.1954
UpgradeCode    {A4849F71-5147-414E-A210-6D8412A2AE83}
```

| metric | value | evidence |
|---|---|---|
| files | **5,425** | `msiinfo export … File \| wc -l` (5,425 data rows) |
| total file bytes | **2,208,240,220 (2.06 GiB)** | sum of File.FileSize (== manifest `InstallSize`) |
| MSI on disk | 725,159,936 B; internal `cab1.cab` = 720,904,424 B (LZX:21, 1031 blocks) | `7z l -slt app/tableau_exe/a1` |
| directories | 429 | Directory.idt |
| components | 420 | Component.idt |
| features | 1 (`MainApplication`, etc. via FeatureComponents 379 rows) | Feature.idt |
| media | 1 (`#cab1.cab`) | Media.idt |

Largest 15 files (`recon/msi_file_summary.txt`):

| bytes | file |
|---:|---|
| 207,962,976 | `hyperd.exe` (Hyper DB engine) |
| 191,297,810 | `plugin-host-desktop.rcc` (HybridUI Qt resource) |
| 178,978,816 | `GeocodingData.hyper` |
| 162,660,192 | `Qt6WebEngineCore.dll` |
| 132,146,440 | `eps.exe` (Node.js) |
| 124,705,028 | `modules` (JRE `lib/modules` jimage) |
| 86,165,770 | `vizclient-static-assets.rcc` |
| 63,314,718 | `jdbcserver.jar` |
| 50,729,513 | `oauthservice.jar` |
| 44,476,531 | `GeographicSearch.gdb` |
| 38,434,144 | `libGLESv2.dll` (ANGLE) |
| 30,796,640 | `icudt74.dll` |
| 29,749,088 | `docapi.dll` |
| 27,937,622 | `tablangres.rcc` |
| 26,463,072 | `hyperapi.dll` |

Top install directories by size: `bin` 869 MB, `HybridUI` 277 MB, `local\data` 224 MB, `bin\hyper` 208 MB,
`bin\jre\lib` 134 MB, `bin\eps` 132 MB, `bin\swiftshader` 39 MB, `bin\translations\qtwebengine_locales` 37 MB.

### 2.2 `VC2022Redist` — `app/tableau_exe/a0`

```
$ file app/tableau_exe/a0      → PE32 executable (GUI) Intel i386, 6 sections
$ 7z l -slt app/tableau_exe/a0 → FileVersion 14.44.35211.0 ; InternalName setup
$ 7z l app/tableau_exe/a0      → 33 files (u0..u31 + "0"), 25,635,768 B
```
This is the **Microsoft Visual C++ 2022 Redistributable bootstrapper (14.44.35211.0)** that the Burn
`InstallCondition` gates on `VC2022X64_* >= 14.44`. It is the *only* external runtime prerequisite the payload
declares — relevant because Tableau's own MSIs vendor everything else (JRE, Qt, ICU).

---

## 3. Component versions

All version strings come from PE VS_VERSIONINFO, read with `pefile` (`recon/imports_raw.json` companion script).
`7z l -slt` does **not** expose them for these binaries (it printed nothing for `Comment`).

| component | version | evidence string (FileVersion / ProductName) |
|---|---|---|
| Tableau core (`tableau.exe`, `tabui.dll`, `tabdoc.dll`, `docapi.dll`, `art_cpp.dll`, `atrdiag.exe`) | `20262.26.0912.1023` | FileVersion `20262.26.0912.1023`, ProductName `Tableau 2026.2` |
| **Qt** (`Qt6Core.dll`, `Qt6Gui.dll`, `Qt6Widgets.dll`, `Qt6WebEngineCore.dll`, …) | **6.5.11.0** | `Qt6Core.dll` FileVersion `6.5.11.0`, CompanyName *The Qt Company Ltd.* (`strings -a Qt6Core.dll \| grep -oE 'Qt [0-9.]+'` → `Qt 6.5.11`) |
| **Chromium / QtWebEngine** | **122.0.6261.171** | `strings -a Qt6WebEngineCore.dll \| grep -oE 'Chrome/[0-9.]+'` → `Chrome/122.0.6261.171` |
| QtWebEngineProcess | 6.5.11.0 | `QtWebEngineProcess.exe` FileVersion |
| **JRE / Java** | **Azul Zulu 17.0.18+1 (OpenJDK 17, JDK)** | `jre/bin/server/jvm.dll` ProductName `Azul Zulu 17`, FileVersion `17.0.18.0.101`, CompanyName *Azul Systems Inc.* |
| **Node.js** (`eps.exe`, the "External Protocol Service") | **22.17.1** | `eps/eps.exe` ProductName `Node.js`, FileVersion `22.17.1`, OriginalFilename `node.exe` |
| **Hyper** (`hyper/hyperd.exe`, `hyperapi.dll`) | **2026.2.24949.r11593467** | ProductName `Tableau Hyper Database Engine`, FileVersion `2026.2.24949.r11593467` |
| **FlexNet Publisher** licensing | **11.19.4.1 build 291070** | `tabfnp.dll`/`FNP_Act_Installer.dll` ProductVersion `11.19.4.1 build 291070`, CompanyName *Flexera* |
| ANGLE (`libEGL.dll`, `libGLESv2.dll`) | 5.15.18.0 | FileVersion `5.15.18.0` |
| `d3dcompiler_47.dll` | 6.3.9600.16384 (winblue) | ProductName `Microsoft® Windows® OS`; **i386** (32-bit, used by ANGLE) |
| ICU | 74 (`icudt74.dll`, `icuin74.dll`, `icuuc74.dll`) | filenames + 30.8 MB data file |
| Boost | 1.8x (`boost_*-mt-x64.dll`) | filenames only |
| `.NET` assemblies | **NONE** | scan of all 405 PEs under the product: 0 have a CLR/COM descriptor |
| Python | **NONE** | no `python*.exe/dll`, no `libpython*` in the payload |
| CEF | **NONE** (`libcef.dll`, `chrome_elf.dll` absent) | `find` over the tree |
| Browser engines present | QtWebEngine (Chromium 122) **and** ANGLE + a software GL fallback: `bin/swiftshader/{libEGL,libGLESv2}.dll` (38.7 MB total; no Vulkan-loader file) | `ls bin/swiftshader` |

Note: no WebView2 dependency is shipped; the HybridUI (`plugin-host-desktop.rcc`, `vizclient-static-assets.rcc`)
runs on the bundled QtWebEngine. Embedded JRE is a full **JDK 17** (`jre/bin/java.exe`, `jre/lib/modules`).

---

## 4. Licensing stack

Tableau uses **two** independent licensing layers: Flexera **FlexNet Publisher 11.19.4.1** (activation /
concurrent "ATR" licensing) plus Tableau's own "ATR" (Automatic Transactional Registration / offline licensing)
settings.

### 4.1 Binaries (all x64)

| file | size | role | evidence string |
|---|---:|---|---|
| `bin/tabfnp.dll` | 10,066,784 | main FlexNet client — activation, machine-ID, license checkout | ProductName `FlexNet Publisher (64 bit)`, ProductVersion `11.19.4.1 build 291070` |
| `bin/fnpcommssoap.dll` | 501,032 | FlexNet SOAP/HTTP activation transport | FileDescription `FLEXnet Publisher Communication SOAP Module` |
| `bin/custactutil.exe` | 1,779,552 | MSI custom-action host that drives FlexNet | installed by component `CP_Main_licensedebugger` |
| `bin/custactutil_libFNP.dll` | 10,066,784 | FLEXnet Secure Activation Module (custom-action lib) | FileDescription `FLEXnet Secure Activation Module`, InternalName `libFNP.dll` |
| `bin/FNP_Act_Installer.dll` | 4,646,184 | **Activation Licensing Service installer** — embeds `FNPLicensingService.exe` (x86_64) | FileDescription `Activation Licensing Service Installer`; `strings` → `FNPLicensingService64`, `Macrovision Shared\`, PDB `…\_release-Windows-NT4-x86_64-main\FNPLicensingService.exe.pdb` |
| `bin/installanchorservice.exe` | 25,440 | installs/„anchors" the FlexNet service | `<assemblyIdentity … name="FNPLicensingService.exe" …>` |
| `bin/uninstallanchorservice.exe` | 25,440 | removes it | same |

No `lmutil`, no `pubglue`, no `*licen*` standalone DLL, **no `.sys` driver anywhere** (`find … -iname '*.sys'` → empty).

### 4.2 What FlexNet does at runtime (from `strings -a bin/tabfnp.dll`)

```
s_cacheNetIfDataViaIOCTL()   s_cacheNetIfDataViaWMI()   s_getMACAddressFromDevice()
CUMNProvider::readDataFromTS()   CBIOSWMI   CWMI   Attempting to read SMBIOS UUID from WMI....
<MachineIdentifier> <OriginalMachineIdentifier> <UniqueMachineNumber>
C:\ProgramData/FLEXnet        %default%/FLEXnet        libFNP_events.log
```
⇒ machine identity is a composite of **NIC MAC address** (read via raw **IOCTL** *or* **WMI**
`Win32_NetworkAdapter`) and **SMBIOS UUID** from **WMI** `Win32_ComputerSystemProduct`.
**This is the single most Wine-hostile subsystem in the product** (see §6).

### 4.3 Installation of the licensing service (from the MSI tables)

```
CustomAction:
  InstallFlexNetServiceSet…   51 → InstallFlexNetService…   = "[bin]\installanchorservice"    "Tableau Software, LLC" "Tableau 2026.2"
  InstallFlexNetService…      3073 WixCA CAQuietExec64
  UpdateFlexNetServicePermissionsSet… 51 → "[SystemFolder]sc.exe" sdset "flexnet licensing service 64" D:(D;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;NU)(…)
  UninstallFlexNetServiceSet… / Rollback variants similarly
InstallExecuteSequence: InstallFlexNetService @5802 (cond NOT REMOVE); UpdateFlexNetServicePermissions @5803;
                        RollbackFlexNetService @5801; uninstall/rollback sets @1951–1956
```
⇒ **Service installed: `FNPLicensingService64`, display "FlexNet Licensing Service 64"**, launched from
`%CommonProgramFiles%\Macrovision Shared\FLEXnet Publisher\`. Registry probe
`RS_FLEXNET_OTHER_PRODUCT_INSTALLED` = `HKLM\SOFTWARE\Tableau\FlexNetUsers / loom`.

### 4.4 Licensing properties (MSI Property table + Burn variables)

`ACCEPTEULA` (LaunchCondition `ACCEPTEULA="1" OR UILevel=5 OR Installed OR OEM="1"`), `REGISTER`,
`SILENTLYREGISTERUSER`, `SYNCHRONOUSLICENSECHECK`, `ACTIVATE_KEY`, `RECLAIMLICENSE`, `ACTIVATIONSERVER`,
`LBLM`, `ATRENABLED`, `ATRREQUESTEDDURATIONSECONDS`. Custom actions:
`tableau.exe -activate [ACTIVATE_KEY]`, `tableau.exe -register`, `tableau.exe -return all`.
ATR settings live at `HKCU/HKLM\Software\Tableau\ATR` and `…\Tableau 2026.2\Settings`.

---

## 5. Services / drivers / tasks / registry keys the installer creates

**Services** — the MSI has **no `ServiceInstall`/`ServiceControl` tables** (verified: not in
`msiinfo tables`). The only service is created imperatively by the `installanchorservice.exe` custom action:

| entity | name | how |
|---|---|---|
| Service | `FNPLicensingService64` / "FlexNet Licensing Service 64" | `bin\installanchorservice.exe "Tableau Software, LLC" "Tableau 2026.2"`; ACL set by `sc.exe sdset` |

**Drivers:** none. **Scheduled tasks:** none (no `schtasks*`/`ScheduledTask` strings; not in any table).
**Firewall rules:** none. Environment strings: no `Environment` table (nothing exported to `PATH`).

**Registry (Registry table, 167 rows, HKLM/HKCU/HKCR):**

| hive | key | values | component |
|---|---|---|---|
| HKLM | `SOFTWARE\Tableau\Directories` | `Drivers`, `Connectors` | CP_Driverdir / CP_Connectordir |
| HKLM | `Software\Tableau\Tableau 2026.2\Directories` | `Application`, `Help` | app dirs |
| HKLM | `SOFTWARE\Tableau\Tableau 2026.2\AutoUpdate` | `AutoUpdateAllowed` 1/0 | AutoUpdate |
| HKLM | `SOFTWARE\Tableau\Tableau 2026.2\Autosave` | `AutosaveAllowed` | Autosave |
| HKLM | `SOFTWARE\Tableau\Tableau 2026.2\DiscoverPane` | `DiscoverPaneUrl` | |
| HKLM | `SOFTWARE\Tableau\Tableau 2026.2\Samples` | `CustomSamplesDir` | |
| HKLM | `SOFTWARE\Tableau\ReportingServer` | `Server`, `schedulereportInterval` | |
| HKLM | `SOFTWARE\Tableau\Tableau 2026.2\Settings` | `SynchronousLicenseCheck`, `SilentlyRegisterUser` | licensing |
| HKLM | `SOFTWARE\Tableau\ATR` | `ATREnabled`, `ATRRequestedDurationSeconds`, `LBLM`, `LicensingWorkgroupServer` | ATR licensing |
| HKLM | `SOFTWARE\Tableau\FlexNetUsers` | `loom` | FlexNet detection |
| HKLM | `SOFTWARE\Tableau\Tableau 2026.2\Telemetry` | `TelemetryEnabled` 1/0 | |
| HKLM | `SOFTWARE\Tableau\Tableau 2026.2\Crashdump` | `CrashdumpEnabled` | |
| HKLM | `…\Settings\Extensions` | `DisableExtensions`, `DisableNetworkExtensions`, `DisableSandboxExtensions`, `Disable3PTrustedExtensions`, `DisableTabTrustedExtensions` | extension sandbox |
| HKLM | `SOFTWARE\Tableau\Tableau 2026.2\Install` | `DTSC2`, `SMSC2` | |
| HKCR | `.twb/.twbx/.tps/.twb…`, `Tableau.Workbook.2`, `Tableau.PackagedWorkbook.2`, `Tableau.Preferences.2`, `Tableau.Bookmark.2`, `Tableau.Extract.2`, … + `shell\open|print|printto|package` verb commands `"[#tableau.exe]" "%1"` | file associations & verbs |
| HKCR | `tableau`, `twdc`, `tableau-desktop` | `URL:Tableau Protocol` | custom URL protocols |

`InstallExecuteSequence` also ships the **standard MSI service verbs `StartServices`/`StopServices`/
`DeleteServices`**, which are no-ops with no ServiceInstall rows. `APPSEARCH`/`RegLocator` probes:
`RS_WINDOWSBUILDNUM` (`HKLM\…\CurrentVersion\CurrentBuild`), `ATRENABLED`, `ACTIVATIONSERVER`, etc.

---

## 6. Wine-risk API import scan

Method: `python3` + `pefile` (`parse_data_directories()`; includes `DIRECTORY_ENTRY_DELAY_IMPORT`), matching
imported names against a curated risky-API list. Raw sets in `recon/imports_raw.json`.
Equivalent one-liner for a single PE: `objdump -p <pe> | sed -n '/DLL Name/,$p'` (note: for these binaries
objdump prints member names in a 4-column table, `vma <ord> <hint> Name`, so pefile is more reliable).

| file | API | one-line Wine risk |
|---|---|---|
| `bin/tabfnp.dll`, `bin/custactutil*.dll/exe`, `bin/atrdiag.exe` | `DeviceIoControl` (+ `GetVolumeInformationA`, `QueryDosDeviceA`, `DefineDosDeviceA`) | FlexNet reads NIC/disk identity via raw IOCTL on `\\.\` device paths; Wine handles IOCTLs only for CD-ROM/tape (`dlls/ntdll/unix/cdrom.c`), hard-disk `IOCTL_STORAGE_QUERY_PROPERTY`/SMART are unhandled → hostid may come back empty. Falls back to WMI (`s_cacheNetIfDataViaWMI`). |
| `bin/FNP_Act_Installer.dll` | `OpenSCManagerA/OpenServiceA/CreateServiceA/StartServiceA/ControlService/QueryServiceConfigA/QueryServiceStatus/ChangeServiceConfigA/DeleteService` | installs & controls the `FNPLicensingService64` SCM service; Wine's SCM works, but the service binary itself is Windows-only FlexNet code. |
| `bin/tabfnp.dll`, `custactutil*`, `atrdiag.exe` | `CoCreateInstance` + `CoInitializeSecurity` + `CoSetProxyBlanket` (+ `CoInitializeEx`) | WMI/DCOM locality; wbemprox is the target — DCOM security blanket calls are accepted but marshalling of `IWbem*` through Wine must work. |
| `bin/installanchorservice.exe` / CustomAction `sc.exe sdset` | `sc sdset "flexnet licensing service 64" D:(…)` | Wine's `programs/sc/sc.c` implements `sdset` as `FIXME("SdSet command not supported, faking success")` — safe (returns success, does not set the ACL). |
| `bin/tabfnp.dll`, `custactutil*` | `SetupDiGetClassDevsA`, `SetupDiEnumDeviceInfo`, `SetupDiGetDeviceRegistryPropertyA` | enumerating NIC/disk PnP devices for hostid; Wine's setupapi is a partial implementation (devinst.c) and may return an empty device set. |
| `bin/tabfnp.dll`, `custactutil*`, `atrdiag.exe` | `GetAdaptersInfo` (iphlpapi) | MAC enumeration for machine identity; Wine returns host NICs — should work. |
| `bin/tabfnp.dll`, `custactutil*` | `CryptAcquireContextA`, `winspool!OpenPrinterA`/`DocumentPropertiesA`, `shell32!ShellExecuteA`/`SHGetFileInfoA` | capi/printing/shell: Wine has these (winspool is thin); used for env fingerprinting. |
| `Qt6WebEngineCore.dll`, `QtWebEngineProcess.exe` | `EventRegister/EventWrite/EventWriteTransfer/EventUnregister` (advapi32→ntdll ETW) | Wine ntdll `EtwEventRegister` is a stub returning `ERROR_SUCCESS` with a fake handle `0xdeadbeef`; `EventWrite*` are FIXME stubs returning success. Chromium must tolerate this (it does — it logs nothing). |
| `Qt6WebEngineCore.dll`, `libGLESv2.dll` | `CreateDXGIFactory(1)`, `D3D11CreateDevice`, `Direct3DCreate9`, `D3DCompile` | Chromium/ANGLE GPU path. Wine ships `dxgi`/`d3d11`/`d3d9`; software fallback exists (`bin/swiftshader`, bundled `d3dcompiler_47.dll`). Expect SwiftShader/llvmpipe unless a GL/Vulkan driver is present. |
| `Qt6WebEngineCore.dll` | `OpenSCManagerW/OpenServiceW/QueryServiceStatus` | Chromium probing for running services (e.g. update) — informational only. |
| `Qt6WebEngineCore.dll`, `QtWebEngineProcess.exe`, `jre/bin/server/jvm.dll`, `hyperd.exe` | `CreateToolhelp32Snapshot/Process32First(W)/Process32Next(W)` | process enumeration (Chromium child discovery, JVM/Hyper helpers); Wine supports it. (No `NtQuerySystemInformation`/`GetSystemFirmwareTable`/`WerRegister` are imported anywhere in the set — verified against `recon/imports_raw.json`.) |
| `Qt6WebEngineCore.dll`, `hyperd.exe`, `eps.exe` | `CryptProtectData`/`CryptUnprotectData`, `CertOpenStore`/`CertFindCertificateInStore`, `CryptAcquireContextW`, `BCryptOpenAlgorithmProvider` | DPAPI + cert stores. Wine's DPAPI (crypt32) works per-user; cert store is sparse (no machine certs) — Chromium/JRE usually proceed, but TLS client-cert paths may differ. |
| `Qt6WebEngineCore.dll`, `QtWebEngineProcess.exe`, `hyperd.exe`, `jvm.dll` | `OpenProcessToken/GetTokenInformation/AdjustTokenPrivileges/DuplicateTokenEx` | Chromium sandbox token manipulation; Wine tokens are emulated — Chromium's `--no-sandbox` equivalent may be needed. |
| `Qt6WebEngineCore.dll` | `SetupDiEnumDeviceInfo`, `SetupDiGetClassDevsW` | Chromium media-device enumeration; Wine returns an empty set (no cameras) — non-fatal. |
| `hyperd.exe`, `eps.exe`, `Qt6WebEngineCore.dll` | `GetAdaptersAddresses`, `NotifyAddrChange`, `WSAIoctl` | Wine/iphlpapi+ws2_32 implement these; SIO_* secondary-interface ioctls can differ. |
| `hyperd.exe`, `tabsys.dll`, `eps.exe` (`dbghelp`) | `MiniDumpWriteDump` | Wine's dbghelp can write minidumps but quality of stacks is poor; crash-reporting path only. |
| `bin/atrdiag.exe` | `OpenSCManagerA/OpenServiceA/QueryServiceStatus/StartServiceA` | Tableau diagnostic tool inspecting services; read-only. |
| all main binaries | `SetUnhandledExceptionFilter`, `SetErrorMode`, `AddVectoredExceptionHandler` | Wine supports; crash handler path. |
| `jre/bin/server/jvm.dll` | `GetVolumeInformationA`, `CreateToolhelp32Snapshot`, `AdjustTokenPrivileges` | JVM ergonomics/hotspot perf data; Wine OK. |
| `tabsrv.dll`, `tabprotosrv.exe`, `qt*` | `CoInitializeEx` | COM init only (tabsrv is the TabSrv client); low risk. |
| `bin/FNP_Act_Installer.dll` | embedded `FNPLicensingService.exe` | the service binary uses the same FlexNet device/WMI identity code as `tabfnp.dll`; installing it under Wine may succeed while *activation* still fails. |

TPM/secure-crypto note: Wine's `tbs.dll` (`Tbsi_Context_Create`, `Tbsi_GetDeviceInfo`, `GetDeviceIDString`) is a
**stub returning `TBS_E_TPM_NOT_FOUND`**. Nothing in the Tableau payload imports `tbs`, but if FlexNet falls
back to TPM-backed activation it gets no TPM under Wine. **INFERENCE** (no `tbs.dll` in the import sets).

---

## 7. App logging knobs (the diagnostic channel on both platforms)

Evidence from `strings -a` / `strings -el` over `bin/*.dll`, `bin/*.exe` (both ASCII and UTF-16):

| knob | evidence string | meaning |
|---|---|---|
| **Log level** | `An invalid value '%1' was specified for LogLevel. LogLevel reset to 'Info'.` | accepted levels are `Info` (default) / `Debug` / `Trace`-derived; invalid resets to `Info`. |
| **Runtime switch** | `-DLogLevel=%1` | passed on child-process command lines (tabprotosrv / Java / Hyper). Setting it on `tableau.exe` propagates. |
| **Native log config file** | `log_config` … `?NativeLogConfigPath@appoptions@tableau@@YA?AVTString@@XZ` … `-DNativeLogConfigPath=` … `Unable to read native logging configuration file.` | a `log_config` file overrides levels; path overridable with `-DNativeLogConfigPath=`. |
| **Other level knobs** | `DefaultLogLevel`, `ExternalProtocolLogLevel`, `GRPC_STACKTRACE_MINLOGLEVEL`, `?GetLogFileRotateSizeMB`, `?GetMaxBackupLogFileCount`, `SizeBasedRotateAndDeleteFileChannel` | per-subsystem levels + rotation (`TLog`). |
| **Qt/Chromium channel** | `QT_LOGGING_RULES`, `QT_LOGGING_CONF`, `QT_FORCE_STDERR_LOGGING`, `QT_LOGGING_TO_CONSOLE` (from `Qt6Core.dll`); `--remote-debugging-port=` in `Qt6WebEngineCore.dll` | Qt rules env vars work in-process; `--remote-debugging-port` exposes the embedded Chromium DevTools (very useful for the HybridUI). |
| **FlexNet log** | `libFNP_events.log`, `C:\ProgramData\FLEXnet`, `%default%/FLEXnet` | licensing event log + FlexNet state dir. |
| **Log destination** | `My Tableau Repository`, `Tableau needs permission to read the Tableau Repository folder in Documents. Without access, saved workbooks, preferences, samples, and logs aren't available.`, `?GetUserRepositoryDir@AppConfig`, `StartRepositoryConfig@TStartup` | logs live in the user Repository (`%USERPROFILE%\Documents\My Tableau Repository\Logs\`) and in the per-product `%LOCALAPPDATA%\Tableau\Tableau 2026.2\` folder. **INFERENCE** for the exact `%LOCALAPPDATA%` subpath — the path is composed at runtime from `SHGetKnownFolderPath(LOCAL_APPDATA)` + the product name (`Tableau 2026.2` literal present); the strings for `\Tableau\` alone are not in the payload. |
| **Installer log** | Burn `WixBundleLog` prefix `Tableau_2026.2_(20262.26.0912.1023)`; `-DLogLevel` also accepted by Burn-launched children | `/log <file>` on the silent install line. |
| Per-process log files | `log.txt`, `tabprotosrv.txt`, `hyperd.log`, `tdcache.txt` (**INFERENCE** — standard Tableau naming; the literal filenames are not in the payload strings, only the dir-resolution code) | each hosted process writes its own file. |

Practical diagnostic recipe: set `HKCU\Software\Tableau\Tableau 2026.2\Settings\LogLevel`? **not present in the MSI**
(only `SynchronousLicenseCheck`/`SilentlyRegisterUser` are written there) — so use the file/CLI knobs:
`tableau.exe -DLogLevel=Debug`, a `log_config` file, and `QT_LOGGING_RULES=*=true` for Qt-side spam. On Wine
add `WINEDEBUG=+etw,+d3d11,+dxgi,+wbemprox` and run under a debugger channel.

---

## 8. Ranked: what must work for Tableau to open

1. **MSI install path itself** — Burn → `msiexec` on `a1` (5,425 files, 2.06 GiB, LZX cab), plus the
   `WixQuietExec64` custom actions; and the `VC2022Redist` prerequisites. Nothing exotic, but the whole
   2.06 GiB install must run under `msiexec` in Wine. *Highest blast radius.*
2. **x86_64 PE loading + full Qt 6.5.11 runtime** — `tableau.exe` and ~200 x64 DLLs; `--enable-archs=i386,x86_64`
   is mandatory because the bootstrap is 32-bit while the product is 64-bit.
3. **Qt GUI stack up to a first window** — `Qt6Gui/Widgets` + platform plugin (`qwindows`), `d3dcompiler_47.dll`,
   ANGLE `libEGL/libGLESv2` → D3D11/D3D9; fall back to `bin/swiftshader` software GL. If the Qt platform plugin
   or D3D init fails, the process aborts before any UI.
4. **FlexNet licensing stack load + machine identifier** — `tabfnp.dll` must resolve a hostid from
   `DeviceIoControl`-based NIC/disk reads **or** the WMI fallback (`Win32_NetworkAdapter` +
   `Win32_ComputerSystemProduct`). This is the #1 *functional* Wine risk: Wine's device IOCTL coverage is
   CD-ROM/tape-only and wbemprox returns partially-stubbed values, so the derived machine ID can be empty →
   license checkout/activation fails even though the app starts.
5. **`FNPLicensingService64` service install/start** — `installanchorservice.exe` + FlexNet SCM service
   (`sc sdset` already fakes success in Wine). Needed for concurrent/ATR activation; if the service can't run,
   only unlicensed/limited mode may appear.
6. **QtWebEngine (Chromium 122) + its sandbox/token paths** — HybridUI `plugin-host-desktop.rcc` /
   `vizclient-static-assets.rcc` and the start page are Chromium; needs `QtWebEngineProcess.exe`, ETW stubs to
   no-op, and token/sandbox calls to be tolerated (or `--no-sandbox`). A Chromium init failure kills the
   WebEngine-based shell even if the native Qt window shows.
7. **Embedded JDK 17 (`jre/`) + `jdbcserver.jar` / `oauthservice.jar`** — spawned as child processes for
   connectors and OAuth; the JVM's `AdjustTokenPrivileges`/perf-counter paths must not abort it.
8. **`hyperd.exe` (Hyper, 208 MB) + `hyperapi.dll`** — launched for extracts/datasource engine; imports
   `MiniDumpWriteDump`, `BCrypt*`, `CertOpenStore`, `RegNotifyChangeKeyValue`, `GetAdaptersAddresses`.
9. **`eps.exe` (Node.js 22.17.1) + `tabprotosrv.exe`** — the "external protocol service" and protocol/process
   broker; both are ordinary Wine-friendly console processes (Node needs nothing special).
10. **Crash/telemetry stubs return success** — `MiniDumpWriteDump` (dbghelp), `EventRegister/EventWrite*`
    (ntdll ETW stubs returning success with handle `0xdeadbeef`), `SetUnhandledExceptionFilter`; nothing here
    blocks startup, but the app's own diagnostics are effectively void on Wine — rely on `-DLogLevel`/`log_config`.

---

## Appendix — exact commands used

```bash
# Burn structure
7z l app/tableau_burn.cab
python3 -c "…parse app/tableau_ux/0 (BurnManifest XML)…"
file app/tableau_exe/a0 app/tableau_exe/a1

# MSI identity + tables
msiinfo suminfo app/tableau_exe/a1
msiinfo tables  app/tableau_exe/a1
for t in Property File Registry CustomAction InstallExecuteSequence Directory Component Feature Shortcut \
         CreateFolder RemoveFile AppSearch Signature Upgrade Binary Media Icon ModuleComponents \
         ModuleSignature InstallUISequence AdminExecuteSequence AdvtExecuteSequence ControlEvent \
         LaunchCondition RegLocator DrLocator EventMapping ActionText Error; do
  msiinfo export app/tableau_exe/a1 "$t" > recon/msi_tables/$t.idt
done
msiinfo export app/tableau_exe/a1 Property | grep -E 'Product(Name|Version|Code)|UpgradeCode|Manufacturer'

# versions (pefile)
python3 -c "import pefile; pe=pefile.PE(path); pe.parse_data_directories(); …VS_VERSIONINFO…"
strings -a  bin/Qt6Core.dll            | grep -oE 'Qt [0-9]+\.[0-9]+\.[0-9]+'
strings -a  bin/Qt6WebEngineCore.dll   | grep -oE 'Chrome/[0-9.]+'

# licensing evidence
strings -a bin/tabfnp.dll | grep -aiE 'flexnet|IOCTL|WMI|hostid|FLEXnet'
strings -a bin/FNP_Act_Installer.dll | grep -aiE 'FNPLicensingService|Macrovision|Common Files'
grep -i 'licens\|flexnet\|anchor\|FNP' recon/msi_tables/{Directory,File,Signature,RegLocator,Component}.idt

# imports
python3 -c "import pefile; pe=pefile.PE(p, fast_load=True); pe.parse_data_directories(); …IMPORT+DELAY_IMPORT…"
objdump -p bin/tableau.exe | sed -n '/DLL Name/,$p'      # cross-check

# Wine ground truth
grep -rn 'EventRegister' wine-11.18/dlls/advapi32/advapi32.spec wine-11.18/dlls/ntdll/misc.c
sed -n '300,370p' wine-11.18/dlls/ntdll/misc.c            # EtwEventRegister = stub, handle 0xdeadbeef
sed -n '420,470p' wine-11.18/programs/sc/sc.c             # sdset = FIXME "faking success"
cat wine-11.18/dlls/tbs/tbs.spec ; head -60 wine-11.18/dlls/tbs/tbs.c   # Tbsi_* = stub/TPM_NOT_FOUND
grep -rn 'case IOCTL_' wine-11.18/dlls/ntdll/unix/*.c     # only cdrom.c handles storage IOCTLs
grep -roh '"Win32_[A-Za-z_]*"' wine-11.18/dlls/wbemprox/ # WMI classes available

# targeted extraction (extract dir kept small, 26 MB)
7z x -y -oapp/msi_extract/tableau-26.2.1954-licensing app/tableau_exe/a1 \
   'FL_tabfnp.dll.*' 'FL_fnpcommssoap.dll.*' 'FL_custactutil*.CE9CB17D*' \
   'FL_FNP_Act_Installer.dll.*' 'FL_installanchorservice.exe.*'
```

Disk check at end of recon: `df -h /` → **19 GB free** (≥15 GB requirement met). The 2.1 GB
`app/tableau_exe/msi_root/` (the `a1` extraction) was **not** duplicated into `app/msi_extract/`; only the
26 MB licensing subset was extracted there.
