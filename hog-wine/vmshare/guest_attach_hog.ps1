# Non-destructive Windows reference for the running Hog server/desktop: attach the
# 32-bit tracer to the live processes (no kill), collect ~25 s, PUT the logs back.
# Must run elevated (the processes are elevated, so OpenProcess needs an admin token):
#   tools/vm/elev.sh tools/vm/guest_attach_hog.ps1
$ErrorActionPreference = 'Continue'
$dir  = 'C:\hog\apitrace32'
$base = 'http://192.168.122.1:8000'
$status = "$dir\win_hog_attach_status.txt"
Start-Transcript -Path $status -Force | Out-Null
"ELEVATED=$([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)"
Remove-Item "$dir\win_hog_server.log","$dir\win_hog_desktop.log","$dir\win_hog_critical.log" -ErrorAction SilentlyContinue
foreach ($role in @('server','desktop','critical')) {
  $pr = Get-Process "$role-win32-golden" -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $pr) { "NO $role"; continue }
  $astr = '--pid {0} --cfg "{1}" --out "{2}"' -f $pr.Id, "$dir\hog.cfg", "$dir\win_hog_$role.log"
  Start-Process -FilePath "$dir\apitrace.exe" -ArgumentList $astr | Out-Null
  "ATTACHED $role pid=$($pr.Id)"
}
Start-Sleep -Seconds 25
foreach ($r in @('server','desktop','critical')) {
  $f = "$dir\win_hog_$r.log"
  if (Test-Path $f) { "LOG $r size=$((Get-Item $f).Length)"; curl.exe -s -T $f "$base/win_hog_$r.log"; "PULLED $r" }
}
Stop-Transcript | Out-Null
curl.exe -s -T $status "$base/win_hog_attach_status.txt"
"DONE"
