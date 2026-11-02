@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0diagnose-pos.ps1" -AppDirectory "%~dp0."
pause
