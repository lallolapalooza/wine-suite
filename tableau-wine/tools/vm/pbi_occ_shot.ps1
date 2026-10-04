param(
  [string]$Tag = 'shot',
  [int]$Port = 9222,
  [string]$Pbix = 'C:\pbiref\IbeRevUATEpamPerformance.pbix',
  [int]$WaitSeconds = 130
)
# Guest side: launch the app on the document, then read which surface the SCREEN shows while each Minerva page
# says what IT is rendering.  The pair is the point:
#   * an in-guest screen capture (the pixels a user sees),
#   * `Page.captureScreenshot` per page target (what that page's own compositor has),
#   * `document.visibilityState` + the tour-dialog markup per page.
# If the covered DAX/TMDL pages have a fully rendered screenshot of their own while the screen shows the report
# page, then Windows hides them at the compositor/DWM level — not by occlusion state and not by page visibility.
#
# usage (from the host):
#   tools/vm/vmcmd.sh 'curl.exe -s -o C:\pbiref\occshot.ps1 http://192.168.122.1:8000/pbi_occ_shot.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File C:\pbiref\occshot.ps1 -Tag s130' 360
$ErrorActionPreference = 'Continue'
$U = 'http://192.168.122.1:8000/'
$out = "C:\pbiref\occ_$Tag"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$log = "$out\log.txt"
function L($m) { Add-Content -Path $log -Value ("$([DateTime]::Now.ToString('o')) $m") -Encoding utf8 }
function Push($f, $n) { if (Test-Path $f) { curl.exe -s -T $f ($U + $n) | Out-Null } }

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Namespace OccN -Name N -MemberDefinition '
[DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr h);
[DllImport("user32.dll")] public static extern bool GetWindowRect(System.IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int cmd);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr h);
[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);
public struct RECT { public int Left, Top, Right, Bottom; }
' | Out-Null
try { [OccN.N]::SetThreadExecutionState([uint32]2147483651) | Out-Null } catch {}

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

# the poller's own console sits on top of the app; minimise it so the screen capture is the app's pixels
function FocusApp {
  try {
    $best = [System.IntPtr]::Zero; $bestA = 0
    foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
      $h = $p.MainWindowHandle
      if ($h -eq [System.IntPtr]::Zero) { continue }
      if (-not [OccN.N]::IsWindowVisible($h)) { continue }
      if ($p.ProcessName -match 'WindowsTerminal|cmd|powershell|conhost|OpenConsole') { [OccN.N]::ShowWindow($h, 6) | Out-Null; continue }
      if ($p.ProcessName -eq 'PBIDesktop') {
        $r = New-Object OccN.N+RECT
        [OccN.N]::GetWindowRect($h, [ref]$r) | Out-Null
        $a = ($r.Right - $r.Left) * ($r.Bottom - $r.Top)
        if ($a -gt $bestA) { $bestA = $a; $best = $h }
      }
    }
    if ($best -ne [System.IntPtr]::Zero) { [OccN.N]::SetForegroundWindow($best) | Out-Null; L ("focused=" + $best) }
  } catch { L ("FOCUS-ERROR " + ($_ | Out-String).Trim()) }
}

function CdpCall($wsUrl, $json, $bufSize = 524288) {
  $ws = New-Object System.Net.WebSockets.ClientWebSocket
  $ct = [System.Threading.CancellationToken]::None
  try {
    if (-not $ws.ConnectAsync([Uri]$wsUrl, $ct).Wait(8000)) { return 'CDP-CONNECT-TIMEOUT' }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $seg = New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$bytes)
    if (-not $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait(8000)) { return 'CDP-SEND-TIMEOUT' }
    $ms = New-Object System.IO.MemoryStream
    $buf = New-Object byte[] $bufSize
    do {
      $rseg = New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$buf)
      $t = $ws.ReceiveAsync($rseg, $ct)
      if (-not $t.Wait(30000)) { return 'CDP-RECV-TIMEOUT' }
      $r = $t.Result
      $ms.Write($buf, 0, $r.Count)
    } while (-not $r.EndOfMessage)
    return [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
  } catch { return ('CDP-ERROR ' + ($_ | Out-String).Trim()) }
  finally { try { $ws.Dispose() } catch {} }
}

$expr = @'
(function(){var H=document.documentElement.outerHTML;var o={url:String(location.href),visibilityState:document.visibilityState,hidden:document.hidden,hasFocus:document.hasFocus()};
var pats=['tmdl-view-tutorial','Take a tour','Run DAX queries on your model','Edit your model with TMDL','mat-dialog-container','Welcome to TMDL View!'];
for(var i=0;i<pats.length;i++){o['n:'+pats[i]]=H.split(pats[i]).length-1;}
o.svg=document.querySelectorAll('svg').length;return JSON.stringify(o);})()
'@

