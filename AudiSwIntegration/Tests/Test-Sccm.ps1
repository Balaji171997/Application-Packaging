# ==============================================================================
#  Tests for the SCCM engine. Runs anywhere - no SCCM, no network, no rights.
#  The dry-run provider stands in for the site, so ordering, failure handling
#  and rollback are all exercised for real.
#    .\Test-AudiSwSccm.ps1
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

$package = 'INA_AUDI_DummyTest_x86_1.0_0001_MUL'

# A package is named for the environment it is published into, so the test plan
# is built with a matching prefix. Preflight rejects a mismatch on purpose - see
# the SitePrefix check, and the dedicated test for it further down.
function New-TestPlan { param([string]$Code = 'INA')
    $name = $package -replace '^[A-Za-z0-9]+_', "${Code}_"
    Get-AudiIntegrationPlan -PackageName $name -EnvironmentCode $Code -Rfc 'RFC0012345'
}

Write-Host ''
Write-Host 'Audi SCCM Integration Tool - engine tests' -ForegroundColor Cyan
Write-Host ''

# ---------------------------------------------------------------- step model
Write-Host 'Step model' -ForegroundColor Cyan
$steps = Get-AudiIntegrationStep
Assert-Equal 'eight integration steps' 8 $steps.Count
Assert-Equal 'four removal steps'      4 (Get-AudiRemovalStep).Count

# Every dependency must name a step that exists and comes earlier in the list.
$seen = New-Object System.Collections.Generic.HashSet[string]
$orderOk = $true
foreach ($s in $steps) {
    foreach ($d in $s.DependsOn) { if (-not $seen.Contains($d)) { $orderOk = $false } }
    $null = $seen.Add($s.Key)
}
Assert-True 'every dependency is declared before it is needed' $orderOk
Assert-True 'the security scope depends on the application' ((@($steps | Where-Object Key -eq 'SecurityScope')[0].DependsOn) -contains 'Application')
Assert-True 'deployments depend on both application and collections' ((@($steps | Where-Object Key -eq 'Deployments')[0].DependsOn).Count -eq 2)
Assert-True 'removing collections depends on removing deployments first' ((@(Get-AudiRemovalStep | Where-Object Key -eq 'Collections')[0].DependsOn) -contains 'Deployments')

# ---------------------------------------------------------------- happy path
Write-Host ''
Write-Host 'A clean run' -ForegroundColor Cyan
$plan = New-TestPlan
$provider = New-AudiSccmDryRunProvider
$run = Invoke-AudiSwIntegration -Plan $plan -Provider $provider -DryRun

Assert-True  'the run reports success' $run.Ok $run.Message
Assert-Equal 'all eight steps succeeded' 8 (@($run.Steps | Where-Object { $_.Ok }).Count)
Assert-Equal 'nothing was rolled back'   0 $run.RolledBack.Count

$log = $provider.Log.ToArray()
Assert-Equal 'one application created'          1 (@($log | Where-Object Operation -eq 'NewApplication').Count)
Assert-Equal 'nine collections created'         9 (@($log | Where-Object Operation -eq 'NewCollection').Count)
Assert-Equal 'nine deployments created'         9 (@($log | Where-Object Operation -eq 'NewDeployment').Count)
Assert-Equal 'ten objects filed (app + nine)'  10 (@($log | Where-Object Operation -eq 'MoveObject').Count)
Assert-Equal 'one AD group created'             1 (@($log | Where-Object Operation -eq 'NewArsGroup').Count)

# Move-CMObject wants a PROVIDER path rooted at the object type, not the folder
# name the environment file holds. A bare name binds to the parameter and then
# fails at the site, so the built path is checked here rather than on ICZ.
$moves = @($log | Where-Object Operation -eq 'MoveObject' | ForEach-Object { $_.Detail })
Assert-True 'the application is filed under the site drive, not a bare folder name' `
    (@($moves | Where-Object { $_ -like '* -> INA:\Application\INA-Applications' }).Count -eq 1) ($moves -join ' | ')
Assert-True 'collections are filed under DeviceCollection, keeping their sub-folders' `
    (@($moves | Where-Object { $_ -like '* -> INA:\DeviceCollection\SCCM-Manager\Single-Removals' }).Count -eq 1) ($moves -join ' | ')
