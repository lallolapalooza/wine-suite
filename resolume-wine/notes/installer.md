# Resolume Arena 7.28.0 Installer analysis

Target: `/home/asdf/Downloads/Resolume_Arena_7_28_0_rev_24303_Installer.exe`
(1,715,490,072 bytes, PE32 i386 Inno Setup **6.1.0 (unicode)** loader) and its extracted
payload `/home/asdf/projects/resolume-wine/installer/media_x/`.

All findings below were produced with `innoextract` 1.9 plus a locally built
debug-enabled `innoextract` (so the decoded `[Setup]` header / `[Run]` / `[Files]`
entries could be read directly), and with `strings` on the raw setup data. Scratch
work lives in `state/tmp/`. Nothing outside this file was modified.

Tool used throughout:

```
$ export LD_LIBRARY_PATH=/tmp/inno/x/usr/lib/x86_64-linux-gnu
$ /tmp/inno/x/usr/bin/innoextract --version
innoextract 1.9
```

---

## 0. Confirming it is Inno Setup 6.1.0

```
$ /tmp/inno/x/usr/bin/innoextract -i .../Resolume_Arena_7_28_0_rev_24303_Installer.exe
Inspecting "Resolume Arena 7.28.0 rev 24303" - setup data version 6.1.0 (unicode)

Languages:
 - default: English

No GOG.com game ID found!

Setup is not passworded!

Done.
```

`innoextract -l -s` lists **1180 entries** (`tmp/…`, `app/…`, `pf/…`):

```
$ innoextract -l -s .../Resolume_Arena_7_28_0_rev_24303_Installer.exe
tmp/Bonjour64.msi
tmp/VC_redist_2022.x64.exe
tmp/vulkan-runtime.exe
app/Arena.exe
app/avcodec-61.dll
...
$ ... | wc -l
1180
```

Decoded header (via locally-built `innoextract --debug -i`) confirms the engine:

```
known version: "Inno Setup Setup Data (6.1.0) (u)"
[block] size: 50603  compression: lzma1
...
Inspecting "Resolume Arena 7.28.0 rev 24303" - setup data version 6.1.0 (unicode)
```

---

## 1. Silent / unattended command line

`innoextract -i` does **not** print the command-line switches (it only reports
version/languages/password). The switches are the *generic Inno Setup 6.1.0
loader help text*, which is present as UTF-16 strings in the installer stub.
`strings -el` (16-bit little-endian) on the EXE extracts them:

```
$ strings -el -n 4 .../Resolume_Arena_7_28_0_rev_24303_Installer.exe | grep -n -E \
    '/VERYSILENT|/SILENT|/SUPPRESSMSGBOXES|/NORESTART|/DIR=|/ALLUSERS|/CURRENTUSER|/SP-'
137:/SP-
143:/ALLUSERS
144:Instructs Setup to install in administrative install mode.
145:/CURRENTUSER
146:Instructs Setup to install in non administrative install mode.
152:/SILENT, /VERYSILENT
153:Instructs Setup to be silent or very silent.
154:/SUPPRESSMSGBOXES
155:Instructs Setup to suppress message boxes.
162:/NORESTART
186:/DIR="x:\dirname"
```

All of `/SP- /SILENT /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOCANCEL
/CLOSEAPPLICATIONS /NOCLOSEAPPLICATIONS /FORCECLOSEAPPLICATIONS /LOG[="file"]
/LOADINF /SAVEINF /LANG /DIR="x:\dir" /GROUP="folder" /NOICONS /TYPE /COMPONENTS
/TASKS /MERGETASKS /PASSWORD` are present in the engine help block
(`strings -el`, lines 137–193). So the installer **accepts**: `VERYSILENT`,
`/SUPPRESSMSGBOXES`, `/NORESTART`, `/DIR=`, and (engine-side) `/ALLUSERS`,
`/CURRENTUSER`.

### Recommended command line

```
Resolume_Arena_7_28_0_rev_24303_Installer.exe /VERYSILENT /SUPPRESSMSGBOXES \
    /NORESTART /SP- /LOG="C:\resolume-install.log" \
    /DIR="C:\Program Files\Resolume Arena"
```

### `/ALLUSERS` and `/CURRENTUSER` are ineffective on THIS installer

The decoded `[Setup]` header shows `PrivilegesRequiredOverridesAllowed` is empty:

