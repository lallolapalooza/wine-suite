# FlexNet hostid — differential identity probe (Wine vs Windows)

Owner `HostIdProbes`. Artifacts:

| path | what |
|---|---|
| `tools/winapi/hostid_probe.c` | the probe (new, 1 file, mingw-w64 x86_64) |
| `tools/winapi/bin/hostid_probe.exe` | build output, md5 `b9ef3a833ce93f08e4be421b5be6dfbd` |
| `vmshare/hostid_probe.exe` | same bytes, served by the `:8000` hub for the guest (`curl` → 200, 390 689 B) |
| `recon/hostid_probe_wine.txt` | **verbatim** Wine stdout+stderr (`WINEDEBUG=-all`) |
| `recon/hostid_probe_wine_debug.txt` | same probe under `WINEDEBUG=fixme+mountmgr,err+all` (fixme evidence) |
| this report | design, verbatim Wine output, guest command, per-input verdicts |

The point of the probe is to answer *"what does the machine look like to FlexNet, on each platform?"*
line-for-line: every API is called with `SetLastError(0)` first and printed as
`section.api.key=value` with `ok=`/`lastError=`/`hr=`, so the Windows and Wine captures can be diffed
mechanically.

---

## 1. Probe design

Covers everything FlexNet's `tabfnp.dll` / `custactutil_libFNP.dll` / `FNP_Act_Installer.dll` can read
for a hostid (see §4 for what they actually import), plus the WMI fallbacks `tabfnp.dll` names in its
strings (`s_cacheNetIfDataViaWMI`, `SELECT UUID FROM Win32_ComputerSystemProduct`, `Win32_BaseBoard`,
`SELECT * FROM Win32_NetworkAdapter`):

