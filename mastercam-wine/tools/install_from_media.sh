#!/bin/bash
# Fallback install path: place the already-extracted vendor payload into the Wine prefix,
# bypassing the Inno installer and its prerequisite stage ([Code] runs Bonjour/VC++/Vulkan).
#
# The layout comes from notes/installer.md: {app} = C:\Program Files\Resolume Arena,
# {pf}\Resolume Wire and {pf}\Resolume Alley.
#
# usage: tools/install_from_media.sh [--prefix DIR] [--dest DIR]
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$ROOT/env.sh"

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) RW_PREFIX="$2"; shift 2 ;;
    --dest)   DEST="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

MEDIA="$RES_MEDIA"
[ -d "$MEDIA/app" ] || { echo "no extracted payload at $MEDIA (run innoextract)" >&2; exit 1; }
PF="$RW_PREFIX/drive_c/Program Files"
[ -d "$PF" ] || { echo "no prefix at $RW_PREFIX" >&2; exit 1; }

echo "== copying app/ -> $PF/Resolume Arena"
mkdir -p "$PF/Resolume Arena"
cp -a "$MEDIA/app/." "$PF/Resolume Arena/"

echo "== copying pf/"
for d in "$MEDIA"/pf/*/; do
  n=$(basename "$d")
  echo "   $n"
  mkdir -p "$PF/$n"
  cp -a "$d." "$PF/$n/"
done

echo "== installing VC++ runtime DLLs the payload ships for FFmpeg (if the app dir lacks them)"
# app/ ships no msvcp140/vcruntime140 although everything imports them; the FFmpeg temp copy has
# vcruntime140/vcruntime140_1/msvcp140 which the installer's VC_redist step would provide system-wide.
for f in msvcp140.dll vcruntime140.dll vcruntime140_1.dll; do
  if [ -f "$MEDIA/tmp/ffmpeg/$f" ] && [ ! -f "$PF/Resolume Arena/$f" ]; then
    cp -a "$MEDIA/tmp/ffmpeg/$f" "$PF/Resolume Arena/$f"
    echo "   $f"
  fi
done

echo "== done"
ls -la "$PF/Resolume Arena/Arena.exe" 2>/dev/null
