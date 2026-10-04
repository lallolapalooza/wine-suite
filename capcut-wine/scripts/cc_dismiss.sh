#!/bin/bash
# cc_dismiss.sh -- find an input method that actually presses CapCut's first-run button.
#
# usage: cc_dismiss.sh [display] [total_seconds]
#   display default :10, total default 180
#
# Every 2 s it screenshots the display.  While a CapCut accent-coloured button is
# visible it tries, one method per attempt, in escalating order:
#   1 XTEST click at the button centre
#   2 activate the CapCut window, then Return
#   3 press-and-hold click (300 ms between press and release)
#   4 Tab, then Return
#   5 XTEST click with --sync and --clearmodifiers after an explicit pointer warp
# After each attempt it re-screenshots and reports whether the button disappeared,
# so the log says which primitive the app actually accepts.  Screenshots are kept in
# recon/dismiss/ so the report can point at them.
set -u
CCWS=/home/asdf/projects/capcut-wine
D=${1:-:10}
TOTAL=${2:-180}
export DISPLAY=$D
OUT="$CCWS/recon/dismiss"; mkdir -p "$OUT"
LOG="$CCWS/logs/cc_dismiss.$RANDOM.log"
: > "$LOG"
echo "cc_dismiss display=$D total=${TOTAL}s log=$LOG"

find_btn() {   # $1 = png; echoes "x y run" or nothing
  python3 "$CCWS/scripts/find_cyan_click.py" "$1" 2>/dev/null
}

capcut_win() { xdotool search --name '^CapCut$' 2>/dev/null | tail -1; }

START=$(date +%s)
attempt=0
last_hit=""
while :; do
  EL=$(( $(date +%s) - START ))
  [ "$EL" -gt "$TOTAL" ] && break
  shot="$OUT/probe_${EL}s.png"
  timeout 15 import -window root "$shot" 2>/dev/null || { sleep 2; continue; }
  hit=$(find_btn "$shot")
  if [ -z "$hit" ]; then
    echo "t=${EL}s: no CapCut button on screen" | tee -a "$LOG"
    sleep 2
    continue
  fi
  x=$(echo "$hit" | awk '{print $1}'); y=$(echo "$hit" | awk '{print $2}'); n=$(echo "$hit" | awk '{print $3}')
  wid=$(capcut_win)
  echo "t=${EL}s: button at ($x,$y) run=$n capcut_win=${wid:-none} -> attempt method $attempt" | tee -a "$LOG"
  case "$attempt" in
    0) xdotool mousemove "$x" "$y" click 1 ;;
    1) [ -n "${wid:-}" ] && xdotool windowactivate "$wid"
       xdotool key --clearmodifiers Return ;;
    2) xdotool mousemove "$x" "$y"; xdotool mousedown 1; sleep 0.3; xdotool mouseup 1 ;;
    3) xdotool key --clearmodifiers Tab; sleep 0.2; xdotool key --clearmodifiers Return ;;
    4) xdotool mousemove --sync "$x" "$y"; sleep 0.3; xdotool click --clearmodifiers 1 ;;
    *) echo "t=${EL}s: all methods tried, still present" | tee -a "$LOG"; sleep 4; continue ;;
  esac
  sleep 3
  shot2="$OUT/after_method${attempt}_${EL}s.png"
  timeout 15 import -window root "$shot2" 2>/dev/null
  hit2=$(find_btn "$shot2")
  if [ -z "$hit2" ]; then
    echo "t=${EL}s: METHOD $attempt WORKED (button gone) -- $shot2" | tee -a "$LOG"
    exit 0
  else
    echo "t=${EL}s: method $attempt had no effect (button still at $hit2)" | tee -a "$LOG"
    attempt=$(( attempt + 1 ))
  fi
done
echo "timed out without dismissing" | tee -a "$LOG"
exit 1
