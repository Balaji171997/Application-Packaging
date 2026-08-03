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
function New-TestPlan { param([string]$Code = 'INA')
    Get-AudiIntegrationPlan -PackageName $package -EnvironmentCode $Code -Rfc 'RFC0012345'
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

$pf = Test-AudiSwPrerequisite -Plan (New-TestPlan) -Provider (New-AudiSccmDryRunProvider)
Assert-True  'preflight passes when everything is present' $pf.Ok
Assert-Equal 'nothing is blocking' 0 $pf.Blocking.Count

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
    $text = Get-Content -LiteralPath $run5.LogPath -Raw
    Assert-True 'the log names the executor'    ($text -like '*svc-swintegration*')
    Assert-True 'the log names the RFC'         ($text -like '*RFC0012345*')
    Assert-True 'the log marks it as a dry run' ($text -like '*DRY RUN*')
    Assert-True 'the log names NO person'       (-not ($text -like "*$env:USERNAME*" -or $text -like '*tester*')) 'a user name reached the server log'

    $jobFile = Join-Path (Split-Path -Parent $run5.LogPath) 'job.json'
    Assert-True 'a job record is written' (Test-Path -LiteralPath $jobFile)
    if (Test-Path -LiteralPath $jobFile) {
        $raw = Get-Content -LiteralPath $jobFile -Raw
        $job = $raw | ConvertFrom-Json
        Assert-Equal 'the job record keeps the executor'  'deaudi00\svc-swintegration' $job.Executor
        Assert-Equal 'the job record keeps the RFC'       'RFC0012345'                 $job.Rfc
        Assert-Equal 'the job record states the outcome'  'Succeeded'                  $job.Outcome
        Assert-True  'the job record has no Requester field' (-not $job.PSObject.Properties['Requester'])
        Assert-True  'the job record names NO person' (-not ($raw -like "*$env:USERNAME*" -or $raw -like '*tester*')) 'a user name reached job.json'
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

# One identity only: the shared account. A person must not survive into the result.
Assert-True  'the result carries no requester' (-not $run.PSObject.Properties['Requester'])
Assert-Equal 'the executor is the service account' 'deaudi00\svc-swintegration' $run.Executor
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
