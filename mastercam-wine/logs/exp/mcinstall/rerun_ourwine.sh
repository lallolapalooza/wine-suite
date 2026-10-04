#!/bin/bash
# Re-run the Mastercam product-MSI install against OUR build (19 patches + local 0100/0101)
# on a FRESH prefix, with a live monitor of the CLSID_PSDispatch registry view, then
# re-run the regression probes and (if it installed) try to launch MastercamLauncher.exe.
set -u
ROOT=/home/asdf/projects/mastercam-wine
L=$ROOT/logs/exp/mcinstall
W=$ROOT/wine-install/bin/wine
P=/run/media/asdf/Windows/mc-scratch/pfx2
M=/run/media/asdf/Windows/mastercam-media
export TMPDIR=$ROOT/state/tmp
export DISPLAY=:2
exec > "$L/rerun_ourwine.log" 2>&1

echo "=== 1. wait for our build ($(date +%T)) ==="
ok=0
for i in $(seq 1 200); do
  if [ -x "$W" ] && "$W" --version >/dev/null 2>&1; then ok=1; break; fi
  sleep 15
done
if [ "$ok" != 1 ]; then echo "BUILD NOT READY after 50 min - aborting"; exit 1; fi
echo "wine: $("$W" --version)"
stat -c '%y %n' "$W" "$ROOT/wine-install/lib/wine/x86_64-windows/msi.dll" "$ROOT/wine/wine-11.18/dlls/msi/classes.c"
md5sum "$ROOT/wine-install/lib/wine/x86_64-windows/msi.dll" "$ROOT/wine-install/lib/wine/i386-windows/msi.dll"

echo "=== 2. fresh prefix ($P) ($(date +%T)) ==="
export WINEPREFIX=$P WINEARCH=win64
export PATH="$(dirname $W):$PATH"
rm -rf "$P"; mkdir -p "$P"
"$W" wineboot -u > "$L/wineboot_ourwine.log" 2>&1
"$W" wineserver -w >/dev/null 2>&1
for kv in "CurrentVersion 10.0" "CurrentBuildNumber 19045" "CurrentBuild 19045" "ProductName|Windows 10 Pro"; do
  k=${kv%% *}; v=${kv#* }
  "$W" reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' /v "$k" /d "${v//|/ }" /f >>"$L/wineboot_ourwine.log" 2>&1
done
echo "-- baseline PS keys --"
"$W" reg query 'HKLM\Software\Classes\CLSID\{00020420-0000-0000-C000-000000000046}\InprocServer32' 2>&1 | sed -n '3p'
"$W" reg query 'HKLM\Software\Classes\CLSID\{00020424-0000-0000-C000-000000000046}\InprocServer32' 2>&1 | sed -n '3p'

echo "=== 3. registry monitor ==="
cat > "$L/keymon3.sh" <<'EOS'
#!/bin/bash
export WINEPREFIX=/run/media/asdf/Windows/mc-scratch/pfx2
W=/home/asdf/projects/mastercam-wine/wine-install/bin/wine
L=/home/asdf/projects/mastercam-wine/logs/exp/mcinstall/keymon3.log
for i in $(seq 1 200); do
  v=$(timeout 15 $W reg query 'HKLM\Software\Classes\CLSID\{00020420-0000-0000-C000-000000000046}\InprocServer32' 2>/dev/null | sed -n '3p' | sed 's/^ *//')
  echo "$(date +%T) [$v]" >> $L
  sleep 6
done
EOS
chmod +x "$L/keymon3.sh"; rm -f "$L/keymon3.log"
setsid nohup "$L/keymon3.sh" >/dev/null 2>&1 &
sleep 4; cat "$L/keymon3.log"

echo "=== 4. install with OUR wine ($(date +%T)) ==="
export WINEDEBUG='+timestamp,+err,+warn'
rm -f "$P/drive_c/mc_msi_ourwine.log"
time "$W" msiexec /i "$M/mastercam/Mastercam_Installer.msi" \
  TRANSFORMS="$M/mastercam/1033.mst" \
  INSTALLDIR='C:\Program Files\Mastercam 2027' \
  SHAREDDEFAULTS='C:\ProgramData\Mastercam' \
  CNC_UNIT_TYPE=I REBOOT=ReallySuppress \
  /qn /norestart /L*v 'C:\mc_msi_ourwine.log' \
  > "$L/msi_ourwine_stdout.log" 2> "$L/winedbg_ourwine.log"
echo "MSIEXEC_EXIT=$?"

echo "=== 5. post-checks ==="
echo "-- monitor (uniq) --"; uniq -f1 "$L/keymon3.log" | head -20
echo "-- PS key now --"
"$W" reg query 'HKLM\Software\Classes\CLSID\{00020420-0000-0000-C000-000000000046}\InprocServer32' 2>&1 | sed -n '3p'
echo "-- install dir --"
ls -la "$P/drive_c/Program Files/Mastercam 2027/" 2>&1 | head -25
echo "files: $(find "$P/drive_c/Program Files/Mastercam 2027" -type f 2>/dev/null | wc -l)"
du -sh "$P/drive_c/Program Files/Mastercam 2027" 2>/dev/null
ls -la "$P/drive_c/Program Files/Mastercam 2027/MastercamLauncher.exe" "$P/drive_c/Program Files/Mastercam 2027/Mastercam.exe" "$P/drive_c/Program Files/Mastercam 2027/Mastercam.dll" 2>&1
echo "-- MSI log: decisive --"
grep -anE "Failed to initialize 64-bit helper|Error 27555|ApplyPermissionsItems|Action ended [0-9:]+: (InstallFinalize|ISLockPermissionsInstall|RegisterClassInfo|UnregisterClassInfo|INSTALL)" "$P/drive_c/mc_msi_ourwine.log" 2>/dev/null | head -20
echo "-- MSI log tail --"; tail -5 "$P/drive_c/mc_msi_ourwine.log" 2>/dev/null
echo "-- stderr err:msi / err:ole --"
grep -anE "err:msi|err:ole:apartment_add_dll|no class object" "$L/winedbg_ourwine.log" | head -15

echo "=== 6. regression probes in new prefix ==="
cd /run/media/asdf/Windows/mc-scratch
"$W" ./ps_test32.exe 2>/dev/null | head -6
"$W" ./ps_test64.exe 2>/dev/null | head -6
cd "$ROOT"

echo "=== 7. launch attempt ($(date +%T)) ==="
if [ -f "$P/drive_c/Program Files/Mastercam 2027/MastercamLauncher.exe" ]; then
  export MCW_LOGS=$L
  tools/run_mastercam.sh mcfix --secs 90 --iv 15 --prefix "$P" --wine "$W" \
      --debug '+timestamp,+err,+warn' --exe MastercamLauncher.exe || true
  echo "-- run dir --"; ls -la "$L/runs/mcfix" 2>/dev/null | head -20
  echo "-- app stderr head --"; head -40 "$L/runs/mcfix/app.stderr" 2>/dev/null
else
  echo "no MastercamLauncher.exe installed - launch step skipped"
fi
echo "=== DONE ($(date +%T)) ==="
