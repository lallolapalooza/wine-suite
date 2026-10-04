$ErrorActionPreference='Continue'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$o = New-Object System.Collections.Generic.List[string]
$o.Add("time=" + (Get-Date).ToString('s'))
$procs = @(Get-Process ETC_LaunchOffline,ETC_Launch,Eos,augment3d_app,augment3d_engine -ErrorAction SilentlyContinue)
if ($procs.Count -eq 0) { $o.Add("NO TARGET PROCESS") }
foreach ($p in $procs) {
  $o.Add("=== proc $($p.ProcessName) pid=$($p.Id) mainhwnd=0x$('{0:X}' -f $p.MainWindowHandle.ToInt64())")
  $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $els = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
  $o.Add("elements=" + $els.Count)
  for ($i=0; $i -lt $els.Count; $i++) {
    $e = $els.Item($i)
    try {
      $r = $e.Current.BoundingRectangle
      $o.Add(("  [{0}] type={1} id='{2}' name='{3}' enabled={4} offscreen={5} rect=({6:F0},{7:F0})-({8:F0},{9:F0})" -f `
        $i, $e.Current.ControlType.ProgrammaticName, $e.Current.AutomationId, $e.Current.Name, $e.Current.IsEnabled, $e.Current.IsOffscreen, $r.X, $r.Y, ($r.X+$r.Width), ($r.Y+$r.Height)))
    } catch { $o.Add("  [$i] <err>") }
  }
}
$o | Set-Content -Encoding UTF8 'C:\eos-ref\uia.txt'
$o | ForEach-Object { $_ }
& curl.exe -s -T 'C:\eos-ref\uia.txt' 'http://192.168.122.1:8000/vm_uia.txt' | Out-Null
