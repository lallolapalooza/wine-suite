# cleanup_vm.ps1 — remove every third-party app previously installed in the win11 reference VM.
# Runs elevated (invoked by the elevated poller / Start-Process from C:\seref).
# Progress is streamed to the host via http://192.168.122.1:8000/vm_cleanup_progress.txt
$ErrorActionPreference = 'Continue'
$U    = 'http://192.168.122.1:8000/'
$LOG  = 'C:\seref\cleanup.log'
$prog = 'C:\seref\vm_cleanup_progress.txt'
New-Item -ItemType Directory -Force -Path 'C:\seref' | Out-Null
Remove-Item $LOG, $prog -ErrorAction SilentlyContinue

function Say([string]$m) {
  $line = "{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
  Add-Content -Path $LOG -Value $line -Encoding utf8
  Write-Host $line
  Copy-Item $LOG $prog -Force -ErrorAction SilentlyContinue
  curl.exe -s -T $prog ($U + 'vm_cleanup_progress.txt') 2>$null | Out-Null
}

function FreeGB { [math]::Round((Get-PSDrive C).Free/1GB, 2) }

function Run([string]$file, [string[]]$arguments, [int]$timeoutSec = 900, [string]$tag = '') {
  if (-not (Test-Path $file)) { Say "SKIP(missing) $tag :: $file"; return }
  $argsTxt = ($arguments -join ' ')
  Say "RUN $tag :: $file $argsTxt"
  try {
    $p = Start-Process -FilePath $file -ArgumentList $arguments -PassThru -WindowStyle Hidden
    if (-not $p.WaitForExit($timeoutSec * 1000)) {
      Say "TIMEOUT(${timeoutSec}s) $tag pid=$($p.Id) -> kill"
      Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
      foreach ($c in (Get-CimInstance Win32_Process -Filter "ParentProcessId=$($p.Id)" -ErrorAction SilentlyContinue)) {
        Stop-Process -Id $c.ProcessId -Force -ErrorAction SilentlyContinue
      }
      Say "KILLED $tag"
    } else {
      Say "EXIT($($p.ExitCode)) $tag"
    }
  } catch { Say "ERROR $tag :: $_" }
}

function KillTree([string]$pattern) {
  $ps = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match $pattern }
  foreach ($p in $ps) {
    Say "KILL-PROC $($p.ProcessName) id=$($p.Id)"
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  }
}

Say "==== VM CLEANUP START free=${FreeGB}GB admin=$(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) ===="

# ---------------------------------------------------------------- phase A: stop everything
Say "--- phase A: stop vendor processes ---"
KillTree 'acad|AcWebBrowser|AdAppMgr|Autodesk|Adsk|AdODIS|CER|AdSSO|AdskAccess'
KillTree 'Eos|ETC|Augment|slpd|slptool'
KillTree 'Hog|win32-golden'
KillTree 'Resolume|Arena'
KillTree 'PBIDesktop|msmdsrv|PowerBI|pbidesktop'
KillTree 'Bonjour|mDNSResponder|mdnsNSP|AppleMobileDevice'
KillTree 'apitrace'
Start-Sleep -Seconds 3