Assert-Equal 'every filed object gets a rooted path' 10 `
    (@($moves | Where-Object { $_ -match ' -> INA:\\(Application|DeviceCollection)\\' }).Count)

# The application must exist before anything is deployed to it.
$appIndex  = [array]::IndexOf(@($log | ForEach-Object { $_.Operation }), 'NewApplication')
$deployIdx = [array]::IndexOf(@($log | ForEach-Object { $_.Operation }), 'NewDeployment')
$scopeIdx  = [array]::IndexOf(@($log | ForEach-Object { $_.Operation }), 'AddSecurityScope')
Assert-True 'the application is created before any deployment' ($appIndex -lt $deployIdx)
Assert-True 'the security scope is attached after the application' ($appIndex -lt $scopeIdx)

# Exactly one deployment is an uninstall, and it is the right collection.
$uninstall = @($log | Where-Object { $_.Operation -eq 'NewDeployment' -and $_.Detail -like '*(Uninstall)' })
Assert-Equal 'exactly one uninstall deployment' 1 $uninstall.Count
Assert-True  'the uninstall targets _RemoveComputer' ($uninstall[0].Detail -like '*_RemoveComputer*')

# ---------------------------------------------------------------- failures
Write-Host ''
Write-Host 'Failure handling and rollback' -ForegroundColor Cyan

# Fail at the deployments step, after the application and collections exist.
$provider2 = New-AudiSccmDryRunProvider -FailOn 'NewDeployment'
$run2 = Invoke-AudiSwIntegration -Plan (New-TestPlan) -Provider $provider2 -DryRun

Assert-True  'a failed run reports failure, not success' (-not $run2.Ok)
Assert-True  'the failing step is marked as failed' (@($run2.Steps | Where-Object { $_.Step -eq 'Deployments' -and -not $_.Ok }).Count -eq 1)
Assert-True  'the real error is reported, not "Done."' ($run2.Message -like '*failed*')

# One application plus nine collections were created, so ten objects must be undone.
Assert-Equal 'ten objects rolled back' 10 $run2.RolledBack.Count
$rolledLog = $provider2.Log.ToArray()
Assert-Equal 'nine collections removed during rollback' 9 (@($rolledLog | Where-Object Operation -eq 'RemoveCollection').Count)
Assert-Equal 'the application removed during rollback'  1 (@($rolledLog | Where-Object Operation -eq 'RemoveApplication').Count)
# newest first: collections were created last, so they go first
$firstUndo = @($rolledLog | Where-Object { $_.Operation -like 'Remove*' })[0]
Assert-Equal 'rollback removes the newest object first' 'RemoveCollection' $firstUndo.Operation

# Steps after the failure must not run at all.
Assert-Equal 'no security scope was attached' 0 (@($rolledLog | Where-Object Operation -eq 'AddSecurityScope').Count)
Assert-Equal 'nothing was filed into folders'  0 (@($rolledLog | Where-Object Operation -eq 'MoveObject').Count)

# -NoRollback leaves the part-built package in place for investigation.
$provider3 = New-AudiSccmDryRunProvider -FailOn 'NewDeployment'
$run3 = Invoke-AudiSwIntegration -Plan (New-TestPlan) -Provider $provider3 -DryRun -NoRollback
Assert-Equal 'NoRollback leaves everything in place' 0 $run3.RolledBack.Count

# An application that already exists is refused rather than duplicated - and
# preflight catches it before a single object is created.
$provider4 = New-AudiSccmDryRunProvider -ExistingApplications @($package)
$run4 = Invoke-AudiSwIntegration -Plan (New-TestPlan) -Provider $provider4 -DryRun
Assert-True  'an existing application is refused' (-not $run4.Ok)
Assert-True  'the refusal explains why' ($run4.Message -like '*already exists*')
Assert-Equal 'no step ran at all - preflight stopped it' 0 $run4.Steps.Count
Assert-Equal 'nothing was created when refused' 0 $provider4.Log.Count

# ------------------------------------------------------------------ preflight
Write-Host ''
Write-Host 'Preflight' -ForegroundColor Cyan

# -DryRun, because the testing content share is a local path and SCCM only
# accepts a UNC one. That is a warning for a preview - which creates nothing -
# and a blocking error for a real run, checked separately below.
$pf = Test-AudiSwPrerequisite -Plan (New-TestPlan) -Provider (New-AudiSccmDryRunProvider) -DryRun
Assert-True  'preflight passes when everything is present' $pf.Ok
Assert-Equal 'nothing is blocking' 0 $pf.Blocking.Count

# SCCM refuses a local content path, and it refuses it INSIDE
# Add-CMScriptDeploymentType - after the application has been created. Catching
# it here is the difference between "nothing was created" and "an application was
# created and then rolled straight back out".
# A plan with a deliberately local content path. The environment files all carry
# real UNC stores now, so this cannot borrow one of them - and it should not:
# what is being tested is the check, not today's config.
$localPlan = New-TestPlan
$localPlan.ContentPath = 'C:\temp\INA_AUDI_DummyTest_x86_1.0_0001_MUL'
$localPath = Test-AudiSwPrerequisite -Plan $localPlan -Provider (New-AudiSccmDryRunProvider)
$uncCheck  = @($localPath.Findings | Where-Object { $_.Check -eq 'ContentPathIsUnc' })
Assert-Equal 'a local content share is checked'      1 $uncCheck.Count
Assert-True  'and a real run is stopped by it'       (-not $uncCheck[0].Ok)
Assert-True  'the run is refused before anything is created' (-not $localPath.Ok)
Assert-True  'the message says what to set, and where' `
    ($uncCheck[0].Message -like '*Content/@share*') $uncCheck[0].Message
