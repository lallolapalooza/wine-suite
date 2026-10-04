#!/bin/bash
# Continuous guest frame sampler (read-only virsh screenshots with host timestamps).
# usage: vm_sample.sh <dir> <count> <interval_seconds> [prefix]
set -u
DIR=$1; N=$2; IV=$3; PFX=${4:-frame}
mkdir -p "$DIR"
IDX="$DIR/index_${PFX}.txt"
: > "$IDX"
T0=$(date +%s.%N)
echo "# host_epoch_start $T0  # columns: frame hostclock offset_since_start bytes" >> "$IDX"
for i in $(seq 1 "$N"); do
  F=$(printf '%s/%s_%04d.png' "$DIR" "$PFX" "$i")
  TS=$(date +%s.%N)
  virsh screenshot win11 --file "$F" >/dev/null 2>&1
  REL=$(awk -v a="$TS" -v b="$T0" 'BEGIN{printf "%.3f", a-b}')
  printf '%s %s %s %s\n' "$i" "$(date -d @"$TS" '+%H:%M:%S')" "$REL" "$(stat -c %s "$F" 2>/dev/null || echo 0)" >> "$IDX"
  sleep "$IV"
done
echo "sampled $N frames into $DIR (index $IDX)"
