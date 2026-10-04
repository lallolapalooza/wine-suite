$ErrorActionPreference='Continue'
$U='http://192.168.122.1:8000/'
$Log='C:\vm_msi.log'
function L($m){ Add-Content -Path 'C:\vm_msi_run.log' -Value ("{0} {1}" -f (Get-Date -Format o), $m) -Encoding utf8 }
Set-Content -Path 'C:\vm_msi_run.log' -Value "" -Encoding utf8
function Put { foreach ($f in 'C:\vm_msi_run.log','C:\vm_msi_tail.log') { if (Test-Path $f) { curl.exe -s -T $f ($U + (Split-Path -Leaf $f)) | Out-Null } } }

L ("elevated=" + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
L ("freeGB_before=" + [math]::Round((Get-PSDrive C).Free/1GB,2))

# the direct-MSIX path runs once the bootstrapper is out of the way
Get-Process setup -ErrorAction SilentlyContinue | ForEach-Object { L ("stopping setup " + $_.Id); Stop-Process -Id $_.Id -Force }

$msi = 'E:\mastercam\Mastercam_Installer.msi'
$mst = 'E:\mastercam\1033.mst'
L ("msi=" + $msi + " exists=" + (Test-Path $msi) + " size=" + (Get-Item $msi -EA 0).Length)
L ("mst=" + $mst + " exists=" + (Test-Path $mst))

$cl = 'msiexec.exe /i "' + $msi + '" TRANSFORMS="' + $mst + '" INSTALLDIR="C:\Program Files\Mastercam 2027" /qn /norestart /l*v "' + $Log + '"'
L ("CMDLINE: " + $cl)
$t0 = Get-Date
$p = Start-Process cmd.exe -ArgumentList '/c', $cl -Wait -PassThru
L ("exit=" + $p.ExitCode + " seconds=" + [math]::Round(((Get-Date)-$t0).TotalSeconds,1))
L ("freeGB_after=" + [math]::Round((Get-PSDrive C).Free/1GB,2))
L ("msi_log_bytes=" + (Get-Item $Log -EA 0).Length)
if (Test-Path $Log) { Get-Content $Log -Tail 120 | Set-Content 'C:\vm_msi_tail.log' -Encoding utf8 }
foreach ($d in 'C:\Program Files\Mastercam 2027','C:\Program Files\Common Files\Mastercam','C:\Users\Public\Documents\Shared Mastercam 2027') {
  if (Test-Path $d) { L ("installed " + $d + " files=" + (Get-ChildItem $d -Recurse -File -EA 0).Count + " MB=" + [math]::Round(((Get-ChildItem $d -Recurse -File -EA 0 | Measure-Object Length -Sum).Sum/1MB),1)) }
  else { L ("absent " + $d) }
}
L 'msi-run-done'
Put
