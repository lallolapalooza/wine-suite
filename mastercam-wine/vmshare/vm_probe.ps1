$ErrorActionPreference='Continue'
$p = Get-Process setup -ErrorAction SilentlyContinue
if (-not $p) { 'setup NOT RUNNING' } else {
  "pid=$($p.Id) cpu=$($p.CPU) ws=$([math]::Round($p.WorkingSet64/1MB,1))MB threads=$($p.Threads.Count) handles=$($p.HandleCount) responding=$($p.Responding) startTime=$($p.StartTime)"
  "path=$($p.Path)"
  "modules=" + (($p.Modules | Select-Object -First 15 | ForEach-Object ModuleName) -join ',')
  "cputime_now=" + $p.TotalProcessorTime
}
Start-Sleep -Seconds 5
$p2 = Get-Process setup -ErrorAction SilentlyContinue
if ($p2) { "after5s cpu=$($p2.CPU) threads=$($p2.Threads.Count) ws=$([math]::Round($p2.WorkingSet64/1MB,1))MB" }
"--- children of setup ---"
Get-CimInstance Win32_Process -Filter "Name like '%setup%' or Name like '%msiexec%' or Name like '%Mastercam%'" | ForEach-Object { "{0} {1} parent={2} cmd={3}" -f $_.ProcessId, $_.Name, $_.ParentProcessId, $_.CommandLine }
"--- E:\ writability / temp activity ---"
Get-ChildItem $env:TEMP -ErrorAction SilentlyContinue | Select-Object -First 15 | ForEach-Object { "{0} {1}" -f $_.Name, $_.LastWriteTime }
"--- any new dirs on C: ---"
Get-ChildItem C:\ -Directory | ForEach-Object Name
"done"
