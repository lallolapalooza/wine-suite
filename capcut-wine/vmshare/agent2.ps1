$ErrorActionPreference = "Continue"
$last = ""
while ($true) {
  try {
    $raw = (Invoke-WebRequest -Uri "http://192.168.122.1:8000/cmd2.txt" -UseBasicParsing -TimeoutSec 8).Content
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
    $tmp = "C:\Users\adsf\guest_cmd_out2.txt"
    [IO.File]::WriteAllText($tmp, $body, (New-Object Text.UTF8Encoding($true)))
    try { & curl.exe -s -T $tmp http://192.168.122.1:8000/guest_cmd_out2.txt | Out-Null } catch {}
  }
  Start-Sleep -Seconds 3
}
