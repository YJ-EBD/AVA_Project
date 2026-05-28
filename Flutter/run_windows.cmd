@echo off
setlocal

call "%~dp0flutter_local.cmd" pub get
if errorlevel 1 exit /b %ERRORLEVEL%

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tooling\ensure_windows_plugin_junctions.ps1"
if errorlevel 1 exit /b %ERRORLEVEL%

call "%~dp0flutter_local.cmd" run --no-pub -d windows %*
