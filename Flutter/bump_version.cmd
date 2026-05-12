@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tooling\bump_version.ps1" %*
