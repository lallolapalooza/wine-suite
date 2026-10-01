#!/bin/bash
# =============================================================================
# tools/install_se_prefix.sh — take an EMPTY Wine prefix to an installed Solid Edge 2026
#
# usage: tools/install_se_prefix.sh <prefix-path> [--install-only] [--force-install]
#                                    [--skip-prereqs] [--wine PATH]
#
#   (default)        prefix -> prerequisites -> Solid Edge install -> fixups -> report
#   --install-only   stop after the Solid Edge install
#   --force-install  install even if Edge.exe is already present
#   --skip-prereqs   do not run winetricks/VC++/WebView2 (use when they are already done)
#   --msi            drive the MSI with msiexec directly instead of InstallShield's setup.exe
#
# Media: $SE_MEDIA must contain the InstallShield layout (setup.exe + "Siemens Solid Edge 2026.msi"
# + the cabs), i.e. the extracted `Solid Edge/` directory from
# Solid_Edge_Web_Package_2026.7z.001..027.
#
# Logs: $SE_LOGS/<prefix-name>/
# =============================================================================
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$ROOT/env.sh"
WINE=${SE_WINE:-$WINEPREFIX_INSTALL/bin/wine}
MEDIA=${SE_MEDIA:-$ROOT/installer/media_x/Solid Edge}
DISPLAY_X=${DISP:-:2}
export WINEDLLOVERRIDES="${SE_DLLOVERRIDES:-mshtml=}"

PREFIX_IN=""
INSTALL_ONLY=0
FORCE_INSTALL=0
SKIP_PREREQS=0
USE_MSI=0
while [ $# -gt 0 ]; do
  case "$1" in
    --install-only)  INSTALL_ONLY=1; shift ;;
    --force-install) FORCE_INSTALL=1; shift ;;
    --skip-prereqs)  SKIP_PREREQS=1; shift ;;
    --msi)           USE_MSI=1; shift ;;
    --wine)          WINE="$2"; shift 2 ;;
    -h|--help)       sed -n '2,20p' "$0"; exit 0 ;;
    *)               PREFIX_IN="$1"; shift ;;
  esac
done
[ -n "$PREFIX_IN" ] || { sed -n '2,6p' "$0" >&2; exit 2; }
mkdir -p "$PREFIX_IN"
PREFIX=$(readlink -f "$PREFIX_IN")
LOG_DIR="$SE_LOGS/$(basename "$PREFIX")"
mkdir -p "$LOG_DIR"

FAIL=0
step()    { printf '\n== %s\n' "$*"; }
ok()      { printf '  [ ok ]      %s\n' "$*"; }
note()    { printf '  [note]      %s\n' "$*"; }
warn()    { printf '  [warn]      %s\n' "$*"; }
missing() { printf '  [MISSING]   %s\n' "$*"; FAIL=1; }
wrun()    { WINEPREFIX="$PREFIX" DISPLAY="$DISPLAY_X" "$WINE" "$@"; }

step "0. sanity"
[ -x "$WINE" ] || missing "wine at $WINE (build it first: tools/build_wine.sh)"
[ -f "$MEDIA/setup.exe" ] || missing "media incomplete: $MEDIA/setup.exe"
[ -f "$MEDIA/Siemens Solid Edge 2026.msi" ] || missing "media incomplete: the MSI"
[ "$FAIL" = 0 ] || exit 1
ok "$("$WINE" --version)"
ok "media: $MEDIA"

step "1. prefix (win64, Windows 10)"
if [ -s "$PREFIX/system.reg" ]; then
  note "prefix already exists at $PREFIX"
else
  WINEARCH=win64 WINEPREFIX="$PREFIX" DISPLAY="$DISPLAY_X" "$WINE" wineboot -u \
      > "$LOG_DIR/wineboot.log" 2>&1
  for _ in $(seq 1 120); do
    [ -s "$PREFIX/system.reg" ] && [ -s "$PREFIX/user.reg" ] && break
    sleep 2
  done
  WINEPREFIX="$PREFIX" "$WINE" wineserver -w 2>/dev/null || true
  [ -s "$PREFIX/system.reg" ] || { missing "wineboot produced no system.reg"; exit 1; }
  ok "created prefix"
fi
grep -q '#arch=win64' "$PREFIX/system.reg" || { missing "$PREFIX is not win64"; exit 1; }
# Solid Edge 2026 refuses to install on a Windows version older than 10.
wrun reg add 'HKCU\Software\Wine' /v Version /t REG_SZ /d win10 /f >/dev/null 2>&1
WINEPREFIX="$PREFIX" WINE="$WINE" WINESERVER="$(dirname "$WINE")/wineserver" \
    winetricks -q win10 > "$LOG_DIR/winetricks_win10.log" 2>&1 ||
  note "winetricks win10 returned non-zero (log $LOG_DIR/winetricks_win10.log)"
