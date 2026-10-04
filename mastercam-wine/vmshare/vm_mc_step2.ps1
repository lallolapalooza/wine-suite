$ErrorActionPreference='Continue'
$U='http://192.168.122.1:8000/'
$Log='C:\vm_mc_step2.log'
function L($m){ Add-Content -Path $Log -Value ("{0} {1}" -f (Get-Date -Format o), $m) -Encoding utf8 }
Set-Content -Path $Log -Value "" -Encoding utf8
function Put { curl.exe -s -T $Log ($U + 'vm_mc_step2.log') | Out-Null }

Add-Type -Namespace W -Name S -MemberDefinition @'
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowW(string cls, string title);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern IntPtr SetWindowLongPtrW(IntPtr h, int idx, IntPtr v);
[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
[DllImport("user32.dll")] public static extern bool RedrawWindow(IntPtr h, IntPtr r, IntPtr rgn, uint flags);
[DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
[StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Rt, B; }
'@

L ("elevated=" + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
$h = [W.S]::FindWindowW('#32770', 'Mastercam Installation Manager')
L ("hwnd=" + $h + " visible=" + [W.S]::IsWindowVisible($h) + " parent=" + [W.S]::GetParent($h))
$r = New-Object W.S+R
[void][W.S]::GetWindowRect($h, [ref]$r)
L ("rect=" + $r.L + "," + $r.T + "," + $r.Rt + "," + $r.B)
if ($h -ne [IntPtr]::Zero) {
  [void][W.S]::ShowWindow($h, 9)      # SW_RESTORE
  [void][W.S]::ShowWindow($h, 5)      # SW_SHOW
  [void][W.S]::SetWindowLongPtrW($h, -16, [IntPtr](0x80000000 -bor 0x10000000))  # WS_VISIBLE|WS_POPUP (best effort)
  [void][W.S]::SetWindowPos($h, [IntPtr]::Zero, 331, 76, 618, 600, 0x0040 -bor 0x0010 -bor 0x0004)  # SHOWWINDOW|NOACTIVATE|NOZORDER
  [void][W.S]::RedrawWindow($h, [IntPtr]::Zero, [IntPtr]::Zero, 0x0400 -bor 0x0100 -bor 0x0080)     # INVALIDATE|UPDATENOW|ALLCHILDREN
  [void][W.S]::SetForegroundWindow($h)
  Start-Sleep -Seconds 2
  L ("visible_after=" + [W.S]::IsWindowVisible($h))
}
# also list every top-level window of setup's pid
$pidSetup = (Get-Process setup -ErrorAction SilentlyContinue | Select-Object -First 1).Id
L ("setup_pid=" + $pidSetup)
L ("cpu=" + (Get-Process setup -ErrorAction SilentlyContinue).CPU)
Get-Process | Where-Object { $_.MainWindowTitle } | ForEach-Object { L ("win: " + $_.ProcessName + " '" + $_.MainWindowTitle + "'") }
L ("freeGB=" + [math]::Round((Get-PSDrive C).Free/1GB, 2))
L 'step2-done'
Put
