# Harvest the state a real Tableau install creates on Windows - this is what the Wine side must reproduce,
# and what lets us install the FlexNet licensing service there without guessing.
# Runs ON the guest; PUTs one zip back to the :8000 hub and lists what it captured.
$ErrorActionPreference = 'Continue'
$hub = 'http://192.168.122.1:8000/'
$stage = Join-Path $env:USERPROFILE 'tabharvest'
$zip = Join-Path $env:USERPROFILE 'tabharvest.zip'
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $stage | Out-Null

# 1. the licensing service: binaries + any driver/registry anchor
$svc = Join-Path ${env:CommonProgramFiles} 'Macrovision Shared\FLEXnet Publisher'
if (Test-Path $svc) { Copy-Item $svc (Join-Path $stage 'flexnet') -Recurse -Force -ErrorAction SilentlyContinue }
# 2. Trusted Storage
foreach ($p in @((Join-Path $env:ProgramData 'FLEXnet'), 'C:\ProgramData\FLEXnet')) {
    if (Test-Path $p) { Copy-Item $p (Join-Path $stage 'FLEXnet-data') -Recurse -Force -ErrorAction SilentlyContinue; break }
}
# 3. registry state the app reads
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'reg') | Out-Null
foreach ($k in @('HKLM\SOFTWARE\Tableau', 'HKLM\SOFTWARE\WOW6432Node\Tableau', 'HKLM\SYSTEM\CurrentControlSet\Services\FNPLicensingService64', 'HKLM\SYSTEM\CurrentControlSet\Services\FlexNet Licensing Service 64')) {
    $f = Join-Path $stage ('reg\' + ($k -replace '[\\]', '_') + '.reg')
    reg.exe export $k $f /y 2>&1 | Out-Null
}
# 4. what actually got installed (file list + versions + the MSI's ARP entry)
Get-ChildItem 'C:\Program Files\Tableau' -Recurse -File -ErrorAction SilentlyContinue |
    Select-Object FullName, Length | Export-Csv (Join-Path $stage 'tableau_files.csv') -NoTypeInformation
Get-Service | Where-Object { $_.Name -like '*FNP*' -or $_.DisplayName -like '*FlexNet*' } |
    Select-Object Name, DisplayName, Status, StartType | Export-Csv (Join-Path $stage 'services.csv') -NoTypeInformation

Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force
Write-Output ('zip_bytes=' + (Get-Item $zip).Length)
curl.exe -s -T $zip ($hub + 'tabharvest.zip') | Out-Null
Write-Output 'uploaded=1'
Get-ChildItem $stage -Recurse -File -ErrorAction SilentlyContinue |
    Group-Object { $_.Directory.Name } | ForEach-Object { Write-Output ($_.Name + '=' + $_.Count) }
