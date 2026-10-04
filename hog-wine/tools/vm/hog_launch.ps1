$ErrorActionPreference = 'Continue'
$root = 'C:\Program Files (x86)\ETC\HogPC'
$ExeName = 'launcher-win32-golden.exe'   # <-- entry point under test
$WaitSec = 25

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
      string pname = "";
      try { pname = System.Diagnostics.Process.GetProcessById((int)pid).ProcessName; } catch {}
      if (vis || t.Length > 0) {
        res.Add(String.Format("hwnd=0x{0:X8} pid={1} proc={2} vis={3} hung={4} fg={5} class={6} title={7}",
          h.ToInt64(), pid, pname, vis, IsHungAppWindow(h), (h==fg), c.ToString(), t.ToString()));
      }
      return true;
    }, IntPtr.Zero);
    return res;
  }
}
'@

$L = New-Object System.Collections.Generic.List[string]
$L.Add("=== hog launch: $ExeName  at $(Get-Date -Format s)")
$L.Add("FREE_GB={0:N3}" -f ((Get-PSDrive C).Free/1GB))

# kill any previous Hog instance
Get-Process -EA SilentlyContinue | Where-Object { $_.Path -like "$root*" } | ForEach-Object { $L.Add("KILL $($_.ProcessName) pid=$($_.Id)"); Stop-Process -Id $_.Id -Force }
Start-Sleep -Seconds 3

$exe = Join-Path $root $ExeName
$L.Add("EXE_EXISTS=$(Test-Path $exe)")
$L.Add("=== launching ===")
try { $p = Start-Process -FilePath $exe -WorkingDirectory $root -PassThru; $L.Add("PID=$($p.Id) start=$($p.StartTime.ToString('s'))") }
catch { $L.Add("LAUNCH_ERROR $_") }

Start-Sleep -Seconds $WaitSec

$L.Add("=== windows after ${WaitSec}s ===")
$L.AddRange([WinEnum]::Dump())
$L.Add("=== processes under install root / named golden ===")
Get-Process -EA SilentlyContinue | Where-Object { ($_.Path -like "$root*") -or ($_.ProcessName -match 'golden|hog|launcher|desktop|server|monitor|QtWebEngine') } |
  ForEach-Object { $L.Add(("proc pid={0} {1} cpu={2} ws={3}MB resp={4} title='{5}' path={6} started={7}" -f $_.Id,$_.ProcessName,[math]::Round($_.CPU,1),[math]::Round($_.WorkingSet64/1MB,1),$_.Responding,$_.MainWindowTitle,$_.Path,$_.StartTime)) }
$L.Add("=== cpu/gpu ===")
$L.Add("wmic_video=" + ((Get-CimInstance Win32_VideoController -EA SilentlyContinue | ForEach-Object { $_.Name + '|' + $_.DriverVersion }) -join ' ; '))

$L.Add("FREE_AFTER_GB={0:N3}" -f ((Get-PSDrive C).Free/1GB))
$L | Set-Content -Encoding UTF8 "C:\hog\hog_launch_$ExeName.txt"
$L | ForEach-Object { $_ }
& curl.exe -s -T "C:\hog\hog_launch_$ExeName.txt" "http://192.168.122.1:8000/vm_hog_launch.txt" | Out-Null
