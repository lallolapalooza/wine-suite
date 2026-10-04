param(
  [string]$Tag = 'canvasdom',
  [int]$Port = 9222,
  [int]$MaxPages = 3,
  [string]$Match = 'minerva|IbeRev|Power BI Desktop',
  [string]$Pbix = 'C:\pbiref\IbeRevUATEpamPerformance.pbix',
  [switch]$Launch
)
# Read the *text of the report canvas* out of a running Power BI Desktop on the Windows guest.
#
# The canvas is a WebView2 (Chromium) page and Power BI exposes nothing of it to a same-session UIA
# client (measured: pbi_viewref.ps1's UiaText returns only the window/titlebar), so the only
# textual window into the canvas is the browser's own DevTools protocol.  The app must have been
# launched with WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=<Port> in its
# environment (pbi_viewref.ps1 -CdpPort does that; or use -Launch here).
#
# usage: pbi_cdp_probe.ps1 -Tag <tag> [-Port 9222] [-MaxPages 3] [-Match <regex>] [-Launch -Pbix <path>]
# Writes C:\pbiref\cdp_<tag>\dom_<stamp>.txt and pushes it to http://192.168.122.1:8000/ as
# wv_<tag>_dom_<stamp>.txt.
$ErrorActionPreference = 'Continue'
$U = 'http://192.168.122.1:8000/'
$out = "C:\pbiref\cdp_$Tag"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$log = "$out\probe.log"
function L($m) { Add-Content -Path $log -Value ("$([DateTime]::Now.ToString('o')) $m") -Encoding utf8 }
function Push($f, $n) { if (Test-Path $f) { curl.exe -s -T $f ($U + $n) | Out-Null } }

Add-Type -Namespace PbiCdp -Name N -MemberDefinition '
[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);
' | Out-Null
try { [PbiCdp.N]::SetThreadExecutionState([uint32]2147483651) | Out-Null } catch {}

$env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = "--remote-debugging-port=$Port --disable-gpu"
L ("port=$Port match=$Match addl=" + $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS)
if ($Launch) {
  $exe = 'C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe'
  $p = Start-Process -FilePath $exe -ArgumentList "`"$Pbix`"" -PassThru
  L ("launched_pid=" + $p.Id)
}

$EvalExpr = @'
(function(){var out=[];function walk(w,d){try{var t=(w.document&&w.document.body)?w.document.body.innerText:'';out.push('[frame depth='+d+' url='+String(w.location.href).substring(0,140)+']\n'+t);}catch(e){out.push('[frame depth='+d+' UNREADABLE '+e.name+']');}try{for(var i=0;i<w.frames.length;i++){walk(w.frames[i],d+1);}}catch(e){}}
walk(window,0);
var extra=[];
try{var all=document.documentElement.outerHTML;extra.push('[top-html-len='+all.length+']');
var pats=['Error fetching data','See details','DataExtensionError','visualContainer','actualSize'];
for(var k=0;k<pats.length;k++){extra.push('['+pats[k]+'='+(all.split(pats[k]).length-1)+']');}
extra.push('[svg='+(all.split('<svg').length-1)+']');extra.push('[canvas='+(all.split('<canvas').length-1)+']');}catch(e){extra.push('[html-scan-err '+e.name+']');}
return out.join('\n')+'\n---\n'+extra.join(' ');})()
'@

function CdpCall($wsUrl, $json) {
  $ws = New-Object System.Net.WebSockets.ClientWebSocket
  $ct = [System.Threading.CancellationToken]::None
  try {
    if (-not $ws.ConnectAsync([Uri]$wsUrl, $ct).Wait(6000)) { return 'CDP-CONNECT-TIMEOUT' }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $seg = New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$bytes)
    if (-not $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait(6000)) { return 'CDP-SEND-TIMEOUT' }
    $ms = New-Object System.IO.MemoryStream
    $buf = New-Object byte[] 524288
    do {
      $rseg = New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$buf)
      $t = $ws.ReceiveAsync($rseg, $ct)
      if (-not $t.Wait(12000)) { return 'CDP-RECV-TIMEOUT' }
      $r = $t.Result
      $ms.Write($buf, 0, $r.Count)
    } while (-not $r.EndOfMessage)
    return [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
  } catch { return ('CDP-ERROR ' + ($_ | Out-String).Trim()) }
  finally { try { $ws.Dispose() } catch {} }
}

$stamp = [DateTime]::Now.ToString('HHmmss')
$rep = New-Object System.Collections.Generic.List[string]
$list = $null
for ($try = 1; $try -le 12 -and $null -eq $list; $try++) {
  try { $list = Invoke-RestMethod -Uri ("http://127.0.0.1:$Port/json/list") -TimeoutSec 5 } catch { L ("list try $try failed: " + ($_ | Out-String).Trim()); Start-Sleep -Seconds 3 }
}
if ($null -eq $list) {
  $rep.Add('CDP UNREACHABLE on port ' + $Port)
  L 'CDP UNREACHABLE'
} else {
  $rep.Add("# CDP port $Port at $([DateTime]::Now.ToString('o'))  targets=" + @($list).Count)
  foreach ($t in $list) { $rep.Add("target type=$($t.type) title=`"$($t.title)`" url=$($t.url)") }
  $pages = @($list | Where-Object { $_.type -eq 'page' -and ($_.url -match $Match -or $_.title -match $Match) })
  $rep.Add("# matching pages=" + $pages.Count + " (match=$Match)")
  $n = 0
  foreach ($p in ($pages | Select-Object -First $MaxPages)) {
    $n++
    if (-not $p.webSocketDebuggerUrl) { continue }
    $expr = $EvalExpr -replace "`r?`n", ' '
    $req = @{ id = 1; method = 'Runtime.evaluate'; params = @{ expression = $expr; returnByValue = $true } } | ConvertTo-Json -Depth 6 -Compress
    $res = CdpCall $p.webSocketDebuggerUrl $req
    $rep.Add("===== page $n title=`"$($p.title)`" url=$($p.url)")
    if ($res -like 'CDP-*') { $rep.Add("  $res") }
    else {
      try {
        $j = $res | ConvertFrom-Json
        $v = $j.result.result.value
        if ($null -eq $v) { $rep.Add('  (no value) raw=' + $res.Substring(0, [Math]::Min(1000, $res.Length))) } else { $rep.Add($v) }
      } catch { $rep.Add('  parse-fail raw=' + $res.Substring(0, [Math]::Min(1000, $res.Length))) }
    }
  }
}
$f = "$out\dom_$stamp.txt"
$rep | Set-Content -Path $f -Encoding utf8
$name = "wv_${Tag}_dom_$stamp.txt"
Push $f $name
L ("wrote $f (" + $rep.Count + " lines) -> $name")
Write-Output ("wrote $f (" + $rep.Count + " lines) -> $name")
