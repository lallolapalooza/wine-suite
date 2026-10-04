param(
  [string]$Tag = 'mature',
  [string]$Pbix = 'C:\pbiref\IbeRevUATEpamPerformance.pbix',
  [string]$Offsets = '10,20,30,45,60,90,120,150,180,240',
  # -CdpPort 9222 makes the app's WebView2 (the report canvas is a Chromium page) open a local
  # DevTools endpoint, so the *text of the canvas* can be read: the canvas exposes nothing to a
  # same-session UIA client (see UiaText below), so CDP is the only textual window into it.
  # 0 = off, i.e. the exact pure-Windows launch.
  [int]$CdpPort = 0
)
# Measures, on the Windows guest: (a) the view timeline of one .pbix open
# (window states with timestamps + screen frames + UI Automation names), and
# (b) the user-state files, before the launch and after each sample.
# Everything is pushed to the host over the 192.168.122.1:8000 file channel as it is taken,
# so the run can be followed from the host without further guest commands.
$ErrorActionPreference = 'Continue'
$U = 'http://192.168.122.1:8000/'
$B = "$env:LOCALAPPDATA\Microsoft\Power BI Desktop"
$R = "$env:APPDATA\Microsoft\Power BI Desktop"
$out = "C:\pbiref\viewref_$Tag"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$log = "$out\run.log"
Remove-Item $log -ErrorAction SilentlyContinue
function L($m) { Add-Content -Path $log -Value ("$([DateTime]::Now.ToString('o')) $m") -Encoding utf8 }
function Push($f, $n) { if (Test-Path $f) { curl.exe -s -T $f ($U + $n) | Out-Null } }
function PushLog { curl.exe -s -T $log ($U + "wv_${Tag}_run.log") | Out-Null }

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -Namespace PbiVR -Name N -MemberDefinition '
[DllImport("user32.dll")] public static extern bool GetWindowRect(System.IntPtr hWnd, out RECT lpRect);
[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr h);
[DllImport("user32.dll")] public static extern int GetWindowTextLength(System.IntPtr h);
[DllImport("user32.dll")] public static extern int GetWindowText(System.IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, System.IntPtr l);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int cmd);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr h);
public delegate bool EnumWindowsProc(System.IntPtr h, System.IntPtr l);
public struct RECT { public int Left, Top, Right, Bottom; }
' | Out-Null
try { [PbiVR.N]::SetThreadExecutionState([uint32]2147483651) | Out-Null; L 'keepawake=ok' } catch { L "keepawake=FAIL" }

function Snap($path) {
  try {
    $w = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $b = New-Object System.Drawing.Bitmap $w.Width, $w.Height
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.CopyFromScreen($w.X, $w.Y, 0, 0, (New-Object System.Drawing.Size $w.Width, $w.Height))
    $b.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $b.Dispose(); return $true
  } catch { L ("CAPTURE-ERROR " + ($_ | Out-String).Trim()); return $false }
}

# The guest's poller console (Windows Terminal / cmd) sits on top of the app after any
# vmcmd call and would own the pixels of every frame.  Minimise every foreign console
# window and raise the largest Power BI window before each capture.
function FocusApp {
  $script:bestA = 0; $script:bestH = [System.IntPtr]::Zero
  try {
    $cb = [PbiVR.N+EnumWindowsProc] {
      param($h, $l)
      if ([PbiVR.N]::IsWindowVisible($h)) {
        $opid = 0
        [PbiVR.N]::GetWindowThreadProcessId($h, [ref]$opid) | Out-Null
        $pn = (Get-Process -Id $opid -ErrorAction SilentlyContinue).ProcessName
        if ($pn -match '^(WindowsTerminal|cmd|powershell|conhost|OpenConsole)$') { [PbiVR.N]::ShowWindow($h, 6) | Out-Null }
        elseif ($pn -eq 'PBIDesktop') {
          $r = New-Object PbiVR.N+RECT
          [PbiVR.N]::GetWindowRect($h, [ref]$r) | Out-Null
          $a = ($r.Right - $r.Left) * ($r.Bottom - $r.Top)
          if ($a -gt $script:bestA) { $script:bestA = $a; $script:bestH = $h }
        }
      }
      $true
    }
    [PbiVR.N]::EnumWindows($cb, [System.IntPtr]::Zero) | Out-Null
    if ($script:bestH -ne [System.IntPtr]::Zero) { [PbiVR.N]::SetForegroundWindow($script:bestH) | Out-Null }
  } catch { L ("FOCUS-ERROR " + ($_ | Out-String).Trim()) }
}

