#!/bin/bash
# Run the Windows-side ApiTracer (tools/apitrace) against Eos.exe under this project's Wine,
# then copy the tracer log back to logs/api/.
#
# usage: tools/run_apitrace_eos.sh <tag> [--secs N] [--cfg F] [--target EXE] [--debug SPEC]
#                                  [--prefix DIR] [--wine PATH] [--apitrace DIR]
#
# The tracer + apihook.dll must already be staged inside the prefix (see docs/API_DIFF.md);
# this script does not copy them.
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$ROOT/env.sh"

TAG=""; SECS=20; CFG='C:\apitrace\eos.cfg'; TARGET='Eos.exe'; WDBG=""
APIDIR='C:\apitrace'; APILINUX=""
while [ $# -gt 0 ]; do
  case "$1" in
    --secs)    SECS="$2"; shift 2 ;;
    --cfg)     CFG="$2"; shift 2 ;;
    --target)  TARGET="$2"; shift 2 ;;
    --debug)   WDBG="$2"; shift 2 ;;
    --prefix)  EW_PREFIX="$2"; shift 2 ;;
    --wine)    WINEBUILD="$2"; shift 2 ;;
    --apitrace) APIDIR="$2"; shift 2 ;;
    --)        shift; break ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *)         TAG="$1"; shift ;;
  esac
done
[ -n "$TAG" ] || { sed -n '2,4p' "$0" >&2; exit 2; }

export WINEPREFIX=$(readlink -f "$EW_PREFIX")
export DISPLAY="$DISP"
APP_DIR="$WINEPREFIX/drive_c/Program Files/ETC/EosFamily/v3/Eos"
APILINUX="$WINEPREFIX/drive_c/apitrace"
OUTWIN="$APIDIR\\${TAG}.log"
OUTLINUX="$APILINUX/${TAG}.log"
D="$EW_LOGS/api"; mkdir -p "$D"
[ -x "$WINEBUILD" ] || { echo "no wine at $WINEBUILD" >&2; exit 1; }
[ -f "$APP_DIR/$TARGET" ] || { echo "$TARGET not installed in $WINEPREFIX" >&2; exit 1; }
[ -f "$APILINUX/apitrace.exe" ] || { echo "apitrace.exe not staged in $APILINUX" >&2; exit 1; }

export PATH="$(dirname "$WINEBUILD"):$PATH"
export TMPDIR="${TMPDIR:-$EW_TMP}"
if [ -n "$WDBG" ]; then export WINEDEBUG="$WDBG"; else unset WINEDEBUG; fi

cd "$APP_DIR" || exit 1
# Eos enforces a single instance; a leftover instance makes the traced launch exit in ~2 s.
for p in $(pgrep -f -- 'Eos.exe' 2>/dev/null); do
  grep -qa "WINEPREFIX=$WINEPREFIX" /proc/$p/environ 2>/dev/null && kill -9 "$p" 2>/dev/null
done
sleep 1
echo "start $(date +%T) tag=$TAG prefix=$WINEPREFIX secs=$SECS cfg=$CFG target=$TARGET debug=${WDBG:-<default>}"
timeout $((SECS + 60)) "$WINEBUILD" "$APIDIR\\apitrace.exe" \
    --cfg "$CFG" --out "$OUTWIN" --timeout "$SECS" -- "$TARGET" \
    > "$D/${TAG}.stderr" 2>&1
rc=$?
echo "wine rc=$rc"
cp -f "$OUTLINUX" "$D/${TAG}.log" 2>/dev/null || echo "no tracer log at $OUTLINUX" >&2
wc -l "$D/${TAG}.log" 2>/dev/null
echo "end $(date +%T)"
