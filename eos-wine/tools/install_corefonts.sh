#!/bin/bash
# =============================================================================
# tools/install_corefonts.sh — install the fonts Arena requires into a Wine prefix
#
# WHY THIS IS NEEDED (measured, see FINDINGS.md M12):
#   Resolume Arena 7 enumerates *font families* and looks up ("Arial", "Regular") and
#   ("Verdana", "Regular"); the table lives at Arena.exe VA 0x142f4fa00 and is consumed by
#   0x140fd87f0.  With no Arial/Verdana installed, Wine substitutes them for CreateFont()
#   (GetTextFace -> "Liberation Sans") but does NOT report them from EnumFontFamiliesEx, so
#   the lookup fails and the app stops at
#       INFO: Enumerate fonts / INFO: Find default fonts / INFO: Default fonts not available
#   instead of continuing to "INFO: Create Application Object".
#   On Windows these fonts are part of the OS, so the app never hits this.
#
# WHAT IT DOES:
#   Copies a set of Windows core fonts (Arial, Verdana, Times New Roman, Courier New, Segoe UI,
#   Calibri, Consolas, ...) into <prefix>/drive_c/windows/Fonts.  Wine's font enumeration picks up
#   that directory, after which fontprobe.exe reports FOUND family "Arial"/"Verdana".
#
# FONT SOURCE:
#   The TTFs are taken from the *Windows guest that this project already uses as its reference*
#   (`C:\Windows\Fonts`, exported as corefonts.zip over the HTTP channel by `tools/vm/vmcmd.sh`).
#   They are not redistributed by this repository; supply your own licensed copies, e.g.
#     * copy them out of a licensed Windows installation (what this project did), or
#     * `winetricks corefonts` (downloads the Microsoft core fonts web packages), or
#     * any Arial/Verdana/Times/Courier that fontconfig can see.
#
# usage: tools/install_corefonts.sh [--prefix DIR] [--src DIR_OR_ZIP] [--check]
#   --src defaults to $RW/state/tmp/fonts, then $RW/vmshare/corefonts.zip
#   --check only runs the fontprobe and reports (needs wine-install/)
# =============================================================================
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$ROOT/env.sh"

SRC=""; CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) RW_PREFIX="$2"; shift 2 ;;
    --src)    SRC="$2"; shift 2 ;;
    --check)  CHECK=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

FONTDIR="$RW_PREFIX/drive_c/windows/Fonts"
TMP=$(mktemp -d "$RW_TMP/corefonts.XXXXXX")

say() { printf '\n== %s\n' "$*"; }

if [ "$CHECK" = 1 ]; then
  say "checking font enumeration in $RW_PREFIX"
  WINEPREFIX="$RW_PREFIX" DISPLAY="$DISP" "$WINEBUILD" "$ROOT/tools/winapi/fontprobe.exe" 2>&1 |
    grep -aE 'CreateFont\("(Arial|Verdana)|FOUND family "(Arial|Verdana)|total families'
  exit 0
fi

# resolve the font source
if [ -z "$SRC" ]; then
  if [ -d "$ROOT/state/tmp/fonts" ] && ls "$ROOT/state/tmp/fonts"/*.ttf >/dev/null 2>&1; then
    SRC="$ROOT/state/tmp/fonts"
  elif [ -f "$VM_SHARE/corefonts.zip" ]; then
    SRC="$VM_SHARE/corefonts.zip"
  fi
fi
[ -n "$SRC" ] && [ -e "$SRC" ] || {
  echo "no font source found: put the TTFs in state/tmp/fonts/ or a corefonts.zip in vmshare/" >&2
  echo "(see the FONT SOURCE note at the top of this script)" >&2
  exit 1
}

say "font source: $SRC"
if [ -f "$SRC" ]; then
  case "$SRC" in
    *.zip) unzip -o -q "$SRC" -d "$TMP" ;;
    *)     echo "unsupported archive: $SRC" >&2; exit 1 ;;
  esac
  SRCDIR="$TMP"
else
  SRCDIR="$SRC"
fi

say "installing into $FONTDIR"
mkdir -p "$FONTDIR"
n=0
for f in "$SRCDIR"/*.ttf "$SRCDIR"/*.TTF "$SRCDIR"/*.otf; do
  [ -f "$f" ] || continue
  cp -f "$f" "$FONTDIR/" && n=$((n + 1))
done
echo "  copied $n font files"
ls "$FONTDIR" | head -25

if [ -x "$ROOT/tools/winapi/fontprobe.exe" ]; then
  say "verifying with fontprobe"
  WINEPREFIX="$RW_PREFIX" DISPLAY="$DISP" "$WINEBUILD" "$ROOT/tools/winapi/fontprobe.exe" 2>&1 |
    grep -aE 'CreateFont\("(Arial|Verdana)|FOUND family "(Arial|Verdana)|total families' |
    sort -u | head -12
fi

rm -rf "$TMP"
say "done"