Assert-True  'a preview only warns, so a plan can still be reviewed' `
    (@($pf.Findings | Where-Object { $_.Check -eq 'ContentPathIsUnc' })[0].Severity -eq 'Warning')

# The content checks run while the current location is the SITE DRIVE, and a
# path with no drive qualifier is resolved by the CURRENT provider. A UNC share
# has no drive qualifier, so without naming the filesystem provider a share that
# is sitting right there and perfectly readable comes back as "not found".
$providerLines = @(Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'Server\Engine\Src\Sccm.ps1'))
foreach ($probe in 'TestContentPath', 'TestContentShare', 'GetContentShareNames') {
    # the assignment and the two lines after it - these probes span more than one line
    $at = @(0..($providerLines.Count - 1) | Where-Object { $providerLines[$_] -match "^\s*$probe\s*=" })[0]
    $block = ($providerLines[$at..([Math]::Min($at + 2, $providerLines.Count - 1))] -join ' ')
    Assert-True "$probe pins itself to the filesystem provider" `
        ($block -like '*FileSystem::*') "a UNC content share would read as missing from the site drive: $block"
}

# -AddAppCategory wants a category OBJECT on a current console. Passing the name
# gives "Cannot convert the "Development" value of type System.String to type
# ...IResultObject" - which failed AFTER the application had been created, so a
# good application was rolled straight back out over a category.
$at = @(0..($providerLines.Count - 1) | Where-Object { $providerLines[$_] -match '^\s*SetCategory\s*=' })[0]
$categoryBlock = ($providerLines[$at..([Math]::Min($at + 10, $providerLines.Count - 1))] -join ' ')
Assert-True 'the category is looked up as an object, not passed as a name' `
    ($categoryBlock -like '*Get-CMCategory*') $categoryBlock
Assert-True 'and created when the site does not have it yet' `
    ($categoryBlock -like '*New-CMCategory*') $categoryBlock

# SCCM refuses an Available uninstall - nobody opts in to having software taken
# away. It has to be Required, and it is the LAST collection in every
# environment, so this fails at the very end of a run that has created everything.
$at = @(0..($providerLines.Count - 1) | Where-Object { $providerLines[$_] -match '^\s*NewDeployment\s*=' })[0]
$deployBlock = ($providerLines[$at..([Math]::Min($at + 24, $providerLines.Count - 1))] -join ' ')
Assert-True 'an uninstall deployment is Required, not Available' `
    ($deployBlock -like "*Uninstall*Required*") $deployBlock
# -DeployAction only takes Install or Uninstall. The environment file's word -
# Available, Required, Uninstall - describes the PURPOSE, and passing it as the
# action gives "Unable to match the identifier name Available".
Assert-True 'the action is never taken straight from the environment file' `
    ($deployBlock -notlike '*-DeployAction $c.DeploymentAction*') $deployBlock
