$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$NS = New-Object System.Collections.Generic.List[string]
$NSRoot = [System.Windows.Automation.AutomationElement]::RootElement
function Find-ByName($NSname) {
  $NScond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $NSname)
  return $NSRoot.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $NScond)
}
$NS.Add("looking for 'Hog Start' window / 'New Show' button")
$NSwin = Find-ByName 'Hog Start'
if ($NSwin -ne $null) { $NS.Add("win found pid=" + $NSwin.Current.ProcessId + " offscreen=" + $NSwin.Current.IsOffscreen) } else { $NS.Add("no Hog Start window element") }
$NSbtn = Find-ByName 'New Show'
if ($NSbtn -ne $null) {
  $NSr = $NSbtn.Current.BoundingRectangle
  $NS.Add(("button 'New Show' offscreen={0} enabled={1} rect=({2:F0},{3:F0})-({4:F0},{5:F0})" -f $NSbtn.Current.IsOffscreen, $NSbtn.Current.IsEnabled, $NSr.X, $NSr.Y, ($NSr.X+$NSr.Width), ($NSr.Y+$NSr.Height)))
  try {
    $NSpat = $NSbtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $NSpat.Invoke()
    $NS.Add("INVOKED New Show")
  } catch { $NS.Add("invoke failed: $_") }
} else { $NS.Add("no 'New Show' button element") }
Start-Sleep -Seconds 6
$NS.Add("--- after ---")
$NSRoot2 = [System.Windows.Automation.AutomationElement]::RootElement
$NSwcond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window)
$NSwins = $NSRoot2.FindAll([System.Windows.Automation.TreeScope]::Children, $NSwcond)
for ($NSi = 0; $NSi -lt $NSwins.Count; $NSi++) {
  $NSw = $NSwins.Item($NSi)
  $NSr2 = $NSw.Current.BoundingRectangle
  $NS.Add(("WINDOW '{0}' class='{1}' pid={2} rect=({3:F0},{4:F0})-({5:F0},{6:F0})" -f $NSw.Current.Name, $NSw.Current.ClassName, $NSw.Current.ProcessId, $NSr2.X, $NSr2.Y, ($NSr2.X+$NSr2.Width), ($NSr2.Y+$NSr2.Height)))
}
Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'golden' } | ForEach-Object { $NS.Add(("PROC {0} pid={1} title='{2}'" -f $_.ProcessName, $_.Id, $_.MainWindowTitle)) }
$NS | Set-Content -Encoding UTF8 'C:\hog\hog_newshow.txt'
$NS | ForEach-Object { $_ }
& curl.exe -s -T 'C:\hog\hog_newshow.txt' 'http://192.168.122.1:8000/vm_hog_newshow.txt' | Out-Null
