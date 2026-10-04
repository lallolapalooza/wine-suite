{
  "file": "/home/asdf/projects/tableau-wine/recon/WINDOWS_METHOD.md",
  "api_logging_available": true,
  "api_logging_notes": "PROVEN on this guest: (A) differential native probes - a real PE built once with x86_64-w64-mingw32-gcc, run under Wine AND on the Windows guest via the channel, outputs diffed line by line (tools/winapi/roprobe.c, asimp.c, kprobe.c, ntlmprobe.c, msolapprobe.c, dataconvprobe.c, winenum.c, winzorder.c, dcompprobe.c, wvexstyle.c). Windows references stored as logs/roprobe_windows.txt, logs/msolap/winprobe_engine_ok.out, winprobe_sspi_ref.txt, kprobe_windows.out. (B) the app's own verbose trace (PBI_forceTracing=1 -> Traces/PBIDesktop.*.log) compared on both platforms. (C) targeted WINEDEBUG traces for the comparison side (+reg,+file,+module,+secur32,+rpc; bracketed +relay with @@GD-START/END). NOT used in the Power BI reference: ProcMon…
  "installer_transfer_method": "HTTP pull from the host hub: the installer is placed/symlinked into $P/vmshare and served by tools/vm/vmserv.py on port 8000; the guest fetches it from http://192.168.122.1:8000/<name> with curl.exe (this is what was actually used and verified - Power BI: '192.168.122.230 - GET /PBIDesktopSetup_x64.exe HTTP/1.1 200', INFRA.md:374-380; Tableau: installer symlinked into vmshare, hub 200 / 743,872,856 B, guest downloading to C:\\Users\\adsf\\TableauDesktop.exe, tableau STATE.md:102-103). An ISO CAN be hot-plugged into the empty USB CD slots sdc/sdd (sde = csp media ISO, STATE.md:33), but no attach/change-media command appears anywhere in the record, so ISO was NOT used for app media; prefer the proven HTTP pull.",
  "pitfalls": [
    "Port 8000 is single-instance: only one vmserv may serve the share (a second instance on 8001 failed) [INFRA.md:382-383].",
    "Guest firewall direction: host->guest TCP is CLOSED; only guest->host works, so the channel is guest-poll-initiated [tableau STATE.md:34].",
    "No QEMU guest agent exists on this VM - vmclick.py/vmkeys.py/vmwin.py (QMP input-send-event) are the only way to drive the console [INFRA.md:412].",
    "The poller dedupes on exact command text ($seen): a repeated command without a changed nonce is silently dropped and vmcmd.sh times out. Append a nonce like ; \"__n=$(date +%s%N)\" [tableau STATE.md:97-98; tools/vm/pbi_svc.ps1].",
    "Long-lived host processes must be started through the harness's hub service mode; plain nohup ... & dies when the calling command settles [tableau STATE.md:99-100].",
    "Windows Defender refuses a downloaded .ps1 (Mark-of-the-Web): 'Windows cannot access the specified device, path, or file'. Strip it with `type a.ps1 > b.ps1` before running, or run the loop inline [INFRA.md:406-409].",
    "{WIN}+r never reaches the shell - keystrokes land in the foreground app. Click the taskbar Search box with vmclick.py 450 780 --screen 1280x800, then type 'cmd' [INFRA.md:402-404].",
    "PowerShell 5.1 strips double quotes when building a native command line (mangles DAX/quoted args). Pass statements/arguments in a file instead [INFRA.md:895-897].",
    "The guest channel is single-threaded and serialised by flock - one agent at a time [tools/vm/vmcmd.sh; INFRA.md:894].",
    "Every vmcmd call foregrounds the poller console (Windows Terminal), which then appears in screenshots; run captures in-process and minimise every WindowsTerminal|cmd|powershell|conhost window first [WINDOWS_REFERENCE.md:238-249; WINDOWS_VIEW_REFERENCE.md:361-363].",
    "Run only ONE virsh-screenshot sampler at a time - three concurrent samplers made virsh screenshot hang past its timeout [WINDOWS_REFERENCE.md:250-253].",
    "The guest locks itself between sessions; wake and sign in as adsf (virsh screenshot to see it, then vmkeys.py) [WINDOWS_REFERENCE.md:227-229].",
    "No silent elevation: Start-Process -Verb RunAs raises a secure-desktop UAC consent prompt whose default button is No; keyboard Enter cancels. Click Yes; on the 1280x800 guest Yes is centred at (540,557), No at (745,557) [WINDOWS_REFERENCE.md:23,74-78].",
    "A Burn/WiX bootstrapper exits 0 even when its MSI payload failed - verify by product presence, not the exit code [WINDOWS_REFERENCE.md:52-59].",
    "Guest clock skews relative to the host; correlate timestamps by offset [FINDINGS M8; WINDOWS_REFERENCE.md:275].",
    "The copies in $P are stale: tools/vm/vmcmd.sh hardcodes 'cd /home/asdf/Downloads/powerbi-linux' (a path that no longer exists) and pbi_svc.ps1 hardcodes C:\\pbiref - fix the cd line or use the inline client [tools/vm/vmcmd.sh:7].",
    "vmserv.py's default share is <repo>/vmshare (3x dirname of the script); pass the share explicitly [tools/vm/vmserv.py:12-15].",
    "virsh screenshot is the only guest access free to non-owning slices; coordinate ownership of the VM [INFRA §6].",
    "Windows Defender scanning makes cold start highly variable (3.5 s to 29 s to splash); do not treat a 25-30 s wait as a failure [WINDOWS_REFERENCE_SPEC.md §4]."
  ],
  "method_md": "# WINDOWS_METHOD — driving the `win11` guest and capturing Windows-side reference behaviour\n\nScope: `$P=/home/asdf/projects/tableau-wine`. The prior Power BI checkout whose docs are cited lives at `/home/asdf/projects/powerbi-linux`; those docs use `$ROOT=/home/asdf/Downloads/powerbi-linux`, which no longer exists — adjust paths. Every command below was run on this machine by one of the two projects unless marked `[INFERENCE]`.\n\n---\n\n## 0. Fixed facts\n\n| thing | value | source |\n|---|---|---|\n| Domain | `win11`, 4 vCPU / 8 GiB, UEFI+secure boot, TPM, host-passthrough | `$P/STATE.md:30-31` |\n| Disk | `sda`=/var/lib/libvirt/images/win11.qcow2 (grows on `/`) | `$P/STATE.md:32` |\n| CD-ROM | `sdc`/`sdd` empty hot-pluggable USB CD slots…
}

[Some lines truncated to 768 chars]