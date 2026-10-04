param(
  [string]$Tag = 'occ',
  [int]$Port = 9222
)
# Read, from a *running* Power BI Desktop on the Windows guest, two things per Minerva page:
#   (a) the tutorial dialog's own markup (the localization key `Take_A_Tour`, the `tmdl-view-tutorial`
#       container / `tri-dialog`), which proves the getKey("<X>TutorialKey") gate opened the dialog even
#       though the key is absent from the profile;
#   (b) `document.visibilityState` — the occlusion signal: on Windows a page whose window is covered by
#       another one is marked occluded by Chromium's native window-occlusion detection (DWM), which is a
#       stub under Wine (docs/MANAGED_VIEW.md 5.2 / FINDINGS M59).
# The app must be running with WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=<Port>.
#
# usage: tools/vm/vmcmd.sh "curl.exe -s -o C:\pbiref\occ.ps1 http://192.168.122.1:8000/pbi_occ_probe.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File C:\pbiref\occ.ps1 -Tag t70"
$ErrorActionPreference = 'Continue'
$U = 'http://192.168.122.1:8000/'
$out = "C:\pbiref\occ_$Tag"
New-Item -ItemType Directory -Force -Path $out | Out-Null
function Push($f, $n) { if (Test-Path $f) { curl.exe -s -T $f ($U + $n) | Out-Null } }

$expr = @'
(function(){
 var H=document.documentElement.outerHTML;
 var o={url:String(location.href), visibilityState:document.visibilityState, hidden:document.hidden,
        hasFocus:document.hasFocus(), htmlLen:H.length};
 var pats=['tmdl-view-tutorial','dax-query-view-tutorial','dax-view-tutorial','Take_A_Tour','Take a tour',
           'tri-dialog','Tmdl_View_Tutorial','DaxQueryViewTutorialKey','TmdlViewTutorialKey',
           'Run DAX queries on your model','Edit your model with TMDL','mat-dialog-container',
           'Welcome to DAX query view!','Welcome to TMDL View!','data-unique-id','Try it now',
           'Servicio','Tiempo Promedio','Limite_Tiempo','Página 1','Design your report on mobile',
           'Error fetching data','See details','visualContainer','Add data field here'];
 for(var i=0;i<pats.length;i++){ o['n:'+pats[i]] = H.split(pats[i]).length-1; }
 o.svg = document.querySelectorAll('svg').length;
 o.visualContainers = document.querySelectorAll('.visualContainer,[class*=visualContainer]').length;
 o.sel_tri_dialog = document.querySelectorAll('tri-dialog').length;
 o.sel_tmdl_tutorial = document.querySelectorAll('tmdl-view-tutorial').length;
 o.sel_mat_dialog = document.querySelectorAll('mat-dialog-container').length;
 o.sel_tour_attr = document.querySelectorAll('[data-unique-id*="Tour" i]').length;
 o.perfNow = Math.round(performance.now());
 o.bodyTextLen = (document.body?document.body.innerText:'').length;
 o.focused = (document.activeElement&&document.activeElement.tagName)||'';
 var el=null, all=document.querySelectorAll('*');
 for(var i=0;i<all.length;i++){
   if(all[i].children.length===0 && /Run DAX queries on your model|Edit your model with TMDL/.test(all[i].textContent||'')){el=all[i];break;}
 }
 if(el){ var d=el; for(var k=0;k<10&&d.parentElement;k++){ d=d.parentElement; }
         o.dialogOuterHTML=d.outerHTML.substring(0,4000); }
 else { o.dialogOuterHTML='(no element carrying the dialog title text)'; }
 return JSON.stringify(o);
})()
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
    $buf = New-Object byte[] 262144
    do {
      $rseg = New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$buf)
      $t = $ws.ReceiveAsync($rseg, $ct)
      if (-not $t.Wait(15000)) { return 'CDP-RECV-TIMEOUT' }
      $r = $t.Result
      $ms.Write($buf, 0, $r.Count)
    } while (-not $r.EndOfMessage)
    return [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
  } catch { return ('CDP-ERROR ' + ($_ | Out-String).Trim()) }
  finally { try { $ws.Dispose() } catch {} }
}

$rep = New-Object System.Collections.Generic.List[string]
$rep.Add("# occlusion probe tag=$Tag at $([DateTime]::Now.ToString('o')) port=$Port")
$rep.Add("pbi_procs=" + @(Get-Process PBIDesktop -ErrorAction SilentlyContinue).Count)

# the browser's own command line: proves the WebView2 children really got the flags
try {
  $cl = Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe'" |
        Where-Object { $_.CommandLine -match 'embedded-browser-webview' } | Select-Object -First 1 -ExpandProperty CommandLine
  if ($cl) { $rep.Add("msedgewebview2_cmdline=" + $cl.Substring(0, [Math]::Min(700, $cl.Length))) }
  else { $rep.Add("msedgewebview2_cmdline=(none matched embedded-browser-webview)") }
} catch { $rep.Add("msedgewebview2_cmdline=read-failed") }

$list = $null
for ($i = 0; $i -lt 8 -and $null -eq $list; $i++) {
  try { $list = Invoke-RestMethod -Uri ("http://127.0.0.1:$Port/json/list") -TimeoutSec 5 } catch { Start-Sleep -Seconds 2 }
}
if ($null -eq $list) {
  $rep.Add("CDP UNREACHABLE on $Port")
} else {
  $rep.Add("targets=" + @($list).Count)
  foreach ($t in $list) { $rep.Add("target type=$($t.type) title=`"$($t.title)`" url=$($t.url)") }
  $pages = @($list | Where-Object { $_.type -eq 'page' -and $_.url -match 'minerva/(daxQueryView|tmdlView|reportView|modelView|dataExploreView)\.html' })
  foreach ($p in $pages) {
    $req = @{ id = 1; method = 'Runtime.evaluate'; params = @{ expression = ($expr -replace "`r?`n", ' '); returnByValue = $true } } | ConvertTo-Json -Depth 6 -Compress
    $res = CdpCall $p.webSocketDebuggerUrl $req
    $rep.Add("===== page $($p.url)")
    if ($res -like 'CDP-*') { $rep.Add("  $res") }
    else {
      try { $j = $res | ConvertFrom-Json; $rep.Add($j.result.result.value) }
      catch { $rep.Add("  parse-fail raw=" + $res.Substring(0, [Math]::Min(700, $res.Length))) }
    }
  }
}
$f = "$out\probe.txt"
$rep | Set-Content -Path $f -Encoding utf8
Push $f "occ_$Tag.txt"
Write-Output ("occ probe written: $f -> occ_$Tag.txt (lines=" + $rep.Count + ")")
