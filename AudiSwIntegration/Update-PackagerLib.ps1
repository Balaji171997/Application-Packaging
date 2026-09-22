# ==============================================================================
#  Refreshes the packager window's copy of the shared files from the SCCM
#  server's engine.                                              (developers)
# ==============================================================================
#  The three folders - Packager, MiddleServer, SccmServer - are deployed to
#  three different machines, so each carries what it needs. The packager window
#  needs three of the engine's .ps1 files and its Config - and two copies of
#  anything drift apart, which is exactly how PCZ ended up holding INA's
#  security scope in the tool being replaced.
#
#  So there is ONE master - SccmServer\Engine - and this copies from it. Edit
#  there, run this, commit both. Never edit Packager\Lib or Packager\Config by
#  hand.
#
#    .\Update-PackagerLib.ps1            copy
#    .\Update-PackagerLib.ps1 -Check     report differences, change nothing
# ==============================================================================
[CmdletBinding()]
param([switch]$Check)

$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'SccmServer\Engine'
$cli = Join-Path $PSScriptRoot 'Packager'
$shared = 'Config.ps1', 'Runtime.ps1', 'Transport.ps1'

$differences = New-Object System.Collections.Generic.List[string]

foreach ($file in $shared) {
    $from = Join-Path $src "Src\$file"
    $to   = Join-Path $cli "Lib\$file"
    $same = (Test-Path -LiteralPath $to) -and
            ((Get-FileHash $from).Hash -eq (Get-FileHash $to).Hash)
    if (-not $same) {
        $differences.Add("Lib\$file") | Out-Null
        if (-not $Check) { Copy-Item $from $to -Force }
    }
}

# Environments\ is deliberately NOT copied. Those files describe SCCM topology -
# collections, security scopes, console folders, distribution point groups - and
# a packager machine has no business holding them. The window works the
# environment list out from the drop folder and the package name instead.
foreach ($from in @(Get-ChildItem (Join-Path $src 'Config') -File)) {
    $relative = $from.FullName.Substring((Join-Path $src 'Config').Length).TrimStart('\')
    $to = Join-Path (Join-Path $cli 'Config') $relative
    $same = (Test-Path -LiteralPath $to) -and
            ((Get-FileHash $from.FullName).Hash -eq (Get-FileHash $to).Hash)
    if (-not $same) {
        $differences.Add("Config\$relative") | Out-Null
        if (-not $Check) {
            $parent = Split-Path -Parent $to
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item $from.FullName $to -Force
        }
    }
}

if ($differences.Count -eq 0) { Write-Host 'The packager copy is up to date.' -ForegroundColor Green; exit 0 }
if ($Check) {
    Write-Host "The packager copy is STALE - $($differences.Count) file(s) differ:" -ForegroundColor Red
    foreach ($d in $differences) { Write-Host "  $d" }
    Write-Host 'Run Update-PackagerLib.ps1 to refresh it.'
    exit 1
}
Write-Host "Refreshed $($differences.Count) file(s) in the packager copy." -ForegroundColor Green
foreach ($d in $differences) { Write-Host "  $d" }
exit 0