```
$ innoextract --debug -i ...   (excerpt)
Privileges required: 2
```

`2` is `Admin` (`stored_privileges_1` map = `NoPrivileges=0, PowerUser=1, Admin=2,
Lowest=3`; the other `PrivilegesRequiredOverridesAllowed` flag byte decodes to 0 =
neither `commandline` nor `dialog`). Per the Inno Setup docs, `/ALLUSERS` /
`/CURRENTUSER` only have an effect when `PrivilegesRequiredOverridesAllowed`
allows the commandline override:

> **/ALLUSERS** Instructs Setup to install in administrative install mode. *Only
> has an effect when the [Setup] section directive
> PrivilegesRequiredOverridesAllowed allows the commandline override.*
> — https://jrsoftware.org/ishelp/topic_setupcmdline.htm

Because this script leaves it blank, `/ALLUSERS` and `/CURRENTUSER` are accepted
by the parser but **ignored**; the install always runs as `admin`
(`PrivilegesRequired=admin`). [INFERENCE from the two observations above:
engine supports the switches, header disables the override.]

Note: because the script sets `DisableDirPage=yes`, the directory page is not
shown, but `/DIR=` still overrides the destination (the directive only hides the
page).

---

## 2. Default install directory and uninstall registry key

Decoded `[Setup]` header (`innoextract --debug -i`, lines 40–77 of the dump):

```
App name: "Resolume Arena"
App ver name: "Resolume Arena 7.28.0 rev 24303"
App id: "Resolume Arena"
Publisher: "Resolume"
Version: "7.28.0.24303"
Default dir name: "{pf}\Resolume Arena"
Default group name: "Resolume Arena"
Uninstall files dir: "{app}"
Uninstall reg key: "yes"
Uninstallable: "yes"
...
Min version: 0.0  nt 10.010240 (Windows 10)
Back color: ff0000
Uninstall log mode: append
Uninstall style: modern
Dir exists warning: auto
Privileges required: 2
Show language dialog: yes
Language detection: 0
Compression: lzma2
Architectures allowed: amd64
Architectures installed in 64-bit mode: amd64
Disable dir page: yes
Disable program group page: yes
Options: ... create app dir, ... use previous app dir, ... signed uninstaller,
         ... disable dir page
```

* **Default install dir**: `{pf}\Resolume Arena`. With
  `ArchitecturesInstallIn64BitMode=amd64`, on 64-bit Windows `{pf}` resolves to
  the native 64-bit `C:\Program Files`, so the default is
  **`C:\Program Files\Resolume Arena`**. `UsePreviousAppDir` is set, so on
  reinstall the previous directory is reused. [INFERENCE for the literal
  `C:\Program Files` expansion; `{pf}` + 64-bit mode is observed.]
