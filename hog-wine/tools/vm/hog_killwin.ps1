$ErrorActionPreference = 'Continue'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class KW {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowW(string cls, string title);
  [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint msg, IntPtr w, IntPtr l);
}
'@
$KWt = 'Run'
$KWh = [KW]::FindWindowW($null, $KWt)
"FOUND '$KWt' hwnd=0x$('{0:X}' -f $KWh.ToInt64())"
if ($KWh -ne [IntPtr]::Zero) { $KWr = [KW]::PostMessageW($KWh, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero); "WM_CLOSE posted=$KWr" }
Start-Sleep -Milliseconds 500
"STILL=" + ([KW]::FindWindowW($null, $KWt) -ne [IntPtr]::Zero)
