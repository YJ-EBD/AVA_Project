@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tooling\build_windows_installer.ps1" %*
exit /b %ERRORLEVEL%
