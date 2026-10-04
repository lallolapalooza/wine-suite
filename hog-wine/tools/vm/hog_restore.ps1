$ErrorActionPreference = 'Continue'
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class WinCtl {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  public static List<string> Find(string want) {
    var r = new List<string>();
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      var t = new StringBuilder(512); GetWindowTextW(h, t, 512);
      if (t.ToString() == want) r.Add(h.ToInt64().ToString());
      return true;
    }, IntPtr.Zero);
    return r;
  }
}
'@
$RC = New-Object System.Collections.Generic.List[string]
# 1. close the stray Run dialog(s)
foreach ($RCs in [WinCtl]::Find('Run')) {
  $RCh = [IntPtr]([int64]$RCs)
  $RC.Add("closing Run hwnd=$RCs vis=$([WinCtl]::IsWindowVisible($RCh))")
  [WinCtl]::PostMessageW($RCh, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
}
Start-Sleep -Milliseconds 800
# 2. restore + foreground the launcher
foreach ($RCs in [WinCtl]::Find('Hog Start')) {
  $RCh = [IntPtr]([int64]$RCs)
  $RC.Add("launcher hwnd=$RCs visible_before=$([WinCtl]::IsWindowVisible($RCh))")
  [WinCtl]::ShowWindow($RCh, 9) | Out-Null                                  # SW_RESTORE
  [WinCtl]::SetWindowPos($RCh, [IntPtr](-1), 0,0,0,0, 0x43) | Out-Null     # TOPMOST, keep pos/size
  Start-Sleep -Milliseconds 300
  [WinCtl]::SetWindowPos($RCh, [IntPtr](-2), 0,0,0,0, 0x43) | Out-Null     # NOTOPMOST
  [WinCtl]::SetForegroundWindow($RCh) | Out-Null
  Start-Sleep -Milliseconds 400
  $RC.Add("after: visible=$([WinCtl]::IsWindowVisible($RCh))")
}
$RC | ForEach-Object { $_ }
