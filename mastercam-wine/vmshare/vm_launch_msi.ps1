$ErrorActionPreference='Continue'
$U='http://192.168.122.1:8000/'
$B='C:\Users\adsf\vm_msi.ps1'
curl.exe -s -o $B ($U+'vm_msi.ps1')
"msi_script_bytes=" + (Get-Item $B).Length
Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$B
"runas-returned"
