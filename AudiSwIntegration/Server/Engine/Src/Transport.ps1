# ==============================================================================
#  Audi SCCM Integration Tool - job transport
# ==============================================================================
#  Flow 2 (drop folder): the window writes a job file, the server collects it,
#  the server writes a result file, the window reads it back.
#
#  THE IDENTITY RULE - NO PERSON REACHES THE SERVER
#  ------------------------------------------------
#  Audi's requirement: a real person's name must not appear anywhere on the
#  SCCM side. Not on an SCCM object, and not in the tool's own log or job
#  record on the server.
#
#  So the server never establishes who asked. The job file carries no
#  requester, nothing reads the file's NTFS owner, and no result or log line
#  names a person. Every record is keyed by JOB ID and RFC NUMBER.
#
#  The audit trail is not lost - it moves. The RFC number travels with the job
#  and is written onto every SCCM object; Audi's change system already knows
#  which person raised that RFC. That keeps the link to a person entirely on
#  the requesting side, which is what Audi asked for.
#
#  Consequence, stated plainly: the RFC is now the only way back to a person.
#  Read-AudiSwJobFile therefore refuses a job that carries no RFC, unless
#  Audit/@requireRfc in Defaults.xml says otherwise.
#
#  One residual trace: the job file in \New is written by the packager, so
#  Windows stamps THEIR name on it as the NTFS owner. Nothing reads it, but it
#  is metadata on a file in the secure zone. The collector therefore re-writes
#  the archive copy as the service account and deletes the original, so no
#  person-owned file is left behind on the server.
#
#  ASCII only.
# ==============================================================================

Set-StrictMode -Version 2.0

function Get-AudiDropFolderPath {
    <#  <dropFolder>\New | Working | Done | Failed  #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$DropFolder)
    return [pscustomobject]@{
        Root    = $DropFolder
        New     = (Join-Path $DropFolder 'New')
        Working = (Join-Path $DropFolder 'Working')
        Done    = (Join-Path $DropFolder 'Done')
        Failed  = (Join-Path $DropFolder 'Failed')
    }
}

function Initialize-AudiDropFolder {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$DropFolder)
    $paths = Get-AudiDropFolderPath -DropFolder $DropFolder
    foreach ($p in @($paths.New, $paths.Working, $paths.Done, $paths.Failed)) {
        if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    }
    return $paths
}

