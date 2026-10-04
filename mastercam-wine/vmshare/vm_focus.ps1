$ErrorActionPreference='Continue'
Add-Type -Namespace Z -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int c);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
[StructLayout(LayoutKind.Sequential)] public struct R { public int L,T,Rt,B; }
'@
foreach($p in (Get-Process Mastercam)) {
  if ($p.MainWindowHandle -eq 0) { continue }
  [void][Z.U]::ShowWindow($p.MainWindowHandle,9)
  [void][Z.U]::SetForegroundWindow($p.MainWindowHandle)
  $r=New-Object Z.U+R
  [void][Z.U]::GetWindowRect($p.MainWindowHandle,[ref]$r)
  "hwnd=" + $p.MainWindowHandle + " rect=" + $r.L + "," + $r.T + "," + $r.Rt + "," + $r.B
}
