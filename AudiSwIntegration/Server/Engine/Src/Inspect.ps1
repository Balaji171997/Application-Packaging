# ==============================================================================
#  Audi SCCM Integration Tool - reading and changing what is there
# ==============================================================================
#  Get-AudiSwPackageState  reads the site and reports what exists for one
#                          package against what the environment file asks for.
#                          Read-only. This is what the window's Modify tab draws
#                          its three lists from - in place, missing, not asked
#                          for - and the answer to "what happened to my package"
#                          without opening the console.
#
#  Invoke-AudiSwChange     applies EXACTLY the collections a packager ticked.
#                          Not a reconcile: the person looking at the site made
#                          the decision, and this carries it out.
#
#  Dot-sourced by AudiSwIntegration.ps1. ASCII only.
# ==============================================================================

Set-StrictMode -Version 2.0

# -------------------------------------------------------------- what is there
#
# Reads the site and reports what EXISTS for one package, against what the
# environment file says should exist. Read-only - it creates and changes nothing.
#
# This is what a Modify screen is built on. Rather than a packager editing an
# environment XML to add or retire a collection, the window shows three lists -
# what is there and wanted, what is there and no longer wanted, what is wanted
# and missing - and the packager ticks what to do about each. The job that comes
# out still goes through the drop folder like any other.
#
# It is also the answer to "what actually happened to my package?", which until
# now meant opening the console.