Assert-True 'Available becomes an Install with an Available purpose' `
    ($deployBlock -like "*`$action = 'Install'*`$purpose = 'Available'*") $deployBlock

# Same object-versus-name trap as the category.
$at = @(0..($providerLines.Count - 1) | Where-Object { $providerLines[$_] -match '^\s*AddSecurityScope\s*=' })[0]
$scopeBlock = ($providerLines[$at..([Math]::Min($at + 12, $providerLines.Count - 1))] -join ' ')
Assert-True 'the security scope is looked up as an object first' `
    ($scopeBlock -like '*Get-CMSecurityScope*') $scopeBlock

# A distribution point group that exists but is EMPTY passes the existence check
# and then fails when content is distributed to it - after the application has
# been created. Warn about it up front instead.
# -DryRun so the local testing content share is a warning, not the thing that
# blocks - this check is about the distribution point group, nothing else.
$emptyDp = Test-AudiSwPrerequisite -Plan (New-TestPlan) -Provider (New-AudiSccmDryRunProvider -Missing @('DpGroupEmpty')) -DryRun
$dpMembers = @($emptyDp.Findings | Where-Object { $_.Check -eq 'DistributionPointGroupMembers' })
Assert-Equal 'an empty distribution point group is noticed' 1 $dpMembers.Count
Assert-True  'and it says content distribution would fail'  ($dpMembers[0].Message -like '*fails*') $dpMembers[0].Message
Assert-True  'but it does not block the run on its own' $emptyDp.Ok `
    'the count comes from a property that is not on every console build, so it must not be the thing that stops a run'

# Reading distribution PROGRESS is a convenience - SCCM finishes the
# distribution whether or not anyone is watching. A console that will not report
# it must not fail a step whose real work already succeeded, and must not sit in
# the wait loop for the whole timeout either.
$noStatus = Invoke-AudiSwIntegration -Plan (New-TestPlan) -DryRun `
                -Provider (New-AudiSccmDryRunProvider -Missing @('DistributionStatus'))
Assert-True 'an unreadable distribution status does not fail the run' $noStatus.Ok $noStatus.Message
$contentStep = @($noStatus.Steps | Where-Object { $_.Step -eq 'Content' })[0]
Assert-True 'the content step still succeeds' $contentStep.Ok $contentStep.Message
Assert-True 'and says the progress was not tracked' `
    ($contentStep.Message -like '*could not be read*') $contentStep.Message

# "not found" and "cannot be reached" need different fixes, so they must not
# share one message.
$noShare = Test-AudiSwPrerequisite -Plan (New-TestPlan) -Provider (New-AudiSccmDryRunProvider -Missing @('ContentPath', 'ContentShare'))
$noShareFinding = @($noShare.Findings | Where-Object { $_.Check -eq 'ContentPath' })[0]
Assert-True 'an unreachable share says so, and names the account' `
    ($noShareFinding.Message -like '*cannot be reached*') $noShareFinding.Message

$noFolder = Test-AudiSwPrerequisite -Plan (New-TestPlan) -Provider (New-AudiSccmDryRunProvider -Missing @('ContentPath'))
$noFolderFinding = @($noFolder.Findings | Where-Object { $_.Check -eq 'ContentPath' })[0]
Assert-True 'a reachable share with no package folder says THAT instead' `
    ($noFolderFinding.Message -like '*no folder named*') $noFolderFinding.Message
Assert-True 'and explains that browsing locally is not the same thing' `
    ($noFolderFinding.Message -like '*fills in the window*') $noFolderFinding.Message

# Each missing prerequisite must be caught, named, and must stop the run before
# anything is created. The old tool only ever checked the source folder.
$cases = @(
    @{ Name = 'a missing package source is caught';            Missing = @('ContentPath');              Check = 'ContentPath' },
    @{ Name = 'a missing limiting collection is caught';       Missing = @('Collection:INA010CA');      Check = 'LimitingCollection:INA010CA' },
    @{ Name = 'a missing distribution point group is caught';  Missing = @('DpGroup:INA-DP-Group all'); Check = 'DistributionPointGroup' },
    @{ Name = 'a missing security scope is caught';            Missing = @('Scope:INA00003');           Check = 'SecurityScope:INA00003' }
)
foreach ($case in $cases) {
    $p = New-AudiSccmDryRunProvider -Missing $case.Missing
    $r = Test-AudiSwPrerequisite -Plan (New-TestPlan) -Provider $p
    Assert-True $case.Name (-not $r.Ok)
    Assert-True "$($case.Check) is named in the findings" (@($r.Blocking | Where-Object { $_.Check -eq $case.Check }).Count -eq 1)

    $blockedRun = Invoke-AudiSwIntegration -Plan (New-TestPlan) -Provider $p -DryRun
    Assert-True  "the run is stopped by $($case.Check)" (-not $blockedRun.Ok)
    Assert-Equal "nothing was created for $($case.Check)" 0 $p.Log.Count
}

