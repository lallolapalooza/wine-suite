#!/bin/bash
# Create and provision the CSP Wine prefix, following the documented recipe
# (WineHQ AppDB 4.x notes + parka6060/CSPenguin-Installer):
#   corefonts, vcrun2022, dotnet48, dxvk, vkd3d, wine-gecko, a light CJK font,
#   concrt140 override, per-exe Windows versions, WINEESYNC.
#
#   tools/mkprefix.sh [stages...]
#     stages: base fonts vcrun dotnet gecko dxvk cjk regs   (default: all but dotnet)
#   tools/mkprefix.sh all        -> everything including dotnet48
#
# Everything is idempotent: re-running a stage is cheap and skips work already done.
set -euo pipefail
CW=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$CW/env.sh"

WINE=$CW_INSTALL/bin/wine
if [ ! -x "$WINE" ]; then echo "no wine at $WINE — build first (tools/build_wine.sh)"; exit 1; fi
export WINEPREFIX=$CW_PREFIX
export WINEARCH=win64
export WINEDEBUG=${WINEDEBUG:--all}
export TMPDIR=$CW_TMP
WINETRICKS=${WINETRICKS:-/usr/bin/winetricks}

log() { echo "[mkprefix] $*"; }

stages=("$@")
if [ ${#stages[@]} -eq 0 ]; then stages=(base fonts vcrun gecko dxvk cjk regs); fi
if [ "${stages[0]}" = "all" ]; then stages=(base fonts vcrun dotnet gecko dxvk cjk regs); fi
has() { [[ " ${stages[*]} " == *" $1 "* ]]; }

# ---------------------------------------------------------------- base
if has base; then
  log "base: wineboot on $WINEPREFIX"
  mkdir -p "$CW_PREFIX"
  WINEESYNC=1 "$WINE" wineboot -u >/dev/null 2>&1 || true
  "$CW_INSTALL/bin/wineserver" -w
  log "base: Windows version 10 (global)"
  "$WINE" reg add 'HKCU\Software\Wine' /v Version /t REG_SZ /d win10 /f >/dev/null
fi

# ---------------------------------------------------------------- fonts
if has fonts; then
  log "fonts: corefonts via winetricks (Arial/Times/Courier/Verdana/...) + enumeration fix"
  if [ -f "$CW/tools/install_corefonts.sh" ]; then
    bash "$CW/tools/install_corefonts.sh" || true
  fi
  WINEDLLOVERRIDES="winemenubuilder.exe=d" WINEESYNC=1 "$WINETRICKS" -q corefonts || log "corefonts: winetricks failed (continuing)"
fi

if has cjk; then
  log "cjk: WenQuanYi Micro Hei (asset store + brush names); replaces heavy cjkfonts"
  FONT=$CW/sources/media/wqy-microhei.ttc
  if [ ! -f "$FONT" ]; then
    mkdir -p "$(dirname "$FONT")"
    curl -fsSL -m 300 -o "$FONT" \
      "https://raw.githubusercontent.com/parka6060/CSPenguin-Installer/main/patches/fonts/wqy-microhei.ttc" \
      || log "cjk: download failed"
  fi
  if [ -f "$FONT" ]; then
    cp "$FONT" "$CW_PREFIX/drive_c/windows/Fonts/" && log "cjk: installed $(basename "$FONT")"
  fi
fi

# ---------------------------------------------------------------- redistributables
if has vcrun; then
  log "vcrun2022 (x64+x86) via winetricks"
  WINEESYNC=1 "$WINETRICKS" -q vcrun2022 || log "vcrun2022: failed (continuing)"
fi

if has dotnet; then
  log "dotnet48 via winetricks — this takes 10-30 min"
  WINEESYNC=1 "$WINETRICKS" -q dotnet48 || log "dotnet48: failed (continuing)"
fi

if has gecko; then
  log "wine-gecko (MSHTML) so IE-based UI renders instead of a blank page"
  WINEESYNC=1 "$WINETRICKS" -q gecko || log "gecko: failed (continuing)"
fi

if has dxvk; then
  log "dxvk + vkd3d"
  WINEESYNC=1 "$WINETRICKS" -q dxvk vkd3d || log "dxvk/vkd3d: failed (continuing)"
  cat > "$CW_PREFIX/dxvk.conf" <<'EOF'
dxvk.enableGraphicsPipelineLibrary = False
dxvk.numCompilerThreads = 0
dxvk.maxChunkSize = 16
EOF
  log "dxvk.conf written (pipeline library off: CSP is OpenGL/Qt, not a D3D game)"
fi

# ---------------------------------------------------------------- registry
if has regs; then
  log "regs: DLL overrides + per-executable Windows versions"
  # Startup-crash fix documented by both the AppDB recipe and CSPenguin: use the
  # concrt140.dll bundled with the application instead of Wine's builtin.
  "$WINE" reg add 'HKCU\Software\Wine\DllOverrides' /v concrt140 /t REG_SZ /d 'native,builtin' /f >/dev/null
  # CLIPStudioPaint.exe must report Windows 8.1: CSP exits immediately on 10/11
  # (WineHQ bug 58254).  Wine's registry spelling is `win81` — `win8.1` is rejected by
  # err:ver:parse_win_version and silently leaves the app on the global (win10) setting.
  for app in CLIPStudioPaint.exe CLIPStudio.exe CLIPStudioUpdater.exe; do
    "$WINE" reg add "HKCU\\Software\\Wine\\AppDefaults\\$app" /v Version /t REG_SZ /d win81 /f >/dev/null
  done
  # WebView2 needs Windows 7 for the launcher's asset store.
  "$WINE" reg add 'HKCU\Software\Wine\AppDefaults\msedgewebview2.exe' /v Version /t REG_SZ /d win7 /f >/dev/null
  log "regs: done"
fi

"$CW_INSTALL/bin/wineserver" -w
log "prefix ready: $CW_PREFIX"
