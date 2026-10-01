#!/bin/bash
# Send a command to the guest-side polling service and print its output.
#   vmcmd.sh '<powershell>' [timeout]
#   vmcmd.sh -f <script.ps1> [timeout]     send a whole file as one (multi-line) command
set -u
SHARE=/home/asdf/projects/solidedge-wine-main/vmshare
exec 9>/tmp/vmcmd.lock
flock 9
CMD=$1
if [ "${1:-}" = "-f" ]; then CMD=$(cat "$2"); shift; fi
rm -f $SHARE/guest_cmd_out.txt
printf '%s\n' "$CMD" > $SHARE/cmd.txt
T=${2:-90}
for _ in $(seq 1 "$T"); do
  if [ -f $SHARE/guest_cmd_out.txt ]; then
    sleep 0.3; cat $SHARE/guest_cmd_out.txt; exit 0
  fi
  sleep 1
done
echo "TIMEOUT: no guest_cmd_out.txt after ${T}s"
exit 1
