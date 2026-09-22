# ==============================================================================
#  Collects jobs from the drop folder and runs them.               FLOW 2
# ==============================================================================
#  Runs ON the server, as the shared account, started by a scheduled task every
#  few minutes. Nothing connects inward.
#
#    .\Watch-AudiSwDropFolder.ps1                                                   paths from Watcher-Settings.txt (normal)
#    .\Watch-AudiSwDropFolder.ps1 -DropFolder '\\server\SwIntegration-Inbox$\ICZ'   this environment only
#    .\Watch-AudiSwDropFolder.ps1 -DropFolder '\\server\SwIntegration-Inbox$'       every environment under the root
#    .\Watch-AudiSwDropFolder.ps1 -DropFolder '...' -DryRun -Verbose
#
#  Paths live in Watcher-Settings.txt beside this script (key = value); a
#  parameter given on the command line wins over the file. So the scheduled
#  task carries no path, and a path change is an edit to that file.
#
#  THE IDENTITY RULE - NO PERSON REACHES THIS SERVER
#  -------------------------------------------------
#  Audi's requirement: no real person's name may appear on the SCCM side. This
#  script therefore never establishes who asked. It does not read the job
#  file's NTFS owner, and it writes no personal name to the log, the job record
#  or the result. Everything is keyed by JOB ID and RFC NUMBER, and Audi's
#  change system holds the link from RFC to person.
#
#  The packager still owns the file they wrote into \New, because Windows
#  stamps that at creation. So the archive copy is RE-WRITTEN by this script,
#  running as the service account, and the original is deleted - leaving no
#  person-owned file behind in the secure zone.
#
#  Claiming: a job is MOVED to \Working before it runs, so two overlapping runs
#  of the task can never process the same job twice.
#
#  ASCII only.
# ==============================================================================

