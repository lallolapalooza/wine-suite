#!/bin/bash
# Run Mastercam under the patched Wine on the VNC display, sampling windows + screenshots.
#
# usage: tools/run_mastercam.sh <tag> [--secs N] [--iv N] [--prefix DIR] [--wine PATH]
#                               [--debug SPEC] [--exe NAME] [--] [extra wine args]
#
# Writes logs/runs/<tag>/: out.txt (progress), app.stderr (the app's own stderr, possibly huge),
# windows_<t>.txt (X window tree), screen_<t>.png (root capture), win_<t>.png (app window capture).
# The model has no vision: read windows_*.txt and OCR the PNGs (tesseract) rather than eyeballing.
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$ROOT/env.sh"

TAG=""; SECS=180; IV=10; WDBG=${WDBG:-}; EXE="MastercamLauncher.exe"; EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in
    --secs)   SECS="$2"; shift 2 ;;
    --iv)     IV="$2"; shift 2 ;;
    --prefix) MCW_PREFIX="$2"; shift 2 ;;
    --wine)   WINEBUILD="$2"; shift 2 ;;
    --debug)  WDBG="$2"; shift 2 ;;
    --exe)    EXE="$2"; shift 2 ;;
    --)       shift; EXTRA=("$@"); break ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *)        TAG="$1"; shift ;;
  esac
done
[ -n "$TAG" ] || { sed -n '2,3p' "$0" >&2; exit 2; }

D="$MCW_LOGS/runs/$TAG"; rm -rf "$D"; mkdir -p "$D"
if [ -n "$WDBG" ] && [ "${WDBG#*timestamp}" = "$WDBG" ]; then WDBG="+timestamp,$WDBG"; fi
export WINEPREFIX=$(readlink -f "$MCW_PREFIX")
export DISPLAY="$DISP"
export WINEDLLOVERRIDES="${MCW_DLLOVERRIDES:-}"
if [ -n "$WDBG" ]; then export WINEDEBUG="$WDBG"; else unset WINEDEBUG; fi
export PATH="$(dirname "$WINEBUILD"):$PATH"
export TMPDIR="${TMPDIR:-$MCW_TMP}"

APP_DIR="$WINEPREFIX/drive_c/Program Files/Mastercam 2027"
fail() { echo "$*" >&2; exit 1; }
[ -x "$WINEBUILD" ] || fail "no wine at $WINEBUILD"
xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 || fail "no X display on $DISPLAY"
[ -f "$APP_DIR/$EXE" ] || fail "$EXE not installed in $WINEPREFIX ($APP_DIR)"

if ! wmctrl -m >/dev/null 2>&1; then ( openbox --sm-disable > "$D/openbox.log" 2>&1 & ); sleep 1.5; fi

exec > "$D/out.txt" 2>&1
echo "start $(date +%T) tag=$TAG prefix=$WINEPREFIX display=$DISPLAY secs=$SECS debug=$WDBG exe=$EXE extra='${EXTRA[*]:-}'"

# Kill a previously started instance of $EXE in this prefix.  Skip this script itself
# (and its parent shell): our own command line contains "$EXE" and our environment has
# WINEPREFIX set, so the naive check makes this script SIGKILL itself.
for p in $(pgrep -f -- "$EXE" 2>/dev/null); do
  [ "$p" = "$$" ] && continue
  [ "$p" = "$PPID" ] && continue
  grep -qa "WINEPREFIX=$WINEPREFIX" "/proc/$p/environ" 2>/dev/null || continue
  grep -qa -e wine -e wineserver "/proc/$p/comm" 2>/dev/null || continue
  kill -9 "$p" 2>/dev/null
done
sleep 2

cd "$APP_DIR" || exit 1
setsid nohup env WINEPREFIX="$WINEPREFIX" DISPLAY="$DISPLAY" \
  WINEDLLOVERRIDES="$WINEDLLOVERRIDES" WINEDEBUG="${WINEDEBUG:-}" TMPDIR="$TMPDIR" \
  timeout $((SECS + 120)) "$WINEBUILD" "./$EXE" "${EXTRA[@]:-}" \
  > "$D/app.stderr" 2>&1 </dev/null &

for i in $(seq 1 $((SECS / IV))); do
  sleep "$IV"
  T=$((i * IV))
  xwininfo -root -tree > "$D/windows_${T}.txt" 2>/dev/null
  W=$(grep -a -iE '"(Mastercam|mcam|Mastercam Launcher)' "$D/windows_${T}.txt" | head -1 | awk '{print $1}')
  P=$(pgrep -fc "$EXE" 2>/dev/null || echo 0)
  echo "t=${T}s alive=$P win=${W:-none}"
  [ -n "${W:-}" ] && import -window "$W" "$D/win_${T}s.png" 2>/dev/null
  import -window root "$D/screen_${T}s.png" 2>/dev/null
done

echo "=== windows ==="
xwininfo -root -tree 2>/dev/null | grep -a '"' | head -40
echo "=== stderr tail ==="
tail -100 "$D/app.stderr"
echo "end $(date +%T)"
