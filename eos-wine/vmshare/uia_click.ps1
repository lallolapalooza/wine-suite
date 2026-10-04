param([string]$AutomationId, [string]$NameLike)
$ErrorActionPreference='Continue'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$procs = @(Get-Process ETC_LaunchOffline,ETC_Launch,Eos,augment3d_app,augment3d_engine -ErrorAction SilentlyContinue)
$done = $false
foreach ($p in $procs) {
  $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $els = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
  for ($i=0; $i -lt $els.Count; $i++) {
    $e = $els.Item($i)
    $id = ''; $nm = ''
    try { $id = $e.Current.AutomationId; $nm = $e.Current.Name } catch { continue }
    if (($AutomationId -and $id -eq $AutomationId) -or ($NameLike -and $nm -like $NameLike)) {
      try {
        $pat = $e.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        $pat.Invoke()
        "INVOKED $($p.ProcessName) id='$id' name='$nm'"
        $done = $true
      } catch {
        $r = $e.Current.BoundingRectangle
        "INVOKE_FAILED id='$id' name='$nm' :: $($_.Exception.Message) rect=$($r.X),$($r.Y),$($r.Width),$($r.Height)"
      }
    }
  }
}
if (-not $done) { "NOT_FOUND id='$AutomationId' name='$NameLike'" }
