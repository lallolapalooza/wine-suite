#!/bin/bash
# Launch Solid Edge detached (no timeout, no sampling loop) so a wizard or dialog can be driven
# step by step with tools/se_drive.sh.  Kills any Edge.exe of this prefix first.
#
# usage: tools/se_launch.sh [--prefix DIR] [--wine PATH] [--debug SPEC] [--softgl] [-- exe args]
#   --softgl   export LIBGL_ALWAYS_SOFTWARE=1 (needed on a display whose GLX present blocks; see
#              FINDINGS M10 — on the TigerVNC display hardware GL + swap interval 1 = ~1 fps)
#
# Logs: logs/runs/<tag>/ if TAG is given as the first positional arg, else logs/launch.log
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$ROOT/env.sh"

TAG=""; WDBG=${WDBG:--all}; EXTRA=(); SOFTGL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) SE_PREFIX="$2"; shift 2 ;;
    --wine)   WINEBUILD="$2"; shift 2 ;;
    --debug)  WDBG="$2"; shift 2 ;;
    --softgl) SOFTGL=1; shift ;;
    --)       shift; EXTRA=("$@"); break ;;
    -*) echo "unknown option $1" >&2; exit 2 ;;
    *) TAG="$1"; shift ;;
  esac
done
export WINEPREFIX=$(readlink -f "$SE_PREFIX")
export DISPLAY="$DISP"
export WINEDLLOVERRIDES="${SE_DLLOVERRIDES:-mshtml=}"
export WINEDEBUG="$WDBG"
[ "$SOFTGL" = 1 ] && export LIBGL_ALWAYS_SOFTWARE=1

D="$SE_LOGS/runs/${TAG:-launch}"; mkdir -p "$D"
SE_DIR="$WINEPREFIX/drive_c/Program Files/Siemens/Solid Edge 2026/Program"
[ -f "$SE_DIR/Edge.exe" ] || { echo "Solid Edge not installed in $WINEPREFIX" >&2; exit 1; }
if ! wmctrl -m >/dev/null 2>&1; then ( openbox --sm-disable > "$D/openbox.log" 2>&1 & ); sleep 1.5; fi

for p in $(pgrep -x Edge.exe 2>/dev/null) $(pgrep -x selicwiz.exe 2>/dev/null); do
  grep -qa "WINEPREFIX=$WINEPREFIX" /proc/$p/environ 2>/dev/null && kill -9 "$p" 2>/dev/null
done
sleep 1

cd "$SE_DIR" || exit 1
: > "$D/se.stderr"
setsid nohup env WINEPREFIX="$WINEPREFIX" DISPLAY="$DISPLAY" \
  WINEDLLOVERRIDES="$WINEDLLOVERRIDES" WINEDEBUG="$WINEDEBUG" \
  ${SOFTGL:+LIBGL_ALWAYS_SOFTWARE=1} \
  "$WINEBUILD" ./Edge.exe "${EXTRA[@]:-}" >> "$D/se.stderr" 2>&1 < /dev/null &
echo "launched Solid Edge: prefix=$WINEPREFIX display=$DISPLAY softgl=$SOFTGL log=$D/se.stderr"
sleep 5
"$ROOT/tools/host/ui.sh" "$DISPLAY" windows | grep -iE "solid|edge|selicwiz|licens" | head -10
