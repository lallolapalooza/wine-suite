#!/bin/bash
# Launch Power BI Desktop under Wine on a headless display, with the sampling harness around it.
#
#   tools/run_pbi.sh [tag] [seconds] [document]   # default: tag=pbi seconds=180 document=none (start page)
#
# Environment knobs:
#   WINEDLLOVERRIDES   default "mshtml="  (Wine's builtin mshtml is a poor Trident stand-in; the prior
#                                          AutoCAD project disabled it at every launch — see FINDINGS M3)
#   PBIPREFIX          prefix name under prefix/  (default pbi)
#   WINEDEBUG          default unset (= no debug output); "-all" for silence, "+all" etc. for traces
#
# Everything lands in logs/<tag>/ (run.log, windows_*.txt, shot_*.png, *.stat.txt, exit).
set -o pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TAG=${1:-pbi}
SECS=${2:-180}
DOC=${3:-}
source "$ROOT/tools/pbi_env.sh" "${PBIPREFIX:-pbi}"
export WINEDLLOVERRIDES=${WINEDLLOVERRIDES:-"mshtml="}
EXE='C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe'
LAUNCH="'$WINE' '$EXE'"
[ -n "$DOC" ] && LAUNCH="$LAUNCH '$DOC'"

echo "prefix=$WINEPREFIX wine=$WINE display=$DISPLAY overrides=$WINEDLLOVERRIDES"

# Keep the report page on screen. Power BI keeps the report view selected for the whole run, but Wine has no
# compositor: a secondary view's window can paint over the covering page once during the app's startup and then
# never repaint, and the static covering page produces no damage so it never repaints either (FINDINGS M67).
# The shim re-asserts the selected view's repaint every 5 s and stops by itself when no PBIDesktop.exe is left.
# Measured from start with this wired in: 126 of 172 frames are the report page (107 402 B), frames 14..170 (M68).
install -d "$ROOT/logs/$TAG"
bash "$ROOT/tools/pbi_occl_report_shim.sh" "${PBIPREFIX:-pbi}" 0 reportView > "$ROOT/logs/$TAG/shim.log" 2>&1 &

exec bash "$ROOT/tools/watch_run.sh" --tag "$TAG" --interval 5 --timeout "$SECS" --display "$DISPLAY" \
    -- "$LAUNCH"
