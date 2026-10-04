#!/bin/bash
# Build/test environment for the Resolume-Arena-7-on-Wine fork.
# Source this from the checkout root:   source env.sh
export RW=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Wine source: pristine tarball tree, and the patched tree that gets built.
export RW_PRISTINE=${RW_PRISTINE:-$RW/wine-11.18}
export WINEROOT=${WINEROOT:-$RW/wine/wine-11.18}          # the tree that gets built (pristine + patches)
export WINEPREFIX_INSTALL=${WINEPREFIX_INSTALL:-$RW/wine-install}
export WINEBUILD=$WINEPREFIX_INSTALL/bin/wine

# Resolume media: the vendor installer and its extracted payload.
export RES_INSTALLER=${RES_INSTALLER:-/home/asdf/Downloads/Resolume_Arena_7_28_0_rev_24303_Installer.exe}
export RES_MEDIA=${RES_MEDIA:-$RW/installer/media_x}

# Disk-backed scratch (never a RAM-backed tmpfs): the host's / is a real disk, but make it
# explicit so every build/run/extract writes temp files to a real block device.
export RW_TMP=${RW_TMP:-$RW/state/tmp}
mkdir -p "$RW_TMP"
export TMPDIR=${TMPDIR:-$RW_TMP}

# Work directory: the Wine prefix, logs and evidence live here.
export RW_WORK=${RW_WORK:-$RW/state/work}
export RW_PREFIX=${RW_PREFIX:-$RW_WORK/prefix}
export RW_LOGS=${RW_LOGS:-$RW/logs}

# The display the UI runs on (shared with the sibling projects' TigerVNC :2).
export DISP=${DISP:-:2}
export DISP_GEOM=${DISP_GEOM:-1600x1000x24}

export JOBS=${JOBS:-8}

# Wine build (new WoW64 recipe).
export ARCHS=${ARCHS:-i386,x86_64}

# Windows guest command channel.
export VM_DOMAIN=${VM_DOMAIN:-win11}
export VM_SHARE=${VM_SHARE:-$RW/vmshare}
export VM_HOST_IP=${VM_HOST_IP:-192.168.122.1}
