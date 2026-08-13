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

# Declared up front. Under StrictMode a script-scope variable that has never been
# assigned throws the moment it is READ, so a machine whose console matches its
# site - where no version warning is ever raised - would fail on the first
# connect rather than the tenth.
$script:AudiConsoleVersionNote = ''
$script:AudiPreviousLocation   = $null

function Get-AudiErrorText {
    <#  Readable text for an error record, never an empty string.

        Some ConfigMgr cmdlets throw with NO message at all - their own
        validation fails and the error record carries nothing. Passing that
        straight to the log then fails a second time with "Cannot bind argument
        to parameter 'Message' because it is an empty string", and THAT is what
        the operator ends up reading instead of the real problem. So an empty
        message becomes something that at least names the step and the fault. #>
    [CmdletBinding()]
    param($ErrorRecord, [string]$Context = '')

    $text = ''
    if ($ErrorRecord) {
        try { $text = [string]$ErrorRecord.Exception.Message } catch { }
        if ([string]::IsNullOrWhiteSpace($text)) {
            $type = try { $ErrorRecord.Exception.GetType().Name } catch { 'Exception' }
            $text = "$type was thrown with no message."
            try { if ($ErrorRecord.CategoryInfo) { $text += " Category: $($ErrorRecord.CategoryInfo.Category)." } } catch { }
        }
    }
    if ([string]::IsNullOrWhiteSpace($text)) { $text = 'Failed with no reason given.' }
    if ($Context) { $text = "$Context $text" }
    return $text
}

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
            # -AutoInstall matches their <AllowInstallFromTaskSequence>true.
            # -Owner is set explicitly rather than left to whoever ran it: the
            # whole point of the project is that it reads as the service
            # account, so it is stated rather than assumed.
            New-CMApplication -Name $c.ApplicationName -Publisher $c.Publisher -SoftwareVersion $c.Version `
                              -LocalizedApplicationName $c.LocalizedName -LocalizedApplicationDescription $c.LocalizedDescription `
                              -AutoInstall $true -ErrorAction Stop | Out-Null

            # -Description is the admin Comment in the console, which is NOT the
            # Software Center description above. Their <Description> element put
            # "created by manual MCB script" there; this carries the job and the
            # RFC, so an application can be traced back the same way its
            # collections can.
            Set-CMApplication -Name $c.ApplicationName -Owner $c.Owner -SupportContact $c.Owner `
                              -Description $c.ApplicationComment -ErrorAction Stop | Out-Null

            # The Distribution Settings tab. Their tool set both of these and we
            # did not, which is why "Enable for on-demand distribution" was
            # unticked on the application ours made, and the prestaged radio sat
            # on SCCM's default of "manually copy" instead of AutoDownload.
            #
            # Applied separately and failing soft: they are console settings, not
            # the application itself, and losing a good application over a tick
            # box would be the wrong trade. If the parameter name differs on a
            # given console build, the run says so and carries on.
            try {
                Set-CMApplication -Name $c.ApplicationName `
                                  -DistributionPointSetting $c.PrestagedSetting `
                                  -SendToProtectedDistributionPoint $c.OnDemandDistribution `
                                  -ErrorAction Stop | Out-Null
            }
            catch {
                Write-Warning ("The Distribution Settings could not be applied to '{0}': {1}. Set them by hand on the application's Distribution Settings tab." -f $c.ApplicationName, $_.Exception.Message)
            }
            & $script:AudiSetGermanDisplay $c
        }

        AddDeploymentType = { param($c)
            # A detection rule must be a CLAUSE OBJECT, not a string. Passing the
            # key path as text is accepted by the parameter binder and then fails
            # inside SCCM, so the clauses are built properly here.
            $clauses = & $script:AudiNewDetectionClause $c

            # The Repair command is optional - the old tool set none at all - so
            # it is only passed when the config asks for one. Passing an empty
            # string would put a blank Repair command on the deployment type,
            # which is not the same as having none.
            $repair = @{}
            if (-not [string]::IsNullOrWhiteSpace($c.RepairCommand)) { $repair['RepairCommand'] = $c.RepairCommand }

            Add-CMScriptDeploymentType @repair `
                                       -ApplicationName $c.ApplicationName -DeploymentTypeName $c.DeploymentTypeName `
                                       -ContentLocation $c.ContentPath -InstallCommand $c.InstallCommand `
                                       -UninstallCommand $c.UninstallCommand -AddDetectionClause $clauses `
                                       -InstallationBehaviorType $c.InstallationBehaviorType `
                                       -LogonRequirementType $c.LogonRequirementType `
                                       -UserInteractionMode $c.ProgramVisibility `
                                       -MaximumRuntimeMins $c.MaxRuntimeMinutes -EstimatedRuntimeMins $c.EstimatedInstallMinutes `
                                       -ContentFallback:$c.AllowClientToUseFallback `
                                       -EnableBranchCache:$c.AllowClientToShareContent `
                                       -SlowNetworkDeploymentMode $c.OnSlowNetworkMode `
                                       -PersistContentInClientCache:$c.PersistContentInCache `
                                       -Force32Bit:$c.Run32BitOn64Bit `
                                       -ErrorAction Stop | Out-Null

            # Two of their <DeploymentType> values have no switch on the
            # supported cmdlets, so they are not set here:
            #
            #   OnFastNetworkMode=Download   already the default for a fast
            #                                network - the cmdlet only exposes
            #                                the SLOW network choice, which is
            #                                set above to the same value
            #   SendToProtectedDistributionPoint / DistributionPointSetting
            #                                their module wrote these straight
            #                                onto the content object through
            #                                WMI. Reaching for raw WMI to match
            #                                them would give back the very thing
            #                                this tool exists to remove.
            #
            # Neither changes what a client does with the package. If Audi wants
            # them set, they are a console change on the deployment type.

            # Operating system requirement rules, as the old tool set from its
            # <SccmOSRequirements> block. The platform strings in Defaults.xml
            # are the same values it used.
            if (@($c.OperatingSystems).Count -gt 0) {
                $condition = Get-CMGlobalCondition -Name 'Operating System' | Select-Object -First 1
                $rule = New-CMRequirementRuleOperatingSystemValue -GlobalCondition $condition `
                            -RuleOperator OneOf -PlatformString @($c.OperatingSystems) -ErrorAction Stop
                Set-CMScriptDeploymentType -ApplicationName $c.ApplicationName -DeploymentTypeName $c.DeploymentTypeName `
                                           -AddRequirement $rule -ErrorAction Stop | Out-Null
            }
        }

        # -AddAppCategory wants a CATEGORY OBJECT, not the name:
        #
        #   "Cannot convert the "Development" value of type System.String to type
        #    Microsoft.ConfigurationManagement.ManagementProvider.IResultObject"
        #
        # Older builds took a string, so the string is tried as a fallback rather
        # than pinning the tool to one console version. The category is created
        # if the site does not have it - a new site has no categories at all, and
        # failing there would roll back a perfectly good application.
        SetCategory = { param($c)
            $category = Get-CMCategory -Name $c.Category -CategoryType AppCategories -ErrorAction SilentlyContinue |
                        Select-Object -First 1
            if (-not $category) {
                $category = New-CMCategory -Name $c.Category -CategoryType AppCategories -ErrorAction Stop
            }
            try   { Set-CMApplication -Name $c.ApplicationName -AddAppCategory $category -ErrorAction Stop | Out-Null }
            catch { Set-CMApplication -Name $c.ApplicationName -AddAppCategory $c.Category -ErrorAction Stop | Out-Null }
        }

        StartContentDistribution = { param($c)
            Start-CMContentDistribution -ApplicationName $c.ApplicationName -DistributionPointGroupName $c.DistributionPointGroup -ErrorAction Stop | Out-Null
        }

        NewCollection = { param($c)
            New-CMDeviceCollection -Name $c.Name -LimitingCollectionId $c.LimitingCollectionId -Comment $c.Comment -ErrorAction Stop | Out-Null
        }

        NewDeployment = { param($c)
            # The environment file says what a deployment is FOR in one word, the
            # way the old tool's XML did. SCCM splits that idea across two
            # parameters, and they are not interchangeable:
            #
            #   -DeployAction    Install | Uninstall     what it does
            #   -DeployPurpose   Available | Required    whether a user chooses
            #
            # Passing 'Available' as the ACTION gives:
            #   "Unable to match the identifier name Available to a valid
            #    enumerator name. Specify one of: Install, Uninstall"
            #
            # Uninstall is always Required - nobody opts in to having software
            # taken away - and Available is what puts an install into Software
            # Center for a user to pick.
            switch ($c.DeploymentAction) {
                'Uninstall' { $action = 'Uninstall'; $purpose = 'Required' }
                'Required'  { $action = 'Install';   $purpose = 'Required' }
                default     { $action = 'Install';   $purpose = 'Available' }
            }
            New-CMApplicationDeployment -Name $c.ApplicationName -CollectionName $c.CollectionName `
                                        -DeployAction $action -DeployPurpose $purpose -ErrorAction Stop | Out-Null
        }

        # The environment files hold scope IDs (INA00003). Current consoles want
        # the scope OBJECT, the same as -AddAppCategory; older ones took the id.
        # Try the object, fall back to the id, rather than pinning the tool to
        # one console version.
        AddSecurityScope = { param($c)
            $app = Get-CMApplication -Name $c.ApplicationName -Fast -ErrorAction Stop
            foreach ($scope in $c.SecurityScopes) {
                $scopeObject = Get-CMSecurityScope -Id $scope -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($scopeObject) {
                    try   { Add-CMObjectSecurityScope -InputObject $app -Scope $scopeObject -ErrorAction Stop | Out-Null }
                    catch { Add-CMObjectSecurityScope -InputObject $app -Id $scope -ErrorAction Stop | Out-Null }
                }
                else { Add-CMObjectSecurityScope -InputObject $app -Id $scope -ErrorAction Stop | Out-Null }
            }
        }

        # ---- used by Modify, to bring an existing application back into line
        #
        # Modify never creates a second application. It updates the one that is
        # there, adds what is missing and removes what is no longer wanted.
        SetApplication = { param($c)
            Set-CMApplication -Name $c.ApplicationName `
                              -Publisher $c.Publisher -SoftwareVersion $c.Version `
                              -LocalizedApplicationName $c.LocalizedName `
                              -LocalizedApplicationDescription $c.LocalizedDescription `
                              -ErrorAction Stop | Out-Null
            & $script:AudiSetGermanDisplay $c
        }

        SetDeploymentType = { param($c)
            Set-CMScriptDeploymentType -ApplicationName $c.ApplicationName -DeploymentTypeName $c.DeploymentTypeName `
                                       -ContentLocation $c.ContentPath -InstallCommand $c.InstallCommand `
                                       -UninstallCommand $c.UninstallCommand `
                                       -InstallationBehaviorType $c.InstallationBehaviorType `
                                       -LogonRequirementType $c.LogonRequirementType `
                                       -MaximumRuntimeMins $c.MaxRuntimeMinutes -EstimatedRuntimeMins $c.EstimatedInstallMinutes `
                                       -ErrorAction Stop | Out-Null

            # The detection rules have to be REPLACED, not added to. A new
            # revision changes rule 1, and adding it beside the old one would
            # give a deployment type that can never detect itself as installed:
            # SCCM ANDs the clauses, and the old revision will not be there.
            $existing = @(& $script:AudiGetDetectionClauseName $c)
            $replace  = @{ ApplicationName = $c.ApplicationName; DeploymentTypeName = $c.DeploymentTypeName
                           AddDetectionClause = (& $script:AudiNewDetectionClause $c); ErrorAction = 'Stop' }
            if ($existing.Count -gt 0) { $replace['RemoveDetectionClause'] = $existing }
            Set-CMScriptDeploymentType @replace | Out-Null
        }

        TestDeployment = { param($c)
            [bool](Get-CMApplicationDeployment -Name $c.ApplicationName -CollectionName $c.CollectionName -ErrorAction SilentlyContinue)
        }

        # Every collection this tool would ever have made for this package. Used
        # to find ones the environment file no longer asks for. Deliberately
        # narrow: it can only ever match names built from this package's own
        # name, so a hand-made collection is never in scope for removal.
        GetPackageCollections = { param($c)
            @(Get-CMDeviceCollection -Name "*$($c.PackageName)*" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        }

        # ---- preflight probes: read-only, used before anything is created
        # 'FileSystem::' IS NOT OPTIONAL HERE.
        #
        # These run while the current location is the site drive, and a path with
        # no drive qualifier is resolved by the CURRENT provider. 'C:\temp\...'
        # names a drive so it reaches the filesystem, but '\\server\share\...'
        # does not - the ConfigMgr provider tries to resolve it, fails, and
        # Test-Path answers $false for a share that is sitting right there and
        # perfectly readable. Naming the provider pins it to the filesystem.
        TestContentPath    = { param($c) Test-Path -LiteralPath "FileSystem::$($c.Path)" }

        # The share without the package folder. Test-Path answers false both when
        # a folder is missing and when this account cannot see the share at all,
        # and those need different fixes - so ask separately and say which it is.
        TestContentShare   = { param($c) Test-Path -LiteralPath "FileSystem::$($c.Path)" }
        GetContentShareNames = { param($c)
            @(Get-ChildItem -LiteralPath "FileSystem::$($c.Path)" -Directory -ErrorAction SilentlyContinue |
              Select-Object -First 8 | ForEach-Object { $_.Name })
        }
        TestCollectionId   = { param($c) [bool](Get-CMCollection -Id $c.Id -ErrorAction SilentlyContinue) }
        TestDpGroup        = { param($c) [bool](Get-CMDistributionPointGroup -Name $c.Name -ErrorAction SilentlyContinue) }

        # How many distribution points are IN that group. A group that exists but
        # is empty passes the check above and then fails the moment content is
        # distributed to it - there is nowhere for the content to go. Returns -1
        # when the count cannot be read, which is reported rather than treated
        # as empty.
        GetDpGroupMemberCount = { param($c)
            $group = Get-CMDistributionPointGroup -Name $c.Name -ErrorAction SilentlyContinue
            if (-not $group) { return 0 }
            try   { return [int]$group.MemberCount }
            catch { return -1 }
        }
        TestSecurityScope  = { param($c) [bool](Get-CMSecurityScope -Id $c.Id -ErrorAction SilentlyContinue) }
        TestCollectionName = { param($c) [bool](Get-CMCollection -Name $c.Name -ErrorAction SilentlyContinue) }

        # ---- distribution state, so the tool can wait for a real result
        #
        # Get-CMDistributionStatus has no -Name on a current console:
        #
        #     "A parameter cannot be found that matches parameter name 'Name'."
        #
        # AND A PARAMETER BINDING ERROR IS TERMINATING - -ErrorAction
        # SilentlyContinue does not suppress it, because the binder fails before
        # the cmdlet runs at all. So this threw and failed a step whose real
        # work, starting the distribution, had already succeeded.
        #
        # It takes -InputObject, so the application is fetched and passed.
        # Reading progress is a CONVENIENCE: distribution is asynchronous and
        # SCCM finishes it whether or not anyone is watching. If the status
        # cannot be read, say so rather than failing a distribution that is
        # already under way - Readable carries that back to the caller.
        GetDistributionState = { param($c)
            $unknown = @{ Total = 0; Success = 0; Failed = 0; InProgress = 0; Readable = $false }
            try {
                $app = Get-CMApplication -Name $c.ApplicationName -Fast -ErrorAction Stop
                if (-not $app) { return $unknown }
                $status = Get-CMDistributionStatus -InputObject $app -ErrorAction SilentlyContinue
                if (-not $status) { return $unknown }
                return @{ Total = [int]$status.Targeted; Success = [int]$status.NumberSuccess
                          Failed = [int]$status.NumberErrors; InProgress = [int]$status.NumberInProgress
                          Readable = $true }
            }
            catch { return $unknown }
        }

        # The environment file holds the folder as the console shows it -
        # 'ICZ-Applications', 'II1-Site\II1-Software Management'. Move-CMObject
        # wants a PROVIDER path rooted at the object type:
        #
        #   console   \Software Library\...\Applications\ICZ-Applications
        #   provider  ICZ:\Application\ICZ-Applications
        #
        #   console   \Assets and Compliance\...\Device Collections\II1-Site\...
        #   provider  ICZ:\DeviceCollection\II1-Site\II1-Software Management
        #
        # Passing the bare name binds happily and then fails at the site, so the
        # path is built here. Each level is created if it is not already there,
        # which is what the old tool did too - otherwise a new environment needs
        # every folder made by hand before the first integration will file.
        MoveObject = { param($c)
            $path = "$($c.SiteCode):\$($c.ObjectType)"
            foreach ($segment in @($c.FolderPath -split '\\' | Where-Object { $_ })) {
                $parent = $path
                $path   = Join-Path $parent $segment
                if (-not (Test-Path -LiteralPath $path)) {
                    New-CMFolder -Name $segment -ParentFolderPath $parent -ErrorAction Stop | Out-Null
                }
            }
            Move-CMObject -FolderPath $path -InputObject $c.InputObject -ErrorAction Stop | Out-Null
        }

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

# ----------------------------------------------------------- detection clauses
#
# One clause per rule on the plan, ANDed by SCCM: rule 1 is the branding key the
# package writes, rule 2 is the product's own uninstall entry from the deployment
# script's VWG_SoftIdent. A rule with no value name is a key-exists test.
#
# The hive comes from the rule rather than being assumed, because a SoftIdent is
# free text in the package and could name HKCU.
$script:AudiGetDetectionClauseName = {
    <#  The logical names of the detection clauses a deployment type already has,
        so Modify can replace them rather than pile new ones on top.

        They are only reachable through the deployment type's SDMPackageXML -
        there is no Get-CMDetectionClause cmdlet. If they cannot be read this
        returns nothing, and the caller adds without removing; that is visible
        in the console rather than silently wrong.  #>
    param($c)

    try {
        $dt = Get-CMDeploymentType -ApplicationName $c.ApplicationName -DeploymentTypeName $c.DeploymentTypeName -ErrorAction Stop
        if (-not $dt) { return @() }
        $xml = [string]$dt.SDMPackageXML
        if ([string]::IsNullOrWhiteSpace($xml)) { return @() }
        return @([regex]::Matches($xml, 'LogicalName="(?<n>(?:RegistrySetting|File|Folder|MSI|Script)_[^"]+)"') |
                 ForEach-Object { $_.Groups['n'].Value } | Select-Object -Unique)
    }
    catch { return @() }
}

$script:AudiNewDetectionClause = {
    param($c)

    $rules = @($c.DetectionRules)
    if ($rules.Count -eq 0) {
        throw "The plan carries no detection rule for '$($c.DeploymentTypeName)'. An application with no detection rule would reinstall on every evaluation."
    }

    $clauses = New-Object System.Collections.Generic.List[object]
    foreach ($rule in $rules) {
        $hive = switch -Regex ($rule.Hive) {
            'HKLM|LOCAL_MACHINE' { 'LocalMachine'; break }
            'HKCU|CURRENT_USER'  { 'CurrentUser';  break }
            'HKCR|CLASSES_ROOT'  { 'ClassesRoot';  break }
            default              { 'LocalMachine' }
        }

        if ([string]::IsNullOrWhiteSpace($rule.ValueName)) {
            # the key itself is the evidence - no value to compare
            $clause = New-CMDetectionClauseRegistryKey -Hive $hive -KeyName $rule.Key `
                          -Existence -Is64Bit:$rule.Is64Bit -ErrorAction Stop
        }
        else {
            $clause = New-CMDetectionClauseRegistryKeyValue -Hive $hive -KeyName $rule.Key `
                          -ValueName $rule.ValueName -PropertyType $rule.DataType `
                          -ExpectedValue $rule.Value -ExpressionOperator IsEquals `
                          -Value -Is64Bit:$rule.Is64Bit -ErrorAction Stop
        }
        $clauses.Add($clause) | Out-Null
    }

    # .ToArray(): @() on a List[object] of PSObjects throws under PowerShell 5.1
    return $clauses.ToArray()
}

# ------------------------------------------------------- German display entry
#
# SCCM keeps one display name and description PER LANGUAGE, inside the
# application's SDMPackageXML. The supported cmdlets only ever write the
# console's own language, which is why New-CMApplication alone leaves the German
# entry empty. The old Audi tool built that XML by hand and pushed it through
# WMI; this does the same thing through the supported serializer.
#
# NOT YET EXERCISED AGAINST A LIVE SITE. It is written to fail soft: if the
# German entry cannot be added the English one is already in place, so the
# application is still correct, and the reason is surfaced as a warning rather
# than failing the whole integration.
$script:AudiSetGermanDisplay = {
    param($c)

    if ([string]::IsNullOrWhiteSpace($c.LocalizedNameDe)) { return }
    try {
        $app = Get-CMApplication -Name $c.ApplicationName -ErrorAction Stop
        $xml = [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::DeserializeFromString($app.SDMPackageXML, $true)

        $german = $xml.DisplayInfo | Where-Object { $_.Language -eq 'de-DE' } | Select-Object -First 1
        if (-not $german) {
            $german = New-Object Microsoft.ConfigurationManagement.ApplicationManagement.AppDisplayInfo
            $german.Language = 'de-DE'
            $xml.DisplayInfo.Add($german) | Out-Null
        }
        $german.Title       = $c.LocalizedNameDe
        $german.Description = $c.LocalizedDescriptionDe

        $updated = [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::Serialize($xml, $false)
        $app.SDMPackageXML = $updated
        $app.Put()
    }
    catch {
        Write-Warning ("The German display name could not be written for '{0}': {1}. The English entry is in place." -f $c.ApplicationName, $_.Exception.Message)
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
        [string[]]$Missing = @(),
        # deployments already on the site, as 'CollectionName'
        [string[]]$ExistingDeployments  = @()
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
    # The detection rules are described INLINE, not by calling a helper function.
    # These handlers are closures: a closure carries the session state it was
    # made in, so a function defined at load time is not reliably reachable from
    # inside one - which is how this line silently failed every step once.
    $describe = {
        param($rules)
        (@($rules | ForEach-Object {
            if ([string]::IsNullOrWhiteSpace($_.ValueName)) { "{0}\{1} exists" -f $_.Hive, $_.Key }
            else { "{0}\{1}\{2}={3}" -f $_.Hive, $_.Key, $_.ValueName, $_.Value }
        }) -join ' AND ')
    }
    $provider.AddDeploymentType        = { param($c) & $record 'AddDeploymentType' ("{0} | detection {1} | OS {2}" -f $c.DeploymentTypeName, (& $describe $c.DetectionRules), (@($c.OperatingSystems).Count)) }.GetNewClosure()
    $provider.SetCategory              = { param($c) & $record 'SetCategory'              $c.Category }.GetNewClosure()
    $provider.StartContentDistribution = { param($c) & $record 'StartContentDistribution' $c.DistributionPointGroup }.GetNewClosure()
    $provider.NewCollection            = { param($c) & $record 'NewCollection'            $c.Name }.GetNewClosure()
    $provider.NewDeployment            = { param($c) & $record 'NewDeployment'            ("{0} -> {1} ({2})" -f $c.ApplicationName, $c.CollectionName, $c.DeploymentAction) }.GetNewClosure()
    $provider.AddSecurityScope         = { param($c) & $record 'AddSecurityScope'         ($c.SecurityScopes -join ',') }.GetNewClosure()
    $provider.MoveObject               = { param($c) & $record 'MoveObject'               ("{0} -> {1}:\{2}\{3}" -f $c.Label, $c.SiteCode, $c.ObjectType, $c.FolderPath) }.GetNewClosure()
    $provider.GetApplicationObject     = { param($c) [pscustomobject]@{ Kind = 'Application'; Name = $c.ApplicationName } }.GetNewClosure()
    $provider.GetCollectionObject      = { param($c) [pscustomobject]@{ Kind = 'Collection';  Name = $c.Name } }.GetNewClosure()
    $provider.RemoveDeployment         = { param($c) & $record 'RemoveDeployment'         ("{0} -> {1}" -f $c.ApplicationName, $c.CollectionName) }.GetNewClosure()
    $provider.RemoveCollection         = { param($c) & $record 'RemoveCollection'         $c.Name }.GetNewClosure()
    $provider.RemoveApplication        = { param($c) & $record 'RemoveApplication'        $c.ApplicationName }.GetNewClosure()
    $provider.NewArsGroup              = { param($c) & $record 'NewArsGroup'              $c.GroupName }.GetNewClosure()
    $provider.RemoveArsGroup           = { param($c) & $record 'RemoveArsGroup'           $c.GroupName }.GetNewClosure()

    # ---- Modify
    $provider.SetApplication    = { param($c) & $record 'SetApplication'    $c.ApplicationName }.GetNewClosure()
    $provider.SetDeploymentType = { param($c) & $record 'SetDeploymentType' $c.DeploymentTypeName }.GetNewClosure()
    $provider.TestDeployment    = { param($c) $ExistingDeployments -contains $c.CollectionName }.GetNewClosure()
    $provider.GetPackageCollections = { param($c) @($ExistingCollections) }.GetNewClosure()

    # preflight probes: everything present unless the caller says otherwise
    $provider.TestContentPath    = { param($c) -not ($Missing -contains 'ContentPath') }.GetNewClosure()
    $provider.TestContentShare   = { param($c) -not ($Missing -contains 'ContentShare') }.GetNewClosure()
    $provider.GetContentShareNames = { param($c) @() }.GetNewClosure()
    $provider.TestCollectionId   = { param($c) -not ($Missing -contains "Collection:$($c.Id)") }.GetNewClosure()
    $provider.TestDpGroup        = { param($c) -not ($Missing -contains "DpGroup:$($c.Name)") }.GetNewClosure()
    $provider.GetDpGroupMemberCount = { param($c) $(if ($Missing -contains 'DpGroupEmpty') { 0 } else { 2 }) }.GetNewClosure()
    $provider.TestSecurityScope  = { param($c) -not ($Missing -contains "Scope:$($c.Id)") }.GetNewClosure()
    $provider.TestCollectionName = { param($c) $ExistingCollections -contains $c.Name }.GetNewClosure()
    $provider.GetDistributionState = { param($c) $(if ($Missing -contains 'DistributionStatus') { @{ Total = 0; Success = 0; Failed = 0; InProgress = 0; Readable = $false } } else { @{ Total = 2; Success = 2; Failed = 0; InProgress = 0; Readable = $true } }) }.GetNewClosure()

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

        # The SAME version-warning trap as the drive below, which is easy to miss
        # here. When the console build differs from the site build the module
        # complains - "A new version of the console is available" - but it still
        # loads and every one of its cmdlets is exported. With -ErrorAction Stop
        # that complaint becomes a terminating error and the job fails having
        # done nothing. So import quietly and judge by whether the module is
        # actually there.
        Import-Module $module -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -ErrorVariable importError
        if (-not (Get-Module -Name ConfigurationManager)) {
            $detail = if ($importError) { [string]$importError[0] } else { 'no further detail' }
            return @{ Ok = $false; Message = "The ConfigMgr module could not be loaded: $detail"; Drive = $null }
        }
        # It loaded, but a mismatch is still worth saying out loud rather than
        # swallowing: cmdlets from a different build than the site are Microsoft's
        # own caveat, not ours.
        if ($importError) { $script:AudiConsoleVersionNote = [string]$importError[0] }
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
    # Creating the drive is not enough. Every ConfigMgr cmdlet refuses to run
    # unless the CURRENT LOCATION is that drive:
    #
    #   "This command cannot be run from the current drive. To run this command
    #    you must first connect to a Configuration Manager drive."
    #
    # So step into it here. The caller must step back out before doing file work
    # - Get-ChildItem with -Filter/-Recurse/-File throws under the CMSite
    # provider - which is what Restore-AudiFileSystemLocation is for.
    # Remember where we were standing, so it can be handed back exactly. Setting
    # the location changes the PROCESS working directory: a collector started
    # with a relative path and looping would find its own script gone on the
    # second pass if we dropped it somewhere else.
    $here = Get-Location
    if ($here.Provider.Name -eq 'FileSystem') { $script:AudiPreviousLocation = $here }

    try { Set-Location -LiteralPath "${drive}:" -ErrorAction Stop }
    catch { return @{ Ok = $false; Message = "The site drive ${drive}: was created but could not be entered: $($_.Exception.Message)"; Drive = $null } }

    $message = "Connected to $drive on $($Plan.SiteServer)."
    if ($script:AudiConsoleVersionNote) { $message += " Note: $($script:AudiConsoleVersionNote)" }
    return @{ Ok = $true; Message = $message; Drive = $drive }
}

function Restore-AudiFileSystemLocation {
    <#  Steps back off the CMSite drive onto the filesystem path we came from.

        The ConfigMgr provider does not support -Filter, -Recurse or -File, so
        any Get-ChildItem left running under it throws "the provider does not
        support filters". The collector reads its drop folder that way on every
        pass, so it must come back before the next one.

        It returns to WHERE IT WAS, not to C:\. Set-Location changes the process
        working directory, so a collector started as .\Server\Watch-... and left
        sitting on C:\ cannot find its own script on the second pass:
        "The term '.\Server\Watch-AudiSwDropFolder.ps1' is not recognized."  #>
    [CmdletBinding()]
    param()

    if ((Get-Location).Provider.Name -eq 'FileSystem') { return }

    if ($script:AudiPreviousLocation -and (Test-Path -LiteralPath $script:AudiPreviousLocation.Path)) {
        Set-Location -LiteralPath $script:AudiPreviousLocation.Path
    }
    else {
        Set-Location -LiteralPath "$env:SystemDrive\"
    }
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
                DetectionKey = $Plan.DetectionKey; DetectionValue = $Plan.DetectionValue
                DetectionData = $Plan.DetectionData; DetectionIs64Bit = $Plan.DetectionIs64Bit
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
            & $Provider.AddSecurityScope @{ ApplicationName = $Plan.ApplicationName; SecurityScopes = $Plan.SecurityScopes }
            return "$(@($Plan.SecurityScopes).Count) security scopes attached."
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
                DetectionKey = $Plan.DetectionKey; DetectionValue = $Plan.DetectionValue
                DetectionData = $Plan.DetectionData; DetectionIs64Bit = $Plan.DetectionIs64Bit
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
