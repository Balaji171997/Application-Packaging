# ==============================================================================
#  Audi SCCM Integration Tool - runtime services
# ==============================================================================
#  The operational layer an enterprise tool needs and the old one lacked:
#  a durable audit trail, sane retry on transient faults, and a guard against
#  two packagers working on the same package at once.
#
#  Every threshold and every "is this transient" pattern comes from
#  Defaults.xml, so behaviour is tunable without a rebuild.
#
#  ASCII only.
# ==============================================================================

Set-StrictMode -Version 2.0

# --------------------------------------------------------------------- logging

function New-AudiLogContext {
    <#  One log per job, under <logRoot>\<environment>\<package>\<jobId>.

        The old tool wrote every module's log into one shared C:\temp\Logs and
        then moved the files afterwards, so two operators - or two packages -
        overwrote each other's logs. A job-owned folder cannot collide.  #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Plan, [string]$Root, [switch]$DryRun)

    $runtime = (Get-AudiDefaults -Root $Root).Runtime
    $folder  = Join-Path (Join-Path (Join-Path $runtime.LogRoot $Plan.Environment) $Plan.PackageName) $Plan.JobId

    $context = [pscustomobject]@{
        JobId     = $Plan.JobId
        Folder    = $folder
        LogPath   = (Join-Path $folder 'integration.log')
        Records   = New-Object System.Collections.Generic.List[object]
        DryRun    = [bool]$DryRun
        Writable  = $false
    }

    try {
        if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
        $context.Writable = $true
    }
    catch {
        # Losing the log file must never stop the integration; the in-memory
        # record still comes back to the caller.
        Write-Warning "Could not create the log folder '$folder': $($_.Exception.Message)"
    }
    return $context
}

function Write-AudiLog {
    <#  Appends one structured line. Deliberately no Write-Host: under
        ps2exe -noConsole there is no console to write to and it throws.  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Info', 'Warn', 'Error', 'Debug')][string]$Level = 'Info',
        [string]$Step = ''
    )

    $record = [pscustomobject]@{
        Time  = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        Level = $Level
        Step  = $Step
        Text  = $Message
    }
    $Context.Records.Add($record) | Out-Null

    if ($Context.Writable) {
        $prefix = if ($Context.DryRun) { '[DRYRUN] ' } else { '' }
        $line   = "{0}  {1,-5}  {2,-14}  {3}{4}" -f $record.Time, $Level, $Step, $prefix, $Message
        try { Add-Content -LiteralPath $Context.LogPath -Value $line -Encoding UTF8 -ErrorAction Stop }
        catch { $Context.Writable = $false }
    }
    Write-Verbose $Message
}

function Save-AudiJobRecord {
    <#  The durable record of one job: who asked, who executed, what was planned
        and what actually happened. This is what an auditor reads, and what a
        support call is reconstructed from.  #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)]$Plan, $Result)

    if (-not $Context.Writable) { return $null }

    $record = [pscustomobject]@{
        JobId       = $Plan.JobId
        Written     = (Get-Date).ToString('o')
        Environment = $Plan.Environment
        Package     = $Plan.PackageName
        Requester   = $Plan.Requester      # the real person
        Executor    = $Plan.Executor       # the shared service account
        Rfc         = $Plan.Rfc
        DryRun      = $Context.DryRun
        Outcome     = $(if ($Result) { $(if ($Result.Ok) { 'Succeeded' } else { 'Failed' }) } else { 'Incomplete' })
        Message     = $(if ($Result) { $Result.Message } else { '' })
        Steps       = $(if ($Result) { $Result.Steps } else { @() })
        RolledBack  = $(if ($Result -and $Result.PSObject.Properties['RolledBack']) { $Result.RolledBack } else { @() })
        Plan        = $Plan
    }

    $path = Join-Path $Context.Folder 'job.json'
    try { $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8 -ErrorAction Stop; return $path }
    catch { Write-Warning "Could not write the job record: $($_.Exception.Message)"; return $null }
}

function Remove-AudiExpiredLog {
    <#  Housekeeping, so the log root does not grow without limit.  #>
    [CmdletBinding()]
    param([string]$Root)
    $runtime = (Get-AudiDefaults -Root $Root).Runtime
    if (-not (Test-Path -LiteralPath $runtime.LogRoot)) { return 0 }
    $cutoff  = (Get-Date).AddDays(-$runtime.LogRetentionDays)
    $removed = 0
    Get-ChildItem -LiteralPath $runtime.LogRoot -Directory -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff -and -not (Get-ChildItem -LiteralPath $_.FullName -Recurse -File -ErrorAction SilentlyContinue) } |
        ForEach-Object { try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop; $removed++ } catch { } }
    return $removed
}