# A collection name already in use is caught too.
$pc = New-AudiSccmDryRunProvider -ExistingCollections @("GY1-$package")
Assert-True 'a collection name already in use is caught' (-not (Test-AudiSwPrerequisite -Plan (New-TestPlan) -Provider $pc).Ok)

# -SkipPreflight exists for a deliberate retry, and really does skip.
$ps = New-AudiSccmDryRunProvider -Missing @('ContentPath')
Assert-True 'SkipPreflight bypasses the checks' (Invoke-AudiSwIntegration -Plan (New-TestPlan) -Provider $ps -DryRun -SkipPreflight).Ok

# ----------------------------------------------------------- retry and audit
Write-Host ''
Write-Host 'Retry and audit trail' -ForegroundColor Cyan

Assert-True 'an RPC fault is treated as transient'     (Test-AudiTransientError -Message 'The RPC server is unavailable.')
Assert-True 'a timeout is treated as transient'        (Test-AudiTransientError -Message 'The operation timed out')
Assert-True 'a real error is NOT treated as transient' (-not (Test-AudiTransientError -Message 'Access is denied.'))

$script:tries = 0
$value = Invoke-AudiWithRetry -Description 'flaky call' -RetryCount 3 -Action {
    $script:tries++
    if ($script:tries -lt 3) { throw 'The RPC server is unavailable.' }
    'recovered'
}
Assert-Equal 'a transient fault is retried until it succeeds' 'recovered' $value
Assert-Equal 'it took three attempts' 3 $script:tries

# A permanent fault must fail at once, not be retried and reported late.
$script:tries = 0
$threw = $false
try { Invoke-AudiWithRetry -Description 'bad call' -RetryCount 3 -Action { $script:tries++; throw 'Access is denied.' } | Out-Null }
catch { $threw = $true }
Assert-True  'a permanent fault throws' $threw
Assert-Equal 'a permanent fault is not retried' 1 $script:tries

# Every run leaves an audit record - naming the service account and the RFC,
# and NEVER a person. This is Audi's requirement, checked on the artefacts the
# server actually writes rather than on the code that writes them.
$run5 = Invoke-AudiSwIntegration -Plan (New-TestPlan) -Provider (New-AudiSccmDryRunProvider) -DryRun
Assert-True 'the run reports where its log is' (-not [string]::IsNullOrWhiteSpace($run5.LogPath))
if ($run5.LogPath -and (Test-Path -LiteralPath $run5.LogPath)) {
    # The executor comes from config: a normal user while testing, the gMSA
    # later. Blank it out before looking for a person, or the check would trip
    # over the very account that is supposed to be there.
    $executor = (Get-AudiEnvironment -Code 'INA').Service.account
    $text = Get-Content -LiteralPath $run5.LogPath -Raw
    Assert-True 'the log names the executor'    ($text -like ('*' + $executor + '*'))
    Assert-True 'the log names the RFC'         ($text -like '*RFC0012345*')
    Assert-True 'the log marks it as a dry run' ($text -like '*DRY RUN*')

    $textNoExec = $text.Replace($executor, 'THE-EXECUTOR')
    Assert-True 'the log names nobody but the executor' `
        (-not ($textNoExec -like "*$env:USERNAME*" -or $textNoExec -like '*tester*')) 'a user name reached the server log'

    $jobFile = Join-Path (Split-Path -Parent $run5.LogPath) 'job.json'
    Assert-True 'a job record is written' (Test-Path -LiteralPath $jobFile)
    if (Test-Path -LiteralPath $jobFile) {
        $raw = Get-Content -LiteralPath $jobFile -Raw
        $job = $raw | ConvertFrom-Json
        Assert-Equal 'the job record keeps the executor'  $executor    $job.Executor
        Assert-Equal 'the job record keeps the RFC'       'RFC0012345' $job.Rfc
        Assert-Equal 'the job record states the outcome'  'Succeeded'  $job.Outcome
        Assert-True  'the job record has no Requester field' (-not $job.PSObject.Properties['Requester'])
        # JSON escapes the backslash, so DOMAIN\user is written DOMAIN\\user -
        # blank out both spellings before looking for a person
        $rawNoExec = $raw.Replace($executor.Replace('\', '\\'), 'THE-EXECUTOR').Replace($executor, 'THE-EXECUTOR')
        Assert-True  'the job record names nobody but the executor' `
            (-not ($rawNoExec -like "*$env:USERNAME*" -or $rawNoExec -like '*tester*')) 'a user name reached job.json'
    }
} else {
    Assert-True 'the log file was created' $false "log not found at $($run5.LogPath)"
}

