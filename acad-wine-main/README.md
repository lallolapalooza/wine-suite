# autocad software on wine

AutoCAD is a registered trademark of Autodesk, Inc. This repository is not associated with, affiliated with, supported nor endorsed by Autodesk, Inc. No guarantees are made, as for the suitability of the content of this repository for any particular purpose.

Wine 11.18 with the 14 patches that let AutoCAD software install and run on Linux.

`wine-11.18/` is a pristine `wine-11.18.tar.xz` (dl.winehq.org) with `patches/0001`..`patches/0016`
applied — nothing else. Every patch is against unmodified upstream source and the series applies
cleanly in order (14 patches; `0005`, `0011` and the debug hooks they carried are not part of
this repository):

```
tar -xf wine-11.18.tar.xz && cd wine-11.18
for p in ../patches/*.patch; do patch -p1 -i "$p"; done      # 14/14 OK
```

`wine-11.18/` here is already patched, so you only need that loop if you start from a fresh
tarball. The tree is never built in place — `tools/build_wine.sh` copies it to `wine/wine-11.18/`
and builds there.

No Autodesk software is redistributed here. The install media must come from your own Autodesk
account; the scripts take it from `installer/` or from `ACAD_MEDIA` (see `SETUP.md`).

It could probably work with Revit as well and other professional autodesk software such as inventor, but this is not tested. This has not been tested with GPU 3D accelerated applications such as Maya, 3ds max, inventor, etc.

This was only tested up to the licensing screen. Formerly, this app would fail to install.

This is not wine upstream ready: tests were not created and this repo is ai-assisted. This took 3 days to finish with deepseek v4.1 and oh my pi on ubuntu 26.04

## Start here

```
tools/check_prereqs.sh        # what this machine still needs, with the fix for each gap
```

`SETUP.md` is the full walkthrough: packages, the media layout, the build, the display, the
prefix, verify, known limits and troubleshooting. `check_prereqs.sh` performs the same checks
on your machine and prints the ordered next steps.

### Short version

```
tools/check_prereqs.sh                                   # fix every [MISSING] line it prints
python3 -m venv tools/venv && tools/venv/bin/pip install fonttools
Xvfb :2 -screen 0 1920x1080x24 &                          # ui_plug.sh/verify default to :2 (DISP overrides)
# put your Autodesk media in installer/ (Setup.exe + ODIS/), or set ACAD_MEDIA
tools/build_wine.sh                                       # ~30-60 min: copy, configure, make, make install
tools/install_fresh_prefix.sh ~/acad-prefix               # empty prefix -> installed AutoCAD
tools/verify_fresh_prefix.sh ~/acad-prefix 240            # launches acad, PASS/FAIL per check
```

## Layout

| path | what it is |
|---|---|
| `wine-11.18/` | the fork: Wine 11.18 source with the 14 patches applied (no build output) |
| `patches/` | the same 14 changes as individual patches, each with its reasoning and evidence |
| `env.sh` | build/test environment; all paths follow the checkout (rootfs-aware, no edits needed) |
| `tools/check_prereqs.sh` | checks a machine can build/install, and prints the remediation per gap |
| `tools/build_wine.sh` | copy → configure → make → `make install` into `wine-install/` |
| `run_build.sh` | incremental `make` in the existing build tree |
| `ui_plug.sh` | launches `acad.exe` on the X display and samples its windows/screenshots |
| `tools/install_fresh_prefix.sh` | empty prefix → installed, registered, rendering AutoCAD |
| `tools/verify_fresh_prefix.sh` | re-reads the evidence and prints PASS/FAIL per acceptance check |
| `tools/fix_licensing_registration.sh` | fallback for the acadprivate MSI's licensing custom action |
| `tools/make_wine_fonts.py` | builds the Arial / Microsoft Sans Serif substitutes the WPF UI asks for |

Generated and gitignored (re-creatable): `wine/` (build tree), `wine-install/` (the build),
`prefix*/` (installed products), `installer/`, `pkgs/`, `logs/`, `tools/venv/`.

## Requirements

`tools/check_prereqs.sh` reports all of this per machine; the table below is what it looks for.

* **Build toolchain** — `make`, `m4`, `patch`, `pkg-config`, `flex` >= 2.5.33, `bison` >= 3.0,
  a C compiler and a PE cross compiler (`clang`+`lld`+`llvm-dlltool`, or `mingw-w64`),
  `libfreetype-dev`, `python3`(+`python3-venv`). `env.sh` uses a private rootfs at `root/` when
  one exists (the project it came from built rootless with `apt-get download` + `dpkg-deb -x`);
  otherwise the system toolchain is used as-is.
* **Libraries** — X11 + X extensions (`libx11-dev libxext-dev libxrender-dev libxrandr-dev
  libxi-dev libxcursor-dev libxinerama-dev libxfixes-dev libxcomposite-dev libxkbcommon-dev`),
  `libgnutls28-dev` (TLS), `fonts-liberation` (the Arial substitutes are built from Liberation
  Sans). Xrender/Xcursor/Xi/Shm/Vulkan/SDL2/pulse/alsa/dbus/udev/fontconfig were absent from the
  reference build and AutoCAD still ran, so most other `-dev` packages are optional.
* **X display + tools** — `ui_plug.sh` and `verify_fresh_prefix.sh` default to display `:2`
  (`DISP` overrides) and need `xwininfo`, `xdotool`, `import` (imagemagick) and `pgrep`.
  `Xvfb :2 -screen 0 1920x1080x24 &` is enough; `Xtigervnc :2 ...` if you want to watch it.
