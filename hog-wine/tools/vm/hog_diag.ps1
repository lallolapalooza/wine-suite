$ErrorActionPreference = 'Continue'
$root = 'C:\Program Files (x86)\ETC\HogPC'
"ROOT_EXISTS=$(Test-Path $root)"
if (Test-Path $root) {
  "TOPLEVEL:"
  Get-ChildItem $root -Force | ForEach-Object { "  {0} {1}" -f $_.Mode, $_.Name }
  $tot = (Get-ChildItem $root -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
  "TOTAL_MB={0:N1}" -f ($tot/1MB)
  "EXE_COUNT={0}" -f (Get-ChildItem $root -Recurse -File -Filter *.exe -Force -EA SilentlyContinue).Count
}
"=== LOG keyword lines (last 60) ==="
Select-String -Path C:\hog\hog_msi.log -Pattern 'Return value 3','Note: 1: 2262','Error 1','Product: ','MainEngineThread is returning','1603','CustomAction ','Installation success or error status' -EA SilentlyContinue | Select-Object -Last 60 | ForEach-Object { $_.Line }
"=== MSI cache / installer dir ==="
"FREE_GB={0:N3}" -f ((Get-PSDrive C).Free/1GB)
(Get-ChildItem C:\Windows\Installer -File -Force -EA SilentlyContinue | Measure-Object Length -Sum).Sum/1MB
