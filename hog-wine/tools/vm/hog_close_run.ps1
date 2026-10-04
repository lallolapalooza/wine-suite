$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$CR = New-Object System.Collections.Generic.List[string]
$CRRoot = [System.Windows.Automation.AutomationElement]::RootElement
$CRcond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, 'Run')
$CRwin = $CRRoot.FindFirst([System.Windows.Automation.TreeScope]::Children, $CRcond)
if ($CRwin -eq $null) { $CR.Add("NO RUN WINDOW") } else {
  $CR.Add("RUN win pid=" + $CRwin.Current.ProcessId)
  $CRbc = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
  $CRbtns = $CRwin.FindAll([System.Windows.Automation.TreeScope]::Descendants, $CRbc)
  for ($CRi = 0; $CRi -lt $CRbtns.Count; $CRi++) {
    $CRb = $CRbtns.Item($CRi)
    $CRr = $CRb.Current.BoundingRectangle
    $CR.Add(("BTN '{0}' rect=({1:F0},{2:F0})-({3:F0},{4:F0})" -f $CRb.Current.Name, $CRr.X, $CRr.Y, ($CRr.X+$CRr.Width), ($CRr.Y+$CRr.Height)))
    if ($CRb.Current.Name -match 'Cancel') {
      try { $CRb.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); $CR.Add("INVOKED Cancel") } catch { $CR.Add("invoke failed: $_") }
    }
  }
}
"CR_result:"; $CR | ForEach-Object { $_ }
