#!/bin/bash
# Run CapCut's own "does Qt6 + D3D11 hardware rendering work here?" probe in isolation.
#
# The full app spawns:  VEDetector.exe -cmd_qt6render_dx_hw_support
# and that child is the piece we have seen spinning at ~95-99% CPU while the main app's windows
# stay unmapped. Run it alone to observe/debug it without the rest of the app.
#
# usage: probe_detector.sh [seconds] [extra wine args...]
set -u
CCWS=/home/asdf/projects/capcut-wine
S=${1:-90}
shift || true
export WINEPREFIX=${WINEPREFIX:-$CCWS/prefix}
export PATH=${WINELOADER_BIN:-$CCWS/wine-install/bin}:$PATH
export DISPLAY=${DISPLAY:-:10}
V="$WINEPREFIX/drive_c/users/asdf/AppData/Local/CapCut/Apps/9.5.0.4050"
OUT="$CCWS/logs/probe_detector"; mkdir -p "$OUT"

pgrep -f "cmd_qt6render_dx_hw_support" >/dev/null && { echo "probe already running"; exit 1; }

cd "$V" || exit 1
env WINEDEBUG=${WINEDEBUG:--all} wine VEDetector.exe -cmd_qt6render_dx_hw_support \
    > "$OUT/stdout.log" 2>&1 &
P=$!
echo "probe pid=$P display=$DISPLAY"
for i in $(seq 1 "$S"); do
  sleep 1
  kill -0 $P 2>/dev/null || { echo "probe exited after ${i}s"; break; }
  # cpu of the probe and any children
  cpu=$(ps -o pcpu= -p $P 2>/dev/null | tr -d ' ')
  printf 't=%03ds cpu=%s\n' "$i" "${cpu:-gone}" >> "$OUT/cpu.log"
done
if kill -0 $P 2>/dev/null; then
  echo "STILL RUNNING after ${S}s (blocked/spinning) -- leaving it up for inspection: pid $P"
  echo "$P" > "$OUT/pid"
else
  wait $P; echo "exit_code=$?"
fi
echo "--- stdout head ---"; head -30 "$OUT/stdout.log"
echo "--- cpu trace tail ---"; tail -12 "$OUT/cpu.log" 2>/dev/null
