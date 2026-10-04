#!/bin/bash
# Move artifacts the guest PUT into vmshare/ to their home in logs/vm/ or evidence/.
#   tools/vm/pull_artifacts.sh
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SHARE=${VM_SHARE:-$ROOT/vmshare}
mkdir -p "$ROOT/logs/vm" "$ROOT/evidence"
shopt -s nullglob
for f in "$SHARE"/vm_*.log "$SHARE"/vm_*.txt; do
  b=$(basename "$f")
  mv -f "$f" "$ROOT/logs/vm/$b"
  echo "logs/vm/$b  ($(stat -c%s "$ROOT/logs/vm/$b") bytes)"
done
for f in "$SHARE"/vm_*.png "$SHARE"/vm_*.ppm; do
  b=$(basename "$f")
  mv -f "$f" "$ROOT/evidence/$b"
  echo "evidence/$b  ($(stat -c%s "$ROOT/evidence/$b") bytes)"
done
