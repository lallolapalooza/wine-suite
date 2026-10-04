$out = "C:\Users\adsf\ved_search.txt"
"=== dir /s /b C:\ve_detector* ===" | Set-Content $out
cmd /c "dir /s /b C:\ve_detector* 2>nul" | Add-Content $out
"=== Get-ChildItem C:\ -Recurse -Filter *ve_detector* ===" | Add-Content $out
Get-ChildItem C:\ -Recurse -Force -ErrorAction SilentlyContinue -Filter "*ve_detector*" | Select-Object -First 20 -Expand FullName | Add-Content $out
"=== DONE ===" | Add-Content $out
& curl.exe -s -T $out http://192.168.122.1:8000/ved_search.txt
