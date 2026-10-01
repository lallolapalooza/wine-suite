#!/bin/bash
# Register AutoCAD 2027 (prodKey 001S1) with the Autodesk licensing components.
#
# Why this exists: the registration is normally performed by the "ACAD Private" (acadprivate) package's MSI
# custom actions (LicensingCustomAction.licRegister / licMarkInstall). ODIS never installs that package in this
# prefix, so the licensing service's BoltDB ends up with no FEATURE entry for 001S1/2027.0.0.F and the licensing
# web UI (the AdskLicensingAgent's WebView2, page /ui/v2/lgs) falls back to /ui/v2/error?...&page=errGeneric.
#
# This runs exactly the sequence a working Windows install runs (captured from the guest's
# Autodesk_AutoCAD_Private_2027_install.log), using the .pit that ships inside the acadprivate payload.
#
# usage: tools/fix_licensing_registration.sh [prefix]
set -eu
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PREFIX="${1:-$ROOT/prefix}"
PIT_SRC="$ROOT/pkgs/x/x64/acadprivate/AutoCADConfig.pit"
PIT_DST_DIR="C:\\ProgramData\\Autodesk\\acadprivate"
PROD_KEY=001S1
PROD_VER=2027.0.0.F

export WINEPREFIX="$PREFIX"
export WINEDLLOVERRIDES="mshtml="
export PATH="$ROOT/wine-install/bin:$PATH"
export DISPLAY="${DISP:-:2}"

# Find the helper the way Windows does: preferentially through the AdskLicensing "Current" link, else the newest
# versioned install - a fresh prefix may lay down a different licensing version than the one this was written on.
ADSK="Program Files (x86)/Common Files/Autodesk Shared/AdskLicensing"
HELPER_WIN=""
while IFS= read -r cand; do
  [ -n "$cand" ] && [ -f "$cand" ] || continue
  HELPER_WIN="C:\\$(printf '%s' "${cand#"$PREFIX/drive_c/"}" | sed 's|/|\\|g')"
  break
done <<EOF
$PREFIX/drive_c/$ADSK/Current/helper/AdskLicensingInstHelper.exe
$(ls -t "$PREFIX/drive_c/$ADSK"/*/helper/AdskLicensingInstHelper.exe 2>/dev/null)
EOF
[ -n "$HELPER_WIN" ] || { echo "AdskLicensingInstHelper.exe not found under $PREFIX/drive_c/$ADSK" >&2; exit 1; }
echo "helper: $HELPER_WIN"

[ -f "$PIT_SRC" ] || { echo "missing $PIT_SRC (acadprivate payload)" >&2; exit 1; }

# The helper reads the product's licence types from here; the product installer creates it.
if [ ! -f "$PREFIX/drive_c/ProgramData/Autodesk/Adlm/ProductInformation.pit" ]; then
  echo "WARNING: $PREFIX/drive_c/ProgramData/Autodesk/Adlm/ProductInformation.pit is missing;" >&2
  echo "         UserLicEnable/TrialEnable will stay false." >&2
fi

mkdir -p "$PREFIX/drive_c/ProgramData/Autodesk/acadprivate"
cp -f "$PIT_SRC" "$PREFIX/drive_c/ProgramData/Autodesk/acadprivate/AutoCADConfig.pit"
echo "pit: $(md5sum "$PREFIX/drive_c/ProgramData/Autodesk/acadprivate/AutoCADConfig.pit" | cut -d' ' -f1)"

run() { echo "+ $*"; timeout 180 wine "$HELPER_WIN" "$@" 2>&1 | grep -avE 'fixme|BCRYPTDUMP' || true; }

run product_install stop
run product_install start -p "$PROD_KEY:$PROD_VER"
run upgrade isUpgraded
run register --upgrade -pk "$PROD_KEY" -pv "$PROD_VER" -cf "$PIT_DST_DIR\\AutoCADConfig.pit" -sk 00000

# The licensing UI is the AdskLicensingAgent's own WebView2, and the agent is launched by the licensing service, so
# it does *not* inherit the WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS that acad.exe is started with. Without
# --disable-gpu its Chromium surface never paints under Wine (the window stays a blank rectangle). Setting it
# machine-wide makes both webviews render.
timeout 60 wine reg add "HKCU\\Environment" /v WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS /t REG_SZ /d "--disable-gpu" /f \
  2>&1 | grep -avE 'fixme' || true

# `product_install start` leaves this marker (the MSI clears it in its licUnmarkInstall action at uninstall time).
# While it exists every later helper call answers "Autodesk product installation is in progress and please try later".
MARKER="$PREFIX/drive_c/ProgramData/Autodesk/AdskLicensingService/product_install.json"
if [ -f "$MARKER" ]; then rm -f "$MARKER"; echo "cleared $(basename "$MARKER")"; fi

echo "--- AdskLicensingInstHelper list ---"
timeout 90 wine "$HELPER_WIN" list 2>&1 | grep -avE 'fixme' || true
echo "--- feature record in the service DB ---"
strings -n 20 "$PREFIX/drive_c/ProgramData/Autodesk/AdskLicensingService/AdskLicensingService.sds" \
  | grep -a 'UserLicEnable' | head -1 | cut -c1-300 || true
