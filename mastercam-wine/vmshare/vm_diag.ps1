$ErrorActionPreference='Continue'
"admin=" + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
"user=$env:USERNAME computer=$env:COMPUTERNAME"
"cmd Register-ScheduledTask -> " + [bool](Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)
"--- boot log ---"
if (Test-Path C:\vm_mc_boot.log) { Get-Content C:\vm_mc_boot.log -Tail 30 } else { 'no boot log' }
"--- schtasks query ---"
schtasks.exe /query /tn McElevBoot /v /fo LIST 2>&1 | Select-Object -First 25
"--- processes ---"
Get-Process | Where-Object { $_.ProcessName -match 'setup|msiexec|powershell|Mastercam' } | ForEach-Object { "{0} {1} {2}" -f $_.Id, $_.ProcessName, $_.MainWindowTitle }
"--- window titles ---"
Get-Process | Where-Object { $_.MainWindowTitle } | ForEach-Object { $_.ProcessName + ' | ' + $_.MainWindowTitle }
"--- last task run info ---"
try { Get-ScheduledTaskInfo -TaskName McElevBoot -ErrorAction Stop | Format-List * | Out-String } catch { "Get-ScheduledTaskInfo failed: " + $_.Exception.Message }
"done"
