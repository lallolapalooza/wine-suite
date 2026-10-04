param([string]$NameLike='*')
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class W4 {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
}
'@
$HWND_TOPMOST=[IntPtr](-1); $SWP_SHOWWINDOW=0x40; $SWP_NOMOVE=0x2; $SWP_NOSIZE=0x1
foreach ($p in (Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and ($_.ProcessName -like $NameLike -or $_.MainWindowTitle -like $NameLike) })) {
  $h=$p.MainWindowHandle
  [void][W4]::ShowWindow($h,5)
  [void][W4]::SetWindowPos($h,$HWND_TOPMOST,0,0,0,0,($SWP_NOMOVE -bor $SWP_NOSIZE -bor $SWP_SHOWWINDOW))
  [void][W4]::SetForegroundWindow($h)
  $r = New-Object W4+RECT; [void][W4]::GetWindowRect($h,[ref]$r)
  "raised $($p.ProcessName) '$($p.MainWindowTitle)' hwnd=0x$('{0:X}' -f $h.ToInt64()) rect=($($r.L),$($r.T))-($($r.R),$($r.B))"
}
