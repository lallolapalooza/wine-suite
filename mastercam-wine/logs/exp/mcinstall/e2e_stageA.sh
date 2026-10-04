#!/bin/bash
# Stage A: fresh state/work/prefix + all prerequisites for Mastercam, with OUR wine.
set -u
ROOT=/home/asdf/projects/mastercam-wine
cd "$ROOT"
source "$ROOT/env.sh"          # MCW_PREFIX=$MCW/state/work/prefix, WINEBUILD=$MCW/wine-install/bin/wine
L=$ROOT/logs/exp/mcinstall
export MCW_LOGS=$L
export TMPDIR=$ROOT/state/tmp
export DISPLAY=:2
export LC_ALL=C
export WINEPREFIX="$MCW_PREFIX"
export WINEARCH=win64
export WINEDEBUG="${WINEDEBUG:--all}"
export PATH="$(dirname "$WINEBUILD"):$PATH"
mkdir -p "$L" "$MCW_PREFIX"
M=$MCW_MEDIA
SCRATCH=/run/media/asdf/Windows/mc-scratch
exec > "$L/e2e_stageA.log" 2>&1

echo "=== $(date +%T) wine $("$WINEBUILD" --version) prefix $WINEPREFIX ==="
echo "msi.dll: $(stat -c '%y' "$ROOT/wine-install/lib/wine/x86_64-windows/msi.dll")"

echo "=== 1. mkprefix ==="
tools/mkprefix.sh --prefix "$MCW_PREFIX" --wine "$WINEBUILD" --stage fonts
"$WINEBUILD" wineserver -w >/dev/null 2>&1

echo "=== 2. core fonts (RW_TMP workaround) ==="
mkdir -p "$ROOT/state/tmp/fonts"
cp -n /home/asdf/projects/resolume-wine/state/tmp/fonts/*.ttf "$ROOT/state/tmp/fonts/" 2>/dev/null
RW_TMP=$ROOT/state/tmp "$ROOT/tools/install_corefonts.sh" --prefix "$WINEPREFIX" --src "$ROOT/state/tmp/fonts" 2>&1 | tail -8

echo "=== 3. .NET 10 Desktop Runtime 10.0.12 ($(date +%T)) ==="
"$WINEBUILD" "$SCRATCH/wd10.exe" /install /quiet /norestart > "$L/prereq_dotnet10.log" 2>&1
echo "dotnet10 rc=$?"
"$WINEBUILD" wineserver -w >/dev/null 2>&1
find "$WINEPREFIX/drive_c/Program Files/dotnet" -maxdepth 3 -type d 2>/dev/null | head -8

echo "=== 4. .NET Framework 4.8 (winetricks, ~15 min) ($(date +%T)) ==="
WINEPREFIX="$WINEPREFIX" LC_ALL=C winetricks -q -f dotnet48 > "$L/prereq_dotnet48.log" 2>&1
echo "dotnet48 rc=$?"
"$WINEBUILD" wineserver -w >/dev/null 2>&1
ls "$WINEPREFIX/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319" 2>/dev/null | head -3

echo "=== 5. VC++ 2022 x64 ($(date +%T)) ==="
"$WINEBUILD" "$M/SetupPrerequisites/VC2022/VC_redist.x64.exe" /install /quiet /norestart > "$L/prereq_vc2022.log" 2>&1
echo "vc2022 rc=$?"
"$WINEBUILD" wineserver -w >/dev/null 2>&1

echo "=== 6. CodeMeter Runtime (patch 0101 test) ($(date +%T)) ==="
"$WINEBUILD" msiexec /i "$M/SetupPrerequisites/CodeMeterRuntime64.msi" ALLOW_BELOW=1 /qn /norestart \
    /L*v 'C:\cm.log' > "$L/prereq_codemeter.log" 2>&1
echo "codemeter msi rc=$?"
"$WINEBUILD" wineserver -w >/dev/null 2>&1
echo "-- cm.log decisive --"
grep -aE "Return value 3|InstallFinalize|StartServices|ServiceControl|Error 2|1053|Product: CodeMeter" "$WINEPREFIX/drive_c/cm.log" 2>/dev/null | tail -20
echo "-- service state --"
"$WINEBUILD" net start 2>&1 | head -20
"$WINEBUILD" sc query CodeMeter 2>&1 | head -10
ls -la "$WINEPREFIX/drive_c/Program Files/CodeMeter/Runtime/CodeMeter.exe" 2>&1 | head -2

echo "=== stage A done $(date +%T) ==="
