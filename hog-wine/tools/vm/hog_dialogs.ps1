$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$FW = New-Object System.Collections.Generic.List[string]
$FW.Add("time=" + (Get-Date).ToString('s'))
$FWRoot = [System.Windows.Automation.AutomationElement]::RootElement
$FWCond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Window)
$FWWins = $FWRoot.FindAll([System.Windows.Automation.TreeScope]::Children, $FWCond)
for ($FWj = 0; $FWj -lt $FWWins.Count; $FWj++) {
  $FWw = $FWWins.Item($FWj)
  try {
    $FWr = $FWw.Current.BoundingRectangle
    $FW.Add(("WINDOW name='{0}' class='{1}' pid={2} rect=({3:F0},{4:F0})-({5:F0},{6:F0})" -f $FWw.Current.Name, $FWw.Current.ClassName, $FWw.Current.ProcessId, $FWr.X, $FWr.Y, ($FWr.X+$FWr.Width), ($FWr.Y+$FWr.Height)))
    $FWbcond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button)
    $FWbtns = $FWw.FindAll([System.Windows.Automation.TreeScope]::Descendants, $FWbcond)
    for ($FWk = 0; $FWk -lt $FWbtns.Count; $FWk++) {
      $FWb = $FWbtns.Item($FWk)
      $FWbr = $FWb.Current.BoundingRectangle
      $FW.Add(("    BTN '{0}' rect=({1:F0},{2:F0})-({3:F0},{4:F0}) enabled={5}" -f $FWb.Current.Name, $FWbr.X, $FWbr.Y, ($FWbr.X+$FWbr.Width), ($FWbr.Y+$FWbr.Height), $FWb.Current.IsEnabled))
    }
  } catch { $FW.Add("WINDOW <err>") }
}
$FW | Set-Content -Encoding UTF8 'C:\hog\hog_dialogs.txt'
$FW | ForEach-Object { $_ }
& curl.exe -s -T 'C:\hog\hog_dialogs.txt' 'http://192.168.122.1:8000/vm_hog_dialogs.txt' | Out-Null
