# SETUP — from this checkout to AutoCAD 2027 running on Wine

This is the long form of `README.md`'s Requirements section: every prerequisite, every
path the scripts expect, and every step between "I have this repository" and "acad.exe is
up". `tools/check_prereqs.sh` checks all of it on your machine and prints the same steps.

**Nothing Autodesk is redistributed here.** You need your own AutoCAD 2027 download from
your Autodesk account, and the run stops at the licensing/sign-in screen (see
[Known limits](#known-limits)).

**What you do *not* need:** a Windows machine or a Windows guest, Windows certificates or
their private keys, the original developer's toolchain rootfs (`root/`), the original
`prefix/`, or the reference data (`vmshare/`) — nothing in the shipped scripts reads them.

---

## 0. Check the machine first

```
tools/check_prereqs.sh                       # one line per requirement + the steps for this box
tools/check_prereqs.sh --prefix ~/acad-prefix # also reports on an installed prefix
```

`[MISSING]` lines are blocking, `[ opt]` lines are compiled-out features. Exit code 1 =
something blocking is missing. The script changes nothing.

## 1. Host packages

Debian/Ubuntu names; the checker prints the exact `apt-get install` line for your gaps.

| what | package | needed for |
|---|---|---|
| `make`, `m4`, `patch`, `pkg-config` | `make m4 patch pkg-config` | the build |
| `flex` >= 2.5.33, `bison` >= 3.0 | `flex bison` | Wine's parser/lexer generation (configure hard-fails without them) |
| C compiler + PE cross compiler | `clang lld llvm` **or** `mingw-w64` | the Unix side, and the Windows-side PE DLLs (`llvm-dlltool` comes from `llvm`) |
| freetype | `libfreetype-dev` | every glyph acad's UI draws |
| X11 + X extensions | `libx11-dev libxext-dev libxrender-dev libxrandr-dev libxi-dev libxcursor-dev libxinerama-dev libxfixes-dev libxcomposite-dev libxkbcommon-dev` | winex11 |
| TLS | `libgnutls28-dev` | the licensing/WebView2 HTTPS traffic |
| python | `python3` (+ `python3-venv`) | `tools/venv`, used by the install/verify scripts |
| X tools | `x11-utils xdotool imagemagick procps` | `ui_plug.sh` samples windows/screenshots |
| fonts | `fonts-liberation` | `arial.ttf`/`arialbd.ttf` are built from Liberation Sans |
| (optional) | `libfontconfig-dev libdbus-1-dev libasound2-dev libpulse-dev libvulkan-dev libwayland-dev libunwind-dev libcups2-dev libudev-dev libgstreamer1.0-dev libkrb5-dev libldap2-dev libxml2-dev libncurses-dev zlib1g-dev` | features Wine compiles out otherwise |

The reference build was made **without** Xrender/Xcursor/Xi/Shm/Vulkan/SDL2/pulse/alsa/
dbus/udev/fontconfig and still ran AutoCAD, so treat the last row as optional.

**No sudo?** The project this came from built rootless: `apt-get download <pkg>`, then
`dpkg-deb -x <pkg>.deb root/`. `env.sh` prepends `root/usr/bin` to `PATH` and points
`BISON_PKGDATADIR`/`M4`/`PKG_CONFIG_PATH` at that rootfs **only when `root/` exists**;
without it the system toolchain is used unchanged.

**A system `wine` package is not used and not needed** — the scripts run the fork built
here (`wine-install/bin/wine`).

## 2. The AutoCAD media (the one thing you must supply)

`tools/install_fresh_prefix.sh` runs the ODIS installer unattended from a directory that
contains **both** `Setup.exe` and `ODIS/`. The file you download from Autodesk
(`Autodesk_AutoCAD_2027_1_English_en-US_setup_webinstall.exe`) is the ODIS *bootstrapper*,
not that directory: running it (on Windows, or in any Wine prefix) unpacks `Setup.exe` +
`ODIS/` into its extraction directory (`C:\Autodesk\...` / `%TEMP%`) before it downloads
the packages. Copy the extracted directory to `installer/`, or point the scripts at it:

```
ACAD_MEDIA=/mnt/media/autocad tools/install_fresh_prefix.sh ~/acad-prefix
tools/check_prereqs.sh --media /mnt/media/autocad
```

* **Stay online for the install.** `Setup.exe -q` downloads the real packages; the run
  takes tens of minutes (`INSTALL_TIMEOUT`, default 7200 s).
* `pkgs/` is **optional** and only used by `--repair`: the extracted package payloads
  (`pkgs/x/x64/acadprivate/acadprivate.msi` + `PF/Root/`, `pkgs/x/x64/en-US/acadps/acadps.msi`,
  `pkgs/pkg.acadps1.tar.xz` — override with `ACADPS_PAYLOAD` / `ACADPS_CUIX_DIR`).
  `tools/fix_licensing_registration.sh` needs `pkgs/x/x64/acadprivate/AutoCADConfig.pit`.
  A normal (non-`--repair`) install fetches its own packages and needs none of this.
* `pkgs/dotnet/` is optional: without it the .NET Desktop Runtime is downloaded from
  `builds.dotnet.microsoft.com` if the installer did not bring one.
* A `.dwg` for the verify run is optional: set `VERIFY_DWG=/path/to/file.dwg` or the run
  proceeds without a drawing.

## 3. Build the patched Wine

```
tools/check_prereqs.sh
tools/build_wine.sh                     # ~30-60 min; JOBS=n caps parallelism
```

What it does, in order: copies the tracked `wine-11.18/` (already carrying all 13 patches)
to the gitignored build tree `wine/wine-11.18/`, runs

```
./configure --prefix=<checkout>/wine-install --enable-archs=i386,x86_64
```

(the reference configuration; clang/lld is picked up automatically as the PE cross
compiler), then `make -j$(nproc)` and `make install` → `wine-install/`.

* `EXTRA_CONFIGURE="--disable-tests" tools/build_wine.sh` skips the test suite and shortens
  the build.
* `tools/build_wine.sh --dry-run` prints the commands without running them;
  `--configure-only`, `--clean`, `--archs=x86_64`, `--no-check` are available.
* Later rebuilds: `run_build.sh` (incremental `make`, no configure).
* A single module after an edit, the way this project was developed:
  `make -C dlls/urlmon -j$(nproc)` then copy the DLL into
  `wine-install/lib/wine/{x86_64,i386}-windows/`.
* Logs: `logs/build_configure.log`, `logs/build.log`.
* `wine-install/share/wine/fonts/tahoma.ttf` must exist afterwards — `micross.ttf` is built
  from it plus Liberation Sans.

## 4. An X display for the UI runs

`ui_plug.sh` and `verify_fresh_prefix.sh` default to `:2` and need `xwininfo`/`xdotool`/
`import`/`pgrep`. Start a display that no compositor/portal owns:

```
Xvfb :2 -screen 0 1920x1080x24 &                        # headless; screenshots still work
Xtigervnc :2 -geometry 1920x1080 -SecurityTypes None -localhost &   # if you want to watch
```

`DISP=:0` selects another display. On a Wayland session `import -window root` fails, which
is why the scripts use a dedicated display.

## 5. Python venv (used by install and verify)

```
python3 -m venv tools/venv
tools/venv/bin/pip install fonttools          # for tools/make_wine_fonts.py
```

Without `tools/venv` both scripts stop; without `fonttools` the font fixup cannot run and
the WPF UI stays blank.

## 6. Install into an empty prefix

```
tools/install_fresh_prefix.sh ~/acad-prefix
```

creates a win64/Windows-10 prefix (`wineboot -u`), runs the unattended Autodesk install,
measures what the installer produced against the Windows reference numbers, then applies
the four Wine-environment fixups a prefix needs (Arial/Arial Bold/Microsoft Sans Serif +
fonts registry, the `installed-components.autodesk` hosts line, `RpcSs`/`SamSs` Start=2,
`HKCU\Environment\WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--disable-gpu`). It ends with a
`present` / `fixup` / `MISSING` line per end-state component and prints "prefix is ready".
Logs: `logs/freshinstall/<prefix-name>/`.

* `--install-only` — stop after the install and its measurement (acceptance path).
* `--repair` — additionally apply the installer-defect workarounds (acadprivate MSI/payload,
  licensing registration, acadps/CUIX, .NET). Only for a prefix whose install came out
  incomplete; a normal install needs none of it.
* `--force-install` — install even if `acad.exe` is already there.
* `ACAD_WINE=/path/to/wine` uses a different patched Wine binary.

## 7. Verify

```
tools/verify_fresh_prefix.sh ~/acad-prefix 240          # add --apphome for the Start-tab webview
```

launches acad from that prefix on `:2` (or `DISP`), samples the X tree and screenshots, and
prints one PASS/FAIL line per acceptance check: a titled acad window, a painted (non-blank)
frame, zero `.NET Assertion Failed` dialogs, no licence-error dialog, and the licensing
agent's WebView2 having reached `/ui/v2/lgs`. Evidence: `logs/ui/<tag>/` and `log_<tag>.txt`.
One check is reported `SKIP`: the licence-failure record comes from a debug-only Wine patch
that is not part of this repository.

## Known limits

* **The run ends at the licensing screen.** This repository was tested up to the licensing
  UI ("Let's Get Started"); getting past it needs an AutoCAD 2027 entitlement and a
  sign-in. Without one the licensing agent's own WebView2 shows its generic error page.
* `AdskAccessUIHost.exe`, an Electron-based Autodesk UI host, hits an unresolved
  Node/libuv stdio problem under Wine (`EBADF` on a piped stdout). Nothing here works
  around it.
* No tests were created for the Wine changes: each patch carries its symptom, the Windows
  behaviour it restores, and the evidence it was verified with. Not upstream-ready.
* 3D/GPU-accelerated Autodesk products were not tested; only AutoCAD's 2D UI path was.

## Troubleshooting

| symptom | cause | fix |
|---|---|---|
| `no suitable bison/flex found` | missing/too old | install `bison`/`flex` (>= 3.0 / >= 2.5.33) |
| `cannot build a 32-bit program` | no 32-bit dev libs | install them, or build with `--archs=x86_64` |
| `install media missing` | no `Setup.exe`+`ODIS/` at `ACAD_MEDIA` | see [section 2](#2-the-autocad-media-the-one-thing-you-must-supply) |
| install finishes but no `acad.exe` | ODIS ran a delegate-update **uninstall** pass over the fresh install | the script retries; if it persists, use `--repair` |
| `License manager is not functioning or is improperly installed` | `AcJab.dll` (acadprivate payload) missing → licensing code 20001 "AcJab.dll branding error" | `--repair` installs the payload and the licensing registration |
| ribbon/status bar unstyled, `.NET Assertion Failed` dialog | urlmon `res://` zone mapping (patch 0003) missing from the build | rebuild from `wine-11.18/`, which has it applied |
| blank windows, blank palettes, no text | fonts: `wine-install/share/wine/fonts/tahoma.ttf` and Liberation Sans must exist, and the prefix needs `arial.ttf`/`arialbd.ttf`/`micross.ttf` | `tools/build_wine.sh`; then the font fixup (needs `fonttools`) |
| webview areas stay blank rectangles | Chromium needs software painting | `HKCU\Environment\WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--disable-gpu` (the fixup sets it) |
| `ui_plug.sh` finds no window | no display / wrong display / no XAUTHORITY | start `Xvfb :2 ...`, or set `DISP`; the script prints why it refused to run |
| certificate-store or signature errors | **not** a certificate problem: patches 0001/0007 supply the missing wintrust blob/timestamp handling and the group-policy/enterprise stores | rebuild; do **not** import Windows certificates — the original project tried exactly that and it changed nothing |

## Layout

| path | what it is |
|---|---|
| `wine-11.18/` | tracked Wine 11.18 source **with all 13 patches applied**; never built in place |
| `patches/` | the same 13 changes as individual patches, each with its reasoning and evidence |
| `env.sh` | paths for everything below; `source` it (rootfs-aware, `ACAD_MEDIA` override) |
| `tools/check_prereqs.sh` | verify a machine can build/install, with remediation |
| `tools/build_wine.sh` | copy → configure → make → `make install` into `wine-install/` |
| `run_build.sh` | incremental `make` in the existing build tree |
| `tools/install_fresh_prefix.sh` | empty prefix → installed, registered, rendering AutoCAD |
| `tools/verify_fresh_prefix.sh` | re-reads the evidence, PASS/FAIL per acceptance check |
| `tools/fix_licensing_registration.sh` | fallback for the acadprivate MSI's licensing custom action |
| `tools/make_wine_fonts.py` | builds the Arial / Microsoft Sans Serif substitutes the WPF UI asks for |
| `ui_plug.sh` | launches `acad.exe` on the display and samples windows/screenshots |

Generated, gitignored, re-creatable: `wine/` (build tree), `wine-install/` (the build),
`prefix*/` (installed products), `installer/`, `pkgs/`, `logs/`, `tools/venv/`.
