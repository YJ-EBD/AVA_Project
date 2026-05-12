@echo off
setlocal

for %%I in ("%~dp0..") do set "PROJECT_ROOT=%%~fI"

set "JAVA_HOME=C:\Program Files\Microsoft\jdk-21.0.11.10-hotspot"
set "ANDROID_SDK_ROOT=%PROJECT_ROOT%\.tools\android-sdk"
set "ANDROID_HOME=%ANDROID_SDK_ROOT%"
set "PATH=%PROJECT_ROOT%\.tools\flutter\bin;%ANDROID_SDK_ROOT%\platform-tools;%ANDROID_SDK_ROOT%\cmdline-tools\latest\bin;%JAVA_HOME%\bin;C:\Program Files\Git\cmd;%PATH%"

cd /d "%~dp0"
flutter.bat %*
