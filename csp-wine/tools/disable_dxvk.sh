#!/bin/bash
# Stop DXVK/VKD3D from shadowing Wine's D3D stack in the CSP prefix.
#
# Why: CSP's UI composites through DirectComposition/DXGI
# (CreateSwapChainForComposition + IDCompositionVisual).  DXVK's dxgi.dll does not implement
# CreateSwapChainForComposition ("DxgiFactory::CreateSwapChainForComposition: Not implemented"),
# so with DXVK installed the app silently bypasses Wine's dxgi/d3d11 — and with it the
# dcomp support this project patches in — leaving CSP with a blank white window.
#
# The fix is NOT to delete files from system32: in a Wine prefix those are Wine's own builtin
# PE modules, and deleting them makes the app fail to start
# ("Library d3d11.dll ... not found", status c0000135).  Instead:
#   1. wineboot -u restores any builtin module a previous native install overwrote,
#   2. the overrides are pinned to builtin for the whole D3D/DXGI/dcomp family.
#
#   tools/disable_dxvk.sh
set -euo pipefail
CW=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$CW/env.sh"

export WINEPREFIX=$CW_PREFIX
DLLS="dxgi d3d8 d3d9 d3d10core d3d10_1 d3d11 d3d12 d3d12core dcomp"

echo "-- restoring Wine builtin modules (wineboot -u)"
"$CW_INSTALL/bin/wine" wineboot -u >/dev/null 2>&1 || true
"$CW_INSTALL/bin/wineserver" -w

echo "-- pinning overrides to builtin"
for d in $DLLS; do
  "$CW_INSTALL/bin/wine" reg add 'HKCU\Software\Wine\DllOverrides' /v "$d" /t REG_SZ /d builtin /f >/dev/null
done

echo "overrides now:"
"$CW_INSTALL/bin/wine" reg query 'HKCU\Software\Wine\DllOverrides' 2>/dev/null | tr -d '\r' | grep -E "d3d|dxgi|dcomp" || true
