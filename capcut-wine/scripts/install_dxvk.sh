#!/bin/bash
# Install DXVK (D3D9/10/11 + DXGI -> Vulkan) into the CapCut prefix and set the DLL overrides.
# Reproducible fixup: DXVK replaces Wine's d3d11/dxgi, which CapCut's Qt RHI + ANGLE need.
# usage: install_dxvk.sh [dxvk_dir]
set -eu
CCWS=/home/asdf/projects/capcut-wine
DXVK=${1:-$CCWS/third_party/dxvk-3.1.1}
export WINEPREFIX=$CCWS/prefix
export PATH=${WINELOADER_BIN:-/opt/wine-staging/bin}:$PATH
SYS64="$WINEPREFIX/drive_c/windows/system32"
SYS32="$WINEPREFIX/drive_c/windows/syswow64"
[ -d "$DXVK/x64" ] || { echo "no $DXVK/x64"; exit 1; }

for f in "$DXVK"/x64/*.dll; do cp -f "$f" "$SYS64/"; done
if [ -d "$SYS32" ]; then for f in "$DXVK"/x32/*.dll; do cp -f "$f" "$SYS32/"; done; fi
echo "copied DXVK into $SYS64 (and syswow64 if present)"

# native overrides so the DXVK DLLs win over Wine's builtins
for dll in d3d8 d3d9 d3d10core d3d11 dxgi; do
  wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v "$dll" /d "native" /f >/dev/null 2>&1 || true
done
wine reg query "HKCU\\Software\\Wine\\DllOverrides" 2>/dev/null || true
echo done
