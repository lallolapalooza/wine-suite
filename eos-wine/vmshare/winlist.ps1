$ErrorActionPreference = 'Continue'
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class WinEnum {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr hWnd, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr hWnd, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool IsHungAppWindow(IntPtr hWnd);
  public static List<string> Dump() {
    var res = new List<string>();
    IntPtr fg = GetForegroundWindow();
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      var t = new StringBuilder(512); GetWindowTextW(h, t, 512);
      var c = new StringBuilder(256); GetClassNameW(h, c, 256);
      uint pid = 0; GetWindowThreadProcessId(h, out pid);
      bool vis = IsWindowVisible(h);
      if (vis || t.Length > 0) {
        string pname = "";
        try { pname = System.Diagnostics.Process.GetProcessById((int)pid).ProcessName; } catch {}
        res.Add(String.Format("hwnd=0x{0:X8} pid={1} proc={2} vis={3} hung={4} fg={5} class={6} title={7}",
          h.ToInt64(), pid, pname, vis, IsHungAppWindow(h), (h==fg), c.ToString(), t.ToString()));
      }
      return true;
    }, IntPtr.Zero);
    return res;
  }
}
'@
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("=== host time " + (Get-Date).ToString('s'))
$lines.AddAll([WinEnum]::Dump())
$lines.Add("")
$lines.Add("=== processes of interest")
Get-Process Eos,ETC_LaunchOffline,ETC_Launch,augment3d_app,augment3d_engine,ETCDoctor,explorer -ErrorAction SilentlyContinue |
  ForEach-Object { $lines.Add(("pid={0} {1} cpu={2} threads={3} ws={4}MB responding={5} title='{6}' start={7}" -f $_.Id,$_.ProcessName,[math]::Round($_.CPU,1),$_.Threads.Count,[math]::Round($_.WorkingSet64/1MB,1),$_.Responding,$_.MainWindowTitle,$_.StartTime)) }
$lines | Set-Content -Encoding UTF8 'C:\eos-ref\windows.txt'
$lines | ForEach-Object { $_ }
& curl.exe -s -T 'C:\eos-ref\windows.txt' 'http://192.168.122.1:8000/vm_windows.txt' | Out-Null
