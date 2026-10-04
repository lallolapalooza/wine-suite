$ErrorActionPreference = 'Continue'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class W2 {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern IntPtr GetDesktopWindow();
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
}
'@
$o = New-Object System.Collections.Generic.List[string]
$o.Add("time=" + (Get-Date).ToString('s'))
$o.Add("screen=" + [W2]::GetSystemMetrics(0) + "x" + [W2]::GetSystemMetrics(1))
$o.Add("fg=0x{0:X}" -f [W2]::GetForegroundWindow().ToInt64())
function Dump($h, $tag) {
  $r = New-Object W2+RECT
  $ok = [W2]::GetWindowRect($h, [ref]$r)
  return ("{0} hwnd=0x{1:X} rect=({2},{3})-({4},{5}) {6}x{7} visible={8} iconic={9} zoomed={10} style=0x{11:X}" -f `
     $tag, $h.ToInt64(), $r.L, $r.T, $r.R, $r.B, ($r.R-$r.L), ($r.B-$r.T), `
     [W2]::IsWindowVisible($h), [W2]::IsIconic($h), [W2]::IsZoomed($h), [W2]::GetWindowLong($h,-16))
}
foreach ($p in (Get-Process | Where-Object { $_.MainWindowHandle -ne 0 })) {
  $o.Add((Dump $p.MainWindowHandle ("proc:" + $p.ProcessName + ":" + $p.Id + ":" + $p.MainWindowTitle)))
}
# restore + foreground the shell
$sh = Get-Process ETC_LaunchOffline -ErrorAction SilentlyContinue
if ($sh) {
  foreach ($p in $sh) {
    $h = $p.MainWindowHandle
    if ($h -ne 0) {
      [void][W2]::ShowWindow($h, 9)   # SW_RESTORE
      [void][W2]::ShowWindow($h, 5)   # SW_SHOW
      [void][W2]::SetForegroundWindow($h)
      $o.Add("after-restore: " + (Dump $h "shell"))
    }
  }
}
$o | Set-Content -Encoding UTF8 'C:\eos-ref\winprobe.txt'
$o | ForEach-Object { $_ }
& curl.exe -s -T 'C:\eos-ref\winprobe.txt' 'http://192.168.122.1:8000/vm_winprobe.txt' | Out-Null
