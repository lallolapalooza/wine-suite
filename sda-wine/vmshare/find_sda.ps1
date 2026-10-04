# Find where SDA installed, and any installer log.
$paths = @("C:\Program Files\Steinberg","C:\Program Files (x86)\Steinberg",
           "$env:LOCALAPPDATA\Programs\Steinberg","C:\ProgramData\Steinberg",
           "$env:APPDATA\Steinberg","$env:LOCALAPPDATA\Steinberg")
foreach ($p in $paths) {
  "PATH $p exists=$(Test-Path $p)"
  if (Test-Path $p) { Get-ChildItem $p -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 60 -Expand FullName }
}
"--- uninstall entries ---"
Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*,
                 HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*,
                 HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue |
  Where-Object {$_.DisplayName -match "Steinberg"} |
  Select-Object DisplayName,DisplayVersion,InstallLocation | Format-List
"--- temp logs ---"
Get-ChildItem $env:TEMP -ErrorAction SilentlyContinue | Where-Object {$_.Name -match "bitrock|install|sda"} |
  Sort-Object LastWriteTime -Descending | Select-Object -First 10 FullName,Length,LastWriteTime | Format-Table -Auto
"--- root dirs ---"
Get-ChildItem C:\ -Directory | Select-Object -Expand Name
"--- any exe named like sda/steinberg ---"
Get-ChildItem C:\ -Recurse -Filter "Steinberg*.exe" -ErrorAction SilentlyContinue -Depth 4 | Select-Object -First 20 -Expand FullName
