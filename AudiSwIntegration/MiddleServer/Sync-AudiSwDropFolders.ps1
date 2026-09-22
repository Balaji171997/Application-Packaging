# ==============================================================================
#  Keeps the two drop folders in step: carries jobs and package content from
#  the packagers' drop folder to the SCCM server's, and results back.  FLOW 2
# ==============================================================================
#  Runs ON THE MIDDLE SERVER - the one machine that can open both shares -
#  started by a scheduled task every few minutes. The packagers' zone and the
#  SCCM zone never see each other; this script is the only thing that crosses.
#  It keeps nothing: every copy goes share to share, staged on the destination.
#
#    .\Sync-AudiSwDropFolders.ps1                                    paths from Sync-Settings.txt (normal)
#    .\Sync-AudiSwDropFolders.ps1 -ClientRoot '\\packager-side\DropFolder' -ServerRoot '\\sccm-side\DropFolder'
#    .\Sync-AudiSwDropFolders.ps1 ... -Verbose
#
#  Paths live in Sync-Settings.txt beside this script (key = value); a
#  parameter given on the command line wins over the file. So the scheduled
#  task carries no path, and a path change is an edit to that file.
#
#  Both roots have the same layout, <root>\<ENV>\New|Working|Done|Failed|Sources,
#  so nothing else changes: the window writes to the client root exactly as
#  before, the collector on the SCCM server reads the server root exactly as
#  before. Per environment, each pass does:
#
#    OUT  Sources\<package>\        client -> server   (content first, so a job
#                                                       never arrives before it)
#    OUT  New\<package>\<job>.xml   client -> server, and the client's copy moves
#                                   to client Working\ as the "in transit" marker,
#                                   so the window still sees the job as pending
#    IN   Working\<package>\*.result.xml   server -> client   (the heartbeat)
#    IN   Done|Failed\<package>\*.result.xml  server -> client, and the marker in
#                                   client Working\ is cleared
#
#  Every copy goes to a temporary name and is renamed into place, so neither
#  side can ever pick up a half-copied file or folder.
#
#  It carries files; it reads nothing inside them and runs nothing. It needs
#  no SCCM rights and no environment files - only the two shares.
#
#  ASCII only.
# ==============================================================================

