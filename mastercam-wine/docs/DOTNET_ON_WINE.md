# .NET on Wine — can Mastercam 2027's `net10.0` ManagedUI run under our patched Wine?

Ticket: **DotnetProbe**. Wine used: `/home/asdf/projects/resolume-wine/wine-install/bin/wine`
(`wine-11.18`, pristine 11.18 + the project's AutoCAD(14)+PowerBI(5) patch series — identical
base to the tree this project builds; our own build was still compiling).

Scratch: `state/exp/DotnetProbe/` (prefix `state/exp/DotnetProbe/prefix`), `TMPDIR=state/tmp`.

**Verdict (short).** Yes. The official **Microsoft Windows Desktop Runtime 10.0.12 (x64)** — the
`net10.0` WindowsDesktop runtime, containing both `Microsoft.NETCore.App` and
`Microsoft.WindowsDesktop.App` — installs cleanly into a `win64`/Windows-10 Wine prefix with
`exit code 0x0`, framework-dependent `net10.0` and `net10.0-windows` **WPF** apps then execute,
and WPF **does present a real, painted, OCR-readable window** under Wine (both on a headless Xvfb
and as a WM-managed top-level on the real display `:0`). Nothing failed: there is no first failing
call to report, and the Wine log contains **zero `err:` lines** for the whole WPF run. The only
notable issues are `fixme` stubs (chiefly `dwmapi:DwmAttachMilContent`) and a GL/DRI3 warning on
the headless X server. The other prerequisite Mastercam needs — **.NET Framework 4.8**
(`winetricks -q dotnet48`, which itself pulls in `dotnet40`) — also installs (`WT_EXIT=0`) and runs
managed code (`.NET Framework 4.8.3761.0`).

Mastercam ships **.NET Framework 4.8** (`SetupPrerequisites/ndp48-x86-x64-allos-enu.exe`) but **no
.NET 10 runtime** — so the .NET 10 Desktop Runtime must be installed separately, and it works.

---

## 0. What Mastercam's ManagedUI actually requires

From `docs/PAYLOAD_RECON.md` §".NET vs native", the shipped `ManagedUI` `*.runtimeconfig.json` is:

```json
{ "runtimeOptions": { "tfm": "net10.0",
    "frameworks": [ { "name": "Microsoft.NETCore.App",       "version": "10.0.0" },
                    { "name": "Microsoft.WindowsDesktop.App", "version": "10.0.0" } ] } }
```

So the requirement is exactly two shared frameworks, `Microsoft.NETCore.App 10.0.0` and
`Microsoft.WindowsDesktop.App 10.0.0` (roll-forward to any 10.0.x patch). The installer bundles
only `ijwhost.dll` (C++/CLI shim) and the **.NET Framework 4.8** offline installer; it does not
bundle any CoreCLR/hostfxr (`grep -iE 'hostfxr|coreclr|hostpolicy|clrjit'` over the MSI `File`
table → nothing). Hence the experiment below.

## 1. Baseline — fresh `win64` prefix, Windows 10, no .NET

```console
$ mkdir -p state/exp/DotnetProbe && cd state/exp/DotnetProbe
$ export WINEPREFIX=$PWD/prefix WINEARCH=win64 TMPDIR=.../state/tmp WINEDEBUG=-all
$ wine wineboot -u
wine: created the configuration directory '.../state/exp/DotnetProbe/prefix'      # exit 0
$ wine reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' /v CurrentVersion /d 10.0 /f
$ wine reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' /v ProductName   /d 'Windows 10 Pro' /f
$ wine reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' /v CurrentBuild  /d 19045 /f

$ ls prefix/drive_c/Program\ Files/dotnet
ls: cannot access '.../prefix/drive_c/Program Files/dotnet': No such file or directory
$ wine 'C:\windows\system32\dotnet.exe' --info
wine: failed to open ".../prefix/drive_c/windows/system32/dotnet.exe"
```

→ **No .NET runtime of any kind is present in a fresh prefix**, and no `dotnet.exe` host.

The Windows-10 setting took effect — the runtime installer's own log reports
`Windows v10.0 x64 (Build 19045: Service Pack 0)` and the managed probe later reports
`RuntimeInformation.OSDescription = Microsoft Windows 10.0.19045`.

## 2. Install the official .NET 10 Windows Desktop Runtime

Download (hash checked against the Microsoft release metadata
`https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/10.0/releases.json`):

