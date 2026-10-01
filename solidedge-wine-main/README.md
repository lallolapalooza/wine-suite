# Solid Edge 2026 on Wine

Wine 11.18 with the patches that let Siemens **Solid Edge 2026** install and run on Linux, and
the fixes for the three defects it showed once it did:

1. the 3D viewport flickers black continuously in sketch mode,
2. the sketch cannot be closed — clicking Close Sketch logs
   `fixme:dwmapi:DwmGetWindowAttribute attribute 14 not implemented`,
3. Solid Edge cannot be exited — the title bar's X is greyed out.

Siemens software is not redistributed here. The media comes from the user's own download of
`Solid_Edge_X_Web_Installer_2026.exe`; `tools/dl_media.sh` and `FINDINGS.md` M1 record how its
payload is obtained, because the web installer's own download host no longer resolves.

This is not upstream-ready: no upstream MR was opened and the work is AI-assisted.

## Layout

| path | what it is |
|---|---|
| `wine-11.18/` | pristine Wine 11.18 source + the patch series (what gets built) |
| `wine/wine-11.18/` | the build tree (copy of the above; configure/make output) |
| `wine-install/` | `make install` output; `wine-install/bin/wine` |
| `patches/series/` | the consolidated series, `0001`..`0022`, applied to pristine Wine |
| `patches/local/` | this project's own patches, numbered from `0023` |
| `patches/sources/` | the untouched patch directories of the four sibling projects |
| `patches/README.md` | what each series patch is, where it came from, how the series was verified |
| `installer/media/` | the downloaded payload chunks (`Solid_Edge_Web_Package_2026.7z.001..027`) |
| `installer/media_x/` | the extracted InstallShield media (`Solid Edge/`) |
| `installer/cabs_x/` | the cabs unpacked, named by their MSI `File` key (`tools/cabx.py` resolves names) |
| `state/` | `vm/` guest captures, `iso/`, `work/` (the Wine prefix), `msi_File.tsv` |
| `tools/` | build / install / run / test / guest / host tooling |
| `vmshare/` | the host↔Windows-guest file channel |
| `logs/` | every log, including `logs/runs/<tag>/` per application run |
| `FINDINGS.md` | the evidence: one milestone per measured result |
| `STATE.md` | the current position; read this first when resuming |

## Requirements

* Wine 11.18 source and the toolchain from the Wine wiki's build dependencies. The build is the
  wiki's "new WoW64" recipe — `./configure --enable-archs=i386,x86_64 && make -j` — so no 32-bit
  Linux libraries are needed. `clang`/`lld` provide the PE toolchain (`i686-w64-mingw32-gcc` is
  accepted as the i386 PE compiler when clang's `-target i686-windows` probe fails, as here).
* An X display for the UI runs — the project uses a **TigerVNC** display `:2` (`Xtigervnc :2
  -geometry 1600x1000 -depth 24 -rfbport 5902 -SecurityTypes None -AlwaysLocalhost`) so a human
  can watch, and so `import -window root` works (it does not on the GNOME Xwayland `:0`).
* `openbox` for an EWMH window manager on `:2` (`wmctrl` needs one).
* `xorriso` and `virsh` only for the Windows-guest reference work.

## Build

```sh
tools/build_wine.sh              # configure + make + make install, with a memory guard
tools/build_wine.sh --jobs 8
tools/build_wine.sh --inc        # incremental, after editing dlls/foo
```

The script prints the free memory and caps `-j` from it before it starts, because this host also
runs an 8 GiB Windows guest.

## Install Solid Edge

```sh
tools/install_se_prefix.sh state/work/prefix        # empty prefix -> installed Solid Edge
```

It creates a win64 prefix set to Windows 10, installs .NET Framework 4.8 with winetricks (its
`dotnet48` cache is reused, ~30-90 min), then runs the vendor's own command line (FINDINGS M6):

```
setup.exe /s /clone_wait /v"/qn" /v"INSTALLDIR=..." /v"USERFILESPEC=...\Preferences\SELicense.lic"
```

## Run and observe

```sh
tools/run_se.sh <tag> --secs 240 --iv 10            # on DISP=:2, sampling windows + screenshots
tools/run_se.sh <tag> --debug +dwmapi,+relay        # targeted WINEDEBUG
```

`logs/runs/<tag>/` gets `out.txt`, `win_<t>s.png` (the app's own window), `screen_<t>s.png` (the
whole display), `windows_<t>.txt` (the X window tree) and `<tag>.stderr`.

## Verify

```sh
tools/run_wine_tests.sh --list                # which patch carries a test
tools/run_wine_tests.sh dwmapi dwmapi         # run dlls/dwmapi's suite under this fork
```

Differential probes (one PE, run on the Windows guest **and** under Wine, then diffed):
`tools/winapi/dwmprobe.c` (this is where the `DwmGetWindowAttribute` contract in the patches comes
from). Compile with `x86_64-w64-mingw32-gcc`; push to the guest with `tools/vm/vmcmd.sh`.

## The Windows guest

`virsh start win11`, log in as `adsf`/`asdf`, then bootstrap the command channel:
build an ISO with the launcher (`xorriso -as mkisofs -V GSHARE -o state/gshare.iso state/iso`),
`virsh attach-disk win11 state/gshare.iso sdc --type cdrom --mode readonly --targetbus usb --live`
(it mounts at `D:\`), and in the guest `Win+R` -> `d:\g.bat`.  After that
`tools/vm/vmcmd.sh '<powershell>'` runs commands and returns their output.

Key injection: `tools/vm/vmkey.py 'ctrl+a'` — **QEMU's left modifiers are `ctrl`/`alt`/`shift`,
not `ctrl_l`/`alt_l`**; with the wrong name QMP rejects the event and the modifier is silently
dropped.