[CmdletBinding()]
param(
    [string]$ClientRoot = '',
    [string]$ServerRoot = '',
    # only this environment's folder, when the middle server serves one zone
    [string]$EnvironmentCode = '',
    [string]$SettingsFile = (Join-Path $PSScriptRoot 'Sync-Settings.txt')
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
if (-not $ClientRoot)      { $ClientRoot      = [string]$settings['ClientRoot'] }
if (-not $ServerRoot)      { $ServerRoot      = [string]$settings['ServerRoot'] }
if (-not $EnvironmentCode) { $EnvironmentCode = [string]$settings['EnvironmentCode'] }
if (-not $ClientRoot -or -not $ServerRoot) {
    throw "No drop folders to keep in step. Set ClientRoot (packager side) and ServerRoot (SCCM side) in $SettingsFile, or pass -ClientRoot and -ServerRoot."
}

# ---- CAN THIS ACCOUNT OPEN BOTH SHARES? Three things are tried before giving
# up, in this order, and the failure names which one it was and as whom:
#   1. a stale session to the same server under another account (Windows
#      error 1219, "multiple connections") is dropped and the path retried;
#   2. run by a PERSON at a console, a sign-in is asked for (up to 3 times);
#      the scheduled task cannot ask, and says so;
#   3. still nothing: a clear reason - denied, not found, network - so the
#      task log tells the server team exactly what to grant.
function Get-AudiShareRoot { param([string]$Path)
    $m = [regex]::Match("$Path", '^(\\\\[^\\]+\\[^\\]+)'); if ($m.Success) { return $m.Groups[1].Value }; return ''
}
function Clear-AudiStaleSession { param([string]$Path)
    <# net use /delete for the share and for every other connection to that
       server - the one thing that clears error 1219. Returns $true if any went. #>
    $share = Get-AudiShareRoot $Path; if (-not $share) { return $false }
    $server = ($share -split '\\')[2]
    $any = $false
    foreach ($line in @(net use 2>$null)) {
        if ($line -match '(\\\\' + [regex]::Escape($server) + '\\\S+)') {
            $null = net use $matches[1] /delete /y 2>$null; $any = $true
        }
    }
    return $any
}
function Test-AudiInteractive {
    return ([Environment]::UserInteractive -and -not ([Environment]::GetCommandLineArgs() -contains '-NonInteractive') -and
            -not ([Environment]::GetCommandLineArgs() -contains '-noninteractive'))
}
function Connect-AudiSyncRoot { param([string]$Path, [string]$Purpose)
    if (Test-Path -LiteralPath $Path) { return }
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    # 1. a stale session under another account?
    $probe = ''; try { $null = [System.IO.Directory]::GetDirectories($Path) } catch { $probe = $_.Exception.Message }
    if ($probe -match '1219|multiple connections|Mehrfachverbindungen' -or (Clear-AudiStaleSession $Path)) {
        if (Test-Path -LiteralPath $Path) { Write-Verbose "$Purpose : a stale session to the server was cleared; the folder opens now."; return }
    }
    # 2. a person at the console can sign in
    $share = Get-AudiShareRoot $Path
    if ($share -and (Test-AudiInteractive)) {
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            $cred = $null
            try { $cred = Get-Credential -Message "Sign in to $share for $Purpose (attempt $attempt of 3)" } catch {}
            if (-not $cred) { break }
            try {
                $name = 'AudiSync' + [guid]::NewGuid().ToString('N').Substring(0, 6)
                $null = New-PSDrive -Name $name -PSProvider FileSystem -Root $share -Credential $cred -Scope Global -ErrorAction Stop
                if (Test-Path -LiteralPath $Path) { Write-Verbose "$Purpose : signed in as $($cred.UserName)."; return }
            }
            catch {
                if ($_.Exception.Message -match '1219|multiple connections|Mehrfachverbindungen') { $null = Clear-AudiStaleSession $Path; $attempt-- ; continue }
                Write-Warning "Sign-in to $share as $($cred.UserName) failed: $($_.Exception.Message)"
            }
        }
    }
    # 3. say exactly what is wrong
    $reason = 'the path does not exist'
    try { $null = [System.IO.Directory]::GetDirectories($Path); $reason = 'it opened on the retry' }
    catch [System.UnauthorizedAccessException] { $reason = 'ACCESS DENIED - this account has no rights on the share or the folder' }
    catch [System.IO.DirectoryNotFoundException] { $reason = 'the path does not exist - ' + $_.Exception.Message.Trim().TrimEnd('.') }
    catch [System.IO.IOException] { $reason = 'the network path could not be opened - ' + $_.Exception.Message.Trim().TrimEnd('.') }
    catch { $reason = $_.Exception.Message.Trim() }
    $how = $(if (Test-AudiInteractive) { 'No sign-in was given, or it did not work.' } else { 'This is a scheduled task, so no sign-in can be asked for: the task account itself must have MODIFY on the share.' })
    throw ("{0} '{1}' cannot be opened as {2}: {3}. {4} Nothing was carried." -f $Purpose, $Path, $me, $reason, $how)
}

# THE PACKAGER IS NEVER BLIND. Every pass leaves a one-line status file on the
# packager side - when it ran, on which machine, and whether it could reach
# the SCCM side - and copies the SCCM watcher's own status file across. The
# window shows both on the Jobs page, so "QUEUED for an hour" comes with the
# reason (middle server down, SCCM side unreachable, watcher not running)
# instead of silence.
function Write-AudiSyncStatus { param([string]$Root, [bool]$Ok, [string]$Message)
    try {
        $line = "{0}|{1}|{2}|{3}" -f (Get-Date).ToString('o'), $env:COMPUTERNAME, $(if ($Ok) { 'OK' } else { 'FAILED' }), ($Message -replace '[\r\n|]+', ' ')
        $tmp = Join-Path $Root '~sync-status.tmp'
        [IO.File]::WriteAllText($tmp, $line, (New-Object Text.UTF8Encoding $false))
        Move-Item -LiteralPath $tmp -Destination (Join-Path $Root 'sync-status.txt') -Force
    } catch {}
}

Connect-AudiSyncRoot -Path $ClientRoot -Purpose 'The packager-side drop folder'
try { Connect-AudiSyncRoot -Path $ServerRoot -Purpose 'The SCCM-side drop folder' }
catch { Write-AudiSyncStatus -Root $ClientRoot -Ok $false -Message $_.Exception.Message; throw }

