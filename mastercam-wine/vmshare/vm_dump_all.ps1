$ErrorActionPreference='Continue'
$U='http://192.168.122.1:8000/'
$Log='C:\vm_dump.log'
function L($m){ Add-Content -Path $Log -Value ("{0} {1}" -f (Get-Date -Format o), $m) -Encoding utf8 }
function Put($p){ if (Test-Path $p) { curl.exe -s -T $p ($U + (Split-Path -Leaf $p)) | Out-Null; L ("PUT " + (Split-Path -Leaf $p) + " " + (Get-Item $p).Length + " bytes") } }
Set-Content -Path $Log -Value "" -Encoding utf8

L ("elevated=" + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
L ("freeGB=" + [math]::Round((Get-PSDrive C).Free/1GB,2))

$roots = @('C:\Program Files\Mastercam 2027','C:\Program Files\Common Files\Mastercam','C:\Program Files (x86)\Common Files\Mastercam','C:\Users\Public\Documents\Shared Mastercam 2027','C:\ProgramData\Mastercam','C:\ProgramData\Mastercam 2027','C:\Program Files\Mastercam','C:\Program Files\mcam')
foreach ($d in $roots) {
  if (Test-Path $d) {
    $tag = ($d -replace '^C:\\','' -replace '[^A-Za-z0-9]','_')
    $out = "C:\vm_tree_$tag.txt"
    $files = Get-ChildItem $d -Recurse -File -ErrorAction SilentlyContinue
    $bytes = ($files | Measure-Object Length -Sum).Sum
    Get-ChildItem $d -Recurse -ErrorAction SilentlyContinue |
      ForEach-Object { if ($_.PSIsContainer) { "DIR`t`t{0}" -f $_.FullName } else { "{0}`t{1}`t{2}" -f $_.Length, $_.LastWriteTime.ToString('s'), $_.FullName } } |
      Set-Content -Path $out -Encoding utf8
    L ("TREE $d -> $out files=$($files.Count) MB=" + [math]::Round($bytes/1MB,1))
    Put $out
    $v = "C:\vm_ver_$tag.txt"
    $files | Where-Object { $_.Extension -in '.exe','.dll' } | ForEach-Object { $i=$_.VersionInfo; "{0}`t{1}`t{2}`t{3}`t{4}" -f $_.FullName,$i.FileVersion,$i.ProductVersion,$i.CompanyName,$i.FileDescription } | Set-Content -Path $v -Encoding utf8
    Put $v
  } else { L ("absent: " + $d) }
}

L '--- uninstall registry ---'
$r = 'C:\vm_uninstall_reg.txt'
$lines = @()
foreach ($rp in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') {
  Get-ItemProperty $rp -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.DisplayName) {
      $lines += "KEY=$($_.PSPath)"
      $lines += "  DisplayName    = $($_.DisplayName)"
      $lines += "  DisplayVersion = $($_.DisplayVersion)"
      $lines += "  Publisher      = $($_.Publisher)"
      $lines += "  InstallLocation= $($_.InstallLocation)"
      $lines += "  UninstallString= $($_.UninstallString)"
      $lines += "  QuietUninstall = $($_.QuietUninstallString)"
      $lines += "  InstallDate    = $($_.InstallDate)  EstimatedSize(KB)=$($_.EstimatedSize)"
    }
  }
}
$lines | Set-Content -Path $r -Encoding utf8
L ("uninstall entries: " + (($lines | Where-Object { $_ -like 'KEY=*' }).Count))
Put $r

L '--- services ---'
$s = 'C:\vm_services.txt'
Get-Service | ForEach-Object { "{0}`t{1}`t{2}`t{3}" -f $_.Name, $_.DisplayName, $_.Status, $_.StartType } | Set-Content -Path $s -Encoding utf8
Put $s

L '--- install logs ---'
$logs = @()
$logs += Get-ChildItem $env:TEMP -Filter 'mcim_*.log' -ErrorAction SilentlyContinue
$logs += Get-ChildItem $env:TEMP -Filter '*.log' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Mastercam|mcam|CodeMeter|licens' }
$logs += Get-ChildItem 'C:\Program Files (x86)\InstallShield Installation Information' -Recurse -Filter '*.log' -ErrorAction SilentlyContinue
$logs += Get-ChildItem 'C:\ProgramData\Mastercam*' -Recurse -Filter '*.log' -ErrorAction SilentlyContinue
$logs += Get-ChildItem 'C:\ProgramData\CodeMeter' -Recurse -Filter '*.log' -ErrorAction SilentlyContinue
foreach ($f in ($logs | Select-Object -Unique -First 25)) { L ("log " + $f.FullName + " " + $f.Length + " bytes") ; if ($f.Length -lt 20MB) { curl.exe -s -T $f.FullName ($U + 'vm_' + $f.Name) | Out-Null } }

L '--- shortcuts ---'
Get-ChildItem 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs' -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Mastercam' } | ForEach-Object { L ("shortcut " + $_.FullName) }
Get-ChildItem 'C:\Users\Public\Desktop' -ErrorAction SilentlyContinue | ForEach-Object { L ("desktop " + $_.FullName) }
L 'dump-done'
Put $Log
