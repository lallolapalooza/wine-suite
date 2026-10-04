$ErrorActionPreference='Continue'
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class WC2 {
  public delegate bool P(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(P cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, P cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr SetActiveWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static List<string> Tops(uint wantPid) {
    var res = new List<string>();
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (wantPid != 0 && pid != wantPid) return true;
      var sb = new StringBuilder(1024); GetWindowText(h, sb, 1024);
      var cn = new StringBuilder(256); GetClassName(h, cn, 256);
      RECT r; GetWindowRect(h, out r);
      res.Add(string.Format("{0}|{1}|{2}|vis={3}|{4},{5},{6},{7}|{8}", h.ToInt64(), pid, cn.ToString(), IsWindowVisible(h), r.L, r.T, r.R, r.B, sb.ToString()));
      return true; }, IntPtr.Zero);
    return res;
  }
  public static List<string> Kids(IntPtr p) {
    var res = new List<string>();
    EnumChildWindows(p, delegate(IntPtr h, IntPtr l) {
      var sb = new StringBuilder(1024); GetWindowText(h, sb, 1024);
      var cn = new StringBuilder(256); GetClassName(h, cn, 256);
      RECT r; GetWindowRect(h, out r);
      res.Add(string.Format("{0}|{1}|vis={2}|en={3}|{4},{5},{6},{7}|{8}", h.ToInt64(), cn.ToString(), IsWindowVisible(h), IsWindowEnabled(h), r.L, r.T, r.B, r.B, sb.ToString()));
      return true; }, IntPtr.Zero);
    return res;
  }
  public static string Focus(IntPtr h) {
    ShowWindow(h, 9); BringWindowToTop(h); SetForegroundWindow(h); SetActiveWindow(h);
    return "focused " + h.ToInt64();
  }
}
'@
$setup = Get-Process setup -ErrorAction SilentlyContinue | Select-Object -First 1
"setup_pid=" + $setup.Id
"--- top windows of setup pid ---"
$tops = [WC2]::Tops([uint32]$setup.Id)
$tops | ForEach-Object { $_ }
$main = $null
foreach ($t in $tops) { if ($t -match '\|#32770\|' -and $t -match 'vis=True') { $main = [IntPtr]([int64]($t -split '\|')[0]); break } }
"main_dialog=" + $main
if ($main) {
  "--- children ---"
  [WC2]::Kids($main) | ForEach-Object { $_ }
  [WC2]::Focus($main)
  Start-Sleep -Milliseconds 300
  "foreground_now=" + [WC2]::GetForegroundWindow()
}
"done"
