#!/bin/bash
# Run a PowerShell script file ELEVATED in the Windows guest, auto-accepting the UAC prompt.
#
# The guest user is in Administrators but runs with a UAC-filtered (medium-integrity) token, and
# the UAC consent dialog focuses "No" by default — so the prompt has to be answered with Alt+Y.
#
# usage: tools/vm/elev.sh <local-script.ps1> [--name guestname]
#   The script is published on the HTTP channel, pulled by the guest to
#   C:\Users\adsf\<name>.ps1, then launched with Start-Process -Verb RunAs.
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=../../env.sh
source "$ROOT/env.sh"

SRC=${1:?usage: elev.sh <local-script.ps1>}
NAME=${3:-$(basename "$SRC")}
[ "${2:-}" = "--name" ] && NAME="$3"
cp "$SRC" "$VM_SHARE/$NAME"
LOG="$ROOT/logs/elev_$(basename "$NAME" .ps1).log"

GUEST="C:\\Users\\adsf\\$NAME"
PS="\$ProgressPreference='SilentlyContinue'; curl.exe -s -o '$GUEST' http://$VM_HOST_IP:8000/$NAME; Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$GUEST'"

( "$ROOT/tools/vm/vmcmd.sh" "$PS" 120 > "$LOG" 2>&1 ) &
VMC=$!
# wait for the UAC prompt to appear, then answer Yes
sleep 4
for _ in 1 2 3; do
  if virsh screenshot "$VM_DOMAIN" /tmp/_elev.ppm >/dev/null 2>&1; then :; fi
  virsh send-key "$VM_DOMAIN" --holdtime 60 KEY_LEFTALT KEY_Y >/dev/null 2>&1
  sleep 1
done
wait "$VMC" 2>/dev/null
echo "== elev launch log ($LOG) =="
cat "$LOG"
