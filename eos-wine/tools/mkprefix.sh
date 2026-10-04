#!/bin/bash
# =============================================================================
# tools/mkprefix.sh — create the Eos Family Wine prefix and install the product
#
# usage: tools/mkprefix.sh [--prefix DIR] [--wine PATH] [--fresh]
#                         [--stage fonts|prereqs|eos|all] [--no-install]
# =============================================================================
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$ROOT/env.sh"

FRESH=0; NOINSTALL=0; STAGE=all
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) EW_PREFIX="$2"; shift 2 ;;
    --wine)   WINEBUILD="$2"; shift 2 ;;
    --fresh)  FRESH=1; shift ;;
    --no-install) NOINSTALL=1; shift ;;
    --stage)  STAGE="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

export WINEPREFIX="$EW_PREFIX"
export WINEARCH=win64
export DISPLAY="$DISP"
export WINEDEBUG="${WDBG:--all}"
export PATH="$(dirname "$WINEBUILD"):$PATH"
export TMPDIR="$EW_TMP"
mkdir -p "$EW_LOGS" "$EW_TMP" "$EW_LOGS/prefix"

MED="$EW_MEDIA/msi/\$PLUGINSDIR"
say() { printf '\n== %s\n' "$*"; }

say "wine $($WINEBUILD --version 2>&1)"
say "prefix $WINEPREFIX (fresh=$FRESH, stage=$STAGE)"
if [ "$FRESH" = 1 ] && [ -n "${WINEPREFIX:-}" ] && [ "$WINEPREFIX" != "/" ]; then rm -rf "$WINEPREFIX"; fi
mkdir -p "$WINEPREFIX"

say "wineboot -u"
"$WINEBUILD" wineboot -u > "$EW_LOGS/prefix/wineboot.log" 2>&1 || true
"$WINEBUILD" wineserver -w >/dev/null 2>&1 || true

# Wine reports the Windows version from CurrentMajorVersionNumber/CurrentMinorVersionNumber
# (REG_DWORD) when they exist; the CurrentVersion string alone is ignored.  Several vendor
# installers gate on this (the Mastercam project hit CodeMeter's CA_OSBelowWinVerX).
say "set Windows 10"
cv='HKLM\Software\Microsoft\Windows NT\CurrentVersion'
reg() { "$WINEBUILD" reg add "$cv" /v "$1" /t "$2" /d "$3" /f >>"$EW_LOGS/prefix/wineboot.log" 2>&1 || true; }
reg CurrentMajorVersionNumber REG_DWORD 10
reg CurrentMinorVersionNumber REG_DWORD 0
reg CurrentBuildNumber        REG_SZ    19045
reg CurrentBuild              REG_SZ    19045
reg CurrentVersion            REG_SZ    6.3
reg ProductName               REG_SZ    'Windows 10 Pro'
reg CSDVersion                REG_SZ    ''

stage_fonts() {
  say "core fonts"
  if [ -x "$ROOT/tools/install_corefonts.sh" ]; then
    RW_TMP="$EW_TMP" "$ROOT/tools/install_corefonts.sh" --prefix "$WINEPREFIX" \
      > "$EW_LOGS/prefix/fonts.log" 2>&1 || echo "   (fonts not installed; see tools/install_corefonts.sh)"
  fi
}

stage_prereqs() {
  say "VC++ 2022 x64"
  [ -f "$MED/VC_redist.x64.exe" ] && { "$WINEBUILD" "$MED/VC_redist.x64.exe" /install /quiet /norestart \
      > "$EW_LOGS/prefix/vcredist64.log" 2>&1; echo "   rc=$?"; }
  say "VC++ 2022 x86"
  [ -f "$MED/VC_redist.x86.exe" ] && { "$WINEBUILD" "$MED/VC_redist.x86.exe" /install /quiet /norestart \
      > "$EW_LOGS/prefix/vcredist86.log" 2>&1; echo "   rc=$?"; }
}

stage_eos() {
  say "Eos Family product MSI (WiX, x64)"
  local msi="$MED/ETC_EosFamily_v3.3.10.28.msi"
  [ -f "$msi" ] || { echo "   no MSI at $msi" >&2; return 1; }
  "$WINEBUILD" msiexec /i "$msi" /qn /norestart \
      /L*v "C:\\eos_msi.log" > "$EW_LOGS/prefix/eos_stdout.log" 2>&1
  echo "   rc=$?"
  # keep the MSI log next to our own logs for evidence
  cp -a "$WINEPREFIX/drive_c/eos_msi.log" "$EW_LOGS/prefix/eos_msi.log" 2>/dev/null || true
}

case "$STAGE" in
  fonts)   stage_fonts ;;
  prereqs) stage_prereqs ;;
  eos)     stage_eos ;;
  all)     stage_fonts; stage_prereqs
           [ "$NOINSTALL" = 1 ] || stage_eos ;;
  *) echo "unknown stage: $STAGE" >&2; exit 2 ;;
esac

"$WINEBUILD" wineserver -w >/dev/null 2>&1 || true
say "result"
ls -la "$WINEPREFIX/drive_c/Program Files/Eos" 2>/dev/null | head -20 || echo "   (not installed yet)"
exit 0
