$base = "C:\Users\adsf\AppData\Local\CapCut"
Write-Output "=== 1. ve_detector matches ==="
Get-ChildItem "$base\Apps" -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*ve_detector*" -or $_.FullName -like "*ve_detector*" } | Select-Object -First 20 FullName,Length | Format-Table -AutoSize | Out-String -Width 250
Write-Output "=== 2. VEAngle listing ==="
Get-ChildItem "$base\Apps\9.5.0.4050\VEAngle" -Force -ErrorAction SilentlyContinue | Select-Object Name,Length | Format-Table -AutoSize | Out-String -Width 200
Write-Output "=== 2c. all libEGL/libGLESv2 in install ==="
Get-ChildItem "$base\Apps" -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^lib(EGL|GLESv2)" } | Select-Object FullName,Length | Format-Table -AutoSize | Out-String -Width 250
Write-Output "=== 3. VeDetector log EGL/GLES/AGFX/GPDevice/ve_detector ==="
Get-ChildItem "$base\User Data\Log" -Filter "VeDetector_*.log" -ErrorAction SilentlyContinue | ForEach-Object { Get-Content $_.FullName | Select-String -Pattern "EGL|GLES|AGFX|GPDevice|ve_detector" | Select-Object -Last 40 }
Write-Output "=== 4. CapCut procs ==="
Get-Process | Where-Object { $_.Name -match "CapCut|VEDetector|VECreator|videoeditor|ttdaemon|taskcontainer|CefCreator" } | Select-Object Name,Id,MainWindowTitle,StartTime | Format-List
Write-Output "=== 6. main window title ==="
Get-Process CapCut -ErrorAction SilentlyContinue | Select-Object Id,MainWindowTitle,Responding | Format-List
Write-Output "DONE"
