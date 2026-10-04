$ErrorActionPreference = 'Continue'
function Size($p) { if (Test-Path $p) { (Get-ChildItem $p -Recurse -File -Force -EA SilentlyContinue | Measure-Object Length -Sum).Sum } else { -1 } }
"FREE_GB={0:N3}" -f ((Get-PSDrive C).Free/1GB)
"=== C:\ProgramData\ETC breakdown ==="
Get-ChildItem 'C:\ProgramData\ETC' -Directory -Force -EA SilentlyContinue | ForEach-Object { "ETCSUB {0} {1:N2} GB" -f $_.Name, ((Size $_.FullName)/1GB) }
"=== C:\Users\adsf\AppData breakdown ==="
Get-ChildItem 'C:\Users\adsf\AppData\Local' -Directory -Force -EA SilentlyContinue | ForEach-Object { $s=Size $_.FullName; if ($s -gt 50MB) { "LOCAL {0} {1:N2} GB" -f $_.Name, ($s/1GB) } }
Get-ChildItem 'C:\Users\adsf\AppData\Roaming' -Directory -Force -EA SilentlyContinue | ForEach-Object { $s=Size $_.FullName; if ($s -gt 50MB) { "ROAMING {0} {1:N2} GB" -f $_.Name, ($s/1GB) } }
"=== Downloads ==="
Get-ChildItem 'C:\Users\adsf\Downloads' -Force -EA SilentlyContinue | ForEach-Object { "DL {0} {1:N2} MB" -f $_.Name, ($_.Length/1MB) }
"=== Package Cache ==="
Get-ChildItem 'C:\ProgramData\Package Cache' -Directory -Force -EA SilentlyContinue | ForEach-Object { "PKG {0} {1:N2} GB" -f $_.Name, ((Size $_.FullName)/1GB) }
"=== Windows\Installer recent 400MB+ ==="
Get-ChildItem 'C:\Windows\Installer' -File -Force -EA SilentlyContinue | Where-Object { $_.Length -gt 400MB } | ForEach-Object { "CACHE {0} {1:N2} GB {2}" -f $_.Name, ($_.Length/1GB), $_.LastWriteTime }
"=== C:\hog ==="
Get-ChildItem 'C:\hog' -Force -EA SilentlyContinue | ForEach-Object { "HOG {0} {1:N2} MB" -f $_.Name, ($_.Length/1MB) }
