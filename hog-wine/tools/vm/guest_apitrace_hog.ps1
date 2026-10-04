# Guest-side capture of the Hog PC start-up on Windows with the 32-bit IAT tracer.
#
# launcher-win32-golden.exe carries a requireAdministrator manifest
# (CreateProcessW from a medium-integrity process fails with GetLastError=740), so
# this script must run ELEVATED:   tools/vm/elev.sh tools/vm/guest_apitrace_hog.ps1
#
# Pass 1: launcher-win32-golden.exe traced from its first instruction; server/desktop/
#         critical/dp8k children are attached as soon as they appear.
# Pass 2: if a show exists, server-win32-golden then desktop-win32-golden are started
#         directly under the tracer.
# Every win_hog*.log is PUT back to http://192.168.122.1:8000/ .
$ErrorActionPreference = 'Continue'
$base = 'http://192.168.122.1:8000'
$dir  = 'C:\hog\apitrace32'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$status = "$dir\win_hog_status.txt"
Start-Transcript -Path $status -Force | Out-Null
"FREE_BEFORE_GB=$([math]::Round((Get-PSDrive C).Free/1GB,3))"

foreach ($f in 'apihook.dll','apitrace.exe','hog.cfg') {
  curl.exe -s -o (Join-Path $dir $f) "$base/$f"
  "GOT $f $((Get-Item (Join-Path $dir $f)).Length)"
}

$appdir = 'C:\Program Files (x86)\ETC\HogPC'
$exe = Join-Path $appdir 'launcher-win32-golden.exe'
"EXE_OK=$(Test-Path $exe)  ELEVATED=$([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)"
Get-Process *win32-golden*,GadgetDrvChange,QtWebEngineProcess -ErrorAction SilentlyContinue | ForEach-Object {
  "KILLING $($_.ProcessName) $($_.Id)"; Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2
Remove-Item "$dir\win_hog*.log" -ErrorAction SilentlyContinue

# ---- pass 1: launcher (traced) + children (attached) -------------------------
# Start-Process -ArgumentList joins arrays with spaces and does NOT quote elements,
# so build one explicitly quoted string instead (the app dir has spaces).
$log = "$dir\win_hog_launcher.log"
$argstr = '--cfg "{0}" --out "{1}" --timeout 70 -- "{2}"' -f "$dir\hog.cfg", $log, $exe
$p = Start-Process -FilePath "$dir\apitrace.exe" -ArgumentList $argstr -WorkingDirectory $appdir -PassThru
"TRACER_PID=$($p.Id)"
$attached = @{}
$deadline = (Get-Date).AddSeconds(66)
while ((Get-Date) -lt $deadline -and -not $p.HasExited) {
  foreach ($role in @('server','desktop','critical','dp8k')) {
    $proc = Get-Process "$role-win32-golden" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc -and -not $attached.ContainsKey($proc.Id)) {
      $attached[$proc.Id] = $true
      $al = "$dir\win_hog_$role.log"
      $astr = '--pid {0} --cfg "{1}" --out "{2}"' -f $proc.Id, "$dir\hog.cfg", $al
      Start-Process -FilePath "$dir\apitrace.exe" -ArgumentList $astr | Out-Null
      "ATTACHED $role pid=$($proc.Id)"
    }
  }
  Start-Sleep -Milliseconds 300
}
$p.WaitForExit()
"PASS1_RC=$($p.ExitCode)"

# ---- pass 2: server + desktop directly (show creation + console UI) ----------
$shows = Join-Path $env:USERPROFILE 'Documents\ETC\HogPC\Shows'
$show = Get-ChildItem $shows -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
"SHOW_EXISTS=$([bool]$show)"
if ($show) {
  Get-Process *win32-golden* -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
  Start-Sleep -Seconds 2
  $srv = Join-Path $appdir 'server-win32-golden.exe'
  $sstr = '--cfg "{0}" --out "{1}" --nowait -- "{2}" -port=6600 -netnum=1 "-showpath={3}" "-showname={4}"' -f `
      "$dir\hog.cfg", "$dir\win_hog_server.log", $srv, ($shows -replace '\\','/'), $show.Name
  Start-Process -FilePath "$dir\apitrace.exe" -ArgumentList $sstr -WorkingDirectory $appdir | Out-Null
  for ($i=0; $i -lt 60; $i++) { if (Get-NetTCPConnection -LocalPort 6600 -State Listen -ErrorAction SilentlyContinue) { break }; Start-Sleep -Milliseconds 500 }
  "SERVER_UP=$([bool](Get-NetTCPConnection -LocalPort 6600 -State Listen -ErrorAction SilentlyContinue))"
  $dsk = Join-Path $appdir 'desktop-win32-golden.exe'
  $dstr = '--cfg "{0}" --out "{1}" --nowait -- "{2}" -port=6600 -nodeid=1 -netnum=1' -f `
      "$dir\hog.cfg", "$dir\win_hog_desktop.log", $dsk
  Start-Process -FilePath "$dir\apitrace.exe" -ArgumentList $dstr -WorkingDirectory $appdir | Out-Null
  Start-Sleep -Seconds 25
  Get-Process *win32-golden* -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
}

# ---- pull every log back ------------------------------------------------------
foreach ($f in Get-ChildItem "$dir\win_hog*.log" -ErrorAction SilentlyContinue) {
  "LOG $($f.Name) size=$($f.Length)"
  curl.exe -s -T $f.FullName "$base/$($f.Name)"; "PULLED $($f.Name)"
}
"FREE_AFTER_GB=$([math]::Round((Get-PSDrive C).Free/1GB,3))"
Stop-Transcript | Out-Null
curl.exe -s -T $status "$base/win_hog_status.txt"
"DONE"
