@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Wallpaper.ps1" -Mode Run
if errorlevel 1 echo Operation failed. See data\errors.log.
pause
