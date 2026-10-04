#!/bin/bash
# Send a command to the ELEVATED guest poller (C:\seref\vm_admin.ps1) and print its output.
#   vmcmda.sh '<powershell>' [timeout]
#   vmcmda.sh -f <script.ps1> [timeout]
set -u
SHARE=${VM_SHARE:-/home/asdf/projects/csp-wine/vmshare}
exec 9>/tmp/csp_vmcmda.lock
flock 9
if [ "${1:-}" = "-f" ]; then CMD=$(cat "$2"); shift; else CMD=$1; fi
rm -f "$SHARE/admin_out.txt"
{ printf '# nonce %s\n' "$(date +%s.%N)"; printf '%s\n' "$CMD"; } > "$SHARE/cmd_admin.txt"
T=${2:-90}
for _ in $(seq 1 "$T"); do
  if [ -f "$SHARE/admin_out.txt" ]; then
    sleep 0.4; cat "$SHARE/admin_out.txt"; exit 0
  fi
  sleep 1
done
echo "TIMEOUT: no admin_out.txt after ${T}s"
exit 1
