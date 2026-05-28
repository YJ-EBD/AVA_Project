@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ava_server_control.ps1" restart %*
