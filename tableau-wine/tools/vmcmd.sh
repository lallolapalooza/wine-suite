#!/bin/bash
# Send a command to the guest-side polling service and print its output.
# Adapted for the tableau-wine project from powerbi-linux/tools/vm/vmcmd.sh.
# The guest polls http://192.168.122.1:8000/cmd.txt (served by tools/vmserv.py) and writes
# guest_cmd_out.txt back through the same hub.
# usage: vmcmd.sh '<powershell command>' [timeout_seconds]
set -u
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.."
exec 9>/tmp/tableau-vmcmd.lock
flock 9
rm -f vmshare/guest_cmd_out.txt
printf '%s\n' "$1" > vmshare/cmd.txt
T=${2:-90}
for _ in $(seq 1 "$T"); do
  if [ -f vmshare/guest_cmd_out.txt ]; then
    sleep 0.3
    cat vmshare/guest_cmd_out.txt
    exit 0
  fi
  sleep 1
done
echo "TIMEOUT: no guest_cmd_out.txt after ${T}s"
exit 1
