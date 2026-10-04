# Guest-side log collector for the Tableau-on-Wine project.
# Runs ON the Windows guest (fetched from the :8000 hub). Zips Tableau's own log directories and
# PUTs the archive back to the hub, then prints what it found.
# Robust by design: no nested quoting, all paths from environment/Join-Path.
$ErrorActionPreference = 'Continue'
$hub = 'http://192.168.122.1:8000/'
$zip = Join-Path $env:USERPROFILE 'tablogs.zip'
$src = @()
foreach ($p in @((Join-Path $env:LOCALAPPDATA 'Tableau'), (Join-Path $env:APPDATA 'Tableau'))) {
    if (Test-Path $p) { $src += $p }
}
if ($src.Count -gt 0) {
    Remove-Item $zip -ErrorAction SilentlyContinue
    Compress-Archive -Path $src -DestinationPath $zip -Force
    if (Test-Path $zip) {
        Write-Output ('zip_bytes=' + (Get-Item $zip).Length)
        curl.exe -s -T $zip ($hub + 'tablogs.zip') | Out-Null
        Write-Output 'uploaded=1'
    }
} else {
    Write-Output 'no_tableau_log_dirs=1'
}
# anything the app drops in TEMP is also evidence
foreach ($f in @(Get-ChildItem $env:TEMP -Filter 'tab*' -ErrorAction SilentlyContinue)) {
    Write-Output ('temp=' + $f.Name + ':' + $f.Length)
}
# and the last application-event entries about tableau, which explain an early exit
$ev = Get-WinEvent -LogName Application -MaxEvents 200 -ErrorAction SilentlyContinue |
      Where-Object { $_.Message -match 'tableau' } | Select-Object -First 8
if ($ev) {
    Write-Output '--- events ---'
    foreach ($e in $ev) {
        Write-Output (($e.TimeCreated.ToString('s')) + ' [' + $e.LevelDisplayName + '] ' + $e.ProviderName + ': ' + ($e.Message -replace "`r?`n", ' | ').Substring(0, [Math]::Min(300, $e.Message.Length)))
    }
} else {
    Write-Output 'events=none'
}
