# Runs every test suite and returns a non-zero exit code if any of them fail.
[CmdletBinding()]
param([switch]$Quiet)

$ErrorActionPreference = 'Stop'
$failed = 0

foreach ($suite in (Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'Test-*.ps1' -File | Sort-Object Name)) {
    & $suite.FullName -Quiet:$Quiet
    if ($LASTEXITCODE -ne 0) { $failed++ }
}

if ($failed -eq 0) { Write-Host 'All suites passed.' -ForegroundColor Green }
else               { Write-Host "$failed suite(s) FAILED." -ForegroundColor Red }
exit $(if ($failed -eq 0) { 0 } else { 1 })