| `[section]` | API(s) | what is printed |
|---|---|---|
| `[meta]` | `RtlGetVersion` (dynamic) | arch, reported Windows version |
| `[computer]` | `GetComputerNameW`, `GetUserNameW`, `NetWkstaGetInfo(level 100)`, `GetComputerNameExW(DnsHostname)` | name, user, LAN group/domain, DNS hostname |
| `[volume]` | `GetVolumeInformationW("C:\\")`, `\\.\C:` + `IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS` | volume serial (hex+dec), label, fsname, flags, extent count/disk/offset/length |
| `[physicaldrive]` | `CreateFileW("\\.\PhysicalDrive0")` + `IOCTL_STORAGE_QUERY_PROPERTY`/`StorageDeviceProperty` (+ header-only size query) | open result, `STORAGE_DEVICE_DESCRIPTOR` scalars, vendor/product/revision/**serial** strings and their offsets |
| `[adapters]` | `GetAdaptersInfo`, `GetAdaptersAddresses(AF_UNSPEC)` | per adapter: type, MAC, description/friendly name, IP, iftype/operstatus |
| `[pnpnet]` | `SetupDiGetClassDevsW(GUID_DEVCLASS_NET)` with and without `DIGCF_PRESENT`; `SetupDiEnumDeviceInfo`; `SetupDiGetDeviceRegistryPropertyW` for `SPDRP_DEVICEDESC`, `SPDRP_FRIENDLYNAME`, `0x16`, `SPDRP_HARDWAREID`, `SPDRP_DRIVER`; `SetupDiGetDeviceInstanceIdW` | device count and every property per device |
| `[smbios]` | `GetSystemFirmwareTable('RSMB', 0)` | table size/version, every structure (type/handle/length), and for type 0/1/2/3 the vendor/product/version/serial strings plus the type-1 UUID in raw and canonical form |
| `[wmi]` | COM: `CoInitializeEx`, `CoInitializeSecurity`, `CoCreateInstance(WbemLocator)`, `ConnectServer(ROOT\\CIMV2)`, `CoSetProxyBlanket`, `ExecQuery` | `Win32_ComputerSystemProduct` (UUID/Name/Vendor/Version/IdentifyingNumber), `Win32_BaseBoard`, `Win32_PhysicalMedia`, `Win32_NetworkAdapter`, `Win32_NetworkAdapterConfiguration`, `Win32_ComputerSystem` — every HRESULT printed, failures honest |

Design notes:

* One file, no C++ runtime, links only `setupapi iphlpapi netapi32 ole32 oleaut32 uuid wbemuuid`.
* All strings are emitted `key="value"` with non-printables replaced by `.`; numbers/HRESULTs/lastError
  are hex or decimal as appropriate, so `diff` between the two platforms is meaningful.
* `'RSMB'` is `0x52534D42` (`'R'` most-significant) — an early revision used the byte-reversed value and
  `GetSystemFirmwareTable` returned `ERROR_INVALID_FUNCTION`; the constant now matches Wine's own
  `dlls/ntdll/unix/system.c:305` (`#define RSMB 0x52534D42`).
* `SPDRP_NETWORKADDRESS` is **not** in the mingw/Windows SDK; the probe defines it as `0x16` and prints it
  under the unambiguous name `prop16_networkaddress` (see §4: 0x16 is `SPDRP_ENUMERATOR_NAME`, and this
  build's FlexNet code actually reads property `0` = `SPDRP_DEVICEDESC`).
* Build (clean, `-Wall -Wextra`, no warnings):
  `x86_64-w64-mingw32-gcc -O1 -Wall -Wextra -o bin/hostid_probe.exe hostid_probe.c -lsetupapi -liphlpapi -lnetapi32 -lole32 -loleaut32 -luuid -lwbemuuid`

---

## 2. Wine run (verbatim)

```
$ cd /home/asdf/projects/tableau-wine
$ WINEPREFIX=$PWD/prefix/tableau WINEDEBUG=-all timeout 300 \
      ./wine-install/bin/wine ./tools/winapi/bin/hostid_probe.exe
```

Exit 0. Nothing on stderr under `-all`. The full capture (`recon/hostid_probe_wine.txt`, 152 lines):

```text
# hostid_probe v1
[meta]
meta.arch=x86_64
meta.osversion=10.0 build 19045 platform 2 csd=""
[computer]
computer.GetComputerNameW.name="ASDF-THINKPAD-E"
computer.GetComputerNameW.ok=1 lastError=0
computer.GetUserNameW.name="asdf"
computer.GetUserNameW.ok=1 lastError=0
computer.NetWkstaGetInfo.status=0 lastError=0
computer.NetWkstaGetInfo.computername="ASDF-THINKPAD-E"
computer.NetWkstaGetInfo.langroup="ASDF-THINKPAD-E"
computer.NetWkstaGetInfo.ver_major=6 ver_minor=2 platform_id=500
computer.dnshostname="asdf-ThinkPad-E16-Gen-2"
[volume]
volume.GetVolumeInformationW.C.ok=1 lastError=0 serial=0x43000000 serial_dec=1124073472 label="" fsname="NTFS" maxcomponentlen=255 flags=0x0100008a
volume.open.C.ok=1 lastError=0 handle=0000000000000054
volume.IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS.ok=1 lastError=0 bytesReturned=32
volume.extents.number=1
volume.extent.0.disks=0 start=0x0 length=0x3520f88000
[physicaldrive]
pd0.open.ok=1 lastError=0 handle=0000000000000054
pd0.IOCTL_STORAGE_QUERY_PROPERTY.ok=1 lastError=0 bytesReturned=40
pd0.desc.version=40 size=40 devicetype=0x7 modifier=0x0 removable=0 queueing=0 bustype=1 rawprops=0 vendor_off=0 product_off=0 revision_off=0 serial_off=0
pd0.vendor=""
pd0.product=""
pd0.revision=""
pd0.serial=""
pd0.sizequery.ok=1 lastError=0 bytesReturned=8 size=40
[adapters]
adapters.GetAdaptersInfo.size.status=111 needed=2960 lastError=0
adapters.GetAdaptersInfo.status=0 lastError=0
adapters.GetAdaptersInfo.0.type=6 dhcp=1 addrlen=6 mac="C8:53:09:CF:EE:0C"
adapters.GetAdaptersInfo.0.desc="enp0s31f6"
adapters.GetAdaptersInfo.0.ip="0.0.0.0"
adapters.GetAdaptersInfo.1.type=71 dhcp=1 addrlen=6 mac="28:95:29:D0:83:7E"
adapters.GetAdaptersInfo.1.desc="wlp0s20f3"
adapters.GetAdaptersInfo.1.ip="192.168.0.2"
adapters.GetAdaptersInfo.2.type=6 dhcp=1 addrlen=6 mac="52:54:00:2F:E8:7D"
adapters.GetAdaptersInfo.2.desc="virbr0"
adapters.GetAdaptersInfo.2.ip="192.168.122.1"
adapters.GetAdaptersInfo.3.type=6 dhcp=1 addrlen=6 mac="FE:54:00:15:24:FB"
adapters.GetAdaptersInfo.3.desc="vnet0"
adapters.GetAdaptersInfo.3.ip="0.0.0.0"
adapters.GetAdaptersInfo.count=4
adapters.GetAdaptersAddresses.size.status=111 needed=3144 lastError=0
adapters.GetAdaptersAddresses.status=0 lastError=0
adapters.GetAdaptersAddresses.0.iftype=71 operstatus=1 addrlen=6 mac="28:95:29:D0:83:7E"
adapters.GetAdaptersAddresses.0.friendlyname="wlp0s20f3"
adapters.GetAdaptersAddresses.0.desc="wlp0s20f3"
adapters.GetAdaptersAddresses.1.iftype=6 operstatus=1 addrlen=6 mac="FE:54:00:15:24:FB"
adapters.GetAdaptersAddresses.1.friendlyname="vnet0"
adapters.GetAdaptersAddresses.1.desc="vnet0"
adapters.GetAdaptersAddresses.2.iftype=6 operstatus=1 addrlen=6 mac="52:54:00:2F:E8:7D"
adapters.GetAdaptersAddresses.2.friendlyname="virbr0"
adapters.GetAdaptersAddresses.2.desc="virbr0"
adapters.GetAdaptersAddresses.3.iftype=6 operstatus=1 addrlen=6 mac="C8:53:09:CF:EE:0C"
adapters.GetAdaptersAddresses.3.friendlyname="enp0s31f6"
adapters.GetAdaptersAddresses.3.desc="enp0s31f6"
adapters.GetAdaptersAddresses.4.iftype=24 operstatus=1 addrlen=0 mac=""
adapters.GetAdaptersAddresses.4.friendlyname="lo"
adapters.GetAdaptersAddresses.4.desc="lo"
adapters.GetAdaptersAddresses.count=5
[pnpnet]
pnpnet.GUID_DEVCLASS_NET.flags_PRESENT.ok=1 lastError=0 handle=00007ffffe821a90
pnpnet.GUID_DEVCLASS_NET.flags_PRESENT.enum.count=0 lastError=259
pnpnet.GUID_DEVCLASS_NET.flags_ALL.ok=1 lastError=0 handle=00007ffffe2632e0
pnpnet.GUID_DEVCLASS_NET.flags_ALL.enum.count=0 lastError=259
[smbios]
smbios.GetSystemFirmwareTable.size=501 lastError=122
smbios.GetSystemFirmwareTable.ok=501 size=501 lastError=0
smbios.header.used20=0 major=3 minor=0 dmi_revision=0 length=493
smbios.struct.0.type=0 handle=0x0000 length=24
smbios.struct.0.vendor="LENOVO" version="R2JET48W(1.25 )" date=""
smbios.struct.1.type=1 handle=0x0001 length=27
smbios.struct.1.system.manufacturer="LENOVO" product="21MA009TFJ" version="ThinkPad E16 Gen 2" serial="System Serial Number" sku="LENOVO_MT_21MA_BU_Think_FM_ThinkPad E16 Gen 2" family="ThinkPad E16 Gen 2"
smbios.struct.1.system.uuid_raw=C446EA3FD3084B4FA9BBC04DE00CCF0C uuid_canonical=3FEA46C4-08D3-4F4B-A9BB-C04DE00CCF0C
smbios.struct.2.type=3 handle=0x0002 length=21
smbios.struct.2.chassis.manufacturer="LENOVO" version="" serial="Chassis Serial Number"
smbios.struct.3.type=2 handle=0x0003 length=15
smbios.struct.3.baseboard.manufacturer="LENOVO" product="21MA009TFJ" version="SDK0T76530 WIN" serial="C446EA3FD3084B4FA9BBC04DE00CCF0C" asset="Not Available"
smbios.struct.4.type=4 handle=0x0004 length=48
smbios.struct.5.type=32 handle=0x0005 length=20
smbios.struct.count=6
[wmi]
wmi.CoInitializeEx.hr=0x00000000 lastError=0
wmi.CoInitializeSecurity.hr=0x00000000
wmi.CoCreateInstance.WbemLocator.hr=0x00000000
wmi.ConnectServer.ROOT_CIMV2.hr=0x00000000
wmi.CoSetProxyBlanket.hr=0x00000000
wmi.Win32_ComputerSystemProduct.query.hr=0x00000000
wmi.Win32_ComputerSystemProduct.0.UUID="C446EA3F-D308-4B4F-A9BB-C04DE00CCF0C"
wmi.Win32_ComputerSystemProduct.0.Name="21MA009TFJ"
wmi.Win32_ComputerSystemProduct.0.Vendor="LENOVO"
wmi.Win32_ComputerSystemProduct.0.Version="ThinkPad E16 Gen 2"
wmi.Win32_ComputerSystemProduct.0.IdentifyingNumber="System Serial Number"
wmi.Win32_ComputerSystemProduct.count=1
wmi.Win32_BaseBoard.query.hr=0x00000000
wmi.Win32_BaseBoard.0.Manufacturer="LENOVO"
wmi.Win32_BaseBoard.0.Product="21MA009TFJ"
wmi.Win32_BaseBoard.0.SerialNumber="C446EA3FD3084B4FA9BBC04DE00CCF0C"
wmi.Win32_BaseBoard.0.Version="SDK0T76530 WIN"
wmi.Win32_BaseBoard.0.Tag="Base Board"
wmi.Win32_BaseBoard.count=1
wmi.Win32_PhysicalMedia.query.hr=0x00000000
wmi.Win32_PhysicalMedia.0.SerialNumber="WINEHDISK"
wmi.Win32_PhysicalMedia.0.Tag="\\.\PHYSICALDRIVE0"
wmi.Win32_PhysicalMedia.count=1
wmi.Win32_NetworkAdapter.query.hr=0x00000000
wmi.Win32_NetworkAdapter.0.MACAddress="28:95:29:d0:83:7e"
wmi.Win32_NetworkAdapter.0.Description="wlp0s20f3"
wmi.Win32_NetworkAdapter.0.Name="wlp0s20f3"
wmi.Win32_NetworkAdapter.0.DeviceID="3"
wmi.Win32_NetworkAdapter.0.GUID="{00000003-0000-0000-0000-4E6574446576}"
wmi.Win32_NetworkAdapter.1.MACAddress="fe:54:00:15:24:fb"
wmi.Win32_NetworkAdapter.1.Description="vnet0"
wmi.Win32_NetworkAdapter.1.Name="vnet0"
wmi.Win32_NetworkAdapter.1.DeviceID="5"
wmi.Win32_NetworkAdapter.1.GUID="{00000005-0000-0000-0000-4E6574446576}"
wmi.Win32_NetworkAdapter.2.MACAddress="52:54:00:2f:e8:7d"
wmi.Win32_NetworkAdapter.2.Description="virbr0"
wmi.Win32_NetworkAdapter.2.Name="virbr0"
wmi.Win32_NetworkAdapter.2.DeviceID="4"
wmi.Win32_NetworkAdapter.2.GUID="{00000004-0000-0000-0000-4E6574446576}"
wmi.Win32_NetworkAdapter.3.MACAddress="c8:53:09:cf:ee:0c"
wmi.Win32_NetworkAdapter.3.Description="enp0s31f6"
wmi.Win32_NetworkAdapter.3.Name="enp0s31f6"
wmi.Win32_NetworkAdapter.3.DeviceID="2"
wmi.Win32_NetworkAdapter.3.GUID="{00000002-0000-0000-0000-4E6574446576}"
wmi.Win32_NetworkAdapter.count=4
wmi.Win32_NetworkAdapterConfiguration.query.hr=0x00000000
wmi.Win32_NetworkAdapterConfiguration.0.MACAddress="28:95:29:d0:83:7e"
wmi.Win32_NetworkAdapterConfiguration.0.Description="wlp0s20f3"
wmi.Win32_NetworkAdapterConfiguration.0.SettingID="{00000003-0000-0000-0000-000000000000}"
wmi.Win32_NetworkAdapterConfiguration.1.MACAddress="fe:54:00:15:24:fb"
wmi.Win32_NetworkAdapterConfiguration.1.Description="vnet0"
wmi.Win32_NetworkAdapterConfiguration.1.SettingID="{00000005-0000-0000-0000-000000000000}"
wmi.Win32_NetworkAdapterConfiguration.2.MACAddress="52:54:00:2f:e8:7d"
wmi.Win32_NetworkAdapterConfiguration.2.Description="virbr0"
wmi.Win32_NetworkAdapterConfiguration.2.SettingID="{00000004-0000-0000-0000-000000000000}"
wmi.Win32_NetworkAdapterConfiguration.3.MACAddress="c8:53:09:cf:ee:0c"
wmi.Win32_NetworkAdapterConfiguration.3.Description="enp0s31f6"
wmi.Win32_NetworkAdapterConfiguration.3.SettingID="{00000002-0000-0000-0000-000000000000}"
wmi.Win32_NetworkAdapterConfiguration.count=4
wmi.Win32_ComputerSystem.query.hr=0x00000000
wmi.Win32_ComputerSystem.0.Name="ASDF-THINKPAD-E"
wmi.Win32_ComputerSystem.0.Domain="WORKGROUP"
wmi.Win32_ComputerSystem.0.UserName="ASDF-THINKPAD-E\asdf"
wmi.Win32_ComputerSystem.0.Manufacturer="LENOVO"
wmi.Win32_ComputerSystem.0.Model="21MA009TFJ"
wmi.Win32_ComputerSystem.count=1
# end
```

The block above is the file's content verbatim; the file itself is stored with **CRLF** line endings
(`file recon/hostid_probe_wine.txt` → `ASCII text, with CRLF line terminators`), because the mingw-w64
program's msvcrt stdout is in text mode. The guest capture will be CRLF for the same reason, so a
`diff --strip-trailing-cr` (not a bare `diff`) is the right comparison tool.

### What Wine printed on the error/debug channels

* `WINEDEBUG=-all`: **no** `err:`/`warn:`/`fixme:` lines; exit 0. The only stderr content is what the
  probe itself prints, now in the capture above.
* `WINEDEBUG=fixme+mountmgr,err+all` (`recon/hostid_probe_wine_debug.txt`) additionally shows:
  * `fixme:ole:CoInitializeSecurity ... stub` — Wine accepts the call and returns `S_OK` anyway
    (probe: `wmi.CoInitializeSecurity.hr=0x00000000`);
  * `fixme:wbemprox:client_security_SetBlanket` / `client_security_Release` — the `CoSetProxyBlanket`
    path, also returns `S_OK`;
  * `fixme:ntdll:NtQuerySystemInformation info_class SYSTEM_PERFORMANCE_INFORMATION`.
  * **No** `err:` lines at all.
* The mountmgr FIXMEs (`Faking StorageDeviceProperty data`, `IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS
  semi-stub`) do **not** appear in this capture: `mountmgr.sys` runs inside the `winedevice.exe` driver
  host process, whose `WINEDEBUG` is fixed when that process starts. Their existence is proven by source
  (`dlls/mountmgr.sys/device.c:1595`, `:1947`) and by the values the probe received (§5).

---

## 3. Windows-side invocation (guest) — exact command for the parent

The probe is already downloadable from the hub: `vmshare/hostid_probe.exe` (md5
`b9ef3a833ce93f08e4be421b5be6dfbd`, `curl http://127.0.0.1:8000/hostid_probe.exe` → 200, 390 689 B).

**Run this (parent only — `tools/guest.sh` is parent-owned):**

```bash
tools/guest.sh 'Invoke-WebRequest -UseBasicParsing http://192.168.122.1:8000/hostid_probe.exe -OutFile C:\Users\adsf\hostid_probe.exe; Start-Process -FilePath cmd.exe -ArgumentList "/c C:\Users\adsf\hostid_probe.exe > C:\Users\adsf\hostid_probe_guest.txt 2>&1" -Verb RunAs -Wait; Get-Content C:\Users\adsf\hostid_probe_guest.txt' 240
```

* The elevated wrapper is required because `\\.\PhysicalDrive0` and `\\.\C:` need administrator rights;
  on this guest `ConsentPromptBehaviorAdmin=0`/`PromptOnSecureDesktop=0` are set, so `-Verb RunAs`
  elevates silently. If UAC is ever restored to prompt mode, drive it with `tools/win_uac_click.sh`.
* The output comes back through the hub inside `guest_cmd_out.txt` (the poller prints the command's
  stdout), so the parent can save it verbatim as `recon/hostid_probe_windows.txt`.
* Non-elevated fallback (most sections still print; the two disk opens report `lastError=5`):
  `tools/guest.sh 'Invoke-WebRequest -UseBasicParsing http://192.168.122.1:8000/hostid_probe.exe -OutFile C:\Users\adsf\hostid_probe.exe; & C:\Users\adsf\hostid_probe.exe' 240`
* Then diff: `diff -u recon/hostid_probe_wine.txt recon/hostid_probe_windows.txt`.

Expected Windows-side differences to look for: a real `StorageDeviceProperty` vendor/product/serial, a
`\\.\C:` extent with a non-zero start offset, a real SMBIOS UUID (not the host machine-id), a real
`SPDRP_NETWORKADDRESS`/device list, a domain instead of `WORKGROUP` (if joined), a real
`Win32_PhysicalMedia.SerialNumber`, and `NetWkstaGetInfo.langroup` = workgroup/domain rather than the
computer name.

---

## 4. Which identity APIs the FlexNet client actually uses

Measured from the shipped binaries (import tables via `pefile`; strings via `strings -a`), cross-referenced
with `recon/LICENSE_RISK.md` and `recon/TABLEAU_STACK.md`:

`Tableau 2026.2/bin/tabfnp.dll` (identical code to `custactutil_libFNP.dll`) imports:

| DLL | identity-relevant imports |
|---|---|
| `IPHLPAPI.DLL` | `GetAdaptersInfo` |
| `SETUPAPI.dll` | `SetupDiGetClassDevsA`, `SetupDiEnumDeviceInfo`, `SetupDiGetDeviceRegistryPropertyA`, `SetupDiGetDeviceInstanceIdA`, `SetupDiDestroyDeviceInfoList` |
| `KERNEL32.dll` | `DeviceIoControl`, `GetVolumeInformationA`, `GetComputerNameA`, `QueryDosDeviceA`, `DefineDosDeviceA` |
| `ADVAPI32.dll` | `OpenSCManagerA`, `RegQueryValueA`, `RegQueryValueExA` |
| `ole32.dll` | `CoCreateInstance`, `CoInitialize(Ex)`, `CoInitializeSecurity`, `CoSetProxyBlanket` |
| `snmpapi.dll` | `SnmpUtilOidCpy`, … (raw NIC enumeration fallback) |

Strings in the same DLL: `s_cacheNetIfDataViaIOCTL`, `s_cacheNetIfDataViaWMI`, `s_getMACAddressFromDevice`,
`Attempting to read SMBIOS UUID from WMI....`, `Failed to read SMBIOS UUID`, `SMBIOS UUID successfully read`,
`SELECT UUID FROM Win32_ComputerSystemProduct`, `SELECT * FROM Win32_NetworkAdapter`, `Win32_BaseBoard`,
`GetAdaptersInfo returned an error = %d`, `SetupDiGetClassDevs(%d)`, `serverHostID`.

**Two corrections to the usual "FlexNet reads the disk serial via `IOCTL_STORAGE_QUERY_PROPERTY`" story:**

1. In this build, `SetupDiGetDeviceRegistryPropertyA` is called exactly once, from
   `tabfnp.dll+0x3c0db5`, with `r8d = 0` i.e. **`SPDRP_DEVICEDESC`**, not `SPDRP_NETWORKADDRESS`; the
   device identity is obtained from `SetupDiGetDeviceInstanceIdA` (buffer 0x1000) in the same loop. The
   probe still queries `0x16` (`SPDRP_NETWORKADDRESS`/`SPDRP_ENUMERATOR_NAME`) so both readings are
   visible, but the real unit of comparison is the device description + instance ID.
2. The **service process** is the one that touches the disk: the ProcMon trace of
   `FNPLicensingService64.exe` (`state/win-trace/tab.csv`, 344 `DeviceIoControl`s; recorded in `STATE.md`)
   shows `\Device\Harddisk0\DR0` + **`IOCTL_DISK_GET_DRIVE_GEOMETRY`**, not
   `IOCTL_STORAGE_QUERY_PROPERTY`. Wine implements that one (`dlls/mountmgr.sys/device.c:1885`, `:1900`),
   so the disk-geometry read is *not* the first blocker; the `StorageDeviceProperty` probe here is still
   the right way to see what a `StorageDeviceProperty`-based hostid would get.

---

## 5. Per-input Wine verdict (real / faked / absent)

| input | Wine answer (measured) | verdict | Wine source |
|---|---|---|---|
| `\\.\PhysicalDrive0` open | `ok=1`, handle `0x54` | **real** (device object exists) | `mountmgr.sys` creates `\Device\HarddiskN\DRN`; `device.c` `disk_create` |
| `IOCTL_STORAGE_QUERY_PROPERTY`/`StorageDeviceProperty` | `ok=1`, `Size=40`, `DeviceType=0x7`, `BusType=1` (SCSI), all four string offsets `0` → vendor/product/revision/**serial** empty | **faked** (constant empty descriptor) | `dlls/mountmgr.sys/device.c:1595` (`FIXME("Faking StorageDeviceProperty data")`), fields set `:1605-1614`; dispatch `:1967` |
| `IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS` | `ok=1`, `NumberOfDiskExtents=1`, `DiskNumber=0`, `StartingOffset=0` (hardcoded), `ExtentLength=0x3520f88000` (host fs size) | **faked / semi-stub** | `device.c:1929` handler, `:1943` hardcoded offset, `:1947` `FIXME("... semi-stub.")` |
| `GetVolumeInformationW("C:\\")` | `ok=1`, serial `0x43000000`, label `""`, `fsname="NTFS"`, `flags=0x0100008a` | **real API, host-derived values** — serial comes from the mountmgr volume (no superblock serial → filled from the volume GUID), and `NTFS` is the catch-all mapping for a non-FAT/non-ISO host filesystem | `dlls/kernelbase/volume.c:143`; serial `device.c:1038-1039` (fallback) / `:1716`; `get_mountmgr_fs_type` default `device.c:1412-1422`; host fs is **ext4** (`df -T /`) |
| `GetAdaptersInfo` | `ok=1`, 4 adapters, real MACs incl. `52:54:00:2F:E8:7D` (virbr0) and `FE:54:00:15:24:FB` (vnet0) | **real** (host NICs, incl. the VM bridge interfaces) | `dlls/iphlpapi/iphlpapi_main.c:597` |
| `GetAdaptersAddresses` | `ok=1`, 5 entries (adds `lo`, no MAC) | **real** (host NICs) | `dlls/iphlpapi/iphlpapi_main.c:1329` |
| `SetupDiGetClassDevsW(GUID_DEVCLASS_NET)` | `ok=1`, but `enum.count=0`, `lastError=259` (`ERROR_NO_MORE_ITEMS`) with **and** without `DIGCF_PRESENT` | **absent** (empty device set) | `dlls/setupapi/devinst.c:2106`; enumeration `:1996` (`CM_Get_Device_ID_ListW` + `HKLM\SYSTEM\...\Enum`) has no net-class PnP entries in the prefix |
| `SetupDiGetDeviceRegistryPropertyW` / instance id | n/a (0 devices) | **absent** | `devinst.c:3054` |
| `GetSystemFirmwareTable('RSMB', 0)` | `ok`, 501 B, synthesized SMBIOS `3.0`, host DMI strings (LENOVO / 21MA009TFJ / ThinkPad E16 Gen 2) | **synthesized** (real vendor strings from `/sys/class/dmi/id`, fabricated table) | `dlls/ntdll/unix/system.c:2293` (`create_smbios_data`, linux), `:2512`/`:2533` (RSMB) |
| SMBIOS type-1 UUID | `C446EA3FD3084B4FA9BBC04DE00CCF0C` = **the host's `/etc/machine-id`** (`c446ea3fd3084b4fa9bbc04de00ccf0c`), canonical `3FEA46C4-…`, **not** the firmware UUID | **faked** (machine-id substituted for the SMBIOS UUID) | `system.c:2227` `get_system_uuid` → `:2242` `open("/var/lib/dbus/machine-id")` |
| SMBIOS serials | product serial `"System Serial Number"`, chassis serial `"Chassis Serial Number"`, board serial = the UUID hex | **faked** (fallbacks; the DMI files are root-only) | `system.c:2264-2290` (`get_system_serial`/`get_chassis_serial`/`get_board_serial`) |
| WMI COM bootstrap | all HRESULTs `0x0` (init/security/locator/connect/proxy blanket); `CoInitializeSecurity` is a `fixme` stub that returns `S_OK` | **works** | `dlls/wbemprox/*`, `dlls/ole32/*` |
| WMI `Win32_ComputerSystemProduct` | `hr=0`, 1 row; UUID = the same machine-id UUID; `IdentifyingNumber="System Serial Number"` | **faked values** (derived from Wine's synthesized SMBIOS) | `dlls/wbemprox/builtin.c:2068` `fill_compsysproduct`; UUID getter uses the SMBIOS table |
| WMI `Win32_BaseBoard` | `hr=0`, LENOVO / 21MA009TFJ / `SDK0T76530 WIN` (host DMI), `SerialNumber` = UUID hex | **mixed** — strings real, serial faked | `builtin.c:1607` `fill_baseboard` (falls back to UUID hex) |
| WMI `Win32_PhysicalMedia` | `hr=0`, `SerialNumber="WINEHDISK"` | **faked** (hardcoded, not even the disk's) | `builtin.c:1284-1286` (`data_physicalmedia[] = { L"WINEHDISK", L"\\\\.\\PHYSICALDRIVE0" }`) |
| WMI `Win32_DiskDrive` (not probed; same path) | falls back to `WINEHDISK` when `StorageDeviceProperty` has no serial | **faked fallback** | `builtin.c:2617-2655` (`get_diskdrive_serialnumber`), `:2654` |
| WMI `Win32_NetworkAdapter` | `hr=0`, real MACs; `GUID="{0000000N-0000-0000-0000-4E6574446576}"` (`"NetDev"` placeholder); `PNPDeviceID` hardcoded Intel `PCI\VEN_8086&DEV_100E...`; `Manufacturer="The Wine Project"` | **MACs real, identifiers faked** | `builtin.c:3216` `fill_networkadapter`, `:3249` guid, `:3254` pnpdevice_id, `:3191` `get_networkadapter_guid`; placeholder GUID built in `dlls/nsiproxy.sys/ndis.c:303-304` (`memcpy(entry->if_guid.Data4 + 2, "NetDev", 6)`) |
| WMI `Win32_NetworkAdapterConfiguration` | `hr=0`, real MACs, `SettingID="{0000000N-0000-0000-0000-000000000000}"` | **MACs real, SettingID faked** | `builtin.c:3459` `fill_networkadapterconfig` |
| WMI `Win32_ComputerSystem` | `hr=0`, real name/user, `Domain="WORKGROUP"` | **name/user real, domain hardcoded** | `builtin.c` `fill_computersystem`, `:2015` `rec->domain = L"WORKGROUP"` |
| `GetComputerNameW` / `GetComputerNameExW` | `ok=1`, `ASDF-THINKPAD-E`, DNS hostname `asdf-ThinkPad-E16-Gen-2` | **real** (registry-backed from `wineboot`; differs from the Windows guest's name) | `dlls/kernel32/computername.c:41` → `dlls/kernelbase/registry.c:3699` |
| `GetUserNameW` | `ok=1`, `asdf` (host unix user) | **real** | `dlls/advapi32/advapi.c:60` |
| `NetWkstaGetInfo(100)` | `status=0`, `computername` real, `langroup="ASDF-THINKPAD-E"` (the LSA account domain = computer name) | **implemented, semantically different** (Windows returns the workgroup/AD domain) | `dlls/netapi32/netapi32.c:913`, domain via `LsaQueryInformationPolicy(PolicyAccountDomainInformation)` `:972` |
| volume serial of `C:` | `0x43000000` (same as `GetVolumeInformationW`) | **host-derived** (see above) | `device.c:1038-1039` |

---

## 6. Caveats / open items

* The probe's `[smbios]`/`[wmi]` "real host data" is read by the *Wine process* as `asdf`; the DMI files
  `/sys/class/dmi/id/{product_uuid,product_serial,board_serial}` are mode `0400 root:root` on this host,
  which is exactly why Wine substitutes `/etc/machine-id` and the `"…Serial Number"` fallbacks.
* `WINEDEBUG=-all` hides Wine's FIXMEs (which is what the task specified for the capture); the fixme
  evidence for the faked paths is cited from source in §5 and from the debug capture in §2.
* The probe writes nothing to the filesystem and creates no windows, so it is safe to run in the existing
  `prefix/tableau`; it does not require a display.
* Host conditions at capture time: `df -h /` → 40 G free (163 G used, 81 %); `free -g` → 18 GiB
  available. One compile earlier was killed by `tools/mem_guard.sh` at 87 % used (another agent's build);
  it was retried after memory recovered.
* Not measured here (needs the guest run): the actual Windows hostid value FlexNet would compute. The
  mission acceptance point (`STATE.md` §5b) is parity at the licensing gate, so this probe is a
  measurement tool, not a blocker by itself.
