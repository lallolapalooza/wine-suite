# Guest-side trace of monitor-win32-golden.exe (the offline Processor) on Windows,
# with the 32-bit IAT tracer, launched directly with the launcher's argv.
# Must run ELEVATED (the Hog exes carry a requireAdministrator manifest):
#   tools/vm/elev.sh tools/vm/guest_monitor_hog.ps1
$ErrorActionPreference = 'Continue'
$base = 'http://192.168.122.1:8000'
$dir  = 'C:\hog\apitrace32'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$status = "$dir\win_mon_status.txt"
Start-Transcript -Path $status -Force | Out-Null
"ELEVATED=$([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)"

foreach ($f in 'apihook.dll','apitrace.exe','hog.cfg') {
  curl.exe -s -o (Join-Path $dir $f) "$base/$f"
  "GOT $f $((Get-Item (Join-Path $dir $f)).Length)"
}

# window inventory helper
Add-Type -TypeDefinition @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public class MW {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc f, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsHungAppWindow(IntPtr h);
  public struct RECT { public int L,T,R,B; }
  public static List<string> Dump(uint wantPid) {
    var res = new List<string>();
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      uint pid=0; GetWindowThreadProcessId(h, out pid);
      var t=new StringBuilder(512); GetWindowTextW(h,t,512);
      var c=new StringBuilder(256); GetClassNameW(h,c,256);
      RECT r; GetWindowRect(h, out r);
      string pn=""; try { pn=System.Diagnostics.Process.GetProcessById((int)pid).ProcessName; } catch {}
      if (wantPid==0 || pid==wantPid || t.ToString().Length>0 && (c.ToString().Contains("Monitor")||t.ToString().Contains("Processor"))) {
        res.Add(String.Format("hwnd=0x{0:X8} pid={1} proc={2} vis={3} hung={4} class={5} rect=({6},{7})-({8},{9}) title='{10}'",
          h.ToInt64(), pid, pn, IsWindowVisible(h), IsHungAppWindow(h), c.ToString(), r.L, r.T, r.R, r.B, t.ToString()));
      }
      return true;
    }, IntPtr.Zero);
    return res;
  }
}
'@

$appdir = 'C:\Program Files (x86)\ETC\HogPC'
Get-Process *win32-golden*,GadgetDrvChange,QtWebEngineProcess -ErrorAction SilentlyContinue | ForEach-Object {
  "KILLING $($_.ProcessName) $($_.Id)"; Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2
Remove-Item "$dir\win_mon*.log" -ErrorAction SilentlyContinue

$exe = Join-Path $appdir 'monitor-win32-golden.exe'
$log = "$dir\win_mon.log"
$argstr = '--cfg "{0}" --out "{1}" --timeout 45 -- "{2}" -port=6600 -netnum=1' -f "$dir\hog.cfg", $log, $exe
$p = Start-Process -FilePath "$dir\apitrace.exe" -ArgumentList $argstr -WorkingDirectory $appdir -PassThru
"TRACER_PID=$($p.Id)"
for ($i=0; $i -lt 8; $i++) {
  Start-Sleep -Seconds 5
  $mp = Get-Process monitor-win32-golden -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($mp) { "T=$((($i+1)*5)) monitor_pid=$($mp.Id)"; [MW]::Dump([uint32]$mp.Id) | ForEach-Object { "  $_" } }
  else { "T=$((($i+1)*5)) monitor_gone" }
}
$p.WaitForExit()
"TRACER_RC=$($p.ExitCode)"
Get-Process *win32-golden* -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }

foreach ($f in Get-ChildItem "$dir\win_mon*.log" -ErrorAction SilentlyContinue) {
  "LOG $($f.Name) size=$($f.Length)"
  curl.exe -s -T $f.FullName "$base/$($f.Name)"; "PULLED $($f.Name)"
}
Stop-Transcript | Out-Null
curl.exe -s -T $status "$base/win_mon_status.txt"
"DONE"
