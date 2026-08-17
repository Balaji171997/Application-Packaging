# ==============================================================================
#  Collects jobs from the drop folder and runs them.               FLOW 2
# ==============================================================================
#  Runs ON the server, as the shared account, started by a scheduled task every
#  few minutes. Nothing connects inward.
#
#    .\Watch-AudiSwDropFolder.ps1 -DropFolder '\\server\SwIntegration-Inbox$'
#    .\Watch-AudiSwDropFolder.ps1 -DropFolder '...' -DryRun -Verbose
#
#  THE IDENTITY RULE - NO PERSON REACHES THIS SERVER
#  -------------------------------------------------
#  Audi's requirement: no real person's name may appear on the SCCM side. This
#  script therefore never establishes who asked. It does not read the job
#  file's NTFS owner, and it writes no personal name to the log, the job record
#  or the result. Everything is keyed by JOB ID and RFC NUMBER, and Audi's
#  change system holds the link from RFC to person.
#
#  The packager still owns the file they wrote into \New, because Windows
#  stamps that at creation. So the archive copy is RE-WRITTEN by this script,
#  running as the service account, and the original is deleted - leaving no
#  person-owned file behind in the secure zone.
#
#  Claiming: a job is MOVED to \Working before it runs, so two overlapping runs
#  of the task can never process the same job twice.
#
#  ASCII only.
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

# A previous pass in this session may have left the location on a CMSite drive,
# where Get-ChildItem -Filter throws. Come back to the filesystem first.
Restore-AudiFileSystemLocation

$executor = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

# ONE ROOT, EVERY ENVIRONMENT.
#
# -DropFolder is the root the window writes to, not one environment's queue.
# Underneath it is a folder per environment, each with its own New/Working/
# Done/Failed, and a folder per package inside those:
#
#     <root>\ICZ\New\INA_ETAS_INCA_x64_...\INA_ETAS_..._<jobid>.xml
#
# So one watcher serves every environment, and adding an environment needs no
# change here - the folder appears the first time somebody submits for it.
#
# Every environment configured is looked at, plus any folder already present in
# the root. A folder for an environment this server does not know about is left
# alone rather than guessed at.
$configuredCodes = @(Get-AudiEnvironmentCode)
$presentCodes    = @()
if (Test-Path -LiteralPath $DropFolder) {
    $presentCodes = @(Get-ChildItem -LiteralPath $DropFolder -Directory -ErrorAction SilentlyContinue |
                      ForEach-Object { $_.Name })
}
$codes = @($configuredCodes | Where-Object { $_ }) + @($presentCodes | Where-Object { $configuredCodes -contains $_ })
$codes = @($codes | Sort-Object -Unique)

$unknown = @($presentCodes | Where-Object { $configuredCodes -notcontains $_ })
foreach ($u in $unknown) {
    Write-Verbose "Ignoring '$u' - not an environment this server has a config file for."
}

# Collect across all of them, oldest first, so a busy environment cannot starve
# a quiet one of its turn.
$queue = New-Object System.Collections.Generic.List[object]
foreach ($code in $codes) {
    $envPaths = Get-AudiDropFolderPath -DropFolder $DropFolder -EnvironmentCode $code
    if (-not (Test-Path -LiteralPath $envPaths.New)) { continue }
    foreach ($f in @(Get-ChildItem -LiteralPath $envPaths.New -Filter '*.xml' -File -Recurse -ErrorAction SilentlyContinue)) {
        $queue.Add([pscustomobject]@{ File = $f; Code = $code }) | Out-Null
    }
}

$jobs = @($queue | Sort-Object { $_.File.CreationTimeUtc } | Select-Object -First $MaxJobsPerRun)
if ($jobs.Count -eq 0) { Write-Verbose 'Nothing to collect.'; return }
Write-Verbose "Collecting $($jobs.Count) job(s) across $($codes.Count) environment(s) as $executor."

