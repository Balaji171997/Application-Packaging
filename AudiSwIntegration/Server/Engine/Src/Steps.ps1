# ==============================================================================
#  Audi SCCM Integration Tool - what each step does
# ==============================================================================
#  The steps, in three lists - integrate, modify, remove - and the body of each.
#
#  A step declares what it DEPENDS ON, and the orchestrator refuses to run one
#  whose prerequisite has not succeeded. The tool being replaced had eight
#  buttons and trusted the operator to press them in the right order.
#
#  Undo-AudiCreatedObject is here too: what a failed run takes back out, newest
#  first.
#
#  Dot-sourced by AudiSwIntegration.ps1. ASCII only.
# ==============================================================================

Set-StrictMode -Version 2.0

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

function Get-AudiModifyStep {
    <#  Modify brings an application that already exists back into line with the
        environment file and the package as it now is.

        It is a RECONCILE, not a rebuild: the application object is never
        replaced, so its deployments keep working and the machines already in
        its collections are undisturbed. Anything missing is added, anything the
        environment file no longer asks for is removed, and what has changed -
        a new revision, a new content path, a new description - is updated.  #>
    return @(
        [pscustomobject]@{ Key = 'Application';   Name = 'Update the application';         DependsOn = @() }
        [pscustomobject]@{ Key = 'DeploymentType';Name = 'Update the deployment type';     DependsOn = @('Application') }
        [pscustomobject]@{ Key = 'Category';      Name = 'Set the application category';   DependsOn = @('Application') }
        [pscustomobject]@{ Key = 'Content';       Name = 'Re-distribute the content';      DependsOn = @('DeploymentType') }
        [pscustomobject]@{ Key = 'Collections';   Name = 'Add missing collections';        DependsOn = @() }
        [pscustomobject]@{ Key = 'Deployments';   Name = 'Add missing deployments';        DependsOn = @('Application', 'Collections') }
        [pscustomobject]@{ Key = 'Retire';        Name = 'Remove what is no longer wanted';DependsOn = @('Collections') }
        [pscustomobject]@{ Key = 'SecurityScope'; Name = 'Add the security scope';         DependsOn = @('Application') }
        [pscustomobject]@{ Key = 'MoveObjects';   Name = 'File objects into folders';      DependsOn = @('Application', 'Collections') }
    )
}

