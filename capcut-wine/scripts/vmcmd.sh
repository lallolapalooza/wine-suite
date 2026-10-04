#!/bin/bash
# Send a PowerShell/cmd command to the win11 guest and print its output.
# usage: vmcmd.sh "command"   (or: echo "cmd" | vmcmd.sh)
# Requires vmserv.py running on host port 8000 with share=$CCWS/vmshare.
set -u
CCWS=${CCWS:-/home/asdf/projects/capcut-wine}
SHARE="$CCWS/vmshare"
CMD="$*"
[ -z "$CMD" ] && CMD=$(cat)
OUT="$SHARE/guest_cmd_out.txt"
rm -f "$OUT"
printf '%s' "$CMD" > "$SHARE/cmd.txt"
for i in $(seq 1 300); do          # up to 300s
  if [ -f "$OUT" ]; then
    # wait for the writer to settle (agent uploads after writing locally)
    s1=$(stat -c %s "$OUT" 2>/dev/null || echo 0); sleep 0.4
    s2=$(stat -c %s "$OUT" 2>/dev/null || echo 0)
    [ "$s1" = "$s2" ] && { cat "$OUT"; exit 0; }
  fi
  sleep 1
done
echo "TIMEOUT waiting for guest output" >&2
exit 1
