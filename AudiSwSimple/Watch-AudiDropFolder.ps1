<#
    THE SCHEDULED TASK. Runs on the Script Runner as the service account, every
    few minutes. One pass: take whatever is waiting, run it, write the results,
    exit. It does not loop - the task scheduler is the loop.

        .\Watch-AudiDropFolder.ps1 -Environment II1 -DryRun     # rehearse, touch nothing
        .\Watch-AudiDropFolder.ps1 -Environment II1             # do it

    -DryRun leaves the drop folder alone as well as the site: the jobs stay in
    \New, so the same rehearsal can be run again and then done for real.

    Register it once:

        $action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
                     -Argument '-NoProfile -ExecutionPolicy Bypass -File "D:\AudiSw\Watch-AudiDropFolder.ps1" -Environment II1'
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
                     -RepetitionInterval (New-TimeSpan -Minutes 5)
        Register-ScheduledTask -TaskName 'Audi SW Integration II1' -Action $action -Trigger $trigger `
                     -User 'AUDI\svc-swint$' -LogonType Password

    A job moves New -> Working -> Done or Failed, so two overlapping passes can
    never run the same job twice.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Environment,

    # Rehearse: run every step through the engine's -WhatIf and leave both the
    # site and the drop folder exactly as they were. NOT PowerShell's own
    # -WhatIf, which would also stop this script moving its own job files - the
    # job would then be reported on and left in \New, half handled.
    [switch]$DryRun,

    [int]$MaxJobsPerRun = 10
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$environmentFile = Join-Path $PSScriptRoot "Environments\$Environment.psd1"
if (-not (Test-Path -LiteralPath $environmentFile)) { throw "No environment file for '$Environment'." }
$config = Import-PowerShellDataFile -LiteralPath $environmentFile

$folders = @{}
foreach ($name in 'New', 'Working', 'Done', 'Failed') {
    $folders[$name] = Join-Path $config.DropFolder $name
    if (-not (Test-Path -LiteralPath $folders[$name])) { New-Item -ItemType Directory -Path $folders[$name] -Force | Out-Null }
}

$jobs = @(Get-ChildItem -LiteralPath $folders.New -Filter '*.json' -File -ErrorAction SilentlyContinue |
          Sort-Object CreationTimeUtc | Select-Object -First $MaxJobsPerRun)

if ($jobs.Count -eq 0) { Write-Verbose "Nothing waiting in $($folders.New)."; return }
Write-Host "$($jobs.Count) job(s) waiting in $($config.SiteCode)."

foreach ($file in $jobs) {

    # A rehearsal reads the job where it lies and changes nothing at all.
    if ($DryRun) {
        try   { & (Join-Path $PSScriptRoot 'Invoke-AudiIntegration.ps1') -JobFile $file.FullName -WhatIf | Out-Null }
        catch { Write-Host "  would fail: $($_.Exception.Message)" -ForegroundColor Red }
        continue
    }

    # Claim it first: moving it out of \New means a second pass cannot take it.
    $working = Join-Path $folders.Working $file.Name
    try { Move-Item -LiteralPath $file.FullName -Destination $working -Force }
    catch { Write-Verbose "$($file.Name) was already claimed."; continue }

    $result = $null
    try {
        $job = Get-Content -LiteralPath $working -Raw | ConvertFrom-Json

        # One drop folder serves one environment. A job for another one has been
        # put here by mistake, and running it would act on a site this collector
        # was never pointed at.
        if ($job.Environment -ne $config.SiteCode) {
            throw "This job is for $($job.Environment) but it is in $($config.SiteCode)'s drop folder. Nothing has been done to either site."
        }

        $engine = if ($job.Action -eq 'Remove') { 'Remove-AudiIntegration.ps1' } else { 'Invoke-AudiIntegration.ps1' }
        $result = & (Join-Path $PSScriptRoot $engine) -JobFile $working
    }
    catch {
        $reason = [string]$_.Exception.Message
        if (-not $reason) { $reason = 'Failed with no message.' }
        $result = [pscustomobject]@{ Ok = $false; Message = $reason; Steps = @(); RolledBack = @() }
    }

    # File the job and its result together, so the pair is always in one place.
    $target = if ($result.Ok) { $folders.Done } else { $folders.Failed }

    $record = [ordered]@{
        Outcome    = $(if ($result.Ok) { 'Succeeded' } else { 'Failed' })
        Completed  = (Get-Date).ToString('o')
        ExecutedBy = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        Message    = $result.Message
        Steps      = $result.Steps
        RolledBack = $result.RolledBack
    }
    $record | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $target ($file.BaseName + '.result.json')) -Encoding UTF8

    Move-Item -LiteralPath $working -Destination (Join-Path $target $file.Name) -Force

    Write-Host ("  {0}  {1}" -f $record.Outcome.PadRight(9), $result.Message) `
        -ForegroundColor $(if ($result.Ok) { 'Green' } else { 'Red' })
}
