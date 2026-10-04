# vm_admin.ps1 - elevated companion to the guest command channel.
# Runs ONCE elevated (via vm_launch_admin.ps1 + UAC Alt+Y) and then executes every command that
# appears in <share>/cmd_admin.txt, PUTting the result to <share>/admin_out.txt.  Needed because the
# normal poller runs UAC-filtered and cannot inspect/drive the elevated installer windows.
$ErrorActionPreference = 'Continue'
$U    = 'http://192.168.122.1:8000/'
$out  = 'C:\seref\admin_out.txt'
$in   = 'C:\seref\admin_in.txt'
New-Item -ItemType Directory -Force -Path 'C:\seref' | Out-Null
$seen = ''
"ADMIN-UP pid=$PID elevated=" + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) | Out-File "$out" -Encoding utf8
curl.exe -s -T "$out" ($U + 'admin_out.txt') | Out-Null
while ($true) {
  $raw = (curl.exe -s --max-time 15 ($U + 'cmd_admin.txt')) -join "`n"
  $raw = $raw.Trim()
  if ($raw -and $raw -ne $seen) {
    $seen = $raw
    [System.IO.File]::WriteAllText($in, $raw)
    $res = @()
    $res += "cmd=" + $raw
    try { $o = Invoke-Expression $raw 2>&1 | Out-String; $res += "rc=0" } catch { $o = ($_ | Out-String); $res += "rc=1" }
    $res += "--- output ---"
    $res += $o
    ($res -join "`n") | Out-File "$out" -Encoding utf8
    curl.exe -s -T "$out" ($U + 'admin_out.txt') | Out-Null
  }
  Start-Sleep -Seconds 2
}
