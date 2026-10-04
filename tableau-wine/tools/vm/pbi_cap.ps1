param([string]$Phase = 'Pristine', [string]$Pbix = '', [string[]]$Offsets = @(), [string]$Prefix = '')
$ErrorActionPreference = 'Continue'
$out = 'C:\pbiref\cap_' + $Phase
New-Item -ItemType Directory -Force -Path $out | Out-Null
$U = 'http://192.168.122.1:8000/'
$log = "$out\run.log"
Remove-Item $log -ErrorAction SilentlyContinue
function L($m) { $l = "$([DateTime]::Now.ToString('o')) $m"; Add-Content -Path $log -Value $l -Encoding utf8 }
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Namespace PbiCap -Name Native -MemberDefinition '
[DllImport("user32.dll")] public static extern bool GetWindowRect(System.IntPtr hWnd, out RECT lpRect);
[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr h);
[DllImport("user32.dll")] public static extern int GetWindowTextLength(System.IntPtr h);
[DllImport("user32.dll")] public static extern int GetWindowText(System.IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, System.IntPtr l);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h, out uint pid);
public delegate bool EnumWindowsProc(System.IntPtr h, System.IntPtr l);
public struct RECT { public int Left, Top, Right, Bottom; }
' | Out-Null
# keep the display awake for the whole run (ES_CONTINUOUS|ES_DISPLAY_REQUIRED|ES_SYSTEM_REQUIRED)
try { [PbiCap.Native]::SetThreadExecutionState([uint32]2147483651) | Out-Null; L 'keepawake=ok' } catch { L ("keepawake=FAIL " + ($_ | Out-String).Trim()) }

function Snap($path) {
  try {
    $w = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $b = New-Object System.Drawing.Bitmap $w.Width, $w.Height
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.CopyFromScreen($w.X, $w.Y, 0, 0, (New-Object System.Drawing.Size $w.Width, $w.Height))
    $b.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $b.Dispose()
    return $true
  } catch { L ("CAPTURE-ERROR " + ($_ | Out-String).Trim()); return $false }
}

function TitleList { ((Get-Process | Where-Object { $_.MainWindowTitle } | ForEach-Object { "$($_.ProcessName)[$($_.Id)]=`"$($_.MainWindowTitle)`"" }) -join ' | ') }

function AllWindows {
  $script:winrows = @()
  try {
    $cb = [PbiCap.Native+EnumWindowsProc] {
      param($h, $l)
      if ([PbiCap.Native]::IsWindowVisible($h)) {
        $len = [PbiCap.Native]::GetWindowTextLength($h)
        if ($len -gt 0) {
          $sb = New-Object System.Text.StringBuilder ($len + 2)
          [PbiCap.Native]::GetWindowText($h, $sb, $sb.Capacity) | Out-Null
          $opid = 0
          [PbiCap.Native]::GetWindowThreadProcessId($h, [ref]$opid) | Out-Null
          $r = New-Object PbiCap.Native+RECT
          [PbiCap.Native]::GetWindowRect($h, [ref]$r) | Out-Null
          $pn = (Get-Process -Id $opid -ErrorAction SilentlyContinue).ProcessName
          $script:winrows += "$pn[$opid] `"$($sb.ToString())`" $($r.Right - $r.Left)x$($r.Bottom - $r.Top)@$($r.Left),$($r.Top)"
        }
      }
      $true
    }
    [PbiCap.Native]::EnumWindows($cb, [System.IntPtr]::Zero) | Out-Null
  } catch { L ("ENUM-ERROR " + ($_ | Out-String).Trim()) }
  return ($script:winrows -join ' ;; ')
}