```console
$ curl -sL -o windowsdesktop-runtime-10.0.12-win-x64.exe \
    https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/10.0.12/windowsdesktop-runtime-10.0.12-win-x64.exe
$ sha512sum windowsdesktop-runtime-10.0.12-win-x64.exe
0b907e9312867172a4eb82f4b5ab3f7c2d25e27d8349546d77eeb5d5b8cbecab9ebebfed189b13e9669dc578d892756c548366da539d47b3ddac5efcb7ae72fe
# identical to the `hash` field published in releases.json for 10.0.12 win-x64
```

Silent install exactly as the ticket specifies:

```console
$ wine wd10.exe /install /quiet /norestart /log C:\\wd10.log
$ echo $?
0
```

The bundle (`Burn x86 v6.0.3-dotnet.6`) ran its full 4-package plan and finished:
`prefix/drive_c/wd10.log`:

```
[00E0:00E4]i009: Command Line: '/install /quiet /norestart /log C:\wd10.log'
[00E0:00E4]i201: Planned package: DotNetHost,             execute: Install
[00E0:00E4]i201: Planned package: DotNetHostFxr,          execute: Install
[00E0:00E4]i201: Planned package: DotNetRuntime,          execute: Install
[00E0:00E4]i201: Planned package: WindowsDesktopRuntime,  execute: Install
[00E0:00E4]i319: Applied execute package: DotNetHost,            result: 0x0
[00E0:00E4]i319: Applied execute package: DotNetHostFxr,         result: 0x0
[00E0:00E4]i319: Applied execute package: DotNetRuntime,         result: 0x0
[00E0:00E4]i319: Applied execute package: WindowsDesktopRuntime, result: 0x0
[00E0:00E4]i399: Apply complete, result: 0x0, restart: None, ba requested restart: No
[00E0:00E4]i007: Exit code: 0x0, restarting: No
```

Notes for anyone repeating this:

* `/install` is reported as `i000: Ignoring unknown argument: /install` — harmless; Burn defaults to
  install. `/quiet /norestart` were honoured (`WixBundleUILevel = 2`, `RebootPending = 0`).
* The per-package MSI logs are `prefix/drive_c/wd10_00{0..3}_*.log`; the desktop-runtime MSI ends
  `Action ended 10:59:56: INSTALL. Return value 1.` (1 = success in MSI-speak).
* Whole run ≈ 2 min 25 s under `+seh,+relay` tracing; much faster untraced.

