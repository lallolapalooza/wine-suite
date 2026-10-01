#!/bin/bash
# Register Revit 2027 (prodKey 829S1) with the Autodesk licensing components.
#
# Why this exists: on Windows the registration is performed by the product package's MSI custom actions
# (LicensingCustomAction.licRegister / licMarkInstall).  If the bundle's own registration does not happen
# in this prefix, the licensing service's BoltDB ends up with no FEATURE entry for 829S1/2027.0.0.F and the
# licensing web UI (the AdskLicensingAgent's WebView2, /ui/v2/lgs) falls back to /ui/v2/error...errGeneric
# and the product reports "The License manager is not functioning or is improperly installed".
#
# The sequence below is the one the AutoCAD fork captured from a working Windows install, with Revit's
# product key and its own .pit:
#
#   tools/fix_licensing_registration.sh [prefix]
#
# The .pit comes from the installed RVT package (`RevitConfig.pit`, staged under
# %TEMP%\{8CA3AC7D-…}\x64\RVT\); Revit's identity file puts the product at 829S1 / 2027.0.0.F / RVT.
set -eu
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$ROOT/env.sh" >/dev/null 2>&1

PREFIX="${1:-$REVIT_PREFIX}"
PROD_KEY=829S1
PROD_VER=2027.0.0.F
PIT_DST_DIR='C:\ProgramData\Autodesk\RVT 2027'
PIT_DST_NAME=RevitConfig.pit

export WINEPREFIX="$PREFIX"
export WINEDLLOVERRIDES="${REVIT_DLLOVERRIDES:-mshtml=}"
export DISPLAY="${DISP:-:2}"
WINE=${REVIT_WINE:-$WINEPREFIX_INSTALL/bin/wine}
[ -x "$WINE" ] || { echo "no wine at $WINE" >&2; exit 1; }

find_pit() {
  local c
  for c in "$PREFIX/drive_c/ProgramData/Autodesk/RVT 2027/$PIT_DST_NAME" \
           $(ls -t "$PREFIX/drive_c/users/"*/AppData/Local/Temp/*/x64/RVT/$PIT_DST_NAME 2>/dev/null) \
           $(find "$PREFIX/drive_c/Autodesk/WI" -name "$PIT_DST_NAME" 2>/dev/null); do
    [ -f "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}
PIT_SRC=$(find_pit) || { echo "no $PIT_DST_NAME found in $PREFIX (is the RVT package installed?)" >&2; exit 1; }
echo "pit: $PIT_SRC ($(md5sum "$PIT_SRC" | cut -d' ' -f1))"

ADSK="Program Files (x86)/Common Files/Autodesk Shared/AdskLicensing"
HELPER_WIN=""
for cand in "$PREFIX/drive_c/$ADSK/Current/helper/AdskLicensingInstHelper.exe" \
            $(ls -t "$PREFIX/drive_c/$ADSK"/*/helper/AdskLicensingInstHelper.exe 2>/dev/null); do
  [ -f "$cand" ] || continue
  HELPER_WIN="C:\\$(printf '%s' "${cand#"$PREFIX/drive_c/"}" | sed 's|/|\\|g')"
  break
done
[ -n "$HELPER_WIN" ] || { echo "AdskLicensingInstHelper.exe not found under $PREFIX/drive_c/$ADSK" >&2; exit 1; }
echo "helper: $HELPER_WIN"

mkdir -p "$PREFIX/drive_c/ProgramData/Autodesk/RVT 2027"
cp -f "$PIT_SRC" "$PREFIX/drive_c/ProgramData/Autodesk/RVT 2027/$PIT_DST_NAME"

run() { echo "+ $*"; timeout 180 "$WINE" "$HELPER_WIN" "$@" 2>&1 | grep -avE 'fixme|BCRYPTDUMP' || true; }

run product_install stop
run product_install start -p "$PROD_KEY:$PROD_VER"
run upgrade isUpgraded
run register --upgrade -pk "$PROD_KEY" -pv "$PROD_VER" -cf "$PIT_DST_DIR\\$PIT_DST_NAME" -sk 00000

# The licensing UI is the AdskLicensingAgent's own WebView2 (a different process from Revit), so it does not
# inherit Revit's WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS; without --disable-gpu its surface never paints under
# Wine.  Machine-wide makes every WebView2 in the prefix render.
timeout 60 "$WINE" reg add 'HKCU\Environment' /v WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS /t REG_SZ /d '--disable-gpu' /f \
  2>&1 | grep -avE 'fixme' || true

# `product_install start` leaves this marker; while it exists every later helper call answers
# "Autodesk product installation is in progress and please try later".
MARKER="$PREFIX/drive_c/ProgramData/Autodesk/AdskLicensingService/product_install.json"
[ -f "$MARKER" ] && { rm -f "$MARKER"; echo "cleared $(basename "$MARKER")"; }

echo "--- AdskLicensingInstHelper list ---"
timeout 90 "$WINE" "$HELPER_WIN" list 2>&1 | grep -avE 'fixme' || true
echo "--- feature record in the service DB ---"
strings -n 20 "$PREFIX/drive_c/ProgramData/Autodesk/AdskLicensingService/AdskLicensingService.sds" 2>/dev/null \
  | grep -a "$PROD_KEY" | head -2 | cut -c1-200 || true
