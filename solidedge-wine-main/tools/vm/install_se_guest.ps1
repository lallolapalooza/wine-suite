# install_se_guest.ps1 — install Solid Edge 2026 in the Windows guest from the host's media.
#
# The host serves the extracted InstallShield media (`installer/media_x/`) on port 8001 with
# plain `python3 -m http.server`; this script mirrors `Solid Edge/` into `C:\semedia\Solid Edge`,
# then runs the vendor's own install command line and uploads the MSI log.
#
# Run it from the host with:  tools/vm/vmcmd.sh -f tools/vm/install_se_guest.ps1
# (vmcmd.sh sends one line; pass the script as a single line with ';' separators, or use -f to
#  have the tool read the file and send it as one line.)

$ErrorActionPreference = 'Continue'
$base = 'http://192.168.122.1:8001/Solid%20Edge/'
$dest = 'C:\semedia\Solid Edge'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
New-Item -ItemType Directory -Force -Path 'C:\seprobe' | Out-Null

"== mirroring media"
$listing = (curl.exe -s $base) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^<' }
"files listed: " + $listing.Count
foreach ($f in $listing) {
    $out = Join-Path $dest $f
    if ((Test-Path $out) -and ((Get-Item $out).Length -gt 0)) { continue }
    curl.exe -s -o "$out" ($base + [uri]::EscapeDataString($f))
}
$total = (Get-ChildItem $dest -Recurse | Measure-Object Length -Sum).Sum
"mirrored bytes: " + $total

"== running setup.exe"
$install = 'C:\Program Files\Siemens\Solid Edge 2026'
$lic = $install + '\Preferences\SELicense.lic'
$log = "$env:TEMP\SESilentInstall.txt"
$args = @('/s','/clone_wait','/v"/qn"',
          ('/v"INSTALLDIR=\"' + $install + '\""'),
          ('/v"USERFILESPEC=\"' + $lic + '\""'),
          ('/v"/l*v \"' + $log + '\""'))
"args: " + ($args -join ' ')
$p = Start-Process -FilePath (Join-Path $dest 'setup.exe') -ArgumentList $args -Wait -PassThru
"setup exit: " + $p.ExitCode

"== result"
if (Test-Path ($install + '\Program\Edge.exe')) { "EDGE_EXE=present" } else { "EDGE_EXE=MISSING" }
if (Test-Path $lic) { "LICENSE=present " + (Get-Item $lic).Length } else { "LICENSE=MISSING" }
if (Test-Path $log) {
    Copy-Item $log C:\seprobe\SESilentInstall.txt -Force
    curl.exe -s -T C:\seprobe\SESilentInstall.txt http://192.168.122.1:8000/se_install_guest.txt | Out-Null
    "log uploaded"
}