function New-AudiSwJobFile {
    <#  Builds the job XML. Written by the packager window.  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PackageName,
        [Parameter(Mandatory = $true)][string]$EnvironmentCode,
                # Inspect reads the site and reports; Change applies exactly the
        # collections a packager ticked in the Modify tab.
        [ValidateSet('Integrate', 'Modify', 'Remove', 'Inspect', 'Change')][string]$Action = 'Integrate',
        [string[]]$AddCollections = @(),
        [string[]]$RemoveCollections = @(),
        # Setting edits, as objects carrying Key/From/To. From is recorded for
        # the audit trail only - the server never trusts it, it re-reads the
        # site itself.
        [object[]]$SettingChanges = @(),
        [string]$Rfc = '',
        [string]$NameEn = '', [string]$NameDe = '',
        [string]$DescriptionEn = '', [string]$DescriptionDe = '',
        # What the packager saw and, where they corrected it, what they changed
        # it to. Sent so the server uses exactly what was on the screen rather
        # than deriving it again and possibly differing.
        [hashtable]$Detail = @{},
        [string[]]$OperatingSystems = @(),
        [switch]$DryRun,
        [string]$JobId
    )

    if ([string]::IsNullOrWhiteSpace($JobId)) { $JobId = [guid]::NewGuid().ToString() }

    $doc = New-Object System.Xml.XmlDocument
    $null = $doc.AppendChild($doc.CreateXmlDeclaration('1.0', 'utf-8', $null))
    $job = $doc.CreateElement('Job')
    $job.SetAttribute('schemaVersion', '1.0')
    $job.SetAttribute('jobId', $JobId)
    $job.SetAttribute('environment', $EnvironmentCode)
    $job.SetAttribute('action', $Action)
    $job.SetAttribute('created', (Get-Date).ToString('o'))
    $job.SetAttribute('dryRun', $(if ($DryRun) { 'true' } else { 'false' }))
    $null = $doc.AppendChild($job)

    $package = $doc.CreateElement('Package')
    $package.SetAttribute('name', $PackageName)
    $package.SetAttribute('rfc', $Rfc)
    $null = $job.AppendChild($package)

    $localised = $doc.CreateElement('Localised')
    $localised.SetAttribute('nameEn', $NameEn)
    $localised.SetAttribute('nameDe', $NameDe)
    $localised.SetAttribute('descriptionEn', $DescriptionEn)
    $localised.SetAttribute('descriptionDe', $DescriptionDe)
    $null = $job.AppendChild($localised)

    # The collections a packager ticked in the Modify tab. Written before Detail
    # to match the order the schema declares.
    if (@($AddCollections).Count -gt 0 -or @($RemoveCollections).Count -gt 0 -or @($SettingChanges).Count -gt 0) {
        $changesNode = $doc.CreateElement('Changes')
        foreach ($name in @($AddCollections))    { $e = $doc.CreateElement('Add');    $e.InnerText = $name; $null = $changesNode.AppendChild($e) }
        foreach ($name in @($RemoveCollections)) { $e = $doc.CreateElement('Remove'); $e.InnerText = $name; $null = $changesNode.AppendChild($e) }
        foreach ($change in @($SettingChanges)) {
            $e = $doc.CreateElement('Setting')
            $e.SetAttribute('key', [string]$change.Key)
            $e.SetAttribute('from', [string]$change.From)
            $e.SetAttribute('to',   [string]$change.To)
            $null = $changesNode.AppendChild($e)
        }
        $null = $job.AppendChild($changesNode)
    }

    $detailNode = $doc.CreateElement('Detail')
    foreach ($name in 'Publisher','Product','Version','Architecture','Revision','Language','BrandingKey','SoftIdent') {
        $value = if ($Detail.Contains($name)) { [string]$Detail[$name] } else { '' }
        $detailNode.SetAttribute($name.Substring(0,1).ToLowerInvariant() + $name.Substring(1), $value)
    }
    $null = $job.AppendChild($detailNode)

    $osList = $doc.CreateElement('OperatingSystems')
    foreach ($key in $OperatingSystems) {
        $os = $doc.CreateElement('OperatingSystem')
        $os.SetAttribute('key', $key)
        $null = $osList.AppendChild($os)
    }
    $null = $job.AppendChild($osList)

    return $doc
}

function Submit-AudiSwJob {
    <#  Writes the job into <dropFolder>\New and returns where it went.

        Written to a .tmp name first and then renamed, so the watcher can never
        pick up a half-written file.  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DropFolder,
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Job
    )

    $paths = Initialize-AudiDropFolder -DropFolder $DropFolder
    $jobId = $Job.Job.jobId
    $name  = "{0}_{1}.xml" -f $Job.Job.Package.name, $jobId
    $final = Join-Path $paths.New $name
    $temp  = "$final.tmp"

    $Job.Save($temp)
    Move-Item -LiteralPath $temp -Destination $final -Force

    return [pscustomobject]@{
        JobId      = $jobId
        Path       = $final
        ResultPath = (Join-Path $paths.Done ($name -replace '\.xml$', '.result.xml'))
        FailedPath = (Join-Path $paths.Failed ($name -replace '\.xml$', '.result.xml'))
    }
}

