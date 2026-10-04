$ErrorActionPreference = 'Continue'
$pd = 'C:\ProgramData\ETC\HogPC'
"PD_EXISTS=$(Test-Path $pd)"
if (Test-Path $pd) {
  Get-ChildItem $pd -Force | ForEach-Object { "PD_TOP {0} {1}" -f $_.Mode, $_.Name }
  foreach ($sub in 'fixtureLibrary','helptext','image','drivers') {
    $p = Join-Path $pd $sub
    if (Test-Path $p) {
      $s = (Get-ChildItem $p -Recurse -File -Force -EA SilentlyContinue | Measure-Object Length -Sum).Sum
      "PDSIZE {0} {1:N1} MB files={2}" -f $sub, ($s/1MB), (Get-ChildItem $p -Recurse -File -Force -EA SilentlyContinue).Count
    }
  }
  $all = (Get-ChildItem $pd -Recurse -File -Force -EA SilentlyContinue | Measure-Object Length -Sum).Sum
  "PD_TOTAL {0:N1} MB" -f ($all/1MB)
  Get-ChildItem $pd -Recurse -Force -EA SilentlyContinue -Filter 'fixturelib*' | ForEach-Object { "FIXLIB {0} {1}" -f $_.FullName, $_.Length }
  Get-ChildItem $pd -Recurse -Force -EA SilentlyContinue -Filter '7za.exe' | ForEach-Object { "7ZA {0} {1}" -f $_.FullName, $_.Length }
}
"APPDATA_ETC=$(Test-Path $env:APPDATA\ETC)"
"=== C:\Program Files (x86)\ETC ==="
Get-ChildItem 'C:\Program Files (x86)\ETC' -Force -EA SilentlyContinue | ForEach-Object { "PF {0} {1}" -f $_.Mode, $_.Name }
"=== free ==="
"FREE_GB={0:N3}" -f ((Get-PSDrive C).Free/1GB)
"=== registry ETC HogPC ==="
foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\ETC\HogPC','HKLM:\SOFTWARE\ETC\HogPC') { "KEY $k exists=$(Test-Path $k)" }
"=== services ==="
Get-Service fpstftp,fpsdhcp -EA SilentlyContinue | ForEach-Object { "SVC {0} {1}" -f $_.Name, $_.Status }
"=== uninstall entry ==="
Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' -EA SilentlyContinue | ForEach-Object { $p=Get-ItemProperty $_.PSPath -EA SilentlyContinue; if ($p.DisplayName -match 'Hog') { "UNINST {0} {1}" -f $_.PSChildName, $p.DisplayName } }