# ---------------------------------------------------------------- guard rails
Write-Host ''
Write-Host 'Guard rails' -ForegroundColor Cyan

# PCZ still holds values copied from INA, so a real run must be blocked.
$pczPlan = New-TestPlan -Code 'PCZ'
$blocked = Invoke-AudiSwIntegration -Plan $pczPlan -Provider (New-AudiSccmDryRunProvider)
Assert-True 'an unverified environment is blocked from a real run' (-not $blocked.Ok)
Assert-True 'the block explains that values need confirming' ($blocked.Message -like '*unverified*')
Assert-Equal 'no steps ran for the blocked environment' 0 $blocked.Steps.Count

# A dry run of the same environment is still allowed, so it can be reviewed.
$pczPreview = Invoke-AudiSwIntegration -Plan $pczPlan -Provider (New-AudiSccmDryRunProvider) -DryRun
Assert-True  'an unverified environment can still be previewed' $pczPreview.Ok
Assert-Equal 'the PCZ preview covers ten collections' 10 (@($pczPreview.Provider.Log | Where-Object Operation -eq 'NewCollection').Count)

# ---------------------------------------------------------- the package lock
# Two jobs on the same package would half-create objects under both. The refusal
# has to SAY that. It used to clear the lock before reading its message, so the
# real reason was replaced by a StrictMode complaint - "The property 'Message'
# cannot be found on this object" - which tells an operator nothing at all.
# The lock is checked before the site is touched, so this needs no SCCM.
Write-Host ''
Write-Host 'The package lock' -ForegroundColor Cyan

$lockPlan = New-TestPlan
$held = Enter-AudiPackageLock -Plan $lockPlan -Root $null
try {
    Assert-True 'the first job takes the lock' $held.Ok $held.Message

    $blocked = Invoke-AudiSwIntegration -Plan (New-TestPlan) -Provider (New-AudiSccmDryRunProvider)
    Assert-True  'a second job on the same package is refused' (-not $blocked.Ok)
    Assert-True  'and the refusal names the package and the job holding it' `
        ($blocked.Message -like '*already being integrated*') $blocked.Message
    Assert-True  'the reason is the lock, not a property error' `
        ($blocked.Message -notlike '*cannot be found on this object*') $blocked.Message
    Assert-Equal 'nothing ran while it was locked' 0 @($blocked.Steps).Count
}
finally { Exit-AudiPackageLock -Lock $held }

# and the lock is free again once it is released
$after = Enter-AudiPackageLock -Plan (New-TestPlan) -Root $null
Assert-True 'the lock is released, so the next job can run' $after.Ok $after.Message
Exit-AudiPackageLock -Lock $after

# ---------------------------------------------------------------- modify
# Modify reconciles an application that already exists: add what is missing,
# retire what the environment file no longer asks for, update what changed. It
# must never create a second application, and it must never touch a collection
# that does not belong to this package.
Write-Host ''
Write-Host 'Modify - reconciling an existing application' -ForegroundColor Cyan

$modPlan = New-TestPlan
$allCollections = @($modPlan.Collections | ForEach-Object { $_.Name })

# nothing exists yet -> Modify must refuse rather than silently create
$noApp = Invoke-AudiSwModification -Plan $modPlan -Provider (New-AudiSccmDryRunProvider) -DryRun
Assert-True 'Modify refuses when the application does not exist' (-not $noApp.Ok)
Assert-True 'and says to use Integrate instead' ($noApp.Steps[0].Message -like '*Integrate*')

