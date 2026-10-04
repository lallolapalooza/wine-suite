$ErrorActionPreference = 'Continue'
$out = 'C:\pbiref'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$U = 'http://192.168.122.1:8000/'
$tl = "$out\install2_timeline.txt"
if (Test-Path $tl) { Remove-Item $tl -Force }
if (Test-Path "$out\progress.txt") { Remove-Item "$out\progress.txt" -Force }
function W($m) { $m | Out-File $tl -Append -Encoding utf8; Write-Host $m }

$exe = 'C:\Users\adsf\Downloads\PBIDesktopSetup_x64.exe'
$log = "$out\pbi_burn2.log"
if (Test-Path $log) { Remove-Item $log -Force }

W ("host=" + (hostname))
W ("guest_user=" + $env:USERNAME)
W ("installer=" + $exe)
W ("installer_bytes=" + (Get-Item $exe).Length)
W "installer_md5_skipped=1"
W ("uac_enablelua=" + (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System').EnableLUA)
W ("uac_consent_behavior_admin=" + (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System').ConsentPromptBehaviorAdmin)
W ("cmdline=" + $exe + ' -quiet -norestart -log ' + $log)
W ("launch_method=Start-Process -Verb RunAs (interactive UAC consent)")
W ("launch_request=" + (Get-Date -Format o))

$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
  Start-Process -FilePath $exe -ArgumentList '-quiet', '-norestart', 'ACCEPT_EULA=1', '-log', $log -Verb RunAs -ErrorAction Stop
  W "start_process=ok"
} catch {
  W ("start_process_error=" + $_.Exception.Message)
  curl.exe -s -T $tl ($U + 'guest_install2_timeline.txt') | Out-Null
  Write-Host "INSTALL-ABORT"
  exit 1
}

# wait for the elevated burn bundle to create its log (UAC must be approved meanwhile)
$t0 = Get-Date
while (-not (Test-Path $log) -and ((Get-Date) - $t0).TotalSeconds -lt 300) { Start-Sleep -Seconds 5 }
W ("burn_log_seen=" + (Test-Path $log) + " at=" + (Get-Date -Format o))
W ("launch_to_log_seconds=" + [math]::Round(((Get-Date) - $t0).TotalSeconds, 1))

$deadline = (Get-Date).AddMinutes(60)
$reason = 'timeout'
$last = Get-Date
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 15
  if ((Test-Path $log) -and ((Get-Content $log -Tail 30 -ErrorAction SilentlyContinue) -match 'Exit code')) { $reason = 'burn-log-exit-code'; break }
  $p = Get-Process -Name 'PBIDesktopSetup_x64' -ErrorAction SilentlyContinue
  if (-not $p -and $sw.Elapsed.TotalSeconds -gt 240) { $reason = 'burn-process-gone'; break }
  if (((Get-Date) - $last).TotalSeconds -ge 60) {
    $last = Get-Date
    $msi = (Get-Process -Name msiexec -ErrorAction SilentlyContinue).Count
    $sz = 0; if (Test-Path $log) { $sz = (Get-Item $log).Length }
    $snap = "elapsed=" + [math]::Round($sw.Elapsed.TotalSeconds, 1) + " burn_alive=" + [bool]$p + " msiexec_count=" + $msi + " log_bytes=" + $sz + " t=" + (Get-Date -Format o)
    W $snap
    $snap | Out-File "$out\progress.txt" -Append -Encoding utf8
    curl.exe -s -T "$out\progress.txt" ($U + 'guest_install2_progress.txt') | Out-Null
  }
}
$sw.Stop()
W ("wait_reason=" + $reason)
W ("install_seconds=" + [math]::Round($sw.Elapsed.TotalSeconds, 1))
W ("install_end=" + (Get-Date -Format o))

if (Test-Path $log) {
  W "== burn log exit lines =="
  W (((Select-String -Path $log -Pattern 'Exit code|restarting' -ErrorAction SilentlyContinue).Line) -join "`n")
  W ("burn_log_bytes=" + (Get-Item $log).Length)
  Get-Content $log -Tail 400 | Out-File "$out\burn2_tail.txt" -Encoding utf8
  (Select-String -Path $log -Pattern 'Exit code|Error 0x|Failed|Applying|Caching|Detect complete|Installation|elevat|Launch|ACCEPT_EULA' -ErrorAction SilentlyContinue).Line | Out-File "$out\burn2_filtered.txt" -Encoding utf8
} else { W 'no burn log' }
W ("pbi_dir=" + (Test-Path 'C:\Program Files\Microsoft Power BI Desktop'))
W ("pbid_exe=" + (Test-Path 'C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe'))

curl.exe -s -T $tl ($U + 'guest_install2_timeline.txt') | Out-Null
foreach ($n in 'burn2_tail.txt', 'burn2_filtered.txt', 'progress.txt') {
  if (Test-Path "$out\$n") { curl.exe -s -T "$out\$n" ($U + 'guest_' + $n) | Out-Null }
}
Write-Host "INSTALL-DONE"
