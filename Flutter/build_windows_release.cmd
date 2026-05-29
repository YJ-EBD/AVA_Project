@echo off
setlocal

if "%~1"=="" goto usage
if "%~2"=="" goto usage

set AVA_API_BASE_URL=%~1
set AVA_WS_URL=%~2
set AVA_APP_VERSION=
set AVA_BUILD_NUMBER=

for /f "tokens=1,2 delims=+" %%A in ('powershell.exe -NoProfile -Command "$m=Select-String -Path '%~dp0pubspec.yaml' -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?'; if($null -eq $m){exit 1}; $v=$m.Matches[0].Groups[1].Value; $b=$m.Matches[0].Groups[2].Value; if([string]::IsNullOrWhiteSpace($b)){$b='1'}; Write-Output ($v + '+' + $b)"') do (
  set AVA_APP_VERSION=%%A
  set AVA_BUILD_NUMBER=%%B
)

if "%AVA_APP_VERSION%"=="" exit /b 1

call "%~dp0flutter_local.cmd" pub get
if errorlevel 1 exit /b %ERRORLEVEL%

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tooling\ensure_windows_plugin_junctions.ps1"
if errorlevel 1 exit /b %ERRORLEVEL%

call "%~dp0flutter_local.cmd" build windows --release --no-pub ^
  --dart-define=AVA_API_BASE_URL=%AVA_API_BASE_URL% ^
  --dart-define=AVA_WS_URL=%AVA_WS_URL% ^
  --dart-define=AVA_APP_VERSION=%AVA_APP_VERSION% ^
  --dart-define=AVA_BUILD_NUMBER=%AVA_BUILD_NUMBER%

exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   build_windows_release.cmd https://api.example.com wss://api.example.com/ws
exit /b 1
