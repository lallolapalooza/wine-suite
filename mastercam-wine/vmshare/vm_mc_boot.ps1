# vm_mc_boot.ps1 - run the Mastercam 2027 bootstrapper from read-only media (CD/ISO) ELEVATED.
#
# Used by tools/vm/elev.sh (the UAC prompt is answered with Alt+Y host-side).  It locates the CD
# drive that carries setup.exe, records the media contents, starts the bootstrapper and then, so the
# host can follow the GUI without vision, PUTs a live log with the top-level window titles and free
# space every 15 s until the bootstrapper exits.
$ErrorActionPreference = 'Continue'
$U    = 'http://192.168.122.1:8000/'
$Log  = 'C:\vm_mc_boot.log'
function L($m) { Add-Content -Path $Log -Value ("{0} {1}" -f (Get-Date -Format o), $m) -Encoding utf8 }
function Put { curl.exe -s -T $Log ($U + 'vm_mc_boot.log') | Out-Null }
Set-Content -Path $Log -Value "" -Encoding utf8

L ("elevated=" + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
L ("user=" + $env:USERNAME + " TEMP=" + $env:TEMP)
L ("freeGB=" + [math]::Round((Get-PSDrive C).Free/1GB, 2))
L ("volumes=" + ((Get-Volume | ForEach-Object { "{0}:{1}:{2:N1}G/..." -f $_.DriveLetter, $_.DriveType, ($_.SizeRemaining/1GB) }) -join ' '))

$media = Get-Volume | Where-Object { $_.DriveType -eq 'CD-ROM' -and $_.DriveLetter } |
         ForEach-Object { $_.DriveLetter + ':\' } |
         Where-Object { Test-Path ($_ + 'setup.exe') } | Select-Object -First 1
L ("media=" + $media)
if (-not $media) { L 'NO MEDIA WITH setup.exe'; Put; exit 1 }

L ("media_root:"); Get-ChildItem $media | ForEach-Object { L ("  " + $_.Name) }
L ("datapaths.ini:"); Get-Content ($media + 'datapaths.ini') -ErrorAction SilentlyContinue | ForEach-Object { L ("  " + $_) }

$exe = $media + 'setup.exe'
L ("starting " + $exe)
$p = Start-Process -FilePath $exe -WorkingDirectory $media -PassThru
L ("setup_pid=" + $p.Id)
for ($i = 0; $i -lt 240; $i++) {
  Start-Sleep -Seconds 15
  $alive = -not $p.HasExited
  $ws = (Get-Process | Where-Object { $_.MainWindowTitle } | ForEach-Object { $_.ProcessName + '|' + $_.MainWindowTitle }) -join ' ;; '
  L ("t=" + ($i * 15) + "s alive=" + $alive + " freeGB=" + [math]::Round((Get-PSDrive C).Free/1GB, 2) + " windows: " + $ws)
  Put
  if (-not $alive) { L ("setup exited code=" + $p.ExitCode); break }
}
L 'boot-watch-end'
Put
