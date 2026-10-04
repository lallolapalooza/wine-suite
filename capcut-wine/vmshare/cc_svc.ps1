# Dedicated single-purpose command poller for the capcut-wine project.
# Uses its OWN filename pair, so it cannot race with the older pollers in this guest that share
# guest_cmd_out.txt (which is why that file kept arriving 0 bytes).
#
# host -> guest : cc_cmd.txt      (plain text, the command to run)
# guest -> host : cc_out.txt      (the result, PUT back to the host)
#
# started from the guest side; see recon/GUEST_CHANNEL.md for how.
$ErrorActionPreference = 'Continue'
$out = 'C:\ccwork'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$U = 'http://192.168.122.1:8000/'
$seen = ''
Write-Host "CC-SERVICE-UP pid=$PID"
while ($true) {
  $raw = (curl.exe -s --max-time 15 ($U + 'cc_cmd.txt')) -join "`n"
  $raw = $raw.Trim()
  if ($raw -and $raw -ne $seen) {
    $seen = $raw
    $res = @()
    $res += "cmd=" + $raw
    $res += "start=" + (Get-Date -Format o)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try { $o = Invoke-Expression $raw 2>&1 | Out-String; $res += "rc=0" }
    catch { $o = ($_ | Out-String); $res += "rc=1" }
    $sw.Stop()
    $res += "ms=" + $sw.ElapsedMilliseconds
    $res += "end=" + (Get-Date -Format o)
    $res += "--- output ---"
    $res += $o
    $res -join "`n" | Out-File "$out\cc_out.txt" -Encoding utf8
    curl.exe -s -T "$out\cc_out.txt" ($U + 'cc_out.txt') | Out-Null
  }
  Start-Sleep -Seconds 3
}
