@echo off
rem Stage-1 loader, run from the guest's Run dialog. It exists so that the *only* thing that ever has to be
rem typed at the guest keyboard is the Run line that fetches this file; every later task is then just an edit
rem of g.bat on the host followed by Win+R <Enter> (which re-runs the history entry).
rem
rem host -> guest : g.bat      (the task)
rem guest -> host : g_out.txt  (its output)
set U=http://192.168.122.1:8000
set L=C:\Users\adsf\g_out.txt
curl.exe -s -o C:\Users\adsf\g.bat %U%/g.bat
echo ==== stage1 %DATE% %TIME% ==== > "%L%"
echo loader rc=%ERRORLEVEL% >> "%L%"
call C:\Users\adsf\g.bat >> "%L%" 2>&1
echo ==== stage1 done rc=%ERRORLEVEL% ==== >> "%L%"
curl.exe -s -T "%L%" %U%/g_out.txt