* **Python venv** — `python3 -m venv tools/venv`; `tools/make_wine_fonts.py` additionally needs
  `fonttools` in it. The install/verify scripts stop without it.
* **A licensed AutoCAD 2027 install** — two shapes are used, both from your own Autodesk account:
  * the ODIS web-installer media (`Setup.exe` + `ODIS/`) — expected at `installer/`, or point
    `ACAD_MEDIA` at it (your `..._setup_webinstall.exe` download is the bootstrapper: run it
    once and it unpacks exactly this pair). The install downloads its packages, so stay online;
  * the extracted package payloads — expected at `pkgs/` (see `ACADPS_PAYLOAD` /
    `ACADPS_CUIX_DIR`). Only the `--repair` path uses these.
* **Resources** — roughly 40 GB free (build tree + `wine-install` + media + an installed
  prefix), and a few GB of RAM. `Xvfb`/Wine need no GPU.

## Build

Build out of the tracked tree, so the vendored source stays clean — `tools/build_wine.sh` does
all of it (copy, configure, make, install):

```
tools/build_wine.sh                 # JOBS=8 tools/build_wine.sh caps parallelism
tools/build_wine.sh --dry-run       # print the commands, change nothing
```

The reference configuration, for reference:

```
mkdir -p wine && cp -a wine-11.18 wine/wine-11.18 && cd wine/wine-11.18
./configure --prefix="$ACAD/wine-install" --enable-archs=i386,x86_64
make -j"$(nproc)" && make install                 # installs into wine-install/
```

This produces `wine-install/bin/wine` (and `wine-install/share/wine/fonts/tahoma.ttf`, which the
font fixup needs). Later rebuilds: `run_build.sh`.

## Install into an empty prefix

```
tools/install_fresh_prefix.sh /path/to/prefix
```

Runs `Setup.exe -q` from `installer/` (or `$ACAD_MEDIA`) against a fresh win64 prefix, applies
the documented workarounds for ODIS dropping the `acadprivate`/`acadps` packages, registers the
licensing feature, installs the font substitutes and the .NET Desktop Runtime, and reports a
`present`/`fixup`/`MISSING` line per end-state component. Logs: `logs/freshinstall/<name>/`.

Options: `--install-only` (acceptance path: leave exactly what the installer produced),
`--repair` (apply the installer-defect workarounds), `--force-install`.

Useful overrides: `ACAD_MEDIA` (media directory), `ACAD_WINE` (a different patched wine),
`ACADPS_PAYLOAD` (the acadps payload archive, default `pkgs/pkg.acadps1.tar.xz`) and
`ACADPS_CUIX_DIR` (a harvested CUIX directory). The CUIX gap fill reads the archive's own
`UserDataCache` tree; the archive ships 6 of the 9 files, the other three come from acad and the
ApplicationPlugins bundles.

## Verify

```
tools/verify_fresh_prefix.sh /path/to/prefix [seconds] [--apphome]
```

Launches acad from that prefix and checks the end state: acad's window is titled and sampled,
the surface is painted (non-blank frame), zero `.NET Assertion Failed` dialogs, no licence-error
dialog, and the licensing agent's WebView2 reached `/ui/v2/lgs`. `--apphome` starts acad without a
drawing, which is the only way it creates the AppHome webview.

The drawing it opens is a fixture that is not in the tree; set `VERIFY_DWG` to one, or the run
proceeds without a drawing and says so. Evidence lands in `logs/ui/<tag>/` and `log_<tag>.txt`.

## The patches

| # | subject |
|---|---|
| 0001 | wintrust: accept `WTD_CHOICE_BLOB` and RFC3161 timestamp signatures |
| 0002 | kernelbase: `RegLoadAppKey` over a regf hive file |
| 0003 | urlmon: keep the `res` scheme out of the empty-host `URLZONE_INVALID` rule |
| 0004 | wineserver: run the service manager and the services it starts in session 0 |
| 0006 | ws2_32: resolve names through the Windows hosts file |
| 0007 | crypt32: provide the group-policy and enterprise system certificate stores |
| 0008 | server: allow associating non-overlapped handles with a completion port |
| 0009 | ntdll: make handles on fd-backed Unix pipes behave like Windows pipes |
| 0010 | kernel32/kernelbase/ntdll/dnsapi: export the APIs the licensing and browser stacks probe for |
| 0012 | ws2_32: answer Network Location Awareness (NS_LNA) lookups |
| 0013 | winex11: ignore `BadWindow`/`BadDrawable` X errors on every display connection |
| 0014 | secur32: answer `GetUserNameExW`'s `NameUserPrincipal` and `NameDnsDomain` from the domain |
| 0015 | msiexec: parse the command line with the Windows rules, so a property value ending in a backslash survives |

Each patch file carries the symptom, the Windows behaviour it restores and how it was verified.

Patches 0005 (`bcrypt: dump symmetric keys and plaintext`) and 0011 (`user32: dump the
licence-error caller`) existed only to diagnose the licensing failure; they dump secrets and are
not needed to run AutoCAD, so they are not part of this repository.

## Known limits

* The run stops at the licensing/sign-in screen: continuing needs an AutoCAD 2027 entitlement
  and a sign-in. Without one, the licensing agent's own WebView2 shows its generic error page.
* `AdskAccessUIHost.exe` (an Electron-based Autodesk UI host) hits an unresolved Node/libuv
  stdio problem under Wine (`EBADF` on a piped stdout).
* No tests were written for the Wine changes.
* Importing Windows certificates does not help and is not part of any fix — patches 0001/0007
  are what the trust and certificate-store gaps needed.
