$ErrorActionPreference = "Continue"
$out = "C:\Users\adsf\urlscan.txt"
$note = "C:\Users\adsf\urlhunt_note2.txt"
Remove-Item $out, $note -Force -ErrorAction SilentlyContinue

Add-Type -Namespace K -Name Api -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
[DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
[DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr VirtualQueryEx(IntPtr h, IntPtr addr, out MEMORY_BASIC_INFORMATION mbi, IntPtr len);
[DllImport("kernel32.dll", SetLastError=true)] public static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, int size, out IntPtr read);
[StructLayout(LayoutKind.Sequential)] public struct MEMORY_BASIC_INFORMATION {
  public IntPtr BaseAddress; public IntPtr AllocationBase; public uint AllocationProtect;
  public ulong RegionSize; public uint State; public uint Protect; public uint Type; }
'@

function Get-MemStrings([int]$pid) {
  $h = [K.Api]::OpenProcess(0x0410, $false, [uint32]$pid)   # QUERY_INFORMATION|VM_READ
  if ($h -eq [IntPtr]::Zero) { return @("OPEN_FAILED") }
  $found = New-Object System.Collections.Generic.HashSet[string]
  $addr = [IntPtr]::Zero
  $mbi = New-Object K.Api+MEMORY_BASIC_INFORMATION
  $mbiSize = [System.Runtime.InteropServices.Marshal]::SizeOf($mbi)
  $results = @()
  $iter = 0
  while ([K.Api]::VirtualQueryEx($h, $addr, [ref]$mbi, [IntPtr]$mbiSize) -ne [IntPtr]::Zero) {
    $iter++
    if ($iter -gt 200000) { break }
    $base = [uint64]$mbi.BaseAddress
    $size = [uint64]$mbi.RegionSize
    $nxt  = $base + $size
    $prot = $mbi.Protect
    $readable = ($mbi.State -eq 0x1000) -and (($prot -band 0x02) -or ($prot -band 0x04) -or ($prot -band 0x20) -or ($prot -band 0x40))
    if ($readable -and $size -gt 0 -and $size -le 200MB) {
      $chunk = 1MB
      $off = 0
      while ($off -lt $size) {
        $n = [int][Math]::Min([uint64]$chunk, $size - $off)
        $buf = New-Object byte[] $n
        $got = [IntPtr]::Zero
        $ok = [K.Api]::ReadProcessMemory($h, [IntPtr]([int64]($base + $off)), $buf, $n, [ref]$got)
        if ($ok) {
          $s = [Text.Encoding]::ASCII.GetString($buf)
          foreach ($m in [regex]::Matches($s, 'https?://[ -~]{6,400}')) {
            $v = $m.Value
            if ($v -match 'ibytedtos|bytecdn|bytedance|capcutapi|capcutstatic|zijieapi|capcut|byteoversea|akamai|cdn') {
              if ($found.Add($v)) { $results += $v }
            }
          }
        }
        $off += $chunk
      }
    }
    $addr = [IntPtr]([int64]$nxt)
    if ($nxt -le $base) { break }
  }
  [void][K.Api]::CloseHandle($h)
  return $results
}

"start=$(Get-Date -Format o)" | Set-Content $note
Remove-Item "$env:TEMP\installer_downloader.log" -Force -ErrorAction SilentlyContinue
Get-ChildItem "C:\Users\adsf\AppData\Local" -Directory -Filter "app_shell_cache_*" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Start-Process "C:\Users\adsf\capcut_setup.exe"

$pkg = $null
for ($i=0; $i -lt 60; $i++) {
  Start-Sleep -Seconds 3
  $f = Get-ChildItem "C:\Users\adsf\AppData\Local" -Directory -Filter "app_shell_cache_*" -ErrorAction SilentlyContinue |
       ForEach-Object { Get-ChildItem $_.FullName -File -ErrorAction SilentlyContinue } | Select-Object -First 1
  if ($f -and $f.Length -gt 10MB) { $pkg = $f; break }
}
if (-not $pkg) { Add-Content $note "no payload appeared within 180s" } else {
  Add-Content $note ("payload started: " + $pkg.FullName + " size=" + $pkg.Length)
  $cp = Get-Process capcut_setup -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cp) {
    Add-Content $note ("scanning pid " + $cp.Id)
    $r = Get-MemStrings $cp.Id
    Add-Content $note "=== URLS IN MEMORY ==="
    $r | Sort-Object -Unique | ForEach-Object { Add-Content $note $_ }
  } else { Add-Content $note "capcut_setup not found for scan" }
}
# let the download finish (wait for stability or the log marker)
$last = -1; $stable = 0; $done = $false
for ($i=0; $i -lt 120; $i++) {
  Start-Sleep -Seconds 3
  $t = ""
  if (Test-Path "$env:TEMP\installer_downloader.log") { $t = Get-Content "$env:TEMP\installer_downloader.log" -Raw -ErrorAction SilentlyContinue }
  if ($t -match "Downloader download finish") { $done = $true; break }
  $sz = 0
  Get-ChildItem "C:\Users\adsf\AppData\Local" -Directory -Filter "app_shell_cache_*" -ErrorAction SilentlyContinue |
    ForEach-Object { Get-ChildItem $_.FullName -File -ErrorAction SilentlyContinue } | ForEach-Object { $sz += $_.Length }
  if ($sz -eq $last -and $sz -gt 100MB) { $stable++; if ($stable -ge 3) { break } } else { $stable = 0 }
  $last = $sz
}
Add-Content $note ("download done marker=$done size=" + $last)
# stop the stub BEFORE it installs
Get-Process capcut_setup -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$p = Get-ChildItem "C:\Users\adsf\AppData\Local" -Directory -Filter "app_shell_cache_*" -ErrorAction SilentlyContinue |
     ForEach-Object { Get-ChildItem $_.FullName -File -ErrorAction SilentlyContinue } | Select-Object -First 1
if ($p) {
  Add-Content $note ("payload final: " + $p.FullName + " size=" + $p.Length)
  Add-Content $note ("payload sha256=" + (Get-FileHash $p.FullName -Algorithm SHA256).Hash)
  Copy-Item $p.FullName "C:\Users\adsf\capcut_installer_payload.exe" -Force
}
Add-Content $note "=== DNS (relevant) ==="
Get-DnsClientCache -ErrorAction SilentlyContinue | Where-Object { $_.Entry -match "capcut|bytedance|ibytedtos|zijie|byteoversea|capcutstatic|beecdn" } | ForEach-Object { Add-Content $note ($_.Entry + " -> " + $_.Data) }
Add-Content $note "DONE"
Copy-Item $note $out -Force
& curl.exe -s -T $out http://192.168.122.1:8000/urlscan.txt
if (Test-Path "C:\Users\adsf\capcut_installer_payload.exe") { & curl.exe -s -T "C:\Users\adsf\capcut_installer_payload.exe" http://192.168.122.1:8000/capcut_installer_payload.exe }
Get-Content $out -Raw