function Read-AudiSwJobFile {
    <#  Loads and validates a job file. Returns @{ Ok; Errors; Job }.

        Note what is NOT here: the file's owner is never read, and no requester
        is established. See the identity rule at the top of this file - the
        server is not permitted to know which person asked.  #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path, [string]$Root)

    $result = Test-AudiConfigFile -Path $Path -SchemaPath (Join-Path (Get-AudiConfigRoot -Root $Root) 'Environment.xsd')
    if (-not $result.Ok) { return @{ Ok = $false; Errors = $result.Errors; Job = $null } }

    # The RFC is the only route back to a person, so an empty one is a real
    # defect rather than a cosmetic omission.
    $audit = (Get-AudiDefaults -Root $Root).Audit
    if ($audit.RequireRfc -and [string]::IsNullOrWhiteSpace($result.Document.Job.Package.rfc)) {
        return @{ Ok = $false; Job = $null; Errors = @(
            'The job carries no RFC number. The RFC is the only record of who requested this change, because no personal name is kept on the SCCM side, so a job without one cannot be accepted.') }
    }

    $j  = $result.Document.Job
    $os = @($result.Document.SelectNodes('/Job/OperatingSystems/OperatingSystem') | ForEach-Object { $_.key })

    $job = [pscustomobject]@{
        JobId         = $j.jobId
        Environment   = $j.environment
        Action        = $j.action
        # the collections a packager ticked in the Modify tab
        AddCollections    = @($result.Document.SelectNodes('/Job/Changes/Add')    | ForEach-Object { $_.InnerText })
        RemoveCollections = @($result.Document.SelectNodes('/Job/Changes/Remove') | ForEach-Object { $_.InnerText })
        SettingChanges    = @($result.Document.SelectNodes('/Job/Changes/Setting') | ForEach-Object {
                                [pscustomobject]@{ Key = $_.key; From = $_.from; To = $_.to } })
        Created       = $j.created
        DryRun        = [bool]::Parse($j.dryRun)
        PackageName   = $j.Package.name
        Rfc           = $j.Package.rfc
        NameEn        = $(if ($j.Localised) { $j.Localised.nameEn } else { '' })
        NameDe        = $(if ($j.Localised) { $j.Localised.nameDe } else { '' })
        DescriptionEn = $(if ($j.Localised) { $j.Localised.descriptionEn } else { '' })
        DescriptionDe = $(if ($j.Localised) { $j.Localised.descriptionDe } else { '' })
        OperatingSystems = $os
        Detail        = $(
            $d = @{}
            if ($result.Document.Job.Detail) {
                foreach ($name in 'Publisher','Product','Version','Architecture','Revision','Language','BrandingKey','SoftIdent') {
                    $attr = $name.Substring(0,1).ToLowerInvariant() + $name.Substring(1)
                    $d[$name] = [string]$result.Document.Job.Detail.$attr
                }
            }
            $d
        )
        Path          = $Path
    }
    return @{ Ok = $true; Errors = @(); Job = $job }
}

function Test-AudiResultMember {
    <#  Does this result carry that member? A heartbeat is a plain object with
        only the few fields it needs, while a finished run is the engine's full
        result - and under StrictMode reading a member that is not there throws. #>
    [CmdletBinding()]
    param($Result, [string]$Name)
    if ($null -eq $Result) { return $false }
    if ($Result -is [hashtable]) { return $Result.ContainsKey($Name) }
    return [bool]$Result.PSObject.Properties[$Name]
}

