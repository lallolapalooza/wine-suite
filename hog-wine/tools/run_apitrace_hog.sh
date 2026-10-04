#!/bin/bash
# Trace the Hog PC start-up under Wine with the 32-bit Windows-side IAT tracer
# (tools/apitrace, build32), then copy the logs to logs/api/.
#
# Hog is an i386 application, so the tracer must be the 32-bit build:
#   (cd tools/apitrace && CC=i686-w64-mingw32-gcc OUT=build32 ./build.sh)
# This script stages C:\apitrace32\{apitrace.exe,apihook.dll,hog.cfg} into the
# prefix, traces launcher-win32-golden.exe from its first instruction, attaches
# the tracer to the server/desktop/critical children as soon as they appear, and
# lands logs/api/<tag>{,_server,_desktop,_critical}.log.
#
# usage: tools/run_apitrace_hog.sh <tag> [--secs N] [--cfg F] [--prefix DIR] [--wine PATH]
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$ROOT/env.sh"

TAG=""; SECS=75; CFG='C:\apitrace32\hog.cfg'
while [ $# -gt 0 ]; do
  case "$1" in
    --secs)   SECS="$2"; shift 2 ;;
    --cfg)    CFG="$2"; shift 2 ;;
    --prefix) HW_PREFIX="$2"; shift 2 ;;
    --wine)   WINEBUILD="$2"; shift 2 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *)        TAG="$1"; shift ;;
  esac
done
[ -n "$TAG" ] || { sed -n '2,3p' "$0" >&2; exit 2; }

export WINEPREFIX=$(readlink -f "$HW_PREFIX")
export DISPLAY="$DISP"
export PATH="$(dirname "$WINEBUILD"):$PATH"
export TMPDIR="${TMPDIR:-$HW_TMP}"
APILINUX="$WINEPREFIX/drive_c/apitrace32"
APP_DIR="$WINEPREFIX/drive_c/Program Files (x86)/ETC/HogPC"
D="$HW_LOGS/api"; mkdir -p "$D"

mkdir -p "$APILINUX"
cp -f "$ROOT/tools/apitrace/build32/apitrace.exe" "$ROOT/tools/apitrace/build32/apihook.dll" "$APILINUX/"
cp -f "$ROOT/tools/apitrace/hog.cfg" "$APILINUX/hog.cfg"
[ -f "$APILINUX/apitrace.exe" ] && [ -f "$APILINUX/hog.cfg" ] || { echo "tracer/cfg missing" >&2; exit 1; }
[ -f "$APP_DIR/launcher-win32-golden.exe" ] || { echo "Hog not installed in $WINEPREFIX" >&2; exit 1; }

kill_hog() {
  for p in $(pgrep -f -- 'win32-golden' 2>/dev/null); do
    grep -qa "WINEPREFIX=$WINEPREFIX" /proc/$p/environ 2>/dev/null && kill -9 "$p" 2>/dev/null
  done
  sleep 2
}
kill_hog
rm -f "$APILINUX/${TAG}"*.log

echo "start $(date +%T) tag=$TAG secs=$SECS cfg=$CFG"
cd "$APP_DIR" || exit 1
"$WINEBUILD" 'C:\apitrace32\apitrace.exe' --cfg "$CFG" \
    --out "C:\\apitrace32\\${TAG}.log" --timeout "$SECS" -- ./launcher-win32-golden.exe \
    > "$D/${TAG}.stderr" 2>&1 &
TRACER=$!
# attach to the children the launcher spawns (show creation + UI) as they appear
declare -A done_ids
deadline=$((SECS - 4))
for i in $(seq 1 $((deadline * 4))); do
  kill -0 $TRACER 2>/dev/null || break
  for role in server desktop critical dp8k; do
    pid=$(pgrep -f -- "${role}-win32-golden" 2>/dev/null | while read -r q; do
            grep -qa "WINEPREFIX=$WINEPREFIX" /proc/$q/environ 2>/dev/null && echo "$q"; done | head -1)
    [ -n "$pid" ] || continue
    [ -n "${done_ids[$pid]:-}" ] && continue
    done_ids[$pid]=1
    "$WINEBUILD" 'C:\apitrace32\apitrace.exe' --pid "$pid" --cfg "$CFG" \
        --out "C:\\apitrace32\\${TAG}_${role}.log" > "$D/${TAG}_${role}.stderr" 2>&1 &
    echo "attached $role pid=$pid"
  done
  sleep 0.25
done
wait $TRACER 2>/dev/null
kill_hog
for f in "$APILINUX/${TAG}"*.log; do
  [ -f "$f" ] || continue
  cp -f "$f" "$D/$(basename "$f")"
  echo "logs/api/$(basename "$f")  $(grep -cv '^#' "$f") calls"
done
echo "end $(date +%T)"
