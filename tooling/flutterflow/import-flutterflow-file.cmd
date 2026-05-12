@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0import-flutterflow-file.ps1" %*
