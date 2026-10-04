#!/bin/bash
# Run Eos Family under the patched Wine on the VNC display, sampling windows + screenshots.
#
# usage: tools/run_eos.sh <tag> [--secs N] [--iv N] [--prefix DIR] [--wine PATH]
#                         [--debug SPEC] [--exe NAME] [--] [extra wine args]
#
# Writes logs/runs/<tag>/: out.txt (progress), app.stderr, windows_<t>.txt, screen_<t>.png,
# win_<t>.png.  The model has no vision: read windows_*.txt and OCR the PNGs (tesseract).
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$ROOT/env.sh"

TAG=""; SECS=180; IV=10; WDBG=${WDBG:-}; EXE="Eos.exe"; EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in
    --secs)   SECS="$2"; shift 2 ;;
    --iv)     IV="$2"; shift 2 ;;
    --prefix) EW_PREFIX="$2"; shift 2 ;;
    --wine)   WINEBUILD="$2"; shift 2 ;;
    --debug)  WDBG="$2"; shift 2 ;;
    --exe)    EXE="$2"; shift 2 ;;
    --)       shift; EXTRA=("$@"); break ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *)        TAG="$1"; shift ;;
  esac
done
[ -n "$TAG" ] || { sed -n '2,3p' "$0" >&2; exit 2; }

D="$EW_LOGS/runs/$TAG"; rm -rf "$D"; mkdir -p "$D"
if [ -n "$WDBG" ] && [ "${WDBG#*timestamp}" = "$WDBG" ]; then WDBG="+timestamp,$WDBG"; fi
export WINEPREFIX=$(readlink -f "$EW_PREFIX")
export DISPLAY="$DISP"
export WINEDLLOVERRIDES="${EW_DLLOVERRIDES:-}"
if [ -n "$WDBG" ]; then export WINEDEBUG="$WDBG"; else unset WINEDEBUG; fi
export PATH="$(dirname "$WINEBUILD"):$PATH"
export TMPDIR="${TMPDIR:-$EW_TMP}"

APP_DIR="$WINEPREFIX/drive_c/Program Files/ETC/EosFamily/v3/Eos"
fail() { echo "$*" >&2; exit 1; }
[ -x "$WINEBUILD" ] || fail "no wine at $WINEBUILD"
xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 || fail "no X display on $DISPLAY"
[ -f "$APP_DIR/$EXE" ] || fail "$EXE not installed in $WINEPREFIX ($APP_DIR)"

if ! wmctrl -m >/dev/null 2>&1; then ( openbox --sm-disable > "$D/openbox.log" 2>&1 & ); sleep 1.5; fi

exec > "$D/out.txt" 2>&1
echo "start $(date +%T) tag=$TAG prefix=$WINEPREFIX display=$DISPLAY secs=$SECS debug=$WDBG exe=$EXE extra='${EXTRA[*]:-}'"

# kill earlier instances of this app in this prefix (never our own wrapper)
for p in $(pgrep -f -- "$EXE" 2>/dev/null); do
  [ "$p" = "$$" ] && continue
  [ "$p" = "$PPID" ] && continue
  grep -qa -e wine -e wineserver "/proc/$p/comm" 2>/dev/null || continue
  grep -qa "WINEPREFIX=$WINEPREFIX" /proc/$p/environ 2>/dev/null && kill -9 "$p" 2>/dev/null
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
  W=$(grep -a '"Eos : ' "$D/windows_${T}.txt" | head -1 | awk '{print $1}')
  [ -n "$W" ] || W=$(grep -a -iE '"(Eos|ETC|Augment)' "$D/windows_${T}.txt" | grep -av -e '1x1' | head -1 | awk '{print $1}')
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
