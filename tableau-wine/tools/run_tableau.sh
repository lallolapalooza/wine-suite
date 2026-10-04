#!/bin/bash
# Launch Tableau in the project Wine build on the VNC display and sample its windows/frames.
#
#   tools/run_tableau.sh <tag> <seconds> [extra wine args...]
#
# Env: WINE   (default $TABLEAU/wine-install/bin/wine)
#      PREFIX (default $TABLEAU/prefix/tableau)
#      DISP   (default :11)
#      EXE    (default C:\Program Files\Tableau\Tableau 2026.2\bin\tableau.exe)
#      WINEDEBUG (default: unset - set e.g. WINEDEBUG=+seh,+relay for API-level logs)
# Output: logs/run-<tag>/frame_<n>.png + windows_<n>.txt + run.log
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TAG=${1:?usage: run_tableau.sh <tag> <seconds>}
SECS=${2:-120}
WINE=${WINE:-$ROOT/wine-install/bin/wine}
PREFIX=${PREFIX:-$ROOT/prefix/tableau}
DISP=${DISP:-:11}
EXE=${EXE:-C:\\Program Files\\Tableau\\Tableau 2026.2\\bin\\tableau.exe}
OUT=$ROOT/logs/run-$TAG
mkdir -p "$OUT"

export DISPLAY=$DISP WINEPREFIX=$PREFIX
export WINEDEBUG=${WINEDEBUG:-}

: >"$OUT/run.log"
echo "wine=$WINE prefix=$PREFIX display=$DISP exe=$EXE secs=$SECS $(date -Is)" | tee -a "$OUT/run.log"

"$WINE" "$EXE" >>"$OUT/run.log" 2>&1 &
APP=$!
echo "app_pid=$APP" | tee -a "$OUT/run.log"

end=$(( $(date +%s) + SECS ))
n=0
while [ "$(date +%s)" -lt "$end" ]; do
    if ! kill -0 "$APP" 2>/dev/null; then
        echo "app exited early at $(date -Is)" | tee -a "$OUT/run.log"
        break
    fi
    n=$((n + 1))
    import -window root "$OUT/frame_$(printf '%03d' "$n").png" 2>/dev/null
    xwininfo -root -tree >"$OUT/windows_$(printf '%03d' "$n").txt" 2>&1
    sleep 4
done

echo "frames=$n alive=$(kill -0 "$APP" 2>/dev/null && echo yes || echo no)" | tee -a "$OUT/run.log"
# Leave the app running (inspection); kill it with: WINEPREFIX=$PREFIX wineserver -k
exit 0
