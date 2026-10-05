#!/bin/bash
# Build/test environment for the ETC/High End Systems Hog PC on Wine fork.
# Source this from the checkout root:   source env.sh
export HW=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

export HW_PRISTINE=${HW_PRISTINE:-$HW/wine-11.18}
export WINEROOT=${WINEROOT:-$HW/wine/wine-11.18}
export WINEPREFIX_INSTALL=${WINEPREFIX_INSTALL:-$HW/wine-install}
export WINEBUILD=$WINEPREFIX_INSTALL/bin/wine

# Vendor media: the download is a zip holding one MSI; expanded on the NTFS partition.
export HOG_ZIP=${HOG_ZIP:-/home/asdf/Downloads/Hog_PC_5.2.1.31.zip}
export HW_MEDIA=${HW_MEDIA:-/run/media/asdf/Windows/hog-media}
export HOG_MSI=${HOG_MSI:-$HW_MEDIA/Hog_PC_5.2.1.31.msi}

# Disk-backed scratch.
export HW_TMP=${HW_TMP:-$HW/state/tmp}
mkdir -p "$HW_TMP"
export TMPDIR=${TMPDIR:-$HW_TMP}

export HW_WORK=${HW_WORK:-$HW/state/work}
export HW_PREFIX=${HW_PREFIX:-$HW_WORK/prefix}
export HW_LOGS=${HW_LOGS:-$HW/logs}

export DISP=${DISP:-:2}
export DISP_GEOM=${DISP_GEOM:-1600x1000x24}
export JOBS=${JOBS:-8}
export ARCHS=${ARCHS:-i386,x86_64}

export VM_DOMAIN=${VM_DOMAIN:-win11}
export VM_SHARE=${VM_SHARE:-$HW/vmshare}
export VM_HOST_IP=${VM_HOST_IP:-192.168.122.1}
export VM_HTTP_PORT=${VM_HTTP_PORT:-8000}
