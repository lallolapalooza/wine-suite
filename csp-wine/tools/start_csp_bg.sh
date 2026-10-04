#!/bin/bash
# Start the CSP editor detached on the project display and return immediately.
#   tools/start_csp_bg.sh [editor|launcher]
# Logs under logs/csp_stdout.log and logs/csp_run.log.
set -u
CW=/home/asdf/projects/csp-wine
source "$CW/env.sh"

MODE=${1:-editor}
CSPDIR="$CW_PREFIX/drive_c/Program Files/CELSYS/CLIP STUDIO 1.5"
case "$MODE" in
  editor)   TARGET="$CSPDIR/CLIP STUDIO PAINT/CLIPStudioPaint.exe" ;;
  launcher) TARGET="$CSPDIR/CLIP STUDIO/CLIPStudio.exe" ;;
  *)        TARGET=$MODE ;;
esac
[ -f "$TARGET" ] || { echo "missing $TARGET"; exit 1; }

export WINEPREFIX=$CW_PREFIX
export DISPLAY=$DISP
export WINEESYNC=1
export TMPDIR=$CW_TMP
export WINEDEBUG=${WINEDEBUG:-err+all,fixme-all}

: > "$CW_LOGS/csp_stdout.log"
: > "$CW_LOGS/csp_run.log"
setsid nohup "$CW_INSTALL/bin/wine" "$TARGET" \
  > "$CW_LOGS/csp_stdout.log" 2> "$CW_LOGS/csp_run.log" < /dev/null &
echo "started $TARGET pid=$!"
sleep 3
pgrep -af CLIPStudio | head -3