# ---------------------------------------------------------------- phase B: MSI products
Say "--- phase B: msiexec /X (silent) ---"
$msiGuids = @(
  # Autodesk
  '{201AE4F3-3848-421F-A609-0A72B8FE631B}',  # Autodesk CER
  '{4E5E212E-F881-4C74-9F1B-5B1ADCB4BB7B}',  # Autodesk Genuine Service
  '{5BAB341A-E50E-4D25-AD9D-2E9D3019E759}',  # Augment3d
  '{5C8F1BCF-6909-471A-AA01-41E61C661D27}',  # Autodesk AutoCAD MCP Server
  '{6E3610B2-430D-4EB0-81E3-2B57E8B9DE8D}',  # Bonjour
  '{E23781A6-772C-36B9-9342-7486A04A7FC0}',  # Autodesk Interoperability Engine Manager
  '{F4DF9106-8D55-4CFB-83D4-A6C992E1D1BB}',  # ETCnomad Eos Application v3
  '{3E7AB300-A111-46B8-BE26-16C233ADBA77}',  # Autodesk App Manager
  '{5679FACE-1620-4E71-9956-6DFB0F725C11}',  # Autodesk Featured Apps
  '{6501E546-28F5-4A0E-97E0-1CD914185417}',  # Hog PC
  '{3b7bc56c-a839-49e5-b6ef-3f45ab825fc7}',  # Microsoft Power BI Desktop (x64)
  '{02FA636E-E6C1-4EEB-824D-45F7029F6DD7}'   # ETC USB Device Drivers
)
foreach ($g in $msiGuids) { Run 'msiexec.exe' @('/X', $g, '/qn', '/norestart', 'REBOOT=ReallySuppress') 600 "msi $g" }

# ---------------------------------------------------------------- phase C: EXE uninstallers
Say "--- phase C: vendor uninstallers ---"
Run 'C:\Program Files\Resolume Arena\unins000.exe' @('/SILENT', '/NORESTART') 600 'Resolume'
Run 'C:\Program Files\ETC\EosFamily\v3\Uninstall_Eos_Family_v3_Software.exe' @('/S', '/norestart') 900 'Eos'
Run 'C:\Windows\SysWOW64\SLP_Uninstall.exe' @('/S') 300 'ETC SLP'
Run 'C:\ProgramData\Package Cache\{cd9e3f41-53d3-4206-898f-b6c94c9c7fea}\PBIDesktopSetup_x64.exe' @('/uninstall', '/quiet', '/norestart') 900 'PowerBI bootstrapper'

# ---------------------------------------------------------------- phase D: Autodesk ODIS bundles
Say "--- phase D: Autodesk ODIS bundles ---"
$odis = 'C:\Program Files\Autodesk\AdODIS\V1\Installer.exe'
$bundles = @(
  @{ g = '{8658A469-1448-38DD-8981-8BED78BCCF9D}'; m = 'bundleManifest.xml'; n = 'AutoCAD 2027 - English' },
  @{ g = '{11132D68-6AC6-3DE8-B032-585A4939EC6A}'; m = 'bundleManifest.xml'; n = 'AutoCAD 2027.1 Update' },
  @{ g = '{A3158B3E-5F28-358A-BF1A-9532D8EBC811}'; m = 'pkg.access.xml';    n = 'Autodesk Access' }
)
foreach ($b in $bundles) {
  $meta = "C:\ProgramData\Autodesk\ODIS\metadata\$($b.g)"
  if (Test-Path "$meta\$($b.m)") {
    Run $odis @('-i','uninstall','--trigger_point','system','-m',"$meta\$($b.m)",
                '-x','C:\Program Files\Autodesk\AdODIS\V1\SetupRes\manifest.xsd') 1800 "ODIS $($b.n)"
  } else { Say "SKIP(missing meta) ODIS $($b.n) :: $meta\$($b.m)" }
}

