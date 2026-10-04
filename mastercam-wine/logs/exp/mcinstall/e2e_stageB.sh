#!/bin/bash
# Stage B: product MSI on the prepared prefix, probes, then launch + OCR.
set -u
ROOT=/home/asdf/projects/mastercam-wine
cd "$ROOT"
source "$ROOT/env.sh"
L=$ROOT/logs/exp/mcinstall
export MCW_LOGS=$L TMPDIR=$ROOT/state/tmp DISPLAY=:2 WINEPREFIX="$MCW_PREFIX" WINEARCH=win64
export PATH="$(dirname "$WINEBUILD"):$PATH"
W=$WINEBUILD
M=$MCW_MEDIA
exec > "$L/e2e_stageB.log" 2>&1

echo "=== 7. Mastercam product MSI ($(date +%T)) ==="
export WINEDEBUG='+timestamp,+err,+warn'
time "$W" msiexec /i "$M/mastercam/Mastercam_Installer.msi" \
  TRANSFORMS="$M/mastercam/1033.mst" \
  INSTALLDIR='C:\Program Files\Mastercam 2027' \
  SHAREDDEFAULTS='C:\ProgramData\Mastercam' \
  CNC_UNIT_TYPE=I REBOOT=ReallySuppress \
  /qn /norestart /L*v 'C:\mc_msi_final.log' \
  > "$L/msi_final_stdout.log" 2> "$L/winedbg_final.log"
echo "MSIEXEC_EXIT=$?"
"$W" wineserver -w >/dev/null 2>&1

echo "-- PS key after install --"
"$W" reg query 'HKLM\Software\Classes\CLSID\{00020420-0000-0000-C000-000000000046}\InprocServer32' 2>&1 | sed -n '3p'
echo "-- decisive MSI-log lines --"
grep -anE "Failed to initialize 64-bit helper|Error 27555|Action ended [0-9:]+: (InstallFinalize|ISLockPermissionsInstall|SetDateTimeFormat|INSTALL)" "$WINEPREFIX/drive_c/mc_msi_final.log" 2>/dev/null | head -20
echo "-- stderr err lines --"
grep -anE "err:msi|err:ole:apartment_add_dll|no class object" "$L/winedbg_final.log" | head -10
echo "-- footprint --"
ls -la "$WINEPREFIX/drive_c/Program Files/Mastercam 2027/" 2>&1 | head -30
echo "files: $(find "$WINEPREFIX/drive_c/Program Files/Mastercam 2027" -type f 2>/dev/null | wc -l)"
du -sh "$WINEPREFIX/drive_c/Program Files/Mastercam 2027" 2>/dev/null
ls -la "$WINEPREFIX/drive_c/Program Files/Mastercam 2027/MastercamLauncher.exe" \
       "$WINEPREFIX/drive_c/Program Files/Mastercam 2027/Mastercam.exe" \
       "$WINEPREFIX/drive_c/Program Files/Mastercam 2027/Mastercam.dll" 2>&1

echo "=== 8. regression probes ==="
"$W" /run/media/asdf/Windows/mc-scratch/ps_test32.exe 2>/dev/null | head -6
"$W" /run/media/asdf/Windows/mc-scratch/ps_test64.exe 2>/dev/null | head -6

echo "=== 9. launch MastercamLauncher.exe ($(date +%T)) ==="
if [ -f "$WINEPREFIX/drive_c/Program Files/Mastercam 2027/MastercamLauncher.exe" ]; then
  tools/run_mastercam.sh mcfinal --secs 180 --iv 15 --prefix "$WINEPREFIX" --wine "$W" \
      --debug '+timestamp,+err,+warn' --exe MastercamLauncher.exe || true
  echo "-- window trees --"
  for f in "$L/runs/mcfinal"/windows_*.txt; do echo "## $f"; grep -a '"' "$f" | head -25; done
  echo "-- OCR of captures --"
  for f in "$L/runs/mcfinal"/win_*.png "$L/runs/mcfinal"/screen_*.png; do
    [ -f "$f" ] || continue
    tesseract "$f" "${f%.png}" 2>/dev/null
    echo "## ${f##*/}: $(tr '\n' '|' < "${f%.png}.txt" 2>/dev/null | head -c 400)"
  done
  echo "-- app.stderr head --"
  head -50 "$L/runs/mcfinal/app.stderr" 2>/dev/null
  echo "=== 10. launch Mastercam.exe directly ==="
  tools/run_mastercam.sh mcdirect --secs 120 --iv 15 --prefix "$WINEPREFIX" --wine "$W" \
      --debug '+timestamp,+err,+warn' --exe Mastercam.exe || true
  for f in "$L/runs/mcdirect"/win_*.png; do
    [ -f "$f" ] || continue
    tesseract "$f" "${f%.png}" 2>/dev/null
    echo "## ${f##*/}: $(tr '\n' '|' < "${f%.png}.txt" 2>/dev/null | head -c 400)"
  done
  head -40 "$L/runs/mcdirect/app.stderr" 2>/dev/null
else
  echo "MastercamLauncher.exe not installed - launch skipped"
fi
echo "=== stage B done $(date +%T) ==="
