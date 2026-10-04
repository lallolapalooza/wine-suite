$ErrorActionPreference='Continue'
$U='http://192.168.122.1:8000/'
$B='C:\Users\adsf\vm_mc_step2.ps1'
curl.exe -s -o $B ($U+'vm_mc_step2.ps1')
"step2_script_bytes=" + (Get-Item $B).Length
Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$B
"runas-returned"
Start-Sleep -Seconds 5
Get-Content 'C:\vm_mc_step2.log' -ErrorAction SilentlyContinue
