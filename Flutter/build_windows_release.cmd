@echo off
setlocal

if "%~1"=="" goto usage
if "%~2"=="" goto usage

set AVA_API_BASE_URL=%~1
set AVA_WS_URL=%~2

call "%~dp0flutter_local.cmd" build windows --release ^
  --dart-define=AVA_API_BASE_URL=%AVA_API_BASE_URL% ^
  --dart-define=AVA_WS_URL=%AVA_WS_URL%

exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   build_windows_release.cmd https://api.example.com wss://api.example.com/ws
exit /b 1
