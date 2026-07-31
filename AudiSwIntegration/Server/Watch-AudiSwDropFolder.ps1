# ==============================================================================
#  Collects jobs from the drop folder and runs them.               SCENARIO B
# ==============================================================================
#  Runs ON the server, as the service account, started by a scheduled task every
#  few minutes. Nothing connects in from outside.
#
#    .\Watch-AudiSwDropFolder.ps1 -DropFolder '\\server\SwIntegration-Inbox$'
#
#  THE IMPORTANT SECURITY POINT
#  ----------------------------
#  A job file is just a file. Anyone who can write to the folder could put any
#  name inside it, so the requester name written in the file is NOT trusted.
#  The requester is taken from the NTFS OWNER of the file, which Windows stamps
#  when the file is created and which the writer cannot forge.
#
#  In the live-connection scenario Windows states the caller directly. Here the
#  file owner is the equivalent, and it is what keeps the audit trail honest.
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DropFolder,
    [string]$EngineRoot = (Join-Path $PSScriptRoot 'Engine'),
    [int]$MaxJobsPerRun = 10,
    [switch]$DryRun
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path $EngineRoot 'AudiSwIntegration.ps1')

foreach ($sub in 'New', 'Working', 'Done', 'Failed') {
    $path = Join-Path $DropFolder $sub
    if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
}

$newFolder = Join-Path $DropFolder 'New'
$jobs = @(Get-ChildItem -LiteralPath $newFolder -Filter '*.json' -File -ErrorAction SilentlyContinue |
          Sort-Object CreationTimeUtc | Select-Object -First $MaxJobsPerRun)

if ($jobs.Count -eq 0) { Write-Verbose 'Nothing to collect.'; return }

foreach ($file in $jobs) {

    # --- who really asked: the file owner, not anything inside the file
    $requester = $null
    try { $requester = (Get-Acl -LiteralPath $file.FullName).Owner } catch { }
    if (-not $requester) {
        Move-Item -LiteralPath $file.FullName -Destination (Join-Path $DropFolder 'Failed') -Force
        Write-Warning "Could not establish the owner of $($file.Name) - refused."
        continue
    }

    # --- claim it, so a second run of the task cannot pick up the same job
    $working = Join-Path (Join-Path $DropFolder 'Working') $file.Name
    try { Move-Item -LiteralPath $file.FullName -Destination $working -Force }
    catch { Write-Verbose "$($file.Name) was already claimed."; continue }

    $outcome = 'Failed'
    $result  = $null
    try {
        $request = Get-Content -LiteralPath $working -Raw | ConvertFrom-Json

        foreach ($required in 'PackageName', 'EnvironmentCode', 'Action') {
            if (-not $request.PSObject.Properties[$required] -or -not $request.$required) {
                throw "The job file is missing '$required'."
            }
        }

        $plan = Get-AudiIntegrationPlan `
                    -PackageName     $request.PackageName `
                    -EnvironmentCode $request.EnvironmentCode `
                    -Requester       $requester `
                    -Rfc             $(if ($request.PSObject.Properties['Rfc']) { $request.Rfc } else { '' }) `
                    -LocalizedName        $(if ($request.PSObject.Properties['LocalizedName'])        { $request.LocalizedName }        else { '' }) `
                    -LocalizedDescription $(if ($request.PSObject.Properties['LocalizedDescription']) { $request.LocalizedDescription } else { '' })

        $wantsDryRun = $DryRun -or ($request.PSObject.Properties['DryRun'] -and $request.DryRun)

        $result = if ($request.Action -eq 'Remove') {
            Invoke-AudiSwRemoval     -Plan $plan -DryRun:$wantsDryRun
        } else {
            Invoke-AudiSwIntegration -Plan $plan -DryRun:$wantsDryRun
        }
        $outcome = if ($result.Ok) { 'Done' } else { 'Failed' }
    }
    catch {
        $result = [pscustomobject]@{ Ok = $false; Message = $_.Exception.Message; Steps = @()
                                     JobId = ''; Requester = $requester }
    }

    # --- write the answer back next to the job, then file it
    $answer = [pscustomobject]@{
        Completed = (Get-Date).ToString('o')
        Requester = $requester
        Outcome   = $outcome
        Ok        = $result.Ok
        Message   = $result.Message
        JobId     = $result.JobId
        Steps     = $result.Steps
    }
    $target = Join-Path (Join-Path $DropFolder $outcome) $file.Name
    try {
        $answer | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath ($target -replace '\.json$', '.result.json') -Encoding UTF8
        Move-Item -LiteralPath $working -Destination $target -Force
    }
    catch { Write-Warning "Could not file the finished job $($file.Name): $($_.Exception.Message)" }

    Write-Verbose "$($file.Name): $outcome - $($result.Message)"
}
