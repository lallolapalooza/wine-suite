# Acceptance checklist — what "opens like in Windows" means for SDA

Derived from the Windows reference run: `evidence/win_sda_app.log` (guest, 2026-10-03 18:42,
SDA 1.40.1, Windows 11 25H2 build 26200), plus `virsh screenshot` captures
`evidence/win_sda_app_01.png` (OCR: title "Steinberg Download Assistant", `Sign in`,
`Remember me`).

## Observable end state on Windows

| # | check | Windows reference value |
|---|---|---|
| A1 | process runs | `Steinberg Download Assistant` (~144 MB WS), `Responding = True` |
| A2 | helper process | `aria2c` running, RPC on TCP 6800 |
| A3 | window exists | class **`GlassWndClass-GlassWindowClass-3`** (JavaFX Glass), title `Steinberg Download Assistant`, 586x239 |
| A4 | window content | login form: `Sign in` button, `Remember me` checkbox |
| A5 | app log milestones | see below |
| A6 | exit | closing the window terminates the app and `aria2c` |

## Log milestones, in order (this is the diffable sequence)

```
o.s.boot.SpringApplication            : Starting application using Java 1.8.0_492 ... PID ... started by ... in
                                        C:\Program Files (x86)\Steinberg\Download Assistant\app
n.s.e.d.d.a.i.Aria2SettingsService    : Use free port 6800 for Aria (within the configured range 6800-6850)
n.s.e.d.c.DownloadDirectoryServiceImpl: Set default download subfolder to Steinberg
n.s.e.d.d.a.internal.Aria2Configuration: Aria2 Installation found. Creating Aria2Process.
n.s.e.d.c.SystemInformationServiceImpl: getPid() - This JVM's name is '<pid>@<host>'
n.s.e.d.d.aria2.internal.Aria2Process  : Start Aria2: <...>\3rd Party\optional\aria2\aria2c.exe, --no-conf=true,
                                        --enable-rpc, --rpc-listen-port=6800, --rpc-secret=<uuid>,
                                        --rpc-listen-all=false, --dir=...\Steinberg, --auto-save-interval=1,
                                        --retry-wait=5, --max-concurrent-downloads=5,
                                        --max-overall-download-limit=0K, --max-tries=5,
                                        --stop-with-process=<pid>, --file-allocation=falloc
n.s.e.d.d.aria2.internal.Aria2Process  : stream: [NOTICE] IPv4/IPv6 RPC: listening on TCP port 6800
n.s.e.d.common.system.WindowsOsHelper  : Windows OS Information:
                                        - buildLabEx [registry]   : '26100.1.amd64fre.ge_release.240331-1435'
                                        - WinBuild [registry]     : '26200'
                                        - ProgramW6432 [env]      : 'C:\Program Files'
                                        - ProgramFiles [env]      : 'C:\Program Files (x86)'
                                        - ProgramFiles(x86) [env] : 'C:\Program Files (x86)'
                                        - Proc Arch [env]         : 'x86'
                                        - Proc Arch W6432 [env]   : 'AMD64'
n.s.e.d.common.system.WindowsOsHelper  : isWow64Process = true, processMachine = 332, nativeMachine = 34404
                                        => isArm64OS = false
n.s.e.d.common.system.WindowsOsHelper  : buildLabEx contains amd64, ProgramFiles(x86) environment variable
                                        exists => isWin64OS=true
n.s.e.d.common.system.WindowsOsHelper  : Windows platform was determined as WIN64
n.s.e.d.c.UserAgentServiceFromSystem   : User Agent: Steinberg Download Assistant/1.40.1
                                        ({"ClientBits":"32", "OSName":"Windows 10 Enterprise",
                                          "OSVersion":"10.0 (26100.1.amd64fre.ge_release.240331-1435) x86",
                                          "OSBits":"64", "OSLanguage":"en_US", "AriaVersion":"1.37.0"}; +https://...)
n.s.e.d.http.AuthorizedHttpHandlerFactory: Created final HttpHandler after UserAgentService is initialized.
... GET https://pathfinder.mb.steinberg.net/rest/oidc-issuer -> 200 {"href":"https://iam.steinberg.net:443/am/oauth2"}
... GET .../rest/sda-redirect-uri-steinbergid   -> 200 {"href":"https://flow.steinberg.net/login/application/sda/steinbergid"}
... GET .../rest/sda-selfupdate-v2              -> 200 {"href":".../desktopClients/update/sda"}
... GET .../desktopClients/update/sda           -> 200 {"updateRequired":false}
o.s.boot.SpringApplication             : Started application in 24.233 seconds (JVM running for 31.971)
n.s.elicenser.download.Application     : Java Version: 1.8.0_492
n.s.elicenser.download.Application     : Java Home: C:\Program Files (x86)\Steinberg\Download Assistant\runtime
n.s.elicenser.download.Application     : start() - Start JFX scene
n.s.e.download.oidc.NimbusOIDCService  : Restoring persisted authorization
n.s.e.d.w.WindowsCredentialManagerAccess: WARN Read received an error: [1168] Element not found.   <- expected on a fresh profile
n.s.e.download.gui.common.Styles       : Font loaded '/fonts/AkzidGroCFFBol.otf' -> 'Akzidenz Grotesk BE Bold'
```

