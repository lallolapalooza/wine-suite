$ErrorActionPreference = 'Continue'
$HF = New-Object System.Collections.Generic.List[string]
$HFs = "$env:APPDATA\ETC\Persistent\client_settings.json"
Get-Process launcher-win32-golden,server-win32-golden,desktop-win32-golden,monitor-win32-golden,dialogue-win32-golden,critical-win32-golden,vob-win32-golden -ErrorAction SilentlyContinue | ForEach-Object { $HF.Add("KILL $($_.ProcessName) $($_.Id)"); Stop-Process -Id $_.Id -Force }
Start-Sleep -Seconds 3
if (Test-Path $HFs) {
  $HF.Add("before: " + (Get-Content $HFs -Raw))
  $HFt = (Get-Content $HFs -Raw) -replace '"startProcessor":true','"startProcessor":false' -replace '"startServer":true','"startServer":false' -replace '"startOb":true','"startOb":false'
  Set-Content -Path $HFs -Value $HFt -Encoding ASCII -NoNewline
  $HF.Add("after:  " + (Get-Content $HFs -Raw))
}
$HFroot = 'C:\Program Files (x86)\ETC\HogPC'
$HFp = Start-Process -FilePath (Join-Path $HFroot 'launcher-win32-golden.exe') -WorkingDirectory $HFroot -PassThru
$HF.Add("STARTED launcher pid=$($HFp.Id)")
Start-Sleep -Seconds 16
Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'golden' } | ForEach-Object { $HF.Add(("PROC {0} pid={1} title='{2}'" -f $_.ProcessName, $_.Id, $_.MainWindowTitle)) }
$HF | Set-Content -Encoding UTF8 'C:\hog\hog_fresh.txt'
$HF | ForEach-Object { $_ }
& curl.exe -s -T 'C:\hog\hog_fresh.txt' 'http://192.168.122.1:8000/vm_hog_fresh.txt' | Out-Null
