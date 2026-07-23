@echo off
setlocal
pushd "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File ".\IntuneApps.ps1" %*
popd
