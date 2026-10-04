$ErrorActionPreference = 'Continue'
$out = 'C:\seref'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$U = 'http://192.168.122.1:8000/'
$seen = ''
Write-Host "SERVICE-UP pid=$PID"
while ($true) {
  $raw = (curl.exe -s --max-time 15 ($U + 'cmd.txt')) -join "`n"
  $raw = $raw.Trim()
  if ($raw -and $raw -ne $seen) {
    $seen = $raw
    $res = @()
    $res += "cmd=" + $raw
    $res += "start=" + (Get-Date -Format o)
    try {
      $o = Invoke-Expression $raw 2>&1 | Out-String
      $res += "rc=0"
    } catch {
      $o = ($_ | Out-String)
      $res += "rc=1"
    }
    $res += "end=" + (Get-Date -Format o)
    $res += "--- output ---"
    $res += $o
    $res -join "`n" | Out-File "$out\cmd_out.txt" -Encoding utf8
    curl.exe -s -T "$out\cmd_out.txt" ($U + 'guest_cmd_out.txt') | Out-Null
  }
  Start-Sleep -Seconds 3
}
