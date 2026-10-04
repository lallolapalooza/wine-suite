param([string]$ProcName="capcut_setup",[string]$Out="C:\Users\adsf\shot.png",[int]$MaxH=800,[int]$MaxW=1280)
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace CP -Name Api -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left,Top,Right,Bottom; }
'@
$p = Get-Process $ProcName -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if ($null -eq $p) { Write-Output "NO_PROC $ProcName"; exit 1 }
$h = $p.MainWindowHandle
$r = New-Object CP.Api+RECT
[void][CP.Api]::GetWindowRect($h, [ref]$r)
$w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
if ($w -le 0 -or $w -gt $MaxW) { $w = $MaxW }
if ($ht -le 0 -or $ht -gt $MaxH) { $ht = $MaxH }
Write-Output "win $w x $ht at $($r.Left),$($r.Top)"
$bmp = New-Object System.Drawing.Bitmap($w, $ht)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
$ok = [CP.Api]::PrintWindow($h, $hdc, 2)
$g.ReleaseHdc($hdc)
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "PrintWindow=$ok saved $Out"
