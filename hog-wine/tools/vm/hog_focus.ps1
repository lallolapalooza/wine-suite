$ErrorActionPreference = 'Continue'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class Fg {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern IntPtr FindWindowW(string cls, string title);
}
'@
$HTitle = 'Hog Start'
$HH = [Fg]::FindWindowW($null, $HTitle)
"FOUND hwnd=0x$('{0:X}' -f $HH.ToInt64())"
if ($HH -ne [IntPtr]::Zero) {
  [Fg]::ShowWindow($HH, 9) | Out-Null          # SW_RESTORE
  [Fg]::SetWindowPos($HH, [IntPtr]::new(-1), 0,0,0,0, 0x0003) | Out-Null  # HWND_TOPMOST|NOSIZE|NOMOVE
  [Fg]::SetWindowPos($HH, [IntPtr]::new(-2), 0,0,0,0, 0x0003) | Out-Null  # HWND_NOTOPMOST
  [Fg]::SetForegroundWindow($HH) | Out-Null
  Start-Sleep -Milliseconds 500
  "FG=" + [System.Diagnostics.Process]::GetProcessById(0)
}
Get-Process -EA SilentlyContinue | Where-Object { $_.ProcessName -match 'golden' } | ForEach-Object { "PROC {0} pid={1} title='{2}'" -f $_.ProcessName, $_.Id, $_.MainWindowTitle }
