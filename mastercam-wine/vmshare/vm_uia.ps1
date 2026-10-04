$ErrorActionPreference='Continue'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$AE = [System.Windows.Automation.AutomationElement]
$TS = [System.Windows.Automation.TreeScope]
$setup = Get-Process setup -ErrorAction SilentlyContinue | Select-Object -First 1
"setup_pid=" + $setup.Id
$root = $AE::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition($AE::ProcessIdProperty, [int]$setup.Id)
$wins = $root.FindAll($TS::Children, $cond)
"windows_found=" + $wins.Count
function Dump($el, $depth) {
  if ($depth -gt 6) { return }
  try {
    $n = $el.Current.Name
    $ct = $el.Current.ControlType.ProgrammaticName
    $r = $el.Current.BoundingRectangle
    $off = $el.Current.IsOffscreen
    $en = $el.Current.IsEnabled
    if (-not $off) {
      "{0}{1} | {2} | en={3} | {4},{5},{6},{7} | {8}" -f ('  ' * $depth), $ct, '', $en, [int]$r.X, [int]$r.Y, [int]$r.Width, [int]$r.Height, $n
    }
    $kids = $el.FindAll($TS::Children, [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($k in $kids) { Dump $k ($depth + 1) }
  } catch {}
}
foreach ($w in $wins) { Dump $w 0 }
"uia-done"
