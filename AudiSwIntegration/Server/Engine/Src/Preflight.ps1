# ==============================================================================
#  Audi SCCM Integration Tool - checks before anything is created
# ==============================================================================
#  Everything that can be known BEFORE the first object is made, and the wait for
#  content to reach the distribution points.
#
#  The old tool checked that the source folder existed and then started creating
#  things, discovering a missing limiting collection or a mistyped scope halfway
#  through. Failing here costs nothing and leaves the site untouched.
#
#  Dot-sourced by AudiSwIntegration.ps1. ASCII only.
# ==============================================================================

Set-StrictMode -Version 2.0

# ------------------------------------------------------------------ preflight

function Test-AudiSwPrerequisite {
    <#  Checks everything the run depends on BEFORE anything is created.

        The old tool only checked that the source folder existed, then started
        creating objects and discovered a missing limiting collection or a
        mistyped scope halfway through. Failing here costs nothing and leaves
        the site untouched.

        Returns @{ Ok; Findings; Blocking }. A finding with Severity 'Error'
        blocks the run; 'Warning' is reported and allowed.  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)]$Provider,
        [string]$Root,
        # A preview creates nothing, so a finding that only a real site would
        # object to is reported rather than blocking.
        [switch]$DryRun
    )

    $findings = New-Object System.Collections.Generic.List[object]
    $add = { param($check, $ok, $severity, $message)
        $findings.Add([pscustomobject]@{ Check = $check; Ok = $ok; Severity = $severity; Message = $message }) | Out-Null
    }

    # 1. the package source must be on the content share.
    #
    #    "Not found" has two completely different causes and two completely
    #    different fixes: the folder really is missing, or this account cannot
    #    reach the share at all. Test-Path answers false for both, so the share
    #    is checked separately - a cross-domain share that the collector's
    #    account has no rights on looks exactly like a missing folder otherwise.
    $hasContent = & $Provider.TestContentPath @{ Path = $Plan.ContentPath }
    if ($hasContent) {
        & $add 'ContentPath' $true 'Error' "Source found: $($Plan.ContentPath)"
    }
    else {
        $shareRoot  = Split-Path -Parent $Plan.ContentPath
        $shareThere = & $Provider.TestContentShare @{ Path = $shareRoot }
        $who        = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

        if (-not $shareThere) {
            & $add 'ContentPath' $false 'Error' ("The content share itself cannot be reached: $shareRoot. " +
                "This runs as $who - check that account can open the share from THIS machine, and that the path in " +
                "Config\Environments\$($Plan.Environment).xml is right. A share in another domain usually means the " +
                "account has no rights on it.")
        }
        else {
            $names = @(& $Provider.GetContentShareNames @{ Path = $shareRoot })
            $near  = if ($names.Count -gt 0) { " The share does contain: $($names -join ', ')." } else { ' The share is reachable but empty.' }
            & $add 'ContentPath' $false 'Error' ("The share is reachable but there is no folder named " +
                "'$($Plan.PackageName)' in it. Copy the package FOLDER - not its contents - to $shareRoot.$near " +
                "Browsing the package from C:\temp only fills in the window; SCCM fetches the content from the share.")
        }
    }

    # 1a. ...and it must be a UNC path. SCCM stores the content location for
    #     distribution points to fetch, so a local path is meaningless to it and
    #     is refused outright:
    #
    #       "Directory path 'C:\temp\...' does not appear to be a valid UNC path.
    #        Must be in the format of \\myserver\share"
    #
    #     That refusal comes from Add-CMScriptDeploymentType, which runs AFTER
    #     the application has been created - so without this check the run gets
    #     as far as creating an application and then rolls it straight back out.
    #     Cheaper to say so here, before anything exists.
    #     A preview creates nothing and never reaches that cmdlet, so there it is
    #     reported as a warning: the plan is still worth reviewing.
    $isUnc = ([string]$Plan.ContentPath).StartsWith('\\')
    & $add 'ContentPathIsUnc' $isUnc $(if ($DryRun) { 'Warning' } else { 'Error' }) `
        $(if ($isUnc) { 'The content share is a UNC path, as SCCM requires.' }
          else { "The content share is '$($Plan.ContentPath)', a local path. SCCM only accepts a UNC path here, because distribution points fetch the content over the network - a local path means nothing to them. Set Content/@share in Config\Environments\$($Plan.Environment).xml to a share such as \\server\share." })

    # 1b. the package name's own site prefix must match the environment it is
    #     being published into. INA_ADOBE_... published into ICZ would create
    #     INA-named objects on the ICZ site, which nobody would spot until much
    #     later. The old tool "solved" this by rewriting the first three
    #     characters, which is what corrupted ADO_ADOBE_ into INA_INABE_.
    $site = $Plan.Parts.Site
    $siteOk = ($site -eq $Plan.Environment)
    & $add 'SitePrefix' $siteOk 'Error' $(if ($siteOk) { "The package name is prefixed '$site', matching $($Plan.Environment)." }
        else { "The package name starts with '$site' but it is being published into $($Plan.Environment). Rename the package for the target environment, or select $site instead." })

    # 2. the application must not already exist
    $appExists = & $Provider.TestApplication @{ ApplicationName = $Plan.ApplicationName }
    & $add 'Application' (-not $appExists) 'Error' $(if ($appExists) { "An application named '$($Plan.ApplicationName)' already exists in $($Plan.Environment)." }
        else { 'No application of that name exists yet.' })

    # 3. every limiting collection referenced by the environment file must exist
    foreach ($id in (@($Plan.Collections | ForEach-Object { $_.LimitingCollectionId }) | Sort-Object -Unique)) {
        $ok = & $Provider.TestCollectionId @{ Id = $id }
        & $add "LimitingCollection:$id" $ok 'Error' $(if ($ok) { "Limiting collection $id found." }
            else { "Limiting collection $id does not exist in $($Plan.Environment). Correct it in Config\Environments\$($Plan.Environment).xml." })
    }

    # 4. no collection name may already be taken
    foreach ($collection in $Plan.Collections) {
        $taken = & $Provider.TestCollectionName @{ Name = $collection.Name }
        if ($taken) { & $add "Collection:$($collection.Name)" $false 'Error' "A collection named '$($collection.Name)' already exists." }
    }

    # 5. the distribution point group must exist...
    $hasDp = & $Provider.TestDpGroup @{ Name = $Plan.DistributionPointGroup }
    & $add 'DistributionPointGroup' $hasDp 'Error' $(if ($hasDp) { "Distribution point group '$($Plan.DistributionPointGroup)' found." }
        else { "Distribution point group '$($Plan.DistributionPointGroup)' does not exist in $($Plan.Environment)." })

    # 5a. ...and it must have distribution points in it. An empty group exists,
    #     so the check above passes, and then content distribution fails with
    #     nowhere to send the content - by which point the application and its
    #     deployment type have been created and have to be rolled back.
    #     A warning, not an error: the count is read from a property that is not
    #     on every console build, and being unable to count is not proof of an
    #     empty group.
    if ($hasDp) {
        $members = [int](& $Provider.GetDpGroupMemberCount @{ Name = $Plan.DistributionPointGroup })
        if ($members -eq 0) {
            & $add 'DistributionPointGroupMembers' $false 'Warning' `
                ("Distribution point group '$($Plan.DistributionPointGroup)' has no distribution points in it. " +
                 "Distributing content to an empty group fails, and it fails after the application has been created. " +
                 "Add a distribution point to the group, or point Content/@distributionPointGroup in " +
                 "Config\Environments\$($Plan.Environment).xml at a group that has one.")
        }
        elseif ($members -gt 0) {
            & $add 'DistributionPointGroupMembers' $true 'Warning' "$members distribution point(s) in the group."
        }
    }

    # 6. every security scope must exist
    foreach ($scope in $Plan.SecurityScopes) {
        $ok = & $Provider.TestSecurityScope @{ Id = $scope }
        & $add "SecurityScope:$scope" $ok 'Error' $(if ($ok) { "Security scope $scope found." }
            else { "Security scope $scope does not exist in $($Plan.Environment)." })
    }

    # 7. an unconfirmed environment is a warning here; the orchestrator blocks it
    if (-not $Plan.Verified) {
        & $add 'EnvironmentVerified' $false 'Warning' "Environment $($Plan.Environment) is marked unverified - its settings still need confirming by Audi."
    }

    $all      = $findings.ToArray()
    $blocking = @($all | Where-Object { -not $_.Ok -and $_.Severity -eq 'Error' })
    return [pscustomobject]@{ Ok = ($blocking.Count -eq 0); Findings = $all; Blocking = $blocking }
}

