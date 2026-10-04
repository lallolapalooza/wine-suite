# Method: finding and fixing what Tableau needs from Wine

This is the loop this project runs, in the order that has been measured to work on this machine. Every
tool named here exists in `tools/`.

## 0. Acceptance target

Parity with the Windows guest up to the point Windows itself is blocked: if Windows reaches a
sign-in / licence screen and stops, Wine has to reach the **same screen**. Activation is not the goal.

## 1. Split the problem (do not debug both at once)

| phase | question | how |
|---|---|---|
| **A. runtime** | does `tableau.exe`+its DLLs run? | identical file tree on both platforms, no installer involved: guest `msiexec /a <msi> /qn TARGETDIR=C:\TableauRef`; Wine `tools/deploy_tree.sh` (symlinks `app/tableau_exe/msi_root/Tableau` into the prefix) |
| **B. installer** | does the WiX Burn bundle + MSI install? | `tools/install_tableau_wine.sh` (same command line as the verified Windows run: `/quiet /norestart /log C:\tableau_burn.log ACCEPTEULA=1`) |

Only when A is green is B's failure signal unambiguous.

## 2. Reference on Windows (what "like in Windows" means, measured)

* Silent install: `/quiet /norestart /log C:\tableau_burn.log ACCEPTEULA=1` — **`ACCEPTEULA=1` is
  mandatory**; without it the bootstrapper exits `0x80070057` before doing anything (measured).
* The Burn engine re-launches itself **elevated** → UAC consent on the secure desktop. On this guest the
  secure desktop is neither captured by `virsh screenshot` nor reachable by injected input (measured), so
  prefer the elevation-free `msiexec /a` route for the reference tree.
* Frames: `tools/win_frame_sampler.sh <tag> <secs> [iv]` (`virsh screenshot`; **one sampler at a time**).
* The app's own logs: `tools/collect_logs.sh <tag>` pulls `%LOCALAPPDATA%\Tableau` + `%APPDATA%\Tableau`
  from the guest through the `:8000` hub and the same paths out of the Wine prefix.
* Guest command channel: `tools/guest.sh '<powershell>' [secs]` (nonce-safe wrapper over
  `tools/vmcmd.sh`; the guest poller **ignores a repeat of the last command text**). Serialised by `flock`;
  keep commands light — a recursive scan of a 5400-file tree timed the channel out at 120 s.

## 3. Wine side: get the failure, then the call trace

```bash
tools/make_prefix.sh                                   # prefix + fonts + WinRT .winmd metadata
tools/deploy_tree.sh                                   # C:\Program Files\Tableau -> app/.../msi_root/Tableau
CHANNELS='err+all,fixme-all,seh' tools/wine_diag.sh t1 'C:\Program Files\Tableau\Tableau 2026.2\bin\tableau.exe'
tools/run_tableau.sh t1 120                            # frames + window tree on the VNC display :11
```

`logs/diag-<tag>/{stderr.log,errs.txt,backtrace.txt}` hold Wine's own messages; `errs.txt` is the
deduplicated `err:`/`warn:` histogram — read it first, it usually names the missing API outright.

`+relay` is the call tracer, but a Qt+Chromium app emits gigabytes in seconds. Narrow it in the registry
instead of grepping afterwards:

```bash
wine reg add 'HKCU\Software\Wine\Debug' /v RelayInclude /t REG_SZ /d 'ntdll,kernelbase,secur32' /f
```

## 4. Trace, don't decompile (open-source components)

Qt 6.5.11, Chromium 122 (via Qt WebEngine), Node.js 22.17.1 (`eps/eps.exe`), Envoy (`yaxcatd.exe`), ICU,
OpenSSL, ANGLE/SwiftShader are all open source: read their Windows back-ends for the APIs they call and
what they expect, instead of disassembling Tableau's own binaries. `recon/OPENSOURCE_TRACE.md` maps each
component to the API surface, Wine's implementation status (`file:line` in `wine-11.18/`) and a test per
suspect. Tableau's own binaries are read only as far as their import tables (`objdump -p`).

## 5. Prove an API difference with a differential probe

When an API is suspected, settle it with one PE run on both platforms and diffed:

```bash
x86_64-w64-mingw32-gcc -o probe.exe probe.c -lole32 ...   # tools/winapi/*.c are the prior examples
# run under Wine:  WINE=... wine probe.exe > wine.txt
# run on guest:    copy into vmshare/, guest pulls and runs it, PUTs its output back
diff <(normalise wine.txt) <(normalise guest.txt)
```

Theming the probe on the failure (the exact API the app called just before it died) is what makes the
patch obvious; the probes under `tools/winapi/` (`roprobe.c`, `kprobe.c`, `nameprobe.c`, `asimp.c`, …) are
the worked examples.

## 6. Patch, rebuild, re-verify

1. `tools/make_patch.sh` / hand-written diff → `patches/NNNN-subject.patch` (symptom → Windows behaviour →
   how verified, in the file).
2. `JOBS=6 tools/build_tableau.sh --inc` (incremental; `ccache` is on) with `tools/mem_guard.sh` running.
3. Re-run the same scenario (`tools/wine_diag.sh`, `tools/run_tableau.sh`) and compare against the Windows
   frames with `tools/cmp_frames.sh`.
4. App-specific changes go to `patches/app-exclusive/`; anything that is a genuine general Wine gap stays
   in the main series.

## 7. Resource discipline

* Memory: `make -j6` max (`mem_guard.sh` kills compilers at 85 % used); the Windows guest holds 8 GB.
* Disk: `/` is the only writable filesystem (~19 GB free at the time of writing); the Wine tree is built
  **in place** and the app tree is **symlinked** into the prefix instead of copied.
* Guest: one sampler, one command at a time; the poller holds a lock.