## Things Wine must match, called out explicitly

* **`BuildLabEx`** (`HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion`). Wine sets
  `CurrentBuild`/`CurrentBuildNumber`/`UBR`/`EditionId`/`InstallationType`/`ProductName` but **not**
  `BuildLab`/`BuildLabEx` (`loader/wine.inf.in`, `[VersionInfo]`). The app (a) logs it, (b) puts it
  in the User-Agent, and (c) **decides `isWin64OS` from `buildLabEx contains "amd64"`**. WineHQ bug
  47598's "Could not determine BuildLabEx from registry!" is the same read. Expected patch:
  provide `BuildLabEx` (and `BuildLab`) reflecting the actual build/architecture.
* **`IsWow64Process2`** must report `processMachine = 0x014c` (I386) and `nativeMachine = 0x8664`
  (AMD64) for a 32-bit process in a 64-bit prefix, so `isArm64OS=false` and `isWin64OS=true`.
* **`ProgramFiles(x86)` / `ProgramW6432`** environment variables must exist in a win64 prefix.
* **Windows Credential Manager** must answer with a clean "not found" (`ERROR_NOT_FOUND` = 1168) on
  a fresh profile, not a crash.
* **JavaFX** must reach `start() - Start JFX scene` and create a `GlassWndClass-*` window; the
  rendering pipeline can be forced from the app's own `.cfg` without touching code
  (`tools/apply_jvm_options.sh`).

## Result on Wine (measured)

| # | check | Windows reference | Wine result |
|---|---|---|---|
| A1 | process runs | `Steinberg Download Assistant`, Responding=True | **PASS** — same binary, runs, stays up |
| A2 | helper process | `aria2c`, RPC on 6800 | **PASS** — spawned with byte-identical arguments (`--no-conf=true … --file-allocation=falloc`) |
| A3 | window exists | `GlassWndClass-GlassWindowClass-3`, `Steinberg Download Assistant`, 586x239 | **PASS** — title `Steinberg Download Assistant`, 570x200; Glass window class present (`xwininfo`) |
| A4 | window content | `Sign in`, `Remember me` | **PASS** — OCR reads exactly `Sign in` and `Remember me`; 247 vs 227 unique colours |
| A5 | log milestones | the sequence in the table above | **PASS** — reproduced step for step, including `SelfUpdate … no newer version`, `[1168] Element not found` and the `AkzidGroCFFBol.otf` font load |
| A6 | exit | closing terminates app + aria2c | **PASS** — `wineserver -k` / window close stops both |

Wine stderr for a full run is 5 lines, all benign: two `libEGL warning: DRI3 error` (Xvfb has no
DRI3), two `err:ole:com_get_class_object` for an unregistered class GUID, one
`fixme:file:NtLockFile` — none of which the app depends on.

Two differences from Windows remain, both explained and intended:

* the window is 570x200 vs 586x239 because there is no window-manager frame in the capture
  (the Windows capture includes its title bar and border);
* the rendering pipeline is pinned to `j2d` (`tools/apply_jvm_options.sh`) because Wine's
  `d3d`/`es2` JavaFX pipelines draw the layout but not the glyphs — WineHQ bug 37048. With that
  pin the visible result is identical to Windows.

