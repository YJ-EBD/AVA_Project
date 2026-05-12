@echo off
setlocal

if "%~1"=="" goto usage
if "%~2"=="" goto usage

set AVA_API_BASE_URL=%~1
set AVA_WS_URL=%~2
set AVA_ANDROID_TARGET=%~3

if "%AVA_ANDROID_TARGET%"=="" set AVA_ANDROID_TARGET=apk

if /I "%AVA_ANDROID_TARGET%"=="appbundle" (
  flutter build appbundle --release ^
    --dart-define=AVA_API_BASE_URL=%AVA_API_BASE_URL% ^
    --dart-define=AVA_WS_URL=%AVA_WS_URL%
  exit /b %ERRORLEVEL%
)

if /I "%AVA_ANDROID_TARGET%"=="apk" (
  flutter build apk --release ^
    --dart-define=AVA_API_BASE_URL=%AVA_API_BASE_URL% ^
    --dart-define=AVA_WS_URL=%AVA_WS_URL%
  exit /b %ERRORLEVEL%
)

echo Unknown target: %AVA_ANDROID_TARGET%
echo Use apk or appbundle.
exit /b 1

:usage
echo Usage:
echo   build_android_release.cmd https://api.example.com wss://api.example.com/ws [apk^|appbundle]
exit /b 1
