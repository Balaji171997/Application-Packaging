# ==============================================================================
#  Audi SCCM Integration Tool - entry point
# ==============================================================================
#  Dot-source this one file to get the whole tool:
#
#      . <path>\AudiSwIntegration.ps1
#
#  Layout
#    Config\   Environment.xsd, Defaults.xml, Environments\<CODE>.xml
#    Src\      one file per concern, in the order they are loaded:
#
#      Config.ps1        reads and validates the config; reads a package folder;
#                        turns a package + an environment into a PLAN
#      Runtime.ps1       logging, retry, the package lock, the job record
#      Transport.ps1     the drop folder - job files out, result files back
#      Provider.ps1      every call to a real site, and the dry-run stand-in
#      Steps.ps1         what each step does, and what it depends on
#      Inspect.ps1       reading what is on the site, and applying ticked changes
#      Preflight.ps1     the checks made before anything is created
#      Orchestrator.ps1  Integrate, Modify, Remove - order, rollback, results
#
#    Tests\    Test-Config.ps1, Test-Sccm.ps1, Test-Transport.ps1
#
#  Load order matters. Config first, because everything else reads Defaults.xml
#  through it. Provider before the files that call it. Orchestrator last, because
#  it drives all of them.
# ==============================================================================

Set-StrictMode -Version 2.0

foreach ($file in 'Config.ps1', 'Runtime.ps1', 'Transport.ps1',
                  'Provider.ps1', 'Steps.ps1', 'Inspect.ps1', 'Preflight.ps1', 'Orchestrator.ps1') {
    $path = Join-Path (Join-Path $PSScriptRoot 'Src') $file
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing tool file: $path" }
    . $path
}
