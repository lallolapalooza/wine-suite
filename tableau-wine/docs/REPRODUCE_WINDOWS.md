# Reproducing the Windows reference environment (verified steps)

Everything here was run on this machine; each step names what proved it. Host = Ubuntu, guest = libvirt domain
`win11` (Windows 11 Pro 26200, 1280x800, user `adsf`). Commands are project tools unless marked otherwise.

## 0. Guest channel (host → guest)

```bash
tools/vmserv.py 8000 vmshare         # host hub; must be the only listener on 8000
tools/guest.sh '<powershell>' [secs] # nonce-safe wrapper over tools/vmcmd.sh
```
* The guest polls `http://192.168.122.1:8000/cmd.txt` every 3 s and PUTs `guest_cmd_out.txt` back
  (2.4 s round-trip measured). It **ignores a repeat of the last command text** — hence the nonce.
* Host → guest TCP is firewalled; only the guest-initiated direction works.
* Keep each guest command light: a recursive scan over a 5400-file tree timed the channel out at 120 s.
* Screens: `tools/win_frame_sampler.sh <tag> <secs>` (one sampler at a time; three concurrent samplers hang
  `virsh screenshot`).
* Input: `tools/vm/vmclick.py X Y --screen 1280x800`, `tools/vm/vmkeys.py 'text' --enter`,
  `tools/vm/vmhotkey.py ctrl+alt+delete` (chords with held modifiers).

## 1. Elevation without prompts (the blocker, solved)

libvirt/this VM grants no silent elevation. The UAC consent UI is normally *not* visible while a shell overlay
(Start/Search) is open — closing overlays with `tools/vm/vmhotkey.py esc` restores it, and it can then be
clicked (panel x 412-867 y 212-588; **Yes (541,548)**, No (745,548)).

Once one elevation is approved, an **Administrator console** exists; drive it and remove the problem for good:

```
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v ConsentPromptBehaviorAdmin /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v PromptOnSecureDesktop /t REG_DWORD /d 0 /f
```

After that, an administrator elevates without any prompt: installer runs need no interaction.
**Restore** the machine's defaults afterwards with `ConsentPromptBehaviorAdmin=5`, `PromptOnSecureDesktop=1`.

`tools/win_uac_click.sh` (mean-luminance < 0.40 ⇒ click Yes) remains as a fallback, but it is fooled by any large
dark window (a maximised console reads ~0.30), so prefer the policy route.

## 2. Install Tableau on Windows (reference)

```powershell
Remove-Item C:\Users\adsf\tableau_burn.log -ErrorAction SilentlyContinue
Start-Process -FilePath C:\Users\adsf\TableauDesktop.exe `
  -ArgumentList "/quiet","/norestart","/log","C:\Users\adsf\tableau_burn.log","ACCEPTEULA=1" -PassThru
```
* `ACCEPTEULA=1` is **mandatory**; without it the bootstrapper exits `0x80070057` before doing anything.
* Start it with `Start-Process -PassThru` (detached). `Start-Job { Start-Process … }` did **not** survive here —
  the install never started and no log appeared.
* Give it ~10-20 minutes (5425 files, 2.1 GiB). Progress lives in `C:\Users\adsf\tableau_burn_000_Tableau.log`,
  the bundle log in `tableau_burn.log` stops after "Launching elevated engine process.".
* The Burn bundle first evaluates `VC2022Redist` (skipped when VC++ 14.44+ is present) then the single MSI
  `Tableau` (ProductCode `{D5C4243D-E35D-4F26-A837-EDB5C3AA3739}`).
* Verify **by product presence**, never by exit code (a Burn bundle exits 0 even when its payload failed).

## 3. What the app needs before it will open (measured)

Running the *admin-extracted* tree (`msiexec /a <msi> /qn TARGETDIR=C:\TableauRef`) is not enough:
`bin\tableau.exe` dies in 6.2 s with `0xE06D7363`, and `bin\tableau.com` prints

```
The licensing service is too old.
Tableau could not access Trusted Storage. Verify that the latest version of the FlexNet
Licensing Service is running as a network service.
```

So a working reference needs: the file tree, the 167 `HKLM\SOFTWARE\Tableau\*` registry rows, and the
**FlexNet Licensing Service 64** (`FNPLicensingService64`) with its Trusted Storage. All three come from the MSI
install; `tools/vm/harvest.ps1` captures them (binaries, `C:\ProgramData\FLEXnet`, `reg export`s, file lists,
service state) into `vmshare/tabharvest.zip`.

## 4. Non-elevated alternatives (for parts that allow it)

* `msiexec /a <msi> /qn TARGETDIR=<dir>` — administrative install: unpacks the complete tree with **no**
  elevation (used for the first reference attempt and for the Wine-side tree).
* Transfer: symlink the file into `vmshare/` and let the guest `curl.exe -O http://192.168.122.1:8000/<name>`
  (measured ~48 MB/s for the 725 MB MSI).