function Write-AudiSwJobResult {
    <#  Writes the result XML beside the finished job.  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Job,
        [Parameter(Mandatory = $true)][string]$Executor,
        [Parameter(Mandatory = $true)]$Result,
        # 'Running' while the job is still being worked on - see
        # Write-AudiSwJobProgress. Left alone, the outcome follows Result.Ok.
        [ValidateSet('', 'Succeeded', 'Failed', 'Running')][string]$Outcome = '',
        # only meaningful while Running - lets the window size its progress bar
        [int]$StepCount = 0
    )

    $doc = New-Object System.Xml.XmlDocument
    $null = $doc.AppendChild($doc.CreateXmlDeclaration('1.0', 'utf-8', $null))
    $root = $doc.CreateElement('JobResult')
    $root.SetAttribute('schemaVersion', '1.0')
    $root.SetAttribute('jobId', $Job.JobId)
    $root.SetAttribute('environment', $Job.Environment)
    $root.SetAttribute('package', $Job.PackageName)
    $root.SetAttribute('rfc', [string]$Job.Rfc)   # the audit link, in place of a name
    $root.SetAttribute('executor', $Executor)
    $root.SetAttribute('completed', (Get-Date).ToString('o'))
    $root.SetAttribute('dryRun', $(if ($Result.DryRun) { 'true' } else { 'false' }))
    $root.SetAttribute('outcome', $(if ($Outcome) { $Outcome } elseif ($Result.Ok) { 'Succeeded' } else { 'Failed' }))
    if ($StepCount -gt 0) { $root.SetAttribute('stepCount', [string]$StepCount) }
    $null = $doc.AppendChild($root)

    $message = $doc.CreateElement('Message')
    $message.InnerText = [string]$Result.Message
    $null = $root.AppendChild($message)

    # What Inspect found on the site. This is what the Modify tab draws its
    # three lists from - in place, missing, not asked for.
    if ((Test-AudiResultMember -Result $Result -Name 'State') -and $Result.State) {
        $stateNode = $doc.CreateElement('State')
        $stateNode.SetAttribute('application', $(if ($Result.State.Application) { 'true' } else { 'false' }))
        foreach ($collection in @($Result.State.Collections) + @($Result.State.Extra)) {
            $e = $doc.CreateElement('Collection')
            $e.SetAttribute('name',          [string]$collection.Name)
            $e.SetAttribute('wanted',        $(if ($collection.Wanted) { 'true' } else { 'false' }))
            $e.SetAttribute('exists',        $(if ($collection.Exists) { 'true' } else { 'false' }))
            $e.SetAttribute('hasDeployment', $(if ($collection.HasDeployment) { 'true' } else { 'false' }))
            $null = $stateNode.AppendChild($e)
        }
        foreach ($scope in @($Result.State.SecurityScopes)) {
            $e = $doc.CreateElement('Scope'); $e.InnerText = [string]$scope; $null = $stateNode.AppendChild($e)
        }

        # The settings, and everything the window needs to draw an editor for
        # them: the current value, whether it may be changed, and the values
        # SCCM would accept instead.
        #
        # All of it travels. The window could look the labels and options up in
        # its own copy of Defaults.xml, but the client and the server are
        # different machines in flow 2 - a stale copy on one of them would offer
        # a packager choices the site will not accept. What is on screen is what
        # the server actually read.
        if ((Test-AudiResultMember -Result $Result.State -Name 'Settings')) {
            foreach ($setting in @($Result.State.Settings)) {
                $e = $doc.CreateElement('Setting')
                $e.SetAttribute('key',          [string]$setting.Key)
                $e.SetAttribute('label',        [string]$setting.Label)
                $e.SetAttribute('scope',        [string]$setting.Scope)
                $e.SetAttribute('editor',       [string]$setting.Editor)
                $e.SetAttribute('current',      [string]$setting.Current)
                $e.SetAttribute('currentLabel', [string]$setting.CurrentLabel)
                $e.SetAttribute('editable',     $(if ($setting.Editable) { 'true' } else { 'false' }))
                $e.SetAttribute('readable',     $(if ($setting.Readable) { 'true' } else { 'false' }))
                $e.SetAttribute('lockedReason', [string]$setting.LockedReason)
                $e.SetAttribute('unit',         [string]$setting.Unit)
                $e.SetAttribute('hint',         [string]$setting.Hint)
                foreach ($option in @($setting.Options)) {
                    $o = $doc.CreateElement('Option')
                    $o.SetAttribute('value', [string]$option.Value)
                    $o.InnerText = [string]$option.Label
                    $null = $e.AppendChild($o)
                }
                $null = $stateNode.AppendChild($e)
            }
        }
        $null = $root.AppendChild($stateNode)
    }

    # What a failed run undid. Without this the packager is told the run failed
    # and left to guess whether an application is sitting half-made on the site.
    $rolledBack = $doc.CreateElement('RolledBack')
    if (Test-AudiResultMember -Result $Result -Name 'RolledBack') {
        foreach ($item in @($Result.RolledBack)) {
            $entry = $doc.CreateElement('Item')
            $entry.InnerText = [string]$item
            $null = $rolledBack.AppendChild($entry)
        }
    }
    $null = $root.AppendChild($rolledBack)

    $steps = $doc.CreateElement('Steps')
    foreach ($s in @($Result.Steps)) {
        $step = $doc.CreateElement('Step')
        $step.SetAttribute('key', [string]$s.Step)
        $step.SetAttribute('ok', $(if ($s.Ok) { 'true' } else { 'false' }))
        $step.SetAttribute('message', [string]$s.Message)
        $null = $steps.AppendChild($step)
    }
    $null = $root.AppendChild($steps)

    # 'FileSystem::' because the heartbeat is written DURING a run, while the
    # current location is the site drive. A UNC drop folder - which is what
    # production uses - has no drive qualifier, so without this the ConfigMgr
    # provider tries to resolve it and the write fails. $doc.Save is .NET and
    # takes the plain path.
    $folder = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath "FileSystem::$folder")) { New-Item -ItemType Directory -Path "FileSystem::$folder" -Force | Out-Null }
    $doc.Save($Path)
    return $Path
}

