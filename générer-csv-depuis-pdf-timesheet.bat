@echo off
C:\Cygwin\bin\mintty.exe -t "%~nx0 (%~dp0)" -s 160,40 -h error -e /bin/bash -l -c """$(cygpath ""%~dpn0.sh"")"""
