#!/bin/bash
# Build/test environment for the Tableau-Desktop-2026.2.3-on-Wine project.
# Source from the checkout root:  source env.sh
set -u
export TABLEAU=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

export WINEROOT=${WINEROOT:-$TABLEAU/wine-11.18}            # the patched tree (built in place, no copy: disk)
export WINEPREFIX_INSTALL=${WINEPREFIX_INSTALL:-$TABLEAU/wine-install}
export WINEBUILD=$WINEPREFIX_INSTALL/bin/wine

export APP_EXE=/home/asdf/Downloads/TableauDesktop-64bit-2026-2-3.exe
export TABLEAU_PREFIX=${TABLEAU_PREFIX:-$TABLEAU/prefix/tableau}
export DISP=${DISP:-:11}
export VMCMD=$TABLEAU/tools/guest.sh

# Job count: a Wine compile job is 1.5-2 GB RSS; this host has 30 GB with 8 GB in the Windows VM.
export JOBS=${JOBS:-6}

# ccache: the patch iteration loop is many near-identical rebuilds; without this in PATH Wine's
# configure does not pick ccache up. Enabled here (plus tools/build_tableau.sh inherits it).
if [ -d /usr/lib/ccache ]; then
    case ":$PATH:" in *":/usr/lib/ccache:"*) ;; *) export PATH=/usr/lib/ccache:$PATH ;; esac
fi
