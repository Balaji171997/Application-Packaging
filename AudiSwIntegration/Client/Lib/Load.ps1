# ==============================================================================
#  Audi SCCM Integration Tool - what the PACKAGER WINDOW loads
# ==============================================================================
#  Three files, and deliberately no more:
#
#    Config.ps1     reads Defaults.xml and the environment files, parses the
#                   package name, and pulls values out of the PSADT script and
#                   the install instruction document
#    Runtime.ps1    logging the two below use
#    Transport.ps1  writes the job file into the drop folder, reads results and
#                   history back out of it
#
#  NOT loaded, and not present in this folder at all:
#
#    Provider.ps1 Steps.ps1 Inspect.ps1 Preflight.ps1 Orchestrator.ps1
#
#  Those are the SCCM side. The window never connects to a site, holds no SCCM
#  rights and needs no ConfigMgr console, so it must not even be able to call
#  them - a window that CAN reach SCCM will eventually be made to.
#
#  Test-Client.ps1 asserts this, so the boundary cannot quietly erode.
# ==============================================================================

Set-StrictMode -Version 2.0

foreach ($file in 'Config.ps1', 'Runtime.ps1', 'Transport.ps1') {
    $path = Join-Path $PSScriptRoot $file
    if (-not (Test-Path -LiteralPath $path)) {
        throw "The window is missing $file. Copy the whole Client folder, not just the script."
    }
    . $path
}