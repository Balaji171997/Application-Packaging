@echo off
rem Packaging Agent executor - double-click to open the agent window, or drop an order folder onto this file.
rem Text mode instead:  Run-PackagingAgent.cmd /console
setlocal
set "HERE=%~dp0"
if /I "%~1"=="/console" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%HERE%Start-PackagingAgent.ps1" -Console
) else if "%~1"=="" (
  start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%HERE%Start-PackagingAgent.ps1"
) else (
  start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%HERE%Start-PackagingAgent.ps1" -Folder "%~1"
)
endlocal
