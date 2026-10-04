$ErrorActionPreference='Continue'
$free=[math]::Round((Get-PSDrive C).Free/1GB,2)
"freeGB=$free usedGB=$([math]::Round((Get-PSDrive C).Used/1GB,2))"
"drives=" + ((Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Name + '=' + [math]::Round($_.Free/1GB,1) + 'G' }) -join ' ')
$mc = Get-Item C:\mc.exe -ErrorAction SilentlyContinue
"mc.exe=" + ($(if($mc){$mc.Length}else{'absent'}))
$paths = @('C:\Users\adsf\Downloads','C:\Windows\Temp','C:\Users\adsf\AppData\Local\Temp','C:\Windows\Installer','C:\Windows.old','C:\Program Files','C:\Program Files (x86)','C:\ProgramData','C:\Users\adsf\Documents','C:\Users\adsf\AppData\Local','C:\seref','C:\Users\Public\Documents')
foreach ($p in $paths) {
  if (Test-Path $p) {
    $s = (Get-ChildItem $p -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum)
    "{0,-45} {1,12:N0} MB  {2} files" -f $p, ($s.Sum/1MB), $s.Count
  } else { "{0,-45} absent" -f $p }
}
"--- biggest single files under C:\Users ---"
Get-ChildItem C:\Users -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object Length -gt 200MB | Sort-Object Length -Descending | Select-Object -First 20 | ForEach-Object { "{0,12:N0} MB  {1}" -f ($_.Length/1MB), $_.FullName }
"--- biggest single files under C:\Windows ---"
Get-ChildItem C:\Windows -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object Length -gt 400MB | Sort-Object Length -Descending | Select-Object -First 10 | ForEach-Object { "{0,12:N0} MB  {1}" -f ($_.Length/1MB), $_.FullName }
"--- recycle bin ---"
$rb=(Get-ChildItem 'C:\$Recycle.Bin' -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum)
"recycle={0:N0} MB" -f ($rb.Sum/1MB)
"--- volumes ---"
Get-Volume | ForEach-Object { "{0} {1} {2:N1}GB free of {3:N1}GB" -f $_.DriveLetter, $_.FileSystemLabel, ($_.SizeRemaining/1GB), ($_.Size/1GB) }
"--- existing Mastercam? ---"
foreach ($p in 'C:\Program Files\Mastercam 2027','C:\Program Files\mcam','C:\Program Files (x86)\Mastercam 2027','C:\Program Files\Common Files\Mastercam') { "{0} -> {1}" -f $p, (Test-Path $p) }
"done"