function Invoke-AudiModifyStepBody {
    [CmdletBinding()]
    param($Key, $Plan, $Provider, $Changed)

    switch ($Key) {
        'Application' {
            if (-not (& $Provider.TestApplication @{ ApplicationName = $Plan.ApplicationName })) {
                throw "No application named '$($Plan.ApplicationName)' exists in $($Plan.Environment). Use Integrate to create it."
            }
            & $Provider.SetApplication @{
                ApplicationName = $Plan.ApplicationName; Publisher = $Plan.Parts.Publisher; Version = $Plan.Parts.Version
                LocalizedName = $Plan.LocalizedName; LocalizedDescription = $Plan.LocalizedDescription
                LocalizedNameDe = $Plan.LocalizedNameDe; LocalizedDescriptionDe = $Plan.LocalizedDescriptionDe; Owner = $Plan.Executor }
            $Changed.Add('application details updated') | Out-Null
            return "Application '$($Plan.ApplicationName)' updated."
        }

        'DeploymentType' {
            & $Provider.SetDeploymentType @{
                ApplicationName = $Plan.ApplicationName; DeploymentTypeName = $Plan.DeploymentType
                ContentPath = $Plan.ContentPath; InstallCommand = $Plan.InstallCommand; UninstallCommand = $Plan.UninstallCommand
                RepairCommand = $Plan.RepairCommand
                DetectionRules = $Plan.DetectionRules
                InstallationBehaviorType = $Plan.InstallationBehaviorType
                LogonRequirementType = $Plan.LogonRequirementType; MaxRuntimeMinutes = $Plan.MaxRuntimeMinutes
                EstimatedInstallMinutes = $Plan.EstimatedInstallMinutes
                ProgramVisibility = $Plan.ProgramVisibility
                OnSlowNetworkMode = $Plan.OnSlowNetworkMode
                AllowClientToShareContent = $Plan.AllowClientToShareContent
                AllowClientToUseFallback  = $Plan.AllowClientToUseFallback
                PersistContentInCache     = $Plan.PersistContentInCache
                Run32BitOn64Bit           = $Plan.Run32BitOn64Bit
                OperatingSystems          = $Plan.OperatingSystems }
            $Changed.Add('deployment type updated') | Out-Null
            return "Deployment type '$($Plan.DeploymentType)' updated - content path and detection rule refreshed."
        }

        'Category' {
            & $Provider.SetCategory @{ ApplicationName = $Plan.ApplicationName; Category = $Plan.Category }
            return "Category '$($Plan.Category)' set."
        }

        'Content' {
            & $Provider.StartContentDistribution @{ ApplicationName = $Plan.ApplicationName; DistributionPointGroup = $Plan.DistributionPointGroup }
            $Changed.Add('content re-distributed') | Out-Null
            return "Content re-distribution started to '$($Plan.DistributionPointGroup)'."
        }

        'Collections' {
            $added = 0
            foreach ($collection in $Plan.Collections) {
                if (& $Provider.TestCollectionName @{ Name = $collection.Name }) { continue }
                & $Provider.NewCollection @{ Name = $collection.Name; LimitingCollectionId = $collection.LimitingCollectionId; Comment = $collection.Comment }
                $Changed.Add("collection added: $($collection.Name)") | Out-Null
                $added++
            }
            return $(if ($added -gt 0) { "$added collection(s) added." } else { 'All collections already present.' })
        }

        'Deployments' {
            $added = 0
            foreach ($collection in $Plan.Collections) {
                if (& $Provider.TestDeployment @{ ApplicationName = $Plan.ApplicationName; CollectionName = $collection.Name }) { continue }
                & $Provider.NewDeployment @{ ApplicationName = $Plan.ApplicationName; CollectionName = $collection.Name; DeploymentAction = $collection.DeploymentAction }
                $Changed.Add("deployment added: $($collection.Name)") | Out-Null
                $added++
            }
            return $(if ($added -gt 0) { "$added deployment(s) added." } else { 'All deployments already present.' })
        }

        'Retire' {
            # Only collections this tool would itself have created for THIS
            # package are ever in scope, and only those the environment file no
            # longer asks for. A collection made by hand is never touched.
            $wanted = @($Plan.Collections | ForEach-Object { $_.Name })
            $live   = @(& $Provider.GetPackageCollections @{ PackageName = $Plan.PackageName })
            $stale  = @($live | Where-Object { $_ -and ($wanted -notcontains $_) })

            if ($stale.Count -eq 0) { return 'Nothing to retire.' }
            foreach ($name in $stale) {
                & $Provider.RemoveDeployment @{ ApplicationName = $Plan.ApplicationName; CollectionName = $name }
                & $Provider.RemoveCollection @{ Name = $name }
                $Changed.Add("retired: $name") | Out-Null
            }
            return "$($stale.Count) collection(s) and their deployments retired: $($stale -join ', ')."
        }

        'SecurityScope' {
            # The provider hands back what is REALLY on the application after the
            # adds, not what we asked for. Anything asked for and not there is
            # named - a scope that silently did not stick is a permissions
            # problem somebody has to know about, and reporting it as attached
            # is the same sin as the old tool's unconditional "Done."
            $attached = @(& $Provider.AddSecurityScope @{ ApplicationName = $Plan.ApplicationName; SecurityScopes = $Plan.SecurityScopes })
            $wanted   = @($Plan.SecurityScopes)

            if ($attached.Count -eq 0) {
                return "Asked for $($wanted.Count) security scope(s) - $($wanted -join ', ') - but NONE could be read back afterwards. Check the application's Security Scopes tab before relying on this."
            }

            # The read-back is "Name (ID)", so match on the ID appearing in it.
            # SCCM also puts every application in Default, so the tab always
            # shows ONE MORE than we asked for - that is SCCM, not a mistake.
            $absent = @($wanted | Where-Object { $id = $_; -not (@($attached | Where-Object { $_ -like "*($id)*" })) })
            $extra  = @($attached | Where-Object { $name = $_; -not (@($wanted | Where-Object { $name -like "*($_)*" })) })
            $note   = if ($extra.Count -gt 0) { " The application also carries $($extra -join ', ') - SCCM puts every application in Default, so the console shows one more than was asked for." } else { '' }

            if ($absent.Count -gt 0) {
                return "$($wanted.Count - $absent.Count) of $($wanted.Count) security scope(s) attached. NOT attached: $($absent -join ', '). On the application now: $($attached -join ', ').$note"
            }
            return "$($wanted.Count) security scope(s) attached and verified - $($attached -join ', ').$note"
        }

        'MoveObjects' {
            $app = & $Provider.GetApplicationObject @{ ApplicationName = $Plan.ApplicationName }
            & $Provider.MoveObject @{ FolderPath = $Plan.ApplicationFolder; InputObject = $app; Label = $Plan.ApplicationName
                                      SiteCode = $Plan.SiteCode; ObjectType = 'Application' }
            foreach ($collection in $Plan.Collections) {
                $obj = & $Provider.GetCollectionObject @{ Name = $collection.Name }
                & $Provider.MoveObject @{ FolderPath = $collection.Folder; InputObject = $obj; Label = $collection.Name
                                          SiteCode = $Plan.SiteCode; ObjectType = 'DeviceCollection' }
            }
            return "Application and $(@($Plan.Collections).Count) collections filed."
        }

        default { throw "Unknown modify step '$Key'." }
    }
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
                LocalizedName = $Plan.LocalizedName; LocalizedDescription = $Plan.LocalizedDescription
                LocalizedNameDe = $Plan.LocalizedNameDe; LocalizedDescriptionDe = $Plan.LocalizedDescriptionDe
                ApplicationComment = $Plan.ApplicationComment; Owner = $Plan.Executor
                OnDemandDistribution = $Plan.OnDemandDistribution; PrestagedSetting = $Plan.PrestagedSetting }
            $Created.Add([pscustomobject]@{ Kind = 'Application'; Name = $Plan.ApplicationName }) | Out-Null

            & $Provider.AddDeploymentType @{
                ApplicationName = $Plan.ApplicationName; DeploymentTypeName = $Plan.DeploymentType
                ContentPath = $Plan.ContentPath; InstallCommand = $Plan.InstallCommand; UninstallCommand = $Plan.UninstallCommand
                RepairCommand = $Plan.RepairCommand
                DetectionRules = $Plan.DetectionRules
                InstallationBehaviorType = $Plan.InstallationBehaviorType
                LogonRequirementType = $Plan.LogonRequirementType; MaxRuntimeMinutes = $Plan.MaxRuntimeMinutes
                EstimatedInstallMinutes = $Plan.EstimatedInstallMinutes
                ProgramVisibility = $Plan.ProgramVisibility
                OnSlowNetworkMode = $Plan.OnSlowNetworkMode
                AllowClientToShareContent = $Plan.AllowClientToShareContent
                AllowClientToUseFallback  = $Plan.AllowClientToUseFallback
                PersistContentInCache     = $Plan.PersistContentInCache
                Run32BitOn64Bit           = $Plan.Run32BitOn64Bit
                OperatingSystems          = $Plan.OperatingSystems }
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
            # NAME them. "9 collections created" tells a packager nothing they
            # can check; the names and their limiting collections are what they
            # would otherwise open the console to see.
            $made = New-Object System.Collections.Generic.List[string]
            foreach ($collection in $Plan.Collections) {
                & $Provider.NewCollection @{ Name = $collection.Name; LimitingCollectionId = $collection.LimitingCollectionId; Comment = $collection.Comment }
                $Created.Add([pscustomobject]@{ Kind = 'Collection'; Name = $collection.Name }) | Out-Null
                $made.Add("$($collection.Name) (under $($collection.LimitingCollectionId), filed in $($collection.Folder))") | Out-Null
            }
            return "$($made.Count) collections created: $($made -join ' | ')"
        }

        'Deployments' {
            # ...and say what each deployment actually IS. Install-or-uninstall
            # and available-or-required is the difference between offering
            # software and taking it away.
            $made = New-Object System.Collections.Generic.List[string]
            foreach ($collection in $Plan.Collections) {
                & $Provider.NewDeployment @{ ApplicationName = $Plan.ApplicationName; CollectionName = $collection.Name; DeploymentAction = $collection.DeploymentAction }
                $Created.Add([pscustomobject]@{ Kind = 'Deployment'; Name = $collection.Name }) | Out-Null
                $purpose = if ($collection.DeploymentAction -eq 'Uninstall') { 'Uninstall / Required' }
                           elseif ($collection.DeploymentAction -eq 'Required') { 'Install / Required' }
                           else { 'Install / Available' }
                $made.Add("$($collection.Name) -> $purpose") | Out-Null
            }
            return "$($made.Count) deployments created: $($made -join ' | ')"
        }

        'SecurityScope' {
            # The provider hands back what is REALLY on the application after the
            # adds, not what we asked for. Anything asked for and not there is
            # named - a scope that silently did not stick is a permissions
            # problem somebody has to know about, and reporting it as attached
            # is the same sin as the old tool's unconditional "Done."
            $attached = @(& $Provider.AddSecurityScope @{ ApplicationName = $Plan.ApplicationName; SecurityScopes = $Plan.SecurityScopes })
            $wanted   = @($Plan.SecurityScopes)

            if ($attached.Count -eq 0) {
                return "Asked for $($wanted.Count) security scope(s) - $($wanted -join ', ') - but NONE could be read back afterwards. Check the application's Security Scopes tab before relying on this."
            }

            # The read-back is "Name (ID)", so match on the ID appearing in it.
            # SCCM also puts every application in Default, so the tab always
            # shows ONE MORE than we asked for - that is SCCM, not a mistake.
            $absent = @($wanted | Where-Object { $id = $_; -not (@($attached | Where-Object { $_ -like "*($id)*" })) })
            $extra  = @($attached | Where-Object { $name = $_; -not (@($wanted | Where-Object { $name -like "*($_)*" })) })
            $note   = if ($extra.Count -gt 0) { " The application also carries $($extra -join ', ') - SCCM puts every application in Default, so the console shows one more than was asked for." } else { '' }

            if ($absent.Count -gt 0) {
                return "$($wanted.Count - $absent.Count) of $($wanted.Count) security scope(s) attached. NOT attached: $($absent -join ', '). On the application now: $($attached -join ', ').$note"
            }
            return "$($wanted.Count) security scope(s) attached and verified - $($attached -join ', ').$note"
        }

        'MoveObjects' {
            $app = & $Provider.GetApplicationObject @{ ApplicationName = $Plan.ApplicationName }
            & $Provider.MoveObject @{ FolderPath = $Plan.ApplicationFolder; InputObject = $app; Label = $Plan.ApplicationName
                                      SiteCode = $Plan.SiteCode; ObjectType = 'Application' }
            foreach ($collection in $Plan.Collections) {
                $obj = & $Provider.GetCollectionObject @{ Name = $collection.Name }
                & $Provider.MoveObject @{ FolderPath = $collection.Folder; InputObject = $obj; Label = $collection.Name
                                          SiteCode = $Plan.SiteCode; ObjectType = 'DeviceCollection' }
            }
            return "Application and $(@($Plan.Collections).Count) collections filed."
        }

        'ArsGroup' {
            # TURNED OFF for every environment, in Defaults.xml. The directory
            # refuses the request the old tool's attributes produce:
            #
            #   malformedRequest - Some of the specified attributes for the
            #   'group' object class are not defined in the schema.
            #
            # Everything in SCCM is already done and correct by this point, so
            # failing here would roll a perfectly good application back out over
            # a step nobody can use yet. It is skipped and SAID to be skipped -
            # never quietly reported as done - so no one believes the group
            # exists. Set Steps/@createArsGroup="true" once the attributes are
            # settled with whoever owns the ARS schema.
            if (-not $Plan.CreateArsGroup) {
                return "SKIPPED - the AD group '$($Plan.ArsGroupName)' was NOT created. Turned off in Defaults.xml (Steps/@createArsGroup) until the ARS attributes are agreed. Create it by hand if it is needed."
            }

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

    # REMOVAL TAKES WHAT IT FINDS.
    #
    # The plan says what a full integration WOULD have made. What is actually on
    # the site can be less than that - somebody deleted a collection by hand, or
    # an earlier integration failed halfway. Insisting on the plan means one
    # missing collection stops the removal and leaves the application behind,
    # which is the opposite of what "remove this package" is for.
    #
    # So each object is checked before it is touched, and one that is already
    # gone is counted as gone. Anything that IS there is still removed, and the
    # message says what was found and what was already missing.
    switch ($Key) {
        'Deployments' {
            $removed = 0; $absent = 0
            foreach ($collection in $Plan.Collections) {
                if (& $Provider.TestDeployment @{ ApplicationName = $Plan.ApplicationName; CollectionName = $collection.Name }) {
                    & $Provider.RemoveDeployment @{ ApplicationName = $Plan.ApplicationName; CollectionName = $collection.Name }
                    $removed++
                }
                else { $absent++ }
            }
            return "$removed deployment(s) removed$(if ($absent) { ", $absent already gone" })."
        }
        'Collections' {
            $removed = 0; $absent = 0
            foreach ($collection in $Plan.Collections) {
                if (& $Provider.TestCollectionName @{ Name = $collection.Name }) {
                    & $Provider.RemoveCollection @{ Name = $collection.Name }
                    $removed++
                }
                else { $absent++ }
            }
            return "$removed collection(s) removed$(if ($absent) { ", $absent already gone" })."
        }
        'Application' {
            if (-not (& $Provider.TestApplication @{ ApplicationName = $Plan.ApplicationName })) {
                return "Application '$($Plan.ApplicationName)' was already gone."
            }
            & $Provider.RemoveApplication @{ ApplicationName = $Plan.ApplicationName }
            return "Application '$($Plan.ApplicationName)' removed."
        }
        'ArsGroup' {
            # Not created, so not removed. Removing a group this tool never made
            # would be deleting somebody else's object.
            if (-not $Plan.CreateArsGroup) {
                return "SKIPPED - the AD group '$($Plan.ArsGroupName)' was NOT removed, because this tool does not create it. Turned off in Defaults.xml (Steps/@createArsGroup)."
            }
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
        catch { $undone.Add("$($item.Kind) $($item.Name) COULD NOT BE REMOVED: $(Get-AudiErrorText -ErrorRecord $_)") }
    }
    # .ToArray(), not @() - wrapping a generic List in PowerShell 5.1 throws
    # "Argument types do not match"
    return $undone.ToArray()
}

