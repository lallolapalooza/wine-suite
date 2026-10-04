#!/bin/bash
# Build/test environment for the ETC Eos Family on Wine fork.
# Source this from the checkout root:   source env.sh
export EW=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Wine source: pristine tarball tree (now carrying patches/series + patches/local), and the build tree.
export EW_PRISTINE=${EW_PRISTINE:-$EW/wine-11.18}
export WINEROOT=${WINEROOT:-$EW/wine/wine-11.18}          # the tree that gets built
export WINEPREFIX_INSTALL=${WINEPREFIX_INSTALL:-$EW/wine-install}
export WINEBUILD=$WINEPREFIX_INSTALL/bin/wine

# Vendor media. The download is a zip holding one big installer exe; the zip is expanded on the
# NTFS data partition (which is not the tight filesystem) by tools/../logs/unzip.log.
export EOS_ZIP=${EOS_ZIP:-/home/asdf/Downloads/ETC_EosFamily_v3.3.10.28.zip}
export EW_MEDIA=${EW_MEDIA:-/run/media/asdf/Windows/eos-media}
export EOS_EXE=${EOS_EXE:-$EW_MEDIA/ETC_EosFamily_v3.3.10.28.exe}

# Disk-backed scratch (never a RAM-backed tmpfs).
export EW_TMP=${EW_TMP:-$EW/state/tmp}
mkdir -p "$EW_TMP"
export TMPDIR=${TMPDIR:-$EW_TMP}

# Work directory: the Wine prefix, logs and evidence live here.
export EW_WORK=${EW_WORK:-$EW/state/work}
export EW_PREFIX=${EW_PREFIX:-$EW_WORK/prefix}
export EW_LOGS=${EW_LOGS:-$EW/logs}

# The display the UI runs on (TigerVNC :2, shared with the sibling projects).
export DISP=${DISP:-:2}
export DISP_GEOM=${DISP_GEOM:-1600x1000x24}

export JOBS=${JOBS:-8}

# Wine build (new WoW64 recipe).
export ARCHS=${ARCHS:-i386,x86_64}

# Windows guest command channel (libvirt domain + HTTP poller on the host bridge).
export VM_DOMAIN=${VM_DOMAIN:-win11}
export VM_SHARE=${VM_SHARE:-$EW/vmshare}
export VM_HOST_IP=${VM_HOST_IP:-192.168.122.1}
export VM_HTTP_PORT=${VM_HTTP_PORT:-8000}
