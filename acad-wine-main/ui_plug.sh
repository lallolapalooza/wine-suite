#!/bin/bash
# Run acad.exe with the plugin registered; sample UI + optionally type commands at set times.
# usage: ui_plug.sh <tag> [dwg] [secs] [interval] [typed-command@T ...]
# Set WINEPREFIX to run from a prefix other than the reference one (e.g. a fresh install).
set -u
TAG="${1:-plug}"; DWG="${2:-}"; SECS="${3:-240}"; IV="${4:-10}"; shift 4 2>/dev/null || true
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
D="$ROOT/logs/ui/$TAG"; rm -rf "$D"; mkdir -p "$D"
export WINEPREFIX=${WINEPREFIX:-$ROOT/prefix}
export DISPLAY=${DISP:-:2}   # VNC/Xvfb display: no portal approval needed
# XAUTHORITY only matters when the display is a real session's Xwayland (uid-specific
# cookie name); an Xvfb/Xtigervnc display needs none.  Keep a caller-provided value.
if [ -z "${XAUTHORITY:-}" ]; then
  XAUTH=$(ls -t /run/user/"$(id -u)"/.mutter-Xwaylandauth.* 2>/dev/null | head -1)
  [ -n "$XAUTH" ] && export XAUTHORITY=$XAUTH
fi
export PATH=$ROOT/wine-install/bin:$PATH
export WINEDLLOVERRIDES="mshtml="
rm -f "$WINEPREFIX/drive_c/acadplugin.log"

# Preflight: fail with the reason instead of sampling an empty screen for SECS seconds.
# It runs before the log redirect below so its messages reach the terminal, not just the
# evidence file.
if [ ! -x "$ROOT/wine-install/bin/wine" ]; then
  echo "no patched Wine build at $ROOT/wine-install/bin/wine — run tools/build_wine.sh first" >&2; exit 1
fi
if ! command -v xdpyinfo >/dev/null 2>&1 || ! xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
  echo "no X display on $DISPLAY — start one (Xvfb $DISPLAY -screen 0 1920x1080x24 &) or set DISP" >&2; exit 1
fi
if [ ! -d "$WINEPREFIX/drive_c/Program Files/Autodesk/AutoCAD 2027" ]; then
  echo "AutoCAD is not installed in $WINEPREFIX — install it with tools/install_fresh_prefix.sh" >&2; exit 1
fi
for t in xwininfo xdotool import; do
  command -v "$t" >/dev/null 2>&1 || { echo "missing $t (needed to sample the UI) — see SETUP.md" >&2; exit 1; }
done

# From here on everything (the run's own output too) goes to the evidence file.  The
# preflight above deliberately runs before this redirect, so its errors reach the terminal.
exec > "$D/out.txt" 2>&1
echo "start $(date +%T) tag=$TAG prefix=$WINEPREFIX dwg='$DWG' secs=$SECS xauth=${XAUTHORITY:-none} typed='$*'"

# Kill only acad.exe processes that belong to *this* prefix, so a run from another prefix
# (a fresh install under test) is not disturbed.
for p in $(pgrep -x acad.exe 2>/dev/null); do
  grep -qa "WINEPREFIX=$WINEPREFIX" /proc/$p/environ 2>/dev/null && kill -9 "$p" 2>/dev/null
done
sleep 2
LOG="$ROOT/log_$TAG.txt"; rm -f "$LOG"
cd "$WINEPREFIX/drive_c/Program Files/Autodesk/AutoCAD 2027" || exit 1
setsid nohup env WINEPREFIX="$WINEPREFIX" DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" \
  WINEDLLOVERRIDES="mshtml=" WINEDEBUG="${WDBG:--all}" \
  timeout $((SECS + 90)) "$ROOT/wine-install/bin/wine" acad.exe ${DWG:+"$DWG"} \
  > "$LOG" 2>&1 </dev/null &

for i in $(seq 1 "$((SECS / IV))"); do
  sleep "$IV"
  T=$((i * IV))
  TREE=$(xwininfo -root -tree 2>/dev/null)
  A=$(printf '%s\n' "$TREE" | grep -a -c 'Assertion Failed')
  P=$(ps -ef | grep -c '[a]cad\.exe')
  W=$(printf '%s\n' "$TREE" | grep -a '"Autodesk AutoCAD' | head -1 | awk '{print $1}')
  echo "t=${T}s alive=$P asserts=$A win=${W:-none}"
  [ -n "${W:-}" ] && import -window "$W" "$D/win_${T}s.png" 2>/dev/null
  # real screen (import cannot see the D3D-rendered WPF surface)
  import -window root "$D/screen_${T}s.png" 2>/dev/null   # VNC display: no portal
  for spec in "$@"; do
    CMD="${spec%@*}"; AT="${spec##*@}"
    if [ "$T" = "$AT" ] && [ -n "${W:-}" ]; then
      echo "  typing '$CMD' at t=${T}s -> win=$W"
      xdotool windowactivate --sync "$W" 2>/dev/null; sleep 1
      xdotool type --delay 80 "$CMD"; sleep 1; xdotool key Return; sleep 4
      import -window "$W" "$D/after_${CMD}_${T}s.png" 2>/dev/null
      echo "  asserts_now=$(xwininfo -root -tree 2>/dev/null | grep -a -c 'Assertion Failed')"
    fi
  done
done

echo "=== windows ==="
xwininfo -root -tree 2>/dev/null | grep -a -E '"' | grep -aiE 'autodesk|assertion|acad' | head
echo "=== plugin log ==="
cat "$WINEPREFIX/drive_c/acadplugin.log" 2>/dev/null | tail -60
echo "end $(date +%T)"
