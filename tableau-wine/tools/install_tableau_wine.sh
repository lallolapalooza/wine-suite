#!/bin/bash
# Run the Tableau Burn bundle inside the project Wine prefix, capturing the burn log.
#
#   tools/install_tableau_wine.sh [tag]
#
# The bundle is executed from its Unix path (Wine maps / to Z:) so the 710 MB installer is never copied.
# Same command line as the verified Windows reference run: /quiet /norestart /log <winpath> ACCEPTEULA=1
# Output: logs/install-wine-<tag>/{burn.log,stderr.log}
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TAG=${1:-$(date +%H%M%S)}
OUT=$ROOT/logs/install-wine-$TAG
mkdir -p "$OUT"

export WINEPREFIX=${WINEPREFIX:-$ROOT/prefix/tableau}
export DISPLAY=${DISP:-:11}
export WINE=${WINEBUILD:-$ROOT/wine-install/bin/wine}
export WINEDEBUG=${WINEDEBUG:-err+all,fixme-all}
WINPATH='C:\tableau_burn.log'

[ -x "$WINE" ] || { echo "no wine at $WINE"; exit 1; }
[ -d "$WINEPREFIX" ] || { echo "no prefix at $WINEPREFIX - run tools/make_prefix.sh"; exit 1; }

echo "== wine $("$WINE" --version) prefix=$WINEPREFIX $(date -Is)" | tee "$OUT/cmd.txt"
INSTALLER=${TABLEAU_INSTALLER:-$ROOT/src/TableauDesktop-64bit-2026-2-3.exe}
[ -f "$INSTALLER" ] || INSTALLER=/home/asdf/Downloads/TableauDesktop-64bit-2026-2-3.exe
[ -f "$INSTALLER" ] || INSTALLER=$ROOT/app/TableauDesktop-64bit-2026-2-3.exe
[ -f "$INSTALLER" ] || { echo "installer not found (set TABLEAU_INSTALLER)"; exit 1; }
echo "installer=$INSTALLER" | tee -a "$OUT/cmd.txt"
"$WINE" "$INSTALLER" \
    /quiet /norestart "/log" "$WINPATH" ACCEPTEULA=1 >>"$OUT/stderr.log" 2>&1
rc=$?
echo "wine_exit=$rc" | tee -a "$OUT/cmd.txt"

echo "== installed tree:"
find "$WINEPREFIX/drive_c/Program Files/Tableau" -maxdepth 2 2>/dev/null | head -30

echo "== burn log tail (drive_c/tableau_burn.log):"
tail -40 "$WINEPREFIX/drive_c/tableau_burn.log" 2>/dev/null || echo "(no burn log at $WINEPREFIX/drive_c/tableau_burn.log)"
exit 0
