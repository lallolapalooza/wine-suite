$ErrorActionPreference='Continue'
powercfg.exe /change monitor-timeout-ac 0
powercfg.exe /change monitor-timeout-dc 0
powercfg.exe /change standby-timeout-ac 0
powercfg.exe /change standby-timeout-dc 0
powercfg.exe /change disk-timeout-ac 0
powercfg.exe /change hibernate-timeout-ac 0
powercfg.exe /change monitor-timeout-ac 0
"monitor timeout set"
Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name ScreenSaveActive -ErrorAction SilentlyContinue | ForEach-Object { 'ScreenSaveActive=' + $_.ScreenSaveActive }
Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name ScreenSaveActive -Value '0' -ErrorAction SilentlyContinue
Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name ScreenSaveTimeOut -Value '0' -ErrorAction SilentlyContinue
# keep the console awake and unlocked-looking
"done"
