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
        [ValidateSet('Integrate', 'Modify', 'Remove')][string]$Action = 'Integrate',
        [string]$Rfc = '',
        [string]$NameEn = '', [string]$NameDe = '',
        [string]$DescriptionEn = '', [string]$DescriptionDe = '',
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
        Created       = $j.created
        DryRun        = [bool]::Parse($j.dryRun)
        PackageName   = $j.Package.name
        Rfc           = $j.Package.rfc
        NameEn        = $(if ($j.Localised) { $j.Localised.nameEn } else { '' })
        NameDe        = $(if ($j.Localised) { $j.Localised.nameDe } else { '' })
        DescriptionEn = $(if ($j.Localised) { $j.Localised.descriptionEn } else { '' })
        DescriptionDe = $(if ($j.Localised) { $j.Localised.descriptionDe } else { '' })
        OperatingSystems = $os
        Path          = $Path
    }
    return @{ Ok = $true; Errors = @(); Job = $job }
}

function Write-AudiSwJobResult {
    <#  Writes the result XML beside the finished job.  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Job,
        [Parameter(Mandatory = $true)][string]$Executor,
        [Parameter(Mandatory = $true)]$Result
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
    $root.SetAttribute('outcome', $(if ($Result.Ok) { 'Succeeded' } else { 'Failed' }))
    $null = $doc.AppendChild($root)

    $message = $doc.CreateElement('Message')
    $message.InnerText = [string]$Result.Message
    $null = $root.AppendChild($message)

    $steps = $doc.CreateElement('Steps')
    foreach ($s in @($Result.Steps)) {
        $step = $doc.CreateElement('Step')
        $step.SetAttribute('key', [string]$s.Step)
        $step.SetAttribute('ok', $(if ($s.Ok) { 'true' } else { 'false' }))
        $step.SetAttribute('message', [string]$s.Message)
        $null = $steps.AppendChild($step)
    }
    $null = $root.AppendChild($steps)

    $folder = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    $doc.Save($Path)
    return $Path
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
                        Path      = $candidate
                    }
                }
                catch { }   # still being written - try again on the next pass
            }
        }
        if ((Get-Date) -ge $deadline) {
            return @{ Ok = $false; Found = $false
                Message = "No result after $TimeoutMinutes minutes. The job is still queued in the drop folder, or the collector on the server is not running."
                Steps = @() }
        }
        if ($OnWait) { & $OnWait }
        Start-Sleep -Seconds $PollSeconds
    }
}
