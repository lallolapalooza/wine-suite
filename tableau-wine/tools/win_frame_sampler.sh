#!/bin/bash
# Sample the Windows guest's screen from the host (virsh screenshot) into PNGs.
#   tools/win_frame_sampler.sh <tag> <seconds> [interval]
# PITFALL (measured by the sibling projects): run only ONE virsh screenshot sampler at a time -
# three concurrent samplers made `virsh screenshot` hang past its timeout.
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TAG=${1:?usage: win_frame_sampler.sh <tag> <seconds> [interval]}
SECS=${2:-120}
IV=${3:-5}
OUT=$ROOT/logs/win-$TAG
mkdir -p "$OUT"
end=$(( $(date +%s) + SECS ))
n=0
while [ "$(date +%s)" -lt "$end" ]; do
    n=$((n + 1))
    f=$OUT/frame_$(printf '%03d' "$n").ppm
    if timeout 20 virsh screenshot win11 "$f" --screen 0 >/dev/null 2>&1 && [ -s "$f" ]; then
        convert "$f" "${f%.ppm}.png" 2>/dev/null && rm -f "$f"
    fi
    sleep "$IV"
done
echo "frames=$(ls "$OUT"/frame_*.png 2>/dev/null | wc -l) in $OUT"