ok "Windows version: win10"

if [ "$SKIP_PREREQS" = 0 ] && [ "$INSTALL_ONLY" = 0 ]; then
  step "2a. fonts (Arial / Microsoft Sans Serif substitutes)"
  # WPF and the MFC toolkit ask for Arial by name; a Wine prefix ships neither as a file and
  # WPF's font resolution goes through DirectWrite, which does not consult the GDI
  # FontSubstitutes table.  Same fix the sibling CAD projects needed.
  if [ -f "$PREFIX/drive_c/windows/Fonts/arial.ttf" ]; then
    note "already present"
  else
    "$ROOT/tools/venv/bin/python" "$ROOT/tools/make_wine_fonts.py" \
        "$PREFIX/drive_c/windows/Fonts" > "$LOG_DIR/fonts.log" 2>&1 &&
      ok "built arial.ttf/arialbd.ttf/micross.ttf" || missing "font substitute build failed"
    for f in arial.ttf arialbd.ttf micross.ttf; do
      [ -f "$PREFIX/drive_c/windows/Fonts/$f" ] || continue
      wrun reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts' \
          /v "$f (TrueType)" /t REG_SZ /d "$f" /f >/dev/null 2>&1
    done
  fi

  step "2b. Visual C++ 2022 runtime (x64) — Edge.exe/render.dll import MSVCP140/VCRUNTIME140"
  # A Wine prefix always has a *builtin* vcruntime140_1.dll, so the presence of the file proves
  # nothing; the native redistributable reports itself in the registry, so ask for that.
  if reg_q() { WINEPREFIX="$PREFIX" "$WINE" reg query "$1" /v "$2" >/dev/null 2>&1; }
     reg_q 'HKLM\Software\Microsoft\VisualStudio\14.0\VC\Runtimes\x64' Version; then
    note "native VC++ runtime already registered"
  else
    ( cd "$MEDIA/ISSetupPrerequisites/MS VC++ 2022 Redist (x64)" && \
      WINEPREFIX="$PREFIX" DISPLAY="$DISPLAY_X" \
      WINE="$WINE" "$WINE" VC_redist.x64.exe /install /quiet /norestart ) \
      > "$LOG_DIR/vcredist.log" 2>&1
    rc=$?
    if reg_q 'HKLM\Software\Microsoft\VisualStudio\14.0\VC\Runtimes\x64' Version; then
      ok "VC_redist.x64.exe rc=$rc, runtime registered"
    else
      warn "VC_redist rc=$rc and nothing registered; trying winetricks vcrun2022"
      ( WINEPREFIX="$PREFIX" DISPLAY="$DISPLAY_X" WINEDLLOVERRIDES="mshtml=" \
          WINE="$WINE" WINESERVER="$(dirname "$WINE")/wineserver" winetricks -q vcrun2022 ) \
        > "$LOG_DIR/vcrun2022.log" 2>&1
      reg_q 'HKLM\Software\Microsoft\VisualStudio\14.0\VC\Runtimes\x64' Version &&
        ok "winetricks vcrun2022 installed it" || missing "no native VC++ runtime (see $LOG_DIR)"
    fi
  fi

  step "2c. .NET Framework 4.8 (winetricks; cache at ~/.cache/winetricks/dotnet48)"
  if [ -d "$PREFIX/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319" ] &&
     [ -f "$PREFIX/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319/clr.dll" ]; then
    note "looks already present"
  else
    printf '  this takes 30-90 minutes and is NGEN-heavy; do not interrupt\n'
    # winetricks must drive *this* build, not whatever `wine` resolves to on PATH
    ( WINEPREFIX="$PREFIX" DISPLAY="$DISPLAY_X" WINEDLLOVERRIDES="mshtml=" \
        WINE="$WINE" WINESERVER="$(dirname "$WINE")/wineserver" \
        WINEARCH=win64 \
        winetricks -q --force dotnet48 ) > "$LOG_DIR/dotnet48.log" 2>&1
    ok "winetricks dotnet48 rc=$? (log $LOG_DIR/dotnet48.log)"
  fi
  # winetricks switches the reported Windows version around while installing .NET (winxp64 then
  # win7); Solid Edge wants 10, so put it back.
  wrun reg add 'HKCU\Software\Wine' /v Version /t REG_SZ /d win10 /f >/dev/null 2>&1
  WINEPREFIX="$PREFIX" WINE="$WINE" WINESERVER="$(dirname "$WINE")/wineserver" \
      winetricks -q win10 >/dev/null 2>&1 || true
  ok "Windows version re-asserted: win10"

  step "2d. WebView2 runtime (control.dll imports WebView2Loader.dll)"
  if [ -n "$(find "$PREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application" \
             -maxdepth 2 -iname msedgewebview2.exe -print -quit 2>/dev/null)" ]; then
    note "already deployed"
  else
    if [ -s "$SE_LOGS/webview2/wv2.zip" ]; then
      "$ROOT/tools/deploy_webview2.sh" "$SE_LOGS/webview2/wv2.zip" "$PREFIX" \
          > "$LOG_DIR/webview2.log" 2>&1 &&
        ok "deployed from $SE_LOGS/webview2/wv2.zip" || warn "deploy failed (see $LOG_DIR/webview2.log)"
    else
      "$ROOT/tools/deploy_webview2.sh" --from-guest "$PREFIX" > "$LOG_DIR/webview2.log" 2>&1 &&
        ok "harvested from the guest" || warn "no WebView2 runtime (see $LOG_DIR/webview2.log)"
    fi
  fi

  # The sibling projects' measured requirement: Chromium's surface stays unpainted under Wine
  # without this, and it must be in HKCU\Environment because a service-launched WebView2 does
  # not inherit the app's process environment.
  wrun reg add 'HKCU\Environment' /v WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS \
      /t REG_SZ /d "--disable-gpu" /f >/dev/null 2>&1
  ok "HKCU\\Environment WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = --disable-gpu"
