@echo off
cd /d "%~dp0"
py -3.11 -u "%~dp0tools\build_windows.py"
if errorlevel 1 echo Build failed. See last-apk-build-error.txt in this folder.
pause
