@echo off
setlocal

if "%~1"=="" goto usage
if "%~2"=="" goto usage

set AVA_API_BASE_URL=%~1
set AVA_WS_URL=%~2
set AVA_ANDROID_TARGET=%~3
set AVA_APP_VERSION=
set AVA_BUILD_NUMBER=

if "%AVA_ANDROID_TARGET%"=="" set AVA_ANDROID_TARGET=apk

for /f "tokens=1,2 delims=+" %%A in ('powershell.exe -NoProfile -Command "$m=Select-String -Path '%~dp0pubspec.yaml' -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?'; if($null -eq $m){exit 1}; $v=$m.Matches[0].Groups[1].Value; $b=$m.Matches[0].Groups[2].Value; if([string]::IsNullOrWhiteSpace($b)){$b='1'}; Write-Output ($v + '+' + $b)"') do (
  set AVA_APP_VERSION=%%A
  set AVA_BUILD_NUMBER=%%B
)

if "%AVA_APP_VERSION%"=="" exit /b 1

if /I "%AVA_ANDROID_TARGET%"=="appbundle" (
  flutter build appbundle --release ^
    --dart-define=AVA_API_BASE_URL=%AVA_API_BASE_URL% ^
    --dart-define=AVA_WS_URL=%AVA_WS_URL% ^
    --dart-define=AVA_APP_VERSION=%AVA_APP_VERSION% ^
    --dart-define=AVA_BUILD_NUMBER=%AVA_BUILD_NUMBER%
  exit /b %ERRORLEVEL%
)

if /I "%AVA_ANDROID_TARGET%"=="apk" (
  flutter build apk --release ^
    --dart-define=AVA_API_BASE_URL=%AVA_API_BASE_URL% ^
    --dart-define=AVA_WS_URL=%AVA_WS_URL% ^
    --dart-define=AVA_APP_VERSION=%AVA_APP_VERSION% ^
    --dart-define=AVA_BUILD_NUMBER=%AVA_BUILD_NUMBER%
  exit /b %ERRORLEVEL%
)

echo Unknown target: %AVA_ANDROID_TARGET%
echo Use apk or appbundle.
exit /b 1

:usage
echo Usage:
echo   build_android_release.cmd https://api.example.com wss://api.example.com/ws [apk^|appbundle]
exit /b 1
