# Windows reference for show creation: kill the running tree and start the server
# directly under the tracer against the existing show, so the show-open lock burst is
# captured (the attach in guest_attach_hog.ps1 only sees steady state).
#   tools/vm/elev.sh tools/vm/guest_server_hog.ps1
$ErrorActionPreference = 'Continue'
$dir  = 'C:\hog\apitrace32'
$base = 'http://192.168.122.1:8000'
$status = "$dir\win_hog_server_start_status.txt"
Start-Transcript -Path $status -Force | Out-Null
"ELEVATED=$([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)"
Get-Process *win32-golden* -ErrorAction SilentlyContinue | ForEach-Object { "KILL $($_.ProcessName) $($_.Id)"; Stop-Process -Id $_.Id -Force }
Start-Sleep -Seconds 3
$shows = Join-Path $env:USERPROFILE 'Documents\ETC\HogPC\Shows'
$show = Get-ChildItem $shows -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
"SHOW=$($show.Name)"
$appdir = 'C:\Program Files (x86)\ETC\HogPC'
$srv = Join-Path $appdir 'server-win32-golden.exe'
Remove-Item "$dir\win_hog_server_start.log" -ErrorAction SilentlyContinue
$sstr = '--cfg "{0}" --out "{1}" --nowait -- "{2}" -port=6600 -netnum=1 "-showpath={3}" "-showname={4}"' -f `
    "$dir\hog.cfg", "$dir\win_hog_server_start.log", $srv, ($shows -replace '\\','/'), $show.Name
Start-Process -FilePath "$dir\apitrace.exe" -ArgumentList $sstr -WorkingDirectory $appdir | Out-Null
Start-Sleep -Seconds 22
Get-Process *win32-golden* -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
$f = "$dir\win_hog_server_start.log"
if (Test-Path $f) { "LOG size=$((Get-Item $f).Length)"; curl.exe -s -T $f "$base/win_hog_server_start.log"; "PULLED" }
Stop-Transcript | Out-Null
curl.exe -s -T $status "$base/win_hog_server_start_status.txt"
"DONE"
