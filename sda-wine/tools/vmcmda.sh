#!/bin/bash
# Send a command to the *elevated* guest-side poller (C:\seref\vm_admin.ps1) and print its output.
#   vmcmda.sh '<powershell>' [timeout]
set -u
SHARE=${VM_SHARE:-/home/asdf/projects/sda-wine/vmshare}
exec 9>/tmp/sda_vmcmda.lock
flock 9
CMD=$1
rm -f "$SHARE/admin_out.txt"
{ printf '# nonce %s\n' "$(date +%s.%N)"; printf '%s\n' "$CMD"; } > "$SHARE/cmd_admin.txt"
T=${2:-90}
for _ in $(seq 1 "$T"); do
  if [ -f "$SHARE/admin_out.txt" ]; then
    sleep 0.3; cat "$SHARE/admin_out.txt"; exit 0
  fi
  sleep 1
done
echo "TIMEOUT: no admin_out.txt after ${T}s (is vm_admin.ps1 running elevated in the guest?)"
exit 1
