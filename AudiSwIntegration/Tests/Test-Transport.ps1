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
}
finally {
    if (Test-Path -LiteralPath $drop) { Remove-Item -LiteralPath $drop -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
if ($script:Fail -eq 0) { Write-Host ("All {0} checks passed." -f $script:Pass) -ForegroundColor Green }
else                    { Write-Host ("{0} passed, {1} FAILED." -f $script:Pass, $script:Fail) -ForegroundColor Red }
Write-Host ''
exit $(if ($script:Fail -eq 0) { 0 } else { 1 })
