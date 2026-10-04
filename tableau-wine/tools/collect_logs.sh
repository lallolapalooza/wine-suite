#!/bin/bash
# Collect the app's own logs from BOTH platforms into one directory for diffing.
#
#   tools/collect_logs.sh <tag> [prefix]
#
# Wine side : logs/logs-<tag>/wine/   ($PREFIX/drive_c/users/*/**/Tableau/**, *.log/*.txt)
# Guest side: logs/logs-<tag>/win/    (guest runs tools/vm/tablogs.ps1, fetched from the :8000 hub)
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TAG=${1:?usage: collect_logs.sh <tag> [prefix]}
PREFIX=${2:-$ROOT/prefix/tableau}
OUT=$ROOT/logs/logs-$TAG
mkdir -p "$OUT/wine" "$OUT/win"

echo "== wine side"
if [ -d "$PREFIX/drive_c/users" ]; then
    find "$PREFIX/drive_c/users" -ipath '*Tableau*' \( -name '*.log' -o -name '*.txt' -o -name '*.json' \) \
        -size -20M -exec cp --parents {} "$OUT/wine/" \; 2>/dev/null || true
    echo "   $(find "$OUT/wine" -type f | wc -l) files"
else
    echo "   no prefix at $PREFIX"
fi

echo "== guest side"
# publish the guest script through the hub, then have the guest fetch and run it
cp "$ROOT/tools/vm/tablogs.ps1" "$ROOT/vmshare/tablogs.ps1"
rm -f "$ROOT/vmshare/tablogs.zip"
"$ROOT/tools/guest.sh" 'curl.exe -s -o $env:USERPROFILE\tablogs.ps1 http://192.168.122.1:8000/tablogs.ps1; & $env:USERPROFILE\tablogs.ps1' 180
if [ -s "$ROOT/vmshare/tablogs.zip" ]; then
    (cd "$OUT/win" && unzip -oq "$ROOT/vmshare/tablogs.zip")
    echo "   $(find "$OUT/win" -type f | wc -l) files"
else
    echo "   no tablogs.zip arrived through the hub"
fi

echo
echo "== largest logs"
find "$OUT" -type f -printf '%s %p\n' 2>/dev/null | sort -rn | head -12
echo
echo "log dir: $OUT"
