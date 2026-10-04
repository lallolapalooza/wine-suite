# Report SDA windows / processes / logs on Windows; bring SDA to the front.
$exe = "C:\Program Files (x86)\Steinberg\Download Assistant\Steinberg Download Assistant.exe"
if (-not (Get-Process 'Steinberg Download Assistant' -ErrorAction SilentlyContinue)) {
  Start-Process $exe
  Start-Sleep -Seconds 25
}
$sig = @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class W2 {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
'@
Add-Type -TypeDefinition $sig
$global:wins = New-Object System.Collections.ArrayList
$cb = [W2+EnumProc]{
  param($h, $l)
  if ([W2]::IsWindowVisible($h)) {
    $sb = New-Object System.Text.StringBuilder 512
    [void][W2]::GetWindowText($h, $sb, 512)
    $t = $sb.ToString()
    if ($t.Length -gt 0) {
      $cn = New-Object System.Text.StringBuilder 256
      [void][W2]::GetClassName($h, $cn, 256)
      $pr = 0; [void][W2]::GetWindowThreadProcessId($h, [ref]$pr)
      $r = New-Object W2+RECT
      [void][W2]::GetWindowRect($h, [ref]$r)
      [void]$global:wins.Add([pscustomobject]@{H=$h; ProcId=$pr; Class=$cn.ToString(); Title=$t; Rect="$($r.L),$($r.T) $($r.R-$r.L)x$($r.B-$r.T)"})
    }
  }
  return $true
}
[void][W2]::EnumWindows($cb, [IntPtr]::Zero)
"--- windows ---"
$global:wins | Format-Table -AutoSize
foreach ($w in $global:wins) {
  if ($w.Title -match 'Steinberg|Download Assistant') {
    [void][W2]::ShowWindow($w.H, 9); [void][W2]::SetForegroundWindow($w.H)
  }
}
"--- processes ---"
Get-Process | Where-Object {$_.ProcessName -match 'Steinberg|java|aria'} | Select-Object ProcessName,Id,@{n='WS_MB';e={[int]($_.WorkingSet64/1MB)}},Responding | Format-Table -AutoSize
"--- app logs ---"
$ld = "$env:LOCALAPPDATA\Steinberg Download Assistant\logs"
if (Test-Path $ld) { Get-ChildItem $ld | Sort-Object LastWriteTime -Descending | Select-Object -First 2 FullName,Length | Format-Table -Auto }
"--- app dirs ---"
Get-ChildItem "$env:LOCALAPPDATA\Steinberg*","$env:APPDATA\Steinberg*" -ErrorAction SilentlyContinue | Select-Object -Expand FullName
