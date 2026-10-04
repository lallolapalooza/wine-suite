$ErrorActionPreference = 'Continue'
$exe = 'C:\Users\adsf\Downloads\ResArena.exe'
$log = 'C:\res_install.log'
Remove-Item 'C:\res_install_rc.txt' -ErrorAction SilentlyContinue
"[$(Get-Date -Format o)] starting $exe" | Out-File 'C:\res_install_rc.txt' -Encoding ascii -Append
$args = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=$log")
$p = Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru
"[$(Get-Date -Format o)] exit=$($p.ExitCode)" | Out-File 'C:\res_install_rc.txt' -Encoding ascii -Append
if (Test-Path 'C:\Program Files\Resolume Arena\Arena.exe') {
  $n = (Get-ChildItem 'C:\Program Files\Resolume Arena' -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
  "[$(Get-Date -Format o)] installed_bytes=$n" | Out-File 'C:\res_install_rc.txt' -Encoding ascii -Append
} else {
  "[$(Get-Date -Format o)] ARENA MISSING" | Out-File 'C:\res_install_rc.txt' -Encoding ascii -Append
}
