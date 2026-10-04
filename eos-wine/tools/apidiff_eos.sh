#!/bin/bash
# Produce the Wine-vs-Windows API diff for Eos.exe from the two tracer logs.
#
#   logs/api/win_eos.log   Windows reference (guest, tools/apitrace with tools/apitrace/eos.cfg)
#   logs/api/wine_eos.log  Wine (tools/run_apitrace_eos.sh with the same cfg)
#   logs/api/wine_eos.relay.log  optional scoped WINEDEBUG=+relay capture (decoded names)
#
# Outputs, all under logs/api/:
#   diff.txt        relaydiff.py diff (call sequences present on one side only + per-function table)
#   retvals.txt     api_retval_diff.py retvals (return values that differ per argument tuple)
#   win.tail.txt / wine.tail.txt   last 200 calls of each side, with return values
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
D=logs/api
CFG=tools/apitrace/eos.cfg
WIN=${1:-$D/win_eos.log}
WINE=${2:-$D/wine_eos.log}
[ -f "$WIN" ] || { echo "missing Windows log: $WIN" >&2; exit 1; }
[ -f "$WINE" ] || { echo "missing Wine log: $WINE" >&2; exit 1; }

echo "== relaydiff.py diff =="
python3 tools/relaydiff.py diff "$WIN" "$WINE" --max-report 400 --func-limit 200 > "$D/diff.txt"
wc -l "$D/diff.txt"

echo "== api_retval_diff.py retvals =="
python3 tools/api_retval_diff.py retvals "$WIN" "$WINE" --cfg "$CFG" --max-report 400 > "$D/retvals.txt"
wc -l "$D/retvals.txt"

echo "== tails =="
python3 tools/api_retval_diff.py tail "$WIN" 200 --cfg "$CFG" > "$D/win.tail.txt"
python3 tools/api_retval_diff.py tail "$WINE" 200 --cfg "$CFG" > "$D/wine.tail.txt"
python3 tools/api_retval_diff.py tail "$WIN" 200 --cfg "$CFG" --fail > "$D/win.tail_fail.txt"
python3 tools/api_retval_diff.py tail "$WINE" 200 --cfg "$CFG" --fail > "$D/wine.tail_fail.txt"
wc -l "$D/win.tail.txt" "$D/wine.tail.txt" "$D/win.tail_fail.txt" "$D/wine.tail_fail.txt"
