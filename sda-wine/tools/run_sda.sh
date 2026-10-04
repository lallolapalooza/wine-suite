#!/bin/bash
# Launch Steinberg Download Assistant under the locally built Wine on the project display,
# then harvest both Wine's stderr and the application's own JavaFX/Spring log.
#
#   tools/run_sda.sh [tag] [seconds] [extra args to the launcher...]
#
# Env knobs:
#   SD_PREFIX   prefix (default state/prefix)
#   DISP        X display (default :22)
#   WINEDEBUG   default "+err+all,-fixme-all"
#   OVERRIDES   WINEDLLOVERRIDES, e.g. "packager=n"
#   _JAVA_OPTIONS  passed straight through, e.g. "-Dprism.order=sw -Dprism.verbose=true"
set -uo pipefail
SD=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TAG=${1:-run}; SECS=${2:-60}; shift 2 2>/dev/null || true

WINEPREFIX=${SD_PREFIX:-$SD/state/prefix}
export WINEPREFIX
export WINEARCH=${WINEARCH:-win64}
export DISPLAY=${DISP:-:22}
export TMPDIR=$SD/state/tmp
export WINEDEBUG=${WINEDEBUG:-+err+all,-fixme-all}
[ -n "${OVERRIDES:-}" ] && export WINEDLLOVERRIDES="$OVERRIDES"

WINE=$SD/wine-install/bin/wine
APPDIR="$WINEPREFIX/drive_c/Program Files (x86)/Steinberg/Download Assistant"
EXE='C:\Program Files (x86)\Steinberg\Download Assistant\Steinberg Download Assistant.exe'
LOGDIR=$SD/logs
mkdir -p "$LOGDIR" "$SD/evidence"
WLOG=$LOGDIR/sda_$TAG.wine.log
JLOG=$LOGDIR/sda_$TAG.app.log

[ -x "$WINE" ] || { echo "no wine at $WINE"; exit 1; }

echo "== run_sda tag=$TAG secs=$SECS display=$DISPLAY overrides=${WINEDLLOVERRIDES:-none} java_opts=${_JAVA_OPTIONS:-none}"

# clean slate: kill leftovers and record the app log position
"$SD/wine-install/bin/wineserver" -k 2>/dev/null
sleep 1
JLOGDIR=$(ls -d "$WINEPREFIX"/drive_c/users/*/AppData/Local/'Steinberg Download Assistant'/logs 2>/dev/null | head -1)

( cd "$APPDIR" && exec "$WINE" "$EXE" "$@" ) >"$WLOG" 2>&1 &
WPID=$!

for i in $(seq 1 "$SECS"); do
  sleep 1
  if ! kill -0 "$WPID" 2>/dev/null; then echo "== launcher process exited after ${i}s"; break; fi
  [ $((i % 15)) -eq 0 ] && import -window root -display "$DISPLAY" "$SD/evidence/sda_${TAG}_t${i}.png" 2>/dev/null
done
import -window root -display "$DISPLAY" "$SD/evidence/sda_${TAG}_final.png" 2>/dev/null
echo "== X windows:"
DISPLAY=$DISPLAY wmctrl -l 2>/dev/null || echo "(no wmctrl/EWMH)"
echo "== processes:"
pgrep -a -f 'Steinberg Download|aria2c' | head

echo "== wine log: $WLOG ($(wc -l <"$WLOG") lines)"
grep -aE "err:|Unhandled exception|wine: |page fault|fixme:.*not implemented" "$WLOG" | sed 's/^[0-9a-f]*://' | sort | uniq -c | sort -rn | head -25

if [ -n "${JLOGDIR:-}" ]; then
  NEW=$(ls -t "$JLOGDIR" 2>/dev/null | head -1)
  if [ -n "$NEW" ]; then
    cp -f "$JLOGDIR/$NEW" "$JLOG"
    echo "== app log: $JLOG ($(wc -l <"$JLOG") lines) — tail:"
    tail -40 "$JLOG"
  fi
fi
