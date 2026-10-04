#!/bin/bash
# Send a command to the guest-side polling service (C:\seref\se_svc.ps1) and print its output.
#   vmcmd.sh '<powershell>' [timeout]
#   vmcmd.sh -f <script.ps1> [timeout]
set -u
SHARE=${VM_SHARE:-/home/asdf/projects/sda-wine/vmshare}
exec 9>/tmp/csp_vmcmd.lock
flock 9
if [ "${1:-}" = "-f" ]; then CMD=$(cat "$2"); shift; else CMD=$1; fi
rm -f "$SHARE/guest_cmd_out.txt"
{ printf '# nonce %s\n' "$(date +%s.%N)"; printf '%s\n' "$CMD"; } > "$SHARE/cmd.txt"
T=${2:-90}
for _ in $(seq 1 "$T"); do
  if [ -f "$SHARE/guest_cmd_out.txt" ]; then
    sleep 0.3; cat "$SHARE/guest_cmd_out.txt"; exit 0
  fi
  sleep 1
done
echo "TIMEOUT: no guest_cmd_out.txt after ${T}s"
exit 1