function RestoreConsoles {
  try {
    $cb = [PbiVR.N+EnumWindowsProc] {
      param($h, $l)
      $opid = 0
      [PbiVR.N]::GetWindowThreadProcessId($h, [ref]$opid) | Out-Null
      $pn = (Get-Process -Id $opid -ErrorAction SilentlyContinue).ProcessName
      if ($pn -match '^(WindowsTerminal|cmd|powershell|conhost|OpenConsole)$') { [PbiVR.N]::ShowWindow($h, 9) | Out-Null }
      $true
    }
    [PbiVR.N]::EnumWindows($cb, [System.IntPtr]::Zero) | Out-Null
  } catch {}
}

function AllWindows {
  $script:rows = @()
  try {
    $cb = [PbiVR.N+EnumWindowsProc] {
      param($h, $l)
      if ([PbiVR.N]::IsWindowVisible($h)) {
        $len = [PbiVR.N]::GetWindowTextLength($h)
        if ($len -gt 0) {
          $sb = New-Object System.Text.StringBuilder ($len + 2)
          [PbiVR.N]::GetWindowText($h, $sb, $sb.Capacity) | Out-Null
          $opid = 0
          [PbiVR.N]::GetWindowThreadProcessId($h, [ref]$opid) | Out-Null
          $r = New-Object PbiVR.N+RECT
          [PbiVR.N]::GetWindowRect($h, [ref]$r) | Out-Null
          $pn = (Get-Process -Id $opid -ErrorAction SilentlyContinue).ProcessName
          $script:rows += "$pn[$opid] `"$($sb.ToString())`" $($r.Right - $r.Left)x$($r.Bottom - $r.Top)@$($r.Left),$($r.Top)"
        }
      }
      $true
    }
    [PbiVR.N]::EnumWindows($cb, [System.IntPtr]::Zero) | Out-Null
  } catch { L ("ENUM-ERROR " + ($_ | Out-String).Trim()) }
  return ($script:rows -join ' ;; ')
}

function WinState {
  $r = @()
  foreach ($p in @(Get-Process PBIDesktop -ErrorAction SilentlyContinue)) {
    $h = $p.MainWindowHandle
    $sz = 'none'
    if ($h -ne 0) {
      $rect = New-Object PbiVR.N+RECT
      [PbiVR.N]::GetWindowRect($h, [ref]$rect) | Out-Null
      $sz = "$($rect.Right - $rect.Left)x$($rect.Bottom - $rect.Top)@$($rect.Left),$($rect.Top)"
    }
    $r += "$($p.Id):`"$($p.MainWindowTitle)`":$sz"
  }
  return ($r -join ' ; ')
}

# UI Automation: the app's accessible names.  Descendants traversal of the real app measured
# ~20 s per call and returned nothing beyond "...[Window] | ...[TitleBar] | System Menu Bar[MenuBar]"
# (Power BI's chrome and the WebView2/Minerva canvas are not exposed as UIA names to a
# same-session client), so the children scope is used: it is the honest cheap probe.
function UiaText {
  $acc = New-Object System.Collections.Generic.List[string]
  try {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    foreach ($p in @(Get-Process PBIDesktop -ErrorAction SilentlyContinue)) {
      try {
        $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
        $els = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
        foreach ($e in $els) {
          try {
            $n = $e.Current.Name
            if ($n -and $n.Trim().Length -gt 0) {
              $t = $e.Current.ControlType.ProgrammaticName -replace 'ControlType\.', ''
              $acc.Add(($n.Trim() + "[" + $t + "]"))
            }
          } catch {}
        }
      } catch { $acc.Add("UIA-PIDERR:" + $p.Id) }
    }
  } catch { $acc.Add("UIA-ERR:" + ($_ | Out-String).Trim()) }
  $u = $acc | Select-Object -Unique
  $s = ($u -join ' | ')
  if ($s.Length -gt 6000) { $s = $s.Substring(0, 6000) + ' ...TRUNC' }
  return $s
}

# ---- CDP (only when -CdpPort is given) ----------------------------------------------------
# One DevTools call over a fresh websocket: send the JSON, read frames until EndOfMessage.
function CdpCall($wsUrl, $json) {
  $ws = New-Object System.Net.WebSockets.ClientWebSocket
  $ct = [System.Threading.CancellationToken]::None
  try {
    if (-not $ws.ConnectAsync([Uri]$wsUrl, $ct).Wait(8000)) { return 'CDP-CONNECT-TIMEOUT' }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $seg = New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$bytes)
    if (-not $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait(8000)) { return 'CDP-SEND-TIMEOUT' }
    $ms = New-Object System.IO.MemoryStream
    $buf = New-Object byte[] 262144
    do {
      $rseg = New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$buf)
      $t = $ws.ReceiveAsync($rseg, $ct)
      if (-not $t.Wait(20000)) { return 'CDP-RECV-TIMEOUT' }
      $r = $t.Result
      $ms.Write($buf, 0, $r.Count)
    } while (-not $r.EndOfMessage)
    return [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
  } catch { return ('CDP-ERROR ' + ($_ | Out-String).Trim()) }
  finally { try { $ws.Dispose() } catch {} }
}

# innerText of the top document and of every readable frame, plus a search of the raw HTML for
# the error overlay's own wording.  That is the transcription of the canvas.
$CdpExpr = @'
(function(){var out=[];function walk(w,d){try{var t=(w.document&&w.document.body)?w.document.body.innerText:'';out.push('[frame depth='+d+' url='+String(w.location.href).substring(0,140)+']\n'+t);}catch(e){out.push('[frame depth='+d+' UNREADABLE '+e.name+']');}try{for(var i=0;i<w.frames.length;i++){walk(w.frames[i],d+1);}}catch(e){}}
walk(window,0);
var extra=[];
try{var all=document.documentElement.outerHTML;extra.push('[top-html-len='+all.length+']');
var pats=['Error fetching data','See details','error overlay','DataExtensionError'];
for(var k=0;k<pats.length;k++){var m=all.split(pats[k]).length-1;extra.push('['+pats[k]+'='+m+']');}
var svg=all.split('<svg').length-1;extra.push('[svg-elements='+svg+']');
var canv=all.split('<canvas').length-1;extra.push('[canvas-elements='+canv+']');}catch(e){extra.push('[html-scan-err '+e.name+']');}
return out.join('\n')+'\n---\n'+extra.join(' ');})()
'@

function CdpDump($stamp) {
  $list = $null
  try { $list = Invoke-RestMethod -Uri ("http://127.0.0.1:$CdpPort/json/list") -TimeoutSec 8 } catch { L ("CDP-LIST-ERROR " + ($_ | Out-String).Trim()); return 'CDP-LIST-ERROR' }
  $pages = @($list | Where-Object { $_.type -eq 'page' })
  $rep = New-Object System.Collections.Generic.List[string]
  $rep.Add("# CDP port $CdpPort at $([DateTime]::Now.ToString('o')) targets=" + @($list).Count + " pages=" + $pages.Count)
  foreach ($p in $list) { $rep.Add("target type=$($p.type) title=`"$($p.title)`" url=$($p.url)") }
  $n = 0
  foreach ($p in $pages) {
    $n++
    if (-not $p.webSocketDebuggerUrl) { continue }
    $expr = $CdpExpr -replace "`r?`n", ' '
    $req = @{ id = 1; method = 'Runtime.evaluate'; params = @{ expression = $expr; returnByValue = $true; awaitPromise = $false } } | ConvertTo-Json -Depth 6 -Compress
    $res = CdpCall $p.webSocketDebuggerUrl $req
    $rep.Add("===== page $n title=`"$($p.title)`" url=$($p.url)")
    if ($res -like 'CDP-*') { $rep.Add("  $res") }
    else {
      try {
        $j = $res | ConvertFrom-Json
        $v = $j.result.result.value
        if ($null -eq $v) { $rep.Add('  (no value) raw=' + $res.Substring(0, [Math]::Min(800, $res.Length))) } else { $rep.Add($v) }
      } catch { $rep.Add('  parse-fail raw=' + $res.Substring(0, [Math]::Min(800, $res.Length))) }
    }
  }
  $f = "$out\dom_$stamp.txt"
  $rep | Set-Content -Path $f -Encoding utf8
  Push $f "wv_${Tag}_dom_$stamp.txt"
  return ('domlines=' + $rep.Count)
}

function StateBundle($phase) {
  L "STATE phase=$phase"
  if (Test-Path "$B\User.zip") {
    $z = Get-Item "$B\User.zip"
    L "  User.zip bytes=$($z.Length) mtime=$($z.LastWriteTime.ToString('o'))"
    Push "$B\User.zip" "wv_${Tag}_${phase}_User.zip"
  } else { L "  User.zip ABSENT" }
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("# $B phase=$phase at $([DateTime]::Now.ToString('o'))")
  foreach ($d in @($B, $R)) {
    $lines.Add("## $d exists=" + (Test-Path $d))
    if (Test-Path $d) {
      $items = Get-ChildItem $d -Recurse -Force -Depth 1 -ErrorAction SilentlyContinue
      foreach ($i in $items) {
        $rel = $i.FullName.Substring($d.Length)
        if ($rel -like "*WebView2*" -and -not ($rel -like "*Local Storage*") -and -not ($rel -like "*Session Storage*")) { continue }
        $len = if ($i.PSIsContainer) { 'DIR' } else { $i.Length }
        $lines.Add(("  " + $rel + "`t" + $len + "`t" + $i.LastWriteTime.ToString('o')))
      }
    }
  }
  # registry: same-shaped keys under HKCU\Software\Microsoft\Power BI Desktop
  $lines.Add("## registry HKCU:\Software\Microsoft\Power BI Desktop")
  try {
    $k = Get-Item 'HKCU:\Software\Microsoft\Power BI Desktop' -ErrorAction Stop
    foreach ($v in $k.GetValueNames()) { $lines.Add("  .$v = " + $k.GetValue($v)) }
    foreach ($sk in $k.GetSubKeyNames()) {
      $lines.Add("  [subkey] $sk")
      $s = Get-Item "HKCU:\Software\Microsoft\Power BI Desktop\$sk" -ErrorAction SilentlyContinue
      if ($s) { foreach ($v in $s.GetValueNames()) { $lines.Add("    .$v = " + $s.GetValue($v)) } }
      foreach ($vk in $s.GetSubKeyNames()) {
        $lines.Add("    [subkey] $vk")
        $s2 = Get-Item "HKCU:\Software\Microsoft\Power BI Desktop\$sk\$vk" -ErrorAction SilentlyContinue
        if ($s2) { foreach ($v in $s2.GetValueNames()) { $lines.Add("      .$v = " + $s2.GetValue($v)) } }
      }
    }
  } catch { $lines.Add("  (no such key: " + ($_ | Out-String).Trim() + ")") }
  $storage = @()
  foreach ($sub in @('WebView2\EBWebView\Default\Local Storage\leveldb', 'WebView2\EBWebView\Default\Session Storage')) {
    $p = Join-Path $B $sub
    $lines.Add("## webview2 storage $p exists=" + (Test-Path $p))
    if (Test-Path $p) {
      foreach ($f in @(Get-ChildItem $p -File -Force -ErrorAction SilentlyContinue)) {
        $lines.Add(("  " + $f.Name + "`t" + $f.Length + "`t" + $f.LastWriteTime.ToString('o')))
        if ($f.Length -lt 8000000) { $storage += $f.FullName }
      }
    }
  }
  $lf = "$out\state_$phase.txt"
  $lines | Set-Content -Path $lf -Encoding utf8
  Push $lf "wv_${Tag}_${phase}_statelisting.txt"
  $n = 0
  foreach ($s in $storage) {
    $n++
    Push $s "wv_${Tag}_${phase}_wv2storage_$n`_$(Split-Path $s -Leaf)"
  }
  L "  webview2_storage_files_pushed=$n"
}

function TraceBundle($phase) {
  $base = "$env:LOCALAPPDATA\Microsoft\Power BI Desktop"
  $T = "$base\Traces"
  $pat = 'CanvasVisualErrorOverlayShown|DataExtensionError|AcquirePlatformEmail|GetConceptualSchema|DataShapeProcessing|LoadExplorationVisuals|hideSpinner|Failed to open the MSOLAP connection|AuthenticatedWebRequestor|ExecuteQuery'
  if (-not (Test-Path $T)) { L "TRACE $phase : no Traces dir" } else {
    $items = @(Get-ChildItem $T -File -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    L ("TRACE $phase files=" + $items.Count + " nonempty=" + @($items | Where-Object { $_.Length -gt 0 }).Count)
    foreach ($i in ($items | Select-Object -First 8)) { L ("  tracefile " + $i.FullName.Substring($base.Length) + " bytes=" + $i.Length + " mtime=" + $i.LastWriteTime.ToString('o')) }
    $newest = $items | Where-Object { $_.Length -gt 0 } | Select-Object -First 1
    if ($newest) {
      $m = @(Select-String -Path $newest.FullName -Pattern $pat -ErrorAction SilentlyContinue)
      L ("TRACE $phase grep_lines=" + $m.Count + " file=" + $newest.Name)
      foreach ($hit in ($m | Select-Object -First 60)) {
        $t = $hit.Line; if ($t.Length -gt 500) { $t = $t.Substring(0, 500) }
        L ("  tracehit " + $t)
      }
      if ($newest.Length -lt 80000000) { Push $newest.FullName ("wv_${Tag}_${phase}_trace_" + $newest.Name) }
    } else { L "TRACE $phase : no non-empty trace file (tracing did not engage)" }
  }
  # where else could a fresh trace have gone?
  $recent = @(Get-ChildItem $base -Recurse -File -Force -ErrorAction SilentlyContinue |
              Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-25) -and $_.Length -gt 2000 -and $_.Extension -in @('.log', '.txt') })
  L ("TRACE $phase recent_logs=" + $recent.Count)
  foreach ($r in ($recent | Select-Object -First 10)) { L ("  recentlog " + $r.FullName.Substring($base.Length) + " bytes=" + $r.Length + " mtime=" + $r.LastWriteTime.ToString('o')) }
}

# ---------------- pre-flight ----------------
# PBI_forceTracing=1 is how tools/launch_pbi_traced.sh makes the Windows app write its own
# Traces\PBIDesktop.<pid>.<ts>.log (the JSON action feed: CanvasVisualErrorOverlayShown,
# LoadExplorationVisuals, …).  Set it here so the guest produces the analogous trace.
$env:PBI_forceTracing = '1'
L ("PBI_forceTracing=" + $env:PBI_forceTracing)
if ($CdpPort -gt 0) {
  # WebView2 reads this when the host does not pass its own AdditionalBrowserArguments; Power BI
  # does not (that is why the Wine prefix's --disable-gpu through this variable works).
  $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = "--remote-debugging-port=$CdpPort --disable-gpu"
  L ("CDP enabled port=" + $CdpPort + " addl_args=" + $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS)
}
L ("PHASE=$Tag pbix=$Pbix exe=" + (Test-Path 'C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe'))
L ("pre_titles: " + ((Get-Process | Where-Object { $_.MainWindowTitle } | ForEach-Object { "$($_.ProcessName)[$($_.Id)]=`"$($_.MainWindowTitle)`"" }) -join ' | '))
L ("pre_pbi_procs=" + (@(Get-Process PBIDesktop -ErrorAction SilentlyContinue).Count))
L ("fresh_state_dir_exists=" + (Test-Path $B))
StateBundle 'before'
TraceBundle 'before_prelaunch'

# close anything left over so the frames belong to this launch
foreach ($p in @(Get-Process PBIDesktop -ErrorAction SilentlyContinue)) { $p.CloseMainWindow() | Out-Null }
Start-Sleep -Seconds 5
foreach ($p in @(Get-Process PBIDesktop -ErrorAction SilentlyContinue)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
if ($Tag -eq 'mature') {
  Start-Sleep -Seconds 3
  StateBundle 'after_graceful_close'
}
Start-Sleep -Seconds 2

$offs = @($Offsets.Split(',') | ForEach-Object { [int]$_ })
$t0 = [DateTime]::Now
L ("T0_local=" + $t0.ToString('o'))
$exe = 'C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe'
L ("launch=" + $exe + ' "' + $Pbix + '"')
$proc = Start-Process -FilePath $exe -ArgumentList "`"$Pbix`"" -PassThru
L ("launched_pid=" + $proc.Id)

$prev = ''
$firstWin = $null; $mainWin = $null
foreach ($o in $offs) {
  while (([DateTime]::Now - $t0).TotalSeconds -lt $o) {
    $st = WinState
    if ($st -ne $prev) {
      L ("winstate t=" + [Math]::Round(([DateTime]::Now - $t0).TotalSeconds, 2) + " " + $st)
      $prev = $st
      if (-not $firstWin) {
        $p = @(Get-Process PBIDesktop -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 })
        if ($p.Count -gt 0) { $firstWin = ([DateTime]::Now - $t0).TotalSeconds; L ("FIRST-WINDOW t=" + [Math]::Round($firstWin, 2) + " `"$($p[0].MainWindowTitle)`"") }
      }
      if (-not $mainWin) {
        $big = @(Get-Process PBIDesktop -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Where-Object {
            $r2 = New-Object PbiVR.N+RECT; [PbiVR.N]::GetWindowRect($_.MainWindowHandle, [ref]$r2) | Out-Null
            ($r2.Right - $r2.Left) -gt 900 -and ($r2.Bottom - $r2.Top) -gt 600 })
        if ($big.Count -gt 0) { $mainWin = ([DateTime]::Now - $t0).TotalSeconds; L ("MAIN-WINDOW t=" + [Math]::Round($mainWin, 2) + " `"$($big[0].MainWindowTitle)`"") }
      }
    }
    Start-Sleep -Milliseconds 150
  }
  $el = [Math]::Round(([DateTime]::Now - $t0).TotalSeconds, 2)
  $f = "$out\t$o.png"
  FocusApp
  Start-Sleep -Milliseconds 500
  $ok = Snap $f
  L ("T=$o actual=$el capture=$ok winstate=" + (WinState))
  L ("T=$o allwindows=" + (AllWindows))
  L ("T=$o uia=" + (UiaText))
  if ($CdpPort -gt 0) { L ("T=$o cdp=" + (CdpDump "t$o")) }
  if ($ok) { Push $f "wv_${Tag}_t$o.png" }
  PushLog
}
L ("final_titles: " + ((Get-Process | Where-Object { $_.MainWindowTitle } | ForEach-Object { "$($_.ProcessName)[$($_.Id)]=`"$($_.MainWindowTitle)`"" }) -join ' | '))
L ("final_uia=" + (UiaText))
StateBundle 'after_open'
# graceful close, then capture what a normal exit writes
foreach ($p in @(Get-Process PBIDesktop -ErrorAction SilentlyContinue)) { $p.CloseMainWindow() | Out-Null }
Start-Sleep -Seconds 15
foreach ($p in @(Get-Process PBIDesktop -ErrorAction SilentlyContinue)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 5
StateBundle 'after_exit'
TraceBundle 'after_exit'
RestoreConsoles
L 'DONE'
PushLog
