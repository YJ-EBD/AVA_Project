@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0stop_azoom_sfu.ps1" %*
