$ErrorActionPreference = 'Continue'
"FREE_GB={0:N3}" -f ((Get-PSDrive C).Free/1GB)
"=== BIG DIRS (>1GB) ==="
Get-ChildItem C:\ -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
  $s = (Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
  if ($s -gt 1GB) { "BIG {0} {1:N2} GB" -f $_.FullName, ($s/1GB) }
}
"=== C:\Windows\Installer ==="
"{0:N1} MB" -f ((Get-ChildItem C:\Windows\Installer -File -Force -EA SilentlyContinue | Measure-Object Length -Sum).Sum/1MB)
"=== shadowstorage ==="
vssadmin list shadowstorage 2>&1 | ForEach-Object { $_ }
"=== revert pending ==="
Get-ChildItem C:\ -Recurse -Force -Directory -EA SilentlyContinue -Depth 1 -Filter '*.rbf' | ForEach-Object { "RBF {0}" -f $_.FullName }
Get-ChildItem C:\Config.Msi -Force -EA SilentlyContinue | ForEach-Object { "CONFIGMSI {0} {1}" -f $_.Name, $_.Length }
"=== pull msi log ==="
& curl.exe -s -T C:\hog\hog_msi.log http://192.168.122.1:8000/vm_hog_msi.log
"PULL_RC=$LASTEXITCODE"
