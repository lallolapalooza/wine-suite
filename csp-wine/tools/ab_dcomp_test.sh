#!/bin/bash
# A/B: is the dcomp patch set load-bearing for CSP's UI?
#
# Rigorous form.  The two builds have DIFFERENT wineserver protocol versions (the 67 patches add
# @REQ entries to server/protocol.def, which shifts the handshake version), so a leftover wineserver
# from the other build makes the next run fail with
#     wine client error:0: version mismatch NNN/MMM
# and the window under test is then just stale pixels.  So this script:
#   * kills every wineserver belonging to this project between legs,
#   * waits for the app process to actually appear before capturing,
#   * records whether the process was alive at capture time.
#
#   tools/ab_dcomp_test.sh
set -u
CW=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$CW/env.sh"

NODCOMP_WINE="$CW/state/nodcomp$CW_INSTALL/bin/wine"
[ -x "$NODCOMP_WINE" ] || { echo "no nodcomp build; run tools/ab_dcomp.sh revert first"; exit 1; }
EDITOR="$CW_PREFIX/drive_c/Program Files/CELSYS/CLIP STUDIO 1.5/CLIP STUDIO PAINT/CLIPStudioPaint.exe"
ROAM="$CW_PREFIX/drive_c/users/asdf/AppData/Roaming"
BACKUP="$CW/state/appdata_backup"
export WINEPREFIX=$CW_PREFIX DISPLAY=$DISP WINEESYNC=1 TMPDIR=$CW_TMP WINEDEBUG=-all

mkdir -p "$BACKUP"
for d in CELSYS CELSYS_EN CELSYSUserData; do
  [ -d "$ROAM/$d" ] && [ ! -d "$BACKUP/$d" ] && cp -a "$ROAM/$d" "$BACKUP/$d"
done

kills() {   # kill every wineserver of this project, whichever binary started it
  pkill -f CLIPStudioPaint 2>/dev/null
  pkill -f msedgewebview2 2>/dev/null
  pkill -f "csp-wine.*wineserver" 2>/dev/null
  pkill -f "state/nodcomp.*wineserver" 2>/dev/null
  sleep 3
}

measure() { # <tag> <wine-binary>
  local tag=$1 wine=$2 alive=no t=0
  kills
  for d in CELSYS CELSYS_EN CELSYSUserData; do rm -rf "$ROAM/$d"; done
  setsid nohup "$wine" "$EDITOR" > "$CW_LOGS/ab_${tag}_stdout.log" 2> "$CW_LOGS/ab_${tag}.log" < /dev/null &
  while [ $t -lt 90 ]; do
    pgrep -f CLIPStudioPaint >/dev/null 2>&1 && { alive=yes; break; }
    sleep 3; t=$((t+3))
  done
  [ "$alive" = yes ] && sleep 70          # let it draw the first-run dialog
  pgrep -f CLIPStudioPaint >/dev/null 2>&1 && alive=yes || alive=no
  DISPLAY=$DISP python3 "$CW/tools/uix.py" shot "$CW/evidence/ab_${tag}.png" >/dev/null
  echo "== $tag ==  (process alive at capture: $alive, $(grep -c . "$CW_LOGS/ab_${tag}.log") log lines)"
  grep -c "version mismatch" "$CW_LOGS/ab_${tag}.log" | sed 's/^/   version-mismatch lines: /'
  python3 - "$CW/evidence/ab_${tag}.png" <<'PY'
import sys, collections
from PIL import Image
c = collections.Counter(Image.open(sys.argv[1]).convert('RGB').getdata())
print("   unique colours:", len(c), " top:", c.most_common(3))
PY
  convert "$CW/evidence/ab_${tag}.png" -crop 1180x900+355+105 +repage -colorspace Gray -normalize \
          -resize 200% /tmp/ab_${tag}.png 2>/dev/null
  echo "   OCR:"
  tesseract /tmp/ab_${tag}.png stdout --psm 6 2>/dev/null | sed '/^\s*$/d' | head -5 | sed 's/^/     /'
}

echo "WITH    $(ls -la "$CW_INSTALL/lib/wine/x86_64-windows/dcomp.dll" | awk '{print $5" bytes"}')"
echo "WITHOUT $(ls -la "$CW/state/nodcomp$CW_INSTALL/lib/wine/x86_64-windows/dcomp.dll" | awk '{print $5" bytes"}')"

measure with_dcomp    "$CW_INSTALL/bin/wine"
measure without_dcomp "$NODCOMP_WINE"

kills
for d in CELSYS CELSYS_EN CELSYSUserData; do
  rm -rf "$ROAM/$d"
  [ -d "$BACKUP/$d" ] && cp -a "$BACKUP/$d" "$ROAM/$d"
done
echo "appdata restored"