$rep = New-Object System.Collections.Generic.List[string]
$rep.Add("# occ shot tag=$Tag at $([DateTime]::Now.ToString('o'))")

# --- launch -------------------------------------------------------------------------------------
$env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = "--remote-debugging-port=$Port --disable-gpu"
$q = [char]34
try {
  $p = Start-Process "C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe" -ArgumentList ($q + $Pbix + $q) -PassThru
  $rep.Add("launched pid=" + $p.Id + " addl=" + $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS)
} catch { $rep.Add("launch failed: " + ($_ | Out-String).Trim()) }

# --- wait for the six pages ---------------------------------------------------------------------
$want = 6
for ($i = 0; $i -lt ($WaitSeconds / 5); $i++) {
  Start-Sleep -Seconds 5
  try {
    $l = Invoke-RestMethod -Uri ("http://127.0.0.1:$Port/json/list") -TimeoutSec 5
    $np = @($l | Where-Object { $_.type -eq 'page' -and $_.url -match 'minerva/.*\.html' }).Count
    if ($np -ge $want) { break }
  } catch {}
}
L ("targets ready after ~" + (5 * ($i + 1)) + "s")

# --- the screen, then each page's own screenshot ------------------------------------------------
FocusApp
Start-Sleep -Seconds 3
$scr = "$out\screen.png"
if (Snap $scr) { $rep.Add("screen captured: " + (Get-Item $scr).Length + " bytes") } else { $rep.Add("screen capture FAILED") }
Push $scr "occ_${Tag}_screen.png"

try { $list = Invoke-RestMethod -Uri ("http://127.0.0.1:$Port/json/list") -TimeoutSec 8 } catch { $list = $null }
if ($null -eq $list) { $rep.Add("CDP UNREACHABLE on $Port") } else {
  $rep.Add("targets=" + @($list).Count)
  foreach ($p in @($list | Where-Object { $_.type -eq 'page' -and $_.url -match 'minerva/(reportView|daxQueryView|tmdlView)\.html' })) {
    $name = ($p.url -replace '.*/minerva/','' -replace '\.html','')
    $rep.Add("===== $($p.url)")
    $r1 = CdpCall $p.webSocketDebuggerUrl (@{ id = 1; method = 'Runtime.evaluate'; params = @{ expression = ($expr -replace "`r?`n", ' '); returnByValue = $true } } | ConvertTo-Json -Depth 6 -Compress)
    if ($r1 -like 'CDP-*') { $rep.Add("  eval $r1") } else {
      try { $rep.Add("  " + ($r1 | ConvertFrom-Json).result.result.value) } catch { $rep.Add("  eval parse-fail") }
    }
    $r2 = CdpCall $p.webSocketDebuggerUrl (@{ id = 2; method = 'Page.enable' } | ConvertTo-Json -Compress)
    $r3 = CdpCall $p.webSocketDebuggerUrl (@{ id = 3; method = 'Page.captureScreenshot'; params = @{ format = 'png' } } | ConvertTo-Json -Compress) 4194304
    if ($r3 -like 'CDP-*') { $rep.Add("  shot $r3") } else {
      try {
        $d = ($r3 | ConvertFrom-Json).result.data
        $f = "$out\page_$name.png"
        [IO.File]::WriteAllBytes($f, [Convert]::FromBase64String($d))
        $rep.Add("  page shot: page_$name.png " + (Get-Item $f).Length + " bytes")
        Push $f "occ_${Tag}_page_$name.png"
      } catch { $rep.Add("  shot parse-fail " + $r3.Substring(0, [Math]::Min(200, $r3.Length))) }
    }
  }
}

# --- leave the guest the way we found it --------------------------------------------------------
Get-Process PBIDesktop -ErrorAction SilentlyContinue | ForEach-Object { $_.CloseMainWindow() | Out-Null }
Start-Sleep -Seconds 15
$rep.Add("pbi_after_close=" + @(Get-Process PBIDesktop -ErrorAction SilentlyContinue).Count)

$rep | Set-Content -Path "$out\report.txt" -Encoding utf8
Push "$out\report.txt" "occ_$Tag.txt"
Push $log "occ_${Tag}_log.txt"
Write-Output ("occ shot written: $out\report.txt -> occ_$Tag.txt (lines=" + $rep.Count + ")")
