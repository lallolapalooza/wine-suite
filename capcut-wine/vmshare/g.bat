@echo off
rem run the extended volume probe on the guest, same binary as the Wine side
set U=http://192.168.122.1:8000
curl.exe -s -o C:\Users\adsf\volprobe.exe %U%/volprobe.exe
echo === dir C:\ (serial cross-check) ===
cmd /c dir C:\ | findstr /i "Serial"
echo === volprobe (no args) ===
C:\Users\adsf\volprobe.exe
echo === volprobe-rc=%ERRORLEVEL% ===
