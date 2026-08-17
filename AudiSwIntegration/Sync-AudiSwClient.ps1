# ==============================================================================
#  Refreshes the client's copy of the shared files from the server's.
# ==============================================================================
#  Client and Server are deployed separately, so each carries what it needs.
#  That means two copies of three .ps1 files and of Config - and two copies of
#  anything drift apart, which is exactly how PCZ ended up holding INA's
#  security scope in the tool being replaced.
#
#  So there is ONE master - Server\Engine - and this copies from it. Edit there,
#  run this, commit both. Never edit Client\Lib or Client\Config by hand.
#
#    .\Sync-AudiSwClient.ps1            copy
#    .\Sync-AudiSwClient.ps1 -Check     report differences, change nothing
# ==============================================================================
[CmdletBinding()]
param([switch]$Check)

$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'Server\Engine'
$cli = Join-Path $PSScriptRoot 'Client'
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

if ($differences.Count -eq 0) { Write-Host 'The client copy is up to date.' -ForegroundColor Green; exit 0 }
if ($Check) {
    Write-Host "The client copy is STALE - $($differences.Count) file(s) differ:" -ForegroundColor Red
    foreach ($d in $differences) { Write-Host "  $d" }
    Write-Host 'Run Sync-AudiSwClient.ps1 to refresh it.'
    exit 1
}
Write-Host "Refreshed $($differences.Count) file(s) in the client copy." -ForegroundColor Green
foreach ($d in $differences) { Write-Host "  $d" }
exit 0