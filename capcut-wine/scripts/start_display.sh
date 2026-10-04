#!/bin/bash
# Bring up the X display CapCut is tested on.
#
# Why Xwayland and not Xvfb: Xvfb has no DRI3, so Mesa cannot hand GPU buffers to the X server.
# On Xvfb, GL falls back to llvmpipe (software) and DXVK's Vulkan presentation cannot work at all
# (the client dies at the first Present). On the session's Wayland compositor, a second Xwayland
# instance gives a display that reports both DRI3 and Present, and GLX then uses the real iGPU.
#
#   xdpyinfo -display :9  ->  Present                  (no DRI3)      <= Xvfb
#   xdpyinfo -display :10 ->  DRI3, Present                            <= Xwayland
#
# usage: start_display.sh [display]     default :10
set -u
CCWS=/home/asdf/projects/capcut-wine
DISP=${1:-:10}
N=${DISP#:}
LOG=$CCWS/logs/display${N}.log
mkdir -p "$CCWS/logs"

have_dri3() { xdpyinfo -display "$DISP" 2>/dev/null | grep -q DRI3; }

if have_dri3; then
  echo "$DISP already up with DRI3"
else
  echo "starting Xwayland $DISP ..."
  WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0} XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)} \
    nohup Xwayland "$DISP" -geometry 1600x1000 > "$LOG" 2>&1 &
  disown
  for i in $(seq 1 20); do sleep 1; have_dri3 && break; done
fi

if have_dri3; then
  echo "$DISP: DRI3 present"
else
  echo "$DISP: DRI3 MISSING (falling back to Xvfb means no GPU acceleration)" >&2
fi

# a window manager, so windows are mapped/activated the way an app expects
if ! DISPLAY=$DISP xprop -root _NET_SUPPORTING_WM_CHECK >/dev/null 2>&1; then
  DISPLAY=$DISP nohup openbox > "$CCWS/logs/openbox${N}.log" 2>&1 &
  disown
  sleep 2
fi
DISPLAY=$DISP xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | head -1
echo "use: DISPLAY=$DISP"