$states = @('New', 'Working', 'Done', 'Failed', 'Sources')

function Copy-AudiRelayFile {
    <#  One file, to a temporary name beside the target, then renamed into
        place. A reader on the other side sees the file whole or not at all. #>
    param([string]$From, [string]$ToFolder)
    if (-not (Test-Path -LiteralPath $ToFolder)) { New-Item -ItemType Directory -Path $ToFolder -Force | Out-Null }
    $name = Split-Path -Leaf $From
    $temp = Join-Path $ToFolder ("~{0}.relaying" -f $name)
    Copy-Item -LiteralPath $From -Destination $temp -Force
    $final = Join-Path $ToFolder $name
    if (Test-Path -LiteralPath $final) { Remove-Item -LiteralPath $final -Force }
    Rename-Item -LiteralPath $temp -NewName $name
    return $final
}

function Measure-AudiRelayFolder {
    <#  Files and bytes under a folder - the two numbers both sides are
        compared on after a copy.  #>
    param([string]$Path)
    $files = @(Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue)
    $bytes = 0; foreach ($f in $files) { $bytes += $f.Length }
    return @{ Files = $files.Count; Bytes = $bytes }
}

function Get-AudiRelayFreeSpace {
    <#  Free bytes on the volume behind a path, local or UNC; -1 if unknown. #>
    param([string]$Path)
    try {
        if (-not ('AudiSw.RelayDiskSpace' -as [type])) {
            Add-Type -Namespace AudiSw -Name RelayDiskSpace -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode, SetLastError = true)]
public static extern bool GetDiskFreeSpaceEx(string path, out ulong freeToCaller, out ulong total, out ulong free);
'@
        }
        $free = [uint64]0; $total = [uint64]0; $freeAll = [uint64]0
        $probe = $Path
        while ($probe -and -not (Test-Path -LiteralPath $probe)) { $probe = Split-Path -Parent $probe }
        if ($probe -and [AudiSw.RelayDiskSpace]::GetDiskFreeSpaceEx($probe, [ref]$free, [ref]$total, [ref]$freeAll)) { return [long]$free }
        return -1
    }
    catch { return -1 }
}

function Copy-AudiRelayFolder {
    <#  A whole package's Sources, from the packager share STRAIGHT to the
        SCCM-side share. Nothing lands on this machine: the staging folder
        ~<name>.relaying is on the destination share, beside the final name,
        and is renamed into place at the end. Replaces whatever was there: a
        Sources folder still on the server belongs to a job that did not
        succeed, and the newer content wins.

        Copied with robocopy - restartable, retries on a flaky share, built
        for big packages - and then VERIFIED: file count and total bytes on
        both sides must agree, or the staging folder is dropped and the copy
        is tried again on the next pass. Nothing half-copied is ever renamed
        under the real name.  #>
    param([string]$From, [string]$ToParent)
    if (-not (Test-Path -LiteralPath $ToParent)) { New-Item -ItemType Directory -Path $ToParent -Force | Out-Null }
    $name    = Split-Path -Leaf $From
    $staging = Join-Path $ToParent ("~{0}.relaying" -f $name)
    $final   = Join-Path $ToParent $name
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }

    # room on the SCCM side first - with the numbers, before a byte moves
    $expected = Measure-AudiRelayFolder -Path $From
    $free = Get-AudiRelayFreeSpace -Path $ToParent
    if ($free -ge 0 -and $free -lt ($expected.Bytes + 2GB)) {
        throw ("Not enough free space on the SCCM side for {0}: it needs {1:N1} GB (plus a 2 GB margin), {2:N1} GB free. Left on the packager side; tried again next pass." -f `
               $name, ($expected.Bytes / 1GB), ($free / 1GB))
    }

    $robocopy = Get-Command robocopy.exe -ErrorAction SilentlyContinue
    if ($robocopy) {
        # /E all folders incl. empty; /R:3 /W:5 three retries; /NP no percent
        # spam; /NFL /NDL no per-file lines; /NJH /NJS no headers/summary
        $null = & $robocopy.Source $From $staging /E /R:3 /W:5 /NP /NFL /NDL /NJH /NJS /COPY:DAT
        if ($LASTEXITCODE -ge 8) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue; throw "robocopy reported failure (exit code $LASTEXITCODE) copying $From." }
    }
    else { Copy-Item -LiteralPath $From -Destination $staging -Recurse -Force }

    $actual   = Measure-AudiRelayFolder -Path $staging
    if ($expected.Files -ne $actual.Files -or $expected.Bytes -ne $actual.Bytes) {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        throw ("Copy of {0} did not verify: source {1} file(s) / {2} bytes, copy {3} file(s) / {4} bytes. Dropped; tried again next pass." -f `
               $name, $expected.Files, $expected.Bytes, $actual.Files, $actual.Bytes)
    }
    if (Test-Path -LiteralPath $final) { Remove-Item -LiteralPath $final -Recurse -Force }
    Rename-Item -LiteralPath $staging -NewName $name
    return @{ Path = $final; Files = $actual.Files; Bytes = $actual.Bytes }
}

