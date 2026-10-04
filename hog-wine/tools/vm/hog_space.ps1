$ErrorActionPreference = 'Continue'
"FREE_GB={0:N3}" -f ((Get-PSDrive C).Free/1GB)
"=== system files ==="
foreach ($f in 'C:\hiberfil.sys','C:\pagefile.sys','C:\swapfile.sys','C:\DumpStack.log.tmp') {
  if (Test-Path $f) { $i = Get-Item $f -Force; "SYSFILE {0} {1:N2} GB" -f $f, ($i.Length/1GB) } else { "SYSFILE {0} ABSENT" -f $f }
}
"=== hibernation state ==="
powercfg /a 2>&1 | Select-Object -First 6
"=== C:\Users\adsf top dirs ==="
Get-ChildItem C:\Users\adsf -Directory -Force -EA SilentlyContinue | ForEach-Object { $s=(Get-ChildItem $_.FullName -Recurse -File -Force -EA SilentlyContinue | Measure-Object Length -Sum).Sum; "U {0} {1:N2} GB" -f $_.Name, ($s/1GB) }
"=== C:\ProgramData top dirs ==="
Get-ChildItem C:\ProgramData -Directory -Force -EA SilentlyContinue | ForEach-Object { $s=(Get-ChildItem $_.FullName -Recurse -File -Force -EA SilentlyContinue | Measure-Object Length -Sum).Sum; if ($s -gt 100MB) { "PD {0} {1:N2} GB" -f $_.Name, ($s/1GB) } }
"=== Windows\SoftwareDistribution + DO cache ==="
foreach ($d in 'C:\Windows\SoftwareDistribution','C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization','C:\Windows\Temp','C:\Windows\Logs') {
  if (Test-Path $d) { $s=(Get-ChildItem $d -Recurse -File -Force -EA SilentlyContinue | Measure-Object Length -Sum).Sum; "WDIR {0} {1:N2} GB" -f $d, ($s/1GB) }
}
"=== eos install dirs ==="
foreach ($d in 'C:\Program Files\ETC\EosFamily','C:\Program Files\ETC\Augment3d','C:\Program Files (x86)\ETC','C:\apitrace','C:\eos-ref','C:\Program Files\ETC') {
  if (Test-Path $d) { $s=(Get-ChildItem $d -Recurse -File -Force -EA SilentlyContinue | Measure-Object Length -Sum).Sum; "EOS {0} {1:N2} GB" -f $d, ($s/1GB) }
}
"=== WinSxS ==="
$s=(Get-ChildItem 'C:\Windows\WinSxS' -Recurse -File -Force -EA SilentlyContinue | Measure-Object Length -Sum).Sum
"WINSXS {0:N2} GB" -f ($s/1GB)