function Write-AudiSwJobProgress {
    <#  A heartbeat the collector drops beside the job while it is still working.

        This is what lets the window feel connected to a server it never talks
        to. The collector writes one of these after every step; the window reads
        the folder and shows how far the job has got - live, and again after the
        window has been closed and reopened.

        Same shape as the finished result, with outcome="Running", so there is
        one schema, one parser and one code path in the window. It is replaced by
        the real result when the job ends.  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Job,
        [Parameter(Mandatory = $true)][string]$Executor,
        [Parameter(Mandatory = $true)][string]$CurrentStep,
        [int]$StepNumber,
        [int]$StepCount,
        $Completed,
        [switch]$DryRun
    )

    $text = if ($StepCount -gt 0) { "Working on the server - {0} ({1} of {2})" -f $CurrentStep, $StepNumber, $StepCount }
            else                  { "Working on the server - $CurrentStep" }

    $progress = [pscustomobject]@{ Ok = $false; DryRun = [bool]$DryRun; Message = $text; Steps = @($Completed) }

    # A half-written heartbeat must never be read as the truth, so it goes to a
    # temporary name and is renamed into place.
    $temp = "$Path.writing"
    try {
        $null = Write-AudiSwJobResult -Path $temp -Job $Job -Executor $Executor -Result $progress `
                                      -Outcome 'Running' -StepCount $StepCount
        Move-Item -LiteralPath "FileSystem::$temp" -Destination "FileSystem::$Path" -Force
    }
    catch {
        # progress is a convenience - it must never stop the job it reports on
        Write-Verbose "Could not write progress for job $($Job.JobId): $($_.Exception.Message)"
        if (Test-Path -LiteralPath "FileSystem::$temp") { Remove-Item -LiteralPath "FileSystem::$temp" -Force -ErrorAction SilentlyContinue }
    }
}

function Get-AudiSwJobHistory {
    <#  Every result the drop folder holds for one package, newest first.

        The window does not have to stay open waiting. The collector writes the
        result whether anyone is watching or not, so a packager can close the
        tool, come back later, type the package name and see what happened.

        Returns @{ Outcome; Completed; JobId; Rfc; Executor; DryRun; Message;
                   Steps; Path } per run.  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DropFolder,
        [Parameter(Mandatory = $true)][string]$PackageName,
        [int]$Newest = 20
    )

    $paths = Get-AudiDropFolderPath -DropFolder $DropFolder
    $runs  = New-Object System.Collections.Generic.List[object]

    # \Working first: a job being worked on right now matters more than one that
    # finished yesterday, and its heartbeat is what makes the window look live.
    foreach ($folder in @($paths.Working, $paths.Done, $paths.Failed)) {
        if (-not (Test-Path -LiteralPath $folder)) { continue }
        $files = @(Get-ChildItem -LiteralPath $folder -Filter "$PackageName*.result.xml" -File -ErrorAction SilentlyContinue)
        foreach ($file in $files) {
            try {
                $doc = New-Object System.Xml.XmlDocument
                $doc.Load($file.FullName)
                $r = $doc.JobResult
                $runs.Add([pscustomobject]@{
                    Outcome   = $r.outcome
                    Completed = $(try { [datetime]$r.completed } catch { $file.LastWriteTime })
                    JobId     = $r.jobId
                    Rfc       = $(if ($r.HasAttribute('rfc')) { $r.rfc } else { '' })
                    Executor  = $r.executor
                    DryRun    = [bool]::Parse($r.dryRun)
                    StepCount = $(if ($r.HasAttribute('stepCount')) { [int]$r.stepCount } else { 0 })
                    RolledBack = @($doc.SelectNodes('/JobResult/RolledBack/Item') | ForEach-Object { $_.InnerText })
                    Message   = $doc.SelectSingleNode('/JobResult/Message').InnerText
                    Steps     = @($doc.SelectNodes('/JobResult/Steps/Step') | ForEach-Object {
                                    [pscustomobject]@{ Step = $_.key; Ok = [bool]::Parse($_.ok); Message = $_.message } })
                    Path      = $file.FullName
                }) | Out-Null
            }
            catch { }   # a half-written or hand-edited result is skipped, not fatal
        }
    }

    return @($runs | Sort-Object Completed -Descending | Select-Object -First $Newest)
}

function Wait-AudiSwJobResult {
    <#  Polls for the result file. Used by the packager window after submitting.
        Returns @{ Ok; Found; Outcome; Message; Rfc; Executor; Steps }.  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Submission,
        [int]$TimeoutMinutes = 30,
        [int]$PollSeconds = 10,
        [scriptblock]$OnWait
    )

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ($true) {
        foreach ($candidate in @($Submission.ResultPath, $Submission.FailedPath)) {
            if (Test-Path -LiteralPath $candidate) {
                try {
                    $doc = New-Object System.Xml.XmlDocument
                    $doc.Load($candidate)
                    $r = $doc.JobResult
                    return @{
                        Ok        = ($r.outcome -eq 'Succeeded')
                        Found     = $true
                        Outcome   = $r.outcome
                        Message   = $doc.SelectSingleNode('/JobResult/Message').InnerText
                        Rfc       = $r.rfc
                        Executor  = $r.executor
                        Steps     = @($doc.SelectNodes('/JobResult/Steps/Step') | ForEach-Object {
                                        [pscustomobject]@{ Step = $_.key; Ok = [bool]::Parse($_.ok); Message = $_.message } })
                        RolledBack = @($doc.SelectNodes('/JobResult/RolledBack/Item') | ForEach-Object { $_.InnerText })
                        State      = @($doc.SelectNodes('/JobResult/State/Collection') | ForEach-Object {
                                        [pscustomobject]@{
                                            Name          = $_.name
                                            Wanted        = [bool]::Parse($_.wanted)
                                            Exists        = [bool]::Parse($_.exists)
                                            HasDeployment = [bool]::Parse($_.hasDeployment)
                                        } })
                        Scopes     = @($doc.SelectNodes('/JobResult/State/Scope') | ForEach-Object { $_.InnerText })
                        # NewValue starts at the current value, so a row nobody
                        # touches produces no change when Apply is pressed.
                        Settings   = @($doc.SelectNodes('/JobResult/State/Setting') | ForEach-Object {
                                        $node = $_
                                        [pscustomobject]@{
                                            Key          = $node.key
                                            Label        = $node.label
                                            Scope        = $node.scope
                                            Editor       = $node.editor
                                            Current      = $node.current
                                            CurrentLabel = $node.currentLabel
                                            NewValue     = $node.current
                                            Editable     = [bool]::Parse($node.editable)
                                            Readable     = [bool]::Parse($node.readable)
                                            LockedReason = $node.lockedReason
                                            Unit         = $node.unit
                                            Hint         = $node.hint
                                            Options      = @($node.SelectNodes('Option') | ForEach-Object {
                                                                [pscustomobject]@{ Value = $_.value; Label = $_.InnerText } })
                                        } })
                        Path      = $candidate
                    }
                }
                catch { }   # still being written - try again on the next pass
            }
        }
        if ((Get-Date) -ge $deadline) {
            return @{ Ok = $false; Found = $false
                # Name the exact folder. "Somewhere in the drop folder" is no help
                # when the usual cause is a collector watching a different one.
                Message = ("No result after {0} minutes. The job is still sitting in {1}. Either the collector is not running, or it is watching a different folder - it must be started with -DropFolder pointing at {2}." -f `
                           $TimeoutMinutes, $Submission.Path, (Split-Path -Parent (Split-Path -Parent $Submission.Path)))
                Steps = @() }
        }
        if ($OnWait) { & $OnWait }
        Start-Sleep -Seconds $PollSeconds
    }
}
