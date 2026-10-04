# FlexNet Licensing Service 64 under Wine — measured recipe and results

Prefix: `/home/asdf/projects/tableau-wine/prefix/tableau` (app tree symlinked, **no MSI state**).
All commands below were run with `WINE=$P/wine-install/bin/wine` (Wine 11.18 + 20-patch union, built in place).

## 0. Verdict

The service **runs under Wine** and the app **reaches the Windows reference screen**.

* `tableau.com` (console) before the service: `The FlexNet Licensing Service is not installed on this machine.`
* `tableau.com` after the service: `Unable to verify license. Please activate the product.` → activation stage.
* `tableau.exe` (GUI) shows the **"Activate Tableau"** window and stays alive:
  * window tree: `logs/run-flexnet/windows_024.txt` → `"Activate Tableau": ("tableau.exe") 650x478+624+350`
  * frame: **`logs/run-flexnet/frame_024.png`** (root capture) and **`logs/run-flexnet/activate-tableau-window.png`**
    (window-only capture, X id `0x1400013`, 650×478) — "Welcome to Tableau Desktop / Activate your Tableau
    license to get started", with *Use Tableau for free* / *Activate with product key* / *Activate by signing
    in to a server* / *Exit*.

No guest files are needed — everything came from `vmshare/tabharvest.zip`.

## 1. Recipe (reproducible)

```bash
P=/home/asdf/projects/tableau-wine
WINE=$P/wine-install/bin/wine
export WINEPREFIX=$P/prefix/tableau
export WINEDLLOVERRIDES='msvcp140,msvcp140_1,msvcp140_2,vcruntime140,vcruntime140_1,mfc140u,mfc140=n'
```

