#!/bin/bash
# =============================================================================
# tools/mkprefix.sh — create the Mastercam-2027 Wine prefix and install the product
#
# usage: tools/mkprefix.sh [--prefix DIR] [--wine PATH] [--fresh]
#                         [--stage fonts|prereqs|licensing|mastercam|all] [--no-install]
#
# Stages (any order, all idempotent):
#   fonts      core fonts into the prefix (Wine does not enumerate Arial/Verdana otherwise)
#   prereqs    VC++ 2022 x64, msxml6 x64, .NET Framework 4.8        (from $MCW_MEDIA)
#   licensing  CodeMeter Runtime + Mastercam Licensing Utilities    (from $MCW_MEDIA)
#   mastercam  the product MSI itself
#
# The product MSI is 64-bit-only (Template AMD64) and ~3.3 GiB installed; it expects
# INSTALLDIR=...\Mastercam 2027 (datapaths.ini) and the en-US transform 1033.mst.
# =============================================================================
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$ROOT/env.sh"

FRESH=0; NOINSTALL=0; STAGE=all
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) MCW_PREFIX="$2"; shift 2 ;;
    --wine)   WINEBUILD="$2"; shift 2 ;;
    --fresh)  FRESH=1; shift ;;
    --no-install) NOINSTALL=1; shift ;;
    --stage)  STAGE="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

export WINEPREFIX="$MCW_PREFIX"
export WINEARCH=win64
export DISPLAY="$DISP"
export WINEDEBUG="${WDBG:--all}"
export PATH="$(dirname "$WINEBUILD"):$PATH"
export TMPDIR="$MCW_TMP"
mkdir -p "$MCW_LOGS" "$MCW_TMP" "$MCW_LOGS/prefix"

M="$MCW_MEDIA"
say() { printf '\n== %s\n' "$*"; }
w() { printf '   $ %s\n' "$*"; "$@" ; }

say "wine $($WINEBUILD --version 2>&1)"
say "prefix $WINEPREFIX (fresh=$FRESH, stage=$STAGE)"
if [ "$FRESH" = 1 ] && [ -n "${WINEPREFIX:-}" ] && [ "$WINEPREFIX" != "/" ]; then rm -rf "$WINEPREFIX"; fi
mkdir -p "$WINEPREFIX"

say "wineboot -u"
"$WINEBUILD" wineboot -u > "$MCW_LOGS/prefix/wineboot.log" 2>&1 || true
"$WINEBUILD" wineserver -w >/dev/null 2>&1 || true

say "set Windows 10"
# Wine reports the Windows version from CurrentMajorVersionNumber/CurrentMinorVersionNumber
# (REG_DWORD) when they exist; the CurrentVersion string alone is ignored.  Setting only the
# string leaves a win64 prefix reporting Windows 7 SP1 (6.1.7601), which trips installer OS
# guards such as CodeMeter's CA_OSBelowWinVerX.  (winecfg -v win10 writes 10/0 plus the 6.3
# compat string; we set the DWORDs directly so this works headless.)
cv='HKLM\Software\Microsoft\Windows NT\CurrentVersion'
"$WINEBUILD" reg add "$cv" /v CurrentMajorVersionNumber /t REG_DWORD /d 10        /f >>"$MCW_LOGS/prefix/wineboot.log" 2>&1 || true
"$WINEBUILD" reg add "$cv" /v CurrentMinorVersionNumber /t REG_DWORD /d 0         /f >>"$MCW_LOGS/prefix/wineboot.log" 2>&1 || true
"$WINEBUILD" reg add "$cv" /v CurrentBuildNumber       /t REG_SZ    /d 19045     /f >>"$MCW_LOGS/prefix/wineboot.log" 2>&1 || true
"$WINEBUILD" reg add "$cv" /v CurrentBuild             /t REG_SZ    /d 19045     /f >>"$MCW_LOGS/prefix/wineboot.log" 2>&1 || true
"$WINEBUILD" reg add "$cv" /v CurrentVersion           /t REG_SZ    /d 6.3       /f >>"$MCW_LOGS/prefix/wineboot.log" 2>&1 || true
"$WINEBUILD" reg add "$cv" /v ProductName             /t REG_SZ    /d 'Windows 10 Pro' /f >>"$MCW_LOGS/prefix/wineboot.log" 2>&1 || true

