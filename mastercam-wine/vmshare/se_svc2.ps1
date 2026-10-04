$ErrorActionPreference = 'Continue'
$out = 'C:\seref'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$U = 'http://192.168.122.1:8000/'
$seen = ''
Write-Host "SERVICE2-UP pid=$PID"
while ($true) {
  $raw = (curl.exe -s --max-time 15 ($U + 'cmd.txt')) -join "`n"
  $raw = $raw.Trim()
  if ($raw -and $raw -ne $seen) {
    $seen = $raw
    [System.IO.File]::WriteAllText("$out\cmd_in.txt", $raw)
    # Fire the command in a SEPARATE process so this poller can never wedge on a slow command.
    Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','C:\seref\runner.ps1'
  }
  Start-Sleep -Seconds 3
}
