$ErrorActionPreference='Continue'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
$AE=[System.Windows.Automation.AutomationElement]; $TS=[System.Windows.Automation.TreeScope]
foreach ($p in (Get-Process Mastercam)) {
  "== pid $($p.Id) =="
  $c=New-Object System.Windows.Automation.PropertyCondition($AE::ProcessIdProperty,[int]$p.Id)
  $w=$AE::RootElement.FindAll($TS::Children,$c)
  foreach($x in $w){
    "W: '$($x.Current.Name)' class=$($x.Current.ClassName) rect=$($x.Current.BoundingRectangle)"
    $k=$x.FindAll($TS::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
    $i=0
    foreach($e in $k){ if($i -ge 25){break}; if(-not $e.Current.IsOffscreen){ "   '$($e.Current.Name)' [$($e.Current.ControlType.ProgrammaticName)] rect=$($e.Current.BoundingRectangle)"; $i++ } }
  }
}
