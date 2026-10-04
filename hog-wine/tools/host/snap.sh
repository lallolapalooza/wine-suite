#!/bin/bash
# Snapshot the Wine display: root screenshot, window tree, and an OCR of the screenshot.
# usage: tools/host/snap.sh <tag> [display]
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TAG=${1:?usage: snap.sh <tag> [display]}
DISP=${2:-:2}
D="$ROOT/evidence/snap"; mkdir -p "$D"
export DISPLAY="$DISP"
import -window root "$D/$TAG.png" 2>/dev/null || { echo "capture failed on $DISP"; exit 1; }
xwininfo -root -tree > "$D/$TAG.windows.txt" 2>/dev/null
echo "=== $TAG windows ==="
grep -a '"' "$D/$TAG.windows.txt" | sed 's/^ *//' | head -40
echo "=== $TAG ocr ==="
tesseract "$D/$TAG.png" stdout 2>/dev/null | grep -v '^$' | head -40
