#!/bin/bash
# Wait for a UAC consent prompt on the guest and click Yes.
#
#   tools/win_uac_click.sh [timeout_s] [WxH]
#
# The prompt lives on the secure desktop: it IS captured by `virsh screenshot` (measured), but only when
# no shell overlay (Start/Search) is open — an open Start menu suppresses the desktop switch entirely.
# A consent desktop is a dimmed screen: mean luminance ~0.27 versus ~0.47-0.71 for the plain desktop.
# Geometry on this 1280x800 guest: panel x 412-867, y 212-588; Yes is centred at (541,548), No at (745,548).
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TMO=${1:-90}
SCREEN=${2:-1280x800}
END=$(( $(date +%s) + TMO ))
while [ "$(date +%s)" -lt "$END" ]; do
    f=$(mktemp /tmp/uacXXXXXX.ppm)
    if timeout 15 virsh screenshot win11 "$f" --screen 0 >/dev/null 2>&1 && [ -s "$f" ]; then
        m=$(magick "$f" -format '%[fx:mean]' info: 2>/dev/null || echo 1)
        rm -f "$f"
        if awk -v m="$m" 'BEGIN{exit !(m < 0.40)}'; then
            python3 "$HERE/vm/vmclick.py" 541 548 --screen "$SCREEN"
            echo "clicked Yes (mean=$m)"
            exit 0
        fi
    fi
    sleep 2
done
echo "no consent prompt seen within ${TMO}s"
exit 1
