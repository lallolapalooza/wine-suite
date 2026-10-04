# vm_mc_install.ps1 - Mastercam 2027 install / evidence driver for the win11 guest.
#
# Published on the host HTTP share (http://192.168.122.1:8000/vm_mc_install.ps1) and pulled into the
# guest.  It is meant to be launched ELEVATED (Start-Process -Verb RunAs, UAC answered with Alt+Y by
# tools/vm/elev.sh), because the poller runs UAC-filtered (medium integrity) and cannot write under
# C:\Program Files or install an MSI machine-wide.
#
# Modes:
#   check   - record free space, installer presence/size (download if missing), nothing else.
#   sfx     - run the RAR SFX normally (auto extract to %TEMP% + run setup.exe), detached.
#   silent  - run the SFX with /s, detached.
#   msi     - run msiexec on the MSI found under the extracted SFX tree (en-US transform 1033.mst).
#   dump    - capture install tree + uninstall registry + exe versions, PUT them back.
#   launch  - start the installed main exe, wait, capture process/window state.
#
# Every mode appends to C:\vm_mc.log and PUTs the log + payloads back to the host share.

param(
  [ValidateSet('check','sfx','silent','msi','dump','launch','kill')]
  [string]$Mode = 'check',
  [string]$MsiArgs = '',
  [int]$TimeoutMin = 90,
  [string]$Exe = ''
)

$ErrorActionPreference = 'Continue'
$U     = 'http://192.168.122.1:8000/'
$Host_ = '192.168.122.1'
$Log   = 'C:\vm_mc.log'
$Mc    = 'C:\mc.exe'
$Want  = 2115737528

function Log([string]$m) {
  $line = "{0} [{1}] {2}" -f (Get-Date -Format o), $Mode, $m
  Write-Host $line
  Add-Content -Path $Log -Value $line -Encoding utf8
}
function Put([string]$p) {
  if (Test-Path $p) {
    curl.exe -s -T $p ($U + (Split-Path -Leaf $p)) | Out-Null
    Log ("PUT " + (Split-Path -Leaf $p) + " size=" + (Get-Item $p).Length)
  }
}
function FreeGB { [math]::Round((Get-PSDrive C).Free / 1GB, 2) }