# ----------------------------------------------------------------------- retry

function Test-AudiTransientError {
    <#  True only for the patterns listed in Defaults.xml. Everything else is
        treated as a real failure and reported immediately, rather than being
        retried three times and reported late.  #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Message, [string]$Root)
    foreach ($pattern in (Get-AudiDefaults -Root $Root).Runtime.TransientErrors) {
        if ($Message -match $pattern) { return $true }
    }
    return $false
}

function Invoke-AudiWithRetry {
    <#  Runs a scriptblock, retrying only transient faults, with linear backoff.
        Returns whatever the scriptblock returns; rethrows the last error if
        every attempt fails.  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [string]$Description = 'operation',
        $LogContext,
        [string]$Step = '',
        [string]$Root,
        [int]$RetryCount = -1
    )

    $runtime = (Get-AudiDefaults -Root $Root).Runtime
    if ($RetryCount -lt 0) { $RetryCount = $runtime.RetryCount }

    $attempt = 0
    while ($true) {
        $attempt++
        try { return (& $Action) }
        catch {
            $message = $_.Exception.Message
            $isLast      = ($attempt -ge ($RetryCount + 1))
            $isTransient = Test-AudiTransientError -Message $message -Root $Root

            if ($isLast -or -not $isTransient) {
                if ($LogContext) {
                    $why = if ($isTransient) { "after $attempt attempts" } else { 'not a transient fault' }
                    Write-AudiLog -Context $LogContext -Level 'Error' -Step $Step -Message "$Description failed ($why): $message"
                }
                throw
            }

            $delay = $runtime.RetryDelaySeconds * $attempt
            if ($LogContext) {
                Write-AudiLog -Context $LogContext -Level 'Warn' -Step $Step `
                              -Message "$Description hit a transient fault on attempt $attempt, retrying in ${delay}s: $message"
            }
            Start-Sleep -Seconds $delay
        }
    }
}

# ------------------------------------------------------------------------ lock

function Enter-AudiPackageLock {
    <#  Stops two people integrating the same package into the same environment
        at the same time, which would half-create objects under both jobs.
        A stale lock older than lockTimeoutMinutes is taken over.  #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Plan, [string]$Root)

    $runtime = (Get-AudiDefaults -Root $Root).Runtime
    $dir     = Join-Path $runtime.LogRoot '_locks'
    $safe    = ($Plan.Environment + '_' + $Plan.PackageName) -replace '[^A-Za-z0-9_.-]', '_'
    $path    = Join-Path $dir "$safe.lock"

    try { if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null } }
    catch { return @{ Ok = $true; Path = $null; Message = 'Lock folder unavailable; continuing without a lock.' } }

    if (Test-Path -LiteralPath $path) {
        $existing = $null
        try { $existing = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { }
        $age = if ($existing -and $existing.Started) { (New-TimeSpan -Start ([datetime]$existing.Started) -End (Get-Date)).TotalMinutes } else { [double]::MaxValue }
        if ($age -lt $runtime.LockTimeoutMinutes) {
            return @{ Ok = $false; Path = $path
                Message = "'$($Plan.PackageName)' is already being integrated into $($Plan.Environment) by $($existing.Requester) (job $($existing.JobId), started $($existing.Started))." }
        }
    }

    $content = [pscustomobject]@{ JobId = $Plan.JobId; Requester = $Plan.Requester; Environment = $Plan.Environment
                                  Package = $Plan.PackageName; Started = (Get-Date).ToString('o') }
    try { $content | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding UTF8 -ErrorAction Stop }
    catch { return @{ Ok = $true; Path = $null; Message = 'Lock could not be written; continuing without a lock.' } }

    return @{ Ok = $true; Path = $path; Message = 'Lock taken.' }
}

function Exit-AudiPackageLock {
    [CmdletBinding()]
    param($Lock)
    if ($Lock -and $Lock.Path -and (Test-Path -LiteralPath $Lock.Path)) {
        try { Remove-Item -LiteralPath $Lock.Path -Force -ErrorAction Stop } catch { }
    }
}
