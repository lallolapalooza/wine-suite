$ErrorActionPreference='Continue'
$o = New-Object System.Collections.Generic.List[string]
$o.Add("=== time " + (Get-Date).ToString('s'))
$roots = @('C:\Users\adsf\AppData\Local\ETC','C:\Users\adsf\AppData\Roaming\ETC','C:\Users\adsf\Documents\ETC')
foreach ($r in $roots) {
  $o.Add("--- tree $r")
  if (Test-Path $r) {
    Get-ChildItem $r -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object FullName | ForEach-Object {
      if ($_.PSIsContainer) { $o.Add("  DIR  " + $_.FullName) } else { $o.Add("  {0,10} {1}" -f $_.Length, $_.FullName) }
    }
  } else { $o.Add("  MISSING") }
}
$o | Set-Content -Encoding UTF8 'C:\eos-ref\etc_tree_user.txt'
$o | ForEach-Object { $_ }
& curl.exe -s -T 'C:\eos-ref\etc_tree_user.txt' 'http://192.168.122.1:8000/vm_etc_tree_user.txt' | Out-Null

# copy interesting files
$base = 'C:\Users\adsf\AppData\Local\ETC\EosFamily\v3'
$names = @('OnyxConsole.log','NetworkFeedback.log','eos.ini','EosConsole.log','Console.log')
foreach ($n in $names) {
  $p = Join-Path $base $n
  if (Test-Path $p) {
    $dst = "C:\eos-ref\$n"
    Copy-Item $p $dst -Force
    "COPIED $p ($((Get-Item $p).Length) bytes)"
    & curl.exe -s -T $dst "http://192.168.122.1:8000/vm_$n" | Out-Null
  } else { "ABSENT $p" }
}
