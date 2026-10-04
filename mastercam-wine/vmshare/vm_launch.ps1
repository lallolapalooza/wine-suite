$ErrorActionPreference='Continue'
$U='http://192.168.122.1:8000/'
$B='C:\Users\adsf\vm_mc_boot.ps1'
curl.exe -s -o $B ($U+'vm_mc_boot.ps1')
"boot_script_bytes=" + (Get-Item $B).Length
"launching RunAs..."
Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$B
"runas-returned"
Start-Sleep -Seconds 3
"--- boot log ---"
Get-Content 'C:\vm_mc_boot.log' -ErrorAction SilentlyContinue | Select-Object -First 25
