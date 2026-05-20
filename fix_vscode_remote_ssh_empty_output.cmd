@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0fix_vscode_remote_ssh_empty_output.ps1"
pause
