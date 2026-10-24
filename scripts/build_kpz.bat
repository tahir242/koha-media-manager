@echo off
rem Build MediaManager.kpz in the repository root (Windows). Runs build_kpz.ps1,
rem so it works without changing the PowerShell execution policy.
rem Usage: scripts\build_kpz.bat [OutputName.kpz]
setlocal
if "%~1"=="" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_kpz.ps1"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_kpz.ps1" -OutputName "%~1"
)
set "status=%errorlevel%"
if not "%status%"=="0" echo Build failed.
rem Keep the window open when started by double-click so the result can be read.
rem Explorer starts: cmd.exe /c ""<full path>.bat" " (two quotes after /c).
echo(%cmdcmdline%| findstr /i /c:"/c \"\"" >nul && pause
exit /b %status%
