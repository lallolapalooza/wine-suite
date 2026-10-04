# vm_admin2.ps1 - hardened elevated companion loop for the guest command channel.
# Same protocol as vm_admin.ps1 (poll <share>/cmd_admin.txt -> PUT <share>/admin_out.txt) but all
# internal variables are uniquely named so an injected command can never clobber them.
# Also kills the old wedged vm_admin.ps1 console window on startup.
$ErrorActionPreference = 'Continue'
$ADM_U  = 'http://192.168.122.1:8000/'
$ADM_OP = 'C:\seref\admin_out.txt'
$ADM_IP = 'C:\seref\admin_in.txt'
New-Item -ItemType Directory -Force -Path 'C:\seref' | Out-Null

# clean up the old broken loop (elevated, so we can)
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'vm_admin\.ps1' } | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch {} }

"ADMIN2-UP pid=$PID elevated=" + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) | Out-File "$ADM_OP" -Encoding utf8
& curl.exe -s -T "$ADM_OP" ($ADM_U + 'admin_out.txt') | Out-Null
$ADM_SEEN = ''
while ($true) {
  $ADM_RAW = (& curl.exe -s --max-time 15 ($ADM_U + 'cmd_admin.txt')) -join "`n"
  $ADM_RAW = $ADM_RAW.Trim()
  if ($ADM_RAW -and $ADM_RAW -ne $ADM_SEEN) {
    $ADM_SEEN = $ADM_RAW
    [System.IO.File]::WriteAllText($ADM_IP, $ADM_RAW)
    $ADM_RES = @()
    $ADM_RES += "cmd=" + $ADM_RAW
    $ADM_RES += "start=" + (Get-Date -Format o)
    try { $ADM_OUTPUT = Invoke-Expression $ADM_RAW 2>&1 | Out-String; $ADM_RES += "rc=0" } catch { $ADM_OUTPUT = ($_ | Out-String); $ADM_RES += "rc=1" }
    $ADM_RES += "end=" + (Get-Date -Format o)
    $ADM_RES += "--- output ---"
    $ADM_RES += $ADM_OUTPUT
    ($ADM_RES -join "`n") | Out-File "$ADM_OP" -Encoding utf8
    & curl.exe -s -T "$ADM_OP" ($ADM_U + 'admin_out.txt') | Out-Null
  }
  Start-Sleep -Seconds 2
}
