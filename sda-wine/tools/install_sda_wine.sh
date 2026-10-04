#!/bin/bash
# Install Steinberg Download Assistant into the project Wine prefix, unattended.
#
#   tools/install_sda_wine.sh [seconds]
#
# The installer is a BitRock InstallBuilder 26.5.1 image; it accepts
#   --mode unattended --unattendedmodeui none
# and its own log (on Windows) is %TEMP%\installbuilder_installer.log.
set -uo pipefail
SD=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SECS=${1:-600}

WINEPREFIX=${SD_PREFIX:-$SD/state/prefix}
export WINEPREFIX
export WINEARCH=${WINEARCH:-win64}
export DISPLAY=${DISP:-:22}
export TMPDIR=$SD/state/tmp
export WINEDEBUG=${WINEDEBUG:-+err+all,-fixme-all}
[ -n "${OVERRIDES:-}" ] && export WINEDLLOVERRIDES="$OVERRIDES"

WINE=$SD/wine-install/bin/wine
SETUP=${SDA_SETUP:-/home/asdf/Downloads/Steinberg_Download_Assistant_1.40.1_Installer_win.exe}
LOG=$SD/logs/sda_install_wine.log

[ -x "$WINE" ] || { echo "no wine at $WINE"; exit 1; }
[ -f "$SETUP" ] || { echo "no installer at $SETUP"; exit 1; }

echo "== installing $SETUP (timeout ${SECS}s) prefix=$WINEPREFIX"
timeout "$SECS" "$WINE" "$SETUP" --mode unattended --unattendedmodeui none >"$LOG" 2>&1
rc=$?
echo "== installer rc=$rc  log=$LOG ($(wc -l <"$LOG") lines)"
echo "== notable lines:"
grep -aE "err:|wine: |Unhandled exception|page fault|fixme:.*not implemented|exit_code|installer_ui|installdir" "$LOG" | head -30
echo "== result tree:"
ls -la "$WINEPREFIX/drive_c/Program Files (x86)/Steinberg/Download Assistant" 2>/dev/null | head -20 || echo "nothing installed"
