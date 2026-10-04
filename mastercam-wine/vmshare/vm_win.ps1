$ErrorActionPreference='Continue'
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class WinEnum {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int c);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static List<string> List() {
    var res = new List<string>();
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      var sb = new StringBuilder(1024); GetWindowText(h, sb, 1024);
      var cn = new StringBuilder(256); GetClassName(h, cn, 256);
      uint pid; GetWindowThreadProcessId(h, out pid);
      RECT r; GetWindowRect(h, out r);
      string title = sb.ToString();
      if (title.Length == 0 && !IsWindowVisible(h)) return true;
      res.Add(string.Format("{0}|{1}|{2}|{3}|{4},{5},{6},{7}|{8}", h.ToInt64(), pid, IsWindowVisible(h), cn.ToString(), r.L, r.T, r.R, r.B, title));
      return true;
    }, IntPtr.Zero);
    return res;
  }
  public static string Fg(string needle) {
    foreach (var s in List()) {
      var p = s.Split('|');
      if (p.Length >= 9 && (p[0] == needle || p[1] == needle || p[8].IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0)) {
        var h = new IntPtr(long.Parse(p[0]));
        ShowWindow(h, 9); SetForegroundWindow(h);
        return "activated " + p[0] + " " + p[8];
      }
    }
    return "not found: " + needle;
  }
}
'@
"hwnd|pid|visible|class|L,T,R,B|title"
[WinEnum]::List() | ForEach-Object { $_ }
"--- processes with windows ---"
Get-Process | Where-Object { $_.MainWindowHandle -ne 0 } | ForEach-Object { "{0} {1} '{2}'" -f $_.Id, $_.ProcessName, $_.MainWindowTitle }
"--- setup/msiexec processes ---"
Get-Process | Where-Object { $_.ProcessName -match 'setup|msiexec|Mastercam|Install' } | ForEach-Object { "{0} {1} hwnd={2} '{3}'" -f $_.Id, $_.ProcessName, $_.MainWindowHandle, $_.MainWindowTitle }
"done"
