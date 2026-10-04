$log = "$env:TEMP\installer_downloader.log"
$note = "C:\Users\adsf\urlhunt_note.txt"
Remove-Item $note -Force -ErrorAction SilentlyContinue
Remove-Item $log -Force -ErrorAction SilentlyContinue
"start=$(Get-Date -Format o)" | Set-Content $note
Get-DnsClientCache -ErrorAction SilentlyContinue | Out-Null
$seen = @{}
$events = @()
Start-Process "C:\Users\adsf\capcut_setup.exe"
$killed = $false
for ($i = 0; $i -lt 90; $i++) {
  Start-Sleep -Seconds 2
  try {
    Get-DnsClientCache -ErrorAction SilentlyContinue | ForEach-Object {
      if ($_.Entry) {
        $k = $_.Entry + "|" + $_.Type
        if (-not $seen.ContainsKey($k)) { $seen[$k] = $_.Data; $events += ("t=" + $i*2 + "s " + $_.Entry + " -> " + $_.Data) }
        else { $seen[$k] = $_.Data }
      }
    }
  } catch {}
  $t = ""
  if (Test-Path $log) { $t = (Get-Content $log -Raw -ErrorAction SilentlyContinue) }
  if ($t -match "Downloader download finish") {
    Add-Content $note ("download finished at t=" + $i*2 + "s")
    if (-not $killed) { Get-Process capcut_setup -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue; $killed = $true }
    Start-Sleep -Seconds 4
    break
  }
  if ($t -match "same version|no need|Downloader install finish") {
    Add-Content $note ("skip/done at t=" + $i*2 + "s")
    break
  }
}
if (-not $killed) { Get-Process capcut_setup -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
Add-Content $note "=== DNS entries (new during run) ==="
$events | ForEach-Object { Add-Content $note $_ }
Add-Content $note "=== installer log ==="
if (Test-Path $log) { Get-Content $log | Add-Content $note }
Add-Content $note "=== app_shell_cache ==="
Get-ChildItem "C:\Users\adsf\AppData\Local" -Directory -Filter "app_shell_cache_*" -ErrorAction SilentlyContinue | ForEach-Object {
  Add-Content $note ("DIR " + $_.FullName)
  Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { Add-Content $note ("  " + $_.Length + " " + $_.FullName) }
}
Add-Content $note "DONE"
& curl.exe -s -T $note http://192.168.122.1:8000/urlhunt_note.txt
Get-Content $note -Raw
