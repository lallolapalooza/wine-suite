@echo off
rem Guest-side launcher: fetch the polling service and start it detached.
set U=http://192.168.122.1:8000/
set H=%USERPROFILE%
curl.exe -s -o "%H%\s.ps1" %U%se_svc.ps1
type "%H%\s.ps1" > "%H%\s2.ps1"
start "" powershell -NoProfile -ExecutionPolicy Bypass -File "%H%\s2.ps1"
exit