function Remove-AudiRelayEmptyFolder { param([string]$Path)
    if ($Path -and (Test-Path -LiteralPath $Path) -and ($states -notcontains (Split-Path -Leaf $Path))) {
        try { if (@(Get-ChildItem -LiteralPath $Path -Force).Count -eq 0) { Remove-Item -LiteralPath $Path -Force } } catch { }
    }
}

# Environments = the folders under the client root that carry the layout.
# A folder without a New\ inside it is not an environment and is left alone.
$envFolders = @(Get-ChildItem -LiteralPath $ClientRoot -Directory -ErrorAction SilentlyContinue |
                Where-Object { (Test-Path -LiteralPath (Join-Path $_.FullName 'New')) -and
                               (-not $EnvironmentCode -or $_.Name -eq $EnvironmentCode) })
if ($envFolders.Count -eq 0) {
    Write-AudiSyncStatus -Root $ClientRoot -Ok $true -Message 'nothing to carry yet - no environment folder on the packager side'
    Write-Verbose "Nothing to relay - no environment folder under $ClientRoot yet."; return
}

$carried = 0
$passProblems = New-Object System.Collections.Generic.List[string]
foreach ($envFolder in $envFolders) {
    $code = $envFolder.Name
    $c = @{}; $s = @{}
    foreach ($st in $states) { $c[$st] = Join-Path (Join-Path $ClientRoot $code) $st; $s[$st] = Join-Path (Join-Path $ServerRoot $code) $st }
    foreach ($st in $states) { if (-not (Test-Path -LiteralPath $s[$st])) { New-Item -ItemType Directory -Path $s[$st] -Force | Out-Null } }
    foreach ($st in 'Working', 'Done', 'Failed') { if (-not (Test-Path -LiteralPath $c[$st])) { New-Item -ItemType Directory -Path $c[$st] -Force | Out-Null } }
    $held = @{}   # packages whose content could not be carried this pass

    # ---- OUT: the package content, before the job that needs it
    if (Test-Path -LiteralPath $c.Sources) {
        foreach ($pkg in @(Get-ChildItem -LiteralPath $c.Sources -Directory | Where-Object { $_.Name -notlike '~*' })) {
            # A package whose copy does not verify stays on the packager side
            # and is tried again next pass; its job is left waiting too, so it
            # can never arrive on the server ahead of its content.
            try { $copy = Copy-AudiRelayFolder -From $pkg.FullName -ToParent $s.Sources }
            catch { Write-Warning "$code : Sources\$($pkg.Name) not carried - $($_.Exception.Message)"; $held[$pkg.Name] = $true; $passProblems.Add("$code $($pkg.Name): $($_.Exception.Message)") | Out-Null; continue }
            Remove-Item -LiteralPath $pkg.FullName -Recurse -Force
            $carried++
            Write-Verbose ("$code : Sources\$($pkg.Name) carried to the server and verified - {0} file(s), {1:N0} bytes." -f $copy.Files, $copy.Bytes)
        }
    }

    # ---- OUT: the jobs. The client's file moves to its own Working\ as the
    #      "in transit" marker: still pending in the window, still one job per
    #      package, until the result comes back.
    foreach ($jobFile in @(Get-ChildItem -LiteralPath $c.New -Filter '*.xml' -File -Recurse |
                          Where-Object { $_.Name -notlike '*.result.xml' -and $_.Name -notlike '~*' })) {
        $pkgName = Split-Path -Leaf $jobFile.DirectoryName
        if ($pkgName -eq 'New') { $pkgName = '' }
        if ($pkgName -and $held.ContainsKey($pkgName)) { Write-Verbose "$code : job $($jobFile.Name) waits - its content was not carried this pass."; continue }
        $serverNew    = $(if ($pkgName) { Join-Path $s.New $pkgName }     else { $s.New })
        $clientWorking = $(if ($pkgName) { Join-Path $c.Working $pkgName } else { $c.Working })
        $null = Copy-AudiRelayFile -From $jobFile.FullName -ToFolder $serverNew
        if (-not (Test-Path -LiteralPath $clientWorking)) { New-Item -ItemType Directory -Path $clientWorking -Force | Out-Null }
        Move-Item -LiteralPath $jobFile.FullName -Destination (Join-Path $clientWorking $jobFile.Name) -Force
        Remove-AudiRelayEmptyFolder -Path $jobFile.DirectoryName
        $carried++
        Write-Verbose "$code : job $($jobFile.Name) carried to the server; marker left in client Working."
    }

    # ---- IN: heartbeats of jobs being worked on
    if (Test-Path -LiteralPath $s.Working) {
        foreach ($beat in @(Get-ChildItem -LiteralPath $s.Working -Filter '*.result.xml' -File -Recurse)) {
            $pkgName = Split-Path -Leaf $beat.DirectoryName
            $target  = $(if ($pkgName -ne 'Working') { Join-Path $c.Working $pkgName } else { $c.Working })
            $existing = Join-Path $target $beat.Name
            if ((Test-Path -LiteralPath $existing) -and (Get-Item -LiteralPath $existing).LastWriteTimeUtc -ge $beat.LastWriteTimeUtc) { continue }
            $null = Copy-AudiRelayFile -From $beat.FullName -ToFolder $target
        }
    }

    # ---- IN: finished results, and the client's marker is cleared
    foreach ($st in 'Done', 'Failed') {
        if (-not (Test-Path -LiteralPath $s[$st])) { continue }
        foreach ($res in @(Get-ChildItem -LiteralPath $s[$st] -Filter '*.result.xml' -File -Recurse)) {
            $pkgName = Split-Path -Leaf $res.DirectoryName
            $target  = $(if ($pkgName -ne $st) { Join-Path $c[$st] $pkgName } else { $c[$st] })
            if (Test-Path -LiteralPath (Join-Path $target $res.Name)) { continue }   # already carried
            $null = Copy-AudiRelayFile -From $res.FullName -ToFolder $target
            # the archived job file beside it, so the client side holds the pair too
            $jobName = $res.Name -replace '\.result\.xml$', '.xml'
            $jobArchive = Join-Path $res.DirectoryName $jobName
            if (Test-Path -LiteralPath $jobArchive) { $null = Copy-AudiRelayFile -From $jobArchive -ToFolder $target }
            # clear the marker and the heartbeat on the client side
            $markerFolder = $(if ($pkgName -ne $st) { Join-Path $c.Working $pkgName } else { $c.Working })
            foreach ($leftover in @($jobName, $res.Name)) {
                $p = Join-Path $markerFolder $leftover
                if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
            }
            Remove-AudiRelayEmptyFolder -Path $markerFolder
            $carried++
            Write-Verbose "$code : result $($res.Name) carried back ($st)."
        }
    }

    # ---- IN: the SCCM watcher's own status line, so the packager side can
    #      see that the watcher is alive (or that it is not)
    $watcherStatus = Join-Path (Join-Path $ServerRoot $code) 'watcher-status.txt'
    if (Test-Path -LiteralPath $watcherStatus) {
        try { $null = Copy-AudiRelayFile -From $watcherStatus -ToFolder (Join-Path $ClientRoot $code) } catch {}
    }
}

Write-AudiSyncStatus -Root $ClientRoot -Ok ($passProblems.Count -eq 0) -Message $(
    if ($passProblems.Count -eq 0) { "$carried item(s) carried" } else { "$carried carried; " + ($passProblems -join '; ') })
Write-Verbose "Sync pass done - $carried item(s) carried."