foreach ($entry in $jobs) {
    $file     = $entry.File
    $expected = $entry.Code

    # The package folder the job was found in, so its result lands beside it.
    $package = Split-Path -Leaf (Split-Path -Parent $file.FullName)
    if ($package -eq 'New') { $package = '' }   # older flat layout

    $paths = Initialize-AudiDropFolder -DropFolder $DropFolder -EnvironmentCode $expected -PackageName $package

    # --- claim it first, so a second run cannot take the same job
    $working = Join-Path $paths.Working $file.Name
    New-AudiJobFolder -Path $working
    try { Move-Item -LiteralPath $file.FullName -Destination $working -Force }
    catch { Write-Verbose "$($file.Name) was already claimed by another run."; continue }

    # The package folder in New is empty the moment the job is claimed. It is
    # recreated by the window next time somebody submits for this package.
    Remove-AudiEmptyPackageFolder -Path (Split-Path -Parent $file.FullName)

    $outcome    = 'Failed'
    $result     = $null
    $job        = $null

    try {
        # --- read and validate. Nothing here asks who wrote the file.
        $read = Read-AudiSwJobFile -Path $working
        if (-not $read.Ok) { throw ("The job file was rejected: " + ($read.Errors -join '; ')) }

        $job = $read.Job

        if ($expected -and $job.Environment -ne $expected) {
            throw ("This job is for $($job.Environment) but it was found in $expected's drop folder. " +
                   "One folder serves one environment. Submit it to $($job.Environment)'s folder, " +
                   "or point this collector at that folder instead. Nothing has been done to either site.")
        }

        $plan = Get-AudiIntegrationPlan `
                    -PackageName            $job.PackageName `
                    -EnvironmentCode        $job.Environment `
                    -Rfc                    $job.Rfc `
                    -LocalizedName          $job.NameEn `
                    -LocalizedDescription   $job.DescriptionEn `
                    -LocalizedNameDe        $job.NameDe `
                    -LocalizedDescriptionDe $job.DescriptionDe `
                    -PartOverride           $job.Detail `
                    -BrandingKey            ([string]$job.Detail['BrandingKey']) `
                    -SoftIdent              ([string]$job.Detail['SoftIdent']) `
                    -OperatingSystemKeys    $job.OperatingSystems `
                    -JobId                  $job.JobId

        $wantsDryRun = ($DryRun -or $job.DryRun)

        # A heartbeat beside the job, after every step. The window has no
        # connection to this server, so this file is the only way a packager can
        # see that their job is being worked on rather than stuck - and it is
        # still there to be read after the window has been closed and reopened.
        #
        # NOT .GetNewClosure(). A closure carries the session state it was made
        # in, and the engine's functions are not reachable from inside one - the
        # handler dies with "The term 'Write-AudiSwJobProgress' is not
        # recognized". A plain scriptblock runs in this script's scope, where
        # both the function and the loop variables below are in view, and it is
        # only ever called from inside the same iteration that set them.
        $progressPath = Join-Path $paths.Working ($file.Name -replace '\.xml$', '.result.xml')
        $onProgress = {
            param($stepName, $stepNumber, $stepCount, $completed)
            Write-AudiSwJobProgress -Path $progressPath -Job $job -Executor $executor `
                                    -CurrentStep $stepName -StepNumber $stepNumber -StepCount $stepCount `
                                    -Completed $completed -DryRun:$wantsDryRun
        }

        $result = switch ($job.Action) {
            'Remove'  { Invoke-AudiSwRemoval      -Plan $plan -DryRun:$wantsDryRun -OnProgress $onProgress }
            'Modify'  { Invoke-AudiSwModification -Plan $plan -DryRun:$wantsDryRun -OnProgress $onProgress }

            # Read the site and report what is there. Creates nothing, so it is
            # never a dry run - there is nothing to rehearse. This is what fills
            # the window's Modify tab.
            'Inspect' {
                # -DryRun matters here even though Inspect creates nothing: it
                # decides whether the SITE is read or the dry-run provider stands
                # in. In production the collector runs without it and this reads
                # the real site; under -DryRun the whole road can be exercised on
                # a machine with no console at all.
                $state = Get-AudiSwPackageState -Plan $plan -DryRun:$wantsDryRun
                [pscustomobject]@{
                    Ok = $state.Ok; DryRun = $false; Message = $state.Message
                    Steps = @([pscustomobject]@{ Step = 'Inspect'; Ok = $state.Ok; Message = $state.Message })
                    State = $state
                }
            }

            # Apply exactly the collections the packager ticked.
            'Change'  {
                Invoke-AudiSwChange -Plan $plan -DryRun:$wantsDryRun -OnProgress $onProgress `
                                    -Add $job.AddCollections -Remove $job.RemoveCollections `
                                    -SettingChanges $job.SettingChanges
            }

            default   { Invoke-AudiSwIntegration  -Plan $plan -DryRun:$wantsDryRun -OnProgress $onProgress }
        }
        $outcome = if ($result.Ok) { 'Succeeded' } else { 'Failed' }
    }
    catch {
        $result = [pscustomobject]@{ Ok = $false; DryRun = [bool]$DryRun
                                     Message = $_.Exception.Message; Steps = @() }
    }

    # The run left us standing on the site's CMSite drive. Everything below is
    # file work, and the ConfigMgr provider does not support the switches it
    # uses, so step back onto the filesystem before touching a single file.
    Restore-AudiFileSystemLocation

    # --- file the job and write the result beside it
    $targetFolder = if ($outcome -eq 'Succeeded') { $paths.Done } else { $paths.Failed }
    $resultPath   = Join-Path $targetFolder ($file.Name -replace '\.xml$', '.result.xml')
    New-AudiJobFolder -Path $resultPath

    if (-not $job) {
        # unreadable file: still record why, so the packager is not left guessing
        $job = [pscustomobject]@{ JobId = 'unknown'; Environment = 'ICZ'; PackageName = $file.BaseName; Rfc = '' }
    }

    try {
        $null = Write-AudiSwJobResult -Path $resultPath -Job $job -Executor $executor -Result $result

        # Archive by RE-WRITING the file as this account and deleting the
        # packager's original, rather than Move-Item. A move keeps the NTFS
        # owner, which would leave the packager's name stamped on a file in the
        # secure zone - the one thing Audi asked us not to do.
        $archive = Join-Path $targetFolder $file.Name
        [System.IO.File]::WriteAllBytes($archive, [System.IO.File]::ReadAllBytes($working))
        Remove-Item -LiteralPath $working -Force

        # the heartbeat has served its purpose - the real result is now filed
        $heartbeat = Join-Path $paths.Working ($file.Name -replace '\.xml$', '.result.xml')
        if (Test-Path -LiteralPath $heartbeat) { Remove-Item -LiteralPath $heartbeat -Force -ErrorAction SilentlyContinue }

        # The package folder in Working has nothing left in it now. Left alone,
        # every job leaves one behind and the queue silts up with empty folders.
        # Done keeps its folder - the result is in it, and History reads it.
        Remove-AudiEmptyPackageFolder -Path $paths.Working
    }
    catch { Write-Warning "Could not file the finished job $($file.Name): $($_.Exception.Message)" }

    Write-Verbose "$($file.Name): $outcome - $($result.Message)  [job $($job.JobId), RFC $(if ($job.Rfc) { $job.Rfc } else { 'none' })]"
}
