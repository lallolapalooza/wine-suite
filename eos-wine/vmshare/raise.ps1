$ErrorActionPreference='Continue'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class W3 {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
}
'@
$HWND_TOPMOST = [IntPtr](-1)
$SWP_SHOWWINDOW = 0x40
$SWP_NOMOVE = 0x2
$SWP_NOSIZE = 0x1
$targets = @{}
Get-Process ETC_LaunchOffline,ETC_Launch,Eos,augment3d_app -ErrorAction SilentlyContinue | ForEach-Object {
  if ($_.MainWindowHandle -ne 0) { $targets[$_.ProcessName + ":" + $_.Id] = $_.MainWindowHandle }
}
if ($args.Count -gt 0 -and $args[0] -eq 'minimize-console') {
  $c = Get-Process | Where-Object { $_.MainWindowTitle -like '*Windows PowerShell*' }
  foreach ($p in $c) { [void][W3]::ShowWindow($p.MainWindowHandle, 6); "minimized console " + $p.Id }
}
foreach ($k in $targets.Keys) {
  $h = $targets[$k]
  [void][W3]::ShowWindow($h, 5)
  [void][W3]::SetWindowPos($h, $HWND_TOPMOST, 0,0,0,0, $SWP_NOMOVE -bor $SWP_NOSIZE -bor $SWP_SHOWWINDOW)
  [void][W3]::BringWindowToTop($h)
  [void][W3]::SetForegroundWindow($h)
  "raised $k hwnd=0x{0:X}" -f $h.ToInt64()
}
