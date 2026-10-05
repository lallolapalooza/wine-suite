#!/bin/bash
# Source this from the project root:  source env.sh
export SD=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Wine source / build / install
export SD_PRISTINE=${SD_PRISTINE:-$SD/sources/wine/wine-11.18}   # pristine 11.18 + series + local
export SD_BUILD=${SD_BUILD:-$SD/wine/wine-11.18}                 # build tree (out-of-tree copy)
export SD_INSTALL=${SD_INSTALL:-$SD/wine-install}                # make install prefix
export WINEBIN=${WINEBIN:-$SD_INSTALL/bin/wine}
export WINESERVER=${WINESERVER:-$SD_INSTALL/bin/wineserver}

# Disk-backed scratch only (host / has ~45 GB free; never use tmpfs).
export SD_TMP=${SD_TMP:-$SD/state/tmp}
mkdir -p "$SD_TMP"
export TMPDIR=${TMPDIR:-$SD_TMP}

# Prefix, logs, work
export SD_LOGS=${SD_LOGS:-$SD/logs}
export SD_WORK=${SD_WORK:-$SD/state/work}
export SD_PREFIX=${SD_PREFIX:-$SD/state/prefix}
export WINEPREFIX=${WINEPREFIX:-$SD_PREFIX}
export WINEARCH=${WINEARCH:-win64}
export WINEDEBUG=${WINEDEBUG:--all}

# Display: dedicated Xvfb + x11vnc (VNC), so the app is watchable and scriptable.
export DISP=${DISP:-:22}
export DISP_GEOM=${DISP_GEOM:-1920x1080x24}
export VNC_PORT=${VNC_PORT:-5922}

# Media
export SDA_SETUP=${SDA_SETUP:-/home/asdf/Downloads/Steinberg_Download_Assistant_1.40.1_Installer_win.exe}
export SDA_MEDIA=${SDA_MEDIA:-$SD/sources/sda_installer}

# Windows guest reference (libvirt domain, spice 127.0.0.1:5900, 192.168.122.230)
export VM_DOMAIN=${VM_DOMAIN:-win11}
export VM_SHARE=${VM_SHARE:-$SD/vmshare}
export VM_HOST_IP=${VM_HOST_IP:-192.168.122.1}
export VM_HTTP_PORT=${VM_HTTP_PORT:-8000}

export JOBS=${JOBS:-$(nproc)}

# Convenience: put the freshly built wine first.
export PATH="$SD_INSTALL/bin:$PATH"
