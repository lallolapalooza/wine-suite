#!/bin/bash
# Watch the guest console and answer a UAC consent prompt with Alt+Y as soon as it appears.
# The prompt is detected by OCR ("User Account Control" / "Do you want to allow"), which is far more
# reliable than guessing a delay.
#
# usage: tools/vm/uac_yes.sh [max_seconds]
set -u
DOMAIN=${VM_DOMAIN:-win11}
MAX=${1:-90}
DIR=${2:-/tmp/uacshots}
mkdir -p "$DIR"
i=0
while [ "$i" -lt "$MAX" ]; do
  i=$((i+1))
  f="$DIR/u$(printf '%03d' "$i").png"
  if virsh screenshot "$DOMAIN" /tmp/_uac.ppm >/dev/null 2>&1; then
    if command -v convert >/dev/null 2>&1; then convert /tmp/_uac.ppm "$f" 2>/dev/null || cp /tmp/_uac.ppm "$f"; else cp /tmp/_uac.ppm "$f"; fi
    txt=$(tesseract "$f" stdout --psm 6 2>/dev/null)
    if echo "$txt" | grep -qiE 'user account control|do you want to allow|Yes.*No|app wants to make changes'; then
      echo "[$i] UAC prompt detected; sending Alt+Y"
      virsh send-key "$DOMAIN" --holdtime 60 KEY_LEFTALT KEY_Y >/dev/null 2>&1
      sleep 1.5
      virsh send-key "$DOMAIN" --holdtime 60 KEY_LEFTALT KEY_Y >/dev/null 2>&1
      echo "$txt" | head -20
      exit 0
    fi
  fi
  sleep 1.5
done
echo "no UAC prompt seen in ${MAX} iterations"
exit 1
