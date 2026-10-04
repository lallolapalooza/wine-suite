# Licensing / activation risk on Wine — Tableau Desktop 2026.2.3

Recovered from the `LicenseRisk` recon payload (its own write did not land; this file is the record), then
**updated with what we measured afterwards**, which changes the conclusion materially.

## Mechanism (measured from the MSI tables)

FlexNet Publisher **11.19.4.1** bundled by Tableau — `bin/tabfnp.dll` (10 066 784 B, the client),
`fnpcommssoap.dll`, `custactutil_libFNP.dll` + `custactutil.exe` (MSI custom-action host),
`FNP_Act_Installer.dll`, `installanchorservice.exe`/`uninstallanchorservice.exe` — **plus** Tableau's own
"ATR" layer (registry `HKLM\SOFTWARE\Tableau\ATR`, `FlexNetUsers\loom`; offline files `.tlq/.tlf/.tld`) and
login-based licensing (LBLM, sign-in to Tableau Server/Cloud).

Evidence: `recon/msi_tables/File.idt` rows for the binaries (v11.19.4.1), `CustomAction.idt` row 65
(`installanchorservice.exe`), row 71 (`sc.exe sdset "flexnet licensing service 64"`), rows 19/21/62
(`tableau.exe -activate|-register|-return all`), `Property.idt` rows 91/92 (`ACTIVATE_KEY=none`, `REGISTER=0`).
MSI has **no ServiceInstall/ServiceControl tables** — the service is created by that custom action — and
**no kernel-mode driver** (`Signature.idt` checks only `d2d1.dll`; no `.sys` is shipped).

## The gate is not "activation" — the app will not OPEN without the service (measured, Windows)

Running the admin-extracted tree on Windows (`msiexec /a`, no MSI state):

* `bin\tableau.exe` exits after 6.2 s with **`0xE06D7363`** (unhandled C++ exception);
* `bin\tableau.com` prints on **stdout** `The licensing service is too old.` and on **stderr**
  `Tableau could not access Trusted Storage. Verify that the latest version of the FlexNet Licensing Service
  is running as a network service. …` (exit 1).

With the **real MSI install** (which creates `FNPLicensingService64` and `C:\ProgramData\FLEXnet`), the app
opens the **"Activate Tableau"** window (reference: `logs/win-reftab/frame_026.png`).

⇒ **Consequence for the port**: "opens like Windows" requires the FlexNet service + Trusted Storage to work
under Wine. Activation itself is *not* required, because an unlicensed launch is the normal state on both
platforms (installer defaults `ACTIVATE_KEY=none`, `REGISTER=0`; the UI offers *Use Tableau for free* and a
trial/sign-in path).

## Which identity/host APIs FlexNet uses, and Wine's state

Imports of `tabfnp.dll`, `custactutil_libFNP.dll` and `FNP_Act_Installer.dll` were dumped directly
(`objdump -p`): `DeviceIoControl`, `GetAdaptersInfo`, `GetVolumeInformationA`, `OpenSCManagerA`,
`CreateServiceA`, `SetupDiGetClassDevsA` (plus `snmpapi`, `NETAPI32`, `SETUPAPI`, COM/`OLE32`).
Strings in the same DLLs name the fallbacks: `s_cacheNetIfDataViaIOCTL`, `s_cacheNetIfDataViaWMI`,
`s_getMACAddressFromDevice`, "Attempting to read SMBIOS UUID from WMI", `CUMNProvider::readDataFromTS`,
`CBIOSWMI/CWMI`.

| API / input | Wine (this tree) | Where |
|---|---|---|
| `DeviceIoControl` | implemented | `dlls/kernelbase/file.c`, `kernelbase.spec` |
| `\\.\PhysicalDrive0` device object | implemented | `dlls/mountmgr.sys/device.c` (link `PhysicalDrive%u`) |
| `IOCTL_STORAGE_QUERY_PROPERTY` | **partial** — faked `StorageDeviceProperty` when the serial is unknown | `dlls/mountmgr.sys/device.c` (`query_property`) |
| `IOCTL_SCSI_PASS_THRU(_DIRECT)` | **partial, CD-ROM only** | `dlls/ntdll/unix/cdrom.c` |
| `GetVolumeInformationW` / `NtQueryVolumeInformationFile` | implemented | `dlls/kernelbase/volume.c`, `dlls/ntdll/unix/file.c` |
| `GetAdaptersInfo` / `GetAdaptersAddresses` | implemented (MACs from the host interfaces) | `dlls/iphlpapi/iphlpapi_main.c` |
| `SetupDiGetClassDevsW` + device properties | implemented but may return an empty device set in a VM | `dlls/setupapi/devinst.c` |
| WMI `Win32_PhysicalMedia` | **hardcoded** `WINEHDISK`/`PHYSICALDRIVE0` | `dlls/wbemprox/builtin.c` |
| WMI `Win32_BaseBoard`, `GetSystemFirmwareTable` (SMBIOS/UUID) | implemented, real host data from `/sys/class/dmi/id` | `dlls/wbemprox/builtin.c`, `dlls/ntdll/unix/system.c` |
| `Tbsi_*` (TPM) | **stub** (`TBS_E_TPM_NOT_FOUND`) | `dlls/tbs/tbs.c` |

Unresolved at the time of that recon, now partly settled: whether the service registers and runs under Wine
(`FlexNetWine` is measuring it), and whether FlexNet pins the licence to a disk serial Wine fakes.

## Verdict

* **Augmenting Wine's own code is not what this needs first.** The service is a Microsoft/Flexera *binary*
  that the installer already ships; the task is to make it **run** under Wine (files + trusted storage +
  registry + SCM), which is a documented, reproducible prefix setup — see `recon/FLEXNET_WINE.md`.
* **Opening the app** therefore hinges on the FlexNet service working under Wine, not on the app being
  licensed. If the service cannot be made to run (kernel-level Trusted Storage protection), that is the
  point at which the mission's stop condition applies — and it would be documented here with the failing
  call.
