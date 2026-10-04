$ErrorActionPreference='Continue'
$b=[math]::Round((Get-PSDrive C).Free/1GB,2)
"free_before_GB=$b"
"--- kill leftover resolume processes ---"
Get-Process -Name Arena,Resolume -ErrorAction SilentlyContinue | ForEach-Object { "kill " + $_.ProcessName + " " + $_.Id; Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
"--- delete reclaimable files ---"
$cand = @('C:\Users\adsf\Downloads\ResArena.exe','C:\Users\adsf\AppData\Local\Temp\mcsize.txt')
$cand += (Get-ChildItem 'C:\Users\adsf\Downloads' -Filter '*Resolume*' -ErrorAction SilentlyContinue | ForEach-Object FullName)
$cand += (Get-ChildItem 'C:\' -Filter 'res_install*' -ErrorAction SilentlyContinue | ForEach-Object FullName)
$cand += (Get-ChildItem 'C:\' -Filter 'mc.exe' -ErrorAction SilentlyContinue | ForEach-Object FullName)
foreach ($f in ($cand | Select-Object -Unique)) {
  if (Test-Path $f) { "{0}  {1:N0} MB" -f $f, ((Get-Item $f -EA 0).Length/1MB); Remove-Item $f -Force -Recurse -ErrorAction SilentlyContinue }
}
"--- clear temp ---"
Get-ChildItem 'C:\Users\adsf\AppData\Local\Temp' -Force -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
Get-ChildItem 'C:\Windows\Temp' -Force -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
"--- windows.old ---"
if (Test-Path 'C:\Windows.old') { "present"; Remove-Item 'C:\Windows.old' -Recurse -Force -ErrorAction SilentlyContinue } else { "absent" }
"--- installed apps of interest ---"
foreach ($p in 'C:\Program Files\Resolume Arena','C:\Program Files\Resolume','C:\Program Files\Power BI Desktop','C:\Program Files\Microsoft Power BI Desktop') {
  if (Test-Path $p) {
    $s=(Get-ChildItem $p -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum)
    "INSTALLED {0}  {1:N0} MB" -f $p, ($s.Sum/1MB)
  }
}
$a=[math]::Round((Get-PSDrive C).Free/1GB,2)
"free_after_GB=$a freed_GB=$([math]::Round($a-$b,2))"
"--- E: media ---"
Get-ChildItem E:\ -ErrorAction SilentlyContinue | ForEach-Object { "{0,-30} {1}" -f $_.Name, $(if($_.PSIsContainer){'<dir>'}else{$_.Length}) }
"setup.exe on E: -> " + (Test-Path 'E:\setup.exe')
"msi on E: -> " + (Test-Path 'E:\mastercam\Mastercam_Installer.msi') + " size=" + (Get-Item 'E:\mastercam\Mastercam_Installer.msi' -EA 0).Length
"--- .NET ---"
$ndp = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue
"NETFramework4.8+ Version=" + $ndp.Version + " Release=" + $ndp.Release
"dotnet.exe -> " + (Test-Path 'C:\Program Files\dotnet\dotnet.exe')
foreach ($d in 'Microsoft.WindowsDesktop.App','Microsoft.NETCore.App','Microsoft.AspNetCore.App') {
  $p = "C:\Program Files\dotnet\shared\$d"
  if (Test-Path $p) { "  {0}: {1}" -f $d, ((Get-ChildItem $p | ForEach-Object Name) -join ',') } else { "  ${d}: absent" }
}
& 'C:\Program Files\dotnet\dotnet.exe' --list-runtimes 2>&1 | Select-Object -First 25
"--- VC runtime ---"
(Get-ChildItem 'C:\Windows\System32\vcruntime140*.dll','C:\Windows\System32\msvcp140*.dll' -EA 0 | ForEach-Object { $_.Name + '=' + $_.VersionInfo.FileVersion }) -join ' '
"done"