function Wait-AudiContentDistribution {
    <#  Waits until the content has actually reached the distribution points.

        The old tool slept a flat 30 seconds per deployment and carried on
        regardless - on PCZ that was about five minutes of a frozen window, and
        no knowledge of whether the content had arrived. This polls for a real
        answer and gives up with a clear message at the configured timeout.  #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Plan, [Parameter(Mandatory = $true)]$Provider,
          $LogContext, [string]$Root, [switch]$DryRun)

    $runtime  = (Get-AudiDefaults -Root $Root).Runtime
    $deadline = (Get-Date).AddMinutes($runtime.DistributionTimeoutMinutes)

    while ($true) {
        $state = & $Provider.GetDistributionState @{ ApplicationName = $Plan.ApplicationName }
        $done  = [int]$state.Success + [int]$state.Failed

        # The status could not be read at all - a console that does not expose it,
        # or no rights to the status class. Distribution has still been started
        # and SCCM will carry on with it, so say that plainly and move on rather
        # than sitting in this loop for the whole timeout waiting for a number
        # that is never coming.
        if ($state.ContainsKey('Readable') -and -not $state.Readable) {
            return @{ Ok = $true; State = $state
                Message = 'Content distribution started. Its progress could not be read from this console, so it was not waited on - check the Content Status node in the console.' }
        }

        if ([int]$state.Failed -gt 0) {
            return @{ Ok = $false; State = $state
                Message = "Content distribution reported $($state.Failed) failure(s) across $($state.Total) distribution point(s)." }
        }
        if ([int]$state.Total -gt 0 -and $done -ge [int]$state.Total) {
            return @{ Ok = $true; State = $state; Message = "Content reached all $($state.Total) distribution point(s)." }
        }
        if ($DryRun) { return @{ Ok = $true; State = $state; Message = 'Dry run - distribution not waited on.' } }
        if ((Get-Date) -ge $deadline) {
            return @{ Ok = $false; State = $state
                Message = "Content had not finished distributing after $($runtime.DistributionTimeoutMinutes) minutes ($($state.Success) of $($state.Total) done). The application exists; distribution is still in progress." }
        }
        if ($LogContext) {
            Write-AudiLog -Context $LogContext -Step 'Content' -Message "Waiting for distribution: $($state.Success) of $($state.Total) done."
        }
        Start-Sleep -Seconds $runtime.DistributionPollSeconds
    }
}

