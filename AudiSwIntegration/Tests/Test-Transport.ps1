# ==============================================================================
#  Tests for flow 2 - the drop folder round trip.
#  Uses a real temporary folder, so submit / collect / result is exercised for
#  real. Still needs no SCCM: the collection runs through the dry-run provider.
#    .\Test-Transport.ps1
# ==============================================================================

[CmdletBinding()]
param([switch]$Quiet)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Server\Engine\AudiSwIntegration.ps1')

$script:Pass = 0
$script:Fail = 0
function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) { $script:Pass++; if (-not $Quiet) { Write-Host ("  PASS  " + $Name) -ForegroundColor Green } }
    else            { $script:Fail++; Write-Host ("  FAIL  " + $Name + $(if ($Detail) { " -- $Detail" } else { '' })) -ForegroundColor Red }
}
function Assert-Equal { param([string]$Name, $Expected, $Actual)
    Assert-True -Name $Name -Condition ($Expected -eq $Actual) -Detail "expected '$Expected', got '$Actual'"
}

$drop = Join-Path ([System.IO.Path]::GetTempPath()) ("AudiDrop_{0}" -f ([guid]::NewGuid().ToString('N')))
$package = 'INA_ADOBE_Acrobat_Reader_x64_2024.1_0003_MUL'

Write-Host ''
Write-Host 'Audi SCCM Integration Tool - drop folder tests' -ForegroundColor Cyan
Write-Host ''

