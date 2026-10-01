#!/bin/bash
# =============================================================================
# tools/run_revit.sh — launch Revit from a prefix and sample its UI
#
# usage: tools/run_revit.sh <tag> [secs] [interval] [typed-command@T ...]
#
# Set WINEPREFIX to run from a prefix other than $REVIT_PREFIX.
#
# Samples every <interval> seconds: the window tree (is Revit's main window up? are there
# ".NET Assertion Failed" / exception dialogs?), the process count, a window capture and a
# root-window capture.  Evidence: $REVIT_LOGS/ui/<tag>/{out.txt,win_*s.png,screen_*s.png}
# and $REVIT_LOGS/log_<tag>.txt (the run's own stderr/stdout).
# =============================================================================
set -u
TAG="${1:-revit}"; SECS="${2:-240}"; IV="${3:-10}"; shift 3 2>/dev/null || true
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$ROOT/env.sh" >/dev/null 2>&1
export WINEPREFIX=${WINEPREFIX:-$REVIT_PREFIX}
export DISPLAY=${DISP:-:2}
D="$REVIT_LOGS/ui/$TAG"; rm -rf "$D"; mkdir -p "$D"
export PATH="$WINEPREFIX_INSTALL/bin:$PATH"
export WINEDLLOVERRIDES="${REVIT_DLLOVERRIDES:-mshtml=}"

fail() { printf '%s\n' "$*" >&2; exit 1; }
[ -x "$WINEPREFIX_INSTALL/bin/wine" ] || fail "no patched Wine build at $WINEPREFIX_INSTALL/bin/wine — run tools/build_wine.sh first"
command -v xdpyinfo >/dev/null 2>&1 && xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 \
  || fail "no X display on $DISPLAY — start one (Xvfb $DISPLAY -screen 0 1920x1080x24 &) or set DISP"
[ -d "$WINEPREFIX/drive_c/Program Files/Autodesk/Revit 2027" ] \
  || fail "Revit is not installed in $WINEPREFIX — install it with tools/install_revit_prefix.sh"
for t in xwininfo import; do command -v "$t" >/dev/null 2>&1 || fail "missing $t (needed to sample the UI)"; done

exec > "$D/out.txt" 2>&1
echo "start $(date +%T) tag=$TAG prefix=$WINEPREFIX secs=$SECS typed='$*'"

# only touch Revit processes of *this* prefix
for p in $(pgrep -x Revit.exe 2>/dev/null); do
  grep -qa "WINEPREFIX=$WINEPREFIX" /proc/"$p"/environ 2>/dev/null && kill -9 "$p" 2>/dev/null
done
sleep 2
LOG="$REVIT_LOGS/log_$TAG.txt"; rm -f "$LOG"
cd "$WINEPREFIX/drive_c/Program Files/Autodesk/Revit 2027" || exit 1
setsid nohup env WINEPREFIX="$WINEPREFIX" DISPLAY="$DISPLAY" \
  WINEDLLOVERRIDES="$WINEDLLOVERRIDES" WINEDEBUG="${WDBG:--all}" \
  timeout $((SECS + 120)) "$WINEPREFIX_INSTALL/bin/wine" Revit.exe > "$LOG" 2>&1 </dev/null &

for i in $(seq 1 "$((SECS / IV))"); do
  sleep "$IV"
  T=$((i * IV))
  TREE=$(xwininfo -root -tree 2>/dev/null)
  A=$(printf '%s\n' "$TREE" | grep -a -ciE 'Assertion Failed|\.NET|unhandled exception')
  P=$(pgrep -c -x Revit.exe 2>/dev/null || echo 0)
  W=$(printf '%s\n' "$TREE" | grep -a -i '"Autodesk Revit' | head -1 | awk '{print $1}')
  echo "t=${T}s alive=$P assertlines=$A win=${W:-none}"
  [ -n "${W:-}" ] && import -window "$W" "$D/win_${T}s.png" 2>/dev/null
  import -window root "$D/screen_${T}s.png" 2>/dev/null
  for spec in "$@"; do
    CMD="${spec%@*}"; AT="${spec##*@}"
    if [ "$T" = "$AT" ] && [ -n "${W:-}" ]; then
      echo "  typing '$CMD' at t=${T}s -> win=$W"
      xdotool windowactivate --sync "$W" 2>/dev/null; sleep 1
      xdotool type --delay 80 "$CMD"; sleep 1; xdotool key Return; sleep 4
    fi
  done
done

echo "=== windows ==="
xwininfo -root -tree 2>/dev/null | grep -a -iE 'revit|assertion|autodesk' | head -20
echo "end $(date +%T)"