# ---------------------------------------------------------------- phase E: leftover dirs
Say "--- phase E: force-remove leftover directories ---"
$dirs = @(
  'C:\Program Files\Autodesk', 'C:\Program Files (x86)\Autodesk',
  'C:\Program Files\Common Files\Autodesk Shared', 'C:\ProgramData\Autodesk',
  'C:\Program Files\Common Files\Autodesk', 'C:\Users\adsf\AppData\Local\Autodesk',
  'C:\Users\adsf\AppData\Roaming\Autodesk', 'C:\Users\adsf\AppData\Local\Autodesk\ODIS',
  'C:\Program Files\ETC', 'C:\Program Files (x86)\ETC', 'C:\ProgramData\ETC',
  'C:\Program Files\Hog PC', 'C:\Program Files\Hog', 'C:\Program Files (x86)\Hog PC',
  'C:\ProgramData\Hog', 'C:\Program Files\Resolume Arena', 'C:\ProgramData\Resolume Arena',
  'C:\Users\adsf\AppData\Local\Resolume Arena', 'C:\Users\adsf\AppData\Roaming\Resolume Arena',
  'C:\Program Files\Microsoft Power BI Desktop', 'C:\Program Files\Microsoft Power BI Desktop RS',
  'C:\Program Files\WindowsPowerShell\Modules\MicrosoftPowerBIMgmt',
  'C:\Program Files (x86)\Bonjour', 'C:\Program Files\Bonjour',
  'C:\Program Files\EosFamily'
)
foreach ($d in $dirs) {
  if (Test-Path $d) {
    takeown /F "$d" /R /D Y 2>$null | Out-Null
    icacls "$d" /grant "*S-1-5-32-544:(OI)(CI)F" /T /C /Q 2>$null | Out-Null
    Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
    Say "RM $d exists=$(Test-Path $d)"
  }
}

# ---------------------------------------------------------------- phase F: services / tasks / registry
Say "--- phase F: services, scheduled tasks, registry ---"
foreach ($svc in (Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Adsk|Autodesk|ETC|Hog|Resolume|PBIDesktop|slpd' })) {
  Say "SVC $($svc.Name) $($svc.Status)"
  Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
  & sc.exe delete $svc.Name 2>$null | Out-Null
}
foreach ($t in (Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match 'Autodesk|Adsk|ETC|Eos|Hog|Resolume|Power BI|SLP' })) {
  Say "TASK $($t.TaskPath)$($t.TaskName)"
  Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
}
foreach ($base in 'HKLM:\SOFTWARE\Autodesk', 'HKLM:\SOFTWARE\WOW6432Node\Autodesk',
                  'HKLM:\SOFTWARE\ETC', 'HKLM:\SOFTWARE\WOW6432Node\ETC',
                  'HKLM:\SOFTWARE\Hog', 'HKLM:\SOFTWARE\WOW6432Node\Hog',
                  'HKLM:\SOFTWARE\Resolume', 'HKLM:\SOFTWARE\WOW6432Node\Resolume',
                  'HKCU:\SOFTWARE\Autodesk', 'HKCU:\SOFTWARE\ETC', 'HKCU:\SOFTWARE\High End Systems',
                  'HKCU:\SOFTWARE\Resolume') {
  if (Test-Path $base) { Remove-Item $base -Recurse -Force -ErrorAction SilentlyContinue; Say "RMREG $base exists=$(Test-Path $base)" }
}
# stale uninstall entries
foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
  Get-ItemProperty $k -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match 'Autodesk|ETC|Hog|Resolume|Power BI|PowerBI|Augment3d|Bonjour' } |
    ForEach-Object { Say "STALE-ENTRY $($_.DisplayName) [$($_.PSChildName)]"; Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue }
}
# Autodesk/Eos leftovers in ProgramData paths not covered above
foreach ($p in @('C:\ProgramData\Autodesk\ODIS', 'C:\ProgramData\FLEXnet', 'C:\ProgramData\ETC',
                 'C:\ProgramData\Package Cache')) {
  if (Test-Path $p) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue; Say "RM $p exists=$(Test-Path $p)" }
}

# ---------------------------------------------------------------- phase G: report
Say "--- phase G: report ---"
Say "==== VM CLEANUP DONE free=${FreeGB}GB ===="
$rows = foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                         'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                         'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
  Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }
}
Say ("REMAINING " + (($rows | Sort-Object DisplayName -Unique | ForEach-Object { $_.DisplayName }) -join ' | '))
curl.exe -s -T $prog ($U + 'vm_cleanup_progress.txt') 2>$null | Out-Null
curl.exe -s -T $LOG  ($U + 'vm_cleanup.log') 2>$null | Out-Null
Say "UPLOADED"
