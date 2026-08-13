# ==============================================================================
#  Audi SCCM Integration Tool - the SCCM provider
# ==============================================================================
#  Every call this tool makes to a real site lives here, and nowhere else.
#
#  Two providers with the same shape:
#    New-AudiSccmProvider        the real one - the smallest possible wrapper
#                                around each supported ConfigMgr command, so the
#                                engine holds no raw WMI
#    New-AudiSccmDryRunProvider  touches nothing, records what would have
#                                happened. Drives the packager's preview and
#                                every test in Tests\
#
#  Because the engine only ever speaks to a provider, the whole of it can be
#  tested with no SCCM, no network and no rights - which is what the 400-odd
#  checks in Tests\ do.
#
#  Also here: connecting to the site, and stepping back off it. Both are more
#  awkward than they look and both are commented at the point of use.
#
#  Dot-sourced by AudiSwIntegration.ps1. ASCII only.
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
            # THE APPLICATION IS RE-FETCHED FOR EVERY SCOPE.
            #
            # Adding a scope changes the application's CI version. Adding the
            # next one to the object we fetched before that happened is applied
            # to a version that is no longer current, and it silently does
            # nothing - the cmdlet reports success and the console shows only
            # 'Default'. That is exactly what happened on the first real run.
            foreach ($scope in $c.SecurityScopes) {
                $app = Get-CMApplication -Name $c.ApplicationName -Fast -ErrorAction Stop
                $scopeObject = Get-CMSecurityScope -Id $scope -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($scopeObject) {
                    try   { Add-CMObjectSecurityScope -InputObject $app -Scope $scopeObject -ErrorAction Stop | Out-Null }
                    catch { Add-CMObjectSecurityScope -InputObject $app -Id $scope -ErrorAction Stop | Out-Null }
                }
                else { Add-CMObjectSecurityScope -InputObject $app -Id $scope -ErrorAction Stop | Out-Null }
            }

            # ...and then READ BACK what is really on it. Reporting "4 scopes
            # attached" because four calls returned without throwing is the same
            # sin as the old tool's "Done." - it is a claim, not a fact.
            # Reported as "Name (ID)". The environment file holds IDs like
            # ICZ00001, but the console's Security Scopes tab lists NAMES - so an
            # ID alone cannot be checked against what is on screen, which is why
            # "4 scopes attached" looked like nothing had happened.
            $after = Get-CMApplication -Name $c.ApplicationName -Fast -ErrorAction SilentlyContinue
            if (-not $after) { return @() }
            return @(Get-CMObjectSecurityScope -InputObject $after -ErrorAction SilentlyContinue |
                     ForEach-Object { "{0} ({1})" -f $_.CategoryName, $_.CategoryID })
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

        # What security scopes an application really carries. Used to report the
        # truth after attaching them, and by Get-AudiSwPackageState.
        GetObjectSecurityScope = { param($c)
            $app = Get-CMApplication -Name $c.ApplicationName -Fast -ErrorAction SilentlyContinue
            if (-not $app) { return @() }
            @(Get-CMObjectSecurityScope -InputObject $app -ErrorAction SilentlyContinue |
              ForEach-Object { [string]$_.CategoryID })
        }

        # What the application and its deployment type are ACTUALLY set to
        # right now. Read-only.
        #
        # The application's own properties come off the object, but everything
        # about the deployment type lives inside SDMPackageXML - a serialised
        # blob, not queryable columns - so it is deserialised with the same
        # SccmSerializer the console uses. Get-CMDeploymentType returns the
        # wrapper, not the installer settings underneath it.
        #
        # Returns a flat hashtable keyed by the property names in the settings
        # catalogue. A property that cannot be read is simply absent, never
        # guessed at: a wrong "current value" would be edited on top of.
        GetApplicationSettings = { param($c)
            $values = @{}
            $app = Get-CMApplication -Name $c.ApplicationName -ErrorAction SilentlyContinue
            if (-not $app) { return $values }

            # NEVER read a property straight off this object.
            #
            # Under Set-StrictMode -Version 2.0 an absent property THROWS rather
            # than returning null, and Get-CMApplication does not surface all of
            # these at the top level - Publisher and SoftwareVersion live inside
            # SDMPackageXML, not on SMS_Application. Reading $app.Publisher
            # killed the whole Inspect with "The property 'Publisher' cannot be
            # found on this object".
            $read = {
                param($object, $name)
                if ($null -eq $object) { return $null }
                $property = $object.PSObject.Properties[$name]
                if ($null -eq $property) { return $null }
                return $property.Value
            }

            foreach ($p in 'LocalizedDisplayName', 'LocalizedDescription') {
                $v = & $read $app $p
                if ($null -ne $v) { $values[$p] = [string]$v }
            }

            try {
                $xml = [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::DeserializeFromString($app.SDMPackageXML, $true)

                # Publisher, version and the display strings are properties of
                # the deserialised application, and only reliably there.
                foreach ($pair in @(
                    @('Publisher',            'Publisher'),
                    @('SoftwareVersion',      'SoftwareVersion'))) {
                    $v = & $read $xml $pair[1]
                    if ($null -ne $v -and -not $values.ContainsKey($pair[0])) { $values[$pair[0]] = [string]$v }
                }
                $display = @(& $read $xml 'DisplayInfo')
                if ($display.Count -gt 0) {
                    $title = & $read $display[0] 'Title'
                    $desc  = & $read $display[0] 'Description'
                    if ($null -ne $title -and -not $values.ContainsKey('LocalizedDisplayName')) { $values['LocalizedDisplayName'] = [string]$title }
                    if ($null -ne $desc  -and -not $values.ContainsKey('LocalizedDescription')) { $values['LocalizedDescription'] = [string]$desc }
                }

                $dt = @(& $read $xml 'DeploymentTypes')[0]
                if ($dt) {
                    # Same rule as above: every read goes through $read. An
                    # installer type we have not met - MSI, App-V, a future one -
                    # simply will not carry some of these, and a direct read
                    # would take the whole Inspect down instead of leaving one
                    # setting unreadable.
                    $i = & $read $dt 'Installer'

                    foreach ($pair in @(
                        @('InstallCommandLine',      'InstallCommandLine'),
                        @('UninstallCommandLine',    'UninstallCommandLine'),
                        @('RepairCommandLine',       'RepairCommandLine'),
                        @('ExecutionContext',        'ExecutionContext'),
                        @('PostInstallBehavior',     'PostInstallBehavior'),
                        @('RequireUserInteraction',  'RequiresUserInteraction'))) {
                        $v = & $read $i $pair[1]
                        if ($null -ne $v) { $values[$pair[0]] = [string]$v }
                    }

                    # Tri-state: null means "whether or not a user is signed in",
                    # which is not the same as False ("only when none is"), so
                    # the empty string is a real value here rather than a miss.
                    if ($null -ne $i) {
                        $logon = & $read $i 'RequiresLogOn'
                        $values['RequiresLogOn'] = $(if ($null -eq $logon) { '' } else { [string]$logon })
                    }

                    $maxTime = & $read $i 'MaxExecuteTime'
                    $estTime = & $read $i 'ExecuteTime'
                    if ($null -ne $maxTime) { $values['MaximumRuntimeMins']   = [string][int]$maxTime }
                    if ($null -ne $estTime) { $values['EstimatedRuntimeMins'] = [string][int]$estTime }

                    $content = @(& $read $i 'Contents')[0]
                    if ($content) {
                        foreach ($pair in @(
                            @('ContentLocation',           'Location'),
                            @('PersistContentInCache',     'PinOnClient'),
                            @('SlowNetworkDeploymentMode', 'OnSlowNetwork'))) {
                            $v = & $read $content $pair[1]
                            if ($null -ne $v) { $values[$pair[0]] = [string]$v }
                        }
                    }
                }
            }
            catch {
                # A blob that will not deserialise is reported as unreadable
                # rather than as an application with no settings.
                $values['_Error'] = "The deployment type settings could not be read: $($_.Exception.Message)"
            }
            return $values
        }

        # Writes ONE setting. One call per setting, deliberately: a batch that
        # half-succeeds leaves nobody able to say which half, and the result
        # file has to name each change that landed.
        #
        # $c.Parameter is the cmdlet parameter name from the catalogue, and
        # $c.Value is already in the shape the cmdlet wants - the read/write
        # vocabularies differ for some settings and the translation happened
        # before this point.
        SetApplicationSetting = { param($c)
            $args = @{ Name = $c.ApplicationName; ErrorAction = 'Stop' }
            $args[$c.Parameter] = $c.Value
            Set-CMApplication @args | Out-Null
        }

        SetDeploymentTypeSetting = { param($c)
            $args = @{
                ApplicationName    = $c.ApplicationName
                DeploymentTypeName = $c.DeploymentTypeName
                ErrorAction        = 'Stop'
            }
            # Numbers must go over as integers: the cmdlet's parameters are
            # typed, and a string binds as a terminating error that -ErrorAction
            # cannot suppress.
            $value = $c.Value
            if ($c.Parameter -in @('EstimatedRuntimeMins', 'MaximumRuntimeMins')) { $value = [int]$value }
            elseif ($c.Parameter -in @('RequireUserInteraction', 'PersistContentInClientCache')) { $value = [bool]::Parse($value) }
            $args[$c.Parameter] = $value
            Set-CMScriptDeploymentType @args | Out-Null
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
        [string[]]$ExistingDeployments  = @(),
        [string[]]$ExistingScopes       = @()
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
    $provider.AddSecurityScope         = { param($c) & $record 'AddSecurityScope' ($c.SecurityScopes -join ',');
        $(if ($Missing -contains 'ScopeDidNotStick') { @() } else { @($c.SecurityScopes | ForEach-Object { "Scope $_ ($_)" }) }) }.GetNewClosure()
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
    # "Name (ID)", the same shape the real provider reports - a stand-in that
    # answers in a different shape lets a test pass on something production
    # never produces.
    $provider.GetObjectSecurityScope = { param($c) @($ExistingScopes | ForEach-Object { "Scope $_ ($_)" }) }.GetNewClosure()

    $provider.SetApplicationSetting    = { param($c) & $record 'SetApplicationSetting'    "$($c.Parameter) = $($c.Value)" }.GetNewClosure()
    $provider.SetDeploymentTypeSetting = { param($c) & $record 'SetDeploymentTypeSetting' "$($c.Parameter) = $($c.Value)" }.GetNewClosure()

    # A plausible set of current settings, keyed exactly as the real provider
    # keys them. Same shape or the Modify tab is being tested against something
    # production never returns.
    $provider.GetApplicationSettings = { param($c)
        @{
            LocalizedDisplayName     = $c.ApplicationName
            LocalizedDescription     = 'Installed by the SCCM Integration Tool.'
            Publisher                = 'Contoso'
            SoftwareVersion          = '1.0'
            InstallCommandLine       = 'Invoke-AppDeployToolkit.exe Install'
            UninstallCommandLine     = 'Invoke-AppDeployToolkit.exe Uninstall'
            RepairCommandLine        = ''
            ExecutionContext         = 'System'
            PostInstallBehavior      = 'BasedOnExitCode'
            RequireUserInteraction   = 'False'
            RequiresLogOn            = ''
            MaximumRuntimeMins       = '120'
            EstimatedRuntimeMins     = '3'
            ContentLocation          = '\\server\share\pkg'
            PersistContentInCache    = 'False'
            SlowNetworkDeploymentMode = 'Download'
        }
    }.GetNewClosure()

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

