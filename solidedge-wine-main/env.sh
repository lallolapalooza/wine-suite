#!/bin/bash
# Build/test environment for the Solid-Edge-X-2026-on-Wine fork.
# Source this from the checkout root:   source env.sh
export SE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

export WINEROOT=${WINEROOT:-$SE/wine/wine-11.18}          # the tree that gets built
export WINEPREFIX_INSTALL=${WINEPREFIX_INSTALL:-$SE/wine-install}
export WINEBUILD=$WINEPREFIX_INSTALL/bin/wine

# Siemens media: the extracted InstallShield layout (setup.exe + the MSI + the cabs).
# `installer/media/` holds the downloaded 7z chunks, `installer/media_x/` what they extract to.
export SE_MEDIA=${SE_MEDIA:-$SE/installer/media_x/Solid Edge}

# Work directory: the Wine prefix, logs and evidence live here.
export SE_WORK=${SE_WORK:-$SE/state/work}
export SE_PREFIX=${SE_PREFIX:-$SE_WORK/prefix}
export SE_LOGS=${SE_LOGS:-$SE/logs}

# The display the UI runs on.
export DISP=${DISP:-:2}
export DISP_GEOM=${DISP_GEOM:-1600x1000x24}

export JOBS=${JOBS:-8}
