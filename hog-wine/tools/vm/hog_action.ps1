$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$HA = New-Object System.Collections.Generic.List[string]
$HA.Add("time=" + (Get-Date).ToString('s'))
$HARoot = [System.Windows.Automation.AutomationElement]::RootElement
$HAcond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, 'Hog Start')
$HAwin = $HARoot.FindFirst([System.Windows.Automation.TreeScope]::Children, $HAcond)
if ($HAwin -eq $null) { $HA.Add("NO 'Hog Start' WINDOW"); $HA | ForEach-Object { $_ }; exit }
$HA.Add("win found pid=" + $HAwin.Current.ProcessId)
try { $HAwin.SetFocus(); $HA.Add("SetFocus ok") } catch { $HA.Add("SetFocus failed: $_") }
Start-Sleep -Milliseconds 700
$HA.Add("FGWIN=" + ([System.Windows.Automation.AutomationElement]::FocusedElement.Current.Name))
$HA.Add("--- buttons ---")
$HAbc = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
$HAbtns = $HAwin.FindAll([System.Windows.Automation.TreeScope]::Descendants, $HAbc)
for ($HAi = 0; $HAi -lt $HAbtns.Count; $HAi++) {
  $HAb = $HAbtns.Item($HAi)
  $HAr = $HAb.Current.BoundingRectangle
  $HAname = ($HAb.Current.Name -replace "`n", ' ')
  $HA.Add(("BTN [{0}] '{1}' rect=({2:F0},{3:F0})-({4:F0},{5:F0}) enabled={6}" -f $HAi, $HAname, $HAr.X, $HAr.Y, ($HAr.X+$HAr.Width), ($HAr.Y+$HAr.Height), $HAb.Current.IsEnabled))
}
$HA | Set-Content -Encoding UTF8 'C:\hog\hog_action.txt'
$HA | ForEach-Object { $_ }
& curl.exe -s -T 'C:\hog\hog_action.txt' 'http://192.168.122.1:8000/vm_hog_action.txt' | Out-Null
