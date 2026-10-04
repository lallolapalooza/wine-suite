#!/bin/bash
# Film-strip the guest console: screenshot every <interval> s into <outdir>, skipping frames that
# are pixel-identical to the previous one.  Lets an unattended install be reconstructed afterwards
# (OCR each frame, keep the distinct ones as evidence).
#
# usage: tools/vm/capture.sh <outdir> [interval_s] [max_frames]
set -u
DOMAIN=${VM_DOMAIN:-win11}
OUT=${1:?usage: capture.sh <outdir> [interval] [max_frames]}
IV=${2:-5}
MAX=${3:-1000}
mkdir -p "$OUT"
prev=""
i=0
while [ "$i" -lt "$MAX" ]; do
  i=$((i+1))
  n=$(printf '%04d' "$i")
  tmp=/tmp/_cap.ppm
  if ! virsh screenshot "$DOMAIN" "$tmp" >/dev/null 2>&1; then
    echo "[$n] screenshot failed"; sleep "$IV"; continue
  fi
  md5=$(md5sum "$tmp" | awk '{print $1}')
  if [ "$md5" != "$prev" ]; then
    prev="$md5"
    if command -v convert >/dev/null 2>&1; then
      convert "$tmp" "$OUT/$n.png" 2>/dev/null || cp "$tmp" "$OUT/$n.png"
    else
      cp "$tmp" "$OUT/$n.png"
    fi
    printf '%s %s\n' "$(date +%H:%M:%S)" "$OUT/$n.png"
  fi
  sleep "$IV"
done
