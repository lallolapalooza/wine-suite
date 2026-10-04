# Tableau Burn bundle under Wine — where it actually gets (measured)

Slice owner: `BurnInstallerWine`. Prefix used: `$P/prefix/install-test` (created, used, **deleted**).
Wine: `$P/wine-install/bin/wine` = **wine-11.18** (project patch series applied). Display `:11` (Xvfb).
Logs kept: `$P/logs/install-wine-burntest/`.

## 0. Verdict (read this first)

**The installer does not fail under Wine.** The real WiX Burn bundle was run with the exact verified
Windows command line, and it completed the *whole* chain — VC2022Redist ExePackage → Tableau MSI →
`InstallFinalize` — in **63 s**, exit code **0x0**. The MSI **did reach its `InstallExecute` sequence and
finished it successfully**. The file tree is byte-identical to the MSI payload (5425/5425 files,
2 208 240 220 B = the MSI `InstallSize`), the 167 `HKLM\SOFTWARE\Tableau\*` values are written, and the
**FlexNet Licensing Service 64 is created and RUNNING**.

There is therefore **no "first hard failure" to report for any of the three routes** — all three succeed.
The task premise ("find out exactly where the bundle fails") is **falsified by measurement**. What follows
is the verbatim evidence, the verification, and the few *latent* Wine deviations that do not block install.

| route | command | result | verbatim outcome line |
|---|---|---|---|
| 1. bundle | `TableauDesktop-…exe /quiet /norestart /log C:\tableau_burn.log ACCEPTEULA=1` | **success**, 63 s | `i007: Exit code: 0x0, restarting: No` |
| 2. bundle after VC++ redist | same; the bundle ran `VC2022Redist` itself, inline | **success** (redist exit 0x0, chain continued) | `[0174:0178]…i500: Shutting down, exit code: 0x0` |
| 3. direct MSI | `wine msiexec /i Z:\tmp\a1.msi /qn ACCEPTEULA=1 /l*v C:\direct_msi.log` | **success**, 40 s | `Action ended 11:44:34: INSTALL. Return value 1.` |

## 1. Environment and exact commands

```bash
cd /home/asdf/projects/tableau-wine
df -h /            # 8.3 G free before (>=6 G gate); free -g -> 18 G available
tools/make_prefix.sh /home/asdf/projects/tableau-wine/prefix/install-test   # fresh win64 prefix + fonts + winmd

export WINEPREFIX=/home/asdf/projects/tableau-wine/prefix/install-test
export DISPLAY=:11
export WINE=/home/asdf/projects/tableau-wine/wine-install/bin/wine
export WINEDEBUG=err+all,fixme-all      # diagnostic channels, NOT -all, so Wine's own errors land in the log
```

### Route 0 — the only thing that failed, and it was *our* script, not Wine

`tools/install_tableau_wine.sh` builds the installer path as `"$ROOT/../Downloads/…"`, which resolves to
`/home/asdf/projects/Downloads/…`; the installer really lives at `/home/asdf/Downloads/…`
(`tools/install_tableau_wine.sh:25`). Running the project script verbatim therefore produced, in
`logs/install-wine-burntest/stderr.log`, Wine's *load* failure (exit 53):

```
wine: failed to open "/home/asdf/projects/tableau-wine/../Downloads/TableauDesktop-64bit-2026-2-3.exe"
```

