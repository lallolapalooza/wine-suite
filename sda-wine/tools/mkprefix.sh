#!/bin/bash
# Create and provision the Steinberg Download Assistant Wine prefix.
#
#   tools/mkprefix.sh [stages...]
#     stages: base fonts vcrun dotnet dxvk regs   (default: base fonts vcrun regs)
#   tools/mkprefix.sh all      -> everything including dotnet48 and dxvk
#
# Idempotent: re-running a stage skips work already done.
set -euo pipefail
SD=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$SD/env.sh"

WINE=$SD_INSTALL/bin/wine
if [ ! -x "$WINE" ]; then echo "no wine at $WINE - build first (tools/build_wine.sh)"; exit 1; fi
export WINEPREFIX=$SD_PREFIX
export WINEARCH=win64
export WINEDEBUG=${WINEDEBUG:--all}
export TMPDIR=$SD_TMP
export WINEDLLOVERRIDES=${WINEDLLOVERRIDES:-}
WINETRICKS=${WINETRICKS:-/usr/bin/winetricks}

log() { echo "[mkprefix] $*"; }

stages=("$@")
if [ ${#stages[@]} -eq 0 ]; then stages=(base fonts vcrun regs); fi
if [ "${stages[0]}" = "all" ]; then stages=(base fonts vcrun dotnet dxvk regs); fi
has() { [[ " ${stages[*]} " == *" $1 "* ]]; }

if has base; then
  log "base: wineboot -u ($WINEPREFIX)"
  mkdir -p "$WINEPREFIX"
  "$WINE" wineboot -u >/dev/null 2>&1 || true
  "$SD_INSTALL/bin/wineserver" -w
fi

if has fonts; then
  log "fonts: corefonts + tahoma (installs Arial/Times/Courier; Java/AWT needs real families)"
  "$WINETRICKS" -q corefonts >/dev/null 2>&1 || log "corefonts: winetricks returned non-zero (continuing)"
  "$WINETRICKS" -q tahoma >/dev/null 2>&1 || log "tahoma: winetricks returned non-zero (continuing)"
fi

if has vcrun; then
  log "vcrun: vcrun2019 (JRE/aria2 import msvcp140/vcruntime140)"
  "$WINETRICKS" -q vcrun2019 >/dev/null 2>&1 || log "vcrun2019: winetricks returned non-zero (continuing)"
fi

if has dotnet; then
  log "dotnet: dotnet48 (long; only if the app turns out to need .NET)"
  "$WINETRICKS" -q dotnet48 >/dev/null 2>&1 || log "dotnet48: winetricks returned non-zero (continuing)"
fi

if has dxvk; then
  log "dxvk: installing (NOTE: known to break the patched dcomp/dxgi path; see csp-wine README)"
  "$WINETRICKS" -q dxvk >/dev/null 2>&1 || log "dxvk: winetricks returned non-zero (continuing)"
fi

if has regs; then
  log "regs: windows version + CurrentVersion values + audio rate"
  # The real version switch: RtlGetVersion/GetVersionEx read this.
  "$WINE" reg add "HKCU\\Software\\Wine" /v Version /t REG_SZ /d win10 /f >/dev/null 2>&1 || true
  # winetricks rewrites the *static* HKLM CurrentVersion values to Windows 7 (build 7601,
  # ProductName "Microsoft Windows 7", CSDVersion "Service Pack 1") when it normalises an unknown
  # prefix.  SDA reads those values directly (net.steinberg.elicenser.download.common.system.
  # WindowsOsHelper) and refuses to start on an OS below Windows 8.  SDA is a 32-bit process, so it
  # reads the WOW6432Node view -- both views must be pinned.
  for base in 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' \
              'HKLM\Software\Wow6432Node\Microsoft\Windows NT\CurrentVersion'; do
    "$WINE" reg add "$base" /v CurrentVersion /t REG_SZ /d 6.3 /f >/dev/null 2>&1 || true
    "$WINE" reg add "$base" /v CurrentMajorVersionNumber /t REG_DWORD /d 10 /f >/dev/null 2>&1 || true
    "$WINE" reg add "$base" /v CurrentMinorVersionNumber /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true
    "$WINE" reg add "$base" /v CurrentBuild /t REG_SZ /d 19045 /f >/dev/null 2>&1 || true
    "$WINE" reg add "$base" /v CurrentBuildNumber /t REG_SZ /d 19045 /f >/dev/null 2>&1 || true
    "$WINE" reg add "$base" /v UBR /t REG_DWORD /d 5796 /f >/dev/null 2>&1 || true
    "$WINE" reg add "$base" /v ProductName /t REG_SZ /d "Windows 10 Pro" /f >/dev/null 2>&1 || true
    "$WINE" reg delete "$base" /v CSDVersion /f >/dev/null 2>&1 || true
  done
  # Steinberg audio guidance; note Wine 11.18 has no reader for Default_Rate (tree-wide grep is
  # empty), so this is recorded intent, not an active knob.
  "$WINE" reg add "HKCU\\Software\\Wine\\Drivers" /v Default_Rate /t REG_DWORD /d 48000 /f >/dev/null 2>&1 || true
fi

"$SD_INSTALL/bin/wineserver" -w
log "prefix ready: $WINEPREFIX"
