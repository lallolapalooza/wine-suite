@echo off
rem Bootstrap the hardened guest command channel. Run this once from the guest GUI
rem (e.g. Win+R: cmd /c curl -s -o %TEMP%\m.bat http://192.168.122.1:8000/mc_svc.bat ^& %TEMP%\m.bat).
set U=http://192.168.122.1:8000/
if not exist C:\seref mkdir C:\seref
curl.exe -s -o C:\seref\runner.ps1 %U%runner.ps1
curl.exe -s -o C:\seref\poller.ps1 %U%se_svc2.ps1
taskkill /f /im powershell.exe >nul 2>&1
timeout /t 1 /nobreak >nul
start "" powershell -NoProfile -ExecutionPolicy Bypass -File C:\seref\poller.ps1
exit
