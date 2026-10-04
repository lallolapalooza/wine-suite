#!/bin/bash
# Run a local PowerShell script in the Windows guest, avoiding all shell-quoting problems.
# Uploads the script into the HTTP share and has the guest fetch+execute it.
#
#   tools/vmrun.sh <script.ps1> [timeout] [--admin]
set -u
SHARE=${VM_SHARE:-/home/asdf/projects/sda-wine/vmshare}
FILE=$1
T=90
ADMIN=0
for a in "${@:2}"; do
  [ "$a" = "--admin" ] && ADMIN=1 || T=$a
done
[ -f "$FILE" ] || { echo "no such script: $FILE"; exit 1; }
cp "$FILE" "$SHARE/run.ps1"
CMD='$c=(curl.exe -s --max-time 60 http://192.168.122.1:8000/run.ps1) -join "`n"; iex $c'
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ "$ADMIN" = 1 ]; then exec "$HERE/vmcmda.sh" "$CMD" "$T"; else exec "$HERE/vmcmd.sh" "$CMD" "$T"; fi
