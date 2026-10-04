$ErrorActionPreference = 'Continue'
function Size($p) { if (Test-Path $p) { (Get-ChildItem $p -Recurse -File -Force -EA SilentlyContinue | Measure-Object Length -Sum).Sum } else { -1 } }
"FREE_BEFORE_GB={0:N3}" -f ((Get-PSDrive C).Free/1GB)

# 1. leftover from the failed Hog install (fixture-library extraction debris)
$p = 'C:\ProgramData\ETC\HogPC'
if (Test-Path $p) { "REMOVING $p ({0:N2} GB)" -f ((Size $p)/1GB); Remove-Item $p -Recurse -Force -EA SilentlyContinue }
# 2. Eos Family install from the previous project (explicitly OK to remove if room needed)
foreach ($p in 'C:\Program Files\ETC','C:\ProgramData\ETC\EosFamily','C:\Program Files (x86)\ETC\EosFamily','C:\Users\adsf\AppData\Local\ETC','C:\Users\adsf\AppData\Roaming\ETC') {
  if (Test-Path $p) { "REMOVING $p ({0:N2} GB)" -f ((Size $p)/1GB); Remove-Item $p -Recurse -Force -EA SilentlyContinue }
}
# 3. Eos apitrace leftovers
foreach ($p in 'C:\apitrace','C:\eos-ref','C:\Users\adsf\AppData\Local\ETC') {
  if (Test-Path $p) { "REMOVING $p ({0:N2} GB)" -f ((Size $p)/1GB); Remove-Item $p -Recurse -Force -EA SilentlyContinue }
}
# empty the ETC ProgramData dir if nothing left
if ((Test-Path 'C:\ProgramData\ETC') -and -not (Get-ChildItem 'C:\ProgramData\ETC' -Force -EA SilentlyContinue)) { Remove-Item 'C:\ProgramData\ETC' -Recurse -Force -EA SilentlyContinue }
"FREE_AFTER_GB={0:N3}" -f ((Get-PSDrive C).Free/1GB)
"USED_AFTER_GB={0:N3}" -f ((Get-PSDrive C).Used/1GB)