**Fix for the parent (not applied — script is the parent's):** `$ROOT/../Downloads/` → `$ROOT/../../Downloads/`
or an absolute path. The runs below used the absolute `/home/asdf/Downloads/TableauDesktop-64bit-2026-2-3.exe`
and are otherwise identical to what the script does.

### Route 1+2 — the Burn bundle

```bash
export WINEPREFIX=/home/asdf/projects/tableau-wine/prefix/install-test DISPLAY=:11
export WINEDEBUG=err+all,fixme-all
"$WINE" /home/asdf/Downloads/TableauDesktop-64bit-2026-2-3.exe \
        /quiet /norestart /log 'C:\tableau_burn.log' ACCEPTEULA=1
# host clock 23:37:55 -> 23:38:58 ; wine_exit=0
```

The bundle unpacked itself and ran the two chained packages **in order**, exactly as on Windows:

* `VC2022Redist` (`a0`, `vcredist2022_x64.exe /install /quiet /norestart`) — evaluated, ran, and its own
  nested Burn bundle finished cleanly:
  `[0174:0178][2026-10-03T23:38:07]i500: Shutting down, exit code: 0x0`
  (its log: `…/Temp/dd_vcredist_amd64_20261003233805.log`, kept as `logs/install-wine-burntest/vcredist.log`).
* `Tableau` MSI — started immediately after; see Route 3 for the sequence.

Outer log tail (`C:\tableau_burn.log` = `prefix/install-test/drive_c/tableau_burn.log`, verbatim):

```
[0128:012C][2026-10-03T23:38:58]i410: Variable: WixBundleElevated = 1
[0128:012C][2026-10-03T23:38:58]i410: Variable: WixBundleVersion = 26.2.1954.0
[0128:012C][2026-10-03T23:38:58]i410: Variable: WixBundleLog_Tableau = C:\tableau_burn_001_Tableau.log
[0128:012C][2026-10-03T23:38:58]i410: Variable: WixBundleOriginalSource = Z:\home\asdf\Downloads\TableauDesktop-64bit-2026-2-3.exe
[0128:012C][2026-10-03T23:38:58]i007: Exit code: 0x0, restarting: No
```

Note the bundle header line: `Burn v3.14.1.8722, Windows v10.0 (Build 19045: Service Pack 0)` — Wine reports
build 19045, so the bundle's own `VersionNT >= v6.2` gate passes, and `WixBundleElevated = 1` is set without
any UAC prompt (see §5).

**Route 2 (bundle after installing the redist first) is moot**: the bundle *itself* installs `VC2022Redist`
first, and that step succeeded inline (exit 0x0) in this very prefix, so there was nothing to pre-install.
Wine's builtin `msvcp140`/`vcruntime140` were also enough for the MSI custom actions (Route 3 proves the
MSI installs in a prefix with no vcredist at all — see §5).

### Route 3 — direct `msiexec`

The MSI `a1` (`app/tableau_exe/a1`, 725 159 936 B) had been deleted by the parent; rather than re-carve
709 MB from the original exe, the **bundle's own cached copy** was reused — the bundle stores it at
`C:\ProgramData\Package Cache\{D5C4243D-E35D-4F26-A837-EDB5C3AA3739}v26.2.1954\tableau-setup-std-262-tableau-2026-2.26.0912.1023-x64.msi`.
That file was renamed (same filesystem, no extra disk) to `/tmp/a1.msi` before the prefix was deleted, then
afterward restored to the documented location **`app/tableau_exe/a1`** (725 159 936 B, same SHA/size as the
payload) so the parent has it again.

```bash
# fresh prefix (no vcredist, no bundle) then the MSI alone:
tools/make_prefix.sh /home/asdf/projects/tableau-wine/prefix/install-test
export WINEPREFIX=/home/asdf/projects/tableau-wine/prefix/install-test DISPLAY=:11
export WINEDEBUG=err+all,fixme-all
"$WINE" msiexec /i 'Z:\tmp\a1.msi' /qn ACCEPTEULA=1 '/l*v' 'C:\direct_msi.log'
# host clock 23:43:54 -> 23:44:34 ; msiexec_exit=0 ; stderr had only 2 libEGL/DRI3 lines
```

Verbatim from `C:\direct_msi.log` (`logs/install-wine-burntest/direct_msi.log`):

```
Action 11:44:01: InstallInitialize.
Action ended 11:44:01: InstallInitialize. Return value 1.
Action start 11:44:01: InstallFiles.          # … Copying new files
Action ended 11:44:32: InstallFiles. Return value 1.
Action start 11:44:33: InstallFlexNetService.CE9CB17D_70D7_465A_BADD_BC254420D929.
CAQuietExec64:  Successfully installed anchor service for publisher Tableau Software, LLC, product Tableau 2026.2
CAQuietExec64:  Success code 2003: There was no service on the system so the new one was installed.
Action ended 11:44:34: InstallFinalize. Return value 1.
Action ended 11:44:34: INSTALL. Return value 1.
```