function WinState {
  $r = @()
  foreach ($p in @(Get-Process PBIDesktop -ErrorAction SilentlyContinue)) {
    $h = $p.MainWindowHandle
    $sz = 'none'
    if ($h -ne 0) {
      $rect = New-Object PbiCap.Native+RECT
      [PbiCap.Native]::GetWindowRect($h, [ref]$rect) | Out-Null
      $sz = "$($rect.Right - $rect.Left)x$($rect.Bottom - $rect.Top)@$($rect.Left),$($rect.Top)"
    }
    $r += "$($p.Id):`"$($p.MainWindowTitle)`":$sz"
  }
  $r -join ' ; '
}

function Phase {
  $s = WinState
  if (-not $s) { return 'nowin' }
  $big = @(Get-Process PBIDesktop -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Where-Object {
      $rect = New-Object PbiCap.Native+RECT; [PbiCap.Native]::GetWindowRect($_.MainWindowHandle, [ref]$rect) | Out-Null
      ($rect.Right - $rect.Left) -gt 900 -and ($rect.Bottom - $rect.Top) -gt 600
    })
  if ($big.Count -gt 0) { return 'main' } else { return 'small' }
}

$exe = 'C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe'
L ("PHASE=" + $Phase + " pbix=" + $Pbix)
L ("exe_exists=" + (Test-Path $exe))
L ("pre_titles: " + (TitleList))
L ("pre_allwindows: " + (AllWindows))
L ("pre_pbi_procs: " + (@(Get-Process PBIDesktop -ErrorAction SilentlyContinue).Count))

if ((Get-Process PBIDesktop -ErrorAction SilentlyContinue) -and $Phase -eq 'Pbix') {
  L 'closing existing PBIDesktop before the pbix run'
  foreach ($p in @(Get-Process PBIDesktop -ErrorAction SilentlyContinue)) { $p.CloseMainWindow() | Out-Null }
  Start-Sleep -Seconds 5
  foreach ($p in @(Get-Process PBIDesktop -ErrorAction SilentlyContinue)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Seconds 3
}

if ($Phase -eq 'Pbix') { $offs = @(15, 30, 45, 60, 90); $pfx = 'pbix_run1_t' }
else { $offs = @(2, 4, 6, 10, 30, 60, 120); $pfx = 'pbi_run1_t' }
if ($Offsets.Count -gt 0) { $offs = @($Offsets | ForEach-Object { [int]$_ }) }
if ($Prefix) { $pfx = $Prefix }

if (-not $offs -or $offs.Count -eq 0) { L 'ERROR no offsets' }
L ("offsets=" + ($offs -join ',') + " prefix=" + $pfx)
$t0 = [DateTime]::Now
L ("T0_local=" + $t0.ToString('o') + " T0_utc=" + $t0.ToUniversalTime().ToString('o'))
if ($Pbix) {
  L ("launch_cmd=" + $exe + ' "' + $Pbix + '"')
  $proc = Start-Process -FilePath $exe -ArgumentList "`"$Pbix`"" -PassThru
} else {
  L ("launch_cmd=" + $exe)
  $proc = Start-Process -FilePath $exe -PassThru
}
L ("launched_pid=" + $proc.Id)

$prevState = ''
$firstWin = $null
$mainWin = $null
foreach ($o in $offs) {
  while (([DateTime]::Now - $t0).TotalSeconds -lt $o) {
    $st = WinState
    if ($st -ne $prevState) {
      L ("winstate t=" + [Math]::Round(([DateTime]::Now - $t0).TotalSeconds, 2) + " phase=" + (Phase) + " " + $st + " || all=" + (AllWindows))
      $prevState = $st
    }
    if (-not $firstWin) {
      $p = @(Get-Process PBIDesktop -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 })
      if ($p.Count -gt 0) {
        $firstWin = ([DateTime]::Now - $t0).TotalSeconds
        L ("FIRST-WINDOW t=" + [Math]::Round($firstWin, 2) + " title=`"$($p[0].MainWindowTitle)`" state=" + (WinState))
      }
    }
    if (-not $mainWin -and $firstWin) {
      if ((Phase) -eq 'main') {
        $big = @(Get-Process PBIDesktop -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Where-Object {
            $rect = New-Object PbiCap.Native+RECT; [PbiCap.Native]::GetWindowRect($_.MainWindowHandle, [ref]$rect) | Out-Null
            ($rect.Right - $rect.Left) -gt 900 -and ($rect.Bottom - $rect.Top) -gt 600
          })
        if ($big.Count -gt 0) {
          $mainWin = ([DateTime]::Now - $t0).TotalSeconds
          L ("MAIN-WINDOW t=" + [Math]::Round($mainWin, 2) + " title=`"$($big[0].MainWindowTitle)`"")
        }
      }
    }
    Start-Sleep -Milliseconds 120
  }
  $el = ([DateTime]::Now - $t0).TotalSeconds
  $ph = Phase
  $f = "$out\$pfx$o.png"
  $ok = Snap $f
  L ("T=$o actual=" + [Math]::Round($el, 2) + " guess=" + $ph + " capture=$ok titles=" + (TitleList))
  L ("T=$o allwindows=" + (AllWindows))
  L ("T=$o winstate=" + (WinState))
  if ($ok) { curl.exe -s -T $f ($U + "$pfx$o.png") | Out-Null }
}
L ("final_winstate " + (WinState))
L ("final_titles: " + (TitleList))
L ("final_allwindows: " + (AllWindows))
L ("pbi_procs: " + (@(Get-Process PBIDesktop -ErrorAction SilentlyContinue | Select-Object Id, MainWindowTitle, @{n='MB';e={[int]($_.WorkingSet64/1MB)}} | Out-String -Width 250)))
$s = "$env:LOCALAPPDATA\Microsoft\Power BI Desktop\UserInterface\Settings.xml"
L ("settings_exists=" + (Test-Path $s) + " path=" + $s)
if (Test-Path $s) {
  $sn = 'guest_pbi_settings_' + $Phase + '.xml'
  curl.exe -s -T $s ($U + $sn) | Out-Null
  Copy-Item $s "$out\Settings.xml" -Force -ErrorAction SilentlyContinue
  L ("settings_bytes=" + (Get-Item $s).Length + " uploaded=" + $sn)
}
$lu = "$env:LOCALAPPDATA\Microsoft\Power BI Desktop"
foreach ($sub in @('UserInterface', 'UserInterface\Settings.xml')) {
  $p = Join-Path $lu $sub
  L ("localappdata_probe $p exists=" + (Test-Path $p))
}
L 'DONE'
curl.exe -s -T $log ($U + "guest_pbi_cap_$Phase.log") | Out-Null
