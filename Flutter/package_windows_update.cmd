@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tooling\package_windows_update.ps1" %*