# fully in step already -> updates the definition, adds nothing
$upToDate = New-AudiSccmDryRunProvider -ExistingApplications @($modPlan.ApplicationName) `
                                       -ExistingCollections $allCollections -ExistingDeployments $allCollections
$same = Invoke-AudiSwModification -Plan $modPlan -Provider $upToDate -DryRun
Assert-True  'a package already in step succeeds' $same.Ok $same.Message
Assert-Equal 'no collection is created'  0 (@($upToDate.Log | Where-Object Operation -eq 'NewCollection').Count)
Assert-Equal 'no deployment is created'  0 (@($upToDate.Log | Where-Object Operation -eq 'NewDeployment').Count)
Assert-Equal 'nothing is retired'        0 (@($upToDate.Log | Where-Object Operation -eq 'RemoveCollection').Count)
Assert-Equal 'the application is updated, not created' 1 (@($upToDate.Log | Where-Object Operation -eq 'SetApplication').Count)
Assert-Equal 'no second application is made' 0 (@($upToDate.Log | Where-Object Operation -eq 'NewApplication').Count)
Assert-True  'the deployment type is refreshed' (@($upToDate.Log | Where-Object Operation -eq 'SetDeploymentType').Count -eq 1)

# three collections missing -> exactly those three are added, with deployments
$partial = @($allCollections | Select-Object -First 6)
$gapped  = New-AudiSccmDryRunProvider -ExistingApplications @($modPlan.ApplicationName) `
                                      -ExistingCollections $partial -ExistingDeployments $partial
$filled = Invoke-AudiSwModification -Plan $modPlan -Provider $gapped -DryRun
Assert-True  'a partial package is completed' $filled.Ok $filled.Message
Assert-Equal 'exactly the missing collections are added' 3 (@($gapped.Log | Where-Object Operation -eq 'NewCollection').Count)
Assert-Equal 'and their deployments'                     3 (@($gapped.Log | Where-Object Operation -eq 'NewDeployment').Count)
Assert-Equal 'nothing is retired'                        0 (@($gapped.Log | Where-Object Operation -eq 'RemoveCollection').Count)
Assert-True  'the changes are listed for the operator'   ($filled.Changed.Count -ge 3)

