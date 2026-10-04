$ErrorActionPreference='Continue'
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowW(string cls, string title);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool EnableWindow(IntPtr h, bool b);
'@
"--- tidy clutter ---"
foreach ($n in 'msedge','Notepad') { Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object { "kill " + $n + " " + $_.Id; Stop-Process -Id $_.Id -Force } }
$h = [W.U]::FindWindowW('#32770', 'Mastercam Installation Manager')
"hwnd=$h"
if ($h -ne [IntPtr]::Zero) {
  "visible_before=" + [W.U]::IsWindowVisible($h)
  [W.U]::ShowWindow($h, 9) | Out-Null
  [W.U]::ShowWindow($h, 5) | Out-Null
  [W.U]::EnableWindow($h, $true) | Out-Null
  [W.U]::SetForegroundWindow($h) | Out-Null
  Start-Sleep -Seconds 1
  "visible_after=" + [W.U]::IsWindowVisible($h)
}
Start-Sleep -Seconds 1
"--- windows now ---"
Add-Type -TypeDefinition @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public class WE2 {
  public delegate bool P(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(P cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public static List<string> L() { var r = new List<string>();
    EnumWindows(delegate(IntPtr h, IntPtr l) { var s=new StringBuilder(1024); GetWindowText(h,s,1024); if (s.Length==0) return true;
      var c=new StringBuilder(256); GetClassName(h,c,256); uint pid; GetWindowThreadProcessId(h,out pid);
      r.Add(string.Format("{0}|{1}|vis={2}|{3}|{4}", h.ToInt64(), pid, IsWindowVisible(h), c.ToString(), s.ToString())); return true; }, IntPtr.Zero);
    return r; } }
'@
[WE2]::L() | ForEach-Object { $_ }
"done"
