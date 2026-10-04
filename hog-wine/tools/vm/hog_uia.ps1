$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$HU = New-Object System.Collections.Generic.List[string]
$HU.Add("time=" + (Get-Date).ToString('s'))
$targets = @(Get-Process -EA SilentlyContinue | Where-Object { $_.ProcessName -match 'golden|Hog|QtWebEngine' })
if ($targets.Count -eq 0) { $HU.Add("NO TARGET PROCESS") }
foreach ($HP in $targets) {
  $HU.Add("=== proc $($HP.ProcessName) pid=$($HP.Id) mainhwnd=0x$('{0:X}' -f $HP.MainWindowHandle.ToInt64()) title='$($HP.MainWindowTitle)'")
  $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $HP.Id)
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $els = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
  $HU.Add("elements=" + $els.Count)
  for ($i = 0; $i -lt $els.Count; $i++) {
    $e = $els.Item($i)
    try {
      $r = $e.Current.BoundingRectangle
      $HU.Add(("  [{0}] type={1} id='{2}' name='{3}' enabled={4} offscreen={5} rect=({6:F0},{7:F0})-({8:F0},{9:F0})" -f `
        $i, $e.Current.ControlType.ProgrammaticName, $e.Current.AutomationId, $e.Current.Name, $e.Current.IsEnabled, $e.Current.IsOffscreen, $r.X, $r.Y, ($r.X + $r.Width), ($r.Y + $r.Height)))
    } catch { $HU.Add("  [$i] <err>") }
  }
}
$HU | Set-Content -Encoding UTF8 'C:\hog\hog_uia.txt'
$HU | ForEach-Object { $_ }
& curl.exe -s -T 'C:\hog\hog_uia.txt' 'http://192.168.122.1:8000/vm_hog_uia.txt' | Out-Null
