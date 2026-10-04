# Capture what Tableau Desktop actually asks Windows for during startup.
# ProcMon (already on this guest at C:\acadbox\Procmon.exe) logs file/registry/pipe/process/network activity -
# which includes the FlexNet service IPC (named pipes) and every install-state key the app reads.
# Runs ON the guest; PUTs a compressed CSV back to the :8000 hub.
$ErrorActionPreference = 'Continue'
$hub = 'http://192.168.122.1:8000/'
$pm = 'C:\acadbox\Procmon.exe'
$pml = 'C:\Users\adsf\tab.pml'
$csv = 'C:\Users\adsf\tab.csv'
$zip = 'C:\Users\adsf\tabtrace.zip'

Get-Process tableau -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Remove-Item $pml, $csv, $zip -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# start capture (elevated context is silent on this guest: ConsentPromptBehaviorAdmin=0)
$mon = Start-Process -FilePath $pm -ArgumentList '/AcceptEula', '/Quiet', '/Minimized', '/BackingFile', $pml -PassThru
Start-Sleep -Seconds 6
Write-Output ('procmon_pid=' + $mon.Id)

$app = Start-Process -FilePath 'C:\Program Files\Tableau\Tableau 2026.2\bin\tableau.exe' -PassThru
Write-Output ('tableau_pid=' + $app.Id)
Start-Sleep -Seconds 50
Write-Output ('tableau_alive=' + (-not $app.HasExited))

Start-Process -FilePath $pm -ArgumentList '/Terminate' -Wait
Start-Sleep -Seconds 3
if (Test-Path $pml) { Write-Output ('pml_bytes=' + (Get-Item $pml).Length) } else { Write-Output 'pml_missing=1' }

Start-Process -FilePath $pm -ArgumentList '/OpenLog', $pml, '/SaveAs', $csv -Wait
Start-Sleep -Seconds 2
if (Test-Path $csv) {
    Write-Output ('csv_bytes=' + (Get-Item $csv).Length)
    Compress-Archive -Path $csv -DestinationPath $zip -Force
    Write-Output ('zip_bytes=' + (Get-Item $zip).Length)
    curl.exe -s -T $zip ($hub + 'tabtrace.zip') | Out-Null
    Write-Output 'uploaded=1'
} else {
    Write-Output 'csv_missing=1'
}
Get-Process tableau -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
