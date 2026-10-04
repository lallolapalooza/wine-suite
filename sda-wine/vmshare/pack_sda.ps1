# Package the installed SDA tree and upload it to the host share.
$src = "C:\Program Files (x86)\Steinberg"
$zip = "C:\sda\sda_installed.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $src -DestinationPath $zip -Force
"zip bytes = " + (Get-Item $zip).Length
curl.exe -s -T $zip http://192.168.122.1:8000/sda_installed.zip
"--- full file listing (size, path) ---"
Get-ChildItem $src -Recurse -File | ForEach-Object { "{0,12}  {1}" -f $_.Length, $_.FullName }
"--- Installer.ini ---"
Get-Content "C:\Program Files (x86)\Steinberg\Download Assistant\Installer.ini" -ErrorAction SilentlyContinue
"--- installbuilder log ---"
Get-Content "$env:TEMP\installbuilder_installer.log" -ErrorAction SilentlyContinue | Select-Object -First 60
