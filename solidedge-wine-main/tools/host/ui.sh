#!/bin/bash
# Drive the app on the VNC display: find its window, click, type, key, capture.
#
# usage: tools/host/ui.sh <display> <command> [args]
#   windows                     list top-level windows (id, geometry, title)
#   find <title-regex>          print the X id of the first visible window whose title matches
#   rect <window-id>            print "WxH+X+Y"
#   click <window-id> <x> <y>   activate the window, then click at window-relative x,y
#   click-root <x> <y>          click at display-relative x,y
#   key <window-id> <key>       send one key (xdotool key syntax, e.g. Return, alt+F4)
#   type <window-id> <text>     type text into the window
#   shot <window-id> <out.png>  capture the window (falls back to a root crop)
#   raise <window-id>           activate/raise
#
# Everything is window-relative for clicks so a moved window does not invalidate a script.
set -u
DISP=${1:?usage: ui.sh <display> <command> ...}; shift

case "${1:-}" in
  windows)
    xwininfo -display "$DISP" -root -tree 2>/dev/null | sed -n '/children:/,$p' |
      grep -E '^\s+0x' | sed 's/^ *//'
    ;;
  find)
    pat=${2:?title pattern}
    xwininfo -display "$DISP" -root -tree 2>/dev/null | grep -aE '^\s+0x' |
      grep -aiE "$pat" | head -1 | awk '{print $1}'
    ;;
  rect)
    w=${2:?window id}
    xwininfo -display "$DISP" -id "$w" 2>/dev/null |
      awk '/Absolute upper-left X/{x=$4} /Absolute upper-left Y/{y=$4} /Width:/{w=$2} /Height:/{h=$2} END{printf "%dx%d+%d+%d\n", w,h,x,y}'
    ;;
  geometry)
    w=${2:?window id}
    xwininfo -display "$DISP" -id "$w" 2>/dev/null |
      awk '/Width:/{w=$2} /Height:/{h=$2} END{printf "%dx%d\n", w,h}'
    ;;
  raise)
    w=${2:?window id}
    xdotool windowactivate --sync "$w" 2>/dev/null || xdotool windowraise "$w"
    ;;
  click)
    w=${2:?window id}; x=${3:?x}; y=${4:?y}
    read -r W H X Y < <(xwininfo -display "$DISP" -id "$w" 2>/dev/null |
      awk '/Absolute upper-left X/{x=$4} /Absolute upper-left Y/{y=$4} /Width:/{w=$2} /Height:/{h=$2} END{printf "%s %s %s %s\n", w,h,x,y}')
    [ -n "${W:-}" ] || { echo "no geometry for $w" >&2; exit 1; }
    xdotool windowactivate --sync "$w" 2>/dev/null || true
    sleep 0.3
    DISPLAY=$DISP xdotool mousemove --sync $((X + x)) $((Y + y)) click 1
    echo "clicked window $w at +$x+$y -> display $((X + x)),$((Y + y))  (window ${W}x${H} at $X,$Y)"
    ;;
  click-root)
    x=${2:?x}; y=${3:?y}
    DISPLAY=$DISP xdotool mousemove --sync "$x" "$y" click 1
    echo "clicked display $x,$y"
    ;;
  key)
    w=${2:?window id}; k=${3:?key}
    xdotool windowactivate --sync "$w" 2>/dev/null || true
    DISPLAY=$DISP xdotool key --window "$w" "$k" 2>/dev/null || DISPLAY=$DISP xdotool key "$k"
    echo "sent key $k to $w"
    ;;
  type)
    w=${2:?window id}; t=${3:?text}
    xdotool windowactivate --sync "$w" 2>/dev/null || true
    DISPLAY=$DISP xdotool type --window "$w" --delay 60 "$t"
    echo "typed into $w"
    ;;
  shot)
    w=${2:?window id}; out=${3:?output png}
    if ! import -display "$DISP" -window "$w" "$out" 2>/dev/null; then
      read -r W H X Y < <(xwininfo -display "$DISP" -id "$w" 2>/dev/null |
        awk '/Absolute upper-left X/{x=$4} /Absolute upper-left Y/{y=$4} /Width:/{w=$2} /Height:/{h=$2} END{printf "%s %s %s %s\n", w,h,x,y}')
      import -display "$DISP" -window root -crop "${W}x${H}+${X}+${Y}" +repage "$out"
    fi
    python3 - "$out" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]); g = im.convert("L"); h = g.histogram(); n = sum(h)
mean = sum(i*c for i, c in enumerate(h))/n
dark = sum(h[:24])/n
v = "BLANK" if len(h) and sum(1 for c in h if c) == 1 else ("BLACK" if mean < 12 and dark > .98 else ("DARK" if mean < 40 else "CONTENT"))
print(f"{sys.argv[1]} {im.size[0]}x{im.size[1]} mean={mean:.1f} dark={dark:.3f} verdict={v}")
PY
    ;;
  *)
    sed -n '2,20p' "$0"; exit 2
    ;;
esac
