#!/bin/bash
# =============================================================================
# tools/deploy_webview2.sh — put a WebView2 runtime into a Wine prefix
#
# usage: tools/deploy_webview2.sh <zip|dir> [prefix] [--version X.Y.Z.W]
#        tools/deploy_webview2.sh --from-guest [prefix]
#
# Solid Edge's control.dll imports WebView2Loader.dll, and Microsoft's Evergreen installer
# (which the media bundles) is an Edge updater that does not run under Wine.  Two placement
# mechanisms are used together, because either can be what WebView2Loader picks up:
#
#   1. the evergreen path  <prefix>/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application/<version>/
#   2. HKCU\Environment WEBVIEW2_BROWSER_EXECUTABLE_FOLDER pointing at it (read by the loader
#      before the registry and by out-of-process Chromium helpers)
#
# `--from-guest` harvests the runtime out of the Windows guest (which has one installed) through
# the vmshare channel: zip it in the guest with tar.exe, upload with curl -T, unpack here.
#
# Logs: $SE_LOGS/webview2/
# =============================================================================
set -eu
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$ROOT/env.sh"

SRC=""
PREFIX="$SE_PREFIX"
EXPLICIT_VER=""
FROM_GUEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --from-guest) FROM_GUEST=1; shift ;;
    --version)    EXPLICIT_VER="$2"; shift 2 ;;
    -h|--help)    sed -n '2,20p' "$0"; exit 0 ;;
    *) if [ -z "$SRC" ]; then SRC="$1"; else PREFIX="$1"; fi; shift ;;
  esac
done
mkdir -p "$SE_LOGS/webview2"

if [ "$FROM_GUEST" = 1 ]; then
  SRC="$SE_LOGS/webview2/wv2.zip"
  if [ ! -s "$SRC" ]; then
    echo "== harvesting the runtime from the Windows guest"
    "$ROOT/tools/vm/vmcmd.sh" '
      $d = Get-ChildItem "C:\Program Files (x86)\Microsoft\EdgeWebView\Application" -Directory |
           Where-Object { Test-Path (Join-Path $_.FullName "msedgewebview2.exe") } |
           Sort-Object Name -Descending | Select-Object -First 1
      "GUEST_RUNTIME_DIR=" + $d.FullName
      if (Test-Path C:\seprobe\wv2.zip) { Remove-Item C:\seprobe\wv2.zip -Force }
      tar.exe -a -c -f C:\seprobe\wv2.zip -C $d.FullName .
      "ZIPSIZE=" + (Get-Item C:\seprobe\wv2.zip).Length
      curl.exe -s -T C:\seprobe\wv2.zip http://192.168.122.1:8000/wv2.zip
    ' 240
    cp "$ROOT/vmshare/wv2.zip" "$SRC" 2>/dev/null || true
  fi
  [ -s "$SRC" ] || { echo "could not harvest the runtime from the guest" >&2; exit 1; }
fi
[ -n "$SRC" ] || { sed -n '2,20p' "$0" >&2; exit 2; }

WORK="$SE_WORK/webview2"; rm -rf "$WORK"; mkdir -p "$WORK/tree"
echo "== unpacking $SRC"
if [ -d "$SRC" ]; then cp -a "$SRC"/. "$WORK/tree"/; else 7z x -y "$SRC" -o"$WORK/tree" >/dev/null; fi
EXE=$(find "$WORK/tree" -maxdepth 3 -iname msedgewebview2.exe -print -quit)
[ -n "$EXE" ] || { echo "no msedgewebview2.exe under $WORK/tree" >&2; find "$WORK/tree" -maxdepth 2 | head -20 >&2; exit 1; }
SRCDIR=$(dirname "$EXE")
if [ -n "$EXPLICIT_VER" ]; then
  VER="$EXPLICIT_VER"
else
  m=$(find "$SRCDIR" -maxdepth 1 -name '[0-9]*.[0-9]*.[0-9]*.[0-9]*.manifest' -print -quit 2>/dev/null || true)
  if [ -n "$m" ]; then VER=$(basename "$m" .manifest); else VER=$(basename "$SRCDIR"); fi
fi
case "$VER" in [0-9]*.[0-9]*) ;; *) echo "warning: '$VER' does not look like a version" >&2 ;; esac

DEST="$PREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application/$VER"
echo "runtime dir : $SRCDIR"
echo "destination : $DEST  (version $VER)"
mkdir -p "$DEST"
cp -a "$SRCDIR"/. "$DEST"/

echo "== registry"
WINE="$WINEPREFIX_INSTALL/bin/wine"
WINEPREFIX="$PREFIX" DISPLAY="${DISP:-:2}" "$WINE" reg add 'HKCU\Environment' \
    /v WEBVIEW2_BROWSER_EXECUTABLE_FOLDER /t REG_SZ /d "C:\\Program Files (x86)\\Microsoft\\EdgeWebView\\Application\\$VER" /f >/dev/null
echo "  HKCU\\Environment WEBVIEW2_BROWSER_EXECUTABLE_FOLDER = C:\\Program Files (x86)\\Microsoft\\EdgeWebView\\Application\\$VER"
echo
echo "== result"
ls -la "$DEST/msedgewebview2.exe" && echo "  [ ok ] runtime deployed"
