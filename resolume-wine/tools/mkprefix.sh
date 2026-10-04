#!/bin/bash
# =============================================================================
# tools/mkprefix.sh — create the Resolume Wine prefix and run the vendor installer
#
# usage: tools/mkprefix.sh [--prefix DIR] [--wine PATH] [--fresh] [--no-install]
#
# Wine wiki practice:
#   * WINEARCH=win64, a 64-bit prefix (Arena.exe is PE32+ x86-64);
#   * the window version set to Windows 10 (Resolume 7 requires Win10+);
#   * the install is the vendor's own Inno Setup silently:
#       ResolumeArena7_Installer.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /ALLUSERS
#   * the prerequisites the installer would run (VC++ 2022, Vulkan runtime, Bonjour) are
#     installed explicitly from the same payload so a failure is attributable.
# =============================================================================
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$ROOT/env.sh"

FRESH=0; NOINSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) RW_PREFIX="$2"; shift 2 ;;
    --wine)   WINEBUILD="$2"; shift 2 ;;
    --fresh)  FRESH=1; shift ;;
    --no-install) NOINSTALL=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

export WINEPREFIX="$RW_PREFIX"
export WINEARCH=win64
export DISPLAY="$DISP"
export WINEDEBUG="${WDBG:--all}"
export PATH="$(dirname "$WINEBUILD"):$PATH"
export TMPDIR="$RW_TMP"
mkdir -p "$RW_LOGS" "$RW_TMP"

say() { printf '\n== %s\n' "$*"; }

say "wine $($WINEBUILD --version 2>&1)"
say "prefix $WINEPREFIX (fresh=$FRESH)"
if [ "$FRESH" = 1 ] && [ -n "${WINEPREFIX:-}" ] && [ "$WINEPREFIX" != "/" ]; then
  rm -rf "$WINEPREFIX"
fi
mkdir -p "$WINEPREFIX"

say "wineboot -u"
"$WINEBUILD" wineboot -u > "$RW_LOGS/mkprefix_wineboot.log" 2>&1 || true
"$WINEBUILD" wineserver -w >/dev/null 2>&1 || true

say "set Windows 10"
"$WINEBUILD" reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' /v CurrentVersion /d 10.0 /f >>"$RW_LOGS/mkprefix_wineboot.log" 2>&1 || true
"$WINEBUILD" reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' /v CurrentBuildNumber /d 19045 /f >>"$RW_LOGS/mkprefix_wineboot.log" 2>&1 || true
"$WINEBUILD" reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' /v ProductName /d 'Windows 10 Pro' /f >>"$RW_LOGS/mkprefix_wineboot.log" 2>&1 || true
"$WINEBUILD" reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' /v CurrentBuild /d 19045 /f >>"$RW_LOGS/mkprefix_wineboot.log" 2>&1 || true
"$WINEBUILD" reg add 'HKLM\System\CurrentControlSet\Control\Windows' /v CSDVersion /d 0 /f >>"$RW_LOGS/mkprefix_wineboot.log" 2>&1 || true

say "prerequisites from the payload"
# Arena enumerates font families for Arial/Verdana and refuses to start without them; Wine does not
# report them unless the fonts are installed in the prefix (see FINDINGS M12).
if [ -f "$ROOT/tools/install_corefonts.sh" ]; then
  echo "  core fonts (Arial/Verdana/... required by Arena)"
  "$ROOT/tools/install_corefonts.sh" --prefix "$WINEPREFIX" > "$RW_LOGS/mkprefix_fonts.log" 2>&1 \
    || echo "  (fonts not installed; put TTFs in state/tmp/fonts/ — see tools/install_corefonts.sh)"
fi
VC="$RES_MEDIA/tmp/VC_redist_2022.x64.exe"
VK="$RES_MEDIA/tmp/vulkan-runtime.exe"
if [ -f "$VC" ]; then
  echo "  VC++ 2022 redist"
  "$WINEBUILD" "$VC" /install /quiet /norestart > "$RW_LOGS/mkprefix_vcredist.log" 2>&1 || echo "  (vc redist rc=$?)"
fi
if [ -f "$VK" ]; then
  echo "  Vulkan runtime"
  "$WINEBUILD" "$VK" /S > "$RW_LOGS/mkprefix_vulkan.log" 2>&1 || echo "  (vulkan rc=$?)"
fi

if [ "$NOINSTALL" = 1 ]; then
  say "skipping install (--no-install)"; exit 0
fi

say "vendor installer (silent)"
INS="${RW_INSTALLER:-}"
[ -n "$INS" ] && [ -f "$INS" ] || INS="$RES_INSTALLER"
if [ ! -f "$INS" ]; then echo "no installer found" >&2; exit 1; fi
"$WINEBUILD" "$INS" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /ALLUSERS \
  > "$RW_LOGS/mkprefix_install.log" 2>&1
rc=$?
echo "  installer rc=$rc"
"$WINEBUILD" wineserver -w >/dev/null 2>&1 || true

say "result"
ls -la "$WINEPREFIX/drive_c/Program Files/Resolume Arena/" 2>/dev/null | head -20
exit 0
