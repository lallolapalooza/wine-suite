#!/bin/bash
# =============================================================================
# tools/se_drive.sh — scripted interaction with a running Solid Edge on a display
#
# usage: tools/se_drive.sh <window-id-or-title-part> <action-file> [--display :2] [--outdir DIR]
#
# The action file is one directive per line, '#' comments and blank lines ignored:
#
#   wait <seconds>              sleep
#   shot <name>                 capture the window (and a root grab) as <name>.png
#   click <x> <y>               click at window-relative x,y  (the window is activated first)
#   dblclick <x> <y>            double click
#   move <x> <y>                move the pointer only
#   key <key>                   xdotool key syntax, e.g. Return, Escape, alt+F4, ctrl+s
#   type <text>                 type text
#   note <text>                 echo a marker into the log (so a log line can be timed)
#
# Every step is echoed with a timestamp so its effect can be aligned with the WINEDEBUG stream
# afterwards — that alignment is how a click gets attributed to a log line.
#
# Logs: <outdir>/drive.log, plus one .png per `shot`.
# =============================================================================
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

WIN=${1:?usage: se_drive.sh <window-id-or-title> <action-file>}
ACTIONS=${2:?usage: se_drive.sh <window-id-or-title> <action-file>}
shift 2
DISP=${DISP:-:2}
OUTDIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --display) DISP="$2"; shift 2 ;;
    --outdir)  OUTDIR="$2"; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
[ -f "$ACTIONS" ] || { echo "no action file $ACTIONS" >&2; exit 2; }
OUTDIR=${OUTDIR:-$ROOT/logs/drive/$(basename "$ACTIONS" .txt)}
mkdir -p "$OUTDIR"
UI="$ROOT/tools/host/ui.sh"

resolve() {
  case "$1" in
    0x*) echo "$1" ;;
    *)   "$UI" "$DISP" find "$1" ;;
  esac
}

log() { printf '%s %s\n' "$(date +%H:%M:%S.%3N)" "$*" | tee -a "$OUTDIR/drive.log"; }

W=$(resolve "$WIN")
if [ -z "$W" ]; then
  log "window '$WIN' not found; windows are:"
  "$UI" "$DISP" windows | tee -a "$OUTDIR/drive.log"
  exit 1
fi
log "window $WIN -> $W  rect $("$UI" "$DISP" rect "$W")  display $DISP"
log "--- $(grep -c . "$ACTIONS") action lines"

n=0
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  # strip a trailing comment
  line=${line%%#*}
  set -- $line
  cmd=$1; shift
  n=$((n + 1))
  case "$cmd" in
    wait)     log "$n wait $*"; sleep "$1" ;;
    note)     log "NOTE $*" ;;
    shot)
      "$UI" "$DISP" shot "$W" "$OUTDIR/$1.png" | tee -a "$OUTDIR/drive.log"
      import -display "$DISP" -window root "$OUTDIR/root_$1.png" 2>/dev/null || true
      ;;
    click)    log "$n click $1 $2"; "$UI" "$DISP" click "$W" "$1" "$2" | tee -a "$OUTDIR/drive.log" ;;
    dblclick) log "$n dblclick $1 $2"; "$UI" "$DISP" click "$W" "$1" "$2" >/dev/null; sleep 0.1; "$UI" "$DISP" click "$W" "$1" "$2" | tee -a "$OUTDIR/drive.log" ;;
    move)     DISPLAY=$DISP xdotool mousemove "$1" "$2"; log "$n move $1 $2" ;;
    key)      log "$n key $1"; "$UI" "$DISP" key "$W" "$1" | tee -a "$OUTDIR/drive.log" ;;
    type)     log "$n type '$1'"; "$UI" "$DISP" type "$W" "$1" | tee -a "$OUTDIR/drive.log" ;;
    *)        log "UNKNOWN directive: $line" ;;
  esac
done < "$ACTIONS"
log "done"
