$base = "C:\Users\adsf\AppData\Local\CapCut"
Write-Output "=== 1. loaded ANGLE/D3D modules in CapCut processes ==="
$p = Get-Process CapCut -ErrorAction SilentlyContinue | Sort-Object WS -Descending | Select-Object -First 3
foreach ($x in $p) {
  Write-Output ("--- PID " + $x.Id + " WS=" + [math]::Round($x.WS/1MB,1) + "MB ---")
  $x.Modules | Where-Object { $_.ModuleName -match 'EGL|GLES|d3d11|dxgi|dcomp|D3DCompiler|opengl|vulkan|nvoglv|openvino' } | Select-Object ModuleName, FileName, ModuleMemorySize | Format-Table -AutoSize | Out-String -Width 250
}
Write-Output "=== 3a. EnvDetect* files under User Data\Config ==="
Get-ChildItem "$base\User Data\Config" -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "EnvDetect|gpu|render|angle|setting|ve" } | Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize | Out-String -Width 200
Write-Output "=== 3b. EnvDetect* next to exe ==="
Get-ChildItem "$base\Apps" -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "EnvDetect|env_detect|environment" } | Select-Object FullName,Length | Format-Table -AutoSize | Out-String -Width 250
Write-Output "=== 3c. Modules dir ==="
Get-ChildItem "$base\User Data\Modules" -Recurse -Force -ErrorAction SilentlyContinue | Select-Object FullName,Length | Format-Table -AutoSize | Out-String -Width 250
Write-Output "=== 3d. globalSetting ==="
Get-Content "$base\User Data\Config\globalSetting" -Raw -ErrorAction SilentlyContinue
Write-Output "=== 3e. gpu_driver_bug_list.json head ==="
$g = Get-Content "$base\User Data\Download\gpu_driver_bug_list.json" -Raw -ErrorAction SilentlyContinue
if ($g) { $g.Substring(0, [Math]::Min(1500, $g.Length)) }
Write-Output "=== 3f. all Render/gpu keys in EnvDetect.json ==="
Get-Content "$base\User Data\Config\EnvDetect.json" -Raw -ErrorAction SilentlyContinue
Write-Output "DONE"
