$ErrorActionPreference = 'Continue'
$out = 'C:\pbiref'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$U = 'http://192.168.122.1:8000/'

# 1) Internet Explorer / .NET launch-condition values (raw reg query output)
$ie = "$out\ie.txt"
"=== reg query ""HKLM\SOFTWARE\Microsoft\Internet Explorer"" ===" | Out-File $ie -Encoding utf8
(reg query "HKLM\SOFTWARE\Microsoft\Internet Explorer" 2>&1) | Out-File $ie -Append -Encoding utf8
"=== reg query ""HKLM\SOFTWARE\Microsoft\Internet Explorer"" /v Version ===" | Out-File $ie -Append -Encoding utf8
(reg query "HKLM\SOFTWARE\Microsoft\Internet Explorer" /v Version 2>&1) | Out-File $ie -Append -Encoding utf8
"=== reg query ""HKLM\SOFTWARE\WOW6432Node\Microsoft\Internet Explorer"" /v Version ===" | Out-File $ie -Append -Encoding utf8
(reg query "HKLM\SOFTWARE\WOW6432Node\Microsoft\Internet Explorer" /v Version 2>&1) | Out-File $ie -Append -Encoding utf8
"=== reg query ""HKLM\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"" ===" | Out-File $ie -Append -Encoding utf8
(reg query "HKLM\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" 2>&1) | Out-File $ie -Append -Encoding utf8
"=== file version of C:\Windows\System32\mshtml.dll (IE engine) ===" | Out-File $ie -Append -Encoding utf8
(Get-Item 'C:\Windows\System32\mshtml.dll' -ErrorAction SilentlyContinue).VersionInfo | Format-List * | Out-File $ie -Append -Encoding utf8
"=== iexplore.exe presence ===" | Out-File $ie -Append -Encoding utf8
(Test-Path 'C:\Program Files\Internet Explorer\iexplore.exe') | Out-File $ie -Append -Encoding utf8
curl.exe -s -T $ie ($U + 'guest_ie.txt') | Out-Null

# 2) registry inventory: Power BI keys / uninstall entries
$reg = "$out\registry.txt"
"=== HKLM\SOFTWARE\Microsoft\Office\16.0\Power BI Desktop /s ===" | Out-File $reg -Encoding utf8
(reg query "HKLM\SOFTWARE\Microsoft\Office\16.0\Power BI Desktop" /s 2>&1) | Out-File $reg -Append -Encoding utf8
"=== HKCU\Software\Microsoft\Microsoft Power BI Desktop /s ===" | Out-File $reg -Append -Encoding utf8
(reg query "HKCU\Software\Microsoft\Microsoft Power BI Desktop" /s 2>&1) | Out-File $reg -Append -Encoding utf8
"=== HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall search 'Power BI' ===" | Out-File $reg -Append -Encoding utf8
(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' | ForEach-Object {
    $p = Get-ItemProperty $_.PSPath
    if ($p.DisplayName -match 'Power BI') { $_.PSChildName + ' | ' + $p.DisplayName + ' | ' + $p.DisplayVersion + ' | ' + $p.InstallLocation + ' | ' + $p.UninstallString }
  } | Out-File $reg -Append -Encoding utf8)
"=== HKLM\SOFTWARE\WOW6432Node\...\Uninstall search 'Power BI' ===" | Out-File $reg -Append -Encoding utf8
(Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue | ForEach-Object {
    $p = Get-ItemProperty $_.PSPath
    if ($p.DisplayName -match 'Power BI') { $_.PSChildName + ' | ' + $p.DisplayName + ' | ' + $p.DisplayVersion + ' | ' + $p.InstallLocation }
  } | Out-File $reg -Append -Encoding utf8)
"=== HKCU uninstall search 'Power BI' ===" | Out-File $reg -Append -Encoding utf8
(Get-ChildItem 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue | ForEach-Object {
    $p = Get-ItemProperty $_.PSPath
    if ($p.DisplayName -match 'Power BI') { $_.PSChildName + ' | ' + $p.DisplayName + ' | ' + $p.DisplayVersion + ' | ' + $p.InstallLocation }
  } | Out-File $reg -Append -Encoding utf8)
curl.exe -s -T $reg ($U + 'guest_registry.txt') | Out-Null

# 3) installed tree + version info
$d = "$out\install_dir.txt"
$root = 'C:\Program Files\Microsoft Power BI Desktop'
"=== test-path $root ===" | Out-File $d -Encoding utf8
(Test-Path $root) | Out-File $d -Append -Encoding utf8
"=== recursive listing ===" | Out-File $d -Append -Encoding utf8
(Get-ChildItem $root -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName + ' | ' + $_.Length } | Out-File $d -Append -Encoding utf8)
"=== version info: bin\PBIDesktop.exe ===" | Out-File $d -Append -Encoding utf8
(Get-Item "$root\bin\PBIDesktop.exe" -ErrorAction SilentlyContinue).VersionInfo | Format-List * | Out-File $d -Append -Encoding utf8
"=== version info: bin\PBIDesktop.dll ===" | Out-File $d -Append -Encoding utf8
(Get-Item "$root\bin\PBIDesktop.dll" -ErrorAction SilentlyContinue).VersionInfo | Format-List * | Out-File $d -Append -Encoding utf8
"=== start menu shortcuts ===" | Out-File $d -Append -Encoding utf8
(Get-ChildItem 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs' -Recurse -Filter '*Power BI*' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) | Out-File $d -Append -Encoding utf8
(Get-ChildItem 'C:\Users\adsf\AppData\Roaming\Microsoft\Windows\Start Menu\Programs' -Recurse -Filter '*Power BI*' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) | Out-File $d -Append -Encoding utf8
"=== installed apps via MSI ===" | Out-File $d -Append -Encoding utf8
(Get-CimInstance Win32_Product -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Power BI' } | Select-Object Name, Version, IdentifyingNumber, InstallLocation | Format-List | Out-String) | Out-File $d -Append -Encoding utf8
curl.exe -s -T $d ($U + 'guest_install_dir.txt') | Out-Null

# 4) runtimes
$r = "$out\runtimes.txt"
"=== webview2 machine ===" | Out-File $r -Encoding utf8
(reg query 'HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}' 2>&1) | Out-File $r -Append -Encoding utf8
"=== webview2 user ===" | Out-File $r -Append -Encoding utf8
(reg query 'HKCU\Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}' 2>&1) | Out-File $r -Append -Encoding utf8
"=== dotnet --info ===" | Out-File $r -Append -Encoding utf8
(curl.exe -s -o "$out\dotnet-info-open.txt" 'nul') | Out-Null
(& "$env:ProgramFiles\dotnet\dotnet.exe" --list-runtimes 2>&1) | Out-File $r -Append -Encoding utf8
"=== .NET Framework NDP v4 Full ===" | Out-File $r -Append -Encoding utf8
(reg query 'HKLM\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' 2>&1) | Out-File $r -Append -Encoding utf8
"=== power BI bundled dlls of interest ===" | Out-File $r -Append -Encoding utf8
(Get-ChildItem "$root\bin" -Filter '*.dll' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'WebView|Edge|WinRT|dotnet|coreclr|hostfxr' } | ForEach-Object { $_.Name + ' | ' + $_.Length + ' | ' + $_.VersionInfo.FileVersion }) | Out-File $r -Append -Encoding utf8
curl.exe -s -T $r ($U + 'guest_runtimes.txt') | Out-Null

Write-Host "INVENTORY-DONE"
