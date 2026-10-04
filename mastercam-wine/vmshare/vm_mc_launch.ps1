$U='http://192.168.122.1:8000/'
$L='C:\Users\adsf\vm_mc_install.ps1'
curl.exe -s -o $L ($U+'vm_mc_install.ps1')
if ((Get-Item $L).Length -lt 3000) { Write-Host 'MAIN SCRIPT DOWNLOAD FAILED'; exit 1 }
& $L -Mode launch
