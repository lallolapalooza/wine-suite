#!/bin/bash
# Grab the Wine display: a root screenshot + the X window tree.
# usage: tools/host/shot.sh <out.png> [display]
set -u
OUT=${1:?usage: shot.sh <out.png> [display]}
DISP=${2:-:2}
export DISPLAY="$DISP"
import -window root "$OUT" 2>/dev/null || exit 1
xwininfo -root -tree | grep -a '"' | sed 's/^ *//' | head -40 > "${OUT%.png}.windows.txt"
echo "wrote $OUT (display $DISP)"
cat "${OUT%.png}.windows.txt"
