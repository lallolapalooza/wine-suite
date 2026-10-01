#!/bin/bash
# Put the app's *selected* view back in front under Wine, periodically.
#
#   tools/pbi_occl_report_shim.sh [prefix] [seconds] [page-fragment]
#
# What it does: finds the panel whose WebView2 has loaded <page-fragment> (default reportView) and forces it to
# repaint -- InvalidateRect+UpdateWindow on its render widget (WM_PAINT is what makes Chromium schedule a
# compositor frame) followed by RedrawWindow(panel, RDW_ALLCHILDREN|...|RDW_UPDATENOW).  Verified on a live
# reproduction: with the TMDL view on screen (68 806 B crop, `To start editing` / `Welcome to TMDL` in OCR),
# `wvexstyle.exe redraw reportView` put the report page back in 4 s (107 402 B, `Design your report on mobile` /
# `Filters on this page`) with the panel regions unchanged (the covering panel's region was already full -- a
# static page simply produces no damage, so it never repaints by itself).
#
# Why: the surface that reaches the screen is the one whose system region says it is visible, and raising a panel
# makes its region full and puts its pixels back (measured live: `panelclick top reportView` flipped the report
# render widget's region from EMPTY to SIMPLE and the screen from the covered view back to the report page —
# FINDINGS M67).  Power BI keeps the report view selected for the whole run (`OnViewSelectionChanged` 1,
# `ActivateView …ReportView` 1, zero `SetView`/`DeactivateView`), so re-raising it cannot fight the app: it only
# re-asserts the z-order the app already believes in, and with it the presentation Wine lost.
#
# This is the deterministic arm of the mitigation: `tools/pbi_occl_shim.sh` (ex-styles) addresses the race that
# lets a covered view paint; this one addresses its *consequence* — a static report page that never repaints.
# The interval is 5 s, which is inside the sampler's own 2-3 s frame cadence, so a takeover cannot survive a frame.
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PFX=${1:-pbi2}
SECS=${2:-0}                     # 0 = until no PBIDesktop.exe is left
FRAG=${3:-reportView}
# The display must be chosen BEFORE sourcing pbi_env.sh: that script does `export DISPLAY=${PBIDISPLAY:-:2}`, so
# reading PBIDISPLAY afterwards can only recover :2 — the app, meanwhile, runs on the runner's default :9
# (`acceptance_run.sh` line 31, `DISP=${PBIDISPLAY:-:9}`). Set :9 first so both agree, and only then source.
export PBIDISPLAY=${PBIDISPLAY:-:9}
source "$ROOT/tools/pbi_env.sh" "$PFX" >/dev/null 2>&1
export DISPLAY=${PBIDISPLAY:-:9}

STAGE="$WINEPREFIX/drive_c/winapi"
install -d "$STAGE" 2>/dev/null
install -m755 "$ROOT/tools/winapi/bin/wvexstyle.exe" "$STAGE/" 2>/dev/null || {
    echo "cannot stage wvexstyle.exe into $STAGE" >&2; exit 2; }

echo "shim: prefix=$WINEPREFIX display=${DISPLAY:-} (forcing a repaint of the '$FRAG' panel every 5 s)"
end=0
[ "$SECS" -gt 0 ] && end=$(( $(date +%s) + SECS ))
while :; do
    if pgrep -f 'PBIDesktop.exe' >/dev/null; then
        # Hiding the secondary panels is the load-bearing half, measured (M70): with it, a 240 s run sampled the
        # report page in 161 of 175 frames and the DAX editor in ZERO, where the redraw alone left the DAX on screen
        # for 132 of 173 frames. Reason (M69): the screen is the last DXGI surface the WebView2 GPU processes
        # pushed, so a hidden view's Chromium renderer stops producing frames at all - no Wine repaint can do that.
        # The hide is per-panel and reversible (`wvexstyle.exe showall`), and the app keeps its own selected view.
        DISPLAY="$DISPLAY" WINEPREFIX="$WINEPREFIX" "$WINE" 'C:\winapi\wvexstyle.exe' hide "$FRAG" 2>/dev/null \
            | sed "s/^/$(date +%H:%M:%S) /"
        # And keep re-asserting the selected view's own repaint, which covers the paint-over variant (M67).
        DISPLAY="$DISPLAY" WINEPREFIX="$WINEPREFIX" "$WINE" 'C:\winapi\wvexstyle.exe' redraw "$FRAG" 2>/dev/null \
            | sed "s/^/$(date +%H:%M:%S) /"
    fi
    if [ "$end" != 0 ]; then [ "$(date +%s)" -ge "$end" ] && { echo "shim: reached ${SECS}s, done"; break; }
    else pgrep -f 'PBIDesktop.exe' >/dev/null || { echo "shim: no PBIDesktop.exe left, done"; break; }; fi
    sleep 5
done
