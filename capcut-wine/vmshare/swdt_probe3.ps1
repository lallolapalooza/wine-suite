$ErrorActionPreference = "Continue"
function T($label, $block) { try { $v = & $block; "$label OK [$v]" } catch { "$label EXC hr=[0x{0:X8}] [{1}]" -f $_.Exception.HResult, $_.Exception.Message } }
$d = New-Object -ComObject WbemScripting.SWbemDateTime
$d.Value = "20000120195632.000000+000"
"R1 Year=9999:   " + (T "" { $d.Year = 9999; $d.Value })
"R2 Year=10000:  " + (T "" { $d.Year = 10000; $d.Value })
"R3 Year=0:      " + (T "" { $d.Year = 0; $d.Value })
"R4 Year=-1:     " + (T "" { $d.Year = -1; $d.Value })
$m = New-Object -ComObject WbemScripting.SWbemDateTime
"R5 Month=12:    " + (T "" { $m.Month = 12; $m.Value })
"R6 Month=13:    " + (T "" { $m.Month = 13; $m.Value })
"R7 Month=0:     " + (T "" { $m.Month = 0; $m.Value })
"R8 Hours=23:    " + (T "" { $m.Hours = 23; $m.Value })
"R9 Hours=24:    " + (T "" { $m.Hours = 24; $m.Value })
"R10 Minutes=60: " + (T "" { $m.Minutes = 60; $m.Value })
"R11 Seconds=60: " + (T "" { $m.Seconds = 60; $m.Value })
"R12 us=999999:  " + (T "" { $m.Microseconds = 999999; $m.Value })
"R13 us=1000000: " + (T "" { $m.Microseconds = 1000000; $m.Value })
$u = New-Object -ComObject WbemScripting.SWbemDateTime
"R14 utc=999:    " + (T "" { $u.UTC = 999; $u.Value })
"R15 utc=1000:   " + (T "" { $u.UTC = 1000; $u.Value })
"R16 utc=-999:   " + (T "" { $u.UTC = -999; $u.Value })
"R17 utc=-1000:  " + (T "" { $u.UTC = -1000; $u.Value })
"R18 utc=1440:   " + (T "" { $u.UTC = 1440; $u.Value })
$i = New-Object -ComObject WbemScripting.SWbemDateTime
$i.IsInterval = $true
"R19 int Day=99999999:  " + (T "" { $i.Day = 99999999; $i.Value })
"R20 int Day=100000000: " + (T "" { $i.Day = 100000000; $i.Value })
"R21 int Day=0:         " + (T "" { $i.Day = 0; $i.Value })
$w = New-Object -ComObject WbemScripting.SWbemDateTime
"R22 set wildcard Value: " + (T "" { $w.Value = "2000**********000000.000000+000"; $w.Value })
"R23 wildcard fields: " + (T "" { $w.YearSpecified.ToString() + "/" + $w.MonthSpecified.ToString() + "/" + $w.SecondsSpecified.ToString() })
$e = New-Object -ComObject WbemScripting.SWbemDateTime
"R24 SetFileTime empty: " + (T "" { $e.SetFileTime("", $false); $e.Value })
"R25 SetVarDate 0: " + (T "" { $e.SetVarDate(0.0, $false); $e.Value })
"R26 set Year on interval: " + (T "" { $i.Year = 7; $i.Value })
