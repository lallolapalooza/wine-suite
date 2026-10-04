$A = "C:\Users\adsf\AppData\Local\CapCut\Apps"
$z = "C:\Users\adsf\capcut_payload.zip"
$list = "C:\Users\adsf\capcut_listing.txt"
Write-Output "=== sizes ==="
$all = Get-ChildItem $A -Recurse -File -Force -ErrorAction SilentlyContinue
$sum = ($all | Measure-Object Length -Sum)
Write-Output ("FILES=" + $sum.Count + " TOTAL_BYTES=" + $sum.Sum + " (MiB=" + [math]::Round($sum.Sum/1MB,1) + ")")
Write-Output "=== build listing ==="
$all | Sort-Object FullName | ForEach-Object { "{0}`t{1}" -f $_.Length, $_.FullName } | Set-Content -Path $list -Encoding UTF8
Get-Item $list | Select-Object Length | Format-List
Write-Output "=== sha256 of main exes ==="
Write-Output ((Get-FileHash "$A\CapCut.exe" -Algorithm SHA256).Hash + "  Apps\CapCut.exe")
Write-Output ((Get-FileHash "$A\9.5.0.4050\CapCut.exe" -Algorithm SHA256).Hash + "  Apps\9.5.0.4050\CapCut.exe")
Write-Output "=== zip app tree ==="
if (Test-Path $z) { Remove-Item $z -Force }
Push-Location "C:\Users\adsf\AppData\Local\CapCut"
& tar.exe -a -c -f $z "Apps"
Pop-Location
Get-Item $z | Select-Object Length | Format-List
Write-Output ("ZIP_SHA256=" + (Get-FileHash $z -Algorithm SHA256).Hash)
Write-Output "=== zip logs ==="
$wl = "C:\Users\adsf\winlog.zip"
if (Test-Path $wl) { Remove-Item $wl -Force }
& tar.exe -a -c -f $wl -C "C:\Users\adsf\AppData\Local\CapCut\User Data" "Log" "Config"
Get-Item $wl | Select-Object Length | Format-List
Write-Output ("WINLOG_SHA256=" + (Get-FileHash $wl -Algorithm SHA256).Hash)
Write-Output "=== PUT ==="
curl.exe -s -T $z http://192.168.122.1:8000/capcut_payload.zip
curl.exe -s -T $list http://192.168.122.1:8000/capcut_listing.txt
curl.exe -s -T $wl http://192.168.122.1:8000/winlog.zip
curl.exe -s -T "$A\ProductInfo.xml" http://192.168.122.1:8000/ProductInfo.xml
Write-Output "=== free ==="
(Get-PSDrive C).Free
Write-Output "DONE"
