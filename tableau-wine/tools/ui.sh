#!/bin/bash
# Minimal UI driver for the project VNC display (Xvfb/Xtigervnc :11).
#   tools/ui.sh list              - window tree (id, geometry, title)
#   tools/ui.sh shot <file>       - screenshot the root window
#   tools/ui.sh click <x> <y>     - move+click button 1
#   tools/ui.sh key <keysym>      - send a key (xdotool key syntax)
#   tools/ui.sh type <text>       - type text
#   tools/ui.sh active            - name of the active window
set -u
D=${DISP:-:11}
export DISPLAY=$D
cmd=${1:?usage: ui.sh <list|shot|click|key|type|active> [args]}
shift
case "$cmd" in
  list)   xwininfo -root -tree ;;
  shot)   import -window root "${1:?file}" && identify "${1}";;
  click)  xdotool mousemove "${1:?x}" "${2:?y}" click 1;;
  key)    xdotool key "$1";;
  type)   xdotool type --delay 60 "$1";;
  active) xdotool getactivewindow getwindowname 2>/dev/null || xdotool getwindowfocus getwindowname;;
  *) echo "unknown: $cmd" >&2; exit 2;;
esac
