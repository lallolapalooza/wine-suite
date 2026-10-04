# vm_elev.ps1 - fetch vm_mc_boot.ps1 and run it ELEVATED in the interactive session without a UAC
# prompt, by registering a scheduled task with RunLevel=Highest (legal for an Administrators member;
# the task then runs with the full token because the user is logged on interactively).
$ErrorActionPreference = 'Continue'
$U    = 'http://192.168.122.1:8000/'
$Boot = 'C:\Users\adsf\vm_mc_boot.ps1'
curl.exe -s -o $Boot ($U + 'vm_mc_boot.ps1')
"boot_script_bytes=" + (Get-Item $Boot).Length

$A = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $Boot + '"')
$P = New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\$env:USERNAME" -LogonType Interactive -RunLevel Highest
$S = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::FromHours(6)) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName 'McElevBoot' -Action $A -Principal $P -Settings $S -Force | Out-Null
"registered=" + (Get-ScheduledTask 'McElevBoot').TaskName
Start-ScheduledTask -TaskName 'McElevBoot'
Start-Sleep -Seconds 4
"task_state=" + (Get-ScheduledTask 'McElevBoot').State
"--- boot log so far ---"
Get-Content 'C:\vm_mc_boot.log' -ErrorAction SilentlyContinue | Select-Object -First 20
"elev_launcher_done"
