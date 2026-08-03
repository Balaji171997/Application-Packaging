# ==============================================================================
#  Audi SCCM Integration Tool - entry point
# ==============================================================================
#  Dot-source this one file to get the whole tool:
#
#      . <path>\AudiSwIntegration.ps1
#
#  Layout
#    Config\      Environment.xsd, Defaults.xml, Environments\<CODE>.xml
#    Src\         Config.ps1, Runtime.ps1, Transport.ps1, Sccm.ps1
#    Tests\       Test-Config.ps1, Test-Sccm.ps1, Test-Transport.ps1
#
#  Load order matters: Config first (everything else reads Defaults.xml through
#  it), then Runtime, then Transport, then Sccm.
# ==============================================================================

Set-StrictMode -Version 2.0

foreach ($file in 'Config.ps1', 'Runtime.ps1', 'Transport.ps1', 'Sccm.ps1') {
    $path = Join-Path (Join-Path $PSScriptRoot 'Src') $file
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing tool file: $path" }
    . $path
}