Route 3 also passes the MSI's own `LaunchCondition` rows (`Privileged`, `WindowsBuild >= 9200`,
`D2D1_FOUND OR WindowsBuild > 6002`, `ACCEPTEULA = "1"`) — Wine satisfies all of them (§5).
`SOURCEDIR = Z:\tmp\`, `OriginalDatabase = Z:\tmp\a1.msi`.

## 2. Did the MSI reach its InstallExecute sequence?

**Yes — twice (once per route), and it completed.**

Route 1 (bundle) — `C:\tableau_burn_001_Tableau.log`:
```
Action start 11:38:16: InstallFiles.
Action ended 11:38:55: InstallFiles. Return value 1.
Action start 11:38:56: InstallFlexNetService.CE9CB17D_70D7_465A_BADD_BC254420D929.
CAQuietExec64:  Successfully installed anchor service for publisher Tableau Software, LLC, product Tableau 2026.2
CAQuietExec64:  Success code 2003: There was no service on the system so the new one was installed.
Action ended 11:38:58: InstallFinalize. Return value 1.
Action ended 11:38:58: INSTALL. Return value 1.
```
Route 3 — the `InstallFinalize … Return value 1` / `INSTALL. Return value 1` pair quoted in §1.

`grep -c "Return value 3"` = **0** in both MSI logs. There is no `Return value 3`, no `Error 17xx`, no
`Product: … -- Installation failed` anywhere. Neither run produced a Wine `err:` line at all
(`wine stderr` for the bundle = 2 `libEGL … DRI3` warnings from the host's GL stack; for the direct MSI = the
same 2 lines).

## 3. Post-install verification (route 1 and route 3 gave identical results)

| check | expected | measured |
|---|---|---|
| files under `C:\Program Files\Tableau` | 5425 (MSI `File` table) | **5425** |
| bytes (`du -sb`) | 2 208 240 220 (MSI `InstallSize`) | **2 208 240 220** |
| file set vs `msiextract` reference | identical | **identical** (0 differences after lower-casing paths; the only diffs are MSI-preserved case, `local` vs `Local`) |
| md5 of `bin/tableau.exe`, `bin/tabfnp.dll`, `bin/Qt6WebEngineCore.dll`, `bin/hyper/hyperd.exe`, `bin/FNP_Act_Installer.dll`, `Local/data/GeocodingData.hyper` | equal to reference | **all equal** |
| `HKLM\SOFTWARE\Tableau\*` | written | **written** (`Directories`, `FlexNetUsers\std`, `Tableau 2026.2\{Autosave,AutoUpdate,Crashdump,Directories,Settings}` …) |
| Start-Menu shortcut | created | `…/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Tableau 2026.2.lnk` |
| FlexNet service | created + started | `HKLM\System\CurrentControlSet\Services\FlexNet Licensing Service 64` (`Start=2`, `Type=0x10`, `ObjectName=LocalSystem`, `ImagePath="C:\Program Files\Common Files\Macrovision Shared\FlexNet Publisher\FNPLicensingService64.exe"`); `wine sc query` → **STATE : 4 RUNNING** |
| anchor registration | written | `…/Macrovision Shared/FlexNet Publisher/fnp_registrations.xml` (publisher `Tableau Software, LLC`, product `Tableau 2026.2`) |
| bundle package cache | populated | `ProgramData/Package Cache/{D5C4243D…}v26.2.1954/` (725 MB MSI) + `{d8bbe9f9…}` / vcredist caches |

`RunTableau` (CA type 210, seq 6601) is conditioned `LAUNCHSILENT = 1 Or UILevel = 5`; the silent bundle
passes `LAUNCHSILENT=0` and `UILevel=2`, so it is **not** scheduled — same as on Windows. `tableau.exe` is
therefore not launched by the installer, and any failure after this point belongs to the app/runtime slice,
not the installer.

## 4. Wine code implicated

No Wine code path *failed*. Three Wine behaviours are nevertheless visible and worth recording:

| observation | Wine source | meaning |
|---|---|---|
| `UpdateFlexNetServicePermissions` CA (a `sc.exe sdset "flexnet licensing service 64" D:(…)` deferred CA) reports `Return value 1` but changes nothing | `wine-11.18/programs/sc/sc.c:430-433` — `else if (!wcsicmp( argv[1], L"sdset" )) { WINE_FIXME("SdSet command not supported, faking success\n"); }` | Wine's `sc` **fakes success** for `sdset`; the service DACL is never applied. Cosmetic — the service still starts (Wine has no real ACL enforcement). This is the only installer step whose success is synthetic. |
| MSI `LaunchCondition` `Privileged` passes, `WixBundleElevated = 1`, `MsiRunningElevated = 1`, and the MSI's deferred SYSTEM CAs (`installanchorservice.exe`) run — with no UAC | `wine-11.18/dlls/msi/package.c:737-741` — `/* in a wine environment the user is always admin and privileged */ … msi_set_property(…, L"Privileged", L"1", -1); msi_set_property(…, L"MsiRunningElevated", L"1", -1);` (duplicated at `:969-972`) | Wine hard-codes the elevation properties. This is *why* the bundle needs no consent prompt (unlike the Windows guest, where UAC had to be pre-approved). |
| `internal_ui_handler` FIXME for unimplemented install messages | `wine-11.18/dlls/msi/package.c:1651-1739`, `:1737` `FIXME("internal UI not implemented for message 0x%08x (UI level = %x)\n", …)` | Not hit in `/quiet` (`UILevel = 2`); only affects interactive UI messages. |

The 64-bit MSI custom-action machinery used by this package (`CAQuietExec64` from the MSI `Binary` table,
WixCA.dll) worked, as did `advapi32` service creation (`CreateService`/`StartService`), `WriteRegistryValues`,
shortcuts, and the LZX `cab1.cab` decompression of 2.1 GB.

## 5. Differences vs the Windows reference (none block installation)

1. **No elevation prompt / no separate elevated engine process.** On Windows the Burn engine re-launches
   itself elevated and raises UAC; under Wine the same process id `[0128:012C]` performs the whole install and
   `WixBundleElevated = 1` is simply true. (Windows also needed `ConsentPromptBehaviorAdmin=0` to avoid the
   prompt; Wine needs nothing.)
2. **`sc sdset` is a fake success** (see §4) — harmless under Wine.
3. **Direct `msiexec /i` succeeds in a prefix with no VC++ redist at all**, so the `WixCA` custom actions load
   against Wine's builtin `msvcp140`/`vcruntime140`. On Windows the redist (installed first by the bundle) is
   what makes the CAs work.
4. Everything else (file set, byte sizes, registry, service, package cache, shortcut) matches the Windows
   outcome.

## 6. What the next fix would be

* **Installer: nothing is required** for the silent bundle or the direct-MSI path — both are green. The only
  installer-side Wine gap seen is `sc.exe sdset` (`programs/sc/sc.c:430`); implement it only if the FlexNet
  service DACL ever needs to be real. `Privileged`-always-1 (`dlls/msi/package.c:737`) is a deliberate Wine
  simplification, not a bug.
* **Fix the harness bug**, because it makes the *documented* reproduction command fail: `$ROOT/../Downloads/`
  in `tools/install_tableau_wine.sh:25` → absolute `/home/asdf/Downloads/…`.
* **The real remaining blocker is after the installer**, in the app runtime: on Windows the installed app
  stops at the FlexNet Trusted-Storage gate (`The licensing service is too old.` / `Tableau could not access
  Trusted Storage.`). Now that the MSI *does* create and start `FNPLicensingService64` under Wine, the
  question for the licensing slice is whether that Wine-hosted service can serve Trusted Storage — that is
  the boundary of this slice, not an installer defect.

## 7. Artifacts

* `logs/install-wine-burntest/burn.log` — outer Burn log (28 214 B), verbatim source of the quotes above.
* `logs/install-wine-burntest/burn_001_Tableau.log` — MSI execution log from the bundle (1 207 678 B).
* `logs/install-wine-burntest/direct_msi.log` — MSI log from the direct `msiexec` route (1 207 156 B).
* `logs/install-wine-burntest/vcredist.log` — VC2022Redist nested-bundle log (17 451 B).
* `logs/install-wine-burntest/stderr.log`, `direct_msi_stderr.log` — Wine stderr for both routes.
* `app/tableau_exe/a1` — restored MSI payload (725 159 936 B), recovered from the bundle's package cache.
* `prefix/install-test` — **deleted**; `wineserver -k` scoped to it first. No Wine process from that prefix
  remains (the surviving `FNPLicensingService64.exe` is the parent's `prefix/tableau`).
* Disk: 8.3 GB free before → **41 GB free** after (more was freed elsewhere during the run); prefix torn down.
