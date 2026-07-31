# ==============================================================================
#  Audi SCCM Integration Tool - SCCM engine
# ==============================================================================
#  Increment 2: the twelve operations, ordered, checked and reversible.
#
#  How this differs from the tool being replaced:
#
#    * Every step returns a result and the orchestrator READS it. The old tool
#      discarded the result object and set the label to "Done." unconditionally,
#      so a failed step looked identical to a successful one.
#    * Order is enforced, not remembered. Steps declare what they depend on and
#      the orchestrator refuses to run one whose prerequisite has not succeeded.
#    * A failed run rolls back what it created, newest first.
#    * The SCCM calls sit behind a provider, so the same engine can run for real,
#      or as a dry run that touches nothing. The dry run is what the packager
#      sees as a preview, and it is also what the tests drive.
#
#  ASCII only. No environment-specific value appears here - it all comes from
#  the plan produced by Get-AudiIntegrationPlan.
# ==============================================================================

Set-StrictMode -Version 2.0

# ------------------------------------------------------------------ providers

function New-AudiSccmProvider {
    <#  The real provider. Each entry is the smallest possible wrapper around a
        supported ConfigMgr command, so the engine holds no raw WMI.

        NOT YET EXERCISED AGAINST A LIVE SITE - that is the ICZ run. The shapes
        below are what the orchestrator expects; the bodies get validated there. #>
    [CmdletBinding()]
    param()

    return @{
        Name = 'live'

        TestApplication = { param($c) [bool](Get-CMApplication -Name $c.ApplicationName -Fast -ErrorAction SilentlyContinue) }

        NewApplication = { param($c)
            New-CMApplication -Name $c.ApplicationName -Publisher $c.Publisher -SoftwareVersion $c.Version `
                              -LocalizedApplicationName $c.LocalizedName -LocalizedApplicationDescription $c.LocalizedDescription `
                              -AutoInstall $true -ErrorAction Stop | Out-Null
        }

        AddDeploymentType = { param($c)
            Add-CMScriptDeploymentType -ApplicationName $c.ApplicationName -DeploymentTypeName $c.DeploymentTypeName `
                                       -ContentLocation $c.ContentPath -InstallCommand $c.InstallCommand `
                                       -UninstallCommand $c.UninstallCommand -AddDetectionClause $c.DetectionClause `
                                       -InstallationBehaviorType $c.InstallationBehaviorType `
                                       -LogonRequirementType $c.LogonRequirementType `
                                       -MaximumRuntimeMins $c.MaxRuntimeMinutes -EstimatedRuntimeMins $c.EstimatedInstallMinutes `
                                       -ErrorAction Stop | Out-Null
        }

        SetCategory = { param($c) Set-CMApplication -Name $c.ApplicationName -AddAppCategory $c.Category -ErrorAction Stop | Out-Null }

        StartContentDistribution = { param($c)
            Start-CMContentDistribution -ApplicationName $c.ApplicationName -DistributionPointGroupName $c.DistributionPointGroup -ErrorAction Stop | Out-Null
        }

        NewCollection = { param($c)
            New-CMDeviceCollection -Name $c.Name -LimitingCollectionId $c.LimitingCollectionId -Comment $c.Comment -ErrorAction Stop | Out-Null
        }

        NewDeployment = { param($c)
            New-CMApplicationDeployment -Name $c.ApplicationName -CollectionName $c.CollectionName `
                                        -DeployAction $c.DeploymentAction -DeployPurpose Available -ErrorAction Stop | Out-Null
        }

        # the environment files hold scope IDs (INA00003), so bind by -Id
        AddSecurityScope = { param($c)
            $app = Get-CMApplication -Name $c.ApplicationName -Fast -ErrorAction Stop
            foreach ($scope in $c.SecurityScopes) { Add-CMObjectSecurityScope -InputObject $app -Id $scope -ErrorAction Stop | Out-Null }
        }

        # ---- preflight probes: read-only, used before anything is created
        TestContentPath    = { param($c) Test-Path -LiteralPath $c.Path }
        TestCollectionId   = { param($c) [bool](Get-CMCollection -Id $c.Id -ErrorAction SilentlyContinue) }
        TestDpGroup        = { param($c) [bool](Get-CMDistributionPointGroup -Name $c.Name -ErrorAction SilentlyContinue) }
        TestSecurityScope  = { param($c) [bool](Get-CMSecurityScope -Id $c.Id -ErrorAction SilentlyContinue) }
        TestCollectionName = { param($c) [bool](Get-CMCollection -Name $c.Name -ErrorAction SilentlyContinue) }

        # ---- distribution state, so the tool can wait for a real result
        GetDistributionState = { param($c)
            $status = Get-CMDistributionStatus -Name $c.ApplicationName -ErrorAction SilentlyContinue
            if (-not $status) { return @{ Total = 0; Success = 0; Failed = 0; InProgress = 0 } }
            return @{ Total = [int]$status.Targeted; Success = [int]$status.NumberSuccess
                      Failed = [int]$status.NumberErrors; InProgress = [int]$status.NumberInProgress }
        }

        MoveObject = { param($c) Move-CMObject -FolderPath $c.FolderPath -InputObject $c.InputObject -ErrorAction Stop | Out-Null }

        GetApplicationObject = { param($c) Get-CMApplication -Name $c.ApplicationName -Fast -ErrorAction Stop }
        GetCollectionObject  = { param($c) Get-CMDeviceCollection -Name $c.Name -ErrorAction Stop }

        RemoveDeployment = { param($c) Remove-CMApplicationDeployment -Name $c.ApplicationName -CollectionName $c.CollectionName -Force -ErrorAction Stop | Out-Null }
        RemoveCollection = { param($c) Remove-CMDeviceCollection -Name $c.Name -Force -ErrorAction Stop | Out-Null }
        RemoveApplication= { param($c) Remove-CMApplication -Name $c.ApplicationName -Force -ErrorAction Stop | Out-Null }

        # ---- Active Directory group, via the ARS SPML web service
        #
        # Same SPML contract the old Audi-ARSSPML-* modules used, but with one
        # difference: no credential is passed. Running inside the endpoint the
        # session already IS the service account, so the proxy uses the current
        # identity. The old tool passed a credential variable that was always
        # $null, which made PowerShell prompt on a hidden console and appear to
        # hang - and on PCZ the provider URL was never set at all.
        NewArsGroup = { param($c)
            if ([string]::IsNullOrWhiteSpace($c.ProviderUrl)) {
                throw "No ARS provider address is configured for this environment. Set ActiveDirectory/@arsProviderUrl in the environment file."
            }
            $proxy = New-WebServiceProxy -Uri $c.ProviderUrl -UseDefaultCredential -ErrorAction Stop
            $ns    = $proxy.GetType().Namespace
            $dn    = "CN=$($c.GroupName),$($c.Ou)"

            $add = New-Object -TypeName "$ns.CAddRequest"
            $container = New-Object -TypeName "$ns.CPSOID"; $container.ID = ''
            $add.containerID = $container
            $add.returnData  = 'everything'
            $add.targetID    = ''
            $psoId = New-Object -TypeName "$ns.CPSOID"; $psoId.ID = $dn
            $add.psoID = $psoId

            $attributes = @()
            $objectClass = New-Object -TypeName "$ns.attr"
            $objectClass.name = 'objectClass'; $objectClass.value = @('group')
            $attributes += $objectClass
            foreach ($key in $c.Attributes.Keys) {
                $a = New-Object -TypeName "$ns.attr"
                $a.name = $key; $a.value = @([string]$c.Attributes[$key])
                $attributes += $a
            }
            $add.data = $attributes

            $result = $proxy.add($add)
            if ($result.status -ne 'success') {
                throw "The AD group '$dn' could not be created. $($result.error) $($result.errorMessage)"
            }
        }

        RemoveArsGroup = { param($c)
            if ([string]::IsNullOrWhiteSpace($c.ProviderUrl)) {
                throw "No ARS provider address is configured for this environment. Set ActiveDirectory/@arsProviderUrl in the environment file."
            }
            $proxy = New-WebServiceProxy -Uri $c.ProviderUrl -UseDefaultCredential -ErrorAction Stop
            $ns    = $proxy.GetType().Namespace
            $dn    = "CN=$($c.GroupName),$($c.Ou)"

            $delete = New-Object -TypeName "$ns.CDeleteRequest"
            $psoId  = New-Object -TypeName "$ns.CPSOID"; $psoId.ID = $dn
            $delete.psoID = $psoId

            $result = $proxy.delete($delete)
            if ($result.status -ne 'success') {
                throw "The AD group '$dn' could not be removed. $($result.error) $($result.errorMessage)"
            }
        }
    }
}

function New-AudiSccmDryRunProvider {
    <#  Touches nothing. Records what would have happened, in order.
        Drives the packager's preview and the tests.
        -FailOn <operation> makes one operation fail, to exercise rollback.  #>
    [CmdletBinding()]
    param(
        [string]$FailOn,
        [string[]]$ExistingApplications = @(),
        [string[]]$ExistingCollections  = @(),
        # e.g. 'ContentPath', 'Collection:INA010CA', 'DpGroup:INA-DP-Group all', 'Scope:INA00003'
        [string[]]$Missing = @()
    )

    $log = New-Object System.Collections.Generic.List[object]
    $provider = @{ Name = 'dryrun'; Log = $log; FailOn = $FailOn }

    $record = {
        param($operation, $detail)
        if ($provider.FailOn -eq $operation) { throw "Simulated failure in $operation" }
        $provider.Log.Add([pscustomobject]@{ Operation = $operation; Detail = $detail })
    }.GetNewClosure()

    $provider.TestApplication          = { param($c) $ExistingApplications -contains $c.ApplicationName }.GetNewClosure()
    $provider.NewApplication           = { param($c) & $record 'NewApplication'           $c.ApplicationName }.GetNewClosure()
    $provider.AddDeploymentType        = { param($c) & $record 'AddDeploymentType'        $c.DeploymentTypeName }.GetNewClosure()
    $provider.SetCategory              = { param($c) & $record 'SetCategory'              $c.Category }.GetNewClosure()
    $provider.StartContentDistribution = { param($c) & $record 'StartContentDistribution' $c.DistributionPointGroup }.GetNewClosure()
    $provider.NewCollection            = { param($c) & $record 'NewCollection'            $c.Name }.GetNewClosure()
    $provider.NewDeployment            = { param($c) & $record 'NewDeployment'            ("{0} -> {1} ({2})" -f $c.ApplicationName, $c.CollectionName, $c.DeploymentAction) }.GetNewClosure()
    $provider.AddSecurityScope         = { param($c) & $record 'AddSecurityScope'         ($c.SecurityScopes -join ',') }.GetNewClosure()
    $provider.MoveObject               = { param($c) & $record 'MoveObject'               ("{0} -> {1}" -f $c.Label, $c.FolderPath) }.GetNewClosure()
    $provider.GetApplicationObject     = { param($c) [pscustomobject]@{ Kind = 'Application'; Name = $c.ApplicationName } }.GetNewClosure()
    $provider.GetCollectionObject      = { param($c) [pscustomobject]@{ Kind = 'Collection';  Name = $c.Name } }.GetNewClosure()
    $provider.RemoveDeployment         = { param($c) & $record 'RemoveDeployment'         ("{0} -> {1}" -f $c.ApplicationName, $c.CollectionName) }.GetNewClosure()
    $provider.RemoveCollection         = { param($c) & $record 'RemoveCollection'         $c.Name }.GetNewClosure()
    $provider.RemoveApplication        = { param($c) & $record 'RemoveApplication'        $c.ApplicationName }.GetNewClosure()
    $provider.NewArsGroup              = { param($c) & $record 'NewArsGroup'              $c.GroupName }.GetNewClosure()
    $provider.RemoveArsGroup           = { param($c) & $record 'RemoveArsGroup'           $c.GroupName }.GetNewClosure()

    # preflight probes: everything present unless the caller says otherwise
    $provider.TestContentPath    = { param($c) -not ($Missing -contains 'ContentPath') }.GetNewClosure()
    $provider.TestCollectionId   = { param($c) -not ($Missing -contains "Collection:$($c.Id)") }.GetNewClosure()
    $provider.TestDpGroup        = { param($c) -not ($Missing -contains "DpGroup:$($c.Name)") }.GetNewClosure()
    $provider.TestSecurityScope  = { param($c) -not ($Missing -contains "Scope:$($c.Id)") }.GetNewClosure()
    $provider.TestCollectionName = { param($c) $ExistingCollections -contains $c.Name }.GetNewClosure()
    $provider.GetDistributionState = { param($c) @{ Total = 2; Success = 2; Failed = 0; InProgress = 0 } }.GetNewClosure()

    return $provider
}

# ----------------------------------------------------------------- connection

function Connect-AudiSccm {
    <#  Maps the CMSite drive for the plan's environment.

        The awkward parts are carried over from the Package Builder connection
        layer, where they were learned the hard way:
          * prefer the installed console's module, or two sets of assemblies fight
          * the CMSite provider emits a console/site version warning that
            -ErrorAction Stop wrongly promotes to a terminating error, so the
            drive is created quietly and then checked for existence
          * error text is triaged into something an operator can act on  #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Plan, [switch]$DryRun)

    if ($DryRun) { return @{ Ok = $true; Message = 'Dry run - no site connection made.'; Drive = $null } }

    if (-not (Get-Module -Name ConfigurationManager)) {
        $module = $null
        if ($env:SMS_ADMIN_UI_PATH) {
            $candidate = Join-Path (Split-Path -Parent $env:SMS_ADMIN_UI_PATH) 'ConfigurationManager.psd1'
            if (Test-Path -LiteralPath $candidate) { $module = $candidate }
        }
        if (-not $module) { return @{ Ok = $false; Message = 'The ConfigMgr console is not installed on this machine, so its PowerShell module cannot be loaded.'; Drive = $null } }
        try { Import-Module $module -ErrorAction Stop }
        catch { return @{ Ok = $false; Message = "The ConfigMgr module could not be loaded: $($_.Exception.Message)"; Drive = $null } }
    }

    $drive = $Plan.Environment
    if (-not (Get-PSDrive -Name $drive -PSProvider CMSite -ErrorAction SilentlyContinue)) {
        $null = New-PSDrive -Name $drive -PSProvider CMSite -Root $Plan.SiteServer -Scope Global `
                            -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -ErrorVariable driveError
        if (-not (Get-PSDrive -Name $drive -PSProvider CMSite -ErrorAction SilentlyContinue)) {
            $detail = if ($driveError) { [string]$driveError[0] } else { 'no further detail' }
            $hint = switch -Regex ($detail) {
                'database lookup|no such host|RPC server' { "The site server could not be reached. Check name resolution, the network path, and the account's rights on the site." }
                default { '' }
            }
            return @{ Ok = $false; Message = ("Could not connect to site {0} on {1}. {2} {3}" -f $Plan.Environment, $Plan.SiteServer, $detail, $hint).Trim(); Drive = $null }
        }
    }
    return @{ Ok = $true; Message = "Connected to $drive on $($Plan.SiteServer)."; Drive = $drive }
}

# ---------------------------------------------------------------------- steps

function Get-AudiIntegrationStep {
    <#  The eight integration steps, each declaring what it needs. The old tool
        had eight buttons and trusted the operator to click them in order.  #>
    return @(
        [pscustomobject]@{ Key = 'Application';   Name = 'Create the application';       DependsOn = @() }
        [pscustomobject]@{ Key = 'Category';      Name = 'Set the application category'; DependsOn = @('Application') }
        [pscustomobject]@{ Key = 'Content';       Name = 'Distribute the content';       DependsOn = @('Application') }
        [pscustomobject]@{ Key = 'Collections';   Name = 'Create the collections';       DependsOn = @() }
        [pscustomobject]@{ Key = 'Deployments';   Name = 'Create the deployments';       DependsOn = @('Application', 'Collections') }
        [pscustomobject]@{ Key = 'SecurityScope'; Name = 'Add the security scope';       DependsOn = @('Application') }
        [pscustomobject]@{ Key = 'MoveObjects';   Name = 'File objects into folders';    DependsOn = @('Application', 'Collections') }
        [pscustomobject]@{ Key = 'ArsGroup';      Name = 'Create the AD access group';   DependsOn = @() }
    )
}

function Get-AudiRemovalStep {
    return @(
        [pscustomobject]@{ Key = 'Deployments'; Name = 'Remove the deployments';     DependsOn = @() }
        [pscustomobject]@{ Key = 'Collections'; Name = 'Remove the collections';     DependsOn = @('Deployments') }
        [pscustomobject]@{ Key = 'Application'; Name = 'Remove the application';     DependsOn = @('Deployments') }
        [pscustomobject]@{ Key = 'ArsGroup';    Name = 'Remove the AD access group'; DependsOn = @() }
    )
}

function Invoke-AudiStepBody {
    <#  Runs one step and records what it created, so a later failure can undo it. #>
    [CmdletBinding()]
    param($Key, $Plan, $Provider, $Created)

    switch ($Key) {

        'Application' {
            if (& $Provider.TestApplication @{ ApplicationName = $Plan.ApplicationName }) {
                throw "An application named '$($Plan.ApplicationName)' already exists in $($Plan.Environment)."
            }
            & $Provider.NewApplication @{
                ApplicationName = $Plan.ApplicationName; Publisher = $Plan.Parts.Publisher; Version = $Plan.Parts.Version
                LocalizedName = $Plan.LocalizedName; LocalizedDescription = $Plan.LocalizedDescription }
            $Created.Add([pscustomobject]@{ Kind = 'Application'; Name = $Plan.ApplicationName }) | Out-Null

            & $Provider.AddDeploymentType @{
                ApplicationName = $Plan.ApplicationName; DeploymentTypeName = $Plan.DeploymentType
                ContentPath = $Plan.ContentPath; InstallCommand = $Plan.InstallCommand; UninstallCommand = $Plan.UninstallCommand
                DetectionClause = $Plan.DetectionKey; InstallationBehaviorType = $Plan.InstallationBehaviorType
                LogonRequirementType = $Plan.LogonRequirementType; MaxRuntimeMinutes = $Plan.MaxRuntimeMinutes
                EstimatedInstallMinutes = $Plan.EstimatedInstallMinutes }
            return "Application and deployment type '$($Plan.DeploymentType)' created."
        }

        'Category' {
            & $Provider.SetCategory @{ ApplicationName = $Plan.ApplicationName; Category = $Plan.Category }
            return "Category '$($Plan.Category)' set."
        }

        'Content' {
            & $Provider.StartContentDistribution @{ ApplicationName = $Plan.ApplicationName; DistributionPointGroup = $Plan.DistributionPointGroup }
            return "Content distribution started to '$($Plan.DistributionPointGroup)'."
        }

        'Collections' {
            foreach ($collection in $Plan.Collections) {
                & $Provider.NewCollection @{ Name = $collection.Name; LimitingCollectionId = $collection.LimitingCollectionId; Comment = $collection.Comment }
                $Created.Add([pscustomobject]@{ Kind = 'Collection'; Name = $collection.Name }) | Out-Null
            }
            return "$(@($Plan.Collections).Count) collections created."
        }

        'Deployments' {
            foreach ($collection in $Plan.Collections) {
                & $Provider.NewDeployment @{ ApplicationName = $Plan.ApplicationName; CollectionName = $collection.Name; DeploymentAction = $collection.DeploymentAction }
                $Created.Add([pscustomobject]@{ Kind = 'Deployment'; Name = $collection.Name }) | Out-Null
            }
            return "$(@($Plan.Collections).Count) deployments created."
        }

        'SecurityScope' {
            & $Provider.AddSecurityScope @{ ApplicationName = $Plan.ApplicationName; SecurityScopes = $Plan.SecurityScopes }
            return "$(@($Plan.SecurityScopes).Count) security scopes attached."
        }

        'MoveObjects' {
            $app = & $Provider.GetApplicationObject @{ ApplicationName = $Plan.ApplicationName }
            & $Provider.MoveObject @{ FolderPath = $Plan.ApplicationFolder; InputObject = $app; Label = $Plan.ApplicationName }
            foreach ($collection in $Plan.Collections) {
                $obj = & $Provider.GetCollectionObject @{ Name = $collection.Name }
                & $Provider.MoveObject @{ FolderPath = $collection.Folder; InputObject = $obj; Label = $collection.Name }
            }
            return "Application and $(@($Plan.Collections).Count) collections filed."
        }

        'ArsGroup' {
            # description and order number are the two attributes the old tool set;
            # it left the order number as the literal 123456789 on every package,
            # because there was no field for it. Here it comes from the request.
            $attributes = @{ 'description' = $Plan.ArsDescription }
            if ($Plan.Rfc) { $attributes['edsva-Auftragsnummer'] = $Plan.Rfc }

            & $Provider.NewArsGroup @{ GroupName = $Plan.ArsGroupName; Ou = $Plan.ArsGroupOu
                                       ProviderUrl = $Plan.ArsProviderUrl; Attributes = $attributes }
            $Created.Add([pscustomobject]@{ Kind = 'ArsGroup'; Name = $Plan.ArsGroupName }) | Out-Null
            return "AD group '$($Plan.ArsGroupName)' created."
        }

        default { throw "Unknown integration step '$Key'." }
    }
}

function Invoke-AudiRemovalStepBody {
    [CmdletBinding()]
    param($Key, $Plan, $Provider)

    switch ($Key) {
        'Deployments' {
            foreach ($collection in $Plan.Collections) {
                & $Provider.RemoveDeployment @{ ApplicationName = $Plan.ApplicationName; CollectionName = $collection.Name }
            }
            return "$(@($Plan.Collections).Count) deployments removed."
        }
        'Collections' {
            foreach ($collection in $Plan.Collections) { & $Provider.RemoveCollection @{ Name = $collection.Name } }
            return "$(@($Plan.Collections).Count) collections removed."
        }
        'Application' {
            & $Provider.RemoveApplication @{ ApplicationName = $Plan.ApplicationName }
            return "Application '$($Plan.ApplicationName)' removed."
        }
        'ArsGroup' {
            & $Provider.RemoveArsGroup @{ GroupName = $Plan.ArsGroupName; Ou = $Plan.ArsGroupOu; ProviderUrl = $Plan.ArsProviderUrl }
            return "AD group '$($Plan.ArsGroupName)' removed."
        }
        default { throw "Unknown removal step '$Key'." }
    }
}

function Undo-AudiCreatedObject {
    <#  Rolls back what a failed run created, newest first.  #>
    [CmdletBinding()]
    param($Plan, $Provider, $Created)

    $undone = New-Object System.Collections.Generic.List[string]
    for ($i = $Created.Count - 1; $i -ge 0; $i--) {
        $item = $Created[$i]
        try {
            switch ($item.Kind) {
                'Deployment'  { & $Provider.RemoveDeployment  @{ ApplicationName = $Plan.ApplicationName; CollectionName = $item.Name } }
                'Collection'  { & $Provider.RemoveCollection  @{ Name = $item.Name } }
                'Application' { & $Provider.RemoveApplication @{ ApplicationName = $item.Name } }
                'ArsGroup'    { & $Provider.RemoveArsGroup    @{ GroupName = $item.Name; Ou = $Plan.ArsGroupOu; ProviderUrl = $Plan.ArsProviderUrl } }
            }
            $undone.Add("$($item.Kind) $($item.Name)")
        }
        catch { $undone.Add("$($item.Kind) $($item.Name) COULD NOT BE REMOVED: $($_.Exception.Message)") }
    }
    # .ToArray(), not @() - wrapping a generic List in PowerShell 5.1 throws
    # "Argument types do not match"
    return $undone.ToArray()
}

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
    param([Parameter(Mandatory = $true)]$Plan, [Parameter(Mandatory = $true)]$Provider, [string]$Root)

    $findings = New-Object System.Collections.Generic.List[object]
    $add = { param($check, $ok, $severity, $message)
        $findings.Add([pscustomobject]@{ Check = $check; Ok = $ok; Severity = $severity; Message = $message }) | Out-Null
    }

    # 1. the package source must be on the content share
    $hasContent = & $Provider.TestContentPath @{ Path = $Plan.ContentPath }
    & $add 'ContentPath' $hasContent 'Error' $(if ($hasContent) { "Source found: $($Plan.ContentPath)" }
        else { "The package source was not found at $($Plan.ContentPath). Copy the package to the content share first." })

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

    # 5. the distribution point group must exist
    $hasDp = & $Provider.TestDpGroup @{ Name = $Plan.DistributionPointGroup }
    & $add 'DistributionPointGroup' $hasDp 'Error' $(if ($hasDp) { "Distribution point group '$($Plan.DistributionPointGroup)' found." }
        else { "Distribution point group '$($Plan.DistributionPointGroup)' does not exist in $($Plan.Environment)." })

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
            Requester = $Plan.Requester; Executor = $Plan.Executor; DryRun = [bool]$DryRun
            Message = $message; Steps = $results.ToArray(); RolledBack = $rollback
            Preflight = $preflight; LogPath = $log.LogPath; Provider = $Provider
        }
        Write-AudiLog -Context $log -Level $(if ($ok) { 'Info' } else { 'Error' }) -Message $message
        $null = Save-AudiJobRecord -Context $log -Plan $Plan -Result $result
        return $result
    }

    Write-AudiLog -Context $log -Message ("Job {0} | package {1} | environment {2} | requested by {3} | executed as {4}{5}" -f `
        $Plan.JobId, $Plan.PackageName, $Plan.Environment, $Plan.Requester, $Plan.Executor, $(if ($DryRun) { ' | DRY RUN' } else { '' }))

    # An environment whose values were inherited from another one must not be
    # used by accident. This is what stops PCZ running on INA's settings.
    if (-not $Plan.Verified -and -not $AllowUnverifiedEnvironment -and -not $DryRun) {
        return & $finish $false "Environment $($Plan.Environment) is marked unverified - its settings still need confirming by Audi. Re-run with -AllowUnverifiedEnvironment only if that is intended." $null
    }

    # One package, one environment, one job at a time.
    if (-not $DryRun) {
        $lock = Enter-AudiPackageLock -Plan $Plan -Root $Root
        if (-not $lock.Ok) { $lock = $null; return & $finish $false $lock.Message $null }
    }

    $connection = Connect-AudiSccm -Plan $Plan -DryRun:$DryRun
    if (-not $connection.Ok) { return & $finish $false $connection.Message $null }
    Write-AudiLog -Context $log -Message $connection.Message

    # Fail before creating anything, rather than halfway through and rolling back.
    $preflight = $null
    if (-not $SkipPreflight) {
        Write-AudiLog -Context $log -Step 'Preflight' -Message 'Checking prerequisites.'
        $preflight = Test-AudiSwPrerequisite -Plan $Plan -Provider $Provider -Root $Root
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

        if ($OnProgress) { & $OnProgress $step.Name }
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
            $results.Add([pscustomobject]@{ Step = $step.Key; Name = $step.Name; Ok = $false; Message = $_.Exception.Message }) | Out-Null
            Write-AudiLog -Context $log -Step $step.Key -Level 'Error' -Message $_.Exception.Message
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
    $summary = if ($failed) { "Integration failed after $okCount of $(@(Get-AudiIntegrationStep).Count) steps." }
               else { "Integration completed - $okCount steps." }
    return & $finish (-not $failed) $summary $preflight
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

    foreach ($step in (Get-AudiRemovalStep)) {
        $missing = @($step.DependsOn | Where-Object { -not $succeeded.Contains($_) })
        if ($missing.Count -gt 0) {
            $results.Add([pscustomobject]@{ Step = $step.Key; Name = $step.Name; Ok = $false
                Message = "Skipped - depends on $($missing -join ', '), which did not succeed." }) | Out-Null
            $failed = $true
            continue
        }
        if ($OnProgress) { & $OnProgress $step.Name }
        try {
            $message = Invoke-AudiRemovalStepBody -Key $step.Key -Plan $Plan -Provider $Provider
            $null = $succeeded.Add($step.Key)
            $results.Add([pscustomobject]@{ Step = $step.Key; Name = $step.Name; Ok = $true; Message = $message }) | Out-Null
        }
        catch {
            $results.Add([pscustomobject]@{ Step = $step.Key; Name = $step.Name; Ok = $false; Message = $_.Exception.Message }) | Out-Null
            $failed = $true
            # removal does not stop: independent steps are still attempted
        }
    }

    $okCount = @($results | Where-Object { $_.Ok }).Count
    return [pscustomobject]@{
        Ok = (-not $failed); JobId = $Plan.JobId; Environment = $Plan.Environment; Package = $Plan.PackageName
        Requester = $Plan.Requester; Executor = $Plan.Executor; DryRun = [bool]$DryRun
        Message = $(if ($failed) { "Removal finished with failures - $okCount of $(@(Get-AudiRemovalStep).Count) steps succeeded." } else { "Removal completed - $okCount steps." })
        Steps = $results.ToArray(); Provider = $Provider
    }
}
