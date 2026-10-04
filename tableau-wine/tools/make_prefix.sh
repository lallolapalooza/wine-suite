#!/bin/bash
# Build the Tableau Wine prefix from scratch, with the fixups the sibling projects proved necessary.
#
#   tools/make_prefix.sh [prefix_dir]        (default: $TABLEAU/prefix/tableau)
#
# Carries over, from the AutoCAD/Power BI work:
#   * the real Segoe UI / Arial / Calibri fonts the UI asks for (share/fonts, 66 MB)
#   * the WinRT metadata set (.winmd) at drive_c/windows/system32/WinMetadata (share/winmd, 114 files)
#   * win64 prefix, Wine's own reported Windows version left alone (setting win10 broke WebView2 for
#     Power BI; do not set it unless a measurement here says otherwise)
set -eu
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PREFIX=${1:-$ROOT/prefix/tableau}
WINE=${WINEBUILD:-$ROOT/wine-install/bin/wine}
FONTS=$ROOT/share/fonts
WINMD=$ROOT/share/winmd

[ -x "$WINE" ] || { echo "no wine at $WINE - build it first (tools/build_tableau.sh)"; exit 1; }
export WINEPREFIX=$PREFIX WINEARCH=win64
case "${2:-}" in
  --winver=*) export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-}"; WINVER_SET="${2#--winver=}";;
esac

if [ ! -d "$PREFIX" ]; then
    echo "== wineboot -u ($PREFIX)"
    "$WINE" wineboot -u
    "$ROOT/wine-install/bin/wineserver" -w 2>/dev/null || true
fi

SYS=$PREFIX/drive_c/windows
echo "== fonts -> $SYS/Fonts"
mkdir -p "$SYS/Fonts"
cp -n "$FONTS"/*.ttf "$SYS/Fonts/" 2>/dev/null || true
echo "   $(ls "$SYS/Fonts" | wc -l) font files"

echo "== WinRT metadata -> $SYS/system32/WinMetadata"
mkdir -p "$SYS/system32/WinMetadata"
cp -n "$WINMD"/*.winmd "$SYS/system32/WinMetadata/" 2>/dev/null || true
echo "   $(ls "$SYS/system32/WinMetadata" | wc -l) .winmd files"

if [ -n "${WINVER_SET:-}" ]; then
    echo "== setting reported Windows version to $WINVER_SET"
    "$WINE" reg add 'HKCU\Software\Wine' /v Version /t REG_SZ /d "$WINVER_SET" /f >/dev/null
else
    echo "== Windows version left at Wine default (unset HKCU\\Software\\Wine\\Version)"
fi

echo "OK prefix: $PREFIX"
