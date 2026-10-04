$ErrorActionPreference = "Continue"
function TryGet($label, $block) {
  try { $v = & $block; Write-Output ("{0} = [{1}]" -f $label, $v) }
  catch { Write-Output ("{0} !! EXC {1}" -f $label, $_.Exception.Message) }
}
function Dump($tag, $d) {
  Write-Output ("--- {0} ---" -f $tag)
  TryGet "$tag.Value" { $d.Value }
  TryGet "$tag.IsInterval" { $d.IsInterval }
  TryGet "$tag.Year" { $d.Year }
  TryGet "$tag.Month" { $d.Month }
  TryGet "$tag.Day" { $d.Day }
  TryGet "$tag.Hours" { $d.Hours }
  TryGet "$tag.Minutes" { $d.Minutes }
  TryGet "$tag.Seconds" { $d.Seconds }
  TryGet "$tag.Microseconds" { $d.Microseconds }
  TryGet "$tag.UTC" { $d.UTC }
  TryGet "$tag.YearSpecified" { $d.YearSpecified }
  TryGet "$tag.MonthSpecified" { $d.MonthSpecified }
  TryGet "$tag.DaySpecified" { $d.DaySpecified }
  TryGet "$tag.HoursSpecified" { $d.HoursSpecified }
  TryGet "$tag.MinutesSpecified" { $d.MinutesSpecified }
  TryGet "$tag.SecondsSpecified" { $d.SecondsSpecified }
  TryGet "$tag.MicrosecondsSpecified" { $d.MicrosecondsSpecified }
  TryGet "$tag.UTCSpecified" { $d.UTCSpecified }
  TryGet "$tag.GetVarDate(true)" { $d.GetVarDate($true).ToString("yyyy-MM-dd HH:mm:ss.fff") }
  TryGet "$tag.GetVarDate(false)" { $d.GetVarDate($false).ToString("yyyy-MM-dd HH:mm:ss.fff") }
  TryGet "$tag.GetFileTime(true)" { $d.GetFileTime($true) }
  TryGet "$tag.GetFileTime(false)" { $d.GetFileTime($false) }
}
Write-Output ("TZ = " + (Get-TimeZone).Id + " offset " + (Get-TimeZone).BaseUtcOffset)

$d = New-Object -ComObject WbemScripting.SWbemDateTime
Write-Output ("CREATED type=" + $d.GetType().FullName)

$d.Value = "20000120195632.000000-480"
Dump "A_setValue_utcminus480" $d

$d2 = New-Object -ComObject WbemScripting.SWbemDateTime
$d2.SetVarDate((Get-Date "2000-01-20 11:56:32"), $true)
Dump "B_SetVarDate_local" $d2

$d3 = New-Object -ComObject WbemScripting.SWbemDateTime
$d3.SetVarDate((Get-Date "2000-01-20 11:56:32"), $false)
Dump "C_SetVarDate_utc" $d3

$d4 = New-Object -ComObject WbemScripting.SWbemDateTime
$d4.SetFileTime("126036951652030000", $false)
Dump "D_SetFileTime_false" $d4

$d5 = New-Object -ComObject WbemScripting.SWbemDateTime
$d5.SetFileTime("126036951652030000", $true)
Dump "E_SetFileTime_true" $d5

$d6 = New-Object -ComObject WbemScripting.SWbemDateTime
$d6.IsInterval = $true
$d6.Day = 100
$d6.Hours = 1
$d6.Seconds = 3
Dump "F_interval_build" $d6

$d7 = New-Object -ComObject WbemScripting.SWbemDateTime
$d7.Value = "00000100010003.000000:000"
Dump "G_interval_parse" $d7

Write-Output "--- malformed ---"
$d8 = New-Object -ComObject WbemScripting.SWbemDateTime
TryGet "H1.Value=garbage" { $d8.Value = "garbage"; "ok" }
TryGet "H1.Value_after" { $d8.Value }
TryGet "H2.Value=20000120195632.000000+000" { $d8.Value = "20000120195632.000000+000"; "ok" }
TryGet "H2.Value_after" { $d8.Value }
TryGet "H3.Value=20000120195632.000000" { $d8.Value = "20000120195632.000000"; "ok" }
TryGet "H3.Value_after" { $d8.Value }
TryGet "H4.Value=20001320195632.000000+000" { $d8.Value = "20001320195632.000000+000"; "ok" }
TryGet "H4.Value_after" { $d8.Value }
TryGet "H5.SetFileTime=abc,false" { $d8.SetFileTime("abc", $false); "ok" }

Write-Output "--- utc prop ---"
$d9 = New-Object -ComObject WbemScripting.SWbemDateTime
$d9.Value = "20000120195632.000000+000"
TryGet "I1.UTC=b4set" { $d9.UTC = -480; "ok" }
TryGet "I1.Value" { $d9.Value }
TryGet "I2.UTC" { $d9.UTC }
TryGet "I2.UTCSpecified" { $d9.UTCSpecified }
$d10 = New-Object -ComObject WbemScripting.SWbemDateTime
TryGet "J1.new.UTCSpecified" { $d10.UTCSpecified }
TryGet "J2.new.IsInterval" { $d10.IsInterval }
TryGet "J3.new.YearSpecified" { $d10.YearSpecified }
TryGet "J4.new.Value" { $d10.Value }
Write-Output "--- wildcard ---"
$d11 = New-Object -ComObject WbemScripting.SWbemDateTime
TryGet "K1.Value=2000********.000000+000" { $d11.Value = "2000********.000000+000"; "ok" }
TryGet "K2.Value" { $d11.Value }
TryGet "K3.YearSpecified" { $d11.YearSpecified }
TryGet "K4.GoGetVarDate" { $d11.GetVarDate($true) }
