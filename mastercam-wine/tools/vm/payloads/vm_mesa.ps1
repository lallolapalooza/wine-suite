$ErrorActionPreference = 'Continue'
$d = 'C:\Program Files\Resolume Arena'
$files = @('opengl32.dll', 'libgallium_wgl.dll', 'dxil.dll')
foreach ($f in $files) {
  curl.exe -s -o "$d\$f" "http://192.168.122.1:8000/mesa_win/$f"
  $len = (Get-Item "$d\$f" -ErrorAction SilentlyContinue).Length
  "[$(Get-Date -Format o)] $f -> $len" | Out-File 'C:\mesa_deploy.txt' -Encoding ascii -Append
}
Get-ChildItem "$d\*.dll" | Select-Object Name, Length | Out-String | Out-File 'C:\mesa_deploy.txt' -Encoding ascii -Append
