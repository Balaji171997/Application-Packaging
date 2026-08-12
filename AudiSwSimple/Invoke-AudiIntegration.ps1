<#
    THE ENGINE. Everything that touches SCCM, top to bottom, in the order it
    happens. Run on the Script Runner, as the service account.

        .\Invoke-AudiIntegration.ps1 -JobFile <job.json> -WhatIf     # says what it would do
        .\Invoke-AudiIntegration.ps1 -JobFile <job.json>             # does it

    Returns a result object: Ok, Message, Steps, RolledBack.

    If a step fails, everything already created is removed again, newest first,
    and the result says so plainly. A half-made application left on a site is
    worse than no application.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$JobFile,
    [string]$EnvironmentRoot = (Join-Path $PSScriptRoot 'Environments')
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$real = -not $WhatIfPreference     # $false = rehearsal, nothing is created

# ============================================================ the job and config
$job = Get-Content -LiteralPath $JobFile -Raw | ConvertFrom-Json
$pkg = $job.Package

$environmentFile = Join-Path $EnvironmentRoot "$($job.Environment).psd1"
if (-not (Test-Path -LiteralPath $environmentFile)) { throw "No environment file for '$($job.Environment)'." }
$config = Import-PowerShellDataFile -LiteralPath $environmentFile

$appName    = $pkg.Name
$dtName     = "$($pkg.Name)_INSTALLCOMPUTER"
$contentPath = Join-Path $config.ContentShare $pkg.Name

# what we make, so we can unmake it. Newest last.
$created = New-Object System.Collections.Generic.List[object]
$steps   = New-Object System.Collections.Generic.List[object]

function Add-Step { param([string]$Name, [bool]$Ok, [string]$Detail)
    $steps.Add([pscustomobject]@{ Step = $Name; Ok = $Ok; Detail = $Detail }) | Out-Null
    if ($Ok) { Write-Host ("  OK      {0,-22} {1}" -f $Name, $Detail) -ForegroundColor Green }
    else     { Write-Host ("  FAILED  {0,-22} {1}" -f $Name, $Detail) -ForegroundColor Red }
}

function Move-AudiObject { param([string]$Name, [string]$ObjectType, [string]$Folder, [string]$SiteCode)
    # The environment file holds the folder as the console shows it -
    # 'ICZ-Applications', 'II1-Site\II1-Software Management'. Move-CMObject wants
    # a PROVIDER path rooted at the object type:
    #     II1:\Application\ICZ-Applications
    #     II1:\DeviceCollection\II1-Site\II1-Software Management
    # A bare name binds to the parameter happily and then fails at the site.
    # Missing folder levels are created, as the old tool did.
    $path = "${SiteCode}:\$ObjectType"
    foreach ($segment in @($Folder -split '\\' | Where-Object { $_ })) {
        $parent = $path
        $path   = Join-Path $parent $segment
        if (-not (Test-Path -LiteralPath $path)) { New-CMFolder -Name $segment -ParentFolderPath $parent -ErrorAction Stop | Out-Null }
    }

    $object = if ($ObjectType -eq 'Application') { Get-CMApplication -Name $Name -Fast -ErrorAction Stop }
              else { Get-CMDeviceCollection -Name $Name -ErrorAction Stop }
    Move-CMObject -FolderPath $path -InputObject $object -ErrorAction Stop | Out-Null
}

function Get-ErrorText { param($ErrorRecord)
    # Some ConfigMgr cmdlets throw with NO message. Passing that on gives
    # "Cannot bind argument to parameter 'Message'" instead of the real problem.
    $text = ''
    if ($ErrorRecord) { try { $text = [string]$ErrorRecord.Exception.Message } catch { } }
    if ([string]::IsNullOrWhiteSpace($text)) {
        $type = try { $ErrorRecord.Exception.GetType().Name } catch { 'Exception' }
        $text = "$type was thrown with no message."
    }
    return $text
}

