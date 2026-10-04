$base = "C:\Users\adsf\AppData\Local\CapCut"
function D($p){ Write-Output ("===== " + $p + " ====="); if(Test-Path $p){ Get-Content $p -Raw -ErrorAction SilentlyContinue } else { Write-Output "(missing)" } }
D "$base\User Data\Config\EnvDetectSimulate.json"
D "$base\User Data\Config\vesdk.ini"
D "$base\User Data\Config\ve_ab_conf.ini"
D "$base\Apps\9.5.0.4050\..\Configure.ini"
Write-Output "=== detect/angle keys in globalSetting ==="
Get-Content "$base\User Data\Config\globalSetting" | Select-String -Pattern "render|Render|angle|Angle|dcomp|Composition|opengl|vulkan|rhi|Rhi|hw|Hw|gpu|Gpu|driver|Driver"
Write-Output "DONE"