stage_fonts() {
  say "core fonts"
  if [ -x "$ROOT/tools/install_corefonts.sh" ]; then
    # install_corefonts.sh expects resolume's RW_TMP/RW_PREFIX names, which this project's
    # env.sh does not define; pass RW_TMP or it tries `mktemp -d /corefonts.XXXXXX`.
    RW_TMP="$MCW_TMP" "$ROOT/tools/install_corefonts.sh" --prefix "$WINEPREFIX" \
      > "$MCW_LOGS/prefix/fonts.log" 2>&1 \
      || echo "   (fonts not installed; see tools/install_corefonts.sh)"
  fi
}

stage_prereqs() {
  say "VC++ 2022 x64"
  [ -f "$M/SetupPrerequisites/VC2022/VC_redist.x64.exe" ] && \
    "$WINEBUILD" "$M/SetupPrerequisites/VC2022/VC_redist.x64.exe" /install /quiet /norestart \
      > "$MCW_LOGS/prefix/vcredist.log" 2>&1; echo "   rc=$?"
  say "msxml6 x64"
  [ -f "$M/SetupPrerequisites/msxml6_x64.msi" ] && \
    "$WINEBUILD" msiexec /i "$M/SetupPrerequisites/msxml6_x64.msi" /qn /norestart \
      > "$MCW_LOGS/prefix/msxml6.log" 2>&1; echo "   rc=$?"
  say ".NET Framework 4.8"
  if [ -f "$M/SetupPrerequisites/ndp48-x86-x64-allos-enu.exe" ]; then
    "$WINEBUILD" "$M/SetupPrerequisites/ndp48-x86-x64-allos-enu.exe" /q /norestart \
      > "$MCW_LOGS/prefix/ndp48.log" 2>&1; echo "   rc=$?"
  fi
}

stage_licensing() {
  say "CodeMeter Runtime"
  [ -f "$M/SetupPrerequisites/CodeMeterRuntime64.msi" ] && \
    "$WINEBUILD" msiexec /i "$M/SetupPrerequisites/CodeMeterRuntime64.msi" /qn /norestart \
      > "$MCW_LOGS/prefix/codemeter.log" 2>&1; echo "   rc=$?"
  say "Mastercam Licensing Utilities"
  if [ -f "$M/SetupPrerequisites/MastercamLicensing/MastercamLicensingSetup.exe" ]; then
    "$WINEBUILD" "$M/SetupPrerequisites/MastercamLicensing/MastercamLicensingSetup.exe" /s \
      > "$MCW_LOGS/prefix/mclicensing.log" 2>&1; echo "   rc=$?"
  fi
}

stage_mastercam() {
  say "Mastercam product MSI"
  local msi="$M/mastercam/Mastercam_Installer.msi"
  local mst="$M/mastercam/1033.mst"
  [ -f "$msi" ] || { echo "   no MSI at $msi" >&2; return 1; }
  local args=(msiexec /i "$msi")
  [ -f "$mst" ] && args+=(TRANSFORMS="$mst")
  args+=(INSTALLDIR='C:\Program Files\Mastercam 2027'
         SHAREDDEFAULTS='C:\ProgramData\Mastercam'
         CNC_UNIT_TYPE=I REBOOT=ReallySuppress /qn /norestart
         /L*v "$MCW_LOGS/prefix/mastercam_msi.log")
  w "$WINEBUILD" "${args[@]}" > "$MCW_LOGS/prefix/mastercam_stdout.log" 2>&1; echo "   rc=$?"
}

case "$STAGE" in
  fonts)     stage_fonts ;;
  prereqs)   stage_prereqs ;;
  licensing) stage_licensing ;;
  mastercam) stage_mastercam ;;
  all)       stage_fonts; stage_prereqs
             [ "$NOINSTALL" = 1 ] || { stage_licensing; stage_mastercam; } ;;
  *) echo "unknown stage: $STAGE" >&2; exit 2 ;;
esac

"$WINEBUILD" wineserver -w >/dev/null 2>&1 || true
say "result"
ls -la "$WINEPREFIX/drive_c/Program Files/Mastercam 2027" 2>/dev/null | head -20 || echo "   (not installed yet)"
exit 0