1. **Apply the harvested Windows state** (service binaries + Trusted Storage + registry):
   ```bash
   bash $P/tools/apply_windows_state_wine.sh          # vmshare/tabharvest.zip -> prefix, wineserver-agnostic
   ```
   It places
   * `drive_c/Program Files/Common Files/Macrovision Shared/FLEXnet Publisher/{FNPLicensingService64.exe,fnp_registrations.xml}`
   * `drive_c/ProgramData/FLEXnet/` (Trusted Storage + event log)
   * imports `reg/HKLM_SOFTWARE_Tableau.reg` and
     `reg/HKLM_SYSTEM_CurrentControlSet_Services_FlexNet Licensing Service 64.reg`
     (UTF-16LE `reg export` files; Wine's `reg import` handles them).

2. **The service starts itself.** The imported key has `Start=2` (Automatic), so any `wine` invocation in the
   prefix boots `services.exe`, which auto-starts it. Verified:
   ```bash
   $WINE cmd /c rem                       # boots the prefix
   $WINE sc query "FlexNet Licensing Service 64"   # -> STATE: 4 RUNNING
   # process check: FNPLicensingService64.exe (plus one worker child) with WINEPREFIX=$P/prefix/tableau
   ```
   Explicit start is `$WINE sc start "FlexNet Licensing Service 64"`; if it is already up (normal case) Wine
   returns **1056 = ERROR_SERVICE_ALREADY_RUNNING** — that is not a failure.

3. **VC runtime caveat (this prefix only).** The bundle's VC2022 x64 redist (14.44.35211) installs with exit 0
   under Wine, but Wine's MSI file-version check *skips* three files, leaving Wine's builtins in `system32`:
   `msvcp140.dll`, `msvcp140_2.dll`, `vcruntime140_1.dll`. Because the recipe forces `=n` (native) for the
   VC runtime, those then resolve to "not found" and `tableau.exe` dies with
   `err:module:loader_init Importing dlls ... failed, status c0000135`. Fix (what was done here):
   ```bash
   PK="$PREFIX/drive_c/ProgramData/Package Cache"
   cabextract -q -d /tmp/vcmin "$PK/{43B0D101-A022-48F4-9D04-BA404CEB1D53}v14.44.35211/packages/vcRuntimeMinimum_amd64/cab1.cab"
   for f in msvcp140 msvcp140_2 vcruntime140_1; do
       cp -f "/tmp/vcmin/$f.dll_amd64" "$PREFIX/drive_c/windows/system32/$f.dll"
   done
   ```
   (Same source as Windows: the redist cab. If no installer has run in the prefix, the unsigned equivalent is
   the Burn payload `app/tableau_exe/a0` = `VC_Redist.x64.exe` 14.44.35211 — not exercised here.)

4. **Run the app** (console measure):
   ```bash
   WINEDLLOVERRIDES='msvcp140,msvcp140_1,msvcp140_2,vcruntime140,vcruntime140_1,mfc140u,mfc140=n' \
   WINEDEBUG=-all WINEPREFIX=$P/prefix/tableau DISPLAY=:11 \
   $P/wine-install/bin/wine 'C:\Program Files\Tableau\Tableau 2026.2\bin\tableau.com'
   ```
   GUI: `EXE='C:\Program Files\Tableau\Tableau 2026.2\bin\tableau.exe' tools/run_tableau.sh flexnet 100`
   (→ `logs/run-flexnet/`, 24 frames, app alive at the end).

## 2. Verbatim `tableau.com` output (`logs/flexnet/{before,after}.{out,err}`)

**BEFORE — service deleted** (`$WINE sc delete "FlexNet Licensing Service 64"`, then `wineserver -k`, then run):

```
stdout: The FlexNet Licensing Service is not installed on this machine.
stderr: libEGL warning: DRI3 error: Could not get DRI3 device
        libEGL warning: Ensure your X server supports DRI3 to get accelerated rendering
        FlexNet Library could not be initialized, error code 20. FLEXnet Licensing Service is not installed.
exit 1
```

For reference, on Windows *without* the service the messages are
`The licensing service is too old.` / `Tableau could not access Trusted Storage.` — same gate, different state
(registered-but-old vs. absent).

**AFTER — service present and RUNNING:**

```
stdout: (empty)
stderr: libEGL warning: DRI3 error: Could not get DRI3 device
        libEGL warning: Ensure your X server supports DRI3 to get accelerated rendering
        Unable to verify license. Please activate the product.
exit 1
```

`Unable to verify license. Please activate the product.` is the console form of the activation state; the GUI
run then shows the **Activate Tableau** window (frame paths above) and stays alive.

## 3. What the service binary is and does (measured)

* `FNPLicensingService64.exe` — PE32+ x86-64 **CUI**, FlexNet Publisher **11.19.4.1 build 291070**
  (`strings`/event log). Imports only stock DLLs: `KERNEL32, USER32, ADVAPI32, ole32, SHELL32, OLEAUT32, WS2_32`
  (`objdump -p`). No private imports, nothing app-local.
* Runtime under Wine (`WINEDEBUG=+loaddll,err+all`, `logs/flexnet/svc-loaddll.err`): loaded **native** as
  `C:\Program Files\Common Files\Macrovision Shared\FlexNet Publisher\FNPLicensingService64.exe`; every import
  resolves. The **only** `err:` line in the whole trace is
  `err:eventlog:ReportEventW L"StartServiceCtrlDispatcher() failed"` — and that appears only when the exe is
  started *from the console* instead of by the SCM (any Win32 service exe behaves that way; it is not a Wine
  bug). Started by `services.exe` it stays resident, spawns one worker child, and serves requests.
* Proof it is doing real work: it created
  `drive_c/ProgramData/FLEXnet/tableau_003e2900_tsf.data` (8457 B) and grew
  `tableau_003e2900_event.log` from 604 B (harvest) to ~175 KB, with live entries under `[P:32]`/`[P:36]`.
* **Named pipe (parent's question): confirmed, same name as Windows.** With `WINEDEBUG=+file` the client asks for
  exactly `\\.\pipe\FlexNet Licensing Service 64ABF27A87-DC96-4b05-A06B-83EB2749B800` and Wine returns a valid
  handle — `CreateFileW returning 00000000000004F4`, 822 opens in one run. So the service's `CNamedPipeServer`
  listener works under Wine; `get_nt_and_unix_names -> c00000cb` on the way is the normal pipe routing inside
  Wine, not an error. (`WINEDEBUG=+pipe` is useless: Wine 11.18 has no `pipe` debug channel.)
* Identity inputs (`WINEDEBUG=+loaddll,err+all`, PID 0058 = mountmgr/driver side, 0088/0094 = WMI):
  * `IOCTL_DISK_GET_DRIVE_GEOMETRY` / `_EX` **are implemented** — `wine-11.18/dlls/mountmgr.sys/device.c:1885`
    and `:1900`; the app's `\Device\Harddisk0\DR0` path works.
  * Unsupported ones the service probes (harmless here, it still got a hostid): Wine prints
    `fixme:mountmgr:disk_ioctl Unsupported ioctl 74080 (device=7 access=1 func=20 method=0)`,
    `... 4100c (device=4 access=0 func=403 method=0)`, `... 41018 (device=4 access=0 func=406 method=0)`,
    `... 2d0c10 (device=2d access=0 func=304 method=0)`,
    `fixme:mountmgr:query_property Faking StorageDeviceProperty data`,
    `fixme:mountmgr:query_property Unsupported property 0x31`.
  * WMI path: `fixme:wbemprox:client_security_SetBlanket/Release` and `fixme:ole:CoInitializeSecurity ... stub`
    (CLSID `{1B1CAD8C-2DAB-11D2-B604-00104B703EFD}` is resolved by Wine's wbemprox, no failure).
  * TPM: `fixme:tbs:Tbsi_GetDeviceInfo (16, ...) stub` — non-fatal.
* Trusted Storage location: `C:\ProgramData\FLEXnet` (Wine maps it to
  `drive_c/ProgramData/FLEXnet`); the storage file name embeds the Windows hostid `003e2900`, and Wine's
  service reused it rather than creating a new identity.

## 4. Was the harvest needed?

For **this** prefix, yes and it was **sufficient on its own**: the prefix has only a symlinked app tree (no MSI),
and `tools/apply_windows_state_wine.sh` alone brought the service up and produced the Activate window.
The parent's independent measurement shows the real Burn+MSI installer also creates and starts the same service
under Wine, so the harvest is not the only route — the two paths converge on the same state (service key with
`Start=2`, binaries in `Common Files\Macrovision Shared\FlexNet Publisher`, Trusted Storage in
`ProgramData\FLEXnet`). Only the harvest path was verified end-to-end here.

## 5. Files changed by this task

* `tools/apply_windows_state_wine.sh` (owned) — three fixes:
  1. **bug**: it called `wine reg import` without exporting `WINEPREFIX`, so the registry went to `~/.wine`.
     Now `export WINEPREFIX=$PREFIX` (and `WINEDEBUG=-all`).
  2. `unzip` exits 1 on the guest zip's backslash-separator warning and `set -e` killed the script before any
     work; now tolerated, with an explicit check that `flexnet/`, `FLEXnet-data/` and `reg/` extracted.
  3. a failed `reg import` was masked by `|| echo`; the script now prints the failure and exits nonzero
     (re-verified: `bash -n` clean, full run `rc=0`).
* `prefix/tableau` — applied the harvest; installed the 3 real MS VC runtime DLLs listed in §1.3.
* `recon/FLEXNET_WINE.md` (this file).

## 6. Wine error text still present at startup (all non-fatal)

```
err:winediag:getaddrinfo Failed to resolve your host name IP        (app, ~8x)
fixme:mountmgr:disk_ioctl Unsupported ioctl ... / query_property ... (see §3)
fixme:tbs:Tbsi_GetDeviceInfo (16, ...) stub
fixme:ole:CoInitializeSecurity ... stub ; fixme:wbemprox:client_security_* 
libEGL warning: DRI3 error: Could not get DRI3 device                (X/VNC, cosmetic)
```

Nothing blocks; the app reaches the Activate window with the service running.

## 7. Needed from the Windows guest

Nothing further for this task. Two optional items if the service is ever probed deeper:
* a full `C:\ProgramData\FLEXnet\tableau_003e2900_tsf.data` (the harvest contains only `_backup.001`; Wine's
  service recreated the main file itself, so this did not matter);
* the exact registry tail of the service key if a second publisher/product is ever registered.