Result on disk + in the registry (all written by the vendor MSI under Wine's `msi.dll`):

```console
$ ls 'prefix/drive_c/Program Files/dotnet'
dotnet.exe  host  shared  swidtag  LICENSE.txt  ThirdPartyNotices.txt
$ ls 'prefix/drive_c/Program Files/dotnet/shared/Microsoft.NETCore.App'
10.0.12                       # 188 files (coreclr.dll, clrjit.dll, System.Private.CoreLib.dll, …)
$ ls 'prefix/drive_c/Program Files/dotnet/shared/Microsoft.WindowsDesktop.App'
10.0.12                       # 78 files (PresentationFramework.dll, PresentationCore.dll,
                              #   WindowsBase.dll, wpfgfx_cor3.dll, D3DCompiler_47_cor3.dll,
                              #   DirectWriteForwarder.dll, ReachFramework.dll, System.Printing.dll,
                              #   UIAutomation*.dll, PenImc_cor3.dll, …)
$ grep -a -A3 'Software\\\\dotnet\\\\Setup\\\\InstalledVersions\\\\x64\\\\sharedhost' prefix/system.reg
"Path"="C:\\Program Files\\dotnet\\"
"Version"="10.0.12"
```

The `hostfxr`/`sharedfx` keys under `SOFTWARE\dotnet\Setup\InstalledVersions\x64\...` are present
too — that is what `ijwhost.dll` (Mastercam's C++/CLI shim) and `hostfxr` use to locate the install.

## 3. Does managed code run? Yes.

```console
$ wine 'C:\Program Files\dotnet\dotnet.exe' --info
Host:
  Version:      10.0.12
  Architecture: x64
  RID:          win-x64
.NET SDKs installed:
  No SDKs were found.
.NET runtimes installed:
  Microsoft.NETCore.App 10.0.12 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
  Microsoft.WindowsDesktop.App 10.0.12 [C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App]
$ echo $?
0
$ wine 'C:\Program Files\dotnet\dotnet.exe' --list-runtimes
Microsoft.NETCore.App 10.0.12 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
Microsoft.WindowsDesktop.App 10.0.12 [C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App]
```

### Framework-dependent console app (`net10.0`, pinned to `10.0.0` → proves roll-forward)

Cross-built on the host with the local SDK (`~/.dotnet10`, SDK 10.0.401):

```console
$ dotnet publish -c Release -r win-x64 --self-contained false
```

`hello.runtimeconfig.json` pins `Microsoft.NETCore.App 10.0.0` — the *same* shape as Mastercam's
`net10.0` runtimeconfig — and it rolled forward to 10.0.12:

```console
$ ls prefix/drive_c/hello     # no runtime DLLs shipped: genuinely framework-dependent
hello.deps.json  hello.dll  hello.exe  hello.pdb  hello.runtimeconfig.json

$ wine 'C:\hello\hello.exe' one two
HELLO-MANAGED-OK
FrameworkDescription=.NET 10.0.12
OSDescription=Microsoft Windows 10.0.19045
OSArch=X64
ProcessArch=X64
Environment.Version=10.0.12
BaseDirectory=C:\hello\
ARGV=one|two
$ echo $?
42
```

Same result via `wine 'C:\Program Files\dotnet\dotnet.exe' 'C:\hello\hello.dll' a b` (exit 42).
So: **JIT, BCL, console I/O, `Environment`, `RuntimeInformation`, P/Invoke-free runtime services and
process exit codes all work.**

## 4. Does WPF present a window? Yes — verified with `xwininfo` + OCR.

Probe: `net10.0-windows` + `UseWPF=true`, framework-dependent, published `-r win-x64
--self-contained false`, with a runtimeconfig that names exactly the same `tfm` and the same two
frameworks/versions as Mastercam's (`net10.0`; `Microsoft.NETCore.App 10.0.0`;
`Microsoft.WindowsDesktop.App 10.0.0` — only the optional `configProperties` block differs). It
prints from `Main`, builds a real `Window` (`Title="WPF-PROBE-WINDOW"`, `StackPanel` of
`TextBlock`s), reports `RenderCapability.Tier`, writes a marker file, and closes itself after 25 s.

Run under an isolated headless server: `xvfb-run -a -s "-screen 0 1400x900x24"`.

Application stdout/stderr:

```
libEGL warning: DRI3 error: Could not get DRI3 device
libEGL warning: Ensure your X server supports DRI3 to get accelerated rendering
WPF-MAIN-ENTER
WPF-STARTUP-EVENT
WPF-WINDOW-LOADED
WPF-RENDER-TIER=131072
WPF-TIER-DESC=hardware
WPF-TIMER-TICK-EXITING
WPF-WINDOW-CLOSED
WPF-APP-RUN-RETURNED
```

(X-server window list at the time — WPF registered its real HWND plus its infrastructure windows:)

```console
$ xdotool search --name 'WPF-PROBE-WINDOW'
10485765
$ xwininfo -id 0xa00005
xwininfo: Window id: 0xa00005 "WPF-PROBE-WINDOW"
  Width: 412   Height: 226   Depth: 24   Visual Class: TrueColor
  Map State: IsViewable
$ xwininfo -root -tree | grep -i wpfprobe
 0xa00005 "WPF-PROBE-WINDOW": ("wpfprobe.exe" "wpfprobe.exe")  412x226+4+30
    1 child: 0x800052 (has no name): ()  412x226+0+0
 0xa00004 "MediaContextNotificationWindow": ("wpfprobe.exe" "wpfprobe.exe")  1x1+0+0
 0xa00003 "SystemResourceNotifyWindow": ("wpfprobe.exe" "wpfprobe.exe")  1x1+0+0
```

The `MediaContextNotificationWindow` / `SystemResourceNotifyWindow` pair only exists once WPF's
`MediaContext` (MilCore) has been created, so this is the WPF stack, not just a Win32 window.

**Pixel proof.** Capturing the window itself:

```console
$ import -window 0xa00005 wpf2-win.png
$ identify wpf2-win.png
wpf2-win.png PNG 412x226 8-bit Grayscale Gray 256c 2114B      # 173 colours → real content
$ convert wpf2-win.png -resize 300% -colorspace Gray -normalize wpf2-win-ocr.png
$ tesseract wpf2-win-ocr.png wpf2-win-ocr && cat wpf2-win-ocr.txt
WPF PROBE OK

tier =131072
```

Cross-check on the whole virtual screen (`import -window root`) also contains the painted window,
so WPF composites on the X root even with no window manager/compositor present:

```console
$ identify wpf2-root2.png
wpf2-root2.png PNG 1400x900 8-bit Grayscale Gray 256c 3680B    # 173 colours
$ tesseract <(convert wpf2-root2.png -resize 200% -colorspace Gray -normalize png:-) - 2>/dev/null
WP PROBE OK
tier =131072
```

(One caveat learned the hard way: the *first* root capture of the session came back solid black.
That was a cold-start timing artefact — the window `HWND` already existed (`xwininfo`: `IsViewable`)
but WPF had not yet made its first paint while the runtime JIT-ed `PresentationFramework` from
disk. A later capture, after the window had painted, contains the content. Relevant for anyone
scripting a Mastercam UI screenshot: wait for first paint, not for window creation.)

And the app's own marker file, written from the `Loaded` handler:

```console
$ cat prefix/drive_c/wpf-started.txt
started tier=131072
```

### 4b. Same probe on the real display `:0` (with a window manager)

The probe was also run on the workstation's real X.Org server (`DISPLAY=:0`,
`dimensions: 1920x1200`, a reparenting WM owner present — `_NET_SUPPORTING_WM_CHECK = 0x600001`,
hostname `asdf-ThinkPad-E16-Gen-2`), i.e. *not* the headless Xvfb:

