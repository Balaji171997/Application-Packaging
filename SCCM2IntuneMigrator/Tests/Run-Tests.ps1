# Runs the whole offline suite. Nothing here touches SCCM, Entra or Intune - SCCM reads and every
# Graph call are stubbed, so this is safe to run any time, on any machine.
#
#   powershell -STA -ExecutionPolicy Bypass -File "Tests\Run-Tests.ps1"
#
# -STA is required: one suite builds the real WPF window.
[CmdletBinding()]
param([switch]$KeepWorkFiles)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$tool = Split-Path -Parent $here

Write-Host "SCCM to Intune migrator - offline test suite" -ForegroundColor Cyan
Write-Host "Tool: $tool`n"

# --- 0. the script must parse -----------------------------------------------------------------
$script = Join-Path $tool 'SCCM2IntuneMigrator.ps1'
$perr = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$null, [ref]$perr)
if ($perr -and $perr.Count) {
    Write-Host "PARSE FAILED:" -ForegroundColor Red
    $perr | Select-Object -First 10 | ForEach-Object { Write-Host "  line $($_.Extent.StartLineNumber): $($_.Message)" -ForegroundColor Red }
    exit 1
}
Write-Host "  PASS  the script parses" -ForegroundColor Green

# --- 1. fixtures ------------------------------------------------------------------------------
$fix = Join-Path $here 'fixtures'
& (Join-Path $here 'Build-TestFixtures.ps1') -Root $fix | Out-Null
Write-Host "  PASS  fixtures built" -ForegroundColor Green

# --- 2. the suites ----------------------------------------------------------------------------
$totalPass = 2; $totalFail = 0; $failedSuites = @()
foreach ($suite in 'Test-UiWiring.ps1', 'Test-Engine.ps1', 'Test-Orchestration.ps1', 'Test-MultiApp.ps1', 'Test-Gui.ps1') {
    Write-Host "`n---------- $suite ----------" -ForegroundColor Cyan
    $out = Join-Path $env:TEMP "mig_$([guid]::NewGuid().ToString('N').Substring(0,8)).txt"
    $err = "$out.err"
    # each suite runs in its own STA process: the window suite needs a clean apartment, and a
    # crash in one suite must not take the runner with it
    $p = Start-Process powershell -ArgumentList '-STA','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $here $suite) `
                       -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    $lines = @(Get-Content -LiteralPath $out -ErrorAction SilentlyContinue)
    foreach ($l in ($lines | Where-Object { $_ -match '^\s*(PASS|FAIL)\s|^PASSED\s|^===' })) { Write-Host $l }
    $summary = $lines | Where-Object { $_ -match '^PASSED\s+(\d+)\s+FAILED\s+(\d+)' } | Select-Object -Last 1
    if ($summary -match '^PASSED\s+(\d+)\s+FAILED\s+(\d+)') {
        $totalPass += [int]$Matches[1]; $totalFail += [int]$Matches[2]
    }
    if ($p.ExitCode -ne 0) {
        $failedSuites += $suite
        $e = @(Get-Content -LiteralPath $err -ErrorAction SilentlyContinue | Select-Object -First 8)
        if ($e) { Write-Host "  stderr:" -ForegroundColor Red; $e | ForEach-Object { Write-Host "    $_" -ForegroundColor Red } }
    }
    Remove-Item -LiteralPath $out, $err -Force -ErrorAction SilentlyContinue
}

# --- 3. tidy up -------------------------------------------------------------------------------
if (-not $KeepWorkFiles) {
    foreach ($pat in 'fixtures', 'work_v3', 'work_v4', 'report_test', 'run_*', 'multi_*', '_engine_only*.ps1', '_engine_multi.ps1', '_gui_test.ps1') {
        Get-ChildItem -Path $here -Filter $pat -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host ("=" * 52)
if ($totalFail -eq 0 -and $failedSuites.Count -eq 0) {
    Write-Host "ALL GREEN - $totalPass checks passed" -ForegroundColor Green
    exit 0
}
Write-Host "$totalPass passed, $totalFail FAILED$(if ($failedSuites.Count) { "  (suites with errors: $($failedSuites -join ', '))" })" -ForegroundColor Red
exit 1
