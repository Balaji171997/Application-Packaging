##############################################################
# Package Builder - launcher
# Run this file to start the tool. It re-launches itself in an
# STA PowerShell (WPF requirement) if needed and starts the GUI.
# Usage:  powershell -ExecutionPolicy Bypass -File PackageBuilder.ps1
##############################################################
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    # WPF needs STA; relaunch once with the right switches.
    Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',"`"$root\GUI.ps1`"")
    return
}
& "$root\GUI.ps1"
