# ==============================================================================
#  Audi SCCM Integration Tool - SANDBOX
# ==============================================================================
#  Runs the COMPLETE flow on one machine, with no server, no share, no SCCM and
#  no rights of any kind. For trying the tool out and for demonstrating it.
#
#      .\Tools\Start-AudiSwSandbox.ps1
#
#  What it does:
#    1. makes a drop folder under %LOCALAPPDATA%\AudiSwSandbox
#    2. builds a realistic sample package to read, if one is not there already
#    3. starts the collector in the background, polling every few seconds -
#       this stands in for the scheduled task on the Script Runner
#    4. opens the packager window pointed at that folder
#    5. stops the collector when the window closes
#
#  So pressing Integrate really does write a job file, the collector really does
#  pick it up and run it, and a real result file really does come back. The only
#  thing faked is SCCM itself, which runs through the dry-run provider.
#
#  ASCII only.
# ==============================================================================

[CmdletBinding()]
param(
    [string]$Root = (Join-Path $env:LOCALAPPDATA 'AudiSwSandbox'),
    [int]$PollSeconds = 4,
    [switch]$KeepFolder
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$toolRoot   = Split-Path -Parent $PSScriptRoot
$engineRoot = Join-Path $toolRoot 'Server\Engine'
$client     = Join-Path $toolRoot 'Client\Start-AudiSwClient.ps1'
$watcher    = Join-Path $toolRoot 'Server\Watch-AudiSwDropFolder.ps1'

foreach ($p in @($engineRoot, $client, $watcher)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Not found: $p. Run this from inside the tool folder." }
}

. (Join-Path $engineRoot 'AudiSwIntegration.ps1')

$drop     = Join-Path $Root 'DropFolder'
$packages = Join-Path $Root 'Packages'
$null = Initialize-AudiDropFolder -DropFolder $drop
if (-not (Test-Path -LiteralPath $packages)) { New-Item -ItemType Directory -Path $packages -Force | Out-Null }

# ---------------------------------------------------------- a sample package
# A real PSADT v4 script and a real .docx, so "Read details" has something true
# to find rather than values this script planted into the window.
$sample = (& (Join-Path $PSScriptRoot 'New-AudiSwSamplePackage.ps1') -Path $packages).Path

# ------------------------------------------------------------ the collector
# Stands in for the scheduled task on the Script Runner. Same script, same
# arguments - only the trigger is different.
$collector = Start-Job -Name 'AudiSwSandboxCollector' -ScriptBlock {
    param($watcher, $drop, $engineRoot, $poll)
    while ($true) {
        try { & $watcher -DropFolder $drop -EngineRoot $engineRoot -Verbose 4>&1 }
        catch { "collector error: $($_.Exception.Message)" }
        Start-Sleep -Seconds $poll
    }
} -ArgumentList $watcher, $drop, $engineRoot, $PollSeconds

Write-Host ''
Write-Host '  Audi SCCM Integration Tool - sandbox' -ForegroundColor Cyan
Write-Host ''
Write-Host "  drop folder     $drop"
Write-Host "  sample package  $sample"
Write-Host "  collector       running in the background, every $PollSeconds seconds"
Write-Host ''
Write-Host '  In the window: Browse to the sample package, press Read details,' -ForegroundColor Gray
Write-Host '  put anything in RFC number, then press Integrate.' -ForegroundColor Gray
Write-Host ''
Write-Host '  Close the window to stop.' -ForegroundColor Gray
Write-Host ''

try {
    & $client -EnvironmentCode 'ICZ' -DropFolder $drop
}
finally {
    Stop-Job   -Job $collector -ErrorAction SilentlyContinue
    Receive-Job -Job $collector -ErrorAction SilentlyContinue | Out-Null
    Remove-Job -Job $collector -Force -ErrorAction SilentlyContinue

    Write-Host ''
    foreach ($state in 'Done','Failed') {
        $files = @(Get-ChildItem (Join-Path $drop $state) -Filter '*.result.xml' -ErrorAction SilentlyContinue)
        Write-Host ("  {0,-7} {1} result file(s)" -f $state, $files.Count)
    }
    Write-Host ''
    Write-Host "  Everything is kept in $Root"
    if (-not $KeepFolder) { Write-Host '  Delete that folder to start clean.' -ForegroundColor Gray }
    Write-Host ''
}