* **AppId**: `Resolume Arena` (a plain string, **not** a GUID).
* **Uninstallable = yes**, **UninstallRegKey = yes**, so an uninstall entry is
  written. Inno Setup names the uninstall subkey after `AppId` with the literal
  suffix `_is1` (https://jrsoftware.org/ishelp/topic_setup_appid.htm,
  https://stackoverflow.com/questions/61174457).
* Because `PrivilegesRequired=admin` and the overrides are disabled, the key is
  written under the **administrative (HKLM)** root, in the 64-bit registry view
  (64-bit install mode):

  **`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Resolume Arena_is1`**

  (No `HKCU\...\Uninstall` entry is created for this installer; that root is only
  used by non-administrative installs.) [INFERENCE: exact key name from the
  observed `AppId`, `Uninstallable/UninstallRegKey=yes`, `PrivilegesRequired=Admin`
  and Inno's documented naming convention.]

`Uninstall files dir: {app}` means the generated `unins000.exe/.dat` are placed in
the install dir. An uninstaller run entry calls
`netsh ... firewall ... delete rule ...` (see §3).

---

## 3. Prerequisites launched by the installer

The three runtime prerequisites are **not** `[Run]` entries; they are shipped as
temporary files (`[Files]` with `deleteafterinstall`) and executed from the
`[Code]` (Pascal script) `AfterInstall` handlers. The `[Files]` entries and their
`Check`/`AfterInstall` handlers:

```
$ innoextract --debug -i ...   (excerpt: Files)
 - "{tmp}\Bonjour64.msi" (location: 0)
  Check: "not BonjourInstalled"
  After install: "InstallBonjour"
  Options: never uninstall, delete after install
 - "{tmp}\VC_redist_2022.x64.exe" (location: 1)
  Check: "not VS2022Installed"
  After install: "InstallVS('2022')"
  Options: never uninstall, delete after install
 - "{tmp}\vulkan-runtime.exe" (location: 2)
  After install: "InstallVulkan"
  Options: never uninstall, delete after install
```

The actual command lines are string literals inside the compiled `[Code]`
section (dumped from the decompressed header, `strings -el`):

```
$ strings -el -n 3 state/tmp/header_dec.bin   (excerpt)
Installing Apple Bonjour...
{tmp}
/i "
{tmp}\Bonjour64.msi
" /quiet
msiexec.exe
Apple Bonjour installation failed with error code:
Installing Visual C++ 
 redistributables...
{tmp}
/quiet /norestart
{tmp}\VC_redist_
.x64.exe
Visual C++ 
 redistributables installation failed with error code:
Microsoft.Update.Session
IsInstalled=1
2999226
Making sure Vulkan runtime is installed...
{tmp}
{tmp}\vulkan-runtime.exe
Vulkan Runtime installation failed with error code:
```

### Apple Bonjour  (tmp/Bonjour64.msi, 2,682,368 bytes)

* Guarded by `Check: "not BonjourInstalled"`, run by `InstallBonjour`.
* Command built from literals `msiexec.exe` + `/i "` + `{tmp}\Bonjour64.msi` +
  `" /quiet`, i.e.:

  ```
  msiexec.exe /i "{tmp}\Bonjour64.msi" /quiet
  ```

* Failure surfaces as `"Apple Bonjour installation failed with error code: "`.

### Visual C++ 2022 x64 redistributable  (tmp/VC_redist_2022.x64.exe, 18,537,912 bytes)

* Guarded by `Check: "not VS2022Installed"` (function `InstallVS('2022')`).
* Filename is assembled from `{tmp}\VC_redist_` + version + `.x64.exe`
  (→ `{tmp}\VC_redist_2022.x64.exe`) and run with `/quiet /norestart`:

  ```
  {tmp}\VC_redist_2022.x64.exe /quiet /norestart
  ```

* The version test inspects `SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64`
  and the `VC,redist.x64,amd64,14.22,bundle` dependency key, comparing against
  `14.50.35710.00`; literals `Microsoft.Update.Session`, `IsInstalled=1`,
  `2999226` are also present (KB2999226 fallback check).
* Failure: `"Visual C++ <ver> redistributables installation failed with error code: "`.

### Vulkan Runtime  (tmp/vulkan-runtime.exe, 1,932,376 bytes)

* Run by `InstallVulkan`, status string `"Making sure Vulkan runtime is installed..."`.
* Only the literal `{tmp}\vulkan-runtime.exe` appears; **no** parameter string is
  present in the code string table (no `/S`, `/silent`, `/quiet`, `-s`), so the
  installer exec's it **with no command-line arguments**. [Observed: absence of an
  args literal next to the filename; the file itself would need to be inspected to
  know whether it is self-silent.]
* Failure: `"Vulkan Runtime installation failed with error code: "`.

### Adobe DXV plugins (optional, task `adobeplugins`)

`{tmp}\DXV3AfterEffectsExport.aex`, `{tmp}\DXV3MediaCoreExport.prm`,
`{tmp}\DXV3MediaCoreImport.prm`, and `{tmp}\ffmpeg\*.dll` (avcodec-61,
avformat-61, avutil-59, swscale-8, msvcp140, vcruntime140, vcruntime140_1,
ffmpeg.manifest) all carry `Tasks: "adobeplugins"`, `Check: "AdobeInstalled"`,
`After install: "InstallAdobePlugins"`, `Options: never uninstall, delete after
install`. They are copied by `InstallAdobePlugins` into the Adobe Common plug-in
folders (error strings: "Cannot create directory for the Resolume DXV Adobe
plugins", "Failed to copy Resolume DXV Adobe plugin file..."). Source strings also
list the legacy FFmpeg DLL set (`avcodec-57/58/59/60`, `swscale-4/5/6`) used to
match the installed Adobe host version.

### Actual `[Run]` entries (6) and `[UninstallRun]` entries (4)

`[Run]` is unrelated to the prerequisites; it does firewall rules, launches the
app and fixes Wire's license-file permissions:

```
$ innoextract --debug -i ...   (excerpt)
Run entries:
 - "{sys}\netsh.exe":
  Parameters: "advfirewall firewall add rule name="Resolume Arena" dir=in program="{app}\Arena.exe" action=allow"
  Status message: "Adding Firewall rules for Arena..."
 - "{sys}\netsh.exe":
  Parameters: "advfirewall firewall add rule name="Resolume Arena" dir=out program="{app}\Arena.exe" action=allow"
 - "{app}\Arena.exe":
  Check: "not CommandLineParamExists('/DontLaunch')"
  Wait: 1
  Options: post install, skip if silent, run as original user
 - "{sys}\netsh.exe":     Parameters: 108 bytes  ("Resolume Wire" dir=in)
 - "{sys}\netsh.exe":     Parameters: 109 bytes  ("Resolume Wire" dir=out)
 - "{pf}\Resolume Wire\Wire.exe":
  Parameters: "--FixLicensePermissions"
  Status message: "Ensuring registration file permissions..."

Uninstall run entries:
 - "{sys}\netsh.exe": "firewall advfirewall firewall delete rule name="Resolume Arena" dir=in program="{app}\Arena.exe""
 - "{sys}\netsh.exe": "firewall advfirewall firewall delete rule name="Resolume Arena" dir=out program="{app}\Arena.exe""
 - "{sys}\netsh.exe": "firewall advfirewall firewall delete rule name="Resolume Wire" dir=in program="{pf}\Resolume Wire\Wire.exe""
 - "{sys}\netsh.exe": "firewall advfirewall firewall delete rule name="Resolume Wire" dir=out program="{pf}\Resolume Wire\Wire.exe""
```

(The two "108/109 bytes" parameters print as a byte count in the debug dump but are
readable in the header string table, e.g.
`advfirewall firewall add rule name="Resolume Wire" dir=in program="{pf}\Resolume
Wire\Wire.exe" action=allow` at `state/tmp/header_dec_strs.txt:1895`.)

**Important for a silent Wine install:** the “launch Arena” run entry has
`Options: … skip if silent`, so under `/SILENT` or `/VERYSILENT` the app is *not*
started at the end (a `/DontLaunch` parameter would also suppress it). The netsh
rules and the `Wire.exe --FixLicensePermissions` step still run; both `netsh.exe`
and `Wire.exe` executions are good candidates to stub/skip under Wine (netsh
firewall is meaningless there).

---

## 4. What `tmp/` vs `app/` vs `pf/` mean

* **`tmp/`** → `[Files]` destinations of the form `{tmp}\…` with
  `Options: never uninstall, delete after install`. They are extracted to the
  installer's temp dir during install, used by `[Code]`
  (`InstallBonjour`, `InstallVS`, `InstallVulkan`, `InstallAdobePlugins`), then
  deleted. Contents: `Bonjour64.msi`, `VC_redist_2022.x64.exe`,
  `vulkan-runtime.exe`, the three DXV Adobe plugins and `ffmpeg\*.dll` staging.
  They are **not** part of the installed program.
* **`app/`** → `{app}`, which is `DefaultDirName` = `{pf}\Resolume Arena`
  (i.e. `C:\Program Files\Resolume Arena`). These are the permanent Arena program
  files (`Arena.exe`, its DLLs, `ai-models/`, `plugins/`, `docs/`, `licenses/`,
  `luts/`, `mcp/`, `default/`, `rest/`, …). File options are `ignore version`
  (permanent, not deleted-after-install).
* **`pf/`** → **fixed** destinations independent of `{app}`:
  `{pf}\Resolume Wire\…` (Wire.exe, WireLib/WireNodes/onnxruntime/DirectML DLLs,
  ai-models, licenses, default presets) and `{pf}\Resolume Alley\…`
  (Alley.exe + its DLLs/licenses/presets). These install under
  `C:\Program Files\Resolume Wire` and `C:\Program Files\Resolume Alley` even
  though the main app is in `…\Resolume Arena`. Note `pf\Resolume Wire\Wire.exe`
  is a `shared file` with `uninstall no shared file prompt`.

---

## 5. Licence / activation at first run

### Installer licence agreement (EULA)

The header carries `License: 7055 bytes` and the payload file is
`app/licenses/Resolume-License.txt` (exactly 7,055 bytes), i.e. the same EULA:

```
$ head -3 .../installer/media_x/app/licenses/Resolume-License.txt
LICENSE AGREEMENT

IMPORTANT! BE SURE TO CAREFULLY READ AND UNDERSTAND ALL OF THE RIGHTS AND
RESTRICTIONS SET FORTH IN THIS END-USER LICENSE AGREEMENT ("EULA"). ...
```

The EULA is displayed/accepted during setup (`LicenseFile`). There is no serial
number requested by the installer itself.

### Registration / activation inside the app

Arena is **not** activated by the installer; it is registered from inside the
application. Evidence from `strings` on `app/Arena.exe` (59 MB):

```
$ strings -a -n 8 installer/media_x/app/Arena.exe | grep -iE \
    'watermark|not registered|serial|license file|activation'
#1 is not registered. The video and audio are watermarked.
*Video and audio are watermarked.*
No license file installed.
Enter your #1 serial number to register on this computer.
Enter your #1 serial number to register your dongle.
Resolume #1 has not been able to verify your registration for %d days. In %d days,
your registration will expire and the watermark will be shown. Please connect to
the internet and restart Resolume #1 within %d days.
Resolume #1 has not been able to verify your registration for %d days. Your
registration has expired and the watermark will be shown. ...
Failed to store license file on disk
Watermark_Arena.svg
Watermark_Arena_sdf.png
Watermark_Avenue.svg
Watermark_Avenue_sdf.png
.?AVEnterSerial@registration@@
```

Plus RTTI/type names for `RegistrationController`, `RegistrationInspector`,
`DongleManager`, `DongleWizard`, `FileWizard` (`loadLicenseFile`),
`USBStorageManager`, `PreferencesRegistrationComponent` — i.e. a
serial/dongle/online-verification registration subsystem.

So: **an unlicensed first run starts in an unregistered state and renders a
watermark** over video and audio ("#1 is not registered. The video and audio are
watermarked."). The user must enter a serial number (or use a USB dongle); the
app then stores a licence file and periodically re-verifies it online
(internet-verification/expiry messages above).

Registration file location (from decoded `[Files]`):

```
$ innoextract --debug -i ...   (excerpt)
 - "{commonappdata}\Resolume Arena\Registration\"
  Source: "{commondocs}\Resolume Arena\Registration\Registration.avr"
  Permission entry: 0
  Options: never uninstall, skip if source doesn't exist, only if doesn't exist
```

i.e. `C:\ProgramData\Resolume Arena\Registration\` is pre-created (a template
`Registration.avr` from the Common Documents folder is copied only if it does not
already exist). The `[Run]` step
`{pf}\Resolume Wire\Wire.exe --FixLicensePermissions` ("Ensuring registration
file permissions…") fixes permissions on that registration folder.

**Consequence for Wine:** no network/activation call is needed to *install* the
app; expect the watermark/unregistered UI on first run unless a serial is
entered. The online re-verification and USB-dongle paths are the parts likely to
misbehave under Wine.

---

## Summary

| Question | Answer |
|---|---|
| Silent switches | Inno 6.1.0 set: `/VERYSILENT /SILENT /SUPPRESSMSGBOXES /NORESTART /SP- /NOCANCEL /LOG="f" /DIR="d" /LANG=` …; `/ALLUSERS` `/CURRENTUSER` parsed but ignored (overrides disabled). |
| Default dir | `{pf}\Resolume Arena` → `C:\Program Files\Resolume Arena` (64-bit mode). |
| AppId / uninstall key | AppId `Resolume Arena` → `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Resolume Arena_is1` (admin, 64-bit view). |
| Prerequisites | Runtime prereqs run from `[Code]` (not `[Run]`): `msiexec.exe /i "{tmp}\Bonjour64.msi" /quiet`; `{tmp}\VC_redist_2022.x64.exe /quiet /norestart`; `{tmp}\vulkan-runtime.exe` (no args). Plus optional Adobe DXV plug-in copy. |
| tmp vs app/pf | `tmp/` = delete-after-install staging; `app/` = `{app}` permanent; `pf/` = fixed `{pf}\Resolume Wire` + `{pf}\Resolume Alley`. |
| Licensing | Installer shows EULA (7,055 B). App itself is unregistered on first run and watermarked until a serial/dongle registration, with periodic online re-verification. |