Write-Host ""
Write-Host "$($job.Action) $appName into $($config.SiteCode)$(if (-not $real) { '   [WHAT IF - nothing will be created]' })" -ForegroundColor Cyan
Write-Host "  job $($job.JobId)   rfc $($job.Rfc)" -ForegroundColor DarkGray
Write-Host ""

# ================================================================== 0. CHECKS
# Everything that can be known before anything is created. Each of these has
# already cost somebody an application half-made on a live site.

# SCCM hands the content path to distribution points to fetch from, so a local
# path is meaningless to it - and it is refused INSIDE Add-CMScriptDeploymentType,
# after the application exists. Catch it here instead.
if (-not $config.ContentShare.StartsWith('\\')) {
    throw "The content share for $($config.SiteCode) is '$($config.ContentShare)', a local path. SCCM only accepts a UNC path such as \\server\share. Fix ContentShare in $environmentFile."
}

# ================================================== 1. CONNECT TO THE SITE
$startLocation = Get-Location

if ($real) {
    if (-not (Get-Module ConfigurationManager)) {
        if (-not $env:SMS_ADMIN_UI_PATH) { throw 'The ConfigMgr console is not installed here, so its PowerShell module cannot be loaded.' }
        $module = Join-Path (Split-Path -Parent $env:SMS_ADMIN_UI_PATH) 'ConfigurationManager.psd1'

        # NOT -ErrorAction Stop. When the console build differs from the site's,
        # the module complains - "A new version of the console is available" -
        # but it loads perfectly well. -ErrorAction Stop turns that complaint
        # into a terminating error and the job fails having done nothing.
        Import-Module $module -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -ErrorVariable moduleWarning
        if (-not (Get-Module ConfigurationManager)) { throw "The ConfigMgr module could not be loaded. $moduleWarning" }
        if ($moduleWarning) { Write-Warning "$moduleWarning" }
    }

    if (-not (Get-PSDrive -Name $config.SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) {
        New-PSDrive -Name $config.SiteCode -PSProvider CMSite -Root $config.SiteServer -Scope Global `
                    -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null
    }
    if (-not (Get-PSDrive -Name $config.SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) {
        throw "Could not connect to $($config.SiteCode) on $($config.SiteServer). Check the name resolves and the account has rights on the site."
    }

    # Creating the drive is NOT enough. Every ConfigMgr cmdlet refuses until the
    # current location IS the drive:
    #   "This command cannot be run from the current drive."
    Set-Location "$($config.SiteCode):"
    Add-Step 'Connect' $true "$($config.SiteCode) on $($config.SiteServer)"
}
else { Add-Step 'Connect' $true "would connect to $($config.SiteCode) on $($config.SiteServer)" }

try {
    # ============================================== 2. CREATE THE APPLICATION
    if ($real) {
        if (Get-CMApplication -Name $appName -Fast -ErrorAction SilentlyContinue) {
            throw "An application named '$appName' already exists in $($config.SiteCode). Use Remove first, or Modify it."
        }
        # 'FileSystem::' because we are standing on the site drive, and a path
        # with no drive qualifier is resolved by the CURRENT provider. A local
        # path names a drive so it reaches the filesystem; a UNC share does not,
        # and a perfectly readable \\server\share comes back as "not found".
        if (-not (Test-Path -LiteralPath "FileSystem::$contentPath")) {
            throw "The package is not on the content share. Copy the package FOLDER to $contentPath - browsing it locally only fills in the job; SCCM fetches the content from the share."
        }

        New-CMApplication -Name $appName -Publisher $pkg.Publisher -SoftwareVersion $pkg.Version `
                          -LocalizedApplicationName $pkg.DisplayName `
                          -LocalizedApplicationDescription $pkg.DescriptionEn `
                          -AutoInstall $true -ErrorAction Stop | Out-Null
        $created.Add(@{ Kind = 'Application'; Name = $appName }) | Out-Null
    }
    Add-Step 'Application' $true $appName

    # ========================================== 3. CREATE THE DEPLOYMENT TYPE
    # TWO detection rules, both of which must be true:
    #   1. the branding key the package writes         HKLM\Software\VWG\CM\<key>  Revision = <revision>
    #   2. the product's own uninstall entry           from VWG_SoftIdent in the deployment script
    # Rule 2 is skipped when the package has no SoftIdent, or one in a shape we
    # do not recognise - a guessed rule would detect the wrong thing.
    if ($real) {
        $clauses = @(
            New-CMDetectionClauseRegistryKeyValue -Hive LocalMachine -KeyName $pkg.DetectionKey `
                -ValueName 'Revision' -PropertyType String -ExpectedValue $pkg.Revision `
                -ExpressionOperator IsEquals -Value -Is64Bit -ErrorAction Stop
        )

        # "HKLM:\SOFTWARE\...\INCA7.5.7 [DisplayVersion=7.5.7]"
        $soft = [regex]::Match([string]$pkg.SoftIdent, '^\s*HK[A-Za-z_]+:?\\(?<Key>[^\[]+?)\s*(?:\[\s*(?<Name>[^=\]]+?)\s*=\s*(?<Value>[^\]]*?)\s*\])?\s*$')
        if ($soft.Success -and $soft.Groups['Key'].Value -notmatch '\$') {
            $key = $soft.Groups['Key'].Value.TrimEnd('\')
            if ($soft.Groups['Name'].Success -and $soft.Groups['Name'].Value) {
                $clauses += New-CMDetectionClauseRegistryKeyValue -Hive LocalMachine -KeyName $key `
                                -ValueName $soft.Groups['Name'].Value -PropertyType String `
                                -ExpectedValue $soft.Groups['Value'].Value `
                                -ExpressionOperator IsEquals -Value -Is64Bit -ErrorAction Stop
            }
            else {
                $clauses += New-CMDetectionClauseRegistryKey -Hive LocalMachine -KeyName $key -Existence -Is64Bit -ErrorAction Stop
            }
        }
        elseif ($pkg.SoftIdent) {
            Write-Warning "SoftIdent '$($pkg.SoftIdent)' is not in a shape this script recognises, so only the branding key is used for detection."
        }

        Add-CMScriptDeploymentType -ApplicationName $appName -DeploymentTypeName $dtName `
            -ContentLocation $contentPath `
            -InstallCommand 'Invoke-AppDeployToolkit.exe Install' `
            -UninstallCommand 'Invoke-AppDeployToolkit.exe Uninstall' `
            -AddDetectionClause $clauses `
            -InstallationBehaviorType InstallForSystem `
            -LogonRequirementType WhetherOrNotUserLoggedOn `
            -UserInteractionMode Hidden `
            -MaximumRuntimeMins 120 -EstimatedRuntimeMins 5 `
            -SlowNetworkDeploymentMode Download `
            -ContentFallback -ErrorAction Stop | Out-Null

        # Windows 10 and 11. Windows 7 is out of support and no longer offered.
        $osCondition = Get-CMGlobalCondition -Name 'Operating System' | Select-Object -First 1
        $osRule = New-CMRequirementRuleOperatingSystemValue -GlobalCondition $osCondition -RuleOperator OneOf `
                      -PlatformString 'Windows/All_x64_Windows_10_and_higher_Clients', 'Windows/All_x64_Windows_11_and_higher_Clients' -ErrorAction Stop
        Set-CMScriptDeploymentType -ApplicationName $appName -DeploymentTypeName $dtName -AddRequirement $osRule -ErrorAction Stop | Out-Null
    }
    Add-Step 'DeploymentType' $true "$dtName, $(if ($pkg.SoftIdent) { '2 detection rules' } else { '1 detection rule' })"

    # ==================================================== 4. SET THE CATEGORY
    # -AddAppCategory wants a category OBJECT, not the name. Passing the string
    # gives "Cannot convert the "Development" value of type System.String to type
    # ...IResultObject". Older builds took a string, so that is the fallback.
    # The category is created if the site does not have it.
    if ($real) {
        $category = Get-CMCategory -Name 'Development' -CategoryType AppCategories -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $category) { $category = New-CMCategory -Name 'Development' -CategoryType AppCategories -ErrorAction Stop }
        try   { Set-CMApplication -Name $appName -AddAppCategory $category -ErrorAction Stop | Out-Null }
        catch { Set-CMApplication -Name $appName -AddAppCategory 'Development' -ErrorAction Stop | Out-Null }
    }
    Add-Step 'Category' $true 'Development'

    # ================================================ 5. DISTRIBUTE THE CONTENT
    if ($real) {
        Start-CMContentDistribution -ApplicationName $appName -DistributionPointGroupName $config.DistributionPointGroup -ErrorAction Stop | Out-Null
    }
    Add-Step 'Content' $true "sent to '$($config.DistributionPointGroup)'"

    # =============================== 6. COLLECTIONS, DEPLOYMENTS AND FOLDERS
    # One pass per collection: make it, deploy to it, file it. Doing all three
    # together means a collection can never end up with the wrong deployment -
    # the old tool paired them by list position and one manual removal shifted
    # every deployment after it.
    foreach ($c in $config.Collections) {
        $collectionName = "$($c.Prefix)$($pkg.Name)$($c.Suffix)"

        if ($real) {
            New-CMDeviceCollection -Name $collectionName -LimitingCollectionId $c.Limiting `
                -Comment "Created by the SCCM Integration Tool | job $($job.JobId) | RFC $($job.Rfc)" -ErrorAction Stop | Out-Null
            $created.Add(@{ Kind = 'Collection'; Name = $collectionName }) | Out-Null

            # The environment file says what a deployment is FOR in one word.
            # SCCM splits that across two parameters and they are NOT the same:
            #   -DeployAction   Install | Uninstall     what it does
            #   -DeployPurpose  Available | Required    whether a user chooses
            # 'Available' is not a valid ACTION - only Install or Uninstall are.
            switch ($c.Action) {
                'Uninstall' { $action = 'Uninstall'; $purpose = 'Required' }
                'Required'  { $action = 'Install';   $purpose = 'Required' }
                default     { $action = 'Install';   $purpose = 'Available' }
            }
            New-CMApplicationDeployment -Name $appName -CollectionName $collectionName `
                -DeployAction $action -DeployPurpose $purpose -ErrorAction Stop | Out-Null

            Move-AudiObject -Name $collectionName -ObjectType 'DeviceCollection' -Folder $c.Folder -SiteCode $config.SiteCode
        }
        Add-Step 'Collection' $true "$collectionName  ($($c.Action))"
    }

    # ============================================== 7. ADD THE SECURITY SCOPES
    if ($real) {
        # Current consoles want the scope OBJECT, the same as -AddAppCategory;
        # older ones took the id. Try the object, fall back to the id.
        $application = Get-CMApplication -Name $appName -Fast -ErrorAction Stop
        foreach ($scope in $config.SecurityScopes) {
            $scopeObject = Get-CMSecurityScope -Id $scope -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($scopeObject) {
                try   { Add-CMObjectSecurityScope -InputObject $application -Scope $scopeObject -ErrorAction Stop | Out-Null }
                catch { Add-CMObjectSecurityScope -InputObject $application -Id $scope -ErrorAction Stop | Out-Null }
            }
            else { Add-CMObjectSecurityScope -InputObject $application -Id $scope -ErrorAction Stop | Out-Null }
        }
    }
    Add-Step 'SecurityScopes' $true ($config.SecurityScopes -join ', ')

    # ========================================= 8. FILE THE APPLICATION AWAY
    if ($real) { Move-AudiObject -Name $appName -ObjectType 'Application' -Folder $config.ApplicationFolder -SiteCode $config.SiteCode }
    Add-Step 'Folder' $true "$($config.SiteCode):\Application\$($config.ApplicationFolder)"

    # ===================================================== 9. AD GROUP - TODO
    #
    # The tool being replaced also creates an Active Directory access group
    # through the ARS/SPML web service:
    #
    #     name         G-AUDI-AG-SW-<package name>
    #     description  Software-Filtergroups - <package name>
    #     OU           $config.ArsGroupOu
    #     endpoint     $config.ArsProviderUrl
    #
    # Deliberately NOT switched on yet. It is the one step that writes outside
    # SCCM, and it needs its own rights and its own testing. When it is time:
    #
    #     $ars = New-WebServiceProxy -Uri $config.ArsProviderUrl -UseDefaultCredential
    #     ... build the SPML addRequest for the group ...
    #     Add-Step 'AdGroup' $true "G-AUDI-AG-SW-$($pkg.Name)"
    #
    Add-Step 'AdGroup' $true 'SKIPPED - not built yet, see step 9 in this script'

    $result = [pscustomobject]@{
        Ok = $true; JobId = $job.JobId; Package = $pkg.Name; Environment = $config.SiteCode
        Message = "$($steps.Count) steps completed."
        Steps = $steps.ToArray(); RolledBack = @()
    }
}
catch {
    # ======================================================== IT WENT WRONG
    $reason = Get-ErrorText -ErrorRecord $_
    Add-Step 'FAILED' $false $reason

    # Undo what we made, newest first, so nothing half-built is left behind.
    $undone = New-Object System.Collections.Generic.List[string]
    if ($real -and $created.Count -gt 0) {
        Write-Host ""
        Write-Host "  Rolling back $($created.Count) object(s)..." -ForegroundColor Yellow
        for ($i = $created.Count - 1; $i -ge 0; $i--) {
            $item = $created[$i]
            try {
                switch ($item.Kind) {
                    'Collection'  { Remove-CMDeviceCollection -Name $item.Name -Force -ErrorAction Stop }
                    'Application' { Remove-CMApplication -Name $item.Name -Force -ErrorAction Stop }
                }
                $undone.Add("$($item.Kind) $($item.Name)") | Out-Null
                Write-Host "    removed $($item.Kind) $($item.Name)" -ForegroundColor Yellow
            }
            catch {
                $undone.Add("$($item.Kind) $($item.Name) COULD NOT BE REMOVED: $(Get-ErrorText -ErrorRecord $_)") | Out-Null
                Write-Host "    COULD NOT REMOVE $($item.Kind) $($item.Name)" -ForegroundColor Red
            }
        }
    }

    # Say what is left on the site. That is the first thing anyone needs to know.
    $stuck = @($undone | Where-Object { $_ -like '*COULD NOT BE REMOVED*' })
    $state = if ($undone.Count -eq 0) { ' Nothing had been created yet, so nothing was left on the site.' }
             elseif ($stuck.Count -gt 0) { " {0} object(s) were rolled back, but {1} could NOT be removed and are STILL ON THE SITE: {2}." -f ($undone.Count - $stuck.Count), $stuck.Count, ($stuck -join '; ') }
             else { " Everything it had created was rolled back, so nothing was left on the site: {0}." -f ($undone -join '; ') }

    $result = [pscustomobject]@{
        Ok = $false; JobId = $job.JobId; Package = $pkg.Name; Environment = $config.SiteCode
        Message = "$reason$state"
        Steps = $steps.ToArray(); RolledBack = $undone.ToArray()
    }
}
finally {
    # Step back off the site drive, onto WHERE WE CAME FROM. Set-Location changes
    # the process working directory: leave it on II1: and the next file read
    # fails, because the ConfigMgr provider does not support -Filter or -Recurse.
    Set-Location $startLocation
}

Write-Host ""
Write-Host $result.Message -ForegroundColor $(if ($result.Ok) { 'Green' } else { 'Red' })
Write-Host ""
return $result
