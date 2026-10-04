$ErrorActionPreference = 'Continue'
Get-Process launcher-win32-golden,server-win32-golden,desktop-win32-golden,monitor-win32-golden,dialogue-win32-golden,critical-win32-golden -ErrorAction SilentlyContinue | ForEach-Object { "KILL $($_.ProcessName) $($_.Id)"; Stop-Process -Id $_.Id -Force }
Start-Sleep -Seconds 3
$HGSroot = 'C:\Program Files (x86)\ETC\HogPC'
$HGS = Start-Process -FilePath (Join-Path $HGSroot 'launcher-win32-golden.exe') -WorkingDirectory $HGSroot -PassThru
"STARTED pid=$($HGS.Id)"
Start-Sleep -Seconds 16
Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'golden' } | ForEach-Object {
  "P {0} pid={1} title=[{2}] hwnd=0x{3:X} ws={4}MB" -f $_.ProcessName, $_.Id, $_.MainWindowTitle, $_.MainWindowHandle.ToInt64(), [math]::Round($_.WorkingSet64/1MB)
}
"done"
