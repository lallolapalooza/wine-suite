#!/bin/bash
# Apply the state harvested from the real Windows install to the Wine prefix.
#
#   tools/apply_windows_state_wine.sh [harvest.zip] [prefix]
#
# Input: vmshare/tabharvest.zip produced by tools/vm/harvest.ps1 on the guest (service binaries,
#        C:\ProgramData\FLEXnet, `reg export`ed HKLM keys, file/service lists).
# This is the documented, reproducible way to give Wine the same install state the MSI creates when
# the Burn/MSI installer itself cannot be driven far enough under Wine.
set -eu
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ZIP=${1:-$ROOT/vmshare/tabharvest.zip}
PREFIX=${2:-$ROOT/prefix/tableau}
STAGE=$ROOT/state/harvest-win
WINE=${WINEBUILD:-$ROOT/wine-install/bin/wine}
export WINEPREFIX=$PREFIX
export WINEDEBUG=${WINEDEBUG:--all}

[ -f "$ZIP" ] || { echo "no harvest zip at $ZIP - run tools/vm/harvest.ps1 on the guest first"; exit 1; }
[ -d "$PREFIX" ] || { echo "no prefix at $PREFIX"; exit 1; }

rm -rf "$STAGE"; mkdir -p "$STAGE"
# The guest-produced zip uses backslash separators; unzip writes a warning and exits 1, but the
# tree still extracts correctly, so tolerate a nonzero status as long as the key dirs are there.
unzip -oq "$ZIP" -d "$STAGE" || true
for d in flexnet FLEXnet-data reg; do
    [ -e "$STAGE/$d" ] || { echo "harvest $ZIP is missing $d/ - wrong zip?"; exit 1; }
done
echo "== harvest contents:"; find "$STAGE" -maxdepth 2 | head -20

DC=$PREFIX/drive_c
COMMON="$DC/Program Files/Common Files/Macrovision Shared/FLEXnet Publisher"

# 1. licensing service binaries
if [ -d "$STAGE/flexnet" ]; then
    mkdir -p "$COMMON"
    cp -a "$STAGE/flexnet/." "$COMMON/"
    echo "== service binaries -> $COMMON"
else
    echo "!! no flexnet/ in the harvest (service may live elsewhere; check services.csv)"
fi

# 2. Trusted Storage
if [ -d "$STAGE/FLEXnet-data" ]; then
    mkdir -p "$DC/ProgramData/FLEXnet"
    cp -a "$STAGE/FLEXnet-data/." "$DC/ProgramData/FLEXnet/"
    echo "== Trusted Storage -> $DC/ProgramData/FLEXnet ($(find "$DC/ProgramData/FLEXnet" -type f | wc -l) files)"
fi

# 3. registry (the .reg files come from `reg export`, so paths are already HKLM\... ; wine reg import takes them)
if [ -d "$STAGE/reg" ]; then
    for f in "$STAGE"/reg/*.reg; do
        [ -s "$f" ] || continue
        echo "== reg import $(basename "$f")"
        if out=$("$WINE" reg import "$f" 2>&1); then
            printf '%s\n' "$out" | tail -2
        else
            printf '%s\n' "$out" | tail -5
            echo "!! reg import $(basename "$f") FAILED"
            exit 1
        fi
    done
fi

echo "== service state under Wine:"
"$WINE" sc query "FlexNet Licensing Service 64" 2>&1 | head -8 || true
echo "OK: state applied to $PREFIX"
