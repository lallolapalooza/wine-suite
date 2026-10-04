$ErrorActionPreference = "Continue"
function HR($block) {
  try { $v = & $block; "OK [$v]" }
  catch {
    $e = $_.Exception
    "EXC msg=[{0}] hr=[{1}] inner=[{2}] ihr=[{3}]" -f $e.Message, ("0x{0:X8}" -f $e.HResult), $e.InnerException.Message, ("0x{0:X8}" -f $e.InnerException.HResult)
  }
}
function V($d, $label) { "{0}.Value=[{1}] IsInterval=[{2}] Year=[{3}] Month=[{4}] Day=[{5}] H=[{6}] M=[{7}] S=[{8}] us=[{9}] UTC=[{10}] Ys=[{11}] Ms=[{12}] Ds=[{13}] Us=[{14}]" -f $label,$d.Value,$d.IsInterval,$d.Year,$d.Month,$d.Day,$d.Hours,$d.Minutes,$d.Seconds,$d.Microseconds,$d.UTC,$d.YearSpecified,$d.MonthSpecified,$d.DaySpecified,$d.UTCSpecified }

$d = New-Object -ComObject WbemScripting.SWbemDateTime
"P1 malformed Value: " + (HR { $d.Value = "garbage" })
"P2 malformed Value2: " + (HR { $d.Value = "20000120195632.000000" })
"P3 short Value3: " + (HR { $d.Value = "2000" })
"P4 SetFileTime abc: " + (HR { $d.SetFileTime("abc", $false) })
"P5 SetFileTime empty: " + (HR { $d.SetFileTime("", $false) })
"P6 SetFileTime ok: " + (HR { $d.SetFileTime("126036951652030000", $false); $d.Value })
$di = New-Object -ComObject WbemScripting.SWbemDateTime
$di.Value = "00000100010003.000000:000"
"P7 GetVarDate interval: " + (HR { $di.GetVarDate($true) })
"P8 GetFileTime interval: " + (HR { $di.GetFileTime($false) })
$dz = New-Object -ComObject WbemScripting.SWbemDateTime
"P9 GetVarDate new(default): " + (HR { $dz.GetVarDate($true) })
"P10 GetFileTime new(default): " + (HR { $dz.GetFileTime($false) })
$d11 = New-Object -ComObject WbemScripting.SWbemDateTime
$d11.Value = "20000120195632.000000+000"
"P11 YearSpecified=false -> " + (HR { $d11.YearSpecified = $false; $d11.Value })
"P12 after get Year " + (HR { $d11.Year })
"P13 DaySpecified=false -> " + (HR { $d11.DaySpecified = $false; $d11.Value })
"P14 MicrosecondsSpecified=false -> " + (HR { $d11.MicrosecondsSpecified = $false; $d11.Value })
"P15 UTCSpecified=false -> " + (HR { $d11.UTCSpecified = $false; $d11.Value })
"P16 set year back ok -> " + (HR { $d11.YearSpecified = $true; $d11.Value })
$d12 = New-Object -ComObject WbemScripting.SWbemDateTime
$d12.Value = "20000120195632.000000+000"
"P17 date then IsInterval=true -> " + (HR { $d12.IsInterval = $true; $d12.Value })
"P18 date IsInterval=true fields: " + (V $d12 "P18")
"P19 interval then IsInterval=false -> " + (HR { $d12.IsInterval = $false; $d12.Value })
"P20 : " + (V $d12 "P20")
$d13 = New-Object -ComObject WbemScripting.SWbemDateTime
$d13.IsInterval = $true
$d13.Year = 5
$d13.Month = 7
$d13.Day = 100
"P21 interval y5 m7 d100 -> " + (HR { $d13.Value })
$d14 = New-Object -ComObject WbemScripting.SWbemDateTime
"P22 default new: " + (HR { V $d14 "P22" })
"P23 SetVarDate with interval true then -> " + (HR { $d14.IsInterval = $true; $d14.SetVarDate([datetime]::new(2020,3,4,5,6,7), $true); V $d14 "P23" })
"P24 set UTC=9999 -> " + (HR { $d14.UTC = 9999; $d14.Value })
"P25 set UTC=99999 -> " + (HR { $d14.UTC = 99999; $d14.Value })
"P26 set Hours=99 -> " + (HR { $d14.Hours = 99; $d14.Value })
"P27 set Day=0 -> " + (HR { $d14.Day = 0; $d14.Value })
"P28 msg for 0x80041021: " + (HR { $x = [System.Runtime.InteropServices.Marshal]::GetExceptionForHR([int]0x80041021); $x.Message })
"P29 msg for 0x80041014: " + (HR { $x = [System.Runtime.InteropServices.Marshal]::GetExceptionForHR([int]0x80041014); $x.Message })
"P30 msg for 0x80041001: " + (HR { $x = [System.Runtime.InteropServices.Marshal]::GetExceptionForHR([int]0x80041001); $x.Message })
