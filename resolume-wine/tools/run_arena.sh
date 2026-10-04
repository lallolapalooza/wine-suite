#!/bin/bash
# Run Resolume Arena under the patched Wine on the VNC display, sampling windows + screenshots.
#
# usage: tools/run_arena.sh <tag> [--secs N] [--iv N] [--prefix DIR] [--wine PATH] [--debug SPEC]
#                            [--exe NAME] [--] [extra wine args]
#
# Writes logs/runs/<tag>/: out.txt, win_<t>s.png (Arena's own window), screen_<t>s.png (root),
# windows_<t>.txt (window tree) and the app's stderr at <tag>.stderr.
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$ROOT/env.sh"

TAG=""; SECS=180; IV=10; WDBG=${WDBG:-}; EXE="Arena.exe"; EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in
    --secs)   SECS="$2"; shift 2 ;;
    --iv)     IV="$2"; shift 2 ;;
    --prefix) RW_PREFIX="$2"; shift 2 ;;
    --wine)   WINEBUILD="$2"; shift 2 ;;
    --debug)  WDBG="$2"; shift 2 ;;
    --exe)    EXE="$2"; shift 2 ;;
    --)       shift; EXTRA=("$@"); break ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *)        TAG="$1"; shift ;;
  esac
done
[ -n "$TAG" ] || { sed -n '2,4p' "$0" >&2; exit 2; }

D="$RW_LOGS/runs/$TAG"; rm -rf "$D"; mkdir -p "$D"
if [ -n "$WDBG" ] && [ "${WDBG#*timestamp}" = "$WDBG" ]; then
  WDBG="+timestamp,$WDBG"
fi
export WINEPREFIX=$(readlink -f "$RW_PREFIX")
export DISPLAY="$DISP"
export WINEDLLOVERRIDES="${RW_DLLOVERRIDES:-mshtml=}"
if [ -n "$WDBG" ]; then export WINEDEBUG="$WDBG"; else unset WINEDEBUG; fi
export PATH="$(dirname "$WINEBUILD"):$PATH"
export TMPDIR="${TMPDIR:-$RW_TMP}"

APP_DIR="$WINEPREFIX/drive_c/Program Files/Resolume Arena"
fail() { echo "$*" >&2; exit 1; }
[ -x "$WINEBUILD" ] || fail "no wine at $WINEBUILD"
xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 || fail "no X display on $DISPLAY"
[ -f "$APP_DIR/$EXE" ] || fail "$EXE not installed in $WINEPREFIX ($APP_DIR)"

if ! wmctrl -m >/dev/null 2>&1; then
  ( openbox --sm-disable > "$D/openbox.log" 2>&1 & ) ; sleep 1.5
fi

exec > "$D/out.txt" 2>&1
echo "start $(date +%T) tag=$TAG prefix=$WINEPREFIX display=$DISPLAY secs=$SECS debug=$WDBG exe=$EXE extra='${EXTRA[*]:-}'"

for p in $(pgrep -f "$EXE" 2>/dev/null); do
  grep -qa "WINEPREFIX=$WINEPREFIX" /proc/$p/environ 2>/dev/null && kill -9 "$p" 2>/dev/null
done
sleep 2

cd "$APP_DIR" || exit 1
setsid nohup env WINEPREFIX="$WINEPREFIX" DISPLAY="$DISPLAY" \
  WINEDLLOVERRIDES="$WINEDLLOVERRIDES" WINEDEBUG="${WINEDEBUG:-}" TMPDIR="$TMPDIR" \
  timeout $((SECS + 120)) "$WINEBUILD" "./$EXE" "${EXTRA[@]:-}" \
  > "$D/$TAG.stderr" 2>&1 </dev/null &

for i in $(seq 1 $((SECS / IV))); do
  sleep "$IV"
  T=$((i * IV))
  xwininfo -root -tree > "$D/windows_${T}.txt" 2>/dev/null
  W=$(grep -a -iE '"(Resolume|Arena|Wire|JUCEWindow)' "$D/windows_${T}.txt" | head -1 | awk '{print $1}')
  P=$(pgrep -fc "$EXE" 2>/dev/null || echo 0)
  echo "t=${T}s alive=$P win=${W:-none}"
  [ -n "${W:-}" ] && import -window "$W" "$D/win_${T}s.png" 2>/dev/null
  import -window root "$D/screen_${T}s.png" 2>/dev/null
done

echo "=== windows ==="
xwininfo -root -tree 2>/dev/null | grep -a '"' | head -30
echo "=== stderr tail ==="
tail -80 "$D/$TAG.stderr"
echo "end $(date +%T)"
