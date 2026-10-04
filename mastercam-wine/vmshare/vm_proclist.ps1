$ErrorActionPreference='Continue'
"freeGB=" + [math]::Round((Get-PSDrive C).Free/1GB,2)
Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'msiexec|setup|Mastercam|LanguagePack|CodeMeter' } | ForEach-Object { "{0} | {1} | {2}" -f $_.ProcessId, $_.Name, $_.CommandLine }
"--- dirs ---"
foreach ($d in 'C:\Program Files\Mastercam 2027','C:\Program Files\mcam','C:\Users\Public\Documents\Shared Mastercam 2027','C:\ProgramData\Mastercam','C:\Windows\Temp') {
  if (Test-Path $d) { $s=(Get-ChildItem $d -Recurse -File -EA 0 | Measure-Object Length -Sum); "{0} files={1} MB={2}" -f $d, $s.Count, [math]::Round($s.Sum/1MB,1) } else { "absent $d" }
}
