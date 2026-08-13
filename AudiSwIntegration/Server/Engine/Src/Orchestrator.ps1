# ==============================================================================
#  Audi SCCM Integration Tool - running a job end to end
# ==============================================================================
#  Integrate, Modify and Remove: order, retry, rollback, logging and the result
#  object the window reads.
#
#  Every step returns a result and this READS it. The tool being replaced threw
#  the result away and set its label to "Done." unconditionally, so a failed step
#  looked exactly like a successful one.
#
#  Dot-sourced by AudiSwIntegration.ps1. ASCII only.
# ==============================================================================

Set-StrictMode -Version 2.0

# --------------------------------------------------------------- orchestrator

function Invoke-AudiSwIntegration {
    <#  Runs the integration in order, checking every step.
        -DryRun walks the plan without touching anything (the packager preview).
        -NoRollback keeps whatever succeeded, for deliberate investigation.  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Plan,
        $Provider,
        [switch]$DryRun,
        [switch]$NoRollback,
        [switch]$AllowUnverifiedEnvironment,
        [switch]$SkipPreflight,
        [string]$Root,
        [scriptblock]$OnProgress
    )

    if (-not $Provider) { $Provider = if ($DryRun) { New-AudiSccmDryRunProvider } else { New-AudiSccmProvider } }

    $results  = New-Object System.Collections.Generic.List[object]
    $created  = New-Object System.Collections.Generic.List[object]
    $rollback = @()
    $log      = New-AudiLogContext -Plan $Plan -Root $Root -DryRun:$DryRun
    $lock     = $null

    $finish = {
        param($ok, $message, $preflight)
        Exit-AudiPackageLock -Lock $lock
        $result = [pscustomobject]@{
            Ok = $ok; JobId = $Plan.JobId; Environment = $Plan.Environment; Package = $Plan.PackageName
            Executor = $Plan.Executor; DryRun = [bool]$DryRun
            Message = $message; Steps = $results.ToArray(); RolledBack = $rollback
            Preflight = $preflight; LogPath = $log.LogPath; Provider = $Provider
        }
        Write-AudiLog -Context $log -Level $(if ($ok) { 'Info' } else { 'Error' }) -Message $message
        $null = Save-AudiJobRecord -Context $log -Plan $Plan -Result $result
        return $result
    }

    # RFC, not a person: no real name is written on the SCCM side
    Write-AudiLog -Context $log -Message ("Job {0} | package {1} | environment {2} | RFC {3} | executed as {4}{5}" -f `
        $Plan.JobId, $Plan.PackageName, $Plan.Environment, $(if ($Plan.Rfc) { $Plan.Rfc } else { 'none' }),
        $Plan.Executor, $(if ($DryRun) { ' | DRY RUN' } else { '' }))

    # An environment whose values were inherited from another one must not be
    # used by accident. This is what stops PCZ running on INA's settings.
    if (-not $Plan.Verified -and -not $AllowUnverifiedEnvironment -and -not $DryRun) {
        return & $finish $false "Environment $($Plan.Environment) is marked unverified - its settings still need confirming by Audi. Re-run with -AllowUnverifiedEnvironment only if that is intended." $null
    }

    # One package, one environment, one job at a time.
    if (-not $DryRun) {
        $lock = Enter-AudiPackageLock -Plan $Plan -Root $Root
        if (-not $lock.Ok) {
            # Read the reason BEFORE clearing it. $finish releases whatever $lock
            # holds and we never took one, but clearing it first leaves
            # $null.Message, which throws under StrictMode - and then the real
            # reason is replaced by "The property 'Message' cannot be found".
            $reason = [string]$lock.Message
            $lock = $null
            return & $finish $false $reason $null
        }
    }

    # From here on the lock is held, so everything runs inside a try/finally.
    # Connecting and preflight both THROW on some failures rather than returning,
    # and an exception escaping this function skips $finish entirely - which
    # leaves the lock file behind. Every later run of that package then fails on
    # a lock nobody holds, until it ages out.
    try {
        $connection = Connect-AudiSccm -Plan $Plan -DryRun:$DryRun
        if (-not $connection.Ok) { return & $finish $false $connection.Message $null }
        Write-AudiLog -Context $log -Message $connection.Message

        # Fail before creating anything, rather than halfway through and rolling back.
        $preflight = $null
        if (-not $SkipPreflight) {
            Write-AudiLog -Context $log -Step 'Preflight' -Message 'Checking prerequisites.'
            $preflight = Test-AudiSwPrerequisite -Plan $Plan -Provider $Provider -Root $Root -DryRun:$DryRun
            foreach ($finding in $preflight.Findings) {
                Write-AudiLog -Context $log -Step 'Preflight' -Level $(if ($finding.Ok) { 'Info' } elseif ($finding.Severity -eq 'Warning') { 'Warn' } else { 'Error' }) -Message "$($finding.Check): $($finding.Message)"
            }
            if (-not $preflight.Ok) {
                $reasons = ($preflight.Blocking | ForEach-Object { $_.Message }) -join ' '
                return & $finish $false "Prerequisites not met, so nothing was created. $reasons" $preflight
            }
        }

    $succeeded = New-Object System.Collections.Generic.HashSet[string]
    $failed    = $false

    $stepTotal = @(Get-AudiIntegrationStep).Count
    foreach ($step in (Get-AudiIntegrationStep)) {

        # order is enforced here, not trusted to the operator
        $missing = @($step.DependsOn | Where-Object { -not $succeeded.Contains($_) })
        if ($missing.Count -gt 0) {
            $skip = "Skipped - depends on $($missing -join ', '), which did not succeed."
            $results.Add([pscustomobject]@{ Step = $step.Key; Name = $step.Name; Ok = $false; Message = $skip }) | Out-Null
            Write-AudiLog -Context $log -Step $step.Key -Level 'Warn' -Message $skip
            $failed = $true
            continue
        }

        # Extra arguments so a caller that wants to report progress onward - the
        # collector writing its heartbeat - can say how far through it is. A
        # handler declaring only param($stepName) simply ignores the rest.
        if ($OnProgress) { & $OnProgress $step.Name ($results.Count + 1) $stepTotal $results.ToArray() }
        Write-AudiLog -Context $log -Step $step.Key -Message $step.Name

        try {
            # transient site faults are retried; a real error fails immediately
            $stepKey = $step.Key
            $message = Invoke-AudiWithRetry -Description $step.Name -LogContext $log -Step $stepKey -Root $Root -Action {
                Invoke-AudiStepBody -Key $stepKey -Plan $Plan -Provider $Provider -Created $created
            }

            # content distribution is not finished when the command returns
            if ($step.Key -eq 'Content') {
                $wait = Wait-AudiContentDistribution -Plan $Plan -Provider $Provider -LogContext $log -Root $Root -DryRun:$DryRun
                if (-not $wait.Ok) { throw $wait.Message }
                $message = "$message $($wait.Message)"
            }

            $null = $succeeded.Add($step.Key)
            $results.Add([pscustomobject]@{ Step = $step.Key; Name = $step.Name; Ok = $true; Message = $message }) | Out-Null
            Write-AudiLog -Context $log -Step $step.Key -Message $message
        }
        catch {
            # a failure is reported as a failure - the old tool said "Done."
            # never $_.Exception.Message straight through: an empty one fails the log
            # call and replaces the real reason with a binding error
            $reason = Get-AudiErrorText -ErrorRecord $_ -Context "$($step.Name) failed."
            $results.Add([pscustomobject]@{ Step = $step.Key; Name = $step.Name; Ok = $false; Message = $reason }) | Out-Null
            Write-AudiLog -Context $log -Step $step.Key -Level 'Error' -Message $reason
            $failed = $true
            break
        }
    }

        if ($failed -and -not $NoRollback -and $created.Count -gt 0) {
            Write-AudiLog -Context $log -Step 'Rollback' -Level 'Warn' -Message "Rolling back $($created.Count) created object(s)."
            $rollback = Undo-AudiCreatedObject -Plan $Plan -Provider $Provider -Created $created
            foreach ($undone in $rollback) { Write-AudiLog -Context $log -Step 'Rollback' -Message $undone }
        }

        $okCount = @($results | Where-Object { $_.Ok }).Count

        # Say plainly what is left on the site. "Failed after 0 of 8 steps" does
        # not tell an operator whether an application is sitting there half-made,
        # and that is the first thing they need to know.
        $state = if (-not $failed) { '' }
                 elseif (@($rollback).Count -gt 0) {
                     $stuck = @($rollback | Where-Object { $_ -like '*COULD NOT BE REMOVED*' })
                     if ($stuck.Count -gt 0) {
                         " {0} object(s) were rolled back but {1} could NOT be removed and are still on the site: {2}." -f `
                             (@($rollback).Count - $stuck.Count), $stuck.Count, ($stuck -join '; ')
                     } else {
                         " Everything it had created was rolled back, so nothing was left on the site: {0}." -f (@($rollback) -join '; ')
                     }
                 }
                 elseif ($created.Count -gt 0) { " {0} object(s) were created and NOT rolled back: {1}." -f $created.Count, (@($created | ForEach-Object { "$($_.Kind) $($_.Name)" }) -join '; ') }
                 else { ' Nothing had been created yet, so nothing was left on the site.' }

        $summary = if ($failed) { "Integration failed after $okCount of $(@(Get-AudiIntegrationStep).Count) steps.$state" }
                   else { "Integration completed - $okCount steps." }
        return & $finish (-not $failed) $summary $preflight
    }
    finally {
        # $finish releases the lock on every path that returns a result. This
        # catches the paths that do not - an exception on the way out - so a
        # crash can never leave the package locked against its next run.
        Exit-AudiPackageLock -Lock $lock
    }
}

