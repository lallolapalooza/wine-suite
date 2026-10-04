# Enumerate top-level windows; bring the Steinberg/SDA one to the front.
$sig = @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class Win {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
'@
Add-Type -TypeDefinition $sig
$found = @()
$cb = [Win+EnumProc]{
  param($h, $l)
  if ([Win]::IsWindowVisible($h)) {
    $sb = New-Object System.Text.StringBuilder 512
    [void][Win]::GetWindowText($h, $sb, 512)
    $t = $sb.ToString()
    if ($t.Length -gt 0) {
      $cn = New-Object System.Text.StringBuilder 256
      [void][Win]::GetClassName($h, $cn, 256)
      $procId = 0; [void][Win]::GetWindowThreadProcessId($h, [ref]$procId)
      $r = New-Object Win+RECT
      [void][Win]::GetWindowRect($h, [ref]$r)
      $script:found += [pscustomobject]@{H=$h; ProcId=$procId; Class=$cn.ToString(); Title=$t; Rect="$($r.L),$($r.T) $($r.R - $r.L)x$($r.B - $r.T)"}
    }
  }
  return $true
}
[void][Win]::EnumWindows($cb, [IntPtr]::Zero)
$found | Format-Table -AutoSize
foreach ($w in $found) {
  if ($w.Title -match 'Steinberg|Download Assistant|Setup') {
    Write-Output ("FOREGROUND: " + $w.Title)
    [void][Win]::ShowWindow($w.H, 9)   # SW_RESTORE
    [void][Win]::SetForegroundWindow($w.H)
  }
}