try {
    # ------------------------------------------------------------- the folder
    Write-Host 'Folder layout' -ForegroundColor Cyan
    $paths = Initialize-AudiDropFolder -DropFolder $drop
    foreach ($sub in 'New','Working','Done','Failed') {
        Assert-True "$sub folder is created" (Test-Path -LiteralPath (Join-Path $drop $sub))
    }
    Assert-True 'creating it twice is safe' ([bool](Initialize-AudiDropFolder -DropFolder $drop))

    # -------------------------------------------------------------- the job
    Write-Host ''
    Write-Host 'Writing a job' -ForegroundColor Cyan
    $doc = New-AudiSwJobFile -PackageName $package -EnvironmentCode 'INA' -Rfc 'RFC0012345' `
                             -NameEn 'Adobe - Acrobat Reader - 2024.1' -DescriptionEn 'Reader.' `
                             -OperatingSystems @('Win10x64','Win11x64') -DryRun

    Assert-Equal 'the job names the package'     $package $doc.Job.Package.name
    Assert-Equal 'the job names the environment' 'INA'    $doc.Job.environment
    Assert-Equal 'the action defaults to Integrate' 'Integrate' $doc.Job.action
    Assert-Equal 'two operating systems recorded' 2 (@($doc.SelectNodes('/Job/OperatingSystems/OperatingSystem')).Count)

    # The job must NOT carry a requester - that is the whole point.
    Assert-True 'the job carries no requester attribute' (-not $doc.Job.HasAttribute('requester'))

    $submission = Submit-AudiSwJob -DropFolder $drop -Job $doc
    Assert-True  'the job file lands in New' (Test-Path -LiteralPath $submission.Path)
    Assert-True  'no temporary file is left behind' (-not (Get-ChildItem $paths.New -Filter '*.tmp'))
    Assert-Equal 'the submission reports the job id' $doc.Job.jobId $submission.JobId

    # it must validate against the schema
    $check = Test-AudiConfigFile -Path $submission.Path -SchemaPath (Join-Path (Get-AudiConfigRoot) 'Environment.xsd')
    Assert-True 'the job file validates against the schema' $check.Ok ($check.Errors -join '; ')

    # -------------------------------------------------------- reading it back
    Write-Host ''
    Write-Host 'Reading the job on the server' -ForegroundColor Cyan
    $read = Read-AudiSwJobFile -Path $submission.Path
    Assert-True  'the job is accepted' $read.Ok ($read.Errors -join '; ')
    Assert-Equal 'the package survives the round trip' $package $read.Job.PackageName
    Assert-Equal 'the RFC survives'  'RFC0012345' $read.Job.Rfc
    Assert-True  'dry run survives'  $read.Job.DryRun
    Assert-Equal 'both operating systems survive' 2 $read.Job.OperatingSystems.Count

    # no identity is established at all - not from the file, not from its owner
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    Assert-True 'reading a job establishes no requester' (-not $read.Contains('Requester'))

    # a requester written into the file must be rejected outright
    $forged = New-AudiSwJobFile -PackageName $package -EnvironmentCode 'INA' -Rfc 'RFC0012345' -DryRun
    $forged.Job.SetAttribute('requester', 'DOMAIN\someone.else')
    $forgedPath = Join-Path $paths.New 'forged.xml'
    $forged.Save($forgedPath)
    $readForged = Read-AudiSwJobFile -Path $forgedPath
    Assert-True  'a job naming a requester is rejected by the schema' (-not $readForged.Ok)
    Remove-Item -LiteralPath $forgedPath -Force

    # the RFC is the only route back to a person, so it cannot be left out
    $noRfcPath = Join-Path $paths.New 'norfc.xml'
    (New-AudiSwJobFile -PackageName $package -EnvironmentCode 'INA' -DryRun).Save($noRfcPath)
    $readNoRfc = Read-AudiSwJobFile -Path $noRfcPath
    Assert-True 'a job with no RFC is refused'          (-not $readNoRfc.Ok)
    Assert-True 'the refusal explains why the RFC matters' (($readNoRfc.Errors -join ' ') -like '*who requested*')
    Remove-Item -LiteralPath $noRfcPath -Force

    # a malformed file must be rejected, not half-processed
    $badPath = Join-Path $paths.New 'broken.xml'
    '<Job schemaVersion="1.0"><Package/></Job>' | Set-Content -LiteralPath $badPath -Encoding UTF8
    Assert-True 'a malformed job file is rejected' (-not (Read-AudiSwJobFile -Path $badPath).Ok)
    Remove-Item -LiteralPath $badPath -Force

    # ------------------------------------------------------------ collecting
    Write-Host ''
    Write-Host 'Collecting and running it' -ForegroundColor Cyan
    $watcher = Join-Path (Split-Path -Parent $PSScriptRoot) 'Server\Watch-AudiSwDropFolder.ps1'
    Assert-True 'the collector script exists' (Test-Path -LiteralPath $watcher)

    & $watcher -DropFolder $drop -DryRun -EngineRoot (Join-Path (Split-Path -Parent $PSScriptRoot) 'Server\Engine')

    Assert-Equal 'the job left New'        0 (@(Get-ChildItem $paths.New     -Filter '*.xml').Count)
    Assert-Equal 'nothing stuck in Working' 0 (@(Get-ChildItem $paths.Working -Filter '*.xml').Count)
    Assert-True  'a result file was written' (Test-Path -LiteralPath $submission.ResultPath)

    # The collector reports progress through a scriptblock. If that scriptblock
    # cannot see the engine's own functions - which is what .GetNewClosure() does
    # to it - every step fails with "the term ... is not recognized" and the job
    # is lost. It is not enough that the run finished; check what it actually said.
    $collected = New-Object System.Xml.XmlDocument; $collected.Load($submission.ResultPath)
    $said = @($collected.SelectNodes('/JobResult/Steps/Step') | ForEach-Object { $_.message }) -join ' '
    Assert-True 'no step failed on a name the handler could not resolve' `
        ($said -notlike '*is not recognized*') $said

    # ----------------------------------------------------------- the result
    Write-Host ''
    Write-Host 'The result' -ForegroundColor Cyan
    $waited = Wait-AudiSwJobResult -Submission $submission -TimeoutMinutes 1 -PollSeconds 1
    Assert-True  'the window finds the result' $waited.Found
    Assert-True  'the outcome is success' $waited.Ok $waited.Message
    Assert-Equal 'eight steps are reported' 8 $waited.Steps.Count
    Assert-Equal 'the RFC is carried into the result' 'RFC0012345' $waited.Rfc
    Assert-True  'the executor is recorded'  (-not [string]::IsNullOrWhiteSpace($waited.Executor))

    # The result may name exactly ONE account - the executor, which on a server
    # is the service account. It runs as the signed-in user here, so blank that
    # out first; anything left naming a person is a leak.
    $resultRaw = Get-Content -LiteralPath $waited.Path -Raw
    $rcheckDoc = New-Object System.Xml.XmlDocument; $rcheckDoc.Load($waited.Path)
    Assert-True 'the result file has no requester attribute' (-not $rcheckDoc.JobResult.HasAttribute('requester'))
    $withoutExecutor = $resultRaw.Replace($rcheckDoc.JobResult.executor, 'THE-SERVICE-ACCOUNT')
    Assert-True 'the executor is the only account the result names' `
        (-not ($withoutExecutor -like "*$($me.Split('\')[-1])*")) 'another user name reached the result file'

    # and no file owned by the packager is left behind on the server
    $archived = Join-Path $paths.Done (Split-Path -Leaf $submission.Path)
    if (Test-Path -LiteralPath $archived) {
        Assert-Equal 'the archived job file is owned by whoever ran the collector' `
            $me (Get-Acl -LiteralPath $archived).Owner
    }

    $rdoc = New-Object System.Xml.XmlDocument; $rdoc.Load($submission.ResultPath)
    $rcheck = Test-AudiConfigFile -Path $submission.ResultPath -SchemaPath (Join-Path (Get-AudiConfigRoot) 'Environment.xsd')
    Assert-True  'the result file validates against the schema' $rcheck.Ok ($rcheck.Errors -join '; ')
    Assert-Equal 'the result names the package' $package $rdoc.JobResult.package

    # ------------------------------------------------------- a failing job
    Write-Host ''
    Write-Host 'A job that cannot run' -ForegroundColor Cyan
    # PCZ is unverified, so a real run must be refused even through the folder
    $pczDoc = New-AudiSwJobFile -PackageName $package -EnvironmentCode 'PCZ' -NameEn 'x' -Rfc 'RFC0099999'
    $pczSub = Submit-AudiSwJob -DropFolder $drop -Job $pczDoc
    & $watcher -DropFolder $drop -EngineRoot (Join-Path (Split-Path -Parent $PSScriptRoot) 'Server\Engine')

    Assert-True 'the refused job lands in Failed' (Test-Path -LiteralPath $pczSub.FailedPath)
    $pczResult = Wait-AudiSwJobResult -Submission $pczSub -TimeoutMinutes 1 -PollSeconds 1
    Assert-True 'the refusal is reported as a failure' (-not $pczResult.Ok)
    Assert-True 'the reason mentions the unverified environment' ($pczResult.Message -like '*unverified*')

    # ------------------------------------------------------- timeout branch
    Write-Host ''
    Write-Host 'When nothing collects the job' -ForegroundColor Cyan
    $orphan = Submit-AudiSwJob -DropFolder $drop -Job (New-AudiSwJobFile -PackageName $package -EnvironmentCode 'INA' -Rfc 'RFC0012345' -DryRun)
    $timedOut = Wait-AudiSwJobResult -Submission $orphan -TimeoutMinutes 0 -PollSeconds 1
    Assert-True 'waiting reports not found rather than hanging' (-not $timedOut.Found)
    Assert-True 'the message explains what to check' ($timedOut.Message -like '*not running*')

    # -------------------------------------------------- reading results back
    # A packager who closed the window must still be able to see what happened.
    Write-Host ''
    Write-Host 'Looking up an earlier run' -ForegroundColor Cyan
    $history = @(Get-AudiSwJobHistory -DropFolder $drop -PackageName $package)
    Assert-Equal 'both finished runs are found again' 2 $history.Count
    Assert-True  'the newest is first' ($history[0].Completed -ge $history[1].Completed)
    Assert-True  'a failed run is found too, not only the successful one' `
        (@($history | Where-Object { $_.Outcome -eq 'Failed' }).Count -eq 1)

    $succeeded = @($history | Where-Object { $_.Outcome -eq 'Succeeded' })[0]
    Assert-Equal 'the earlier run still reports its eight steps' 8 @($succeeded.Steps).Count
    Assert-Equal 'the earlier run still carries its RFC' 'RFC0012345' $succeeded.Rfc
    Assert-True  'the earlier run remembers it was a dry run' $succeeded.DryRun
    Assert-True  'the result file it came from is named' (Test-Path -LiteralPath $succeeded.Path)

    # a name that was never run, and a folder that is not there, must both stay quiet
    Assert-Equal 'an unknown package has no history' 0 `
        @(Get-AudiSwJobHistory -DropFolder $drop -PackageName 'INA_NOTHING_x64_1.0.0-0001_MUL').Count
    Assert-Equal 'a drop folder that does not exist yet has no history' 0 `
        @(Get-AudiSwJobHistory -DropFolder (Join-Path $drop 'nowhere') -PackageName $package).Count
    Assert-Equal 'the caller can cap how many runs come back' 1 `
        @(Get-AudiSwJobHistory -DropFolder $drop -PackageName $package -Newest 1).Count

    # ---------------------------------------------- watching a job in progress
    # The window holds no connection to the server. The heartbeat the collector
    # writes after every step is the only thing that makes it look live, and the
    # only reason a packager can close the window and pick the job back up.
    Write-Host ''
    Write-Host 'Following a job that is still running' -ForegroundColor Cyan

    $liveJob = [pscustomobject]@{ JobId = 'live-0001'; Environment = 'INA'; PackageName = $package; Rfc = 'RFC0012345' }
    $beat    = Join-Path $paths.Working "$($package)_live-0001.result.xml"
    Write-AudiSwJobProgress -Path $beat -Job $liveJob -Executor $me -CurrentStep 'Collections' `
                            -StepNumber 4 -StepCount 8 -DryRun `
                            -Completed @(
                                [pscustomobject]@{ Step = 'Application'; Ok = $true; Message = 'created' }
                                [pscustomobject]@{ Step = 'Category';    Ok = $true; Message = 'set' }
                                [pscustomobject]@{ Step = 'Content';     Ok = $true; Message = 'distributed' })

    Assert-True 'a heartbeat is written while the job runs' (Test-Path -LiteralPath $beat)
    Assert-True 'no half-written heartbeat is left behind'  (-not (Test-Path -LiteralPath "$beat.writing"))
    $beatCheck = Test-AudiConfigFile -Path $beat -SchemaPath (Join-Path (Get-AudiConfigRoot) 'Environment.xsd')
    Assert-True 'the heartbeat validates against the same schema as a result' $beatCheck.Ok ($beatCheck.Errors -join '; ')

    $live = @(Get-AudiSwJobHistory -DropFolder $drop -PackageName $package)
    Assert-Equal 'the running job comes back first'        'Running' $live[0].Outcome
    Assert-Equal 'it reports the steps done so far'        3 @($live[0].Steps).Count
    Assert-Equal 'and how many there are in total'         8 $live[0].StepCount
    Assert-True  'it names the step being worked on'       ($live[0].Message -like '*Collections*') $live[0].Message
    Assert-True  'the finished runs are still listed after it' (@($live | Where-Object { $_.Outcome -ne 'Running' }).Count -eq 2)

    # a heartbeat names no more people than a result does
    $beatRaw = (Get-Content -LiteralPath $beat -Raw).Replace($me, 'THE-SERVICE-ACCOUNT')
    Assert-True 'the heartbeat names nobody but the executor' `
        (-not ($beatRaw -like "*$($me.Split('\')[-1])*")) 'a person reached the heartbeat file'

    Remove-Item -LiteralPath $beat -Force
    Assert-Equal 'once it finishes the heartbeat is gone and only the result remains' 2 `
        @(Get-AudiSwJobHistory -DropFolder $drop -PackageName $package).Count

    # ------------------------------------------- a job in the wrong folder
    # One drop folder serves one environment. A job for another environment has
    # been put there by mistake, and running it would carry work out against a
    # site the collector was never pointed at.
    Write-Host ''
    Write-Host 'A job in the wrong folder' -ForegroundColor Cyan

    $inaDrop = (Get-AudiEnvironment -Code 'INA').Transport.DropFolder
    $strayDoc = New-AudiSwJobFile -PackageName 'ICZ_AUDI_DummyTest_x86_1.0_0001_MUL' -EnvironmentCode 'ICZ' `
                                  -Rfc 'RFC0012345' -NameEn 'x' -DryRun
    $stray = Submit-AudiSwJob -DropFolder $inaDrop -Job $strayDoc
    try {
        & $watcher -DropFolder $inaDrop -DryRun -EngineRoot (Join-Path (Split-Path -Parent $PSScriptRoot) 'Server\Engine')
        $strayResult = Wait-AudiSwJobResult -Submission $stray -TimeoutMinutes 1 -PollSeconds 1
        Assert-True 'an ICZ job left in INA''s folder is refused' (-not $strayResult.Ok) $strayResult.Message
        Assert-True 'and the refusal names both environments' `
            ($strayResult.Message -like '*ICZ*INA*') $strayResult.Message
        Assert-True 'nothing was done to either site' ($strayResult.Message -like '*Nothing has been done*')
    }
    finally {
        # remove only what this check created - the folder is a real one
        foreach ($leftover in @($stray.Path, $stray.ResultPath, $stray.FailedPath,
                                (Join-Path (Join-Path $inaDrop 'Failed') (Split-Path -Leaf $stray.Path)),
                                (Join-Path (Join-Path $inaDrop 'Done')   (Split-Path -Leaf $stray.Path)))) {
            if ($leftover -and (Test-Path -LiteralPath $leftover)) { Remove-Item -LiteralPath $leftover -Force -ErrorAction SilentlyContinue }
        }
    }
}
finally {
    if (Test-Path -LiteralPath $drop) { Remove-Item -LiteralPath $drop -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
if ($script:Fail -eq 0) { Write-Host ("All {0} checks passed." -f $script:Pass) -ForegroundColor Green }
else                    { Write-Host ("{0} passed, {1} FAILED." -f $script:Pass, $script:Fail) -ForegroundColor Red }
Write-Host ''
exit $(if ($script:Fail -eq 0) { 0 } else { 1 })
