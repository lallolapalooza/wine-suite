# Elevated guest-side capture of the Hog PC install ground truth.
# Run through tools/vm/vmcmda.sh -f tools/vm/hog_capture.ps1 <timeout>
$ErrorActionPreference = 'Continue'
$base = 'http://192.168.122.1:8000'
$hogLines  = New-Object System.Collections.Generic.List[string]

$hogLines.Add("=== FREE / DRIVES")
$hogLines.Add(("FREE_GB={0:N3} USED_GB={1:N3}" -f ((Get-PSDrive C).Free/1GB), ((Get-PSDrive C).Used/1GB)))

$roots = @('C:\Program Files (x86)\ETC\HogPC','C:\Program Files\ETC\HogPC')
$root = $roots | Where-Object { Test-Path $_ } | Select-Object -First 1
$hogLines.Add("=== INSTALL ROOT")
$hogLines.Add("ROOT=$root")

$hogLines.Add("=== TREE (files, relative path, size)")
if ($root) {
  Get-ChildItem $root -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $rel = $_.FullName.Substring($root.Length).TrimStart('\')
    if ($_.PSIsContainer) { $hogLines.Add("D $rel\") }
    else { $hogLines.Add(("F {0} {1}" -f $rel, $_.Length)) }
  }
}

$hogLines.Add("=== TOP-LEVEL DIR SIZES")
if ($root) {
  Get-ChildItem $root -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $s = (Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    $hogLines.Add(("DIRSIZE {0} {1:N3} MB" -f $_.Name, ($s/1MB)))
  }
  $tot = (Get-ChildItem $root -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
  $hogLines.Add(("TOTAL {0:N1} MB" -f ($tot/1MB)))
}

$hogLines.Add("=== PROGRAMDATA ETC\HogPC tree")
$pd = 'C:\ProgramData\ETC\HogPC'
if (Test-Path $pd) {
  Get-ChildItem $pd -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $rel = $_.FullName.Substring($pd.Length).TrimStart('\')
    if ($_.PSIsContainer) { $hogLines.Add("PD D $rel\") } else { $hogLines.Add("PD F $rel $($_.Length)") }
  }
}

$hogLines.Add("=== EXE FILES (name size version)")
if ($root) {
  Get-ChildItem $root -Recurse -File -Filter *.exe -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $v = $_.VersionInfo.FileVersion
    $hogLines.Add(("EXE {0} {1} v{2}" -f $_.FullName, $_.Length, $v))
  }
}

$hogLines.Add("=== UNINSTALL REGISTRY ENTRIES")
foreach ($hive in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') {
  Get-ChildItem $hive -ErrorAction SilentlyContinue | ForEach-Object {
    $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
    if ($p.DisplayName -match 'Hog' -or $p.Publisher -match 'High End') {
      $hogLines.Add(("UNINST {0}" -f $_.PSPath))
      $hogLines.Add(("  DisplayName={0}" -f $p.DisplayName))
      $hogLines.Add(("  DisplayVersion={0}" -f $p.DisplayVersion))
      $hogLines.Add(("  Publisher={0}" -f $p.Publisher))
      $hogLines.Add(("  InstallLocation={0}" -f $p.InstallLocation))
      $hogLines.Add(("  UninstallString={0}" -f $p.UninstallString))
      $hogLines.Add(("  EstimatedSize={0}" -f $p.EstimatedSize))
    }
  }
}

$hogLines.Add("=== SOFTWARE\ETC REGISTRY")
foreach ($k in 'HKLM:\SOFTWARE\ETC\HogPC','HKLM:\SOFTWARE\WOW6432Node\ETC\HogPC') {
  if (Test-Path $k) {
    $hogLines.Add("KEY $k")
    Get-ItemProperty $k | Out-String -Stream | ForEach-Object { if ($_.Trim()) { $hogLines.Add("  $_") } }
  }
}

$hogLines.Add("=== SERVICES")
foreach ($n in 'fpstftp','fpsdhcp') {
  $s = Get-Service $n -ErrorAction SilentlyContinue
  if ($s) {
    $w = Get-CimInstance Win32_Service -Filter "Name='$n'" -ErrorAction SilentlyContinue
    $hogLines.Add(("SVC {0} Status={1} StartType={2} Path={3}" -f $n, $s.Status, $s.StartType, $w.PathName))
  } else { $hogLines.Add("SVC $n ABSENT") }
}

$hogLines.Add("=== SHORTCUTS")
foreach ($d in ("$env:ProgramData\Microsoft\Windows\Start Menu\Programs","$env:APPDATA\Microsoft\Windows\Start Menu\Programs","$env:USERPROFILE\Desktop","$env:PUBLIC\Desktop")) {
  Get-ChildItem $d -Recurse -Filter *.lnk -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Hog|Widget' } | ForEach-Object {
    $sh = New-Object -ComObject WScript.Shell
    $l = $sh.CreateShortcut($_.FullName)
    $hogLines.Add(("LNK {0} -> {1} {2} WkDir={3}" -f $_.FullName, $l.TargetPath, $l.Arguments, $l.WorkingDirectory))
  }
}

$hogLines.Add("=== HASP DRIVER REGISTRY (Aladdin)")
foreach ($k in 'HKLM:\SOFTWARE\Aladdin Knowledge Systems\HASP\Driver\Installer','HKLM:\SOFTWARE\WOW6432Node\Aladdin Knowledge Systems\HASP\Driver\Installer') {
  if (Test-Path $k) { $hogLines.Add("KEY $k"); Get-ItemProperty $k | Out-String -Stream | ForEach-Object { if ($_.Trim()) { $hogLines.Add("  $_") } } }
  else { $hogLines.Add("KEY $k ABSENT") }
}

$hogLines.Add("=== FIREWALL RULES (Hog)")
Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'Hog|HASP|fpstftp|fpsdhcp' } | ForEach-Object { $hogLines.Add(("FW {0} {1} {2}" -f $_.DisplayName, $_.Direction, $_.Action)) }

$txt = $hogLines -join "`n"
Set-Content -Path 'C:\hog\hog_capture.txt' -Value $txt -Encoding UTF8
& curl.exe -s -T 'C:\hog\hog_capture.txt' "$base/vm_hog_capture.txt" | Out-Null
$hogLines | ForEach-Object { $_ }