```console
$ DISPLAY=:0 wine 'C:\wpfapp\wpfprobe.exe' &        # window found after 5–6 s
$ wmctrl -l
0x01e00007  0 asdf-ThinkPad-E16-Gen-2 WPF-PROBE-WINDOW
$ xwininfo -root -tree | grep -i wpfprobe
 0x1e00007 "WPF-PROBE-WINDOW": ("wpfprobe.exe" "wpfprobe.exe")  412x226+25+62  +71+69
 0x1e00006 "MediaContextNotificationWindow": ("wpfprobe.exe" "wpfprobe.exe")  1x1+0+0
 0x1e00005 "SystemResourceNotifyWindow": ("wpfprobe.exe" "wpfprobe.exe")  1x1+0+0
$ xwininfo -id 0x1e00007 | grep -E 'Map State|Width|Height'
  Absolute upper-left X:  71      Absolute upper-left Y:  69
  Width: 412   Height: 226   Map State: IsViewable
# and the WM's decoration frame carrying the same name:
$ xdotool search --name WPF-PROBE-WINDOW   → 8390168 (462x313, IsViewable), 31457287 (412x226, IsViewable)
```

App log identical to the Xvfb run (`WPF-WINDOW-LOADED`, `WPF-RENDER-TIER=131072`,
`WPF-WINDOW-CLOSED`, `WPF-APP-RUN-RETURNED`, exit 0). So the WPF window is a first-class,
WM-managed, decorated, viewable top-level window on a real X server — not just on a bare Xvfb.

*Caveat on capturing pixels on `:0`:* `import -window …` and even `xwd -root` fail there with
`X Error … BadMatch` on `X_GetImage` — the X server on `:0` refuses `XGetImage` readback (and
`_NET_WM_CM_S0` is absent, so there is no compositor to grab through either). The OCR pixel proof
therefore comes from the Xvfb runs above, which share the same code path. Anyone scripting
screenshots of a Mastercam window must use a display that supports readback (or a compositor), not
`:0` as configured here.

`RenderCapability.Tier = 131072` (= `0x00020000`) is WPF's *tier 2 / hardware* value. Under Wine
this is wined3d-on-OpenGL; there is no D3D9/DXVA path of its own. The rendering nevertheless
succeeded on a **GPU-less Xvfb** (only a `libEGL … DRI3` warning, i.e. Mesa fell back), and the
window content was correct.

## 5. First failing call / exceptions — there are none

Full `WINEDEBUG=err+fixme` log for the WPF run (33 lines total), `grep -a '^[0-9a-f]*:err:'` → **no
matches**. The complete set of `fixme`s, in order:

