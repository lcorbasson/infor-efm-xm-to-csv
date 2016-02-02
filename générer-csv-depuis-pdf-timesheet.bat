@echo off
C:\Cygwin\bin\mintty.exe -t "%~nx0 (%~dp0)" -e /bin/bash -l -c """$(cygpath ""%~dpn0.sh"")""; echo 'Appuyez sur Entrée pour continuer...'; read a"
