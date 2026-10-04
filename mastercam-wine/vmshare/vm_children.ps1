$ErrorActionPreference='Continue'
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class WC {
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
  [DllImport("user32.dll")] public static extern IntPtr FindWindowW(string c, string t);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static List<string> Kids(IntPtr p) {
    var res = new List<string>();
    EnumChildWindows(p, delegate(IntPtr h, IntPtr l) {
      var sb = new StringBuilder(1024); GetWindowText(h, sb, 1024);
      var cn = new StringBuilder(256); GetClassName(h, cn, 256);
      RECT r; GetWindowRect(h, out r);
      res.Add(string.Format("{0}|{1}|vis={2}|en={3}|{4}|{5},{6},{7},{8}|{9}", h.ToInt64(), cn.ToString(), IsWindowVisible(h), IsWindowEnabled(h), "", r.L, r.T, r.R, r.B, sb.ToString()));
      return true;
    }, IntPtr.Zero);
    return res;
  }
  public static List<string> Tops() {
    var res = new List<string>();
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      var sb = new StringBuilder(1024); GetWindowText(h, sb, 1024);
      if (sb.Length == 0) return true;
      var cn = new StringBuilder(256); GetClassName(h, cn, 256);
      uint pid; GetWindowThreadProcessId(h, out pid);
      res.Add(string.Format("{0}|{1}|{2}|{3}|{4}", h.ToInt64(), pid, cn.ToString(), IsWindowVisible(h), sb.ToString()));
      return true; }, IntPtr.Zero);
    return res;
  }
  public static string FgInfo() {
    var h = GetForegroundWindow(); uint pid; GetWindowThreadProcessId(h, out pid);
    var sb = new StringBuilder(512); GetWindowText(h, sb, 512);
    return string.Format("{0}|{1}|{2}", h.ToInt64(), pid, sb.ToString());
  }
}
'@
"elevated=" + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
"foreground=" + [WC]::FgInfo()
"--- top windows ---"
[WC]::Tops() | ForEach-Object { $_ }
"--- installer dialog children ---"
foreach ($t in '2027 (Build 29.0.10172.0)','Mastercam Installation Manager') {
  $h = [WC]::FindWindowW('#32770', $t)
  if ($h -ne [IntPtr]::Zero) {
    "== dialog '$t' hwnd=$h =="
    [WC]::Kids($h) | ForEach-Object { $_ }
  }
}
"done"
