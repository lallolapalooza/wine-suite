#!/bin/bash
set -u
CCWS=${CCWS:-/home/asdf/projects/capcut-wine}
SHARE="$CCWS/vmshare"
CMD="$*"
[ -z "$CMD" ] && CMD=$(cat)
OUT="$SHARE/guest_cmd_out3.txt"
rm -f "$OUT"
printf '%s' "$CMD" > "$SHARE/cmd3.txt"
for i in $(seq 1 900); do
  if [ -f "$OUT" ]; then
    s1=$(stat -c %s "$OUT" 2>/dev/null || echo 0); sleep 0.4
    s2=$(stat -c %s "$OUT" 2>/dev/null || echo 0)
    [ "$s1" = "$s2" ] && { cat "$OUT"; exit 0; }
  fi
  sleep 1
done
echo "TIMEOUT (channel 3)" >&2
exit 1
