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
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'SccmServer\Engine\AudiSwIntegration.ps1')

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
    foreach ($sub in 'New','Working','Done','Failed','Sources') {
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

    # The RFC is recorded, not required. The application name already identifies
    # the package uniquely - SCCM enforces that - so nothing depends on the RFC
    # to know what an object is. A job without one is accepted and runs.
    $noRfcPath = Join-Path $paths.New 'norfc.xml'
    (New-AudiSwJobFile -PackageName $package -EnvironmentCode 'INA' -DryRun).Save($noRfcPath)
    $readNoRfc = Read-AudiSwJobFile -Path $noRfcPath
    Assert-True 'a job with no RFC is accepted' $readNoRfc.Ok ($readNoRfc.Errors -join '; ')
    Remove-Item -LiteralPath $noRfcPath -Force

    # Recorded when it IS given - that is the whole point of keeping the field.
    $withRfcPath = Join-Path $paths.New 'withrfc.xml'
    (New-AudiSwJobFile -PackageName $package -EnvironmentCode 'INA' -Rfc 'RFC0012345' -DryRun).Save($withRfcPath)
    $readWithRfc = Read-AudiSwJobFile -Path $withRfcPath
    Assert-Equal 'an RFC that IS given survives the round trip' 'RFC0012345' $readWithRfc.Job.Rfc
    Remove-Item -LiteralPath $withRfcPath -Force

    # Turning it back into a requirement has to be one config value and nothing
    # else, so the switch stays real rather than becoming dead config.
    Assert-True 'requiring an RFC is still one switch away' `
        ((Get-AudiDefaults).PSObject.Properties['Audit'] -and
         $null -ne (Get-AudiDefaults).Audit.RequireRfc)

    # a malformed file must be rejected, not half-processed
    $badPath = Join-Path $paths.New 'broken.xml'
    '<Job schemaVersion="1.0"><Package/></Job>' | Set-Content -LiteralPath $badPath -Encoding UTF8
    Assert-True 'a malformed job file is rejected' (-not (Read-AudiSwJobFile -Path $badPath).Ok)
    Remove-Item -LiteralPath $badPath -Force

    # ---- INPUT VALIDATION (xkcd 327). The file comes from another zone. Every
    # value that can reach a path, an SCCM name or a cmdlet is limited by the
    # schema, so a crafted file is refused before any code runs on it.
    $goodDoc = New-AudiSwJobFile -PackageName $package -EnvironmentCode 'INA' -Rfc 'RFC0012345' -NameEn 'Reader' -DryRun `
                   -MemberChanges @([pscustomobject]@{ Collection = "GY1-$package"; Machine = 'AUDIPC-04417'; Action = 'Add' })
    $evilPath = Join-Path $paths.New 'evil.xml'
    $rejects = @(
        @{ What = 'a package name with a path in it';       Node = '/Job/Package';         Attr = 'name';    Value = '..\..\Windows\INA_X_Y_x64_1.0-0001_MUL' }
        @{ What = 'a package name with a slash';            Node = '/Job/Package';         Attr = 'name';    Value = 'INA/X_Y_x64_1.0-0001_MUL' }
        @{ What = 'a package name with a quote';            Node = '/Job/Package';         Attr = 'name';    Value = "INA_X_Y'_x64_1.0-0001_MUL" }
        @{ What = 'a package name with a space';            Node = '/Job/Package';         Attr = 'name';    Value = 'INA_X Y_x64_1.0-0001_MUL' }
        @{ What = 'an RFC with a semicolon';                Node = '/Job/Package';         Attr = 'rfc';     Value = "RFC1; DROP TABLE Students" }
        @{ What = 'a machine name with a quote';            Node = '/Job/Changes/Member';  Attr = 'machine'; Value = "PC'); DROP TABLE" }
        @{ What = 'a machine name with a space';            Node = '/Job/Changes/Member';  Attr = 'machine'; Value = 'PC 01' }
        @{ What = 'a job id with a slash';                  Node = '/Job';                 Attr = 'jobId';   Value = '../x' }
        @{ What = 'a display name with a control character'; Node = '/Job/Localised';     Attr = 'nameEn';  Value = ('Reader' + [char]9 + 'x') }
        @{ What = 'a description over the length SCCM takes'; Node = '/Job/Localised';    Attr = 'descriptionEn'; Value = ('x' * 2049) }
    )
    foreach ($case in $rejects) {
        $d = New-Object System.Xml.XmlDocument; $d.LoadXml($goodDoc.OuterXml)
        $d.SelectSingleNode($case.Node).SetAttribute($case.Attr, $case.Value)
        $d.Save($evilPath)
        $verdict = Read-AudiSwJobFile -Path $evilPath
        Assert-True ("the schema refuses " + $case.What) (-not $verdict.Ok)
    }
    # and the ordinary shapes still pass: dots, plus, hyphen, underscore
    $d = New-Object System.Xml.XmlDocument; $d.LoadXml($goodDoc.OuterXml)
    $d.SelectSingleNode('/Job/Package').SetAttribute('name', 'INA_Notepad++_Notepad++_x64_8.6.9-0001_MUL')
    $d.Save($evilPath)
    Assert-True 'a real name with dots, plus and hyphen is accepted' (Read-AudiSwJobFile -Path $evilPath).Ok
    Remove-Item -LiteralPath $evilPath -Force

    # ------------------------------------------------------------ collecting
    Write-Host ''
    Write-Host 'Collecting and running it' -ForegroundColor Cyan
    $watcher = Join-Path (Split-Path -Parent $PSScriptRoot) 'SccmServer\Watch-AudiSwDropFolder.ps1'
    Assert-True 'the collector script exists' (Test-Path -LiteralPath $watcher)

    & $watcher -DropFolder $drop -DryRun -EngineRoot (Join-Path (Split-Path -Parent $PSScriptRoot) 'SccmServer\Engine')

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

    # ---- the collector pointed at ONE environment's folder: <root>\INA.
    # The normal production shape - each server's task watches its own
    # environment folder - and the way "Nothing to collect" was first seen,
    # when only the root was understood. A different package, so the history
    # checks further down still count one run for $package.
    $ownPkg = 'INA_AUDI_OwnFolder_x64_1.0_0001_MUL'
    $ownSub = Submit-AudiSwJob -DropFolder $drop -Job (New-AudiSwJobFile -PackageName $ownPkg -EnvironmentCode 'INA' -Rfc 'RFC0012345' -DryRun)
    $iczSub = Submit-AudiSwJob -DropFolder $drop -Job (New-AudiSwJobFile -PackageName $ownPkg -EnvironmentCode 'ICZ' -Rfc 'RFC0012345' -DryRun)
    $said = & $watcher -DropFolder (Join-Path $drop 'INA') -DryRun -EngineRoot (Join-Path (Split-Path -Parent $PSScriptRoot) 'SccmServer\Engine') -Verbose 4>&1 3>&1
    $warnCount = @($said | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count
    Assert-True  'pointed at INA''s own folder, the INA job is collected'      (Test-Path -LiteralPath $ownSub.ResultPath)
    Assert-True  'and the ICZ job in the folder beside it is NOT touched'      (-not (Test-Path -LiteralPath $iczSub.ResultPath))
    Assert-Equal 'and that is normal, so no warning is raised'                 0 $warnCount
    $iczPaths = Get-AudiDropFolderPath -DropFolder $drop -EnvironmentCode 'ICZ'
    Assert-Equal 'the ICZ job still waits in ICZ\New for ICZ''s own collector' 1 (@(Get-ChildItem $iczPaths.New -Filter '*.xml' -Recurse).Count)
    & $watcher -DropFolder (Join-Path $drop 'ICZ') -DryRun -EngineRoot (Join-Path (Split-Path -Parent $PSScriptRoot) 'SccmServer\Engine')
    Assert-True  'and ICZ''s collector, pointed at ICZ\, picks it up'          (Test-Path -LiteralPath $iczSub.ResultPath)

    # ---- ONE JOB PER PACKAGE AT A TIME. Two people integrate the same package
    # minutes apart: both jobs are queued before the collector runs. The older
    # runs; the newer is filed to Failed as a duplicate, naming the job it lost
    # to - it never reaches SCCM to fail with "already exists".
    $dupPkg = 'INA_AUDI_Duplicate_x64_1.0_0001_MUL'
    $older  = Submit-AudiSwJob -DropFolder $drop -Job (New-AudiSwJobFile -PackageName $dupPkg -EnvironmentCode 'INA' -Rfc 'RFC0000001' -DryRun)
    Start-Sleep -Milliseconds 1200
    $newer  = Submit-AudiSwJob -DropFolder $drop -Job (New-AudiSwJobFile -PackageName $dupPkg -EnvironmentCode 'INA' -Rfc 'RFC0000002' -DryRun)
    $pendingBefore = @(Get-AudiSwPendingJob -DropFolder $drop -EnvironmentCode 'INA' -PackageName $dupPkg)
    Assert-Equal 'both jobs are seen as pending before the collector runs' 2 $pendingBefore.Count
    Assert-Equal 'oldest first'                                            $older.JobId $pendingBefore[0].JobId
    Assert-Equal 'and both as queued'                                      'Queued' $pendingBefore[1].State
    & $watcher -DropFolder $drop -DryRun -EngineRoot (Join-Path (Split-Path -Parent $PSScriptRoot) 'SccmServer\Engine')
    $olderResult = Wait-AudiSwJobResult -Submission $older -TimeoutMinutes 1 -PollSeconds 1
    $newerResult = Wait-AudiSwJobResult -Submission $newer -TimeoutMinutes 1 -PollSeconds 1
    Assert-True  'the older job ran and succeeded'                 $olderResult.Ok $olderResult.Message
    Assert-True  'the newer job was refused, not run'              (-not $newerResult.Ok) $newerResult.Message
    Assert-True  'and its result says it is a duplicate'           ($newerResult.Message -like 'Refused as a duplicate*') $newerResult.Message
    Assert-True  'naming the job it lost to'                       ($newerResult.Message -like "*$($older.JobId)*") $newerResult.Message
    Assert-True  'and that nothing was done'                       ($newerResult.Message -like '*Nothing has been done*')
    Assert-Equal 'nothing is pending for the package afterwards'   0 @(Get-AudiSwPendingJob -DropFolder $drop -EnvironmentCode 'INA' -PackageName $dupPkg).Count
    Assert-True  'the refused job is filed under Failed'           (Test-Path -LiteralPath $newer.FailedPath)

    # ---- SEVERAL WORKERS ON ONE FOLDER. With -Workers N the same folder is
    # collected by N tasks at once. The moment that matters: worker 2 has just
    # claimed the NEWER duplicate (moved it to \Working to refuse it) while
    # worker 1 reaches the OLDER, rightful job. The older one must run - it
    # must not see the newer one "running" and refuse itself, or both die.
    $wPkg   = 'INA_AUDI_Workers_x64_1.0_0001_MUL'
    $wOlder = Submit-AudiSwJob -DropFolder $drop -Job (New-AudiSwJobFile -PackageName $wPkg -EnvironmentCode 'INA' -Rfc 'RFC0000003' -DryRun)
    Start-Sleep -Milliseconds 1200
    $wNewer = Submit-AudiSwJob -DropFolder $drop -Job (New-AudiSwJobFile -PackageName $wPkg -EnvironmentCode 'INA' -Rfc 'RFC0000004' -DryRun)
    $wPaths = Get-AudiDropFolderPath -DropFolder $drop -EnvironmentCode 'INA' -PackageName $wPkg
    New-Item -ItemType Directory -Path $wPaths.Working -Force | Out-Null
    Move-Item -LiteralPath $wNewer.Path -Destination (Join-Path $wPaths.Working (Split-Path -Leaf $wNewer.Path))   # worker 2 holds it
    Assert-Equal 'the newer duplicate is seen as running by another worker' 'Running' `
        (@(Get-AudiSwPendingJob -DropFolder $drop -EnvironmentCode 'INA' -PackageName $wPkg | Where-Object { $_.JobId -eq $wNewer.JobId })[0].State)
    & $watcher -DropFolder $drop -DryRun -EngineRoot (Join-Path (Split-Path -Parent $PSScriptRoot) 'SccmServer\Engine')
    $wResult = Wait-AudiSwJobResult -Submission $wOlder -TimeoutMinutes 1 -PollSeconds 1
    Assert-True  'the older job still runs while a newer duplicate is held by another worker' $wResult.Ok $wResult.Message
    Remove-Item -LiteralPath (Join-Path $wPaths.Working (Split-Path -Leaf $wNewer.Path)) -Force   # worker 2 is done with it
    # and the other way round is still refused: an OLDER job held by another
    # worker blocks a newer one
    $wThird = Submit-AudiSwJob -DropFolder $drop -Job (New-AudiSwJobFile -PackageName $wPkg -EnvironmentCode 'INA' -Rfc 'RFC0000005' -DryRun)
    Start-Sleep -Milliseconds 1200
    $wFourth = Submit-AudiSwJob -DropFolder $drop -Job (New-AudiSwJobFile -PackageName $wPkg -EnvironmentCode 'INA' -Rfc 'RFC0000006' -DryRun)
    Move-Item -LiteralPath $wThird.Path -Destination (Join-Path $wPaths.Working (Split-Path -Leaf $wThird.Path))   # worker 2 runs the older one
    & $watcher -DropFolder $drop -DryRun -EngineRoot (Join-Path (Split-Path -Parent $PSScriptRoot) 'SccmServer\Engine')
    $wFourthResult = Wait-AudiSwJobResult -Submission $wFourth -TimeoutMinutes 1 -PollSeconds 1
    Assert-True  'a newer job is refused while an older one runs on another worker' (-not $wFourthResult.Ok) $wFourthResult.Message
    Assert-True  'and the refusal names the running job' ($wFourthResult.Message -like "*$($wThird.JobId)*running*") $wFourthResult.Message
    Remove-Item -LiteralPath (Join-Path $wPaths.Working (Split-Path -Leaf $wThird.Path)) -Force

    # ---- ERROR HANDLING AFTER THE SERVER STARTED: the server died mid-job.
    # A job left in \Working with a heartbeat that stopped moving would show
    # "running" for ever and block its package. The next pass closes it as
    # FAILED, with what the heartbeat last said, and files it back.
    $deadPkg   = 'INA_AUDI_Stuck_x64_1.0_0001_MUL'
    $deadSub   = Submit-AudiSwJob -DropFolder $drop -Job (New-AudiSwJobFile -PackageName $deadPkg -EnvironmentCode 'INA' -Rfc 'RFC0000007' -DryRun)
    $deadPaths = Initialize-AudiDropFolder -DropFolder $drop -EnvironmentCode 'INA' -PackageName $deadPkg
    $deadFile  = Join-Path $deadPaths.Working (Split-Path -Leaf $deadSub.Path)
    New-Item -ItemType Directory -Path $deadPaths.Working -Force | Out-Null
    Move-Item -LiteralPath $deadSub.Path -Destination $deadFile                      # the server claimed it...
    $deadBeat = $deadFile -replace '\.xml$', '.result.xml'
    Write-AudiSwJobProgress -Path $deadBeat -Executor $me -CurrentStep 'Collections' -StepNumber 4 -StepCount 8 -DryRun `
        -Job ([pscustomobject]@{ JobId = $deadSub.JobId; Environment = 'INA'; PackageName = $deadPkg; Rfc = 'RFC0000007' }) `
        -Completed @([pscustomobject]@{ Step = 'Application'; Ok = $true; Message = 'created' })
    $old = (Get-Date).AddHours(-5)                                                   # ...and then died five hours ago
    (Get-Item -LiteralPath $deadFile).LastWriteTime = $old; (Get-Item -LiteralPath $deadBeat).LastWriteTime = $old
    Assert-Equal 'until then the package looks busy'  'Running' (@(Get-AudiSwPendingJob -DropFolder $drop -EnvironmentCode 'INA' -PackageName $deadPkg)[0].State)
    $stuckSaid = @(& $watcher -DropFolder $drop -DryRun -EngineRoot (Join-Path (Split-Path -Parent $PSScriptRoot) 'SccmServer\Engine') 3>&1)
    $deadResult = Wait-AudiSwJobResult -Submission $deadSub -TimeoutMinutes 1 -PollSeconds 1
    Assert-True  'a job the server died on is closed as failed'         ($deadResult.Found -and -not $deadResult.Ok) $deadResult.Message
    Assert-True  'the result says the server stopped'                   ($deadResult.Message -like '*server stopped*') $deadResult.Message
    Assert-True  'and what the heartbeat last reported'                 ($deadResult.Message -like '*Collections*4 of 8*') $deadResult.Message
    Assert-True  'nothing on the site is touched without a person'      ($deadResult.Message -like '*Nothing on the site has been touched*') $deadResult.Message
    Assert-True  'a dry run is offered Run again'                       ($deadResult.Message -like '*dry run*Run again*') $deadResult.Message
    Assert-Equal 'the steps it had finished are kept'                   1 @($deadResult.Steps).Count
    Assert-Equal 'the package is free again'                            0 @(Get-AudiSwPendingJob -DropFolder $drop -EnvironmentCode 'INA' -PackageName $deadPkg).Count
    Assert-True  'the pass warned about it'                             ((@($stuckSaid) -join ' ') -like '*closed as FAILED*')
    # a job that is alive - heartbeat fresh - is left alone
    $liveSub  = Submit-AudiSwJob -DropFolder $drop -Job (New-AudiSwJobFile -PackageName $deadPkg -EnvironmentCode 'INA' -Rfc 'RFC0000008' -DryRun)
    $liveFile = Join-Path $deadPaths.Working (Split-Path -Leaf $liveSub.Path)
    New-Item -ItemType Directory -Path $deadPaths.Working -Force | Out-Null            # tidied away with the stuck job
    Move-Item -LiteralPath $liveSub.Path -Destination $liveFile
    (Get-Item -LiteralPath $liveFile).LastWriteTime = (Get-Date).AddHours(-5)          # old file...
    Write-AudiSwJobProgress -Path ($liveFile -replace '\.xml$', '.result.xml') -Executor $me -CurrentStep 'Content' -StepNumber 3 -StepCount 8 -DryRun `
        -Job ([pscustomobject]@{ JobId = $liveSub.JobId; Environment = 'INA'; PackageName = $deadPkg; Rfc = 'RFC0000008' }) -Completed @()   # ...fresh heartbeat
    & $watcher -DropFolder $drop -DryRun -EngineRoot (Join-Path (Split-Path -Parent $PSScriptRoot) 'SccmServer\Engine')
    Assert-True  'a job with a fresh heartbeat is left running' (Test-Path -LiteralPath $liveFile)
    Remove-Item -LiteralPath $liveFile -Force; Remove-Item -LiteralPath ($liveFile -replace '\.xml$', '.result.xml') -Force

    # A REAL Integrate that got as far as creating the application: the site
    # holds it, so the packager is pointed at Clean up (the Remove page, typed
    # confirmation) - never an automatic delete. A real Change is pointed at
    # Run again, which skips what is already done.
    foreach ($case in @(@{ Action = 'Integrate'; Done = 'Application'; Expect = '*choose Clean up*' },
                        @{ Action = 'Change';    Done = 'Add';         Expect = '*Run again*machines and collections already handled*' })) {
        $realSub  = Submit-AudiSwJob -DropFolder $drop -Job (New-AudiSwJobFile -PackageName $deadPkg -EnvironmentCode 'INA' -Rfc 'RFC0000010' -Action $case.Action -AddCollections @("GY1-$deadPkg"))
        $realFile = Join-Path $deadPaths.Working (Split-Path -Leaf $realSub.Path)
        New-Item -ItemType Directory -Path $deadPaths.Working -Force | Out-Null
        Move-Item -LiteralPath $realSub.Path -Destination $realFile
        $realBeat = $realFile -replace '\.xml$', '.result.xml'
        Write-AudiSwJobProgress -Path $realBeat -Executor $me -CurrentStep 'Next' -StepNumber 2 -StepCount 8 `
            -Job ([pscustomobject]@{ JobId = $realSub.JobId; Environment = 'INA'; PackageName = $deadPkg; Rfc = 'RFC0000010' }) `
            -Completed @([pscustomobject]@{ Step = $case.Done; Ok = $true; Message = 'done' })
        (Get-Item -LiteralPath $realFile).LastWriteTime = $old; (Get-Item -LiteralPath $realBeat).LastWriteTime = $old
        & $watcher -DropFolder $drop -DryRun -EngineRoot (Join-Path (Split-Path -Parent $PSScriptRoot) 'SccmServer\Engine')
        $realResult = Wait-AudiSwJobResult -Submission $realSub -TimeoutMinutes 1 -PollSeconds 1
        Assert-True ("a dead {0} is closed and pointed at the right next step" -f $case.Action) ($realResult.Found -and $realResult.Message -like $case.Expect) $realResult.Message
    }

    # ---- a file whose name inside does not match the folder it sits in
    $misPkg = 'INA_AUDI_Mismatch_x64_1.0_0001_MUL'
    $misDoc = New-AudiSwJobFile -PackageName $misPkg -EnvironmentCode 'INA' -Rfc 'RFC0000009' -DryRun
    $misPaths = Initialize-AudiDropFolder -DropFolder $drop -EnvironmentCode 'INA' -PackageName 'INA_AUDI_Other_x64_1.0_0001_MUL'
    $misName  = "{0}_{1}.xml" -f $misPkg, $misDoc.Job.jobId
    $misDoc.Save((Join-Path $misPaths.New $misName))
    & $watcher -DropFolder $drop -DryRun -EngineRoot (Join-Path (Split-Path -Parent $PSScriptRoot) 'SccmServer\Engine')
    $misResult = Wait-AudiSwJobResult -TimeoutMinutes 1 -PollSeconds 1 -Submission ([pscustomobject]@{
        JobId = $misDoc.Job.jobId; Path = (Join-Path $misPaths.New $misName)
        ResultPath = (Join-Path $misPaths.Done ($misName -replace '\.xml$', '.result.xml'))
        FailedPath = (Join-Path $misPaths.Failed ($misName -replace '\.xml$', '.result.xml')) })
    Assert-True 'a job filed under another package''s folder is refused' ($misResult.Found -and -not $misResult.Ok) $misResult.Message
    Assert-True 'and the refusal names both'                              ($misResult.Message -like "*$misPkg*INA_AUDI_Other*") $misResult.Message

    # ---- the environment folder does not exist yet. Each server's task runs
    # from the day it is installed; the window creates <root>\PCZ with the
    # first PCZ job. Until then: nothing to collect, and no error.
    $notYet = Join-Path $drop 'PCZ'
    Assert-True  'PCZ''s folder is not there yet' (-not (Test-Path -LiteralPath $notYet))
    $threw = $false
    try { $waitSaid = & $watcher -DropFolder $notYet -DryRun -EngineRoot (Join-Path (Split-Path -Parent $PSScriptRoot) 'SccmServer\Engine') -Verbose 4>&1 }
    catch { $threw = $true; $waitSaid = $_.Exception.Message }
    Assert-True  'a collector pointed at a folder the window has not created yet does not throw' (-not $threw) $waitSaid
    Assert-True  'and says it is waiting for the window to create it' ((@($waitSaid) -join ' ') -like '*not been created*') (@($waitSaid) -join ' ')
    Assert-True  'and creates nothing itself' (-not (Test-Path -LiteralPath $notYet))
    # ...while a folder that really cannot be opened still fails loudly
    $threw = $false
    try { $null = & $watcher -DropFolder 'C:\definitely\not\here\ICZ' -DryRun -EngineRoot (Join-Path (Split-Path -Parent $PSScriptRoot) 'SccmServer\Engine') } catch { $threw = $true }
    Assert-True  'a root that cannot be opened at all is still an error' $threw

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
    & $watcher -DropFolder $drop -EngineRoot (Join-Path (Split-Path -Parent $PSScriptRoot) 'SccmServer\Engine')

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
    # While it sits there it is a pending job, and one job per package at a
    # time means it would block everything below for $package - so it is
    # withdrawn the way a person would: by removing the file from \New.
    Assert-Equal 'while it waits it counts as pending' 1 @(Get-AudiSwPendingJob -DropFolder $drop -EnvironmentCode 'INA' -PackageName $package).Count
    Remove-Item -LiteralPath $orphan.Path -Force
    Assert-Equal 'removing the file withdraws it' 0 @(Get-AudiSwPendingJob -DropFolder $drop -EnvironmentCode 'INA' -PackageName $package).Count

    # -------------------------------------------------- reading results back
    # A packager who closed the window must still be able to see what happened.
    Write-Host ''
    Write-Host 'Looking up an earlier run' -ForegroundColor Cyan
    # One root, a folder per environment, a folder per package inside it - so
    # history is looked up by environment AND package, not by scanning one flat
    # queue.
    # Two runs were submitted for the SAME package name but different
    # environments - an INA one and a PCZ one. Under one root with a folder per
    # environment they are separate queues, and history has to answer per
    # environment. Reporting the PCZ run when asked about INA would tell a
    # packager their INA package had been touched when it had not.
    $history = @(Get-AudiSwJobHistory -DropFolder $drop -EnvironmentCode 'INA' -PackageName $package)
    Assert-Equal 'the INA run is found under INA' 1 $history.Count
    Assert-Equal 'and it is the INA one' 'INA' $history[0].Environment

    $pczHistory = @(Get-AudiSwJobHistory -DropFolder $drop -EnvironmentCode 'PCZ' -PackageName $package)
    Assert-Equal 'the PCZ run is found under PCZ' 1 $pczHistory.Count

    # A third environment nobody submitted to has nothing at all.
    $noneHistory = @(Get-AudiSwJobHistory -DropFolder $drop -EnvironmentCode 'ICZ' -PackageName $package)
    Assert-Equal 'an environment with no runs reports none' 0 $noneHistory.Count
    # Newest first, whatever the count - the window shows this list top-down.
    $outOfOrder = $false
    for ($i = 1; $i -lt $history.Count; $i++) {
        if ($history[$i - 1].Completed -lt $history[$i].Completed) { $outOfOrder = $true }
    }
    Assert-True 'runs come back newest first' (-not $outOfOrder)
    # The failed run is the PCZ one - refused because PCZ is flagged unverified.
    # It belongs in PCZ's queue, which is exactly why it is not in INA's.
    Assert-True  'a failed run is kept too, not only successful ones' `
        (@($pczHistory | Where-Object { $_.Outcome -eq 'Failed' }).Count -eq 1) `
        (@($pczHistory | ForEach-Object { $_.Outcome }) -join ',')

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
        @(Get-AudiSwJobHistory -DropFolder $drop -EnvironmentCode 'INA' -PackageName $package -Newest 1).Count

    # ---------------------------------------------- watching a job in progress
    # The window holds no connection to the server. The heartbeat the collector
    # writes after every step is the only thing that makes it look live, and the
    # only reason a packager can close the window and pick the job back up.
    Write-Host ''
    Write-Host 'Following a job that is still running' -ForegroundColor Cyan

    $liveJob = [pscustomobject]@{ JobId = 'live-0001'; Environment = 'INA'; PackageName = $package; Rfc = 'RFC0012345' }
    # The heartbeat belongs in the same place the collector would write it:
    # <root>\<ENV>\Working\<Package>\ - not the flat root.
    $livePaths = Initialize-AudiDropFolder -DropFolder $drop -EnvironmentCode 'INA' -PackageName $package
    $beat      = Join-Path $livePaths.Working "$($package)_live-0001.result.xml"
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

    $live = @(Get-AudiSwJobHistory -DropFolder $drop -EnvironmentCode 'INA' -PackageName $package)
    Assert-Equal 'the running job comes back first'        'Running' $live[0].Outcome
    Assert-Equal 'it reports the steps done so far'        3 @($live[0].Steps).Count
    Assert-Equal 'and how many there are in total'         8 $live[0].StepCount
    Assert-True  'it names the step being worked on'       ($live[0].Message -like '*Collections*') $live[0].Message
    Assert-True  'the finished runs are still listed after it' (@($live | Where-Object { $_.Outcome -ne 'Running' }).Count -ge 1)

    # a heartbeat names no more people than a result does
    $beatRaw = (Get-Content -LiteralPath $beat -Raw).Replace($me, 'THE-SERVICE-ACCOUNT')
    Assert-True 'the heartbeat names nobody but the executor' `
        (-not ($beatRaw -like "*$($me.Split('\')[-1])*")) 'a person reached the heartbeat file'

    Remove-Item -LiteralPath $beat -Force
    Assert-Equal 'once it finishes the heartbeat is gone and only the result remains' 1 `
        @(Get-AudiSwJobHistory -DropFolder $drop -EnvironmentCode 'INA' -PackageName $package).Count

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

    $engineRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'SccmServer\Engine'

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

    # ---------------------------------- Find, remove what was ticked, refresh
    # The whole road for the three new actions: job file in, the real
    # collector, result out - with the dry-run provider standing in for the site.
    Write-Host ''
    Write-Host 'Find, targeted removal and content refresh through the collector' -ForegroundColor Cyan

    $findJob = Submit-AudiSwJob -DropFolder $drop -Job (
        New-AudiSwJobFile -PackageName 'FIND' -EnvironmentCode 'INA' -Rfc 'RFC0012345' -Action 'Find' -FindPattern 'INA_ADOBE_*')
    Assert-True 'a Find job carrying a wildcard pattern is accepted by the schema' (Read-AudiSwJobFile -Path $findJob.Path).Ok
    & $watcher -DropFolder $drop -DryRun -EngineRoot $engineRoot
    $findResult = Wait-AudiSwJobResult -Submission $findJob -TimeoutMinutes 1 -PollSeconds 1
    Assert-True 'the collector runs a Find job without parsing the pattern as a package name' $findResult.Found $findResult.Message
    Assert-True 'and answers with a list to tick from (empty on the dry-run site)' ($findResult.Ok -and $null -ne $findResult.FoundApps) $findResult.Message

    # a Remove with explicit targets: exact names, one of them a literal wildcard
    $targets = @(
        [pscustomobject]@{ Name = 'INA_ADOBE_Legacy*_x64_1.0_0001_MUL'; ContentPath = ''; Collections = @('GY1-INA_ADOBE_Legacy*_x64_1.0_0001_MUL') }
        [pscustomobject]@{ Name = 'INA_ADOBE_Reader_x64_2024.1_0003_MUL'; ContentPath = ''; Collections = @('GY1-INA_ADOBE_Reader_x64_2024.1_0003_MUL') })
    $targetDoc = New-AudiSwJobFile -PackageName 'REMOVE' -EnvironmentCode 'INA' -Rfc 'RFC0012345' -Action 'Remove' -Targets $targets -RemoveContent -DryRun
    $targetJob = Submit-AudiSwJob -DropFolder $drop -Job $targetDoc
    $readTargets = Read-AudiSwJobFile -Path $targetJob.Path
    Assert-True  'a Remove naming exact targets is accepted by the schema' $readTargets.Ok ($readTargets.Errors -join '; ')
    Assert-Equal 'both targets survive the trip'                            2 @($readTargets.Job.Targets).Count
    Assert-True  'a literal wildcard name survives untouched'               (@($readTargets.Job.Targets | Where-Object { $_.Name -ceq 'INA_ADOBE_Legacy*_x64_1.0_0001_MUL' }).Count -eq 1)
    Assert-True  'and the "also delete the content" choice'                 $readTargets.Job.RemoveContent
    & $watcher -DropFolder $drop -DryRun -EngineRoot $engineRoot
    $targetResult = Wait-AudiSwJobResult -Submission $targetJob -TimeoutMinutes 1 -PollSeconds 1
    Assert-True  'the collector removes exactly the targets'                ($targetResult.Found -and $targetResult.Ok) $targetResult.Message
    Assert-Equal 'one step per target'                                      3 @($targetResult.Steps).Count
    Assert-True  'the content folder step is reported, as a dry run'        (@($targetResult.Steps | Where-Object { $_.Step -eq 'Content folder' -and $_.Message -like 'DRY RUN*' }).Count -eq 1) (@($targetResult.Steps | ForEach-Object { $_.Step }) -join ',')

    # refresh content: the files must be in Sources, and the step says so when they are not
    $refreshJob = Submit-AudiSwJob -DropFolder $drop -Job (
        New-AudiSwJobFile -PackageName $package -EnvironmentCode 'INA' -Rfc 'RFC0012345' -Action 'RefreshContent' -DryRun)
    & $watcher -DropFolder $drop -DryRun -EngineRoot $engineRoot
    $refreshResult = Wait-AudiSwJobResult -Submission $refreshJob -TimeoutMinutes 1 -PollSeconds 1
    Assert-True 'the collector runs a RefreshContent job' $refreshResult.Found $refreshResult.Message

    # ------------------------------------------- a job in the wrong folder
    # One drop folder serves one environment. A job for another environment has
    # been put there by mistake, and running it would carry work out against a
    # site the collector was never pointed at.
    Write-Host ''
    Write-Host 'A job in the wrong folder' -ForegroundColor Cyan

    # Submit-AudiSwJob now derives the folder from the job itself, so the tool
    # CANNOT misfile a job any more - an ICZ job always lands in ICZ's queue.
    # Prove that first, then hand-place a file the way a person would and check
    # the guard still catches it.
    $inaDrop  = (Get-AudiEnvironment -Code 'INA').Transport.DropFolder
    $strayPkg = 'ICZ_AUDI_DummyTest_x86_1.0_0001_MUL'
    $strayDoc = New-AudiSwJobFile -PackageName $strayPkg -EnvironmentCode 'ICZ' `
                                  -Rfc 'RFC0012345' -NameEn 'x' -DryRun
    $filed = Submit-AudiSwJob -DropFolder $inaDrop -Job $strayDoc
    Assert-True 'an ICZ job files itself under ICZ, whatever root it is given' `
        ($filed.Path -like "*\ICZ\New\*") $filed.Path
    Remove-Item -LiteralPath $filed.Path -Force

    # Now the case the guard exists for: somebody copies the file in by hand.
    $wrongPaths = Initialize-AudiDropFolder -DropFolder $inaDrop -EnvironmentCode 'INA' -PackageName $strayPkg
    $strayName  = "{0}_{1}.xml" -f $strayPkg, $strayDoc.Job.jobId
    $strayDoc.Save((Join-Path $wrongPaths.New $strayName))
    $stray = [pscustomobject]@{
        JobId      = $strayDoc.Job.jobId
        Path       = (Join-Path $wrongPaths.New $strayName)
        ResultPath = (Join-Path $wrongPaths.Done   ($strayName -replace '\.xml$', '.result.xml'))
        FailedPath = (Join-Path $wrongPaths.Failed ($strayName -replace '\.xml$', '.result.xml'))
    }
    try {
        & $watcher -DropFolder $inaDrop -DryRun -EngineRoot (Join-Path (Split-Path -Parent $PSScriptRoot) 'SccmServer\Engine')
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
# ------------------------------------------------- the queue tidies up after itself
Write-Host ''
Write-Host 'Empty package folders' -ForegroundColor Cyan

# A job travels New -> Working -> Done, and each package folder it leaves is one
# more empty folder in the queue. After a few weeks the real work is hidden
# among hundreds of them.
$tidy = Join-Path ([System.IO.Path]::GetTempPath()) ("AudiTidy_{0}" -f ([guid]::NewGuid().ToString('N')))
try {
    $tidyPkg = 'INA_ETAS_INCA_x64_7.5.7-0001_MUL'
    $null = Submit-AudiSwJob -DropFolder $tidy -Job (
        New-AudiSwJobFile -PackageName $tidyPkg -EnvironmentCode 'INA' -Rfc 'RFC0012345' -DryRun)

    # Submitting must not create a Failed folder for a job that has not failed.
    Assert-True 'submitting creates the package folder in New' `
        (Test-Path -LiteralPath (Join-Path $tidy "INA\New\$tidyPkg"))
    Assert-True 'and does NOT pre-create one in Failed' `
        (-not (Test-Path -LiteralPath (Join-Path $tidy "INA\Failed\$tidyPkg")))

    & $watcher -DropFolder $tidy -DryRun -EngineRoot (Join-Path (Split-Path -Parent $PSScriptRoot) 'SccmServer\Engine')

    Assert-True 'the New package folder is gone once the job is claimed' `
        (-not (Test-Path -LiteralPath (Join-Path $tidy "INA\New\$tidyPkg")))
    Assert-True 'and the Working one once the job is filed' `
        (-not (Test-Path -LiteralPath (Join-Path $tidy "INA\Working\$tidyPkg")))

    # Done keeps its folder - the result is in it and History reads it.
    Assert-True 'Done keeps the package folder, because the result is in it' `
        (Test-Path -LiteralPath (Join-Path $tidy "INA\Done\$tidyPkg"))

    $leftovers = @(Get-ChildItem -LiteralPath $tidy -Recurse -Directory |
                   Where-Object { $_.Name -notin @('New','Working','Done','Failed','Sources') -and
                                  @(Get-ChildItem -LiteralPath $_.FullName -Force).Count -eq 0 })
    Assert-Equal 'no empty package folder is left anywhere' 0 $leftovers.Count

    # The state folders themselves must survive - the collector expects them.
    foreach ($state in 'New','Working','Done','Failed','Sources') {
        Assert-True "the $state folder itself is kept" (Test-Path -LiteralPath (Join-Path $tidy "INA\$state"))
    }

    # And the folder comes back for the next job.
    $null = Submit-AudiSwJob -DropFolder $tidy -Job (
        New-AudiSwJobFile -PackageName $tidyPkg -EnvironmentCode 'INA' -Rfc 'RFC0012345' -DryRun)
    Assert-True 'a new job recreates the package folder' `
        (Test-Path -LiteralPath (Join-Path $tidy "INA\New\$tidyPkg"))
}
finally { Remove-Item -LiteralPath $tidy -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ''
# ------------------------------------------------- machines over the drop folder
Write-Host ''
Write-Host 'Machines through the drop folder' -ForegroundColor Cyan

$memPkg = $package
$memCol = "GY1-$memPkg"

# A machine change has to survive the trip out...
$memDoc = New-AudiSwJobFile -PackageName $memPkg -EnvironmentCode 'INA' -Rfc 'RFC0012345' -Action 'Change' `
              -MemberChanges @(
                  [pscustomobject]@{ Collection = $memCol; Machine = 'AUDIPC-04417'; Action = 'Add' }
                  [pscustomobject]@{ Collection = $memCol; Machine = 'AUDIPC-09982'; Action = 'Remove' })
$memPath = Join-Path $paths.New 'members.xml'; New-AudiJobFolder -Path $memPath
$memDoc.Save($memPath)
$memRead = Read-AudiSwJobFile -Path $memPath

Assert-True  'a job carrying machine changes is accepted by the schema' $memRead.Ok ($memRead.Errors -join '; ')
Assert-Equal 'both machine changes survive' 2 (@($memRead.Job.MemberChanges).Count)
Assert-Equal 'the machine name survives'   'AUDIPC-04417' (@($memRead.Job.MemberChanges)[0].Machine)
Assert-Equal 'the collection survives'     $memCol        (@($memRead.Job.MemberChanges)[0].Collection)
Assert-Equal 'and the action'              'Add'          (@($memRead.Job.MemberChanges)[0].Action)
Remove-Item -LiteralPath $memPath -Force

# An action the server does not implement must be refused by the SCHEMA, before
# any code sees it - a hand-edited job file is the case this guards.
$evilPath = Join-Path $paths.New 'evil.xml'; New-AudiJobFolder -Path $evilPath
$evilDoc  = New-AudiSwJobFile -PackageName $memPkg -EnvironmentCode 'INA' -Rfc 'RFC0012345' -Action 'Change' `
                -MemberChanges @([pscustomobject]@{ Collection = $memCol; Machine = 'PC-1'; Action = 'Add' })
$evilDoc.Save($evilPath)
$raw = (Get-Content -LiteralPath $evilPath -Raw).Replace('action="Add"', 'action="Destroy"')
Set-Content -LiteralPath $evilPath -Value $raw -Encoding UTF8
Assert-True 'a made-up machine action is rejected by the schema' (-not (Read-AudiSwJobFile -Path $evilPath).Ok)
Remove-Item -LiteralPath $evilPath -Force

# ...and the machines have to come BACK, or the window cannot show who is in what.
$memPlan2 = Get-AudiIntegrationPlan -PackageName $memPkg -EnvironmentCode 'INA' -Rfc 'RFC0012345'
$realCol  = $memPlan2.Collections[0].Name
$memProv2 = New-AudiSccmDryRunProvider -ExistingApplications @($memPlan2.ApplicationName) `
                -ExistingCollections @($realCol) -Members @{ $realCol = @('AUDIPC-04417', 'AUDIPC-09982') }
$memState2 = Get-AudiSwPackageState -Plan $memPlan2 -Provider $memProv2 -DryRun

$memResult = [pscustomobject]@{
    Ok = $true; JobId = 'mem-1'; Environment = 'INA'; Package = $memPkg
    Executor = 'svc-swint'; DryRun = $true; Message = $memState2.Message
    Steps = @(); RolledBack = @(); State = $memState2; LogPath = ''
}
$memResPath = Join-Path $paths.Done 'mem-1.result.xml'
New-AudiJobFolder -Path $memResPath
Write-AudiSwJobResult -Path $memResPath -Executor 'svc-swint' -Result $memResult -Job ([pscustomobject]@{
    JobId = 'mem-1'; Environment = 'INA'; PackageName = $memPkg; Rfc = 'RFC0012345' })

$memBack = Wait-AudiSwJobResult -TimeoutMinutes 1 -PollSeconds 1 -Submission ([pscustomobject]@{
    JobId = 'mem-1'; Path = $memResPath; ResultPath = $memResPath; FailedPath = "$memResPath.none" })
$backRow = @($memBack.State | Where-Object { $_.Name -eq $realCol })[0]
Assert-True  'a result carrying machines is read back' $memBack.Found $memBack.Message
Assert-Equal 'the machines survive the trip back to the window' 'AUDIPC-04417,AUDIPC-09982' `
    (@($backRow.Members) -join ',')
Remove-Item -LiteralPath $memResPath -Force

Write-Host ''
# ------------------------------------------------- the mail man in the middle
Write-Host ''
Write-Host 'Through the middle server' -ForegroundColor Cyan

# The packagers' zone and the SCCM zone have no path between them. The window
# writes to the CLIENT root, the collector reads the SERVER root, and the relay
# on the middle server carries Sources and jobs one way and results the other.
# This drives that whole road: the real relay script, the real collector.
$relay      = Join-Path (Split-Path -Parent $PSScriptRoot) 'MiddleServer\Sync-AudiSwDropFolders.ps1'
$relayBase  = Join-Path ([System.IO.Path]::GetTempPath()) ("AudiRelay_{0}" -f ([guid]::NewGuid().ToString('N')))
$clientRoot = Join-Path $relayBase 'client'
$serverRoot = Join-Path $relayBase 'server'
try {
    New-Item -ItemType Directory -Path $clientRoot, $serverRoot -Force | Out-Null

    # nothing submitted yet: the relay finds no environment folder and stays quiet
    & $relay -ClientRoot $clientRoot -ServerRoot $serverRoot
    Assert-Equal 'before any job, the relay creates nothing on the server' 0 @(Get-ChildItem -LiteralPath $serverRoot).Count

    # a package folder the way a packager has it, and what the window does on
    # Integrate: Sources first, then the job
    $relayPkg = 'INA_WINMERGE_WinMerge_x64_2.16.58_0001_MUL'
    $pkgFolder = Join-Path $relayBase 'INA_WINMERGE_WinMerge_x64_2.16.58-0001_MUL'
    New-Item -ItemType Directory -Path (Join-Path $pkgFolder 'Files') -Force | Out-Null
    '# deploy' | Set-Content -LiteralPath (Join-Path $pkgFolder 'Invoke-AppDeployToolkit.ps1') -Encoding UTF8
    'bin'      | Set-Content -LiteralPath (Join-Path $pkgFolder 'Files\setup.exe') -Encoding UTF8

    $clientPaths = Initialize-AudiDropFolder -DropFolder $clientRoot -EnvironmentCode 'INA'
    $put = Copy-AudiPackageContent -PackagePath $pkgFolder -ContentShare $clientPaths.Sources -SccmName $relayPkg
    Assert-True  'the window puts the content into the client root''s Sources' (Test-Path -LiteralPath (Join-Path $clientPaths.Sources "$relayPkg\Files\setup.exe"))
    Assert-Equal 'under the SCCM name, underscore before the release' (Join-Path $clientPaths.Sources $relayPkg) $put.Target

    $relaySub = Submit-AudiSwJob -DropFolder $clientRoot -Job (
        New-AudiSwJobFile -PackageName $relayPkg -EnvironmentCode 'INA' -Rfc 'RFC0012345' -NameEn 'WinMerge 2.16.58' -DryRun)
    Assert-True 'the job is queued on the client side' ($relaySub.Path -like "$clientRoot\INA\New\*")

    # ---- OUT
    & $relay -ClientRoot $clientRoot -ServerRoot $serverRoot
    $serverPaths = Get-AudiDropFolderPath -DropFolder $serverRoot -EnvironmentCode 'INA' -PackageName $relayPkg
    # with -PackageName every state path already ends in the package folder
    Assert-True  'the content arrives in the server root''s Sources' (Test-Path -LiteralPath (Join-Path $serverPaths.Sources 'Files\setup.exe'))
    Assert-True  'and leaves the client side'                         (-not (Test-Path -LiteralPath (Join-Path $clientPaths.Sources $relayPkg)))
    Assert-True  'the job arrives in the server root''s New'          (Test-Path -LiteralPath (Join-Path $serverPaths.New (Split-Path -Leaf $relaySub.Path)))
    Assert-True  'the job leaves the client''s New'                   (-not (Test-Path -LiteralPath $relaySub.Path))
    $marker = Join-Path (Join-Path (Join-Path $clientRoot 'INA\Working') $relayPkg) (Split-Path -Leaf $relaySub.Path)
    Assert-True  'and is kept in the client''s Working as the in-transit marker' (Test-Path -LiteralPath $marker)
    Assert-Equal 'so the window still sees one pending job for the package' 1 `
        @(Get-AudiSwPendingJob -DropFolder $clientRoot -EnvironmentCode 'INA' -PackageName $relayPkg).Count
    Assert-True  'no half-relayed folder or file is left on the server' `
        (@(Get-ChildItem -LiteralPath (Join-Path $serverRoot 'INA') -Recurse -Force | Where-Object { $_.Name -like '~*' }).Count -eq 0)
    # a second pass with nothing new carries nothing and breaks nothing
    & $relay -ClientRoot $clientRoot -ServerRoot $serverRoot
    Assert-True  'a pass with nothing to carry leaves the marker alone' (Test-Path -LiteralPath $marker)

    # ---- the SCCM server, exactly as before: it reads its own root
    & $watcher -DropFolder $serverRoot -DryRun -EngineRoot $engineRoot
    $serverDone = Join-Path $serverPaths.Done ((Split-Path -Leaf $relaySub.Path) -replace '\.xml$', '.result.xml')
    Assert-True  'the collector runs the job from the server root' (Test-Path -LiteralPath $serverDone)
    Assert-True  'a dry run leaves Sources on the server for the real run' (Test-Path -LiteralPath $serverPaths.Sources)

    # ---- IN
    & $relay -ClientRoot $clientRoot -ServerRoot $serverRoot
    $back = Wait-AudiSwJobResult -Submission $relaySub -TimeoutMinutes 1 -PollSeconds 1
    Assert-True  'the result comes back to the client root' $back.Found $back.Message
    Assert-True  'and the job succeeded' $back.Ok $back.Message
    Assert-True  'the in-transit marker is cleared' (-not (Test-Path -LiteralPath $marker))
    Assert-Equal 'nothing is pending for the package any more' 0 `
        @(Get-AudiSwPendingJob -DropFolder $clientRoot -EnvironmentCode 'INA' -PackageName $relayPkg).Count
    Assert-True  'the archived job file travels back beside the result' `
        (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $back.Path) (Split-Path -Leaf $relaySub.Path)))
    $backSteps = @($back.Steps)
    Assert-Equal 'the content copy is the job''s first step' 'Content copy' $backSteps[0].Step
    Assert-True  'and it names the store it would copy into' ($backSteps[0].Message -like 'DRY RUN*Sources*') $backSteps[0].Message
    Assert-Equal 'the history on the client side shows the run' 1 `
        @(Get-AudiSwJobHistory -DropFolder $clientRoot -EnvironmentCode 'INA' -PackageName $relayPkg).Count
    # carried once - a later pass must not duplicate or re-clear anything
    & $relay -ClientRoot $clientRoot -ServerRoot $serverRoot
    Assert-Equal 'a later pass does not carry the result twice' 1 `
        @(Get-AudiSwJobHistory -DropFolder $clientRoot -EnvironmentCode 'INA' -PackageName $relayPkg).Count

    # ---- WHO DID IT stays on the packagers' side: every submission appends a
    # line to <packager root>\Record\<yyyy-MM>.txt, and the sync never carries
    # that folder (no New\ inside it) - the SCCM side has no name anywhere
    $recordFile = Join-Path (Join-Path $clientRoot 'Record') ((Get-Date).ToString('yyyy-MM') + '.txt')
    Assert-True  'a submission writes the packagers'' record on their own side' (Test-Path -LiteralPath $recordFile)
    $recordLine = @(Get-Content -LiteralPath $recordFile | Where-Object { $_ -like "*|$relayPkg|*" })
    Assert-True  'one line per submission, naming the package' ($recordLine.Count -ge 1)
    $recordParts = @($recordLine[0] -split '\|')
    Assert-Equal 'time | account | machine | environment | package | action | RFC | job id' 8 $recordParts.Count
    Assert-Equal 'the account is the packager who submitted' ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) $recordParts[1]
    Assert-Equal 'the job id links it to the result'         $relaySub.JobId $recordParts[7]
    Assert-True  'the record folder is NOT on the SCCM side'  (-not (Test-Path -LiteralPath (Join-Path $serverRoot 'Record')))
    # (result files carry the EXECUTOR - here the test account, on the server
    # the service account - so only the job files are checked for a person)
    Assert-True  'and no job file on the SCCM side carries the account name' `
        (@(Get-ChildItem -LiteralPath $serverRoot -Recurse -File -Filter '*.xml' | Where-Object { $_.Name -notlike '*.result.xml' -and (Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue) -like "*$($recordParts[1])*" }).Count -eq 0)

    # ---- THE PACKAGER IS NEVER BLIND: each pass of the middle server leaves
    # sync-status.txt on the client root, and the watcher's own status line
    # (written in the server's environment folder) is carried back with it
    $syncStatus = Join-Path $clientRoot 'sync-status.txt'
    Assert-True 'the middle server leaves sync-status.txt on the packager side' (Test-Path -LiteralPath $syncStatus)
    $syncParts = @((Get-Content -LiteralPath $syncStatus -Raw).Trim() -split '\|', 4)
    Assert-Equal 'it says OK after a clean pass' 'OK' $syncParts[2]
    Assert-Equal 'and names the machine it ran on' $env:COMPUTERNAME $syncParts[1]
    Assert-True  'with a round-trip timestamp first' ([datetime]::TryParse($syncParts[0], [ref]([datetime]::MinValue)))
    Assert-True  'the watcher writes watcher-status.txt in its environment folder' (Test-Path -LiteralPath (Join-Path $serverRoot 'INA\watcher-status.txt'))
    Assert-True  'and the middle server carries it back to the packager side'    (Test-Path -LiteralPath (Join-Path $clientRoot 'INA\watcher-status.txt'))
    Assert-Equal 'unchanged' (Get-Content -LiteralPath (Join-Path $serverRoot 'INA\watcher-status.txt') -Raw) (Get-Content -LiteralPath (Join-Path $clientRoot 'INA\watcher-status.txt') -Raw)
    # a server root that cannot be reached: the pass fails loudly AND still
    # tells the packager side what went wrong
    $blindErr = ''
    try { & $relay -ClientRoot $clientRoot -ServerRoot (Join-Path $relayBase 'no-such-server') -ErrorAction Stop } catch { $blindErr = $_.Exception.Message }
    Assert-True  'an unreachable SCCM side is an error on the middle server' ($blindErr -ne '') $blindErr
    $syncParts = @((Get-Content -LiteralPath $syncStatus -Raw).Trim() -split '\|', 4)
    Assert-Equal 'and sync-status.txt on the packager side says FAILED' 'FAILED' $syncParts[2]
    Assert-True  'naming the unreachable root' ($syncParts[3] -like '*no-such-server*') $syncParts[3]

    # ---- every path in a settings file beside the script, never on the task's
    # command line - so a path change is an edit, not a re-install
    $relayCfg = Join-Path $relayBase 'Sync-Settings.txt'
    @('# test', "ClientRoot = $clientRoot", "ServerRoot = $serverRoot", 'EnvironmentCode = ') | Set-Content -LiteralPath $relayCfg -Encoding UTF8
    $cfgSub = Submit-AudiSwJob -DropFolder $clientRoot -Job (
        New-AudiSwJobFile -PackageName $relayPkg -EnvironmentCode 'INA' -Rfc 'RFC0012345' -DryRun)
    & $relay -SettingsFile $relayCfg
    Assert-True 'the relay takes both roots from its settings file' `
        (Test-Path -LiteralPath (Join-Path $serverPaths.New (Split-Path -Leaf $cfgSub.Path)))
    $watcherCfg = Join-Path $relayBase 'Watcher-Settings.txt'
    @("DropFolder = $serverRoot", 'EngineRoot = ', 'MaxJobsPerRun = 5') | Set-Content -LiteralPath $watcherCfg -Encoding UTF8
    & $watcher -SettingsFile $watcherCfg -EngineRoot $engineRoot -DryRun
    Assert-True 'the watcher takes its drop folder from its settings file' `
        (Test-Path -LiteralPath (Join-Path $serverPaths.Done ((Split-Path -Leaf $cfgSub.Path) -replace '\.xml$', '.result.xml')))
    & $relay -SettingsFile $relayCfg
    $noPath = ''
    try { & $relay -SettingsFile (Join-Path $relayBase 'nowhere.txt') } catch { $noPath = $_.Exception.Message }
    Assert-True 'with no path anywhere the relay says which file to fill in' ($noPath -like '*nowhere.txt*') $noPath
    $noPath = ''
    try { & $watcher -SettingsFile (Join-Path $relayBase 'nowhere.txt') -EngineRoot $engineRoot } catch { $noPath = $_.Exception.Message }
    Assert-True 'and so does the watcher' ($noPath -like '*nowhere.txt*') $noPath

    # ---- HOUSEKEEPING on the SCCM side: old results are archived by month,
    # old archives deleted, orphaned Sources removed - only when older than
    # the days in the settings, only inside the drop folder
    $hkCfg = Join-Path $relayBase 'Watcher-Housekeeping.txt'
    @("DropFolder = $serverRoot", 'DoneRetentionDays = 30', 'FailedRetentionDays = 60', 'ArchiveRetentionDays = 365', 'SourcesRetentionDays = 7') | Set-Content -LiteralPath $hkCfg -Encoding UTF8
    $doneFile   = Join-Path $serverPaths.Done ((Split-Path -Leaf $relaySub.Path) -replace '\.xml$', '.result.xml')
    $doneJob    = Join-Path $serverPaths.Done (Split-Path -Leaf $relaySub.Path)
    $orphanSrc  = Join-Path (Split-Path -Parent $serverPaths.Sources) 'INA_AUDI_Orphan_x64_1.0_0001_MUL'
    New-Item -ItemType Directory -Path $orphanSrc -Force | Out-Null; 'x' | Set-Content (Join-Path $orphanSrc 'setup.exe')
    $liveSrc = $serverPaths.Sources   # the relay package's Sources - a job is not pending, but it is fresh
    & $watcher -SettingsFile $hkCfg -EngineRoot $engineRoot -DryRun
    Assert-True 'a fresh result stays in Done'                         (Test-Path -LiteralPath $doneFile)
    Assert-True 'a fresh Sources folder stays'                          (Test-Path -LiteralPath $orphanSrc)
    $ancient = (Get-Date).AddDays(-45)
    (Get-Item -LiteralPath $doneFile).LastWriteTime = $ancient; (Get-Item -LiteralPath $doneJob).LastWriteTime = $ancient
    (Get-Item -LiteralPath $orphanSrc).LastWriteTime = (Get-Date).AddDays(-10); (Get-Item -LiteralPath (Join-Path $orphanSrc 'setup.exe')).LastWriteTime = (Get-Date).AddDays(-10)
    & $watcher -SettingsFile $hkCfg -EngineRoot $engineRoot -DryRun
    $archiveMonth = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $serverPaths.Done)) 'Archive') $ancient.ToString('yyyy-MM')
    Assert-True  'a result older than DoneRetentionDays is moved to Archive\<yyyy-MM>' (Test-Path -LiteralPath (Join-Path (Join-Path $archiveMonth $relayPkg) (Split-Path -Leaf $doneFile)))
    Assert-True  'together with its job file'                          (Test-Path -LiteralPath (Join-Path (Join-Path $archiveMonth $relayPkg) (Split-Path -Leaf $doneJob)))
    Assert-True  'and is gone from Done'                                (-not (Test-Path -LiteralPath $doneFile))
    Assert-True  'a Sources folder with no job for it, older than SourcesRetentionDays, is deleted' (-not (Test-Path -LiteralPath $orphanSrc))
    Assert-True  'a fresh Sources folder is still there'                (Test-Path -LiteralPath $liveSrc)
    # a LARGE package waits fewer days: with the size bar set to a few bytes,
    # a two-day-old folder is already old enough
    $bigSrc = Join-Path (Split-Path -Parent $serverPaths.Sources) 'INA_AUDI_Big_x64_1.0_0001_MUL'
    New-Item -ItemType Directory -Path $bigSrc -Force | Out-Null; ('x' * 4096) | Set-Content (Join-Path $bigSrc 'setup.exe')
    (Get-Item -LiteralPath $bigSrc).LastWriteTime = (Get-Date).AddDays(-3); (Get-Item -LiteralPath (Join-Path $bigSrc 'setup.exe')).LastWriteTime = (Get-Date).AddDays(-3)
    @("DropFolder = $serverRoot", 'SourcesRetentionDays = 14', 'LargeSourcesGB = 0.000001', 'LargeSourcesRetentionDays = 2') | Set-Content -LiteralPath $hkCfg -Encoding UTF8
    & $watcher -SettingsFile $hkCfg -EngineRoot $engineRoot -DryRun
    Assert-True  'a large package with no job is cleared after the shorter LargeSourcesRetentionDays' (-not (Test-Path -LiteralPath $bigSrc))
    Assert-True  'a fresh Sources folder is still there after that too'  (Test-Path -LiteralPath $liveSrc)
    @("DropFolder = $serverRoot", 'DoneRetentionDays = 30', 'FailedRetentionDays = 60', 'ArchiveRetentionDays = 365', 'SourcesRetentionDays = 7') | Set-Content -LiteralPath $hkCfg -Encoding UTF8
    $veryOld = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $serverPaths.Done)) 'Archive') '2019-01'
    New-Item -ItemType Directory -Path $veryOld -Force | Out-Null
    & $watcher -SettingsFile $hkCfg -EngineRoot $engineRoot -DryRun
    Assert-True  'an Archive month older than ArchiveRetentionDays is deleted' (-not (Test-Path -LiteralPath $veryOld))
    Assert-True  'a younger Archive month is kept'                      (Test-Path -LiteralPath $archiveMonth)

    # a relay pinned to one environment leaves the others alone
    $null = Submit-AudiSwJob -DropFolder $clientRoot -Job (
        New-AudiSwJobFile -PackageName 'ICZ_AUDI_DummyTest_x86_1.0_0001_MUL' -EnvironmentCode 'ICZ' -Rfc 'RFC0012345' -DryRun)
    & $relay -ClientRoot $clientRoot -ServerRoot $serverRoot -EnvironmentCode 'INA'
    Assert-True 'a relay pinned to INA does not touch ICZ' (-not (Test-Path -LiteralPath (Join-Path $serverRoot 'ICZ')))
    & $relay -ClientRoot $clientRoot -ServerRoot $serverRoot
    Assert-True 'an unpinned relay carries every environment' (Test-Path -LiteralPath (Join-Path $serverRoot 'ICZ\New'))
}
finally { Remove-Item -LiteralPath $relayBase -Recurse -Force -ErrorAction SilentlyContinue }

# ---- THE FILES REACHED THE STORE, THEN THE SITE STEP FAILED (18 Sep 2026:
# the preflight threw, and the packager saw "Failed - Count" with no word that
# the content copy had already happened and Sources were gone). A REAL run on
# a machine with no ConfigMgr console: the content step copies into the store,
# the engine then fails - and the result must carry the content step first,
# say the files are in the store, and Sources must be cleared, exactly as
# after a success.
Write-Host ''; Write-Host 'Content in the store survives a failed site step' -ForegroundColor Cyan
$storeBase = Join-Path ([System.IO.Path]::GetTempPath()) ("AudiStore_{0}" -f ([guid]::NewGuid().ToString('N')))
try {
    $storeDrop   = Join-Path $storeBase 'drop'
    $storeShare  = Join-Path $storeBase 'store'
    $storeEngine = Join-Path $storeBase 'Engine'
    New-Item -ItemType Directory -Path $storeDrop, $storeShare -Force | Out-Null
    # a private engine root whose INA content share is a temp folder
    Copy-Item -LiteralPath $engineRoot -Destination $storeEngine -Recurse
    $inaFile = Join-Path $storeEngine 'Config\Environments\INA.xml'
    $inaXml  = [xml][System.IO.File]::ReadAllText($inaFile)
    $inaXml.SelectSingleNode('/Environment/Content').SetAttribute('share', $storeShare)
    $inaXml.Save($inaFile)

    $storePkg = 'INA_AUDI_StoreTest_x64_1.0_0001_MUL'
    $storeSrc = Join-Path $storeBase 'INA_AUDI_StoreTest_x64_1.0-0001_MUL'
    New-Item -ItemType Directory -Path (Join-Path $storeSrc 'Files') -Force | Out-Null
    '# deploy' | Set-Content -LiteralPath (Join-Path $storeSrc 'Invoke-AppDeployToolkit.ps1') -Encoding UTF8
    'payload'  | Set-Content -LiteralPath (Join-Path $storeSrc 'Files\setup.exe') -Encoding UTF8
    $storePaths = Initialize-AudiDropFolder -DropFolder $storeDrop -EnvironmentCode 'INA'
    $null = Copy-AudiPackageContent -PackagePath $storeSrc -ContentShare $storePaths.Sources -SccmName $storePkg
    $storeSub = Submit-AudiSwJob -DropFolder $storeDrop -Job (
        New-AudiSwJobFile -PackageName $storePkg -EnvironmentCode 'INA' -Rfc 'RFC0012345' -NameEn 'Store test' -OperatingSystems @('Win10x64','Win11x64'))

    & $watcher -DropFolder $storeDrop -EngineRoot $storeEngine    # NO -DryRun: the copy is real, the site step fails
    $storeRun = @(Get-AudiSwJobHistory -DropFolder $storeDrop -EnvironmentCode 'INA' -PackageName $storePkg)
    Assert-Equal 'the job is filed as failed - there is no site here'      'Failed' $storeRun[0].Outcome
    Assert-True  'the files ARE in the store'                                (Test-Path -LiteralPath (Join-Path (Join-Path $storeShare $storePkg) 'Files\setup.exe'))
    $storeSteps = @($storeRun[0].Steps)
    Assert-True  'the result still carries the content step, first'         ($storeSteps.Count -gt 0 -and $storeSteps[0].Step -eq 'Content copy') (($storeSteps | ForEach-Object { $_.Step }) -join ', ')
    Assert-True  'marked OK'                                                  ($storeSteps.Count -gt 0 -and $storeSteps[0].Ok)
    Assert-True  'the Sources folder is cleared - the store holds them now'  (-not (Test-Path -LiteralPath (Join-Path $storePaths.Sources $storePkg)))
    Assert-True  'and the step says so'                                       ($storeSteps.Count -gt 0 -and $storeSteps[0].Message -like '*Sources cleared*') $storeSteps[0].Message
    Assert-True  'the failure message tells the packager the files are in the store' ($storeRun[0].Message -like '*ARE in the store*') $storeRun[0].Message
}
finally { Remove-Item -LiteralPath $storeBase -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ''
if ($script:Fail -eq 0) { Write-Host ("All {0} checks passed." -f $script:Pass) -ForegroundColor Green }
else                    { Write-Host ("{0} passed, {1} FAILED." -f $script:Pass, $script:Fail) -ForegroundColor Red }
Write-Host ''
exit $(if ($script:Fail -eq 0) { 0 } else { 1 })
