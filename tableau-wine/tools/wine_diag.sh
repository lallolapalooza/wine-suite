#!/bin/bash
# Run a Windows program under the project Wine build with diagnostics that actually help.
#
#   tools/wine_diag.sh <tag> <exe-win-path> [seconds]     # default channels: err+warn+seh
#   CHANNELS='+relay,+seh' tools/wine_diag.sh ...
#
# Notes learned from the sibling projects:
#   * `+relay` on a Qt/Chromium app produces gigabytes in seconds. Narrow it with the Wine registry
#     keys RelayInclude/RelayExclude instead of grepping afterwards:
#       wine reg add 'HKCU\Software\Wine\Debug' /v RelayInclude /t REG_SZ /d 'ntdll,kernelbase,secur32' /f
#     (clear with: wine reg delete 'HKCU\Software\Wine\Debug' /v RelayInclude /f)
#   * Wine's own `err:`/`fixme:` lines and the crash backtrace are the first evidence; the app's own log
#     (see recon/TABLEAU_STACK.md for its path) is the second.
# Output: logs/diag-<tag>/stderr.log, tail.txt, errs.txt, backtrace.txt
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TAG=${1:?usage: wine_diag.sh <tag> <exe> [seconds]}
EXE=${2:?exe}
SECS=${3:-300}
CHANNELS=${CHANNELS:-err+all,fixme-all,seh}
OUT=$ROOT/logs/diag-$TAG
mkdir -p "$OUT"

export WINEPREFIX=${PREFIX:-$ROOT/prefix/tableau}
export DISPLAY=${DISP:-:11}
export WINE=${WINE:-$ROOT/wine-install/bin/wine}
[ -x "$WINE" ] || { echo "no wine at $WINE"; exit 1; }

echo "wine=$WINE prefix=$WINEPREFIX exe=$EXE channels=$CHANNELS $(date -Is)" | tee "$OUT/cmd.txt"
WINEDEBUG="$CHANNELS" timeout "$SECS" "$WINE" "$EXE" >"$OUT/stderr.log" 2>&1
rc=$?
echo "rc=$rc (124 = timeout reached, i.e. the app was still alive)" | tee -a "$OUT/cmd.txt"

wc -l "$OUT/stderr.log"
echo "== last 40 lines" | tee "$OUT/tail.txt"
tail -40 "$OUT/stderr.log" >>"$OUT/tail.txt"
echo "== err:/warn: lines (deduped, top 60 by count)" >"$OUT/errs.txt"
grep -E '^(err|warn):' "$OUT/stderr.log" | sed 's/[0-9a-f]\{8,\}/HEX/g' | sort | uniq -c | sort -rn | head -60 >>"$OUT/errs.txt"
echo "== backtrace candidates" >"$OUT/backtrace.txt"
grep -n -E 'Backtrace|Unhandled exception|0x[0-9a-f]+: ' "$OUT/stderr.log" | tail -60 >>"$OUT/backtrace.txt"
sed -n '1,25p' "$OUT/errs.txt"
exit 0
