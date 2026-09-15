@echo off
setlocal
pushd "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File ".\IntuneAppReport.ps1" %*
popd