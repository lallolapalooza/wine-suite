param([string]$ProcName="capcut_setup",[int]$X=-2147483648,[int]$Y=-2147483648)
Add-Type -Namespace WM -Name Api -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left,Top,Right,Bottom; }
'@
Get-Process cmd,powershell,WindowsTerminal,OpenConsole -ErrorAction SilentlyContinue | ForEach-Object {
  if ($_.MainWindowHandle -ne 0 -and $_.Name -ne $ProcName) { [void][WM.Api]::ShowWindow($_.MainWindowHandle, 6) }
}
$p = Get-Process $ProcName -ErrorAction SilentlyContinue | Where-Object {$_.MainWindowHandle -ne 0} | Select-Object -First 1
if ($null -eq $p) { Write-Output "NO_PROC $ProcName"; exit 1 }
$h = $p.MainWindowHandle
$r = New-Object WM.Api+RECT
[void][WM.Api]::GetWindowRect($h, [ref]$r)
Write-Output ("RECT before: {0},{1} {2}x{3}" -f $r.Left,$r.Top,($r.Right-$r.Left),($r.Bottom-$r.Top))
[void][WM.Api]::ShowWindow($h, 9)   # SW_RESTORE
$flags = 0x43   # SWP_NOSIZE|SWP_NOMOVE|SWP_SHOWWINDOW|HWND_TOP
if ($X -ne -2147483648) { $flags = 0x40 }  # allow move+size only if explicit coords given
[void][WM.Api]::SetWindowPos($h, [IntPtr]::Zero, $X, $Y, 0, 0, $flags)
[void][WM.Api]::SetForegroundWindow($h)
[void][WM.Api]::GetWindowRect($h, [ref]$r)
Write-Output ("RECT after: {0},{1} {2}x{3}" -f $r.Left,$r.Top,($r.Right-$r.Left),($r.Bottom-$r.Top))
Write-Output "OK"
