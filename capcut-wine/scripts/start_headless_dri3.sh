#!/bin/bash
# Headless DRI3 X display for CapCut runs.
#
# Why this exists: the app needs a display with DRI3 (real GPU buffers). Xvfb cannot provide it, so the only
# other option was the session's Xwayland (`:10`), which is a *window on the user's desktop* — closing it kills
# the X server and every run on it (that cost one 600 s attempt). This script builds the same thing headlessly:
#
#   sway (WLR_BACKENDS=headless)  ->  wayland-1  ->  Xwayland :11  ->  DRI3 + Present, invisible
#
# Measured on `:11` after this script: 1916x1173, DPI 96x96, DRI3 present, Present present, openbox running.
# Controlled with SWAYSOCK=/run/user/1000/sway-ipc.<pid>.sock (e.g. `swaymsg output HEADLESS-1 resolution WxH`).
#
# usage: start_headless_dri3.sh [display] [WxH]        default :11  1920x1200
set -u
CCWS=/home/asdf/projects/capcut-wine
DISP=${1:-:11}
SIZE=${2:-1920x1200}
N=${DISP#:}
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
mkdir -p "$CCWS/logs"

have_dri3() { xdpyinfo -display "$DISP" 2>/dev/null | grep -q DRI3; }

# 1. headless compositor
if ! pgrep -f "sway -c /dev/null" >/dev/null; then
  echo "starting headless sway ..."
  WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 \
    nohup sway -c /dev/null > "$CCWS/logs/sway.log" 2>&1 &
  disown
  sleep 6
fi
WL=$(ls -t "$XDG_RUNTIME_DIR"/wayland-[0-9]* 2>/dev/null | grep -v '\.lock$' | head -1)
echo "wayland socket: ${WL:-NONE}"
[ -n "${WL:-}" ] || { echo "no wayland socket — is sway running?" >&2; exit 1; }
WLNAME=$(basename "$WL")

# 2. Xwayland on it (this is the DRI3 X display)
if ! have_dri3; then
  echo "starting Xwayland $DISP on $WLNAME ..."
  WAYLAND_DISPLAY=$WLNAME nohup Xwayland "$DISP" -geometry "$SIZE" \
      > "$CCWS/logs/xwayland${N}.log" 2>&1 &
  disown
  for i in $(seq 1 20); do sleep 1; have_dri3 && break; done
fi

# 3. size it like a real monitor and give it a WM
SWAYSOCK=$(ls -t "$XDG_RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -1)
[ -n "${SWAYSOCK:-}" ] && SWAYSOCK=$SWAYSOCK swaymsg output HEADLESS-1 resolution "$SIZE" >/dev/null 2>&1
if ! DISPLAY=$DISP xprop -root _NET_SUPPORTING_WM_CHECK >/dev/null 2>&1; then
  DISPLAY=$DISP nohup openbox > "$CCWS/logs/openbox${N}.log" 2>&1 &
  disown
  sleep 2
fi

echo -n "$DISP: "; DISPLAY=$DISP xdpyinfo 2>/dev/null | grep -E "dimensions" | head -1
echo -n "$DISP DRI3/Present: "; DISPLAY=$DISP xdpyinfo 2>/dev/null | grep -oE "DRI3|Present" | sort -u | tr '\n' ' '; echo
echo "use: DISPLAY=$DISP"
