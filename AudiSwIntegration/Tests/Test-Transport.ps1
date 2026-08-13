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

    # ------------------------------------------------ Inspect and Change
    # The Modify tab's whole round trip: ask the server what is there, tick
    # rows, send back exactly those names. The window never touches the site.
    Write-Host ''
    Write-Host 'The Modify tab round trip' -ForegroundColor Cyan

    $inspectDoc = New-AudiSwJobFile -PackageName $package -EnvironmentCode 'INA' -Rfc 'RFC0012345' -Action 'Inspect'
    $inspectPath = Join-Path $paths.New 'inspect.xml'
    $inspectDoc.Save($inspectPath)
    $readInspect = Read-AudiSwJobFile -Path $inspectPath
    Assert-True  'an Inspect job is accepted by the schema' $readInspect.Ok ($readInspect.Errors -join '; ')
    Assert-Equal 'and keeps its action' 'Inspect' $readInspect.Job.Action
    Remove-Item -LiteralPath $inspectPath -Force

    $changeDoc = New-AudiSwJobFile -PackageName $package -EnvironmentCode 'INA' -Rfc 'RFC0012345' -Action 'Change' `
                    -AddCollections @("GY1-$package") -RemoveCollections @("SM1-${package}_Legacy")
    $changePath = Join-Path $paths.New 'change.xml'
    $changeDoc.Save($changePath)
    $readChange = Read-AudiSwJobFile -Path $changePath
    Assert-True  'a Change job is accepted by the schema' $readChange.Ok ($readChange.Errors -join '; ')
    Assert-Equal 'the ticked additions survive the round trip' "GY1-$package" ($readChange.Job.AddCollections -join ',')
    Assert-Equal 'and the ticked removals'                     "SM1-${package}_Legacy" ($readChange.Job.RemoveCollections -join ',')
    Assert-True  'a Change job still carries no requester' (-not ([xml](Get-Content $changePath -Raw)).Job.HasAttribute('requester'))
    Remove-Item -LiteralPath $changePath -Force

    # ---- setting edits over the same road -----------------------------------
    #
    # The window sends a key and a value; the SERVER decides what that key means
    # and whether it may be written. So what has to survive the trip is exactly
    # that pair - not a cmdlet parameter name, and not a translated value. If a
    # job file ever carried the resolved parameter, a hand-edited file in the
    # drop folder could call any parameter it liked.
    $settingDoc = New-AudiSwJobFile -PackageName $package -EnvironmentCode 'INA' -Rfc 'RFC0012345' -Action 'Change' `
                    -SettingChanges @(
                        [pscustomobject]@{ Key = 'RebootBehavior'; From = 'BasedOnExitCode'; To = 'ForceReboot' }
                        [pscustomobject]@{ Key = 'Description';    From = 'old text';        To = 'new text' }
                    )
    $settingPath = Join-Path $paths.New 'change-settings.xml'
    $settingDoc.Save($settingPath)
    $readSetting = Read-AudiSwJobFile -Path $settingPath

    Assert-True  'a Change job carrying setting edits is accepted by the schema' `
        $readSetting.Ok ($readSetting.Errors -join '; ')
    Assert-Equal 'both setting edits survive the round trip' 2 (@($readSetting.Job.SettingChanges).Count)
    Assert-Equal 'the key survives'   'RebootBehavior'  (@($readSetting.Job.SettingChanges)[0].Key)
    Assert-Equal 'the new value survives' 'ForceReboot' (@($readSetting.Job.SettingChanges)[0].To)
    # 'from' is the audit trail: what the operator was looking at when they
    # decided. The server never acts on it - it re-reads the site itself.
    Assert-Equal 'and the value the operator saw is kept for the record' 'BasedOnExitCode' `
        (@($readSetting.Job.SettingChanges)[0].From)

    # A value with XML-significant characters must come back intact, not as a
    # mangled attribute - descriptions and command lines contain both.
    $awkward = 'Ends with "quotes" & <angles>'
    $oddDoc  = New-AudiSwJobFile -PackageName $package -EnvironmentCode 'INA' -Rfc 'RFC0012345' -Action 'Change' `
                    -SettingChanges @([pscustomobject]@{ Key = 'Description'; From = ''; To = $awkward })
    $oddPath = Join-Path $paths.New 'change-odd.xml'
    $oddDoc.Save($oddPath)
    $readOdd = Read-AudiSwJobFile -Path $oddPath
    Assert-True  'quotes and angle brackets do not break the job file' $readOdd.Ok ($readOdd.Errors -join '; ')
    Assert-Equal 'and the value comes back exactly as typed' $awkward (@($readOdd.Job.SettingChanges)[0].To)

    # Collections and settings in one job: the Modify tab can send both at once.
    $bothDoc = New-AudiSwJobFile -PackageName $package -EnvironmentCode 'INA' -Rfc 'RFC0012345' -Action 'Change' `
                    -AddCollections @("GY1-$package") `
                    -SettingChanges @([pscustomobject]@{ Key = 'MaximumRuntime'; From = '120'; To = '240' })
    $bothPath = Join-Path $paths.New 'change-both.xml'
    $bothDoc.Save($bothPath)
    $readBoth = Read-AudiSwJobFile -Path $bothPath
    Assert-True  'one job can carry both a collection and a setting' $readBoth.Ok ($readBoth.Errors -join '; ')
    Assert-Equal 'the collection is still there' "GY1-$package" ($readBoth.Job.AddCollections -join ',')
    Assert-Equal 'and so is the setting'         'MaximumRuntime' (@($readBoth.Job.SettingChanges)[0].Key)

    # A job with no setting edits must not grow an empty Changes block, and must
    # still read back as an empty list rather than $null.
    $plainDoc = New-AudiSwJobFile -PackageName $package -EnvironmentCode 'INA' -Rfc 'RFC0012345' -Action 'Integrate'
    $plainPath = Join-Path $paths.New 'plain.xml'
    $plainDoc.Save($plainPath)
    $readPlain = Read-AudiSwJobFile -Path $plainPath
    Assert-True  'a job with no changes is still valid' $readPlain.Ok ($readPlain.Errors -join '; ')
    Assert-Equal 'and reports no setting edits' 0 (@($readPlain.Job.SettingChanges).Count)

    foreach ($p in $settingPath, $oddPath, $bothPath, $plainPath) { Remove-Item -LiteralPath $p -Force }

    # ---- the settings have to come BACK, not just go out --------------------
    #
    # This is the leg that was missing: Get-AudiSwPackageState worked out all
    # the settings and the result file threw them away, so the Modify tab only
    # ever showed collections. Everything upstream can be right and the feature
    # still not exist.
    $inspectPlan = Get-AudiIntegrationPlan -PackageName $package -EnvironmentCode 'INA' -Rfc 'RFC0012345'
    $inspectProv = New-AudiSccmDryRunProvider -ExistingApplications @($inspectPlan.ApplicationName)
    $liveState   = Get-AudiSwPackageState -Plan $inspectPlan -Provider $inspectProv -DryRun

    $inspectResult = [pscustomobject]@{
        Ok = $true; JobId = 'insp-1'; Environment = 'INA'; Package = $package
        Executor = 'svc-swint'; DryRun = $true; Message = $liveState.Message
        Steps = @(); RolledBack = @(); State = $liveState; LogPath = ''
    }
    $resPath = Join-Path $paths.Done 'insp-1.result.xml'
    Write-AudiSwJobResult -Path $resPath -Executor 'svc-swint' -Job ([pscustomobject]@{
        JobId = 'insp-1'; Environment = 'INA'; PackageName = $package; Rfc = 'RFC0012345' }) -Result $inspectResult

    # Read it back the way the window does - through the waiter, not by parsing
    # the file here. A test that parses it itself would pass while the window
    # still saw nothing, which is exactly the failure this covers.
    $readBack = Wait-AudiSwJobResult -TimeoutMinutes 1 -PollSeconds 1 -Submission ([pscustomobject]@{
        JobId = 'insp-1'; Path = $resPath; ResultPath = $resPath; FailedPath = "$resPath.missing" })
    Assert-True 'an Inspect result carrying settings is read back' $readBack.Found $readBack.Message

    $backSettings = @($readBack.Settings)
    Assert-Equal 'every setting survives the trip back to the window' `
        $liveState.Settings.Count $backSettings.Count
    Assert-True  'the locked ones are still locked' `
        (@($backSettings | Where-Object { -not $_.Editable }).Count -eq 3) `
        ("editable=false: " + (@($backSettings | Where-Object { -not $_.Editable } | ForEach-Object { $_.Key }) -join ', '))
    Assert-True  'and they still say why' `
        ((@($backSettings | Where-Object { -not $_.Editable })[0].LockedReason) -like '*package name*')

    # Without the options a Choice renders as an empty dropdown, which is the
    # difference between an editor and a picture of one.
    $choiceBack = @($backSettings | Where-Object { $_.Editor -eq 'Choice' })
    Assert-True 'the choices come back with their options' `
        ($choiceBack.Count -gt 0 -and @($choiceBack | Where-Object { $_.Options.Count -lt 2 }).Count -eq 0)
    Assert-True 'an option keeps both its value and its wording' `
        ($choiceBack[0].Options[0].Value -and $choiceBack[0].Options[0].Label)

    # The grid binds to NewValue; if it did not start at the current value,
    # opening the tab and pressing Apply would rewrite every setting.
    Assert-True 'nothing looks changed until somebody changes it' `
        (@($backSettings | Where-Object { $_.NewValue -ne $_.Current }).Count -eq 0)

    Remove-Item -LiteralPath $resPath -Force

    # The state Inspect found has to survive into the result file, because that
    # is what the window draws its three lists from.
    $stateJob = [pscustomobject]@{ JobId = 'state-1'; Environment = 'INA'; PackageName = $package; Rfc = 'RFC0012345' }
    $stateResult = [pscustomobject]@{
        Ok = $true; DryRun = $false; Message = 'Application present.'; Steps = @()
        State = [pscustomobject]@{
            Application = $true
            Collections = @([pscustomobject]@{ Name = "GY1-$package"; Wanted = $true; Exists = $false; HasDeployment = $false })
            Extra       = @([pscustomobject]@{ Name = "SM1-${package}_Legacy"; Wanted = $false; Exists = $true; HasDeployment = $true })
            SecurityScopes = @('INA00003')
        }
    }
    $statePath = Join-Path $paths.Done 'state.result.xml'
    $null = Write-AudiSwJobResult -Path $statePath -Job $stateJob -Executor $me -Result $stateResult
    $stateCheck = Test-AudiConfigFile -Path $statePath -SchemaPath (Join-Path (Get-AudiConfigRoot) 'Environment.xsd')
    Assert-True  'a result carrying the site state validates' $stateCheck.Ok ($stateCheck.Errors -join '; ')

    $stateXml = [xml](Get-Content $statePath -Raw)
    Assert-Equal 'both collections are recorded' 2 @($stateXml.JobResult.State.Collection).Count
    Assert-Equal 'the missing one is marked wanted but absent' 'false' `
        (@($stateXml.JobResult.State.Collection | Where-Object { $_.name -eq "GY1-$package" })[0].exists)
    Assert-Equal 'the unwanted one is marked present but not wanted' 'false' `
        (@($stateXml.JobResult.State.Collection | Where-Object { $_.name -like '*_Legacy' })[0].wanted)
    Assert-Equal 'the scopes come through' 'INA00003' ([string]$stateXml.JobResult.State.Scope)
    Remove-Item -LiteralPath $statePath -Force

    # ------------------------------ the Modify tab, through the REAL collector
    #
    # Everything above tests the pieces. This drives the whole road the way the
    # window does: a job file into \New, the actual Watch-AudiSwDropFolder.ps1
    # picking it up, the engine running, a result file coming back out - for
    # both of the new actions. No SCCM: the collector runs -DryRun, so the
    # dry-run provider stands in for the site.
    Write-Host ''
    Write-Host 'Inspect and Change through the collector' -ForegroundColor Cyan

    $engineRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'Server\Engine'

    $inspectJob = Submit-AudiSwJob -DropFolder $drop -Job (
        New-AudiSwJobFile -PackageName $package -EnvironmentCode 'INA' -Rfc 'RFC0012345' -Action 'Inspect')
    & $watcher -DropFolder $drop -DryRun -EngineRoot $engineRoot
    $inspectResult = Wait-AudiSwJobResult -Submission $inspectJob -TimeoutMinutes 1 -PollSeconds 1

    Assert-True  'the collector runs an Inspect job' $inspectResult.Found $inspectResult.Message
    Assert-True  'and it reports on the package'     ($inspectResult.Message -like '*application*') $inspectResult.Message
    Assert-True  'the answer carries the collections the window needs' `
        (@($inspectResult.State).Count -gt 0) 'the Modify tab has nothing to draw'
    Assert-True  'every collection says whether it is wanted and whether it exists' `
        (@($inspectResult.State | Where-Object { $null -ne $_.Wanted -and $null -ne $_.Exists }).Count -eq @($inspectResult.State).Count)

    # Inspect must never write to the site. Nothing it did may look like a change.
    $inspectSteps = @($inspectResult.Steps)
    Assert-Equal 'Inspect reports exactly one step' 1 $inspectSteps.Count
    Assert-Equal 'and that step is the inspection'  'Inspect' $inspectSteps[0].Step

    # ...then the packager ticks two rows and sends them back.
    $changeJob = Submit-AudiSwJob -DropFolder $drop -Job (
        New-AudiSwJobFile -PackageName $package -EnvironmentCode 'INA' -Rfc 'RFC0012345' -Action 'Change' `
            -AddCollections @("GY1-$package") -RemoveCollections @("SM1-${package}_Legacy") -DryRun)
    & $watcher -DropFolder $drop -DryRun -EngineRoot $engineRoot
    $changeResult = Wait-AudiSwJobResult -Submission $changeJob -TimeoutMinutes 1 -PollSeconds 1

    Assert-True 'the collector runs a Change job' $changeResult.Found $changeResult.Message
    # Each collector pass builds a fresh dry-run provider, so the site it sees is
    # empty and there is no application to change. That is the RIGHT answer, and
    # it proves the engine checks before it acts rather than blindly creating.
    # Changing a real application is covered against the engine in Test-Sccm.
    Assert-True 'a Change against a site with no application is refused' (-not $changeResult.Ok) $changeResult.Message
    Assert-True 'and it says to Integrate first' ($changeResult.Message -like '*Use Integrate*') $changeResult.Message
    Assert-True 'the result names no person' `
        (-not ((Get-Content -LiteralPath $changeResult.Path -Raw).Replace($me, 'X') -like "*$($me.Split('\')[-1])*"))

    # A ticked name that is not this package's is refused by the ENGINE, not
    # trusted because a window sent it.
    $strayJob = Submit-AudiSwJob -DropFolder $drop -Job (
        New-AudiSwJobFile -PackageName $package -EnvironmentCode 'INA' -Rfc 'RFC0012345' -Action 'Change' `
            -RemoveCollections @('SM1-SomebodyElsesCollection') -DryRun)
    & $watcher -DropFolder $drop -DryRun -EngineRoot $engineRoot
    $strayResult = Wait-AudiSwJobResult -Submission $strayJob -TimeoutMinutes 1 -PollSeconds 1

    Assert-True 'a collection belonging to another package is refused' (-not $strayResult.Ok) $strayResult.Message
    Assert-True 'and the refusal says why' ($strayResult.Message -like '*not belong*') $strayResult.Message

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
