# Elevated guest-side script: stage the IAT tracer and trace Eos.exe start-up on Windows.
# Run through tools/vm/vmcmda.sh -f tools/vm/guest_apitrace_eos.ps1 <timeout>
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Continue'
$base = 'http://192.168.122.1:8000'
$dir  = 'C:\apitrace'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
"FREE_BEFORE_GB=$([math]::Round((Get-PSDrive C).Free/1GB,3))"

foreach ($f in 'apihook.dll','apitrace.exe','eos.cfg') {
  curl.exe -s -o (Join-Path $dir $f) "$base/$f"
  "GOT $f $((Get-Item (Join-Path $dir $f)).Length)"
}
Get-FileHash "$dir\apihook.dll","$dir\apitrace.exe" -Algorithm MD5 | ForEach-Object { "MD5 $($_.Hash) $($_.Path)" }

$exe = 'C:\Program Files\ETC\EosFamily\v3\Eos\Eos.exe'
"EXE_OK=$(Test-Path $exe)"
# make sure no other Eos instance (single-instance exits in ~3 s)
Get-Process Eos -ErrorAction SilentlyContinue | ForEach-Object { "KILLING $($_.Id)"; Stop-Process -Id $_.Id -Force }
Get-Process ETC_LaunchOffline,ETC_Launch -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Seconds 2

$log = "$dir\win_eos.log"
Remove-Item $log -ErrorAction SilentlyContinue
$t0 = Get-Date
# -Wait so the 150 s trace completes before we pull the log back
$p = Start-Process -FilePath "$dir\apitrace.exe" `
  -ArgumentList '--cfg',"$dir\eos.cfg",'--out',$log,'--timeout','60','--',$exe `
  -WorkingDirectory 'C:\Program Files\ETC\EosFamily\v3\Eos' -Wait -PassThru
"TRACER_RC=$($p.ExitCode) elapsed_s=$([math]::Round(((Get-Date)-$t0).TotalSeconds,1))"
"LOG_EXISTS=$(Test-Path $log) size=$((Get-Item $log -ErrorAction SilentlyContinue).Length)"
if (Test-Path $log) { curl.exe -s -T $log "$base/win_eos.log"; "PULLED" }
# also grab the app's own logs from this run
foreach ($f in 'OnyxConsole.log','NetworkFeedback.log','EosAsserts.txt') {
  $src = "C:\Users\adsf\AppData\Local\ETC\EosFamily\v3\$f"
  if (Test-Path $src) { curl.exe -s -T $src "$base/win_$f"; "PULLED $f" }
}
"FREE_AFTER_GB=$([math]::Round((Get-PSDrive C).Free/1GB,3))"
