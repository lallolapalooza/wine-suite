#!/bin/bash
# Send a command to the guest-side polling service and print its output.
# Serialized with flock so concurrent callers cannot interleave cmd.txt/out.
# usage: vmcmd.sh '<powershell command>' [timeout_seconds]
set -u
cd /home/asdf/Downloads/powerbi-linux
exec 9>/tmp/vmcmd.lock
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
