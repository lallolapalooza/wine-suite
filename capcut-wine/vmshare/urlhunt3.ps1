$ErrorActionPreference = "Continue"
$note = "C:\Users\adsf\urlhunt_note3.txt"
$dmp  = "C:\Users\adsf\ccsetup.dmp"
Remove-Item $note,$dmp -Force -ErrorAction SilentlyContinue
Add-Type -Namespace MD -Name Api -MemberDefinition @'
[DllImport("dbghelp.dll", SetLastError=true)] public static extern bool MiniDumpWriteDump(IntPtr hProcess, uint ProcessId, IntPtr hFile, uint DumpType, IntPtr ExceptionParam, IntPtr UserStreamParam, IntPtr CallbackParam);
[DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
[DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
'@
Get-Process capcut_setup -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Get-ChildItem "C:\Users\adsf\AppData\Local" -Directory -Filter "app_shell_cache_*" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\installer_downloader.log" -Force -ErrorAction SilentlyContinue
"start=$(Get-Date -Format o)" | Set-Content $note

Start-Process "C:\Users\adsf\capcut_setup.exe"
$dumped = $false
$seen = @{}
$dns = @{}
for ($i=0; $i -lt 200; $i++) {
  Start-Sleep -Seconds 2
  try { Get-DnsClientCache -ErrorAction SilentlyContinue | ForEach-Object { if ($_.Entry -match "capcut|bytedance|ibytedtos|capcutstatic|beecdn|zijie|byteoversea") { $dns[$_.Entry] = $_.Data } } } catch {}
  $f = Get-ChildItem "C:\Users\adsf\AppData\Local" -Directory -Filter "app_shell_cache_*" -ErrorAction SilentlyContinue |
       ForEach-Object { Get-ChildItem $_.FullName -File -ErrorAction SilentlyContinue } | Select-Object -First 1
  if ($f) { if (-not $seen.ContainsKey($f.Name)) { Add-Content $note ("t=" + $i*2 + "s payload " + $f.Name + " size=" + $f.Length) }; $seen[$f.Name] = $f.Length }
  if (-not $dumped -and $f -and $f.Length -gt 1MB) {
    $cp = Get-Process capcut_setup -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cp) {
      Add-Content $note ("dumping pid " + $cp.Id + " at t=" + $i*2 + "s (payload size " + $f.Length + ")")
      $h = [MD.Api]::OpenProcess(0x0410, $false, [uint32]$cp.Id)
      $fs = [IO.File]::Create($dmp)
      $ok = [MD.Api]::MiniDumpWriteDump($h, [uint32]$cp.Id, $fs.SafeFileHandle.DangerousGetHandle(), 2, [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero)
      $fs.Close(); [void][MD.Api]::CloseHandle($h)
      Add-Content $note ("dump ok=" + $ok + " size=" + (Get-Item $dmp -ErrorAction SilentlyContinue).Length)
      $dumped = $true
    }
  }
  $t = ""
  if (Test-Path "$env:TEMP\installer_downloader.log") { $t = Get-Content "$env:TEMP\installer_downloader.log" -Raw -ErrorAction SilentlyContinue }
  if ($t -match "Downloader download finish") { Add-Content $note ("download finish at t=" + $i*2 + "s"); break }
}
Get-Process capcut_setup -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Add-Content $note "=== DNS ==="
$dns.GetEnumerator() | ForEach-Object { Add-Content $note ($_.Key + " -> " + $_.Value) }
Add-Content $note "=== installer log ==="
if (Test-Path "$env:TEMP\installer_downloader.log") { Get-Content "$env:TEMP\installer_downloader.log" | Add-Content $note }
Add-Content $note "DONE"
& curl.exe -s -T $note http://192.168.122.1:8000/urlhunt_note3.txt
if (Test-Path $dmp) { & curl.exe -s -T $dmp http://192.168.122.1:8000/ccsetup.dmp }
Get-Content $note -Raw
