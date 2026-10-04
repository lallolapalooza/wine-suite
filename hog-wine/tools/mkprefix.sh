#!/bin/bash
# =============================================================================
# tools/mkprefix.sh — create the Hog PC Wine prefix and install the product
#
# usage: tools/mkprefix.sh [--prefix DIR] [--wine PATH] [--fresh] [--arch win32|win64]
#                         [--stage fonts|prereqs|hog|all] [--no-install]
# =============================================================================
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$ROOT/env.sh"

FRESH=0; NOINSTALL=0; STAGE=all; ARCH=win64
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) HW_PREFIX="$2"; shift 2 ;;
    --wine)   WINEBUILD="$2"; shift 2 ;;
    --fresh)  FRESH=1; shift ;;
    --arch)   ARCH="$2"; shift 2 ;;
    --no-install) NOINSTALL=1; shift ;;
    --stage)  STAGE="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

export WINEPREFIX="$HW_PREFIX"
export WINEARCH="$ARCH"
export DISPLAY="$DISP"
export WINEDEBUG="${WDBG:--all}"
export PATH="$(dirname "$WINEBUILD"):$PATH"
export TMPDIR="$HW_TMP"
mkdir -p "$HW_LOGS" "$HW_TMP" "$HW_LOGS/prefix"

say() { printf '\n== %s\n' "$*"; }

say "wine $($WINEBUILD --version 2>&1)"
say "prefix $WINEPREFIX (fresh=$FRESH arch=$ARCH stage=$STAGE)"
if [ "$FRESH" = 1 ] && [ -n "${WINEPREFIX:-}" ] && [ "$WINEPREFIX" != "/" ]; then rm -rf "$WINEPREFIX"; fi
mkdir -p "$WINEPREFIX"

say "wineboot -u"
"$WINEBUILD" wineboot -u > "$HW_LOGS/prefix/wineboot.log" 2>&1 || true
"$WINEBUILD" wineserver -w >/dev/null 2>&1 || true

# Vendor installers gate on the reported Windows version; Wine reads the two REG_DWORDs.
say "set Windows 10"
cv='HKLM\Software\Microsoft\Windows NT\CurrentVersion'
reg() { "$WINEBUILD" reg add "$cv" /v "$1" /t "$2" /d "$3" /f >>"$HW_LOGS/prefix/wineboot.log" 2>&1 || true; }
reg CurrentMajorVersionNumber REG_DWORD 10
reg CurrentMinorVersionNumber REG_DWORD 0
reg CurrentBuildNumber        REG_SZ    19045
reg CurrentBuild              REG_SZ    19045
reg CurrentVersion            REG_SZ    6.3
reg ProductName               REG_SZ    'Windows 10 Pro'

stage_fonts() {
  say "core fonts"
  if [ -x "$ROOT/tools/install_corefonts.sh" ]; then
    RW_TMP="$HW_TMP" "$ROOT/tools/install_corefonts.sh" --prefix "$WINEPREFIX" \
      > "$HW_LOGS/prefix/fonts.log" 2>&1 || echo "   (fonts not installed; see tools/install_corefonts.sh)"
  fi
}

stage_prereqs() {
  say "VC++ 2022 redists (if present in the media dir)"
  for r in VC_redist.x64.exe VC_redist.x86.exe; do
    [ -f "$HW_MEDIA/$r" ] && { "$WINEBUILD" "$HW_MEDIA/$r" /install /quiet /norestart \
        > "$HW_LOGS/prefix/$r.log" 2>&1; echo "   $r rc=$?"; }
  done
}

stage_hog() {
  say "Hog PC MSI (WiX, Intel/32-bit package)"
  [ -f "$HOG_MSI" ] || { echo "   no MSI at $HOG_MSI" >&2; return 1; }
  "$WINEBUILD" msiexec /i "$HOG_MSI" /qn /norestart /L*v "C:\\hog_msi.log" \
      > "$HW_LOGS/prefix/hog_stdout.log" 2>&1
  echo "   rc=$?"
  cp -a "$WINEPREFIX/drive_c/hog_msi.log" "$HW_LOGS/prefix/hog_msi.log" 2>/dev/null || true
}

case "$STAGE" in
  fonts)   stage_fonts ;;
  prereqs) stage_prereqs ;;
  hog)     stage_hog ;;
  all)     stage_fonts; stage_prereqs
           [ "$NOINSTALL" = 1 ] || stage_hog ;;
  *) echo "unknown stage: $STAGE" >&2; exit 2 ;;
esac

"$WINEBUILD" wineserver -w >/dev/null 2>&1 || true
say "result"
find "$WINEPREFIX/drive_c" -maxdepth 5 -type d -iname 'HogPC' 2>/dev/null
exit 0