fi

step "3. Solid Edge install"
SE_EXE="$PREFIX/drive_c/Program Files/Siemens/Solid Edge 2026/Program/Edge.exe"
if [ -f "$SE_EXE" ] && [ "$FORCE_INSTALL" = 0 ]; then
  note "already installed ($SE_EXE)"
else
  ilog="$LOG_DIR/install.log"
  # The vendor's own command line (FINDINGS M6, decompiled from SEWebInstall.frmSEWebInstall).
  # INSTALLDIR is what the web installer would have used, and USERFILESPEC is where the media's
  # demo licence (SElicense.lic, from Licens~1.cab) is placed.
  INSTDIR_WIN='C:\Program Files\Siemens\Solid Edge 2026'
  LICFILE_WIN="$INSTDIR_WIN\\Preferences\\SELicense.lic"
  if [ "$USE_MSI" = 1 ]; then
    # Fallback that bypasses InstallShield's launcher entirely: drive the MSI directly with the
    # en-US transform.  `setup.exe` is the path the vendor itself uses (FINDINGS M6); this is what
    # to try when it fails before reaching the MSI.
    note "msiexec /i \"Siemens Solid Edge 2026.msi\" TRANSFORMS=1033.mst"
    ( cd "$MEDIA" && WINEPREFIX="$PREFIX" DISPLAY="$DISPLAY_X" \
        WINEDLLOVERRIDES="${SE_DLLOVERRIDES:-mshtml=}" \
        timeout "${INSTALL_TIMEOUT:-7200}" \
        "$WINE" msiexec /i "Siemens Solid Edge 2026.msi" TRANSFORMS=1033.mst \
            INSTALLDIR="$INSTDIR_WIN" USERFILESPEC="$LICFILE_WIN" \
            /qn /l*v C:\\se_install_msi.log ) > "$ilog" 2>&1
    ok "msiexec rc=$? (log $ilog)"
  else
    VCMD="/s /clone_wait /v\"/qn\" /v\"INSTALLDIR=\\\"$INSTDIR_WIN\\\"\" /v\"USERFILESPEC=\\\"$LICFILE_WIN\\\"\" /v\"/l*v C:\\\\se_install.log\""
    note "setup.exe $VCMD"
    ( cd "$MEDIA" && WINEPREFIX="$PREFIX" DISPLAY="$DISPLAY_X" \
        WINEDLLOVERRIDES="${SE_DLLOVERRIDES:-mshtml=}" \
        timeout "${INSTALL_TIMEOUT:-7200}" \
        "$WINE" ./setup.exe $VCMD ) > "$ilog" 2>&1
    ok "setup rc=$? (log $ilog)"
  fi
fi
WINEPREFIX="$PREFIX" "$WINE" wineserver -w 2>/dev/null || true

step "4. report"
chk() { if [ -e "$1" ]; then printf '  [ ok ]      %s\n' "$2"; else printf '  [MISSING]   %s\n' "$2"; FAIL=1; fi; }
chk "$PREFIX/drive_c/Program Files/Siemens/Solid Edge 2026/Program/Edge.exe" "Edge.exe"
chk "$PREFIX/drive_c/Program Files/Siemens/Solid Edge 2026/Program/render.dll" "render.dll"
chk "$PREFIX/drive_c/Program Files/Siemens/Solid Edge 2026/Program/D3DGLST.dll" "D3DGLST.dll"
[ -f "$LOG_DIR/install.log" ] && grep -cE "Installation success|Installation failed|Return value 3" "$LOG_DIR/install.log" 2>/dev/null | sed 's/^/  install.log matches: /'
exit "$FAIL"