Log ("host=" + $env:COMPUTERNAME + " user=" + $env:USERNAME + " admin=" + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
Log ("free_before_GB=" + (FreeGB))

# ---- installer staging ------------------------------------------------------
if (-not (Test-Path $Mc) -or (Get-Item $Mc).Length -ne $Want) {
  Log ("staging installer from http://" + $Host_ + ":8000/mastercam2027-web.exe")
  $t0 = Get-Date
  curl.exe -s -o $Mc "$U/mastercam2027-web.exe"
  Log ("download_seconds=" + [math]::Round(((Get-Date) - $t0).TotalSeconds,1))
}
$len = (Get-Item $Mc -ErrorAction SilentlyContinue).Length
Log ("installer_size=" + $len + " expected=" + $Want + " match=" + ($len -eq $Want))
Log ("free_after_stage_GB=" + (FreeGB))
Put $Log

# ---- helpers ----------------------------------------------------------------
function SfxTree { Get-ChildItem $env:TEMP -Directory -Filter 'Rar*' -ErrorAction SilentlyContinue }
function Snap([string]$tag) {
  # screenshot is taken host-side (virsh screenshot); here we only log window titles.
  $ws = Get-Process | Where-Object { $_.MainWindowTitle } | ForEach-Object { "{0}|{1}" -f $_.ProcessName, $_.MainWindowTitle }
  Log ("WINDOWS " + $tag + ": " + ($ws -join ' ;; '))
}
function WaitProc([string[]]$names, [int]$min) {
  $names = $names | ForEach-Object { $_ -replace '\.exe$', '' }
  $deadline = (Get-Date).AddMinutes($min)
  do {
    Start-Sleep -Seconds 10
    $p = Get-Process -Name $names -ErrorAction SilentlyContinue
    Log ("waiting: " + (($p | ForEach-Object { $_.ProcessName + '=' + $_.Id }) -join ',') + " free_GB=" + (FreeGB))
    Put $Log
  } while ($p -and (Get-Date) -lt $deadline)
  Log ("waited_done after " + $min + " min cap")
}

switch ($Mode) {

  'check' { }

  'sfx' {
    Log 'starting SFX (auto: extract to %TEMP% then setup.exe), detached'
    Start-Process -FilePath $Mc -WorkingDirectory (Split-Path $Mc)
    Start-Sleep -Seconds 20
    $t = SfxTree
    Log ("sfx_temp_dirs=" + (($t | ForEach-Object { $_.FullName }) -join ';'))
    foreach ($d in $t) { Log ("  " + $d.FullName + " files=" + (Get-ChildItem $d.FullName -Recurse -File -ErrorAction SilentlyContinue).Count) }
    Snap 'after-sfx'
    WaitProc @('setup','setup.exe','msiexec','Mastercam_Installer') $TimeoutMin
    Snap 'after-wait'
  }

  'silent' {
    Log 'starting SFX with /s'
    # WinRAR SFX: /s silent, /d<path> destination; keep unknown switches visible in the log.
    Start-Process -FilePath $Mc -ArgumentList '/s' -WorkingDirectory (Split-Path $Mc)
    Start-Sleep -Seconds 20
    Snap 'after-silent'
    WaitProc @('setup','setup.exe','msiexec') $TimeoutMin
    Snap 'after-wait'
  }

  'msi' {
    $q = Get-ChildItem 'C:\' -Recurse -Filter 'Mastercam_Installer.msi' -ErrorAction SilentlyContinue | Select-Object -First 3
    $tree = ($q | ForEach-Object { $_.FullName })
    Log ("msi_candidates=" + ($tree -join ';'))
    $dir = ($q | Where-Object { Test-Path (Join-Path $_.DirectoryName '1033.mst') } | Select-Object -First 1).DirectoryName
    if (-not $dir) { Log 'NO MSI FOUND under C:\ (SFX not extracted yet)'; break }
    $msi = Join-Path $dir 'Mastercam_Installer.msi'
    $mst = Join-Path $dir '1033.mst'
    $l2  = 'C:\vm_msi.log'
    if (-not $MsiArgs) { $MsiArgs = "/qn /norestart /l*v $l2" }
    if (Test-Path $mst) { $MsiArgs = "$MsiArgs TRANSFORMS=`"$mst`"" }
    Log ("msiexec /i `"$msi`" $MsiArgs")
    $cl = "msiexec.exe /i `"$msi`" $MsiArgs"
    $p = Start-Process cmd.exe -ArgumentList '/c', $cl -Wait -PassThru
    Log ("msiexec_exit=" + $p.ExitCode)
    Log ("free_after_GB=" + (FreeGB))
    Snap 'after-msi'
    Put 'C:\vm_msi.log'
  }

  'dump' {
    $cands = @('C:\Program Files\Mastercam 2027', 'C:\Program Files\Mastercam', 'C:\Program Files (x86)\Mastercam 2027')
    foreach ($d in $cands) {
      if (Test-Path $d) {
        $tag = ($d -replace '[^A-Za-z0-9]','_')
        $out = "C:\vm_tree$tag.txt"
        Get-ChildItem $d -Recurse -File -ErrorAction SilentlyContinue |
          Sort-Object FullName |
          ForEach-Object { "{0}`t{1}" -f $_.Length, $_.FullName } | Set-Content -Path $out -Encoding utf8
        $b = (Get-ChildItem $d -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        Log ("installdir=$d bytes=$b files=" + (Get-ChildItem $d -Recurse -File -ErrorAction SilentlyContinue).Count)
        Put $out
        # exe versions
        $v = "C:\vm_exe$tag.txt"
        Get-ChildItem $d -Recurse -Include *.exe,*.dll -File -ErrorAction SilentlyContinue |
          ForEach-Object { $i = $_.VersionInfo; "{0}`t{1}`t{2}`t{3}`t{4}" -f $_.FullName, $i.FileVersion, $i.ProductVersion, $i.CompanyName, $i.FileDescription } |
          Set-Content -Path $v -Encoding utf8
        Put $v
      } else { Log "absent: $d" }
    }
    foreach ($p in 'C:\Users\Public\Documents\Shared Mastercam 2027','C:\ProgramData\Mastercam','C:\ProgramData\Mastercam 2027') {
      if (Test-Path $p) { Log ("shared_dir=$p files=" + (Get-ChildItem $p -Recurse -File -ErrorAction SilentlyContinue).Count) }
    }
    $r = 'C:\vm_uninstall_reg.txt'
    $paths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
               'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
    & {
      foreach ($rp in $paths) {
        Get-ItemProperty $rp -ErrorAction SilentlyContinue |
          Where-Object { $_.DisplayName -match 'Mastercam|CodeMeter|Licens|VC\+\+|Visual C\+\+|\.NET' } |
          ForEach-Object { "KEY=$($_.PSPath)`n  DisplayName=$($_.DisplayName)`n  DisplayVersion=$($_.DisplayVersion)`n  Publisher=$($_.Publisher)`n  InstallLocation=$($_.InstallLocation)`n  UninstallString=$($_.UninstallString)`n  InstallDate=$($_.InstallDate)`n  EstimatedSize=$($_.EstimatedSize)" }
      }
    } | Set-Content -Path $r -Encoding utf8
    Log ('uninstall_reg_lines=' + (Get-Content $r -ErrorAction SilentlyContinue).Count)
    Put $r
    $sv = 'C:\vm_services.txt'
    Get-Service | Where-Object { $_.Name -match 'CodeMeter|Mastercam|Hasp|Wibu|NHasp' } |
      ForEach-Object { "{0}`t{1}`t{2}" -f $_.Name, $_.Status, $_.StartType } | Set-Content -Path $sv -Encoding utf8
    Put $sv
    Log ("free_after_GB=" + (FreeGB))
  }

  'launch' {
    $exe = $Exe
    if (-not $exe) {
      $c = @('C:\Program Files\Mastercam 2027\Mastercam.exe','C:\Program Files\Mastercam 2027\mastercam.exe','C:\Program Files\Mastercam 2027\Launcher\MastercamLauncher.exe')
      foreach ($x in $c) { if (Test-Path $x) { $exe = $x; break } }
    }
    Log ("launch_exe=" + $exe)
    if (-not (Test-Path $exe)) { Log 'MAIN EXE NOT FOUND'; break }
    $vi = (Get-Item $exe).VersionInfo
    Log ("version FileVersion=" + $vi.FileVersion + " ProductVersion=" + $vi.ProductVersion + " Desc=" + $vi.FileDescription)
    Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe)
    for ($i = 0; $i -lt 12; $i++) {
      Start-Sleep -Seconds 10
      Snap ("launch+" + (($i + 1) * 10) + "s")
      Put $Log
    }
    $applog = Get-ChildItem 'C:\Users\adsf\Documents' -Recurse -Include *.log -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 5
    foreach ($a in $applog) { Log ("applog=" + $a.FullName + " size=" + $a.Length); Put $a.FullName }
  }

  'kill' {
    foreach ($n in 'mastercam','Mastercam','MastercamLauncher','setup','msiexec') {
      Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object { Log ("kill " + $_.ProcessName + " " + $_.Id); Stop-Process -Id $_.Id -Force }
    }
  }
}

Log ("free_after_GB=" + (FreeGB))
Put $Log