function Get-AudiSwPackageState {
    <#  What the site holds for this package right now.

        Returns:
          Application       does it exist
          Collections       Name, Exists, Wanted, HasDeployment
          Extra             collections named for this package that the
                            environment file does not ask for - somebody made
                            them by hand, or an old environment file did
          Missing           wanted, not there
          SecurityScopes    what is really attached
          Summary           one line a person can read  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Plan,
        $Provider,
        [switch]$DryRun
    )

    if (-not $Provider) { $Provider = if ($DryRun) { New-AudiSccmDryRunProvider } else { New-AudiSccmProvider } }

    $connection = Connect-AudiSccm -Plan $Plan -DryRun:$DryRun
    if (-not $connection.Ok) {
        return [pscustomobject]@{ Ok = $false; Message = $connection.Message
            Application = $false; Collections = @(); Extra = @(); Missing = @(); SecurityScopes = @()
            Settings = @(); SettingsNote = '' }
    }

    try {
        $exists = [bool](& $Provider.TestApplication @{ ApplicationName = $Plan.ApplicationName })

        $wanted = @($Plan.Collections | ForEach-Object { $_.Name })
        $onSite = @(& $Provider.GetPackageCollections @{ PackageName = $Plan.PackageName })

        $collections = @($Plan.Collections | ForEach-Object {
            $there = $onSite -contains $_.Name
            [pscustomobject]@{
                Name          = $_.Name
                Wanted        = $true
                Exists        = $there
                HasDeployment = $(if ($there) { [bool](& $Provider.TestDeployment @{ ApplicationName = $Plan.ApplicationName; CollectionName = $_.Name }) } else { $false })
                Action        = $_.DeploymentAction
            }
        })

        # named for this package but not asked for by the environment file
        $extra = @($onSite | Where-Object { $_ -notin $wanted } | ForEach-Object {
            [pscustomobject]@{
                Name          = $_
                Wanted        = $false
                Exists        = $true
                HasDeployment = [bool](& $Provider.TestDeployment @{ ApplicationName = $Plan.ApplicationName; CollectionName = $_ })
                Action        = ''
            }
        })

        $missing = @($collections | Where-Object { -not $_.Exists } | ForEach-Object { $_.Name })
        $scopes  = @(& $Provider.GetObjectSecurityScope @{ ApplicationName = $Plan.ApplicationName })

        # ---- the settings, as they are on the site right now ------------------
        #
        # Each one is joined to its entry in the catalogue, so a row carries the
        # current value AND the values SCCM would accept instead. That is what
        # lets the Modify tab offer alternatives rather than a blank box the
        # packager has to know the legal values for.
        $settings = @()
        $live     = @{}
        if ($exists) {
            $live = & $Provider.GetApplicationSettings @{ ApplicationName = $Plan.ApplicationName }
            if (-not $live) { $live = @{} }

            $settings = @(Get-AudiSettingCatalogue | ForEach-Object {
                $entry   = $_
                $known   = $live.ContainsKey($entry.Property)
                $current = $(if ($known) { [string]$live[$entry.Property] } else { $null })

                # For a Choice, say which option the current value corresponds
                # to - "System" on its own does not tell a packager much.
                $label = $current
                if ($entry.Editor -eq 'Choice') {
                    $match = @($entry.Options | Where-Object { $_.Value -eq $current })
                    if ($match.Count -gt 0) { $label = $match[0].Label }
                    elseif ($known)         { $label = "$current (not one of the usual values)" }
                }

                # A setting can only be changed if the catalogue allows it AND
                # it could be read in the first place. Offering to edit a value
                # we could not read means writing over something unseen.
                $editable = $entry.Editable -and $known

                [pscustomobject]@{
                    Key          = $entry.Key
                    Label        = $entry.Label
                    Scope        = $entry.Scope
                    Property     = $entry.Property
                    Editor       = $entry.Editor
                    Unit         = $entry.Unit
                    Hint         = $entry.Hint
                    Current      = $current
                    CurrentLabel = $label
                    NewValue     = $current      # what the window will send back
                    Readable     = $known
                    Editable     = $editable
                    LockedReason = $(if (-not $entry.Editable) { $entry.LockedReason }
                                     elseif (-not $known)     { 'This value could not be read from the site.' }
                                     else                     { '' })
                    Options      = $entry.Options
                }
            })
        }
        $settingsNote = $(if ($live.ContainsKey('_Error')) { $live['_Error'] } else { '' })

        $summary = if (-not $exists) {
            "No application named '$($Plan.ApplicationName)' exists in $($Plan.Environment)."
        } else {
            "Application present. {0} of {1} collections in place{2}{3}. Security scopes: {4}." -f `
                @($collections | Where-Object { $_.Exists }).Count, $collections.Count,
                $(if ($missing.Count) { ", $($missing.Count) missing" } else { '' }),
                $(if ($extra.Count)   { ", $($extra.Count) not asked for" } else { '' }),
                $(if ($scopes.Count)  { $scopes -join ', ' } else { 'NONE' })
        }

        return [pscustomobject]@{
            Ok = $true; Message = $summary
            Application = $exists; Collections = $collections; Extra = $extra
            Missing = $missing; SecurityScopes = $scopes
            Settings = $settings; SettingsNote = $settingsNote
        }
    }
    finally { if (-not $DryRun) { Restore-AudiFileSystemLocation } }
}

function Invoke-AudiSwChange {
    <#  Applies EXACTLY the changes a packager ticked in the window - nothing
        more.

        Invoke-AudiSwModification reconciles against the environment file: it
        works out for itself what to add and what to retire. That is right when
        the environment file is the authority, and wrong when a person is
        looking at the site and deciding. This takes the decision as given.

        Add     a collection the environment file asks for that is not there:
                created, deployed to, and filed into its folder.
        Remove  a collection that IS there: its deployment goes first, then the
                collection.

        SAFETY: a name that is not this package's own is refused outright. The
        list comes from a window, and a window can be wrong; a typo must not be
        able to delete somebody else's collection. Nothing here can touch the
        application itself either - that is what Remove is for, deliberately.

        Not rolled back. Each change is independent and already applied to a live
        site by the time a later one fails; undoing them would be a fresh set of
        changes, not an undo. It stops at the first failure and reports exactly
        how far it got.  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [string[]]$Add = @(),
        [string[]]$Remove = @(),
        # Settings to write, as objects carrying Key and To. Anything else on
        # them is ignored: the catalogue on THIS side decides which parameter is
        # called and what value is legal, never the window.
        [object[]]$SettingChanges = @(),
        $Provider,
        [switch]$DryRun,
        [switch]$AllowUnverifiedEnvironment,
        [scriptblock]$OnProgress
    )

    if (-not $Provider) { $Provider = if ($DryRun) { New-AudiSccmDryRunProvider } else { New-AudiSccmProvider } }
    $log     = New-AudiLogContext -Plan $Plan -Root $null -DryRun:$DryRun
    $results = New-Object System.Collections.Generic.List[object]
    $changed = New-Object System.Collections.Generic.List[string]

    $finish = {
        param([bool]$ok, [string]$message)
        $result = [pscustomobject]@{
            Ok = $ok; JobId = $Plan.JobId; Environment = $Plan.Environment; Package = $Plan.PackageName
            Executor = $Plan.Executor; DryRun = [bool]$DryRun; Message = $message
            Steps = $results.ToArray(); Changed = $changed.ToArray(); RolledBack = @()
            LogPath = $log.LogPath; Provider = $Provider
        }
        Write-AudiLog -Context $log -Level $(if ($ok) { 'Info' } else { 'Error' }) -Message $message
        $null = Save-AudiJobRecord -Context $log -Plan $Plan -Result $result
        return $result
    }

    if (-not $Plan.Verified -and -not $AllowUnverifiedEnvironment -and -not $DryRun) {
        return & $finish $false "Environment $($Plan.Environment) is marked unverified - its settings still need confirming by Audi."
    }

    # Every name must belong to this package. Collection names are built as
    # prefix + package name + suffix, so the package name has to appear in them.
    $suspect = @(@($Add) + @($Remove) | Where-Object { $_ -and ($_ -notlike "*$($Plan.PackageName)*") })
    if ($suspect.Count -gt 0) {
        return & $finish $false ("Refused: {0} do(es) not belong to '{1}'. This tool only ever touches collections named for the package being changed." -f ($suspect -join ', '), $Plan.PackageName)
    }

    # Adding is only allowed for collections the environment file actually asks
    # for - otherwise a window could invent a collection with no limiting
    # collection and no folder to put it in.
    $known = @{}
    foreach ($collection in $Plan.Collections) { $known[$collection.Name] = $collection }
    $unknown = @($Add | Where-Object { -not $known.ContainsKey($_) })
    if ($unknown.Count -gt 0) {
        return & $finish $false ("Refused: {0} is not a collection {1} defines. Add it to Config\Environments\{1}.xml first." -f ($unknown -join ', '), $Plan.Environment)
    }

    # Settings are resolved against the catalogue HERE, on the server, before
    # anything connects. The window sends a key and a value; what that key means,
    # which cmdlet parameter it becomes and whether it may be written at all are
    # decided on this side. A window that sent Publisher, or a parameter name of
    # its own invention, gets refused rather than obeyed.
    $plannedSettings = New-Object System.Collections.Generic.List[object]
    if (@($SettingChanges).Count -gt 0) {
        $catalogue = @{}
        foreach ($entry in Get-AudiSettingCatalogue) { $catalogue[$entry.Key] = $entry }

        foreach ($change in @($SettingChanges)) {
            $entry = $catalogue[$change.Key]
            if (-not $entry) {
                return & $finish $false "Refused: '$($change.Key)' is not a setting this tool manages."
            }
            if (-not $entry.Editable) {
                return & $finish $false "Refused: $($entry.Label) cannot be changed here. $($entry.LockedReason)"
            }
            if (-not $entry.WriteParameter) {
                return & $finish $false "Refused: $($entry.Label) can be read but not written."
            }

            # A Choice may only ever be one of its own options, and the value
            # that goes to SCCM is the option's WriteValue - the read and write
            # vocabularies differ for some settings.
            $value = [string]$change.To
            if ($entry.Editor -eq 'Choice') {
                $option = @($entry.Options | Where-Object { $_.Value -eq $value })
                if ($option.Count -eq 0) {
                    return & $finish $false ("Refused: '{0}' is not a value {1} accepts. Allowed: {2}." -f `
                        $value, $entry.Label, (@($entry.Options | ForEach-Object { $_.Label }) -join ', '))
                }
                $value = $option[0].WriteValue
            }
            elseif ($entry.Editor -eq 'Number') {
                $parsed = 0
                if (-not [int]::TryParse($value, [ref]$parsed) -or $parsed -le 0) {
                    return & $finish $false "Refused: $($entry.Label) must be a whole number of $($entry.Unit), not '$value'."
                }
                $value = [string]$parsed
            }

            $plannedSettings.Add([pscustomobject]@{
                Key = $entry.Key; Label = $entry.Label; Scope = $entry.Scope
                Parameter = $entry.WriteParameter; Value = $value; Shown = [string]$change.To
            }) | Out-Null
        }
    }

    $connection = Connect-AudiSccm -Plan $Plan -DryRun:$DryRun
    if (-not $connection.Ok) { return & $finish $false $connection.Message }
    Write-AudiLog -Context $log -Message $connection.Message

    try {
        if (-not (& $Provider.TestApplication @{ ApplicationName = $Plan.ApplicationName })) {
            return & $finish $false "No application named '$($Plan.ApplicationName)' exists in $($Plan.Environment). Use Integrate to create it."
        }

        # Settings first. They change what the application already is, which is
        # the safer half of the job; collections come after, so a rejected
        # setting stops the run before anything is created or deleted.
        foreach ($setting in $plannedSettings) {
            if ($OnProgress) { & $OnProgress "Set $($setting.Label)" }
            try {
                if ($setting.Scope -eq 'Application') {
                    & $Provider.SetApplicationSetting @{
                        ApplicationName = $Plan.ApplicationName
                        Parameter = $setting.Parameter; Value = $setting.Value }
                }
                else {
                    & $Provider.SetDeploymentTypeSetting @{
                        ApplicationName    = $Plan.ApplicationName
                        DeploymentTypeName = $Plan.DeploymentType
                        Parameter = $setting.Parameter; Value = $setting.Value }
                }
                $results.Add([pscustomobject]@{ Step = 'Setting'; Name = $setting.Label; Ok = $true
                    Message = "$($setting.Label) set to '$($setting.Shown)'." }) | Out-Null
                $changed.Add("$($setting.Label) -> $($setting.Shown)") | Out-Null
            }
            catch {
                $reason = Get-AudiErrorText -ErrorRecord $_ -Context "Setting $($setting.Label) failed."
                $results.Add([pscustomobject]@{ Step = 'Setting'; Name = $setting.Label; Ok = $false; Message = $reason }) | Out-Null
                return & $finish $false "$reason Stopped there - $($changed.Count) change(s) had already been made: $($changed -join '; ')."
            }
        }

        foreach ($name in @($Add)) {
            if ($OnProgress) { & $OnProgress "Add $name" }
            try {
                $collection = $known[$name]
                if (-not (& $Provider.TestCollectionName @{ Name = $name })) {
                    & $Provider.NewCollection @{ Name = $name; LimitingCollectionId = $collection.LimitingCollectionId; Comment = $collection.Comment }
                }
                if (-not (& $Provider.TestDeployment @{ ApplicationName = $Plan.ApplicationName; CollectionName = $name })) {
                    & $Provider.NewDeployment @{ ApplicationName = $Plan.ApplicationName; CollectionName = $name; DeploymentAction = $collection.DeploymentAction }
                }
                $object = & $Provider.GetCollectionObject @{ Name = $name }
                & $Provider.MoveObject @{ FolderPath = $collection.Folder; InputObject = $object; Label = $name
                                          SiteCode = $Plan.SiteCode; ObjectType = 'DeviceCollection' }
                $results.Add([pscustomobject]@{ Step = "Add"; Name = $name; Ok = $true; Message = "$name created, deployed and filed." }) | Out-Null
                $changed.Add("added $name") | Out-Null
            }
            catch {
                $reason = Get-AudiErrorText -ErrorRecord $_ -Context "Adding $name failed."
                $results.Add([pscustomobject]@{ Step = 'Add'; Name = $name; Ok = $false; Message = $reason }) | Out-Null
                return & $finish $false "$reason Stopped there - $($changed.Count) change(s) had already been made: $($changed -join '; ')."
            }
        }

        foreach ($name in @($Remove)) {
            if ($OnProgress) { & $OnProgress "Remove $name" }
            try {
                if (& $Provider.TestDeployment @{ ApplicationName = $Plan.ApplicationName; CollectionName = $name }) {
                    & $Provider.RemoveDeployment @{ ApplicationName = $Plan.ApplicationName; CollectionName = $name }
                }
                if (& $Provider.TestCollectionName @{ Name = $name }) {
                    & $Provider.RemoveCollection @{ Name = $name }
                    $results.Add([pscustomobject]@{ Step = 'Remove'; Name = $name; Ok = $true; Message = "$name and its deployment removed." }) | Out-Null
                    $changed.Add("removed $name") | Out-Null
                }
                else {
                    $results.Add([pscustomobject]@{ Step = 'Remove'; Name = $name; Ok = $true; Message = "$name was already gone." }) | Out-Null
                }
            }
            catch {
                $reason = Get-AudiErrorText -ErrorRecord $_ -Context "Removing $name failed."
                $results.Add([pscustomobject]@{ Step = 'Remove'; Name = $name; Ok = $false; Message = $reason }) | Out-Null
                return & $finish $false "$reason Stopped there - $($changed.Count) change(s) had already been made: $($changed -join '; ')."
            }
        }

        if ($changed.Count -eq 0) { return & $finish $true 'Nothing to do - the site already matches what was asked for.' }
        return & $finish $true "$($changed.Count) change(s) applied: $($changed -join '; ')."
    }
    finally { if (-not $DryRun) { Restore-AudiFileSystemLocation } }
}