```
fixme:process:GetProcessGroupAffinity ( …, stub )
fixme:seh:WerRegisterRuntimeExceptionModule (L"C:\Program Files\dotnet\shared\Microsoft.NETCore.App\10.0.12\mscordaccore.dll", …) stub
fixme:ntdll:NtQuerySystemInformation info_class SYSTEM_PERFORMANCE_INFORMATION
fixme:ntdll:EtwEventSetInformation (deadbeef, 2, …) stub               # ×5
fixme:msg:ChangeWindowMessageFilter c042 00000001
fixme:dwmapi:DwmAttachMilContent (000000000001005E) stub               # ← the WPF/MilCore hook
fixme:gdi:GdiEntry13 stub
fixme:dwrite:dwritefactory_CreateMonitorRenderingParams (…): monitor setting ignored
fixme:win:RegisterPowerSettingNotification (…): stub
fixme:wtsapi:WTSRegisterSessionNotification Stub …
fixme:msg:ChangeWindowMessageFilterEx …                                # ×2
fixme:d3d:wined3d_device_apply_stateblock Last Pixel Drawing Disabled, not handled yet.
fixme:d3d:state_linepattern_w Setting line patterns is not supported in OpenGL core contexts.
fixme:dwrite:dwritetextanalyzer_AnalyzeNumberSubstitution (…): stub
fixme:win:UnregisterPowerSettingNotification (00000000DEADBEEF): stub
fixme:wtsapi:WTSUnRegisterSessionNotification Stub …
fixme:dwmapi:DwmDetachMilContent (000000000001005E) stub
fixme:unwind:call_user_apc_dispatcher flags 0x3 are not supported.
```

Interpretation of the only two that touch the WPF render stack:

* `dwmapi:DwmAttachMilContent` / `DwmDetachMilContent` are **stubs** in Wine. WPF calls them to
  hand its D3D composition surface to the Desktop Window Manager **[INFERENCE: that is what these
  two calls do on Windows; Wine implements neither]**. With no DWM, WPF still rendered — the
  observable fact is that the call is stubbed, the app logged no error, and the window painted.
  This is the single most likely place to see renderer-specific breakage in a real Mastercam UI;
  here it was benign.
* `fixme:d3d:…Last Pixel Drawing Disabled…` / `state_linepattern_w … OpenGL core contexts` are
  wined3d state-translation messages, cosmetic.

The only genuine environmental warning is the Mesa/EGL one (`libEGL warning: DRI3 error: Could not
get DRI3 device`) caused by Xvfb having no DRI3/GPU — on a real X server with a working driver this
does not appear, and WPF's tier would be genuinely hardware-accelerated instead of wined3d-over-llvmpipe.

## 6. `winetricks -q dotnet48` (the *other* runtime — .NET Framework 4.8)

Kept deliberately separate from the .NET 10 test, in its own prefix `prefix-fx`. Mastercam needs
this too: it ships `SetupPrerequisites/ndp48-x86-x64-allos-enu.exe` (121 MB, `FileVersion
4.8.4115.0`) for its native MFC/ATL parts, `RunNGEN`, `CodeExpert.exe`, and GAC assemblies.

What the verb does in **winetricks 20250102** (`/usr/bin/winetricks`, sha256 `9df4af03…`) — the
whole body, verbatim:

```console
$ sed -n '9083,9122p' /usr/bin/winetricks
load_dotnet48()
{
    w_package_broken "https://bugs.winehq.org/show_bug.cgi?id=49532" 5.12 5.18
    w_package_broken "https://bugs.winehq.org/show_bug.cgi?id=49897" 5.18 6.6
    w_package_warn_win64
    # Official version. See https://dotnet.microsoft.com/download/dotnet-framework/net48
    w_download https://download.visualstudio.microsoft.com/download/pr/7afca223-…/ndp48-x86-x64-allos-enu.exe 95889d6d…
    w_call remove_mono internal
    w_call dotnet40                      # ← .NET Framework 4.0 is installed FIRST
    w_set_winver win7
    WINEDLLOVERRIDES=fusion=b w_try_ms_installer "${WINE}" "${file1}" /sfxlang:1027 /q /norestart
    w_override_dlls native mscoree
    w_try touch "${W_WINDIR_UNIX}/dotnet48.installed.workaround"
    case "${LANG}" in
        C|en_US.UTF-8*) ;;
        zh_CN*) w_warn "You may encounter infinite loops when trying to use applications that use
                        WPF. Use LC_ALL=C when running your application as a workaround."
    esac
}
```

Two things worth carrying into the Mastercam runbook:

* `dotnet48` **pulls in `dotnet40`**, temporarily flips the prefix to `winxp64` for it and back to
  `win7`; the `ndp48` installer is then run with `WINEDLLOVERRIDES=fusion=b` and the prefix is left
  with `mscoree` overridden to native. It also deletes Wine-Mono first (`remove_mono internal`).