# a collection the environment file no longer asks for -> retired
$stale   = $allCollections + 'SM1-INA_AUDI_DummyTest_x86_1.0_0001_MUL_Retired'
$retiring = New-AudiSccmDryRunProvider -ExistingApplications @($modPlan.ApplicationName) `
                                       -ExistingCollections $stale -ExistingDeployments $stale
$retired = Invoke-AudiSwModification -Plan $modPlan -Provider $retiring -DryRun
Assert-True  'a package with a stale collection succeeds' $retired.Ok $retired.Message
Assert-Equal 'exactly the stale collection is removed' 1 (@($retiring.Log | Where-Object Operation -eq 'RemoveCollection').Count)
Assert-Equal 'its deployment goes with it'            1 (@($retiring.Log | Where-Object Operation -eq 'RemoveDeployment').Count)
Assert-True  'and it is the right one' ((@($retiring.Log | Where-Object Operation -eq 'RemoveCollection')[0]).Detail -like '*_Retired')
Assert-Equal 'the wanted collections are left alone'  0 (@($retiring.Log | Where-Object { $_.Operation -eq 'RemoveCollection' -and $_.Detail -notlike '*_Retired' }).Count)

# the application itself is never removed by Modify
Assert-Equal 'Modify never removes the application' 0 (@($retiring.Log | Where-Object Operation -eq 'RemoveApplication').Count)

# German reaches SCCM as well as English
$dePlan = Get-AudiIntegrationPlan -PackageName 'INA_AUDI_DummyTest_x86_1.0_0001_MUL' -EnvironmentCode 'INA' -Rfc 'R' `
                                  -LocalizedName 'Adobe Reader' -LocalizedNameDe 'Adobe Lesegeraet' `
                                  -LocalizedDescriptionDe 'Liest PDF-Dokumente.'
Assert-Equal 'the plan carries the German name'        'Adobe Lesegeraet'     $dePlan.LocalizedNameDe
Assert-Equal 'the plan carries the German description' 'Liest PDF-Dokumente.' $dePlan.LocalizedDescriptionDe
$deFallback = Get-AudiIntegrationPlan -PackageName 'INA_AUDI_DummyTest_x86_1.0_0001_MUL' -EnvironmentCode 'INA' -Rfc 'R' -LocalizedName 'Only English'
Assert-Equal 'German falls back to English when not given' 'Only English' $deFallback.LocalizedNameDe

# A package named for one environment must not be published into another. The old
# tool rewrote the first three characters instead, which is what turned
# ADO_ADOBE_Reader into INA_INABE_Reader.
$crossed  = Get-AudiIntegrationPlan -PackageName 'INA_AUDI_DummyTest_x86_1.0_0001_MUL' -EnvironmentCode 'ICZ' -Rfc 'RFC0012345'
$crossPre = Test-AudiSwPrerequisite -Plan $crossed -Provider (New-AudiSccmDryRunProvider)
$sitePrefix = @($crossPre.Findings | Where-Object { $_.Check -eq 'SitePrefix' })
Assert-Equal 'the site prefix is checked'                1 $sitePrefix.Count
Assert-True  'an INA package into ICZ is rejected'       (-not $sitePrefix[0].Ok)
Assert-True  'and it blocks the run'                     (-not $crossPre.Ok)
Assert-True  'the message names both sides'              ($sitePrefix[0].Message -like "*INA*ICZ*")

$aligned = Test-AudiSwPrerequisite -Plan (New-TestPlan -Code 'ICZ') -Provider (New-AudiSccmDryRunProvider)
Assert-True  'a matching prefix passes' (@($aligned.Findings | Where-Object { $_.Check -eq 'SitePrefix' })[0].Ok)

# One identity only: the shared account. A person must not survive into the result.
Assert-True  'the result carries no requester' (-not $run.PSObject.Properties['Requester'])
Assert-Equal 'the executor is the environment service account' (Get-AudiEnvironment -Code 'INA').Service.account $run.Executor
Assert-True  'the job id is carried through' ($run.JobId -eq $plan.JobId)

# ---------------------------------------------------------------- removal
Write-Host ''
Write-Host 'Removal' -ForegroundColor Cyan
$provider5 = New-AudiSccmDryRunProvider
$rem = Invoke-AudiSwRemoval -Plan (New-TestPlan) -Provider $provider5 -DryRun
Assert-True  'removal reports success' $rem.Ok $rem.Message
$remLog = $provider5.Log.ToArray()
Assert-Equal 'nine deployments removed' 9 (@($remLog | Where-Object Operation -eq 'RemoveDeployment').Count)
Assert-Equal 'nine collections removed' 9 (@($remLog | Where-Object Operation -eq 'RemoveCollection').Count)
Assert-Equal 'one application removed'  1 (@($remLog | Where-Object Operation -eq 'RemoveApplication').Count)
$depIdx = [array]::IndexOf(@($remLog | ForEach-Object { $_.Operation }), 'RemoveDeployment')
$colIdx = [array]::IndexOf(@($remLog | ForEach-Object { $_.Operation }), 'RemoveCollection')
Assert-True 'deployments are removed before collections' ($depIdx -lt $colIdx)

# If removing deployments fails, collections and the application must be skipped
# rather than attempted anyway.
$provider6 = New-AudiSccmDryRunProvider -FailOn 'RemoveDeployment'
$rem2 = Invoke-AudiSwRemoval -Plan (New-TestPlan) -Provider $provider6 -DryRun
Assert-True  'a failed removal reports failure' (-not $rem2.Ok)
Assert-True  'collection removal is skipped when deployment removal fails' `
             ((@($rem2.Steps | Where-Object Step -eq 'Collections')[0].Message) -like 'Skipped*')
Assert-Equal 'no collections were removed' 0 (@($provider6.Log | Where-Object Operation -eq 'RemoveCollection').Count)
Assert-True  'the independent AD group step still ran' (@($rem2.Steps | Where-Object { $_.Step -eq 'ArsGroup' -and $_.Ok }).Count -eq 1)

# ---------------------------------------------------------------- summary
Write-Host ''
if ($script:Fail -eq 0) { Write-Host ("All {0} checks passed." -f $script:Pass) -ForegroundColor Green }
else                    { Write-Host ("{0} passed, {1} FAILED." -f $script:Pass, $script:Fail) -ForegroundColor Red }
Write-Host ''
exit $(if ($script:Fail -eq 0) { 0 } else { 1 })
