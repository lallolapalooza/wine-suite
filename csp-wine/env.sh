#!/bin/bash
# Source this from the project root:  source env.sh
export CW=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Wine source / build / install
export CW_PRISTINE=${CW_PRISTINE:-$CW/sources/wine/wine-11.18}   # pristine 11.18 + series + local
export CW_BUILD=${CW_BUILD:-$CW/wine/wine-11.18}                 # build tree
export CW_INSTALL=${CW_INSTALL:-$CW/wine-install}                # make install prefix
export WINEBIN=${WINEBIN:-$CW_INSTALL/bin/wine}
export WINESERVER=${WINESERVER:-$CW_INSTALL/bin/wineserver}

# Missing runtime DLLs that the series/local patches do not build (e.g. dcomp), staged here and
# copied over the prefix's system32 when a stub needs replacing.
export CW_OVERRIDE=${CW_OVERRIDE:-$CW/state/override}

# Disk-backed scratch only.
export CW_TMP=${CW_TMP:-$CW/state/tmp}
mkdir -p "$CW_TMP"
export TMPDIR=${TMPDIR:-$CW_TMP}

# Prefix and logs
export CW_LOGS=${CW_LOGS:-$CW/logs}
export CW_WORK=${CW_WORK:-$CW/state/work}
export CW_PREFIX=${CW_PREFIX:-$CW/state/prefix}
export WINEPREFIX=${WINEPREFIX:-$CW_PREFIX}
export WINEARCH=${WINEARCH:-win64}
export WINEDEBUG=${WINEDEBUG:--all}

# Display: dedicated Xvfb + x11vnc, so the app is watchable and scriptable.
export DISP=${DISP:-:20}
export DISP_GEOM=${DISP_GEOM:-1920x1080x24}
export VNC_PORT=${VNC_PORT:-5920}

# Media
export CSP_SETUP=${CSP_SETUP:-/home/asdf/Downloads/CSP_514w_setup.exe}
export CSP_MEDIA=${CSP_MEDIA:-$CW/sources/csp_installer}

# Windows guest reference
export VM_DOMAIN=${VM_DOMAIN:-win11}
export VM_SHARE=${VM_SHARE:-$CW/vmshare}
export VM_HOST_IP=${VM_HOST_IP:-192.168.122.1}
export VM_HTTP_PORT=${VM_HTTP_PORT:-8000}

export JOBS=${JOBS:-$(nproc)}

# Convenience: put the freshly built wine first.
export PATH="$CW_INSTALL/bin:$PATH"
