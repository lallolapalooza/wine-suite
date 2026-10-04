#!/bin/bash
# Deploy the already-extracted Tableau tree into a Wine prefix WITHOUT running the installer.
#
# Purpose: separate the two problems. "Does the app run under Wine" and "does the Burn+MSI
# installer run under Wine" are independent; this script answers the first one alone. The same
# layout is what the Windows guest gets from `msiexec /a <msi> TARGETDIR=C:\TableauRef`.
#
#   tools/deploy_tree.sh [prefix] [--copy]
#
# Default is a SYMLINK of the tree into drive_c (saves 2.1 GB); --copy makes a real copy.
# Source tree: $P/app/tableau_exe/msi_root/Tableau  ->  C:\Program Files\Tableau
set -eu
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PREFIX=${1:-$ROOT/prefix/tableau}
MODE=${2:-}
SRC=$ROOT/app/tableau_exe/msi_root/Tableau
[ -d "$SRC" ] || { echo "no extracted tree at $SRC"; exit 1; }

DEST="$PREFIX/drive_c/Program Files/Tableau"
[ -d "$PREFIX" ] || { echo "no prefix at $PREFIX - run tools/make_prefix.sh"; exit 1; }
mkdir -p "$(dirname "$DEST")"

if [ -L "$DEST" ] || [ -d "$DEST" ]; then
    echo "already deployed: $DEST"
else
    if [ "$MODE" = "--copy" ]; then
        echo "copying $(du -sh "$SRC" | cut -f1) -> $DEST"
        cp -a "$SRC" "$DEST"
    else
        ln -s "$SRC" "$DEST"
        echo "symlinked $DEST -> $SRC"
    fi
fi

EXE="C:\\Program Files\\Tableau\\Tableau 2026.2\\bin\\tableau.exe"
echo
echo "run with:"
echo "  WINEPREFIX=$PREFIX DISPLAY=\${DISP:-:11} $ROOT/wine-install/bin/wine '$EXE'"
echo "or:  EXE='$EXE' tools/run_tableau.sh <tag> 120"