* winetricks itself records a **known WPF infinite-loop bug for non-`en_US.UTF-8` locales**
  (winehq #47277) and recommends `LC_ALL=C` when running WPF apps — directly relevant to
  Mastercam's ManagedUI if the box is not English-locale.

Observed (`state/exp/DotnetProbe/fx-dotnet48.log`, `fx-dotnet48b.log`):

* downloads `ndp48-x86-x64-allos-enu.exe` to `~/.cache/winetricks/` (the *same* file Mastercam
  ships);
* `remove_mono internal` → `regsvr32: Successfully unregistered DLL …
  Microsoft.NET/Framework/v4.0.30319/diasymreader.dll` and deletes Wine-Mono `mscoree.dll`
  overrides;
* `w_call dotnet40` → flips the prefix winver to `winxp64`, runs
  `wine dotNetFx40_Full_x86_x64.exe /q /c:install.exe /q`, installs 4.0;
* `w_set_winver win7` → runs the 4.8 `ndp48` installer with `WINEDLLOVERRIDES=fusion=b …
  /sfxlang:1027 /q /norestart`;
* sets `*mscoree=native` (via `regedit /S C:\windows\Temp\override-dll.reg` in both the 32- and
  64-bit views) and touches `c:\windows\dotnet48.installed.workaround`.

**Result: success.** `winetricks -q -f dotnet48` finished with **`WT_EXIT=0`** (≈15 min wall under
`-q`), and the prefix verifies as a real .NET Framework 4.8:

```console
$ grep -a -A6 'NET Framework Setup\\NDP\\v4\\Full]' prefix-fx/system.reg
"Install"=dword:00000001
"InstallPath"="C:\\windows\\Microsoft.NET\\Framework64\\v4.0.30319\\"
"Release"=dword:00080eb1              # 0x80eb1 = 528049  → .NET Framework 4.8
$ ls -la prefix-fx/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319/mscorlib.dll
-rw-rw-r-- 5676080 Mar 28  2019 …/Framework64/v4.0.30319/mscorlib.dll
$ grep -a -A2 'Wine\\\\DllOverrides' prefix-fx/user.reg
"*mscoree"="native"
```

And managed Framework code actually runs — the framework's own `csc.exe` compiled and ran a test
program:

```console
$ wine 'C:\windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe' /nologo /out:C:\fxtest.exe C:\fxtest.cs
$ echo $?
0
$ wine 'C:\fxtest.exe'
FX48-MANAGED-OK
CLR=4.0.30319.42000
CLRdesc=.NET Framework 4.8.3761.0
$ echo $?
9
```

Winetricks warns `This package (dotnet48) may not fully work on a 64-bit installation` and that
Wine's new-WoW64 mode is experimental — the verb's own breakage metadata only covers Wine 5.12–6.6
(`w_package_broken … 5.12 5.18 / 5.18 6.6`), so 11.18 is *not* on its known-broken list, and indeed
it worked. This is *orthogonal* to the ManagedUI question — the .NET Framework 4.8 install path is
the classic one Mastercam's `setup.exe` already drives
(`ndp48-x86-x64-allos-enu.exe /q /norestart`), and it neither helps nor hinders whether the
`net10.0` WindowsDesktop runtime works. **Mastercam needs both, and both install.**

Practical note: run this verb in the *same* prefix that will host Mastercam — `dotnet48` also
installs `dotnet40` and leaves `*mscoree=native`, and it takes ~15 min and ~2.7 GiB.

## 7. What remains unknown / unverified

1. **End-to-end Mastercam ManagedUI.** The probes above prove the *runtime* works; nobody has yet
   started `Mastercam.exe` → C++/CLI `ManagedUI.Interop.dll` → `ijwhost.dll` → `hostfxr` → WPF.
   `ijwhost.dll` is **not** part of the runtime install (`find … -iname 'ijwhost*'` in
   `Program Files/dotnet` → nothing); Mastercam ships its own (v10.0.25.52411), and it will resolve
   `hostfxr` through the `SOFTWARE\dotnet\Setup\InstalledVersions\x64\...` keys that the installer
   did write. **[INFERENCE]** that chain will work; it is the highest-value thing to verify next.
2. **Mastercam's own WPF views** (Actipro controls, ~80 ManagedUI assemblies) — only a stock WPF
   window was exercised, not Mastercam's XAML. Actipro is pure WPF and should be unremarkable.
3. **GPU readback / performance.** Rendering was verified on the GPU-less Xvfb (pixels + OCR) and
   the window was verified as a WM-managed, viewable top-level on the real `:0`; but pixels could
   not be read back from `:0` (`XGetImage` → `BadMatch`, no compositor), so *visual* confirmation
   there is outstanding. Throughput of wined3d-on-OpenGL for a heavy Mastercam viewport is also
   untested.
4. **`Microsoft.WindowsDesktop.App` assemblies other than the ones WPF touches** — e.g.
   `WindowsBase` XPS/printing (`ReachFramework`, `System.Printing`) and
   `PresentationFramework.Classic/Aero2/Fluent` themes were not individually exercised.
5. **WebView2** (needed by the "My Mastercam" panel) is a *separate* native+managed stack and is out
   of scope here.

## 8. Recommended path for Mastercam's ManagedUI

1. **Install the runtime into the Mastercam prefix** exactly as tested:
   `windowsdesktop-runtime-10.0.12-win-x64.exe /install /quiet /norestart /log C:\wd10.log` —
   verified exit 0x0, and it registers both shared frameworks plus the `hostfxr`/`sharedhost`
   registry keys. 10.0.12 is fine for a `10.0.0`-pinned runtimeconfig (proven by the `hello`
   probe). Later 10.0.x patches are drop-in. Do this in the *same* prefix as Mastercam.
2. **Install .NET Framework 4.8 too** — a different stack, also required. Either let Mastercam's own
   `SetupPrerequisites/ndp48-x86-x64-allos-enu.exe` run (what `setup.exe` does:
   `/q /norestart`), or use the verified `winetricks -q dotnet48` (which additionally pulls in
   `dotnet40` and sets `*mscoree=native`; ~15 min, ~2.5 GiB). Installing one does not help the
   other: `dotnet48` alone will not run `net10.0` assemblies and the 10.0.x runtime alone will not
   run the .NET Framework side.
3. Do **not** expect Mastercam's shipped `WebView2Loader.dll`+wrappers to cover the web panel; the
   Edge WebView2 Evergreen Runtime is still a separate prerequisite.
4. Budget attention for `DwmAttachMilContent` (Wine stub). It did not break a stock WPF window, but
   it is the one WPF-render-path API Wine does not implement, so if Mastercam's UI shows a
   blank/black client area, that call is the first place to look (and to relay-trace).
5. Plan for WPF's GL fallback: with no GPU it still renders correctly, just slowly (`d3d` runs on
   OpenGL via wined3d). Also keep winetricks' caveat in mind — for non-`en_US.UTF-8` locales it
   records a WPF infinite-loop bug (winehq #47277) with the workaround `LC_ALL=C`.

---

### Evidence files (scratch, `state/exp/DotnetProbe/`)

| file | content |
|---|---|
| `dotnet-info.txt`, `dotnet-listruntimes.txt` | §3 host output |
| `hello-run.log`, `hello-run-dotnet.log` | §3 managed execution (exit 42) |
| `wpf1-live.log`, `wpf1-xstate.txt`, `wpf1-screen.png` | §4 first run (app stdout, window tree) |
| `wpf2-win.log`, `wpf2-wininfo.txt`, `wpf2-win.png`, `wpf2-win-ocr.png`, `wpf2-win-ocr.txt` | §4 window-pixel capture + OCR |
| `wpf-winedebug.log` | §5 full `err+fixme` log |
| `wpf-real0{,b,c,d}.log`, `wpf-real0c-wininfo.txt` | §4b real-display `:0` run |
| `hello/`, `wpfapp/` (with `*.csproj`, `Prog.cs`, `Program.cs`) | the two probe sources + FDD publish output |
| `prefix/drive_c/wd10.log`, `wd10_00{0..3}_*.log` | §2 bundle + per-MSI logs (`Exit code: 0x0`) |
| `fx-dotnet48.log`, `fx-dotnet48b.log`, `fx-run.log` | §6 winetricks dotnet48 (`WT_EXIT=0`) + Framework test app |
| `prefix/` | the .NET 10 Wine prefix (contains `Program Files/dotnet` with both runtimes) |
| `prefix-fx/` | the .NET Framework 4.8 prefix (**deleted after the run** to reclaim ~2.7 GiB) |
