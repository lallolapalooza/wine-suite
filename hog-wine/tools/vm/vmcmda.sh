#!/bin/bash
# Send a command to the ELEVATED guest loop (vmshare/vm_admin.ps1) and print its output.
#   tools/vm/vmcmda.sh '<powershell>' [timeout]
#   tools/vm/vmcmda.sh -f <script.ps1> [timeout]
set -u
SHARE=${VM_SHARE:-/home/asdf/projects/mastercam-wine/vmshare}
exec 9>/tmp/vmcmda.lock
flock 9
CMD=$1
if [ "${1:-}" = "-f" ]; then CMD=$(cat "$2"); shift; fi
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
