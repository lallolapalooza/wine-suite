# cleanup_force.ps1 — second-pass VM cleanup: instead of waiting on vendor uninstallers
# (the Autodesk ODIS `Installer.exe -i uninstall` hangs for >30 min per bundle), stop everything,
# force-remove the trees, then strip services / scheduled tasks / registry.
# Progress is streamed to http://192.168.122.1:8000/vm_cleanup_progress.txt
$ErrorActionPreference = 'Continue'
$U    = 'http://192.168.122.1:8000/'
$LOG  = 'C:\seref\cleanup2.log'
$prog = 'C:\seref\vm_cleanup_progress.txt'
New-Item -ItemType Directory -Force -Path 'C:\seref' | Out-Null
Remove-Item $LOG -ErrorAction SilentlyContinue

function Say([string]$m) {
  $line = "{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
  Add-Content -Path $LOG -Value $line -Encoding utf8
  Copy-Item $LOG $prog -Force -ErrorAction SilentlyContinue
  curl.exe -s -T $prog ($U + 'vm_cleanup_progress.txt') 2>$null | Out-Null
}
function FreeGB { [math]::Round((Get-PSDrive C).Free/1GB, 2) }

Say "==== FORCE CLEANUP START free=$(FreeGB)GB ===="

# --- stop the first-pass cleanup script so it cannot race us into phase E/F
foreach ($p in (Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                Where-Object { $_.CommandLine -like '*cleanup_vm.ps1*' })) {
  Say "KILL cleanup_vm.ps1 pid=$($p.ProcessId)"
  Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 1

# --- kill the still-running vendor uninstallers and every vendor process
Say "--- kill uninstallers + vendor processes ---"
foreach ($p in (Get-Process -ErrorAction SilentlyContinue | Where-Object {
      $_.ProcessName -match 'Installer|AdODIS|msiexec|acad|Adsk|Autodesk|CER|AdSSO|cer_service|Eos|ETC|Augment|slpd|slptool|Hog|Resolume|PBIDesktop|msmdsrv|PowerBI|Bonjour|mDNSResponder|apitrace|Setup' })) {
  Say "KILL $($p.ProcessName) id=$($p.Id)"
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 4
# kill the cleanup script's own earlier ODIS children if still alive
foreach ($p in (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'Installer' })) {
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

# --- services first, so their files are not locked
Say "--- services + scheduled tasks ---"
foreach ($svc in (Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Adsk|Autodesk|ETC|slpd|Hog|Resolume|PBIDesktop|PowerBI|Bonjour|mDNS' })) {
  Say "SVC $($svc.Name) $($svc.Status)"
  Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
  & sc.exe delete $svc.Name 2>$null | Out-Null
}
foreach ($t in (Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match 'Autodesk|Adsk|ETC|Eos|Hog|Resolume|Power BI|PowerBI|SLP|Bonjour' })) {
  Say "TASK $($t.TaskPath)$($t.TaskName)"
  Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
}
# ETC USB drivers registered as PnP driver services
foreach ($d in @('ETC_WinUSB','usbdrv','ETCUsb')) {
  & pnputil.exe /delete-driver "$d.inf" /uninstall /force 2>$null | Out-Null
}

# --- force-remove directories
Say "--- force-remove directories ---"
$dirs = @(
  'C:\Program Files\Autodesk', 'C:\Program Files (x86)\Autodesk',
  'C:\Program Files\Common Files\Autodesk Shared', 'C:\Program Files\Common Files\Autodesk',
  'C:\ProgramData\Autodesk', 'C:\ProgramData\FLEXnet',
  'C:\Users\adsf\AppData\Local\Autodesk', 'C:\Users\adsf\AppData\Roaming\Autodesk',
  'C:\Program Files\ETC', 'C:\Program Files (x86)\ETC', 'C:\ProgramData\ETC',
  'C:\Program Files\Hog PC', 'C:\Program Files\Hog', 'C:\Program Files (x86)\Hog PC',
  'C:\ProgramData\Hog', 'C:\Program Files (x86)\High End Systems',
  'C:\Program Files\Resolume Arena', 'C:\ProgramData\Resolume Arena',
  'C:\Users\adsf\AppData\Local\Resolume Arena', 'C:\Users\adsf\AppData\Roaming\Resolume Arena',
  'C:\Program Files\Microsoft Power BI Desktop', 'C:\Program Files\Microsoft Power BI Desktop RS',
  'C:\Program Files (x86)\Microsoft Power BI Desktop',
  'C:\Program Files\Bonjour', 'C:\Program Files (x86)\Bonjour',
  'C:\ProgramData\Package Cache', 'C:\Program Files (x86)\InstallShield Installation Information'
)
foreach ($d in $dirs) {
  if (Test-Path $d) {
    takeown /F "$d" /R /D Y 2>$null | Out-Null
    icacls "$d" /grant "*S-1-5-32-544:(OI)(CI)F" /T /C /Q 2>$null | Out-Null
    Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 300
    if (Test-Path $d) {
      # second pass: kill anything that re-locked it, then retry
      Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$d*" } | Stop-Process -Force -ErrorAction SilentlyContinue
      Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
    }
    Say "RM $d exists=$(Test-Path $d)"
  }
}

# --- registry
Say "--- registry ---"
foreach ($base in 'HKLM:\SOFTWARE\Autodesk', 'HKLM:\SOFTWARE\WOW6432Node\Autodesk',
                  'HKLM:\SOFTWARE\ETC', 'HKLM:\SOFTWARE\WOW6432Node\ETC',
                  'HKLM:\SOFTWARE\High End Systems', 'HKLM:\SOFTWARE\WOW6432Node\High End Systems',
                  'HKLM:\SOFTWARE\Resolume', 'HKLM:\SOFTWARE\WOW6432Node\Resolume',
                  'HKCU:\SOFTWARE\Autodesk', 'HKCU:\SOFTWARE\ETC', 'HKCU:\SOFTWARE\High End Systems',
                  'HKCU:\SOFTWARE\Resolume', 'HKLM:\SOFTWARE\CELSYS') {
  if (Test-Path $base) { Remove-Item $base -Recurse -Force -ErrorAction SilentlyContinue; Say "RMREG $base exists=$(Test-Path $base)" }
}
$pat = 'Autodesk|ETC|Hog|Resolume|Power BI|PowerBI|Augment3d|Bonjour|AutoCAD|ACAD'
foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
  Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match $pat } |
    ForEach-Object { Say "STALE $($_.DisplayName)"; Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue }
}
# run keys / services leftovers
foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')) {
  Get-ItemProperty $k -ErrorAction SilentlyContinue | Get-Member -MemberType NoteProperty |
    Where-Object { $_.Name -match $pat } | ForEach-Object { Say "RUNKEY $($_.Name)"; Remove-ItemProperty $k -Name $_.Name -Force -ErrorAction SilentlyContinue }
}

# --- report
Say "--- report ---"
Say "==== FORCE CLEANUP DONE free=$(FreeGB)GB ===="
$rows = foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                         'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                         'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
  Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }
}
Say ("REMAINING " + (($rows | Sort-Object DisplayName -Unique | ForEach-Object { $_.DisplayName }) -join ' | '))
curl.exe -s -T $prog ($U + 'vm_cleanup_progress.txt') 2>$null | Out-Null
curl.exe -s -T $LOG  ($U + 'vm_cleanup2.log') 2>$null | Out-Null
Say "UPLOADED"
