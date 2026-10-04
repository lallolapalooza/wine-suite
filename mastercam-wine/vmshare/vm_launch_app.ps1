$ErrorActionPreference='Continue'
$U='http://192.168.122.1:8000/'
$Log='C:\vm_launch_app.log'
function L($m){ Add-Content -Path $Log -Value ("{0} {1}" -f (Get-Date -Format o), $m) -Encoding utf8 }
Set-Content -Path $Log -Value "" -Encoding utf8
function Put { curl.exe -s -T $Log ($U + 'vm_launch_app.log') | Out-Null }

L ("elevated=" + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
L ("freeGB=" + [math]::Round((Get-PSDrive C).Free/1GB,2))

# what the shortcuts point at
foreach ($sm in (Get-ChildItem 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs' -Recurse -Filter '*Mastercam*' -ErrorAction SilentlyContinue)) {
  L ("shortcut " + $sm.FullName)
  try {
    $sh = New-Object -ComObject WScript.Shell
    $lnk = $sh.CreateShortcut($sm.FullName)
    L ("   target=" + $lnk.TargetPath + " args=" + $lnk.Arguments + " wd=" + $lnk.WorkingDirectory)
  } catch { L ("   (lnk read failed)") }
}

$cands = @(
  'C:\Program Files\Mastercam 2027\Mastercam.exe',
  'C:\Program Files\Mastercam 2027\MastercamLauncher.exe',
  'C:\Program Files\Mastercam 2027\mastercam.exe',
  'C:\Program Files\Common Files\Mastercam\McamVersionSelector.exe',
  'C:\Program Files\mcam\Mastercam.exe'
)
$exe = $null
foreach ($c in $cands) { if (Test-Path $c) { $i=(Get-Item $c).VersionInfo; L ("present " + $c + " FileVersion=" + $i.FileVersion + " ProductVersion=" + $i.ProductVersion + " Desc=" + $i.FileDescription) ; if (-not $exe) { $exe = $c } } else { L ("absent  " + $c) } }
L ("chosen_main_exe=" + $exe)

# launch the launcher (the vendor's normal entry point) and the real exe
$toRun = @()
if (Test-Path 'C:\Program Files\Mastercam 2027\MastercamLauncher.exe') { $toRun += 'C:\Program Files\Mastercam 2027\MastercamLauncher.exe' }
if ($exe -and $exe -notin $toRun) { $toRun += $exe }
foreach ($x in $toRun) {
  L ("starting " + $x)
  try { Start-Process -FilePath $x -WorkingDirectory (Split-Path $x) -PassThru | ForEach-Object { L ("  pid=" + $_.Id) } } catch { L ("  start failed: " + $_.Exception.Message) }
  Start-Sleep -Seconds 20
  $ws = (Get-Process | Where-Object { $_.MainWindowTitle } | ForEach-Object { $_.ProcessName + '|' + $_.MainWindowTitle }) -join ' ;; '
  L ("  windows: " + $ws)
  L ("  freeGB=" + [math]::Round((Get-PSDrive C).Free/1GB,2))
  Put
}
Start-Sleep -Seconds 20
$ps = Get-Process | Where-Object { $_.ProcessName -match 'Mastercam|MastercamLauncher|Mcam' } | ForEach-Object { $_.ProcessName + ' ' + $_.Id + ' hwnd=' + $_.MainWindowHandle + ' title=' + $_.MainWindowTitle + ' cpu=' + [math]::Round($_.CPU,1) }
L ("processes: " + ($ps -join ' ;; '))
Put
L 'launch-done'
Put
