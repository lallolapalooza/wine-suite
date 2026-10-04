#!/bin/bash
# Run the Wine-vs-Windows API diff for the Hog PC start-up.
#
# Inputs (all in logs/api/): wine_hog*.log (32-bit IAT tracer under Wine, §2.2),
# win_hog*.log (same tracer on Windows, §2.4), wine_hog*.relay.log (scoped +relay
# with return values, §2.3).
#
# Emits, per process role, the sequence diff and per-function counts, plus the
# Wine failure/fixme summary.  Same-role logs only — the launcher, server and
# desktop legitimately make different calls, so cross-role diffs are noise.
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
D="$ROOT/logs/api"
R="$ROOT/tools/relaydiff.py"
OUT="$D/hog_apidiff.txt"
: > "$OUT"

for role in "" _server _desktop; do
  case "$role" in
    "") w="$D/wine_hog.log";  n="$D/win_hog.log" ;;
    *)  w="$D/wine_hog$role.log"; n="$D/win_hog$role.log" ;;
  esac
  [ -f "$w" ] || continue
  echo "################################################################" >> "$OUT"
  echo "### role=${role:-launcher}   wine=$(basename "$w")  win=$(basename "$n")" >> "$OUT"
  echo "################################################################" >> "$OUT"
  if [ -f "$n" ]; then
    python3 "$R" diff "$n" "$w" --max-report 400 --func-limit 250 >> "$OUT" 2>&1
  else
    echo "(no Windows log for this role: $n)" >> "$OUT"
  fi
  echo >> "$OUT"
done

for t in wine_hog_launcher wine_hog_server; do
  [ -f "$D/$t.relay.log" ] || continue
  echo "################################################################" >> "$OUT"
  echo "### relay errors: $t" >> "$OUT"
  echo "################################################################" >> "$OUT"
  python3 "$R" wine-log --errors --top 40 "$D/$t.relay.log" >> "$OUT" 2>&1
  echo >> "$OUT"
done

echo "wrote $OUT"
grep -c . "$OUT"
