# install_csp.ps1 — install the CSP reference on the Windows guest (F: = CSPMEDIA ISO).
# WebView2 first, then the CSP installer.  Streams progress to the host.
$ErrorActionPreference = 'Continue'
$U    = 'http://192.168.122.1:8000/'
$LOG  = 'C:\seref\csp_install.log'
$prog = 'C:\seref\vm_cleanup_progress.txt'
New-Item -ItemType Directory -Force -Path 'C:\seref' | Out-Null
Remove-Item $LOG -ErrorAction SilentlyContinue

function Say([string]$m) {
  $line = "{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
  Add-Content -Path $LOG -Value $line -Encoding utf8
  Copy-Item $LOG $prog -Force -ErrorAction SilentlyContinue
  curl.exe -s -T $prog ($U + 'vm_cleanup_progress.txt') 2>$null | Out-Null
}

Say "==== CSP REFERENCE INSTALL START ===="
Say "media: $(Get-ChildItem F:\ -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name -ErrorAction SilentlyContinue)"

# --- WebView2 runtime (the launcher's home screen depends on it)
if (Test-Path 'F:\MicrosoftEdgeWebView2RuntimeInstallerX64.exe') {
  Say "WebView2: installing"
  $p = Start-Process 'F:\MicrosoftEdgeWebView2RuntimeInstallerX64.exe' -ArgumentList '/silent','/install' -PassThru -Wait -WindowStyle Hidden
  Say "WebView2: exit=$($p.ExitCode)"
  $wv = Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}' -ErrorAction SilentlyContinue
  Say "WebView2: version=$($wv.pv)"
}

# --- CSP installer.  It is an InstallScript project: try /s first, then report what it did.
Say "CSP: launching installer (silent attempt)"
$csp = Start-Process 'F:\CSP_514w_setup.exe' -ArgumentList '/s' -PassThru
Say "CSP: pid=$($csp.Id)"
$waited = 0
while (-not $csp.HasExited -and $waited -lt 600) { Start-Sleep -Seconds 10; $waited += 10 }
Say "CSP: after ${waited}s exited=$($csp.HasExited) code=$(if($csp.HasExited){$csp.ExitCode}else{'running'})"

$dir = 'C:\Program Files\CELSYS'
Say "CELSYS dir exists: $(Test-Path $dir)"
if (Test-Path $dir) {
  Get-ChildItem $dir -Recurse -Depth 2 -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '\.exe$' } | ForEach-Object { Say "EXE $($_.FullName)" }
}
Say "==== CSP REFERENCE INSTALL DONE ===="
curl.exe -s -T $prog ($U + 'vm_cleanup_progress.txt') 2>$null | Out-Null
curl.exe -s -T $LOG  ($U + 'csp_install.log') 2>$null | Out-Null
