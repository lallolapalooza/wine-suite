Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class W5 {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
}
'@
$TOP=[IntPtr](-1); $NOTOP=[IntPtr](-2); $SWP_SHOWWINDOW=0x40; $SWP_NOMOVE=0x2; $SWP_NOSIZE=0x1
foreach ($n in 'Eos','ETC_LaunchOffline','ETC_Launch','augment3d_app') {
  Get-Process $n -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.MainWindowHandle -ne 0) {
      [void][W5]::SetWindowPos($_.MainWindowHandle,$NOTOP,0,0,0,0,($SWP_NOMOVE -bor $SWP_NOSIZE))
      [void][W5]::ShowWindow($_.MainWindowHandle,6)
      "minimised $($_.ProcessName) pid=$($_.Id)"
    }
  }
}
Start-Sleep 1
Get-Process | Where-Object { $_.ProcessName -like 'ETC_EosFamily*' -and $_.MainWindowHandle -ne 0 } | ForEach-Object {
  $h=$_.MainWindowHandle
  [void][W5]::ShowWindow($h,5)
  [void][W5]::SetWindowPos($h,$TOP,0,0,0,0,($SWP_NOMOVE -bor $SWP_NOSIZE -bor $SWP_SHOWWINDOW))
  [void][W5]::SetForegroundWindow($h)
  $r = New-Object W5+RECT; [void][W5]::GetWindowRect($h,[ref]$r)
  "raised installer pid=$($_.Id) '$($_.MainWindowTitle)' rect=($($r.L),$($r.T))-($($r.R),$($r.B))"
}