[CmdletBinding()]
param(
    [string]$DropFolder = '',
    [string]$EngineRoot = '',
    [int]$MaxJobsPerRun = 0,
    # a job in \Working with no sign of life for this long is closed as failed
    [int]$StaleJobMinutes = 0,
    [switch]$DryRun,
    [string]$SettingsFile = (Join-Path $PSScriptRoot 'Watcher-Settings.txt')
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ---- settings file: key = value, # comments; a command-line value wins
$settings = @{}
if (Test-Path -LiteralPath $SettingsFile) {
    foreach ($line in Get-Content -LiteralPath $SettingsFile) {
        if ($line -match '^\s*([A-Za-z]+)\s*=\s*(.*?)\s*$') { $settings[$matches[1]] = $matches[2] }
    }
}
if (-not $DropFolder)    { $DropFolder = [string]$settings['DropFolder'] }
if (-not $EngineRoot)    { $EngineRoot = [string]$settings['EngineRoot'] }
if (-not $EngineRoot)    { $EngineRoot = Join-Path $PSScriptRoot 'Engine' }
if ($MaxJobsPerRun -le 0) { $MaxJobsPerRun = 0; [int]::TryParse([string]$settings['MaxJobsPerRun'], [ref]$MaxJobsPerRun) | Out-Null }
if ($MaxJobsPerRun -le 0) { $MaxJobsPerRun = 10 }
if ($StaleJobMinutes -le 0) { $StaleJobMinutes = 0; [int]::TryParse([string]$settings['StaleJobMinutes'], [ref]$StaleJobMinutes) | Out-Null }
if ($StaleJobMinutes -le 0) { $StaleJobMinutes = 240 }   # the task's own 4-hour limit
# housekeeping - days; 0 keeps for ever. Only from the settings file.
$retention = @{ Done = 90; Failed = 180; Archive = 365; Sources = 14; LargeSources = 2 }
foreach ($k in @($retention.Keys)) {
    $v = 0
    if ([int]::TryParse([string]$settings["${k}RetentionDays"], [ref]$v) -and $v -ge 0) { $retention[$k] = $v }
}
# a package this big or bigger counts as large and gets the shorter Sources retention
$largeSourcesGB = 8.0
$v = 0.0
if ([double]::TryParse([string]$settings['LargeSourcesGB'], [ref]$v) -and $v -gt 0) { $largeSourcesGB = $v }
if (-not $DropFolder) {
    throw "No drop folder to watch. Set DropFolder in $SettingsFile (this environment's folder, e.g. \\share\SwIntegration`$\INA), or pass -DropFolder."
}

. (Join-Path $EngineRoot 'AudiSwIntegration.ps1')

# A previous pass in this session may have left the location on a CMSite drive,
# where Get-ChildItem -Filter throws. Come back to the filesystem first.
Restore-AudiFileSystemLocation

$executor = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

# THE LAYOUT the window writes, under one root:
#
#     <root>\ICZ\New\INA_ETAS_INCA_x64_...\INA_ETAS_..._<jobid>.xml
#            \Working  \Done  \Failed
#     <root>\INA\New\...
#
# A folder for an environment this server has no config file for is left
# alone rather than guessed at. Which folder -DropFolder may name is below.
$configuredCodes = @(Get-AudiEnvironmentCode)

$queueNames = @('New', 'Working', 'Done', 'Failed', 'Sources')
$leaf = Split-Path -Leaf $DropFolder.TrimEnd('\')
$onlyCode = $null

# THE ENVIRONMENT FOLDER IS NOT THERE YET - THAT IS NORMAL.
#
# The window creates <root>\<ENV> the first time somebody submits a job for
# that environment. Each server's task is pointed at its own <root>\<ENV> and
# runs every few minutes from the day it is installed, so on a fresh share the
# folder simply does not exist for a while. That is "nothing to collect", not
# an error: as long as the ROOT above it can be opened, wait for it.
if (-not (Test-Path -LiteralPath $DropFolder) -and ($configuredCodes -contains $leaf)) {
    $parent = Split-Path -Parent $DropFolder.TrimEnd('\')
    if ($parent -and (Test-Path -LiteralPath $parent)) {
        Write-Verbose "Nothing to collect. $leaf's folder has not been created under $parent yet - the window creates it with the first job."
        return
    }
}

# CAN THIS SESSION OPEN THE FOLDER?
#
# "It is there, I can see it in Explorer" is not the same thing. Explorer runs
# as the signed-in user, unelevated, with that user's network logon; this
# script may be running elevated, as the service account, or on a server that
# cannot reach the share's domain at all - and each of those fails differently.
# So when the folder cannot be opened, say WHICH failure it was and as WHOM,
# rather than a bare "not found".
if (-not (Test-Path -LiteralPath $DropFolder) -and $DropFolder -like '\\*') {
    # A stale session to the same server under another account (Windows error
    # 1219, "multiple connections") is the usual reason a share that opens in
    # Explorer does not open here. Drop every connection to that server and
    # look again; run by a person at a console, ask for a sign-in (3 tries).
    $shareRoot = $(if ($DropFolder -match '^(\\\\[^\\]+\\[^\\]+)') { $matches[1] } else { '' })
    $server = $(if ($shareRoot) { ($shareRoot -split '\\')[2] } else { '' })
    if ($server) {
        foreach ($line in @(net use 2>$null)) { if ($line -match '(\\\\' + [regex]::Escape($server) + '\\\S+)') { $null = net use $matches[1] /delete /y 2>$null } }
    }
    $interactive = [Environment]::UserInteractive -and -not (@([Environment]::GetCommandLineArgs()) -match '^-NonInteractive$').Count
    if (-not (Test-Path -LiteralPath $DropFolder) -and $shareRoot -and $interactive) {
        for ($attempt = 1; $attempt -le 3 -and -not (Test-Path -LiteralPath $DropFolder); $attempt++) {
            $cred = $null; try { $cred = Get-Credential -Message "Sign in to $shareRoot for the drop folder (attempt $attempt of 3)" } catch {}
            if (-not $cred) { break }
            try { $null = New-PSDrive -Name ('AudiDrop' + $attempt) -PSProvider FileSystem -Root $shareRoot -Credential $cred -Scope Global -ErrorAction Stop }
            catch { Write-Warning "Sign-in to $shareRoot as $($cred.UserName) failed: $($_.Exception.Message)" }
        }
    }
}
if (-not (Test-Path -LiteralPath $DropFolder)) {
    $me        = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $elevated  = (New-Object System.Security.Principal.WindowsPrincipal($me)).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    $reason    = 'the path does not exist'
    try { $null = [System.IO.Directory]::GetDirectories($DropFolder); $reason = 'Test-Path said no but the folder opened - the current location is probably not a filesystem drive' }
    catch [System.UnauthorizedAccessException] { $reason = 'ACCESS DENIED - the account running this has no rights on the share or the folder' }
    catch [System.IO.DirectoryNotFoundException] { $reason = "the path does not exist - " + $_.Exception.Message.Trim().TrimEnd('.') }
    catch [System.IO.IOException] { $reason = "the network path could not be opened - " + $_.Exception.Message.Trim().TrimEnd('.') }
    catch { $reason = $_.Exception.Message.Trim() }

    $hints = @()
    if ($DropFolder -like '\\*') {
        if ($elevated) { $hints += 'This window is ELEVATED (Run as administrator). An elevated session does not share the network logon of the desktop, so a share Explorer can open is often unreachable here. Try a normal PowerShell window, or map nothing and use the UNC path from an unelevated session.' }
        $hints += "The account is $($me.Name). A share in another domain needs that account to be known there; the scheduled task's service account must be granted rights on the share itself, not just on the folder."
        $hints += 'Try in THIS window:  Get-ChildItem -LiteralPath ''' + $DropFolder + '''  - the error it gives is the real one.'
    }
    throw ("The drop folder '{0}' cannot be opened: {1}.`r`n{2}" -f $DropFolder, $reason, ($hints -join "`r`n"))
}
$presentCodes = @(Get-ChildItem -LiteralPath $DropFolder -Directory -ErrorAction SilentlyContinue |
                  ForEach-Object { $_.Name })

# TWO WAYS TO POINT THE COLLECTOR, BOTH FIRST-CLASS:
#
#   -DropFolder <root>        serves every environment folder under the root
#   -DropFolder <root>\<ENV>  serves THAT environment only
#
# The second is the normal production shape: ICZ, INA and PCZ are separate
# servers, and each one's scheduled task is pointed at its own folder, so a
# server can never pick up another environment's jobs. The window always
# writes <root>\<ENV>\New\<package>\..., so the layout is the same either way.
#
# An environment folder is recognised by its name (a configured environment
# code) and by holding the queues (New/Working/Done/Failed) rather than
# environment folders. That is what stops <root> being mistaken for an
# environment when a site happens to be called the same as the share.
if (($configuredCodes -contains $leaf) -and
    (@($presentCodes | Where-Object { $configuredCodes -contains $_ }).Count -eq 0) -and
    (@($presentCodes | Where-Object { $queueNames -contains $_ }).Count -gt 0)) {
    $onlyCode   = $leaf
    $DropFolder = Split-Path -Parent $DropFolder.TrimEnd('\')
    Write-Verbose "Serving $leaf only - -DropFolder is that environment's folder under $DropFolder."
    $presentCodes = @($leaf)
}
elseif (($configuredCodes -contains $leaf) -and ($presentCodes.Count -eq 0)) {
    # Named like an environment and still empty: the window has not written a
    # job for it yet. Still that environment's folder, still served. (A folder
    # named like an environment that already holds environment folders is a
    # root, and is served as one.)
    $onlyCode   = $leaf
    $DropFolder = Split-Path -Parent $DropFolder.TrimEnd('\')
    Write-Verbose "Serving $leaf only - its folder is empty so far."
    $presentCodes = @($leaf)
}

$codes = @($configuredCodes | Where-Object { $_ }) + @($presentCodes | Where-Object { $configuredCodes -contains $_ })
$codes = @($codes | Sort-Object -Unique)
if ($onlyCode) { $codes = @($onlyCode) }

# THE PACKAGER IS NEVER BLIND: every pass leaves a one-line status file in
# each environment folder it serves - when, on which server, as whom, how
# many jobs were waiting - and the middle server carries it back, so the
# window can say "watcher alive, last pass 10:41" or "no pass since 09:10".
function Write-AudiWatcherStatus { param([string]$Code, [string]$Message)
    try {
        $envRoot = (Get-AudiDropFolderPath -DropFolder $DropFolder -EnvironmentCode $Code).Root
        if (-not (Test-Path -LiteralPath $envRoot)) { return }
        $line = "{0}|{1}|OK|{2}" -f (Get-Date).ToString('o'), $env:COMPUTERNAME, ($Message -replace '[\r\n|]+', ' ')
        $tmp = Join-Path $envRoot '~watcher-status.tmp'
        [IO.File]::WriteAllText($tmp, $line, (New-Object Text.UTF8Encoding $false))
        Move-Item -LiteralPath $tmp -Destination (Join-Path $envRoot 'watcher-status.txt') -Force
    } catch {}
}

$unknown = @($presentCodes | Where-Object { $configuredCodes -notcontains $_ -and $queueNames -notcontains $_ })
foreach ($u in $unknown) {
    Write-Verbose "Ignoring '$u' - not an environment this server has a config file for."
}
$queueAtRoot = @($presentCodes | Where-Object { $queueNames -contains $_ })
if ($queueAtRoot.Count -gt 0 -and -not $onlyCode) {
    Write-Warning ("'$DropFolder' holds $($queueAtRoot -join ', ') directly. Jobs are collected from <root>\<ENV>\New, " +
                   "never from <root>\New - a folder at this level is not looked at. The window writes " +
                   "<root>\<ENV>\New itself when DropFolder in Packager\Settings.txt names the root.")
}

# HOUSEKEEPING - the drop folder does not grow for ever.
#
# The permanent record of a job is the server log under ProgramData; what is
# in Done\ and Failed\ exists so the window can show history and so the middle server
# can carry results back. After DoneRetentionDays a finished job (its job file
# and its result) moves to Archive\<yyyy-MM>\<package>\; Failed\ the same after
# FailedRetentionDays; Archive months older than ArchiveRetentionDays go. A
# package's Sources\ with no job pending for it - a failed job nobody ran
# again - goes after SourcesRetentionDays; the next Integrate copies it afresh.
# Everything here is by literal path and only inside this drop folder.
foreach ($code in $codes) {
    $envPaths = Get-AudiDropFolderPath -DropFolder $DropFolder -EnvironmentCode $code
    if (-not (Test-Path -LiteralPath $envPaths.Root)) { continue }
    $archiveRoot = Join-Path $envPaths.Root 'Archive'
    foreach ($pair in @(@{ Folder = $envPaths.Done; Days = $retention.Done }, @{ Folder = $envPaths.Failed; Days = $retention.Failed })) {
        if ($pair.Days -le 0 -or -not (Test-Path -LiteralPath $pair.Folder)) { continue }
        $cutoff = (Get-Date).AddDays(-$pair.Days)
        foreach ($old in @(Get-ChildItem -LiteralPath $pair.Folder -Filter '*.result.xml' -File -Recurse -ErrorAction SilentlyContinue |
                           Where-Object { $_.LastWriteTime -lt $cutoff })) {
            try {
                $pkgFolder = Split-Path -Leaf $old.DirectoryName
                $month     = $old.LastWriteTime.ToString('yyyy-MM')
                $dest      = Join-Path (Join-Path $archiveRoot $month) $(if ($pkgFolder -in @('Done', 'Failed')) { '' } else { $pkgFolder })
                if (-not (Test-Path -LiteralPath $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
                $jobFile = Join-Path $old.DirectoryName ($old.Name -replace '\.result\.xml$', '.xml')
                Move-Item -LiteralPath $old.FullName -Destination (Join-Path $dest $old.Name) -Force
                if (Test-Path -LiteralPath $jobFile) { Move-Item -LiteralPath $jobFile -Destination (Join-Path $dest (Split-Path -Leaf $jobFile)) -Force }
                Remove-AudiEmptyPackageFolder -Path $old.DirectoryName
                Write-Verbose "$code : archived $($old.Name) to Archive\$month."
            }
            catch { Write-Warning "$code : could not archive $($old.Name): $($_.Exception.Message)" }
        }
    }
    if ($retention.Archive -gt 0 -and (Test-Path -LiteralPath $archiveRoot)) {
        $cutoffMonth = (Get-Date).AddDays(-$retention.Archive).ToString('yyyy-MM')
        foreach ($month in @(Get-ChildItem -LiteralPath $archiveRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d{4}-\d{2}$' -and $_.Name -lt $cutoffMonth })) {
            try { Remove-Item -LiteralPath $month.FullName -Recurse -Force; Write-Verbose "$code : Archive\$($month.Name) deleted after $($retention.Archive) days." }
            catch { Write-Warning "$code : could not delete Archive\$($month.Name): $($_.Exception.Message)" }
        }
    }
    if ($retention.Sources -gt 0 -and (Test-Path -LiteralPath $envPaths.Sources)) {
        foreach ($src in @(Get-ChildItem -LiteralPath $envPaths.Sources -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike '~*' })) {
            # a package this size is not kept around "in case": a big one waits
            # LargeSourcesRetentionDays, a small one SourcesRetentionDays
            $newest = $src.LastWriteTime; $bytes = 0
            foreach ($f in @(Get-ChildItem -LiteralPath $src.FullName -File -Recurse -Force -ErrorAction SilentlyContinue)) {
                if ($f.LastWriteTime -gt $newest) { $newest = $f.LastWriteTime }
                $bytes += $f.Length
            }
            $isLarge = ($bytes -ge $largeSourcesGB * 1GB)
            $days    = $(if ($isLarge) { $retention.LargeSources } else { $retention.Sources })
            if ($days -le 0 -or $newest -ge (Get-Date).AddDays(-$days)) { continue }
            if (@(Get-AudiSwPendingJob -DropFolder $DropFolder -EnvironmentCode $code -PackageName $src.Name).Count -gt 0) { continue }
            try {
                Remove-Item -LiteralPath $src.FullName -Recurse -Force
                Write-Warning ("$code : Sources\$($src.Name) deleted ({0:N1} GB{1}) - no job for it for $days days. The next Integrate copies it afresh." -f ($bytes / 1GB), $(if ($isLarge) { ', large' } else { '' }))
            }
            catch { Write-Warning "$code : could not delete Sources\$($src.Name): $($_.Exception.Message)" }
        }
    }
}

# A JOB THE SERVER DIED ON.
#
# A reboot, a killed task or the task's own time limit can stop a pass in the
# middle of a job. The job then sits in \Working with a heartbeat that never
# moves: the window shows it "running" for ever and, one job per package, it
# blocks every later job for that package. So a job whose heartbeat (or file)
# has not moved for StaleJobMinutes is closed here as FAILED, with what the
# heartbeat last reported, and filed back so the packager sees it and the
# package is free again. It is not re-run: what it created may be half there,
# and that needs a person to look before anything runs on top of it.
foreach ($code in $codes) {
    $envPaths = Get-AudiDropFolderPath -DropFolder $DropFolder -EnvironmentCode $code
    if (-not (Test-Path -LiteralPath $envPaths.Working)) { continue }
    foreach ($stuck in @(Get-ChildItem -LiteralPath $envPaths.Working -Filter '*.xml' -File -Recurse -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -notlike '*.result.xml' -and $_.Name -notlike '~*' })) {
        $beat = Join-Path $stuck.DirectoryName ($stuck.Name -replace '\.xml$', '.result.xml')
        $lastSign = $stuck.LastWriteTimeUtc
        if (Test-Path -LiteralPath $beat) { $lastSign = (Get-Item -LiteralPath $beat).LastWriteTimeUtc }
        if ($lastSign -gt (Get-Date).ToUniversalTime().AddMinutes(-$StaleJobMinutes)) { continue }

        $stuckPkg = Split-Path -Leaf $stuck.DirectoryName
        if ($stuckPkg -eq 'Working') { $stuckPkg = '' }
        $stuckPaths = Get-AudiDropFolderPath -DropFolder $DropFolder -EnvironmentCode $code -PackageName $stuckPkg
        $lastStep = 'no step was reported'
        $doneSteps = @()
        try {
            $hb = New-Object System.Xml.XmlDocument; $hb.Load($beat)
            $lastStep = [string]$hb.SelectSingleNode('/JobResult/Message').InnerText
            $doneSteps = @($hb.SelectNodes('/JobResult/Steps/Step') | ForEach-Object {
                [pscustomobject]@{ Step = $_.GetAttribute('key'); Ok = ($_.GetAttribute('ok') -eq 'true'); Message = $_.GetAttribute('message') } })
        } catch { }
        $stuckJob = $null
        try { $r = Read-AudiSwJobFile -Path $stuck.FullName; if ($r.Ok) { $stuckJob = $r.Job } } catch { }
        if (-not $stuckJob) { $stuckJob = [pscustomobject]@{ JobId = $stuck.BaseName; Environment = $code; PackageName = $stuckPkg; Rfc = ''; Action = ''; DryRun = $true } }

        # NOTHING ON THE SITE IS TOUCHED WITHOUT A PERSON SAYING SO.
        #
        # Audi's rule: an automatic action is fine as long as it stays inside
        # the drop folder; anything that writes to or deletes from SCCM needs a
        # confirmation. Closing the job is a drop-folder action, so it happens
        # here. What to do about the site is offered on the Jobs page instead:
        #
        #   Run again  - the same job, submitted afresh after confirmation.
        #                Modify, Change and Remove pick up where they stopped:
        #                a step already done reports "already there / already
        #                gone" and the rest is completed. An Integrate that
        #                stopped before its application existed runs clean.
        #   Clean up   - for an Integrate that got as far as creating the
        #                application: the Remove page, package name typed back,
        #                takes off exactly this package's own objects. Then
        #                Integrate again.
        $stuckWhen = $lastSign.ToLocalTime().ToString('dd.MM.yyyy HH:mm')
        $madeApplication = @($doneSteps | Where-Object { $_.Step -eq 'Application' -and $_.Ok }).Count -gt 0
        $advice = switch ($stuckJob.Action) {
            'Integrate' {
                if ($madeApplication) { " The application and what came after it are still on the site. On the Jobs page choose Clean up (removes exactly this package's objects, after you confirm), then Integrate again." }
                else                  { " It stopped before the application was created, so nothing of this job is on the site. Choose Run again on the Jobs page." }
            }
            'Remove' { " Choose Run again on the Jobs page - what is already gone is skipped and the rest is removed." }
            'Modify' { " Choose Run again on the Jobs page - what was already done is skipped and the rest is applied." }
            'Change' { " Choose Run again on the Jobs page - machines and collections already handled are skipped and the rest is applied." }
            default  { " Check the site, then submit again." }
        }
        if ($stuckJob.DryRun) { $advice = " It was a dry run, so nothing is on the site. Choose Run again on the Jobs page." }

        $stuckResult = [pscustomobject]@{ Ok = $false; DryRun = [bool]$stuckJob.DryRun; Steps = @($doneSteps)
            Message = ("The server stopped while this job was running - nothing has been reported since {0} (last: {1}). Nothing on the site has been touched since.{2}" -f $stuckWhen, $lastStep, $advice) }
        $stuckResultPath = Join-Path $stuckPaths.Failed ($stuck.Name -replace '\.xml$', '.result.xml')
        try {
            New-AudiJobFolder -Path $stuckResultPath
            $null = Write-AudiSwJobResult -Path $stuckResultPath -Job $stuckJob -Executor $executor -Result $stuckResult
            [System.IO.File]::WriteAllBytes((Join-Path $stuckPaths.Failed $stuck.Name), [System.IO.File]::ReadAllBytes($stuck.FullName))
            Remove-Item -LiteralPath $stuck.FullName -Force
            if (Test-Path -LiteralPath $beat) { Remove-Item -LiteralPath $beat -Force -ErrorAction SilentlyContinue }
            Remove-AudiEmptyPackageFolder -Path $stuck.DirectoryName
            Write-Warning "$($stuck.Name): closed as FAILED - no progress for more than $StaleJobMinutes minutes. The site may hold a half-finished package."
        }
        catch { Write-Warning "Could not close the stuck job $($stuck.Name): $($_.Exception.Message)" }
    }
}

# Collect across all of them, oldest first, so a busy environment cannot starve
# a quiet one of its turn.
$queue = New-Object System.Collections.Generic.List[object]
foreach ($code in $codes) {
    $envPaths = Get-AudiDropFolderPath -DropFolder $DropFolder -EnvironmentCode $code
    if (-not (Test-Path -LiteralPath $envPaths.New)) { continue }
    foreach ($f in @(Get-ChildItem -LiteralPath $envPaths.New -Filter '*.xml' -File -Recurse -ErrorAction SilentlyContinue)) {
        $queue.Add([pscustomobject]@{ File = $f; Code = $code }) | Out-Null
    }
}

$jobs = @($queue | Sort-Object { $_.File.CreationTimeUtc } | Select-Object -First $MaxJobsPerRun)
if ($jobs.Count -eq 0) {
    # Say WHERE nothing was found. "Nothing to collect" on its own gives a
    # person with a job sitting in the wrong folder no way to see that.
    $looked = @($codes | ForEach-Object { (Get-AudiDropFolderPath -DropFolder $DropFolder -EnvironmentCode $_).New })
    Write-Verbose ("Nothing to collect. Looked in: {0}" -f ($looked -join ' ; '))
    foreach ($code in $codes) { Write-AudiWatcherStatus -Code $code -Message "nothing waiting, as $executor" }
    return
}
Write-Verbose "Collecting $($jobs.Count) job(s) across $($codes.Count) environment(s) as $executor."
foreach ($code in $codes) { Write-AudiWatcherStatus -Code $code -Message ("{0} job(s) waiting, collecting as {1}" -f @($queue | Where-Object { $_.Code -eq $code }).Count, $executor) }

# Which queued jobs are duplicates of an older one for the same package - worked
# out over the WHOLE queue before anything runs, because by the time the newer
# one's turn comes the older one has finished and would no longer be "pending".
$olderInQueue = @{}
$firstForPackage = @{}
foreach ($entry in @($queue | Sort-Object { $_.File.CreationTimeUtc })) {
    $key = "{0}|{1}" -f $entry.Code, (Split-Path -Leaf (Split-Path -Parent $entry.File.FullName))
    if ($firstForPackage.ContainsKey($key)) {
        $first = $firstForPackage[$key]
        $firstId = ''; $firstAction = ''
        try { $d = New-Object System.Xml.XmlDocument; $d.Load($first.File.FullName); $firstId = $d.DocumentElement.GetAttribute('jobId'); $firstAction = $d.DocumentElement.GetAttribute('action') } catch { $firstId = $first.File.BaseName }
        $olderInQueue[$entry.File.FullName] = [pscustomobject]@{ JobId = $firstId; Action = $firstAction; State = 'Queued'; Submitted = $first.File.CreationTime; Path = $first.File.FullName }
    }
    else { $firstForPackage[$key] = $entry }
}

foreach ($entry in $jobs) {
    $file     = $entry.File
    $expected = $entry.Code

    # The package folder the job was found in, so its result lands beside it.
    $package = Split-Path -Leaf (Split-Path -Parent $file.FullName)
    if ($package -eq 'New') { $package = '' }   # older flat layout

    $paths = Initialize-AudiDropFolder -DropFolder $DropFolder -EnvironmentCode $expected -PackageName $package

    # ONE JOB PER PACKAGE AT A TIME.
    #
    # If another job for this package is already being run, or an OLDER one is
    # still waiting, this one is a duplicate - two people integrating the same
    # package minutes apart - and running it after the first would only end in
    # "already exists". It is filed to \Failed with a result that names the job
    # it lost to, so the window shows exactly that. The window refuses this
    # before submitting; this catches what got past it.
    $inTheWay = @()
    if ($package) {
        # an older job for this package in the same queue pass (decided up
        # front, before any of them ran) ...
        if ($olderInQueue.ContainsKey($file.FullName)) { $inTheWay += $olderInQueue[$file.FullName] }
        # ... or an OLDER one another collector worker is running right now.
        # Only older: several workers may collect the same folder at once, and
        # a newer duplicate that a second worker has just claimed in order to
        # refuse it must not make this, the rightful older job, refuse itself.
        $inTheWay += @(Get-AudiSwPendingJob -DropFolder $DropFolder -EnvironmentCode $expected -PackageName $package |
                       Where-Object { $_.Path -ne $file.FullName -and $_.State -eq 'Running' -and $_.Submitted -lt $file.CreationTime })
    }

    # --- claim it first, so a second run cannot take the same job
    $working = Join-Path $paths.Working $file.Name
    New-AudiJobFolder -Path $working
    try { Move-Item -LiteralPath $file.FullName -Destination $working -Force }
    catch { Write-Verbose "$($file.Name) was already claimed by another run."; continue }

    # The package folder in New is empty the moment the job is claimed. It is
    # recreated by the window next time somebody submits for this package.
    Remove-AudiEmptyPackageFolder -Path (Split-Path -Parent $file.FullName)

    $outcome     = 'Failed'
    $result      = $null
    $job         = $null
    $contentStep = $null      # set once the store step has run - kept even when a later step throws
    $wantsDryRun = [bool]$DryRun

    try {
        if ($inTheWay.Count -gt 0) {
            $other = $inTheWay[0]
            $readDup = Read-AudiSwJobFile -Path $working
            if ($readDup.Ok) { $job = $readDup.Job }
            $dupText = ("Refused as a duplicate: job {0} ({1}, submitted {2}) for this package was still {3} when this one was submitted. " +
                        "One job per package at a time - wait for that one's result on the Jobs page, then submit again if it is still needed. Nothing has been done.")
            throw ($dupText -f $other.JobId, $(if ($other.Action) { $other.Action } else { 'unknown action' }),
                              $other.Submitted.ToString('dd.MM.yyyy HH:mm'), $(if ($other.State -eq 'Running') { 'running' } else { 'queued' }))
        }
        # --- read and validate. Nothing here asks who wrote the file.
        $read = Read-AudiSwJobFile -Path $working
        if (-not $read.Ok) { throw ("The job file was rejected: " + ($read.Errors -join '; ')) }

        $job = $read.Job

        if ($expected -and $job.Environment -ne $expected) {
            throw ("This job is for $($job.Environment) but it was found in $expected's drop folder. " +
                   "One folder serves one environment. Submit it to $($job.Environment)'s folder, " +
                   "or point this collector at that folder instead. Nothing has been done to either site.")
        }
        # The name inside the file must be the folder it sits in. The schema
        # already keeps slashes and dots-only names out of it; this keeps a
        # hand-edited file from running under one name and filing under another.
        if ($package -and $job.PackageName -ne $package) {
            throw ("The job file names the package '$($job.PackageName)' but it was found in the folder for '$package'. " +
                   "The two must be the same. Nothing has been done.")
        }

        # Find, and a Remove of ticked targets, are not about ONE package - the
        # "package" is a search pattern or a list. They get a site-only plan and
        # never go near the naming rules or a path.
        $siteOnly = ($job.Action -eq 'Find') -or ($job.Action -eq 'Remove' -and @($job.Targets).Count -gt 0)
        $plan = if ($siteOnly) {
            New-AudiSiteOnlyPlan -EnvironmentCode $job.Environment -JobId $job.JobId -Rfc $job.Rfc -Label $job.PackageName
        } else {
            Get-AudiIntegrationPlan `
                    -PackageName            $job.PackageName `
                    -EnvironmentCode        $job.Environment `
                    -Rfc                    $job.Rfc `
                    -LocalizedName          $job.NameEn `
                    -LocalizedDescription   $job.DescriptionEn `
                    -LocalizedNameDe        $job.NameDe `
                    -LocalizedDescriptionDe $job.DescriptionDe `
                    -PartOverride           $job.Detail `
                    -BrandingKey            ([string]$job.Detail['BrandingKey']) `
                    -OperatingSystemKeys    $job.OperatingSystems `
                    -JobId                  $job.JobId
        }

        $wantsDryRun = ($DryRun -or $job.DryRun)

        # THE PACKAGE CONTENT COMES WITH THE JOB.
        #
        # The window never reaches the content store; it puts the package
        # beside its job, in \Sources\<package>, and the middle server carries both
        # across. So the first thing an Integrate or Update does HERE, as the
        # service account, is copy \Sources\<package> into the store - the
        # same copy the packager used to do by hand. It is reported as the
        # job's first step, and the Sources folder is cleared once the whole
        # job has succeeded. A package already in the store is left alone.
        # An unverified environment copies nothing: the engine refuses that job
        # itself, and that refusal - not a missing package - is what it reports.
        $contentStep = $null
        $mayTouchStore = $plan.Verified -or $wantsDryRun
        # RefreshContent REPLACES what is in the store; Integrate and Modify
        # only fill a gap and leave a package already there alone.
        $refresh = ($job.Action -eq 'RefreshContent')
        if ($mayTouchStore -and $job.Action -in @('Integrate', 'Modify', 'RefreshContent') -and (Test-Path -LiteralPath $paths.Sources)) {
            $sourceFiles = @(Get-ChildItem -LiteralPath $paths.Sources -File -Recurse -ErrorAction SilentlyContinue).Count
            if ((Test-Path -LiteralPath $plan.ContentPath) -and -not $refresh) {
                $contentStep = [pscustomobject]@{ Step = 'Content copy'; Ok = $true
                    Message = "Already in the store: $($plan.ContentPath). The $sourceFiles file(s) in Sources were not copied over it." }
            }
            elseif ($wantsDryRun) {
                $contentStep = [pscustomobject]@{ Step = 'Content copy'; Ok = $true
                    Message = "DRY RUN - would $(if ($refresh) { 'compare' } else { 'copy' }) $sourceFiles file(s) from Sources $(if ($refresh) { 'with' } else { 'to' }) $($plan.ContentPath)$(if ($refresh) { ' and replace only what differs' })." }
            }
            elseif ($refresh -and (Test-Path -LiteralPath $plan.ContentPath)) {
                # UPDATE CONTENT: only what differs is written, judged by size
                # and SHA-256 - never by timestamp - so the store changes in
                # seconds and the distribution points fetch only the delta.
                $synced = Sync-AudiPackageContent -Source (Get-AudiPackageContentRoot -PackagePath $paths.Sources) -Target $plan.ContentPath
                $changedList = $(if (@($synced.Changed).Count -le 12) { @($synced.Changed) -join ', ' } else { (@($synced.Changed) | Select-Object -First 12) -join ', ' + " ... (+$(@($synced.Changed).Count - 12) more)" })
                $contentStep = [pscustomobject]@{ Step = 'Content update'; Ok = $true
                    Message = ("{0} replaced, {1} added, {2} removed, {3} unchanged in {4} - {5} file(s), {6:N0} bytes, verified.{7}" -f `
                               $synced.Replaced, $synced.Added, $synced.Removed, $synced.Unchanged, $plan.ContentPath, $synced.Files, $synced.Bytes,
                               $(if ($changedList) { " Changed: $changedList" } else { ' Nothing differed.' })) }
            }
            else {
                $copied = Copy-AudiPackageContent -PackagePath $paths.Sources `
                            -ContentShare (Split-Path -Parent $plan.ContentPath) -SccmName (Split-Path -Leaf $plan.ContentPath)
                $contentStep = [pscustomobject]@{ Step = 'Content copy'; Ok = $true
                    Message = ("{0} file(s), {1:N0} bytes copied from Sources to {2} - verified by file count and size." -f $copied.Files, $copied.Bytes, $copied.Target) }
            }
        }
        elseif ($mayTouchStore -and $job.Action -in @('Integrate', 'RefreshContent') -and -not (Test-Path -LiteralPath $plan.ContentPath) -and -not $wantsDryRun) {
            throw ("The package is neither in the store ($($plan.ContentPath)) nor in the drop folder's Sources ($($paths.Sources)). " +
                   "The window puts it in Sources when you Integrate - if the middle server has not carried it across yet, wait for the next pass. Nothing has been done.")
        }
        elseif ($mayTouchStore -and $refresh -and -not $wantsDryRun) {
            throw "Refresh content needs the new files in the drop folder's Sources ($($paths.Sources)), and there are none. Nothing has been done."
        }

        # A heartbeat beside the job, after every step. The window has no
        # connection to this server, so this file is the only way a packager can
        # see that their job is being worked on rather than stuck - and it is
        # still there to be read after the window has been closed and reopened.
        #
        # NOT .GetNewClosure(). A closure carries the session state it was made
        # in, and the engine's functions are not reachable from inside one - the
        # handler dies with "The term 'Write-AudiSwJobProgress' is not
        # recognized". A plain scriptblock runs in this script's scope, where
        # both the function and the loop variables below are in view, and it is
        # only ever called from inside the same iteration that set them.
        $progressPath = Join-Path $paths.Working ($file.Name -replace '\.xml$', '.result.xml')
        $onProgress = {
            param($stepName, $stepNumber, $stepCount, $completed)
            Write-AudiSwJobProgress -Path $progressPath -Job $job -Executor $executor `
                                    -CurrentStep $stepName -StepNumber $stepNumber -StepCount $stepCount `
                                    -Completed $completed -DryRun:$wantsDryRun
        }

        $result = switch ($job.Action) {
            'Remove'  {
                if (@($job.Targets).Count -gt 0) {
                    # exactly the applications the packager ticked out of a Find answer
                    Invoke-AudiSwTargetRemoval -Plan $plan -Targets $job.Targets -DryRun:$wantsDryRun -OnProgress $onProgress
                } else {
                    Invoke-AudiSwRemoval -Plan $plan -DryRun:$wantsDryRun -OnProgress $onProgress
                }
            }
            'Modify'  { Invoke-AudiSwModification -Plan $plan -DryRun:$wantsDryRun -OnProgress $onProgress }
            'RefreshContent' { Invoke-AudiSwContentRefresh -Plan $plan -DryRun:$wantsDryRun -OnProgress $onProgress }
            'Find'    { Find-AudiSwApplication -Plan $plan -Pattern $job.FindPattern -DryRun:$wantsDryRun }

            # Read the site and report what is there. Creates nothing, so it is
            # never a dry run - there is nothing to rehearse. This is what fills
            # the window's Modify tab.
            'Inspect' {
                # -DryRun matters here even though Inspect creates nothing: it
                # decides whether the SITE is read or the dry-run provider stands
                # in. In production the collector runs without it and this reads
                # the real site; under -DryRun the whole road can be exercised on
                # a machine with no console at all.
                $state = Get-AudiSwPackageState -Plan $plan -DryRun:$wantsDryRun
                [pscustomobject]@{
                    Ok = $state.Ok; DryRun = $false; Message = $state.Message
                    Steps = @([pscustomobject]@{ Step = 'Inspect'; Ok = $state.Ok; Message = $state.Message })
                    State = $state
                }
            }

            # Apply exactly the collections the packager ticked.
            'Change'  {
                Invoke-AudiSwChange -Plan $plan -DryRun:$wantsDryRun -OnProgress $onProgress `
                                    -Add $job.AddCollections -Remove $job.RemoveCollections `
                                    -SettingChanges $job.SettingChanges `
                                    -MemberChanges $job.MemberChanges
            }

            default   { Invoke-AudiSwIntegration  -Plan $plan -DryRun:$wantsDryRun -OnProgress $onProgress }
        }
        $outcome = if ($result.Ok) { 'Succeeded' } else { 'Failed' }

        # The engine leaves the session standing on the site's CMSite drive.
        # Everything from here on is FILE work (the store folder, Sources, the
        # result file), and under the ConfigMgr provider a file-system cmdlet
        # on a UNC path dies with "Object reference not set to an instance"
        # (19.09.2026, Remove: "Content folder FAILED - could not delete
        # \\...\INA_WinMerge_...: Der Objektverweis wurde nicht ... festgelegt").
        # So step back onto the filesystem BEFORE touching a path.
        Restore-AudiFileSystemLocation

        # THE CONTENT FOLDER, only when the packager ticked "also delete the
        # content" and confirmed, and only after SCCM has let go of the
        # application. One folder per removed application, directly under this
        # environment's store, by literal path - nothing else can be deleted
        # from here whatever a name looks like.
        if ($job.Action -eq 'Remove' -and $job.RemoveContent -and $result.Ok) {
            $folders = @($(if (@($job.Targets).Count -gt 0) { $job.Targets | ForEach-Object { @{ Name = $_.Name; Path = $_.ContentPath } } }
                          else { @(@{ Name = $plan.PackageName; Path = $plan.ContentPath }) }))
            $lines = @(); $anyFailed = $false
            foreach ($f in $folders) {
                if ($wantsDryRun) { $lines += "DRY RUN - would delete $($f.Path)"; continue }
                try {
                    $gone = Remove-AudiPackageContent -ContentShare $plan.ContentShare -Path ([string]$f.Path)
                    $lines += $(if ($gone.Removed) { "deleted $($gone.Path)" } else { "NOT deleted $($f.Path) - $($gone.Reason)" })
                }
                catch { $anyFailed = $true; $lines += "could not delete $($f.Path): $($_.Exception.Message)" }
            }
            $result.Steps = @($result.Steps) + @([pscustomobject]@{ Step = 'Content folder'; Ok = (-not $anyFailed); Message = ($lines -join ' | ') })
            if ($anyFailed) { $outcome = 'Failed'; $result.Message = $result.Message + ' The content folder could not be deleted - see the last step.' }
            else { $result.Message = $result.Message + " Content folder: $($lines -join '; ')." }
        }

        # a job the packager chose to run again says so, so the history reads right
        if ($job.Retried -gt 0) { $result.Message = "(Run again, attempt $($job.Retried + 1).) " + $result.Message }
    }
    catch {
        # An engine that THREW (a preflight refusal, a provider error) rather
        # than returning a failed result still gets a result file - with the
        # content step it already did in front, so the packager reads "the
        # files are in the store, the site step failed", not just the error.
        $result = [pscustomobject]@{ Ok = $false; DryRun = $wantsDryRun
                                     Message = $_.Exception.Message; Steps = @() }
    }

    # An engine that threw may have left the session on the CMSite drive as
    # well - back onto the filesystem before Sources is touched (idempotent).
    Restore-AudiFileSystemLocation

    # the content copy is the job's first step, in front of the engine's own -
    # on a thrown failure it is the ONLY step, and the one the packager needs
    if ($contentStep) { $result.Steps = @($contentStep) + @($result.Steps) }

    # SOURCES ARE GONE AS SOON AS THE STORE HOLDS THEM.
    #
    # Not "when the job succeeded": the moment the content step has put a
    # verified copy in the store - or found one already there - the Sources
    # folder is a duplicate of gigabytes the store already has, whatever the
    # rest of the job did, including a step that threw. A later failure (a
    # collection, a scope, a preflight refusal) is retried from the store
    # ("Already in the store"), never from Sources. Sources stay only when
    # the content step itself failed or never ran - the one case a retry
    # needs them - and under a dry run, which copies nothing.
    $storeHasIt = ($contentStep -and $contentStep.Ok -and -not $wantsDryRun)
    if ($storeHasIt -and $paths -and (Test-Path -LiteralPath $paths.Sources)) {
        try {
            Remove-Item -LiteralPath $paths.Sources -Recurse -Force
            $contentStep.Message += ' Sources cleared from the drop folder - the store holds them now.'
        }
        catch { Write-Warning "$($file.Name): the store holds the content but Sources could not be cleared: $($_.Exception.Message)" }
    }
    if ($storeHasIt -and -not $result.Ok) {
        $result.Message = $result.Message + ' The package files ARE in the store (see the first step); Run again continues from there without copying them again.'
    }

    # The run left us standing on the site's CMSite drive. Everything below is
    # file work, and the ConfigMgr provider does not support the switches it
    # uses, so step back onto the filesystem before touching a single file.
    Restore-AudiFileSystemLocation

    # --- file the job and write the result beside it
    $targetFolder = if ($outcome -eq 'Succeeded') { $paths.Done } else { $paths.Failed }
    $resultPath   = Join-Path $targetFolder ($file.Name -replace '\.xml$', '.result.xml')
    New-AudiJobFolder -Path $resultPath

    if (-not $job) {
        # unreadable file: still record why, so the packager is not left guessing
        $job = [pscustomobject]@{ JobId = 'unknown'; Environment = 'ICZ'; PackageName = $file.BaseName; Rfc = '' }
    }

    try {
        $null = Write-AudiSwJobResult -Path $resultPath -Job $job -Executor $executor -Result $result

        # Archive by RE-WRITING the file as this account and deleting the
        # packager's original, rather than Move-Item. A move keeps the NTFS
        # owner, which would leave the packager's name stamped on a file in the
        # secure zone - the one thing Audi asked us not to do.
        $archive = Join-Path $targetFolder $file.Name
        [System.IO.File]::WriteAllBytes($archive, [System.IO.File]::ReadAllBytes($working))
        Remove-Item -LiteralPath $working -Force

        # the heartbeat has served its purpose - the real result is now filed
        $heartbeat = Join-Path $paths.Working ($file.Name -replace '\.xml$', '.result.xml')
        if (Test-Path -LiteralPath $heartbeat) { Remove-Item -LiteralPath $heartbeat -Force -ErrorAction SilentlyContinue }

        # The package folder in Working has nothing left in it now. Left alone,
        # every job leaves one behind and the queue silts up with empty folders.
        # Done keeps its folder - the result is in it, and History reads it.
        Remove-AudiEmptyPackageFolder -Path $paths.Working
    }
    catch { Write-Warning "Could not file the finished job $($file.Name): $($_.Exception.Message)" }

    Write-Verbose "$($file.Name): $outcome - $($result.Message)  [job $($job.JobId), RFC $(if ($job.Rfc) { $job.Rfc } else { 'none' })]"
}

# the pass is over: say so where the packager side can see it
Restore-AudiFileSystemLocation
foreach ($code in $codes) { Write-AudiWatcherStatus -Code $code -Message ("pass finished - {0} job(s) done, as {1}" -f @($jobs | Where-Object { $_.Code -eq $code }).Count, $executor) }
