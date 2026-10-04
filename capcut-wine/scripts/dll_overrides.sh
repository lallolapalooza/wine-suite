#!/bin/bash
# dll_overrides.sh <native|builtin> [dll...]
# Set HKCU\Software\Wine\DllOverrides for the D3D stack in the CapCut prefix.
#   native : use DXVK (DLLs copied into system32 by scripts/install_dxvk.sh)
#   builtin: use Wine's own wined3d-based d3d*/dxgi
# Default DLL set: d3d8 d3d9 d3d10core d3d11 dxgi
# usage: dll_overrides.sh native
#        dll_overrides.sh builtin
set -eu
CCWS=/home/asdf/projects/capcut-wine
MODE=${1:?usage: dll_overrides.sh <native|builtin> [dll...]}
shift || true
DLLS=${*:-"d3d8 d3d9 d3d10core d3d11 dxgi"}
export WINEPREFIX=$CCWS/prefix
export PATH=${WINELOADER_BIN:-/opt/wine-staging/bin}:$PATH
for dll in $DLLS; do
  wine reg add 'HKCU\Software\Wine\DllOverrides' /v "$dll" /d "$MODE" /f >/dev/null 2>&1
done
wine reg query 'HKCU\Software\Wine\DllOverrides' 2>/dev/null | grep -vE 'winediag|loader_init|^$'