function Invoke-AudiSwModification {
    <#  Brings an application that already exists back into line.

        Deliberately NOT rolled back on failure. A rollback would have to undo
        changes to an application that is already live and already deployed to
        real machines, and half-undoing that is worse than stopping. Instead the
        run stops at the first failure and reports exactly what it had changed
        up to that point, so the operator can decide.  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Plan,
        $Provider,
        [switch]$DryRun,
        [switch]$AllowUnverifiedEnvironment,
        [scriptblock]$OnProgress
    )

    # A Modify rehearsal has to assume the application is already there. Modify
    # exists only for applications that exist, so a dry-run provider that reports
    # nothing on the site would fail every rehearsal at the first step with "use
    # Integrate instead" - which is what a packager testing the flow hits, and it
    # tells them nothing. Seeded with this package's own objects, the rehearsal
    # shows the shape of a real Modify. A caller that wants to rehearse a
    # different starting state passes its own provider.
    if (-not $Provider) {
        $Provider = if ($DryRun) {
            New-AudiSccmDryRunProvider -ExistingApplications @($Plan.ApplicationName) `
                                       -ExistingCollections  @($Plan.Collections | ForEach-Object { $_.Name }) `
                                       -ExistingDeployments  @($Plan.Collections | ForEach-Object { $_.Name })
        } else { New-AudiSccmProvider }
    }
    $log = New-AudiLogContext -Plan $Plan -Root $null -DryRun:$DryRun

    if (-not $Plan.Verified -and -not $AllowUnverifiedEnvironment -and -not $DryRun) {
        return [pscustomobject]@{ Ok = $false; JobId = $Plan.JobId; Environment = $Plan.Environment; Package = $Plan.PackageName
            Executor = $Plan.Executor; DryRun = [bool]$DryRun; Changed = @()
            Message = "Environment $($Plan.Environment) is marked unverified - its settings still need confirming by Audi."
            Steps = @(); Provider = $Provider }
    }

    $connection = Connect-AudiSccm -Plan $Plan -DryRun:$DryRun
    if (-not $connection.Ok) {
        return [pscustomobject]@{ Ok = $false; JobId = $Plan.JobId; Environment = $Plan.Environment; Package = $Plan.PackageName
            Executor = $Plan.Executor; DryRun = [bool]$DryRun; Changed = @()
            Message = $connection.Message; Steps = @(); Provider = $Provider }
    }

    Write-AudiLog -Context $log -Message ("Job {0} | MODIFY {1} | environment {2} | RFC {3} | executed as {4}{5}" -f `
        $Plan.JobId, $Plan.PackageName, $Plan.Environment, $(if ($Plan.Rfc) { $Plan.Rfc } else { 'none' }),
        $Plan.Executor, $(if ($DryRun) { ' | DRY RUN' } else { '' }))

    $results   = New-Object System.Collections.Generic.List[object]
    $changed   = New-Object System.Collections.Generic.List[string]
    $succeeded = New-Object System.Collections.Generic.HashSet[string]
    $failed    = $false

    $stepTotal = @(Get-AudiModifyStep).Count
    foreach ($step in (Get-AudiModifyStep)) {
        $missing = @($step.DependsOn | Where-Object { -not $succeeded.Contains($_) })
        if ($missing.Count -gt 0) {
            $results.Add([pscustomobject]@{ Step = $step.Key; Name = $step.Name; Ok = $false
                Message = "Skipped - depends on $($missing -join ', '), which did not succeed." }) | Out-Null
            $failed = $true
            continue
        }
        # Extra arguments so a caller that wants to report progress onward - the
        # collector writing its heartbeat - can say how far through it is. A
        # handler declaring only param($stepName) simply ignores the rest.
        if ($OnProgress) { & $OnProgress $step.Name ($results.Count + 1) $stepTotal $results.ToArray() }
        try {
            # $stepKey, not $step.Key: Invoke-AudiWithRetry has its own -Step
            # parameter, and PowerShell variable names are case-insensitive, so
            # inside the scriptblock $step would resolve to that parameter.
            $stepKey = $step.Key
            $message = Invoke-AudiWithRetry -Description $step.Name -LogContext $log -Step $stepKey -Action {
                Invoke-AudiModifyStepBody -Key $stepKey -Plan $Plan -Provider $Provider -Changed $changed
            }
            $null = $succeeded.Add($step.Key)
            $results.Add([pscustomobject]@{ Step = $step.Key; Name = $step.Name; Ok = $true; Message = $message }) | Out-Null
            Write-AudiLog -Context $log -Step $step.Key -Message $message
        }
        catch {
            # never $_.Exception.Message straight through: an empty one fails the log
            # call and replaces the real reason with a binding error
            $reason = Get-AudiErrorText -ErrorRecord $_ -Context "$($step.Name) failed."
            $results.Add([pscustomobject]@{ Step = $step.Key; Name = $step.Name; Ok = $false; Message = $reason }) | Out-Null
            Write-AudiLog -Context $log -Step $step.Key -Level 'Error' -Message $reason
            $failed = $true
            break
        }
    }

    $okCount = @($results | Where-Object { $_.Ok }).Count
    $result = [pscustomobject]@{
        Ok = (-not $failed); JobId = $Plan.JobId; Environment = $Plan.Environment; Package = $Plan.PackageName
        Executor = $Plan.Executor; DryRun = [bool]$DryRun
        Changed = $changed.ToArray()
        Message = $(if ($failed) { "Modification stopped after $okCount of $(@(Get-AudiModifyStep).Count) steps - $($changed.Count) change(s) had already been made." }
                    elseif ($changed.Count -eq 0) { 'Nothing to change - already up to date.' }
                    else { "Modification completed - $($changed.Count) change(s)." })
        Steps = $results.ToArray(); LogPath = $log.LogPath; Provider = $Provider
    }
    Write-AudiLog -Context $log -Level $(if ($result.Ok) { 'Info' } else { 'Error' }) -Message $result.Message
    $null = Save-AudiJobRecord -Context $log -Plan $Plan -Result $result
    return $result
}

function Invoke-AudiSwRemoval {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Plan,
        $Provider,
        [switch]$DryRun,
        [switch]$AllowUnverifiedEnvironment,
        [scriptblock]$OnProgress
    )

    if (-not $Provider) { $Provider = if ($DryRun) { New-AudiSccmDryRunProvider } else { New-AudiSccmProvider } }

    if (-not $Plan.Verified -and -not $AllowUnverifiedEnvironment -and -not $DryRun) {
        return [pscustomobject]@{ Ok = $false; JobId = $Plan.JobId; Environment = $Plan.Environment
            Message = "Environment $($Plan.Environment) is marked unverified."; Steps = @(); Provider = $Provider }
    }

    $connection = Connect-AudiSccm -Plan $Plan -DryRun:$DryRun
    if (-not $connection.Ok) {
        return [pscustomobject]@{ Ok = $false; JobId = $Plan.JobId; Environment = $Plan.Environment
            Message = $connection.Message; Steps = @(); Provider = $Provider }
    }

    $results   = New-Object System.Collections.Generic.List[object]
    $succeeded = New-Object System.Collections.Generic.HashSet[string]
    $failed    = $false

    $stepTotal = @(Get-AudiRemovalStep).Count
    foreach ($step in (Get-AudiRemovalStep)) {
        $missing = @($step.DependsOn | Where-Object { -not $succeeded.Contains($_) })
        if ($missing.Count -gt 0) {
            $results.Add([pscustomobject]@{ Step = $step.Key; Name = $step.Name; Ok = $false
                Message = "Skipped - depends on $($missing -join ', '), which did not succeed." }) | Out-Null
            $failed = $true
            continue
        }
        # Extra arguments so a caller that wants to report progress onward - the
        # collector writing its heartbeat - can say how far through it is. A
        # handler declaring only param($stepName) simply ignores the rest.
        if ($OnProgress) { & $OnProgress $step.Name ($results.Count + 1) $stepTotal $results.ToArray() }
        try {
            $message = Invoke-AudiRemovalStepBody -Key $step.Key -Plan $Plan -Provider $Provider
            $null = $succeeded.Add($step.Key)
            $results.Add([pscustomobject]@{ Step = $step.Key; Name = $step.Name; Ok = $true; Message = $message }) | Out-Null
        }
        catch {
            # never $_.Exception.Message straight through: an empty one fails the log
            # call and replaces the real reason with a binding error
            $reason = Get-AudiErrorText -ErrorRecord $_ -Context "$($step.Name) failed."
            $results.Add([pscustomobject]@{ Step = $step.Key; Name = $step.Name; Ok = $false; Message = $reason }) | Out-Null
            $failed = $true
            # removal does not stop: independent steps are still attempted
        }
    }

    $okCount = @($results | Where-Object { $_.Ok }).Count
    return [pscustomobject]@{
        Ok = (-not $failed); JobId = $Plan.JobId; Environment = $Plan.Environment; Package = $Plan.PackageName
        Executor = $Plan.Executor; DryRun = [bool]$DryRun
        Message = $(if ($failed) { "Removal finished with failures - $okCount of $(@(Get-AudiRemovalStep).Count) steps succeeded." } else { "Removal completed - $okCount steps." })
        Steps = $results.ToArray(); Provider = $Provider
    }
}
