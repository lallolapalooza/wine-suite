#!/bin/bash
# Build/test environment for the Mastercam-2027-on-Wine fork.
# Source this from the checkout root:   source env.sh
export MCW=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Wine source: pristine tarball tree, and the patched tree that gets built.
export MCW_PRISTINE=${MCW_PRISTINE:-$MCW/wine-11.18}
export WINEROOT=${WINEROOT:-$MCW/wine/wine-11.18}          # the tree that gets built (pristine + patches)
export WINEPREFIX_INSTALL=${WINEPREFIX_INSTALL:-$MCW/wine-install}
export WINEBUILD=$WINEPREFIX_INSTALL/bin/wine

# The vendor media: the RAR-SFX "web" installer and its extracted payload.
export MCW_INSTALLER=${MCW_INSTALLER:-/home/asdf/Downloads/mastercam2027-web.exe}
# Extracted payload lives on the NTFS data partition to keep / free (ntfs3, 40 GiB free).
export MCW_MEDIA=${MCW_MEDIA:-/run/media/asdf/Windows/mastercam-media}

# Disk-backed scratch (never a RAM-backed tmpfs).
export MCW_TMP=${MCW_TMP:-$MCW/state/tmp}
mkdir -p "$MCW_TMP"
export TMPDIR=${TMPDIR:-$MCW_TMP}

# Work directory: the Wine prefix, logs and evidence live here.
export MCW_WORK=${MCW_WORK:-$MCW/state/work}
export MCW_PREFIX=${MCW_PREFIX:-$MCW_WORK/prefix}
export MCW_LOGS=${MCW_LOGS:-$MCW/logs}

# The display the UI runs on (TigerVNC :2, shared with the sibling projects).
export DISP=${DISP:-:2}
export DISP_GEOM=${DISP_GEOM:-1600x1000x24}

export JOBS=${JOBS:-8}

# Wine build (new WoW64 recipe).
export ARCHS=${ARCHS:-i386,x86_64}

# Windows guest command channel (libvirt domain + HTTP poller on the host bridge).
export VM_DOMAIN=${VM_DOMAIN:-win11}
export VM_SHARE=${VM_SHARE:-$MCW/vmshare}
export VM_HOST_IP=${VM_HOST_IP:-192.168.122.1}
export VM_HTTP_PORT=${VM_HTTP_PORT:-8000}

export WINEDEBUG_SILENT=${WINEDEBUG_SILENT:-fixme-all}
