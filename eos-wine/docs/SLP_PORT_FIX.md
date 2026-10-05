# Reproducible setup fix: ETC SLP must be able to bind port 427

## Symptom
`Eos.exe` paints its splash and then takes **~48–58 s** to reach the editor (window `Eos : 1`,
1600x1000), while on Windows the same transient self-heals in **~10 s**. The app's own logs show why:

`%LOCALAPPDATA%\ETC\EosFamily\v3\NetworkFeedback.log`
```
Network    Discovery InternalRegister: SLPReg() failed with result -19.      <- SLP_NETWORK_TIMED_OUT
```
`%LOCALAPPDATA%\ETC\EosFamily\v3\OnyxConsole.log`
```
Console    Registering for network changes...
CreateComponent Created component handle=ffffffff cid=EF4DC218-…            <- Windows: 80000000
OnyxConsole ACN started
OnyxConsole recovered from hang after 47.90 s                                <- Windows: ~10 s
```

## Cause — two independent gaps

1. **The ETC SLP component is not part of the product MSI.** The vendor NSIS bundle installs
   *ETC SLP 3.0.0.22* as a prerequisite; a direct `msiexec` install skips it. Windows ends up with
   `C:\Windows\SysWOW64\{slpd.exe,slptool.exe}` + `C:\Windows\slp.conf` and a **`slpd` service
   (Running, Automatic)**; `slp.conf` (`net.slp.useScopes=ACN-DEFAULT`, `net.slp.isDA=true`) makes Eos
   a local SLP Directory Agent on `127.0.0.1:427`. `Eos.exe` itself only ever **connects** to
   `127.0.0.1:427` — it never binds it.

2. **Even installed, `slpd` cannot bind 427 under Wine on this host.** Ports < 1024 are *privileged*
   on Linux (`net.ipv4.ip_unprivileged_port_start = 1024`, we run as uid 1000); the kernel returns
   `EPERM` and Wine faithfully maps it to `WSAEACCES`:

```
trace:winsock:bind socket 0x70, addr { AF_INET, address 127.0.0.1, port 427 }, len 16
trace:winsock:bind failed, status 0xc0000022        <- STATUS_ACCESS_DENIED -> WSAEACCES
slpd.log: NETWORK_ERROR - Could not listen for TCP on IPv4 loopback
```
   **Windows has no privileged-port concept**, so no Wine source patch can make this succeed without
   the capability — the fix belongs to the host.

## Fix
```sh
# 1. Install the ETC SLP component into the Wine prefix (it is inside the vendor NSIS bundle):
7z x ETC_EosFamily_v3.3.10.28.exe '$PLUGINSDIR/ETC_SLP_Install.exe' -o<dir>
WINEPREFIX=<prefix> wine <dir>/\$PLUGINSDIR/ETC_SLP_Install.exe /S /noreboot
WINEPREFIX=<prefix> wine sc start slpd          # -> STATE 4 RUNNING

# 2. Let the Wine process bind privileged ports (needs root). EITHER host-wide:
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=0     # revert with: =1024
#    ...or narrowly, granting the capability only to the Wine binaries:
sudo setcap 'cap_net_bind_service=+ep' \
  <prefix>/../wine-install/bin/wine <prefix>/../wine-install/bin/wine64 \
  <prefix>/../wine-install/bin/wine64-preloader <prefix>/../wine-install/bin/wineserver
```

## Verification
- `python3 -c "import socket;s=socket.socket();s.bind(('127.0.0.1',427))"` must stop raising
  `Permission denied`.
- `%LOCALAPPDATA%\ETC\EosFamily\v3\NetworkFeedback.log` must stop printing
  `SLPReg() failed with result -19`.
- `OnyxConsole.log`'s `recovered from hang after N s` should fall from ~48 s toward Windows' ~10 s, and
  `CreateComponent` should return `80000000` instead of `ffffffff`.
- `slptool findsrvtypes` in the prefix should report `service:acn.esta` (as it does on Windows).

## What this does *not* block
Without any of it the app **still reaches the editor** — `Eos : 1` (1600x1000) appears and the console
runs normally; the fix removes the ~40 s SLP-induced delay and matches Windows' component set.

## State on this host (2026-10-03)
Step 1 is **done** in `state/work/prefix` (`slpd` = STATE 4 RUNNING). Step 2 is **not applied** — this
account has no passwordless `sudo`; `net.ipv4.ip_unprivileged_port_start` is still 1024 and a plain
`bind(427)` still fails. That is the one manual, root-requiring step.
