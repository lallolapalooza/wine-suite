#!/bin/bash
# Launch the CSP editor (or launcher) on the project display with logging.
#
#   tools/run_csp.sh [editor|launcher|installer|exe <path>] [extra wine args...]
#
# Logs: logs/csp_run.log (WINEDEBUG), logs/csp_stdout.log.
set -uo pipefail
CW=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$CW/env.sh"

WINE=$CW_INSTALL/bin/wine
[ -x "$WINE" ] || { echo "no wine at $WINE"; exit 1; }

export WINEPREFIX=$CW_PREFIX
export DISPLAY=$DISP
export WINEDEBUG=${WINEDEBUG:-err+all,fixme-all}
export WINEESYNC=1
export TMPDIR=$CW_TMP
# Never let the app's scratch land in a RAM-backed tmpfs.
mkdir -p "$CW_WORK"

CSPDIR="$WINEPREFIX/drive_c/Program Files/CELSYS/CLIP STUDIO 1.5"
MODE=${1:-editor}; shift || true

case "$MODE" in
  editor)    TARGET="$CSPDIR/CLIP STUDIO PAINT/CLIPStudioPaint.exe" ;;
  launcher)  TARGET="$CSPDIR/CLIPStudio.exe" ;;
  installer) TARGET="$CSP_SETUP" ;;
  exe)       TARGET=$1; shift ;;
  *)         TARGET=$MODE ;;
esac

echo "[run_csp] $TARGET  (prefix=$WINEPREFIX display=$DISPLAY)"
if [ ! -f "$TARGET" ] && [ "$MODE" != installer ]; then
  echo "[run_csp] target does not exist yet"; exit 1
fi

"$WINE" "$TARGET" "$@" >"$CW_LOGS/csp_stdout.log" 2>"$CW_LOGS/csp_run.log"
rc=$?
echo "[run_csp] exited rc=$rc"
exit $rc
