$ErrorActionPreference = "Continue"
# instance guard: if another copy of agent3 is already running, exit
$me = $PID
$others = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -match 'agent3\.ps1' -and $_.ProcessId -ne $me }
if ($others) { exit }
# also clean up older agent2 instances (there are duplicates)
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -match 'agent2\.ps1' } |
  ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }

$last = ""
while ($true) {
  try {
    $u = "http://192.168.122.1:8000/cmd3.txt?t=" + [DateTime]::UtcNow.Ticks + "-" + (Get-Random)
    $raw = (Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 8 -Headers @{ "Cache-Control" = "no-cache"; "Pragma" = "no-cache" }).Content
  } catch { Start-Sleep -Seconds 3; continue }
  if ($null -eq $raw) { Start-Sleep -Seconds 3; continue }
  $raw = [string]$raw
  $raw = $raw.TrimStart([char]0xFEFF).Trim()
  if ($raw.Length -gt 0 -and $raw -ne $last) {
    $last = $raw
    $start = (Get-Date).ToString("o")
    $o = ""
    try { $o = Invoke-Expression $raw 2>&1 | Out-String } catch { $o = "EXC: " + $_.Exception.Message }
    $rc = $LASTEXITCODE
    $end = (Get-Date).ToString("o")
    $body = "cmd=$raw`nstart=$start`nrc=$rc`nend=$end`n--- output ---`n$o"
    $tmp = "C:\Users\adsf\guest_cmd_out3.txt"
    [IO.File]::WriteAllText($tmp, $body, (New-Object Text.UTF8Encoding($true)))
    try { & curl.exe -s -T $tmp http://192.168.122.1:8000/guest_cmd_out3.txt | Out-Null } catch {}
  }
  Start-Sleep -Seconds 3
}
