# Tableau Desktop 2026.2.3 installer — static recon (slice: InstallerRecon)

Target: `/home/asdf/Downloads/TableauDesktop-64bit-2026-2-3.exe` — 743 872 856 B, unmodified (never written to).
All numbers below are measured; every claim names its measurement. Extracted artifacts live in
`$P/app/` (see §2). MSI table dumps: `$P/app/tableau_exe/meta/` (this slice) and
`$P/recon/msi_tables/` (sibling `BuildEnv`; same content, independently produced).

---

## 1. Container type: **WiX Burn bundle (WiX v3.14.1.8722 "Extended" BA)** — not NSIS/InstallShield/Inno

Evidence (each independently sufficient):

| # | measurement | result |
|---|---|---|
| 1 | `objdump -h` section table | 6 sections; section #4 is named **`.wixburn`** (VA 0x470000, 0x38 B) — the Burn marker section. There is no NSIS (`Nullsoft`), InstallShield (`_setup.dll`/`ISSetupStream`), Inno (`Inno Setup`), or 7z SFX signature. |
| 2 | `7z l -slt` on the exe | `Type = PE`, `CPU = x86`, `Comment { FileVersion: 26.2.1954.0, InternalName: setup, ProductVersion: 26.2.1954.0 }`, and exactly one appended stream `[0]` at offset **508928** size 743 353 336. |
| 3 | bytes at file offset 508 928 (= exactly 497 KiB) | `4d 53 43 46` = **`MSCF`** → appended CAB. |
| 4 | Burn manifest (see below) | `<Container Id="WixAttachedContainer" FilePath="tableau-setup-std-262-tableau-2026-2.26.0912.1023-x64.exe" AttachedIndex="1" Primary="yes"/>` |
| 5 | MSI Author/creator | `Name of Creating Application: Windows Installer XML Toolset (3.14.1.8722)` |
| 6 | BA payload | `wixextba.dll`, payload Id `WixExtendedBootstrapperApplication.HyperlinkLicense`, `BootstrapperApplicationData.xml` → the **WiX Extended Bootstrapper Application** (Tableau's customised BA, a WixStdBA fork). |

### 1.1 Appended-data layout (measured by carving + scanning for `MSCF`)

```
off 0           ─ PE stub (32-bit i386, 6 sections, 508 928 B)
off 508 928     ─ MSCF  UX container CAB        593 235 B   entries: "0"=BurnManifest XML, u0..u23   (ends at 1 102 163)
off 1 102 163   ─ PKCS#7 signature              10 597 B    (gap between the two containers; starts 30 82 29 4d 06 09 2a 86 48 86 f7 0d 01 07 02 = signedData)
off 1 112 760   ─ MSCF  payload container CAB   742 749 504 B  entries: a0, a1                        (ends at 743 862 264)
                ─ Authenticode overlay          10 592 B    (= PE SECURITY dir size; 508928+743353336 = 743 862 264; 743 872 856 − 743 862 264 = 10 592)
```
Reproduce (`tableau_burn.cab` = the appended data starting at exe offset 508 928, i.e. offsets below are relative to that carve):
```sh
dd if=TableauDesktop-64bit-2026-2-3.exe of=tableau_burn.cab   bs=1024 skip=497     # UX cab; # truncate to 743353336 to drop the outer signature
tail -c +603833 tableau_burn.cab > tableau_payload.cab                            # payload cab (carved offset 603832)
```
(`7z` alone only exposes the PE stream `[0]`; it cannot see the Burn containers — carving is required.)

### 1.2 Bundle identity / chain (from the Burn manifest `tableau_ux/0`, 27 567 B XML)

- Bundle Id `{5dfaba8c-274e-499c-8107-cca21f4872b0}`, UpgradeCode `{A48D392E-9B66-4340-9505-9904DB7DF7D8}`, `PerMachine="yes"`.
- Bundle condition: `VersionNT >= v6.2`.
- `WixExtbaInformation LicenseUrl="http://www.tableau.com/eula" Checkprocessorspecs="Checkprocessorspecs.exe" AppName="bin\tableau.exe"`.
- Chain (exactly 2 packages + 1 rollback boundary):

| order | package | type | Id/ProductCode | size | flags |
|---|---|---|---|---|---|
| 1 | `vcredist2022_x64.exe` | ExePackage | Id `VC2022Redist` | 25 635 768 | Vital, Permanent, Cache, PerMachine, `InstallArguments="/install /quiet /norestart"`, `InstallCondition=(NOT VC2022_FOUND) OR (VC2022X64_MAJ_VER < 14 OR (VC2022X64_MAJ_VER = 14 AND VC2022X64_MIN_VER < 44))` |
| 2 | `tableau-setup-std-262-tableau-2026-2.26.0912.1023-x64.msi` | MsiPackage | Id `Tableau`, ProductCode `{D5C4243D-E35D-4F26-A837-EDB5C3AA3739}`, Version `26.2.1954` | 725 159 936 | Vital, RollbackBoundary, DisplayInternalUI=no, PerMachine, 37 `MsiProperty` pass-throughs (`ACCEPTEULA`, `INSTALLDIR`, `LBLM`, `ACTIVATIONSERVER`, …) |

- 9 `RelatedBundle Action="Detect"` GUIDs (older Tableau versions) + 1 `Action="Upgrade"` = `{A48D392E-9B66-4340-9505-9904DB7DF7D8}`.
- `Checkprocessorspecs.exe` (135 520 B, x86-64 console, `u4`) is a BA payload — a CPU-feature gate run by the BA before install.

---

## 2. Extraction result

Command used (7z 26.00): carves as in §1.1, then
```sh
7z x -o$P/app/tableau_exe tableau_payload.cab     # → a0, a1
msiextract -C $P/app/tableau_exe/msi_root $P/app/tableau_exe/a1   # → the real install tree
```
`msiextract` produced **5425 files** — byte-for-byte the MSI's `File` table row count (5425), so nothing was skipped.

| path | size (B) | note |
|---|---|---|
| `$P/app/tableau_exe/msi_root/` | **2 208 240 220** (`du -sb`) | the installed tree, 5425 files; **equals the MSI `InstallSize` 2208240220 exactly** (`du -sh` = 2.1 G) |
| `$P/app/tableau_exe/a0` | 25 635 768 | `vcredist2022_x64.exe` |
| `$P/app/tableau_exe/a1` | 725 159 936 | `tableau-setup-std-262-…-x64.msi` |
| `$P/app/tableau_ux/` | 1 543 634 | Burn UX container (manifest `0`, BA `u0..u23`) |
| `$P/app/tableau_exe/meta/` | 2 458 176 | MSI tables (.idt), `files_full.tsv`, `file_all.txt`, raw listings |
| **`$P/app/` total** | **≈ 2.8 GiB** | (`du -sh .` = 2.8G) |

The carved `tableau_burn.cab` was deleted after extraction (redundant, 709 MB; reproducible with the `dd` above).
`$P/app/tableau_exe/meta/files_full.tsv` is the authoritative `install-path ⇥ size ⇥ version ⇥ component`
map for all 5425 files.

### 2.1 MSI identity

| item | value |
|---|---|
| File | `a1` = `tableau-setup-std-262-tableau-2026-2.26.0912.1023-x64.msi` |
| Title / Subject | `Tableau 2026.2 (20262.26.0912.1023)` |
| Author / Comments | `Salesforce, Inc` / `Copyright (c) 2026 Salesforce, Inc.` |
| **ProductCode** | `{D5C4243D-E35D-4F26-A837-EDB5C3AA3739}` |
| **UpgradeCode** | `{A4849F71-5147-414E-A210-6D8412A2AE83}` |
| PackageCode (SummaryInfo 9) | `{91BE2B2C-3235-45AE-8906-5E5FE045DCE7}` |
| Version / ProductVersion | `26.2.1954` / `26.2.1954` |
| Template | **`x64;1033`** (64-bit package) |
| Media | one cabinet `#cab1.cab`, LZX:21, 1031 blocks, 720 904 424 B |
| Features | exactly 1: `TableauApplication`, Level 1 |
| Tables | 49 (incl. `Binary`, `LaunchCondition`, `RegLocator`, `DrLocator`, `Signature`, `AppSearch`, `Registry`, `Shortcut`, `Upgrade`) — **no `ServiceInstall`, no `Environment`, no `Condition`** |
| Installer binaries: | `Binary` table holds only `WixCA`(+2 GUID-suffixed copies), `CustomActionDLL`, and bitmaps/icons — no nested MSI/EXE |

---

## 3. Component inventory (architecture by `file`)

**Everything shipped is x86-64 except one file.** `file` over all 405 `.exe`/`.dll` in the tree:

```
306  PE32+ executable ... (DLL)     x86-64
 45  PE32+ executable for MS Windows 10.00 (DLL)   x86-64
 42  PE32+ executable ... (console)  x86-64
  6  PE32+ executable ... (GUI)      x86-64
  5  PE32+ executable for MS Windows 5.02 (DLL)    x86-64
  1  PE32  executable ... (DLL), Intel i386        ← bin/d3dcompiler_47.dll
```
The MSI itself is `x64` (Template `x64;1033`); the 32-bit part is only the outer Burn stub (i386) and the VC++
redist bootstrapper stub (i386).

### 3.1 Top-level payload groups (component → files → bytes, from the MSI `File`/`Component` join)

| component | files | size | what it is |
|---|---|---|---|
| `MainApplicationCommon` | 193 | 761.3 MiB | the bulk of `bin/`: 205 top-level DLLs (tab*.dll, Qt6*, docapi, datalith…), 3 jars, ICU, resources |
| `CP_HybridUI` | 2 | 264.6 MiB | `HybridUI/plugin-host-desktop.rcc` (191 297 810 B) + `HybridUI/vizclient-static-assets.rcc` (86 165 770 B) — Qt/QML/JS Hybrid UI assets |
| `CP_LocalData` | 13 | 213.3 MiB | `local/data/…`: `GeocodingData.hyper` (178 978 816 B), `GeographicSearch.gdb` (44.5 MB), maps |
| `HyperApplication` | 2 | 198.7 MiB | `bin/hyper/hyperd.exe` (207 962 976 B) + `bin/hyper/filrtgfw.exe` |
| `MainApplicationEPS` | 1 | 126.0 MiB | `bin/eps/eps.exe` (132 146 440 B) — Node.js-based data/extract engine |
| `DataEngine64` | 14 | 35.3 MiB | `icudt74.dll` (30 796 640 B), data-engine DLLs |
| `CP_SwiftShader` | 2 | 36.9 MiB | `bin/swiftshader/libGLESv2.dll` (38 434 144 B) + `libEGL.dll`, ver 4.1.0.5 |
| `CP_QtWebEngineResources` | 6 | 22.5 MiB | `icudtl.dat` (10.2 MB), `.pak`, `v8_context_snapshot.bin` |
| `CP_QtWebEngineLocales` | 53 | 35.3 MiB | 53 Chromium locale `.pak` |
| `Desktop_Java_COMP_*` | ~180 | ~180 MiB | JRE 17.0.18 (477 files): `bin/jre/{bin,conf,lib,legal}` |
| `CP_Main_licensedebugger` | 5 | 15.8 MiB | FlexNet anchor-service tooling (§5) |
| `LocResourceDlls`/`LocResourceRccs` | 15×3 + 1 | ~100 MiB | 15 localized resource DLLs + `tablangres.rcc` |
| `samples_*` / `defaultDatasources_*` | 15×20 / 15×4 | ~44 / ~29 MiB | localized samples and default datasources |
| `UMMapCOMP_{CN,IN,US}_normal_*` | 30×~30 | ~4 MiB | bundled map tiles (`Local/Maps/{CN,IN,US}/normal/…`) |

### 3.2 `file` output for the main program binaries (pasted verbatim)

```
./Tableau/Tableau 2026.2/bin/tableau.exe:              PE32+ executable for MS Windows 6.00 (GUI), x86-64, 6 sections
./Tableau/Tableau 2026.2/bin/tabui.dll:                PE32+ executable for MS Windows 6.00 (DLL), x86-64, 9 sections
./Tableau/Tableau 2026.2/bin/tabdoc.dll:               PE32+ executable for MS Windows 6.00 (DLL), x86-64, 6 sections
./Tableau/Tableau 2026.2/bin/tabcore.dll:              PE32+ executable for MS Windows 6.00 (DLL), x86-64, 6 sections
./Tableau/Tableau 2026.2/bin/tabquery.dll:             PE32+ executable for MS Windows 6.00 (DLL), x86-64, 6 sections
./Tableau/Tableau 2026.2/bin/tabsrv.dll:               PE32+ executable for MS Windows 6.00 (DLL), x86-64, 6 sections
./Tableau/Tableau 2026.2/bin/tabdata.dll:              PE32+ executable for MS Windows 6.00 (DLL), x86-64, 6 sections
./Tableau/Tableau 2026.2/bin/hyperapi.dll:             PE32+ executable for MS Windows 6.00 (DLL), x86-64, 14 sections
./Tableau/Tableau 2026.2/bin/hyper/hyperd.exe:         PE32+ executable for MS Windows 6.00 (console), x86-64, 14 sections
./Tableau/Tableau 2026.2/bin/eps/eps.exe:              PE32+ executable for MS Windows 6.00 (console), x86-64, 7 sections
./Tableau/Tableau 2026.2/bin/yaxcat/yaxcatd.exe:       PE32+ executable for MS Windows 6.00 (console), x86-64, 6 sections
./Tableau/Tableau 2026.2/bin/atrdiag.exe:              PE32+ executable for MS Windows 6.00 (console), x86-64, 9 sections
./Tableau/Tableau 2026.2/bin/Qt6Core.dll:              PE32+ executable for MS Windows 6.00 (DLL), x86-64, 7 sections
./Tableau/Tableau 2026.2/bin/Qt6Gui.dll:               PE32+ executable for MS Windows 6.00 (DLL), x86-64, 7 sections
./Tableau/Tableau 2026.2/bin/Qt6WebEngineCore.dll:     PE32+ executable for MS Windows 6.00 (DLL), x86-64, 10 sections
./Tableau/Tableau 2026.2/bin/QtWebEngineProcess.exe:   PE32+ executable for MS Windows 6.00 (GUI), x86-64, 6 sections
./Tableau/Tableau 2026.2/bin/d3dcompiler_47.dll:       PE32 executable for MS Windows 6.00 (DLL), Intel i386, 5 sections
./Tableau/Tableau 2026.2/bin/tabfnp.dll:               PE32+ executable for MS Windows 6.00 (DLL), x86-64, 11 sections
./Tableau/Tableau 2026.2/bin/custactutil.exe:          PE32+ executable for MS Windows 6.00 (console), x86-64, 8 sections
./Tableau/Tableau 2026.2/bin/custactutil_libFNP.dll:   PE32+ executable for MS Windows 6.00 (DLL), x86-64, 11 sections
./Tableau/Tableau 2026.2/bin/FNP_Act_Installer.dll:    PE32+ executable for MS Windows 6.00 (DLL), x86-64, 8 sections
./Tableau/Tableau 2026.2/bin/installanchorservice.exe: PE32+ executable for MS Windows 6.00 (console), x86-64, 6 sections
./Tableau/Tableau 2026.2/bin/uninstallanchorservice.exe: PE32+ executable for MS Windows 6.00 (console), x86-64, 6 sections
./Tableau/Tableau 2026.2/bin/fnpcommssoap.dll:         PE32+ executable for MS Windows 6.00 (DLL), x86-64, 7 sections
./Tableau/Tableau 2026.2/bin/jre/bin/java.exe:         PE32+ executable for MS Windows 6.00 (console), x86-64, 6 sections
./Tableau/Tableau 2026.2/bin/jre/bin/server/jvm.dll:   PE32+ executable for MS Windows 6.00 (DLL), x86-64, 6 sections
```
`tableau.exe` (677 728 B, ver `20262.26.912.1023`) is a thin loader; `objdump -p` imports:
`tabsys.dll, Qt6Core.dll, tabcoreplatform.dll, tabdesktopui.dll, tabwidgets.dll, tabcore.dll, art_cpp.dll,
tabcoredata.dll, Qt6Gui.dll, tabdoc.dll, tabcache.dll, tabdata.dll, tabrender.dll, tabvizql.dll,
tabvizrender.dll, tabui.dll, tabquerycache.dll, VCRUNTIME140.dll, VCRUNTIME140_1.dll, api-ms-win-crt-*.dll,
MSVCP140.dll, KERNEL32.dll, gdiplus.dll, tabmixins.dll, tabpreslayerdata.dll`.
`bin/` also ships `tableau.com` (549 216 B, the console twin used by e.g. `-activate`).
Versions: `bin/*` core = `20262.26.912.1023`, `hyperd.exe`/`hyperapi.dll` = `2026.2.0.24949`, `eps.exe` = `22.17.1.0`,
Qt = `6.5.11.0`, FlexNet = `11.19.4.1`, JRE = `17.0.18.0`.

---

## 4. UI / runtime stacks (task items)

| stack | present? | evidence |
|---|---|---|
| **Qt** | **Qt 6.5.11** — 23 `Qt6*.dll` + `Qt6WebEngine*`; `file`/version resources all `6.5.11.0`. Plugin tree `bin/plugins/{platforms,styles,imageformats,sqldrivers,tls}` (12 files) incl. `qwindows.dll` (0.82 MiB), `qwindowsvistastyle.dll`, `qcertonlybackend.dll`, `qschannelbackend.dll`, `qopensslbackend.dll`. | `File.idt` versions + extracted tree |
| **Chromium / CEF** | **No `libcef.dll`.** Chromium is embedded via **Qt WebEngine**: `Qt6WebEngineCore.dll` (162 660 192 B), `QtWebEngineProcess.exe` (695 648 B), `icudtl.dat`, `resources/*.pak`, `qtwebengine_locales/` (53 `.pak`), `swiftshader/{libEGL,libGLESv2}.dll` (4.1.0.5), ANGLE `libEGL/libGLESv2.dll` (file-ver 5.15.18.0). Version string inside `Qt6WebEngineCore.dll`: **`Chrome/122.0.6261.171`**. | `strings Qt6WebEngineCore.dll` → `Chrome/122.0.6261.171` |
| **WebView2** | absent — no `WebView2Loader*.dll`, no `msedgewebview2`, no Edge runtime |
| **.NET** | absent — no `mscoree.dll`, no `coreclr`, no managed assemblies, no `.NET` version resource anywhere in the File table |
| **Java / JRE** | **bundled JRE 17.0.18**, 477 files under `bin/jre/`; `bin/jre/bin/server/jvm.dll` 11.38 MiB; `java.exe/javaw.exe/javac.exe/…` all `ver=17.0.18.0`. Vendor = **Azul Zulu** (`legal/com.azul.crs.client`, `legal/com.azul.tooling` directory names). Ships its own `ucrtbase.dll` 10.0.26100.1 + `msvcp140.dll` 14.40.33810.0. |
| **Python** | absent (no `python*.dll`, no `python*.exe`) |
| **Node.js** | **22.17.1 embedded inside `eps/eps.exe`** (strings `22.17.1`, `napi_node_version`, `require('./node.js')`) — not a separate runtime tree |
| **Envoy** | embedded in `yaxcat/yaxcatd.exe` (strings `envoy/service/discovery/v3`, `envoy.api.v2.core`, c-ares resolver, zlib 1.2.13) — local sidecar daemon |
| **Hyper engine** | `bin/hyper/hyperd.exe` 198 MiB, `hyperapi.dll`, `tabhyper.dll`; data files `.hyp` (e.g. `GeocodingData.hyper`) |
| **GPU/D3D** | SwiftShader + ANGLE (above) + `d3dcompiler_47.dll` (**the only i386 binary**); no DXVK/vkd3d shipped |
| **VC++ runtime DLLs shipped in-tree** | only inside `bin/jre/`: `ucrtbase.dll` (10.0.26100.1), `msvcp140.dll` (14.40.33810.0). The main app links dynamically against `VCRUNTIME140(.1).dll`/`MSVCP140.dll`/UCRT `api-ms-win-crt-*` → **provided by the VC++ redist package** (§6) |

Bundled OLE/ODBC-ish data-source drivers: `bin/connectors/*.dll` (19 files: alibaba-adb/dla/maxcompute, athena,
azure-dw, azure-sqldb, databricks, datorama_jdbc, dremio, esri, firebird-3, impala, kyvos, mariadb, memsql,
mongodb, qubole, redshift, salesforce-uip). `HKLM\SOFTWARE\Tableau\Directories = {Drivers, Connectors}` point at
`%ProgramFiles%\Tableau\{Drivers,Connectors}`; those directories are only *created* during install (they carry no
files in this MSI) — third-party drivers are fetched later by the app/first run.

---

## 5. Licensing stack — FlexNet Publisher 11.19.4.1 (in-process + one Windows *service*)

Evidence string (from `bin/custactutil.exe`):
`@(#) FlexNet Licensing v11.19.4.1 build 291070 (ipv6) x64_n6 (lmgr.lib), Copyright (c) 1988-2023 Flexera. All Rights Reserved.`

### 5.1 Artifacts (all in `bin/`, all x86-64)

| file | size (B) | ver | role |
|---|---|---|---|
| `tabfnp.dll` | 10 066 784 | 11.19.4.1 | Tableau's FlexNet wrapper loaded by the app (exports FlexNet API) |
| `fnpcommssoap.dll` | 501 032 | 11.19.4.1 | FlexNet comm/Soap transport |
| `custactutil_libFNP.dll` | 10 066 784 | 11.19.4.1 | `libFNP` (same engine as tabfnp), used by the CA helper |
| `custactutil.exe` | 1 779 552 | — | FlexNet "custactutil" helper (contains full lmgr/FlexNet errors + trust store) |
| `FNP_Act_Installer.dll` | 4 646 184 | 11.19.4.1 | **anchor-service installer**: exports `fnpActSvcInstallWin`, `fnpActSvcRemoteInstallWin`; contains `CDriverConfig/CDriverHandle/CDriverItem/CDriverRule/CInstaller` (driver-install machinery) |
| `installanchorservice.exe` | 25 440 | — | 25 KB shim: `Usage: installanchorservice publisher_name product_name [-remote_installation]` → calls `FNP_Act_Installer.dll` |
| `uninstallanchorservice.exe` | 25 440 | — | uninstall twin |
| `atrdiag.exe` | 2 984 288 | 20262.26.912.1023 | ATR/LBLM licensing diagnostics; default server `https://atr.licensing.tableau.com:443/` |

Searching the whole `File` table for `*licen*`, `flexnet*`, `fnp*`, `pubglue`, `lm*`, `Tableau_License*` returns
**only** the eight files above (plus Java `LICENSE` text files). There is **no `lmgrd`/`lmutil`/`lmadmin`,
no `pubglue`, no `Tableau_License*`, no `.sys`/`.inf`/`.cat` anywhere in the MSI.**

### 5.2 The Windows service that the install creates

`InstallExecuteSequence` (dumped in §2.1) schedules these custom actions:

```
1951 InstallFlexNetServiceSet      (type 51 → property)  cond=(none)
5802 InstallFlexNetService         (type 3073 = DLL+InScript+NoImpersonate ⇒ deferred as SYSTEM)
5803 UpdateFlexNetServicePermissions (type 3073, deferred SYSTEM)
5801 RollbackFlexNetService        (type 3073)
1955/1956 UninstallFlexNetService(+Rollback)  cond=Installed AND REMOVE
```
The command lines (verbatim from the `CustomAction` table):

```
InstallFlexNetServiceSet → "[LicenseDebugger.CE9CB17D_70D7_465A_BADD_BC254420D929]\installanchorservice" "Tableau Software, LLC" "Tableau 2026.2"
UninstallFlexNetServiceSet → "[LicenseDebugger…]\uninstallanchorservice" "Tableau Software, LLC" "Tableau 2026.2"
UpdateFlexNetServicePermissionsSet → "[SystemFolder…]sc.exe" sdset "flexnet licensing service 64" D:(D;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;NU)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWRPWPLOCRRC;;;IU)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)(A;;CCLCSWRPLOCRRC;;;WD)
```
Registered service details (strings of `FNP_Act_Installer.dll`): internal name **`FNPLicensingService64`**, display name
**`FlexNet Licensing Service 64`**, service binary `FNPLicensingService.exe`, created via
`CreateServiceA`, install dir `%CommonProgramFiles%\Macrovision Shared\FlexNet Publisher\`,
data dir `C:\ProgramData\FLEXnet`, description *"This service performs licensing functions on behalf of FlexNet
enabled products."* There is **no `ServiceInstall` table** — the service is created entirely by the CA above.

### 5.3 Activation / registration custom actions

```
ActivateTableauSet → "[#FL_tableau.exe…]" -activate [ACTIVATE_KEY]   (cond: NOT Installed AND ACTIVATE_KEY<>"none"; type 1089 = deferred, impersonated)
RegisterTableauSet → "[#FL_tableau.exe…]" -register                   (cond: NOT Installed AND REGISTER="1")
ReclaimLicenseSet  → "[#FL_tableau.exe…]" -return all                 (cond: Installed AND REMOVE)
RunTableau         → type 210 (launch file after success)
```

### 5.4 Licensing registry surface (MSI `Registry` + `RegLocator`/`AppSearch` + `Property`)

Written: `HKLM\Software\Tableau\ATR\{LBLM, ATRRequestedDurationSeconds}`, `HKLM\SOFTWARE\Tableau\ATR\ATREnabled`,
`HKLM\Software\Tableau\ATR\{LicensingWorkgroupServer}`, `HKLM\Software\Tableau\Tableau 2026.2\Settings\{SynchronousLicenseCheck, SilentlyRegisterUser}`,
`HKLM\SOFTWARE\Tableau\ReportingServer\{Server, schedulereportInterval}`.
Read (AppSearch): `HKLM\SOFTWARE\Tableau\FlexNetUsers\loom` → `FLEXNET_OTHER_PRODUCT_INSTALLED`
(presence of another FlexNet-based product under key "loom"); `HKLM\Software\Tableau\ATR\LBLM` → `LBLM_HOLD`;
`HKCU\Software\Tableau\ATR\LicensingWorkgroupServer` → `ACTIVATIONSERVER_HOLD`; `HKLM\Software\Tableau\ATR\ATREnabled`;
`HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\CurrentBuild` → `WINDOWSBUILDNUM`;
`[SystemFolder]\d2d1.dll` version ≥ `7.0.6002.18391` → `D2D1_FOUND`.
`Property` table defaults: `ACCEPTEULA 0`, `REBOOT ReallySuppress`, `ALLUSERS 1`, `LAUNCHSILENT 0`, `RECLAIMLICENSE 0`.

---

## 6. VC++ redistributable

- Payload `a0` = `vcredist2022_x64.exe`, `7z -slt` version resource **14.44.35211.0** (linker 14.16, InternalName `setup`), 25 635 768 B, itself a 32-bit Burn stub.
- Bundle `BootstrapperApplicationData.xml` (payload `u23`): `DisplayName="Microsoft Visual C++ 2015-2022 Redistributable (x64) - 14.44.35211"`, `Version="14.44.35211.0"`.
- Its own attached container holds 14 entries; MSI entries identified by `file`:
  - `vc_runtimeMinimum_x64.msi` – *"Visual C++ 2022 X64 Minimum Runtime - 14.44.35211"*, Template `x64;1033` (`a9`)
  - `vc_runtimeAdditional_x64.msi` – *"Visual C++ 2022 X64 Additional Runtime - 14.44.35211"* (`a10`)
  - Arm64 Minimum/Additional MSIs (`a0`, …)
  - UCRT update cabs KB2999226 for Win8.1/Win8/Win7/Win Vista x86+x64 (`a1`–`a8`)
  - DLL cabs: `concrt140.dll_amd64, msvcp140.dll_amd64, mfc140*.dll_amd64, vcruntime140.dll_amd64, …` (`a11`–`a13`)
- Installed by the bundle as `vcredist2022_x64.exe /install /quiet /norestart` (verbatim `InstallArguments` in the Burn manifest), only if `VC2022X64_MAJ_VER < 14` or (`=14` and `MIN_VER < 44`).
- Requirement at runtime: `tableau.exe` imports `VCRUNTIME140.dll`, `VCRUNTIME140_1.dll`, `MSVCP140.dll`, `api-ms-win-crt-*` (UCRT) from `System32`.

---

## 7. Unattended install

### 7.1 What the bundle documents (verbatim from the BA theme `tableau_ux/u10`, `1033/thm.wxl`, `String Id="HelpText"`)

```
/install | /repair | /uninstall | /layout "directory" - Install, repair, uninstall or create a complete local copy of the bundle in the directory. Install is the default.
/passive - Display minimal UI with no prompts. Displaying UI and all prompts is the default.
/quiet | /silent - Display no UI and no prompts. Displaying UI and all prompts is the default.
/norestart - Suppress any attempts to restart. UI prompts before restart is the default.
/log "logfile.txt" - Log information to a specific file. A log file is created in %TEMP% by default.
Install Properties (case sensitive)
    ACCEPTEULA=1|0 – Accepts the EULA.  Required for quiet, silent, and passive installs.
    AUTOUPDATE=1|0 - Check for Tableau product updates.
    DESKTOPSHORTCUT=1|0 - Create a desktop shortcut.
    INSTALLDIR="path to installation folder" - The folder to use for installation.
    STARTMENUSHORTCUT=1|0 - Create a Start menu shortcut.
```
`ACCEPTEULA=1` is enforced by the MSI itself — `LaunchCondition` table (verbatim):

```
Privileged                                                        → admin/elevation required
WindowsBuild >= 9200                                              → Windows 8 / Server 2012 or later
D2D1_FOUND OR WindowsBuild > 6002                                 → Direct2D platform update required
ACCEPTEULA = "1" OR UILevel = 5 OR Installed OR OEM = "1"         → "To accept the End User License Agreement (EULA), add ACCEPTEULA=1 to your command-line to continue the /quiet, /silent, or /passive install process."
NOT NEWERFOUND                                                    → no newer version already installed
```
The BA accepts 53 command-line variables (from `tableau_ux/u23` `BootstrapperApplicationData.xml`,
`WixStdbaOverridableVariable`): the four documented ones **plus** `DISABLEEXTENSIONS`,
`DISABLENETWORKEXTENSIONS`, `DISABLESANDBOXEXTENSIONS`, `DISABLE3PTRUSTEDEXTENSIONS`,
`DISABLETABTRUSTEDEXTENSIONS`, `ACTIVATE_KEY`, `REGISTER`, `RECLAIMLICENSE`, `SENDTELEMETRY`,
`DONTSENDTELEMETRY`, `REPORTINGSERVER`, `SCHEDULEREPORTINTERVAL`, `AUTOSAVE`, `AUTOUPDATESERVER`,
`CUSTOMSAMPLESDIR`, `DISCOVERPANEURL`, `LANGLIST`, `TABLEAU_LANG`, `TABLEAU_LANG_STRING`, `BETA_VERSION`,
`REMOVEINSTALLEDAPP`, `CRASHDUMP`, `DRIVERDIR`, `CONNECTORDIR`, `SKIPAPPLICATIONLAUNCH`, `ATRENABLED`,
`ATRREQUESTEDDURATIONSECONDS`, `LBLM`, `ACTIVATIONSERVER`, `SYNCHRONOUSLICENSECHECK`, `SILENTLYREGISTERUSER`,
and the `*_OR` twins (set to 1 by the BA when the operator supplied the base variable).
Default values of note (Burn manifest): `ACCEPTEULA=0`, `LBLM=notspecified`, `ACTIVATIONSERVER=notspecified`,
`SENDTELEMETRY=1`, `CRASHDUMP=1`, `AUTOUPDATE=1`, `AUTOSAVE=1`, `DESKTOPSHORTCUT=1`, `STARTMENUSHORTCUT=1`,
`INSTALLDIR=[ProgramFiles64Folder]Tableau\Tableau 2026.2`, `DRIVERDIR=…\Tableau\Drivers`,
`CONNECTORDIR=…\Tableau\Connectors`, `TABLEAU_LANG=" "` (→ all 15 locales via `TRANSFORMS=[TABLEAU_LANG]`).

### 7.2 Command lines most likely to work (in order of preference)

1. **Bundle, silent (canonical):**
```bat
TableauDesktop-64bit-2026-2-3.exe /quiet /norestart ACCEPTEULA=1 ^
    INSTALLDIR="C:\Program Files\Tableau\Tableau 2026.2" ^
    SKIPAPPLICATIONLAUNCH=1 AUTOUPDATE=0 DESKTOPSHORTCUT=0 STARTMENUSHORTCUT=0 ^
    SENDTELEMETRY=0 DONTSENDTELEMETRY=1 CRASHDUMP=0 LBLM=1 ^
    /log "C:\tableau_install.log"
```
(`SKIPAPPLICATIONLAUNCH=1` prevents the post-install `RunTableau` launch; `LBLM=1` selects
login-based licensing and avoids `ACTIVATIONSERVER`/`ACTIVATE_KEY`; drop `LBLM=1` and add
`ACTIVATIONSERVER=…`/`ACTIVATE_KEY=…` only if you have a license server or key.)
2. **Passive (progress UI, no prompts)** — same but `/passive` instead of `/quiet` (still needs `ACCEPTEULA=1`).
3. **Extract-only, no install** (useful to get payloads without elevation): `… /layout "C:\tab_layout"`.
4. **Direct MSI fallback (bypasses Burn; the MSI is what actually installs everything):**
```bat
msiexec /i tableau-setup-std-262-tableau-2026-2.26.0912.1023-x64.msi /qn /norestart ^
    ACCEPTEULA=1 INSTALLDIR="C:\Program Files\Tableau\Tableau 2026.2" ^
    DESKTOPSHORTCUT=1 STARTMENUSHORTCUT=1 AUTOUPDATE=0 SENDTELEMETRY=0 DONTSENDTELEMETRY=1 ^
    CRASHDUMP=0 LBLM=1 /l*v "C:\tableau_msi.log"
```
Notes on #4: the package is `x64` (`Template x64;1033`), so it must be handled by a **64-bit `msiexec`**
(Wine needs the 64-bit loader / a `win64` prefix); the `Binary` table's `WixCA` DLL is carried in the MSI, so the
FlexNet anchor-service CAs still run; `Privileged` and `WindowsBuild >= 9200` still apply.
Uninstall/repair: `… /uninstall` / `… /repair` (bundle) or `msiexec /x {D5C4243D-E35D-4F26-A837-EDB5C3AA3739} /qn`.
Key codes: MSI ProductCode `{D5C4243D-E35D-4F26-A837-EDB5C3AA3739}`, UpgradeCode
`{A4849F71-5147-414E-A210-6D8412A2AE83}`, PackageCode `{91BE2B2C-3235-45AE-8906-5E5FE045DCE7}`; Bundle Id
`{5dfaba8c-274e-499c-8107-cca21f4872b0}`, Bundle UpgradeCode `{A48D392E-9B66-4340-9505-9904DB7DF7D8}`.

---

## 8. RISK list — dependencies that cannot work under Wine *by design* or need special handling

- **`RISK:` Windows service + SYSTEM-context install** — the new-install path *always* runs
  `installanchorservice.exe "Tableau Software, LLC" "Tableau 2026.2"` from a deferred, **NoImpersonate** (SYSTEM)
  custom action (`CustomAction` rows `InstallFlexNetServiceSet`/`InstallFlexNetService`, type 3073/3137) which
  calls `CreateServiceA` and installs `FNPLicensingService.exe` as **`FlexNet Licensing Service 64`**
  into `%CommonProgramFiles%\Macrovision Shared\FlexNet Publisher\`. Evidence: `CustomAction.idt`,
  `InstallExecuteSequence.idt`, `FNP_Act_Installer.dll` strings. Under Wine this needs a working SCM, elevation, and
  the 64-bit service binary launched in a service session; failures are non-fatal for file copy (`3137` = continue)
  but the licensing service will be absent.
- **`RISK:` service ACL rewrite with raw SDDL** — the install then runs
  `%SystemRoot%\System32\sc.exe sdset "flexnet licensing service 64" D:(D;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;NU)(A;;…;;;BA)(A;;…;;;IU)(A;;…;;;SY)(A;;…;;;WD)`
  (evidence: `CustomAction.idt` row `UpdateFlexNetServicePermissionsSet`). This requires Wine's `sc.exe` to accept
  an SDDL security descriptor and resolve `NU` (Network Service)/`BA`/`IU`/`SY`/`WD` SIDs — a place Wine's
  implementation is incomplete.
- **`RISK:` FlexNet hostid = hardware/Ethernet identity (hardware-bound licenses)** — `custactutil.exe` /
  `tabfnp.dll` implement FlexNet hostid via the **Ethernet MAC** and use **WMI** to decide whether the host is a
  physical machine: strings `ETHERNET`, `.?AVCEthernet@…`, `PhysicalAdapter`, `Physical machine detected`,
  `Correction - WMI indicates Physical machine`, `serverHostID`, and errors `The hostid of this system does not
  match the hostid`, `Cannot find ethernet device.`, `An item needed for composite hostid missing or invalid.`,
  `An unsupported hostid.`, `Do not use same hostid for FLOAT_OK=hostid as HOSTID=`. Wine's synthetic MAC/adapter
  list and partial `wbemprox` mean a license issued for the Windows hostid will not validate. **Files: `bin/tabfnp.dll`,
  `bin/custactutil.exe`, `bin/custactutil_libFNP.dll`.**
- **`RISK:` kernel-mode driver machinery compiled in** — `FNP_Act_Installer.dll` contains
  `CDriverConfig/CDriverHandle/CDriverItem/CDriverRule/CInstallerRuleBase` and the messages
  *"The hostid of this system does not match… software driver for this dongle type is not installed."* /
  *"Cannot read dongle: check dongle or driver."* (FlexNet dongle/FLEXid support). No `.sys`/`.inf`/`.cat` is shipped,
  so a FLEXid-dongle license would require an out-of-tree kernel driver — **impossible on Wine** (no kernel drivers).
- **`RISK:` install-time launch conditions that a Wine prefix must fake** —
  `Privileged` (admin token), `WindowsBuild >= 9200` and `D2D1_FOUND OR WindowsBuild > 6002`.
  `D2D1_FOUND` is produced by an `AppSearch` signature check on `%SystemRoot%\System32\d2d1.dll`
  version ≥ `7.0.6002.18391` (`AppSearch.idt`, `DrLocator.idt`, `Signature.idt`); Wine's builtin `d2d1.dll`
  will almost certainly fail that version test, so the prefix **must** report a Windows 10/11 build ≥ 9200
  (`WindowsBuild`) or `LaunchConditions` fails with *"Unable to install [ProductName] on current system
  configuration."*
- **`RISK:` Chromium sandbox inside Qt WebEngine** — `QtWebEngineProcess.exe` (Chromium **122.0.6261.171**)
  uses Chromium's Windows sandbox (AppContainer/restricted-token/job APIs). Wine typically requires
  `QTWEBENGINE_DISABLE_SANDBOX=1` (or `--no-sandbox`) for the render process to start; the installer does not set it.
- **`RISK:` x64 MSI through a 32-bit msiexec** — MSI `Template = x64;1033`; a 32-bit `msiexec` refuses it
  ("not supported by this processor type"). Wine must run the 64-bit msiexec (win64 prefix / `wine64`).
- **`RISK:` auto-update / telemetry / cloud activation outbound network** — defaults `AUTOUPDATE=1`
  (`downloads.tableau.com`), `SENDTELEMETRY=1`, `CRASHDUMP=1`, and ATR/LBLM activation against
  `https://atr.licensing.tableau.com:443/` (`atrdiag.exe`, `CP_ActivationServer` registry component).
  Disable via `AUTOUPDATE=0 SENDTELEMETRY=0 DONTSENDTELEMETRY=1 CRASHDUMP=0 LBLM=0` (or provide a license server).
- **`RISK:` driver/connector directories are empty in the payload** — `DRIVERDIR`/`CONNECTORDIR`
  (`%ProgramFiles%\Tableau\{Drivers,Connectors}`) are created and registered in
  `HKLM\SOFTWARE\Tableau\Directories` but ship no files in this MSI; only the 19 in-tree
  `bin/connectors/*.dll` exist. Any additional driver requires the app's own online download.
- **`RISK:` VC++ redist bootstrapper installs Windows-Update cabs** — `a0` carries KB2999226 UCRT update
  cabinets for Win7/8/8.1 (its payload `a1`–`a8`); the MSI install path for those needs Windows Update/CBS
  servicing, which Wine does not implement. On Wine the two MSIs (`vc_runtimeMinimum_x64.msi`,
  `vc_runtimeAdditional_x64.msi`, both x64 14.44.35211) are the usable part.
- **`RISK:` CPU feature gate before install** — the BA runs `Checkprocessorspecs.exe` (`u4`, x86-64 console)
  as a CPU check; not disassembled here, but it can abort the install on CPU/RAM grounds independent of Wine.

---

## 9. Disk

```
$ df -h /            (after extraction + deletion of the carved 709 MB cab)
Filesystem      Size  Used Avail Use% Mounted on
/dev/nvme0n1p5  213G  180G   22G  90% /
```
22 GB free — satisfies the >10 GB requirement. `$P/app/` = 2.8 GiB total
(`msi_root` 2.1 G, `a1` 692 M, `a0` 25 M, `ux` 1.6 M, `meta` 2.4 M).
