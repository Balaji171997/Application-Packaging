##############################################################
# SharePoint.ps1 - source + predecessor from SharePoint instead of the UNC shares.
#
# DESIGN: PB works on LOCAL paths. Everything here resolves a package to a SharePoint folder, downloads what
# PB actually reads into a local staging folder, and hands back that local path. Nothing downstream changes -
# Resolve-Source / Read-PredecessorModel / Assemble see an ordinary folder (verified: PB's real Resolve-Source
# returns Mode=structured, Valid=True on a SharePoint-staged folder).
#
# LOAD ORDER MATTERS: this file must be dot-sourced AFTER Source.ps1 and Predecessor.ps1. It captures their
# originals and overrides three functions, so the UNC path keeps working untouched when the feature is off.
#
# Layout it expects (verified against the live library):
#   PackageSources/{Vendor}/{App}/{Version}_{Release}/
#       source/   installers      doc/  documents
#       SCCM/{FullPackageName}/   the built package = the PREDECESSOR
#       EQS/ Intune/ Order/       other outputs, ignored
#       RITM*.txt                 ticket refs, ignored
##############################################################

$script:SPDefaults = [ordered]@{
    Enabled    = $false                                                   # master switch; off = pure UNC behaviour
    SiteUrl    = 'https://manonlineservices.sharepoint.com/sites/SWPackaging'
    SitePath   = '/sites/SWPackaging'                                     # server-relative prefix for Get-PnPFile
    Library    = 'PackageSources'
    ClientId   = '28bf2c22-437c-42e7-a4be-e8a0f44a8264'                   # PnP Management Shell (already trusted here)
    ModulePath = 'Lib\PnP.PowerShell\1.12.0\PnP.PowerShell.psd1'          # 1.12.0 = last PS 5.1-compatible release
    UseSourceRepo        = $true    # SharePoint is the PRIMARY source (Find-SourceFolder)
    UseUncSourceFallback = $true    # ...and RepositoryPath (what the tool used before) is the FALLBACK
    UsePredecessorRepo   = $true    # SharePoint is the PRIMARY predecessor source
    AlsoSearchUnc        = $true    # ...and PredecessorPath/PredecessorPaths ADD anything SharePoint lacks
                                    # Every fallback is the share the tool already used, so with SharePoint
                                    # switched off the tool behaves exactly as it always has.
    UncProbeTimeoutMs    = 1500     # bounded wait when testing whether a share is reachable
    # Folders under a version folder that are BUILD OUTPUT, not source. EVERYTHING else is fetched, so a folder
    # named SW-Source / Source / doc / Documents / Order Info all come across without needing to be listed.
    # Deliberately short: wrongly skipping a folder loses source silently, wrongly fetching one only costs
    # bandwidth. Add 'Intune' / 'Order' here if those turn out to be build output in your library too.
    SourceSkipFolders    = @('EQS','SCCM')
    SnippetsFile         = ''       # site-relative path of the TEAM snippets.json (e.g. 'PackageSources/_PackageCompanion/snippets.json').
                                    # Empty = the snippet library stays local / on the SnippetsPath share as before.
    StagingRetentionDays = 7        # staged sources/predecessors older than this are deleted on first connect.
                                    # 0 disables the cleanup. Each staged source is the FULL installer payload
                                    # (260 MB is typical, multi-GB happens), and nothing else ever removes them.
}

# SitePath is the server-relative prefix Get-PnPFile needs ('/sites/SWPackaging'). It is ALWAYS derivable from
# SiteUrl, and two fields that must agree by hand is a trap - point SiteUrl at another site and the old SitePath
# would silently break every download. So derive it unless someone deliberately overrides it.
function Get-SPSitePath {
    param($Cfg)
    $explicit = "$($Cfg.SitePath)".Trim()
    $derived  = ''
    try {
        $u = [uri]"$($Cfg.SiteUrl)"
        $derived = $u.AbsolutePath.TrimEnd('/')
    } catch {}
    if (-not $derived) { return $explicit }
    if ($explicit -and ($explicit.TrimEnd('/') -ne $derived)) {
        Write-SPLog "settings.json SitePath ('$explicit') does not match SiteUrl ('$($Cfg.SiteUrl)'). Using '$derived' - remove SitePath to silence this." Warning
    }
    return $derived
}
# Everything here is overridable from settings.json -> "SharePoint". Booleans included: an explicit false in the
# file wins over the default (so "$($p.Value)" -ne '' must not swallow $false).
function Get-SPConfig {
    $cfg = @{}; foreach ($k in $script:SPDefaults.Keys) { $cfg[$k] = $script:SPDefaults[$k] }
    $over = if (Get-Command Get-Setting -ErrorAction SilentlyContinue) { Get-Setting 'SharePoint' } else { $null }
    if ($over) {
        foreach ($p in $over.PSObject.Properties) {
            if ($null -eq $p.Value) { continue }
            if (($p.Value -is [string]) -and ("$($p.Value)".Trim() -eq '')) { continue }   # blank string = "leave default"
            $cfg[$p.Name] = $p.Value                                                        # $false / 0 pass through
        }
    }
    $cfg['SitePath'] = Get-SPSitePath -Cfg $cfg      # always derived from SiteUrl
    return $cfg
}
function Test-SPEnabled { $c = Get-SPConfig; return [bool]$c.Enabled }

function Write-SPLog {
    param([string]$Message, [string]$Level = 'Info')
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log $Message $Level }
    else { Write-Host "[SP] $Message" }
}

# ---------------------------------------------------------------- connection (once per session)
$script:SPConnected = $false

# Locate + import PnP. The module sits in different places depending on how PB is running (dev folder, portable
# copy, this test folder), so probe rather than hard-code, and fall back to an installed copy on PSModulePath.
# NOTE: PnP is a BINARY module - loading it from a UNC share can fail without the .config trust fix that the
# shared-folder rollout already needed for PB's other binary modules. Prefer a local copy when running off a share.
function Import-SPPnPModule {
    param([string]$ConfiguredPath)
    # Silence PnP's "a newer version is available" banner. We are PINNED to 1.12.0 on purpose (2.x needs PS 7),
    # so the notice is pure noise at every launch - and it is one of the two prompts users see on startup.
    $env:PNPPOWERSHELL_UPDATECHECK = 'Off'
    $roots = New-Object System.Collections.Generic.List[string]
    if ($PSScriptRoot) { $roots.Add($PSScriptRoot) }
    if (Get-Command Get-ToolRoot -ErrorAction SilentlyContinue) { try { $roots.Add((Get-ToolRoot)) } catch {} }
    $roots.Add((Get-Location).Path)

    $rel = @($ConfiguredPath, 'Lib\PnP.PowerShell\1.12.0\PnP.PowerShell.psd1', 'PnP.PowerShell\1.12.0\PnP.PowerShell.psd1')
    $tried = New-Object System.Collections.Generic.List[string]

    if ($ConfiguredPath -and [IO.Path]::IsPathRooted($ConfiguredPath)) {
        if (Test-Path -LiteralPath $ConfiguredPath) {
            try { Import-Module $ConfiguredPath -ErrorAction Stop; return $true }
            catch { Write-SPLog "PnP import failed ($ConfiguredPath): $($_.Exception.Message)" Error; return $false }
        }
        $tried.Add($ConfiguredPath)
    } else {
        foreach ($r in $roots) {
            foreach ($x in $rel) {
                if (-not $x -or [IO.Path]::IsPathRooted($x)) { continue }
                $cand = Join-Path $r $x
                if ($tried -contains $cand) { continue }
                $tried.Add($cand)
                if (Test-Path -LiteralPath $cand) {
                    try { Import-Module $cand -ErrorAction Stop; Write-SPLog "PnP loaded from $cand" Info; return $true }
                    catch { Write-SPLog "PnP import failed ($cand): $($_.Exception.Message)" Error; return $false }
                }
            }
        }
    }
    # Last resort: an installed PnP.PowerShell on PSModulePath (must be 1.x for PS 5.1 - 2.0+ needs PS 7).
    try { Import-Module PnP.PowerShell -ErrorAction Stop; Write-SPLog 'PnP loaded from PSModulePath.' Info; return $true } catch {}
    Write-SPLog "PnP module not found. Looked in: $($tried -join ' ; ')" Error
    return $false
}
# ---- cross-runspace auth -------------------------------------------------------------------------------------
# Find-SourceFolder / Get-PredecessorCandidates execute in a BACKGROUND RUNSPACE (Invoke-PBAsync). An interactive
# sign-in cannot complete there - it has no UI thread for the auth window, so the tool just hangs on "PnP loaded".
# A PnP connection also does NOT cross runspaces. So: sign in ONCE on the UI thread, and hand the resulting access
# token to the worker, which connects silently with -AccessToken.
$script:SPAccessToken = $null
$script:SPNoPrompt    = $false          # set inside worker runspaces: never try an interactive sign-in there
function Set-SPAccessToken {
    param([string]$Token)
    $script:SPNoPrompt = $true          # only a worker calls this, and a worker must never prompt
    if (-not "$Token".Trim()) { return }
    $script:SPAccessToken = $Token
    $script:SPConnected   = $false      # force a reconnect using this token
}
# A worker with no token at all still must not prompt - mark it so Connect-PBSharePoint fails fast.
function Set-SPWorkerNoPrompt { $script:SPNoPrompt = $true }

# MAIN (UI) THREAD ONLY. Returns a token the worker runspace can reuse, signing in interactively if needed.
function Get-SPWorkerToken {
    $cfg = Get-SPConfig
    if (-not $cfg.Enabled) { return $null }
    try {
        if (-not (Get-Command Connect-PnPOnline -ErrorAction SilentlyContinue)) {
            if (-not (Import-SPPnPModule -ConfiguredPath $cfg.ModulePath)) { return $null }
        }
        $tok = $null
        if ($script:SPConnected) {
            try { $tok = Get-PnPAccessToken -ErrorAction Stop }
            catch { Write-SPLog "Cached SharePoint token no longer valid - signing in again. ($($_.Exception.Message))" Info; $tok = $null; $script:SPConnected = $false }
        }
        if (-not $tok) {
            Write-SPLog "Signing in to SharePoint: $($cfg.SiteUrl)" Info
            Write-SPLog 'A Microsoft sign-in window should appear now. If nothing appears, check behind this window.' Info
            Connect-PnPOnline -Url $cfg.SiteUrl -ClientId $cfg.ClientId -Interactive -ErrorAction Stop
            $script:SPConnected = $true
            Write-SPLog 'Sign-in completed.' Success
            Invoke-SPStagingCleanup
            # A token is a BONUS, not a requirement: source and predecessor lookups run on this same (main)
            # thread and use the connection directly. The token only matters if something ever runs them in a
            # worker runspace, so failing to get one must never look like a failed sign-in.
            try { $tok = Get-PnPAccessToken -ErrorAction Stop } catch { $tok = $null }
            if ($tok) { Write-SPLog ("Access token acquired ({0} chars) - background jobs can reuse it." -f "$tok".Length) Success }
            else      { Write-SPLog 'Signed in OK. (No reusable access token from this connection type - harmless: SharePoint work runs on this thread.)' Info }
        }
        return $tok
    } catch {
        Write-SPLog "SharePoint sign-in FAILED: $($_.Exception.Message)" Error
        if ($_.Exception.InnerException) { Write-SPLog "  inner: $($_.Exception.InnerException.Message)" Error }
        return $null
    }
}

function Connect-PBSharePoint {
    param([switch]$Force)
    if ($script:SPConnected -and -not $Force) { return $true }
    $cfg = Get-SPConfig
    if (-not (Get-Command Connect-PnPOnline -ErrorAction SilentlyContinue)) {
        if (-not (Import-SPPnPModule -ConfiguredPath $cfg.ModulePath)) { return $false }
    }
    try {
        if ($script:SPAccessToken) {
            # Worker runspace: silent, using the token the UI thread already obtained. NEVER prompt here -
            # an interactive prompt in a background runspace hangs with no window to click.
            Connect-PnPOnline -Url $cfg.SiteUrl -AccessToken $script:SPAccessToken -ErrorAction Stop
            $script:SPConnected = $true
            Write-SPLog "SharePoint connected (token from the UI thread): $($cfg.SiteUrl)" Success
        } elseif ($script:SPNoPrompt) {
            # Inside a worker runspace with no token: an interactive prompt here would HANG with no window to
            # click. Fail fast instead so the caller falls back to the shares and the user sees why.
            Write-SPLog 'No SharePoint token in this background job - not prompting (it would hang). Falling back to the shares.' Warning
            return $false
        } else {
            Connect-PnPOnline -Url $cfg.SiteUrl -ClientId $cfg.ClientId -Interactive -ErrorAction Stop
            $script:SPConnected = $true
            Write-SPLog "SharePoint connected: $($cfg.SiteUrl)" Success
        }
        Invoke-SPStagingCleanup          # once per session, after connect so it never delays startup
        return $true
    } catch {
        Write-SPLog "SharePoint connect failed: $($_.Exception.Message)" Error
        return $false
    }
}

# ---------------------------------------------------------------- UI wording
# The tool must always say where it is ACTUALLY looking. These labels are derived from the live config, so
# flipping SharePoint off in settings.json changes what the window says as well as what it does - no string
# anywhere claims "the live share" while the code is really reading SharePoint.
function Get-SPPrimaryLabel {
    param([ValidateSet('Source','Predecessor')][string]$For = 'Source')
    $cfg = Get-SPConfig
    $on  = $cfg.Enabled -and $(if ($For -eq 'Source') { $cfg.UseSourceRepo } else { $cfg.UsePredecessorRepo })
    if ($on) { return 'SharePoint' }
    return $(if ($For -eq 'Source') { 'the Incoming share' } else { 'the live share' })
}
function Get-SPFallbackLabel {
    param([ValidateSet('Source','Predecessor')][string]$For = 'Source')
    $cfg = Get-SPConfig
    if (-not $cfg.Enabled) { return '' }
    if ($For -eq 'Source') {
        if ($cfg.UseSourceRepo -and $cfg.UseUncSourceFallback) { return 'the Incoming share' }
    } else {
        if ($cfg.UsePredecessorRepo -and $cfg.AlsoSearchUnc)   { return 'the live share' }
    }
    return ''
}
function Get-SPSearchText {
    param([ValidateSet('Source','Predecessor')][string]$For = 'Source')
    $p = Get-SPPrimaryLabel   -For $For
    $f = Get-SPFallbackLabel  -For $For
    $what = $(if ($For -eq 'Source') { 'the source' } else { 'predecessors' })
    if ($f) { return "Searching $p for $what (falls back to $f)..." }
    return "Searching $p for $what..."
}
# One-line summary of where this build reads from - shown in the window so it is obvious at a glance.
function Get-SPOriginSummary {
    $cfg = Get-SPConfig
    if (-not $cfg.Enabled) { return 'Sources: network shares only (SharePoint disabled)' }
    $bits = @()
    $bits += "Source: $(Get-SPPrimaryLabel -For Source)$(if (Get-SPFallbackLabel -For Source) { ' -> share' })"
    $bits += "Predecessor: $(Get-SPPrimaryLabel -For Predecessor)$(if (Get-SPFallbackLabel -For Predecessor) { ' + share' })"
    return ($bits -join '     ')
}

# ---------------------------------------------------------------- SharePoint primitives
function Get-SPItems {
    param([string]$RelUrl)
    return @(Get-PnPFolderItem -FolderSiteRelativeUrl $RelUrl -ErrorAction SilentlyContinue)
}
function Test-SPFolder { param($Item) return $Item.GetType().Name -eq 'Folder' }

# Recursively list files under a site-relative folder -> @(@{ServerUrl;RelInside;Name;Size}).
function Get-SPFilesRecursive {
    param([string]$RelUrl, [string]$RelInside = '')
    $cfg = Get-SPConfig
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($it in (Get-SPItems -RelUrl $RelUrl)) {
        $inside = if ($RelInside) { "$RelInside/$($it.Name)" } else { $it.Name }
        if (Test-SPFolder $it) {
            foreach ($f in (Get-SPFilesRecursive -RelUrl "$RelUrl/$($it.Name)" -RelInside $inside)) { $out.Add($f) }
        } else {
            if ($it.Name -like '~$*') { continue }                    # Word lock-file leftovers
            $size = 0; try { $size = [int64]$it.Length } catch {}
            $out.Add([pscustomobject]@{ ServerUrl = "$($cfg.SitePath)/$RelUrl/$($it.Name)"; RelInside = $inside; Name = $it.Name; Size = $size })
        }
    }
    return $out.ToArray()      # .ToArray(): @() on a List[object] of PSObjects throws in PS 5.1
}

function Get-SPStageRoot {
    if (Get-Command Get-WorkPath -ErrorAction SilentlyContinue) { return (Get-WorkPath 'Temp') }
    return 'C:\temp\PackageCompanion\Temp'
}

# Staged sources hold the FULL installer payload and nothing else ever deletes them, so a packaging machine
# quietly accumulates hundreds of MB per package until the disk fills. Prune once per session, on first connect.
$script:SPCleanupDone = $false
function Invoke-SPStagingCleanup {
    param([switch]$Force)
    if ($script:SPCleanupDone -and -not $Force) { return }
    $script:SPCleanupDone = $true
    try {
        $days = [int](Get-SPConfig).StagingRetentionDays
        if ($days -le 0) { return }                       # 0 = keep everything
        $root = Get-SPStageRoot
        if (-not (Test-Path -LiteralPath $root)) { return }
        $cutoff = (Get-Date).AddDays(-$days)
        $freed = [int64]0; $n = 0
        # Only OUR folders - never touch anything else living under the work Temp dir.
        foreach ($d in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -match '^(spsrc_|sppred_|sp_source_|sp_predecessor_)' })) {
            if ($d.LastWriteTime -ge $cutoff) { continue }
            $sz = 0
            try { $sz = (Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum } catch {}
            try { Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction Stop; $freed += $sz; $n++ }
            catch { Write-SPLog "Could not remove old staging folder '$($d.Name)': $($_.Exception.Message)" Info }
        }
        if ($n -gt 0) { Write-SPLog ("Cleaned {0} staged folder(s) older than {1} day(s) - freed {2:N0} MB." -f $n, $days, ($freed/1MB)) Success }
    } catch {
        Write-SPLog "Staging cleanup skipped: $($_.Exception.Message)" Info      # never let housekeeping break a fetch
    }
}

# Download a file list into $Dest, preserving RelInside structure. Returns the count present locally afterwards.
# Files already on disk at the right SIZE are skipped - so a repeat fetch costs nothing, and a download that died
# half way resumes instead of re-pulling gigabytes.
function Invoke-SPDownload {
    param([object[]]$Files, [string]$Dest, [string]$Activity = 'Fetching from SharePoint')
    if (-not $Files -or @($Files).Count -eq 0) { return 0 }
    if (-not (Test-Path -LiteralPath $Dest)) { New-Item -Path $Dest -ItemType Directory -Force | Out-Null }

    # ---------------------------------------------------------------------------------------------------
    # WHY THIS EXISTS: Get-PnPFile deadlocks when called from the WPF UI thread.
    # Proven with Test-Download.ps1: the identical call on the identical file takes 1.1s from a console and
    # hangs FOREVER from the tool. PnP downloads await internally; on a thread that carries a WPF
    # SynchronizationContext the continuation is posted back to the dispatcher, but the dispatcher is blocked
    # waiting for that very call - so neither side can move. It is not the proxy (direct), not the filename,
    # not file size. Clearing the context for the duration makes continuations run on the thread pool instead,
    # which is exactly what happens in a console. Restored in finally so the GUI is unaffected afterwards.
    $prevCtx = [System.Threading.SynchronizationContext]::Current
    if ($null -ne $prevCtx) {
        [System.Threading.SynchronizationContext]::SetSynchronizationContext($null)
        Write-SPLog 'Detaching the UI sync context for the download (PnP deadlocks on the WPF thread otherwise).' Info
    }
    try {
    $n = 0; $ok = 0; $skipped = 0; $total = @($Files).Count
    # Per-file logging for a normal package; for a big one, report at intervals instead of spamming the log.
    $logEvery = $(if ($total -le 30) { 1 } else { [Math]::Max(1, [int][Math]::Ceiling($total / 10)) })
    $sw = [Diagnostics.Stopwatch]::StartNew()
    foreach ($f in $Files) {
        $n++
        $sub = Split-Path $f.RelInside -Parent
        $dir = if ($sub) { Join-Path $Dest $sub } else { $Dest }
        # -LiteralPath: real filenames here contain brackets ("...for MAN [3dxWare].docx") and [ ] are wildcards.
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }

        $target = Join-Path $dir $f.Name
        if ((Test-Path -LiteralPath $target) -and $f.Size -gt 0) {
            $have = 0; try { $have = (Get-Item -LiteralPath $target).Length } catch {}
            if ($have -eq $f.Size) { $ok++; $skipped++; continue }      # already here, byte count matches
        }

        if (Get-Command Set-PBProgress -ErrorAction SilentlyContinue) {
            Set-PBProgress -Percent ([int](($n / $total) * 100)) -Status "$Activity ($n/$total)"
        }
        if (($n -eq 1) -or ($n % $logEvery -eq 0) -or ($n -eq $total)) {
            $mb = if ($f.Size -ge 1MB) { ('{0:N1} MB' -f ($f.Size / 1MB)) } else { ('{0:N0} KB' -f ($f.Size / 1KB)) }
            Write-SPLog ("  [{0}/{1}] {2}  ({3})" -f $n, $total, $f.RelInside, $mb) Info
        }
        # Plain blocking download - exactly what the old share-based flow did with Copy-Item. The window is
        # unresponsive while this runs; that is expected and was always the case. Do NOT pump the WPF
        # dispatcher from here: this code runs ON the dispatcher thread, so a synchronous Invoke deadlocks.
        try { Get-PnPFile -Url $f.ServerUrl -Path $dir -FileName $f.Name -AsFile -Force -ErrorAction Stop; $ok++ }
        catch { Write-SPLog "Download failed '$($f.RelInside)': $($_.Exception.Message)" Warning }
    }
    $sw.Stop()
    Write-SPLog ("Fetched {0}/{1} file(s) in {2:N0}s." -f $ok, $total, $sw.Elapsed.TotalSeconds) Info
    if ($skipped -gt 0) { Write-SPLog "$skipped of $total file(s) were already staged locally - not re-downloaded." Info }
    # Strip Mark-of-the-Web so staged installers launch cleanly (same reason PB unblocks extracted zips).
    if (Get-Command Unblock-PBPath -ErrorAction SilentlyContinue) { try { Unblock-PBPath -Path $Dest } catch {} }
    else { Get-ChildItem -LiteralPath $Dest -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { try { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue } catch {} } }
    return $ok
    }
    finally {
        # Always put the UI context back, even if a download threw - otherwise the rest of the GUI would keep
        # running without its dispatcher context.
        if ($null -ne $prevCtx) { [System.Threading.SynchronizationContext]::SetSynchronizationContext($prevCtx) }
    }
}

# ---------------------------------------------------------------- name <-> path mapping
# Vendor_App_Arch_Version-Release_Lang  ->  {Vendor}/{App}/{Version}_{Release}
function Get-SPVersionFolderName { param($Parsed) return "$($Parsed.Version)_$($Parsed.Release)" }

function Parse-SPVersionFolder {
    param([string]$FolderName)
    if ($FolderName -match '^(?<Ver>.+)_(?<Rel>\d{4})$') { return @{ Version=$Matches.Ver; Release=$Matches.Rel; RelInt=[int]$Matches.Rel; Raw=$FolderName; Valid=$true } }
    return @{ Raw = $FolderName; Valid = $false }
}
# Component-wise numeric compare: '10.8.7' < '10.8.7.3448', and tolerates 5+ components that [version] rejects.
function Compare-SPVersion {
    param([string]$A, [string]$B)
    $x = @($A -split '[.\-]' | ForEach-Object { $n=0; if ([int]::TryParse($_,[ref]$n)) { $n } else { 0 } })
    $y = @($B -split '[.\-]' | ForEach-Object { $n=0; if ([int]::TryParse($_,[ref]$n)) { $n } else { 0 } })
    for ($i = 0; $i -lt [Math]::Max($x.Count, $y.Count); $i++) {
        $xi = if ($i -lt $x.Count) { $x[$i] } else { 0 }
        $yi = if ($i -lt $y.Count) { $y[$i] } else { 0 }
        if ($xi -lt $yi) { return -1 }; if ($xi -gt $yi) { return 1 }
    }
    return 0
}

# Locate a child folder by name: exact, then punctuation/case-insensitive, then 'starts with'.
function Find-SPChildFolder {
    param([string]$ParentRel, [string]$Want)
    $kids = @(Get-SPItems -RelUrl $ParentRel | Where-Object { Test-SPFolder $_ })
    if (@($kids).Count -eq 0) { return $null }
    $hit = $kids | Where-Object { $_.Name -ieq $Want } | Select-Object -First 1
    if ($hit) { return $hit.Name }
    $norm = { param($s) ($s -replace '[\s_\-\.]','').ToLower() }
    $wn = & $norm $Want
    $hit = $kids | Where-Object { (& $norm $_.Name) -eq $wn } | Select-Object -First 1
    if ($hit) { return $hit.Name }
    $hit = $kids | Where-Object { (& $norm $_.Name).StartsWith($wn) } | Select-Object -First 1
    if ($hit) { return $hit.Name }
    return $null
}

# ---------------------------------------------------------------- SOURCE
# Build-output folders under a version folder - everything else is treated as source/documents and fetched.
# Matches the bare name AND the suffixed form ('EQS_Vendor_App_1.0-0001_MUL'), which really occurs.
# Override in settings.json -> SharePoint.SourceSkipFolders.
function Test-SPSkipSourceFolder {
    param([string]$Name)
    $skip = @((Get-SPConfig).SourceSkipFolders)
    if (@($skip).Count -eq 0) { $skip = @('EQS','SCCM','Intune','Order') }
    foreach ($s in $skip) {
        if (-not "$s".Trim()) { continue }
        if ($Name -ieq "$s") { return $true }
        if ($Name -imatch ('^' + [regex]::Escape("$s") + '[ _\-]')) { return $true }
    }
    return $false
}

# Download <Version>/source + <Version>/doc into a local staging folder; return that path (or $null).
function Get-SPSourceFolder {
    param([Parameter(Mandatory)]$Parsed)
    # $script:SPLastSourceReason lets the caller tell "could not sign in" from "signed in, nothing there" -
    # two very different things to put in front of a packager.
    $script:SPLastSourceReason = ''
    if (-not (Connect-PBSharePoint)) { $script:SPLastSourceReason = 'SharePoint could not be reached or signed in to'; return $null }
    $cfg = Get-SPConfig
    $lib = $cfg.Library

    $vendor = Find-SPChildFolder -ParentRel $lib -Want $Parsed.Vendor
    if (-not $vendor) {
        $script:SPLastSourceReason = "no vendor folder '$($Parsed.Vendor)' in SharePoint"
        Write-SPLog "SharePoint: vendor '$($Parsed.Vendor)' not found." Warning; return $null
    }
    $app = Find-SPChildFolder -ParentRel "$lib/$vendor" -Want $Parsed.AppName
    if (-not $app) {
        $script:SPLastSourceReason = "vendor '$vendor' exists in SharePoint but has no app folder '$($Parsed.AppName)'"
        Write-SPLog "SharePoint: app '$($Parsed.AppName)' not found under '$vendor'." Warning; return $null
    }
    $wantVer = Get-SPVersionFolderName $Parsed
    $ver = Find-SPChildFolder -ParentRel "$lib/$vendor/$app" -Want $wantVer
    if (-not $ver) {
        # Say what versions DO exist - usually the packager just has the version or release digits slightly off.
        $have = @(Get-SPItems -RelUrl "$lib/$vendor/$app" | Where-Object { Test-SPFolder $_ } | ForEach-Object { $_.Name })
        $script:SPLastSourceReason = "'$vendor/$app' exists in SharePoint but has no version folder '$wantVer'"
        Write-SPLog "SharePoint: version folder '$wantVer' not found under '$vendor/$app'." Warning
        if (@($have).Count -gt 0) { Write-SPLog ("SharePoint has these versions for '$vendor/$app': " + (($have | Select-Object -First 12) -join ', ')) Info }
        return $null
    }

    $verRel = "$lib/$vendor/$app/$ver"
    $kids = Get-SPItems -RelUrl $verRel
    $files = New-Object System.Collections.Generic.List[object]

    # TAKE EVERYTHING EXCEPT THE BUILD-OUTPUT FOLDERS. Matching on names like 'source'/'doc' was too rigid -
    # real folders are called SW-Source, Source, doc, Documents, Order Info, ... and the list keeps growing.
    # The only things we reliably know we do NOT want are the build outputs (EQS / SCCM / Intune / Order), and
    # those ARE named predictably (sometimes suffixed, e.g. EQS_Vendor_App_1.0-0001_MUL).
    $taken = @(); $skippedFolders = @()
    foreach ($k in $kids) {
        if (Test-SPFolder $k) {
            if (Test-SPSkipSourceFolder -Name $k.Name) { $skippedFolders += $k.Name; continue }
            foreach ($f in (Get-SPFilesRecursive -RelUrl "$verRel/$($k.Name)" -RelInside $k.Name)) { $files.Add($f) }
            $taken += $k.Name
        } else {
            if ($k.Name -match '^RITM\d+\s*\.txt$') { continue }        # ticket reference, not content
            if ($k.Name -like '~$*') { continue }                       # Word lock-file leftover
            $size = 0; try { $size = [int64]$k.Length } catch {}
            $files.Add([pscustomobject]@{ ServerUrl = "$($cfg.SitePath)/$verRel/$($k.Name)"; RelInside = $k.Name; Name = $k.Name; Size = $size })
        }
    }
    if ($taken)          { Write-SPLog ("SharePoint source folders taken: " + ($taken -join ', ')) Info }
    if ($skippedFolders) { Write-SPLog ("SharePoint build-output folders skipped: " + ($skippedFolders -join ', ')) Info }
    if ($files.Count -eq 0) {
        $script:SPLastSourceReason = "SharePoint has the folder '$ver' but it holds no source files (only ticket refs / build output)"
        Write-SPLog "SharePoint: no source content in $verRel" Warning; return $null
    }

    $arr   = $files.ToArray()
    $bytes = [int64](($arr | Measure-Object -Property Size -Sum).Sum)

    # DETERMINISTIC staging path (was a fresh guid every call, which re-downloaded the same hundreds of MB every
    # time someone clicked Fetch twice). Same package -> same folder -> Invoke-SPDownload skips what is already there.
    $safe  = (("$($Parsed.Vendor)_$($Parsed.AppName)_$($Parsed.Version)_$($Parsed.Release)") -replace '[^A-Za-z0-9._-]','_')
    $stage = Join-Path (Get-SPStageRoot) ("spsrc_" + $safe)

    if (Test-Path -LiteralPath (Join-Path $stage '.spcomplete')) {
        Write-SPLog "SharePoint source already staged - reusing $stage (delete the folder to force a re-download)." Success
        return $stage
    }

    Write-SPLog ("SharePoint source: {0} file(s), {1:N1} MB from {2}" -f @($arr).Count, ($bytes/1MB), $verRel)
    $got = Invoke-SPDownload -Files $arr -Dest $stage -Activity 'Fetching source from SharePoint'
    if ($got -eq 0) { return $null }
    if ($got -lt @($arr).Count) {
        # Partial: usable, but do NOT mark complete - the next fetch retries only the missing files.
        Write-SPLog "SharePoint source PARTIAL: $got of $(@($arr).Count) file(s) staged. Fetch again to retry the rest." Warning
        return $stage
    }
    Set-Content -LiteralPath (Join-Path $stage '.spcomplete') -Value (Get-Date -Format 's') -Force
    Write-SPLog "SharePoint source staged -> $stage" Success
    return $stage
}

# ---------------------------------------------------------------- PREDECESSOR
# Files PB actually reads from a predecessor. Payload is excluded wherever it hides - one real package keeps a
# 190 MB installer inside Content\SupportFiles, which PB never reads.
function Test-SPWantPredecessorFile {
    param([string]$RelInside, [string]$FileName, [switch]$Full)
    if ($Full) { return $true }
    if ($FileName -imatch '\.(exe|msi|msp|msu|zip|7z|rar|cab|iso|img|wim|vhdx?|msix|appx)$') { return $false }
    if ($FileName -ieq 'Deploy-Application.ps1' -or $FileName -ieq 'Invoke-AppDeployToolkit.ps1') { return $true }
    if ($FileName -imatch '\.(mst|ico)$') { return $true }
    if ($RelInside -imatch '(^|/)SupportFiles/') { return $true }     # ActiveSetup stubs + their config files
    if ($RelInside -imatch '(^|/)Icons/')        { return $true }
    return $false
}

# ---------------------------------------------------------------- UNC reachability (secondary source)
# UNC is OPTIONAL here: some users have no read access to any share. A plain Test-Path on an unreachable UNC
# host BLOCKS for 30-90s on the SMB timeout, which looks like a frozen tool - so probe the host's port 445 with
# a bounded wait first, and cache the verdict for the session. Once the host answers, ACL denials come back
# fast, so a normal Test-Path is safe after the probe.
$script:SPPathProbe = @{}
function Test-SPUncUsable {
    param([string]$Path, [int]$TimeoutMs = 0)
    if (-not "$Path".Trim()) { return $false }
    if ($TimeoutMs -le 0) { $TimeoutMs = [int](Get-SPConfig).UncProbeTimeoutMs; if ($TimeoutMs -le 0) { $TimeoutMs = 1500 } }
    $key = "$Path".TrimEnd('\').ToLower()
    if ($script:SPPathProbe.ContainsKey($key)) { return $script:SPPathProbe[$key] }

    $ok = $false
    try {
        if ($Path -notmatch '^\\\\([^\\]+)\\') {
            $ok = (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)      # local path - cheap
        } else {
            $server = $Matches[1]
            $client = New-Object System.Net.Sockets.TcpClient
            try {
                $iar = $client.BeginConnect($server, 445, $null, $null)
                if ($iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false) -and $client.Connected) {
                    $client.EndConnect($iar)
                    $ok = (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)   # reachable: ACL answer is fast
                } else {
                    Write-SPLog "UNC host '$server' did not answer in $($TimeoutMs)ms - skipping $Path" Info
                }
            } finally { try { $client.Close() } catch {} }
        }
    } catch { $ok = $false }

    $script:SPPathProbe[$key] = $ok
    if (-not $ok) { Write-SPLog "UNC not available (ignored): $Path" Info }
    return $ok
}

# Cheap metadata scan - NO downloads. Returns objects matching Get-PredecessorCandidates' contract, with
# FullName set to the staging path the package WILL occupy once selected.
function Get-SPPredecessorCandidates {
    param([Parameter(Mandatory)]$Parsed)
    if (-not (Connect-PBSharePoint)) { return @() }
    $cfg = Get-SPConfig
    $lib = $cfg.Library
    $newFull = "$($Parsed.FullName)"

    $vendor = Find-SPChildFolder -ParentRel $lib -Want $Parsed.Vendor
    if (-not $vendor) { Write-SPLog "SharePoint: vendor '$($Parsed.Vendor)' not found for predecessor lookup." Warning; return @() }
    $app = Find-SPChildFolder -ParentRel "$lib/$vendor" -Want $Parsed.AppName
    if (-not $app) { Write-SPLog "SharePoint: app '$($Parsed.AppName)' not found under '$vendor'." Warning; return @() }

    $exactName = ($vendor -ieq $Parsed.Vendor) -and ($app -ieq $Parsed.AppName)
    $appRel = "$lib/$vendor/$app"
    $list = New-Object System.Collections.Generic.List[object]

    foreach ($v in (Get-SPItems -RelUrl $appRel | Where-Object { Test-SPFolder $_ })) {
        $pv = Parse-SPVersionFolder $v.Name
        if (-not $pv.Valid) { continue }
        # The built package lives in SCCM/. No package there = stale/ticket-only folder, not a candidate.
        $sccm = @(Get-SPItems -RelUrl "$appRel/$($v.Name)/SCCM" | Where-Object { Test-SPFolder $_ })
        if (@($sccm).Count -eq 0) { continue }
        $pkgName = $sccm[0].Name
        if ($pkgName -ieq $newFull) { continue }                      # never offer the package as its own predecessor

        try { $ver = [version]($pv.Version -replace '[^0-9.]','') } catch { $ver = $null }
        $stage = Join-Path (Get-SPStageRoot) ("sppred_" + $pkgName)
        $list.Add([pscustomobject]@{
            Name        = $pkgName
            FullName    = $stage                                       # materialised on selection
            Version     = $pv.Version
            Ver         = $ver
            Revision    = $pv.Release
            SameVersion = ($pv.Version -eq $Parsed.Version)
            Score       = $(if ($exactName) { 100 } else { 85 })
            Close       = (-not $exactName)
            MatchNote   = $(if ($exactName) { '' } else { "matched SharePoint folder '$vendor/$app'" })
            SPRelPath   = "$appRel/$($v.Name)/SCCM/$pkgName"           # extra: where to fetch it from
        })
    }
    if ($list.Count -eq 0) { Write-SPLog "SharePoint: no predecessor packages under $appRel" Warning; return @() }
    return @($list.ToArray() | Sort-Object @{e={$_.Score};Descending=$true}, @{e={$_.Ver};Descending=$true}, @{e={$_.Revision};Descending=$true})
}

# Download the allowlist for ONE predecessor into its staging folder. Idempotent - skips if already staged.
function Get-SPPredecessorPackage {
    param([Parameter(Mandatory)][string]$SPRelPath, [Parameter(Mandatory)][string]$Dest, [switch]$Full)
    if (Test-Path -LiteralPath (Join-Path $Dest '.spcomplete')) { return $Dest }      # already fetched this session
    if (-not (Connect-PBSharePoint)) { return $null }
    $all  = Get-SPFilesRecursive -RelUrl $SPRelPath
    $want = @($all | Where-Object { Test-SPWantPredecessorFile -RelInside $_.RelInside -FileName $_.Name -Full:$Full })
    if (@($want).Count -eq 0) { Write-SPLog "SharePoint: nothing to fetch for predecessor $SPRelPath" Warning; return $null }
    $bytes = [int64](($want | Measure-Object -Property Size -Sum).Sum)
    Write-SPLog ("SharePoint predecessor: {0} file(s), {1:N0} KB (skipping {2} payload file(s))" -f @($want).Count, ($bytes/1KB), (@($all).Count - @($want).Count))
    $got = Invoke-SPDownload -Files $want -Dest $Dest -Activity 'Fetching predecessor from SharePoint'
    if ($got -eq 0) { return $null }
    Set-Content -LiteralPath (Join-Path $Dest '.spcomplete') -Value (Get-Date -Format 's') -Force
    Write-SPLog "SharePoint predecessor staged -> $Dest" Success
    return $Dest
}

# ---------------------------------------------------------------- DELIVERY (the one WRITE to SharePoint)
# True when a local folder is one of OUR staged SharePoint sources - i.e. the package's source came from
# SharePoint, so the built package belongs back there (SCCM/) rather than on the Outgoing share.
function Test-SPStagedSource {
    param([string]$Path)
    if (-not "$Path".Trim()) { return $false }
    $root = "$(Get-SPStageRoot)".TrimEnd('\').ToLower()
    $p = "$Path".TrimEnd('\').ToLower()
    return ($p.StartsWith($root + '\') -and ((Split-Path $p -Leaf) -like 'spsrc_*'))
}
# Already signed in this session? The interactive sign-in only works at STARTUP (before the WPF window exists);
# from a button handler it hangs. So a delivery button must never trigger a sign-in - it checks this instead.
function Test-SPConnected { return [bool]$script:SPConnected }

# Upload a built package to {Vendor}/{App}/{Version}_{Release}/SCCM/{PackageName}/ - the same place the tool
# reads predecessors from, so the next release finds this one. Creates missing folders. Refuses to overwrite
# unless -Replace. VERIFIES every file by name + size after the upload and only reports Ok when all landed.
# Returns @{ Ok; Exists; RelPath; Total; Uploaded; Missing=@(); Message }.
function Copy-SPPackage {
    param([Parameter(Mandatory)][string]$LocalPath, [Parameter(Mandatory)]$Parsed, [switch]$Replace, [switch]$CheckOnly)
    $r = @{ Ok = $false; Exists = $false; RelPath = ''; Total = 0; Uploaded = 0; Missing = @(); Message = '' }
    if (-not (Test-Path -LiteralPath $LocalPath)) { $r.Message = "Package folder not found: $LocalPath"; return $r }
    if (-not (Test-SPConnected)) { $r.Message = 'Not signed in to SharePoint. Sign-in happens when the tool starts - restart Package Companion and try again.'; return $r }
    if (-not (Connect-PBSharePoint)) { $r.Message = 'SharePoint connection lost - restart Package Companion.'; return $r }

    $cfg = Get-SPConfig
    $lib = $cfg.Library
    $pkgName = Split-Path $LocalPath -Leaf

    # Reuse the folders that already exist (their spelling may differ from the parsed name); create only what is missing.
    $vendor = Find-SPChildFolder -ParentRel $lib -Want $Parsed.Vendor;                       if (-not $vendor) { $vendor = "$($Parsed.Vendor)" }
    $app    = Find-SPChildFolder -ParentRel "$lib/$vendor" -Want $Parsed.AppName;            if (-not $app)    { $app    = "$($Parsed.AppName)" }
    $wantVer = Get-SPVersionFolderName $Parsed
    $ver    = Find-SPChildFolder -ParentRel "$lib/$vendor/$app" -Want $wantVer;              if (-not $ver)    { $ver    = $wantVer }
    $sccm   = Find-SPChildFolder -ParentRel "$lib/$vendor/$app/$ver" -Want 'SCCM';           if (-not $sccm)   { $sccm   = 'SCCM' }
    $rel    = "$lib/$vendor/$app/$ver/$sccm/$pkgName"
    $r.RelPath = $rel

    $existing = @()
    try { $existing = @(Get-SPFilesRecursive -RelUrl $rel) } catch { $existing = @() }
    if (@($existing).Count -gt 0) {
        $r.Exists = $true
        if (-not $Replace) { $r.Message = "'$pkgName' already exists in SharePoint at $rel ($(@($existing).Count) file(s))."; return $r }
    }
    if ($CheckOnly) { $r.Ok = $true; return $r }

    $files = @(Get-ChildItem -LiteralPath $LocalPath -File -Recurse -Force -ErrorAction SilentlyContinue)
    $r.Total = @($files).Count
    if ($r.Total -eq 0) { $r.Message = 'The package folder is empty - nothing to upload.'; return $r }
    $bytes = [int64](($files | Measure-Object Length -Sum).Sum)
    Write-SPLog ("SharePoint upload: {0} file(s), {1:N1} MB -> {2}" -f $r.Total, ($bytes/1MB), $rel) Info

    # Same reason as Invoke-SPDownload: PnP awaits internally and deadlocks on the WPF thread unless the UI
    # SynchronizationContext is detached for the duration. Restored in finally.
    $prevCtx = [System.Threading.SynchronizationContext]::Current
    if ($null -ne $prevCtx) { [System.Threading.SynchronizationContext]::SetSynchronizationContext($null) }
    try {
        # Folders first (Resolve-PnPFolder creates the whole chain), so every Add-PnPFile has a home.
        $base = "$LocalPath".TrimEnd('\')
        $dirs = @($files | ForEach-Object { $d = $_.DirectoryName.Substring($base.Length).TrimStart('\'); $d -replace '\\','/' } | Sort-Object -Unique)
        foreach ($d in $dirs) {
            $target = if ($d) { "$rel/$d" } else { $rel }
            try { Resolve-PnPFolder -SiteRelativePath $target -ErrorAction Stop | Out-Null }
            catch { $r.Message = "Could not create SharePoint folder '$target': $($_.Exception.Message)"; return $r }
        }
        $n = 0; $logEvery = $(if ($r.Total -le 30) { 1 } else { [Math]::Max(1, [int][Math]::Ceiling($r.Total / 10)) })
        $sw = [Diagnostics.Stopwatch]::StartNew()
        foreach ($f in $files) {
            $n++
            $sub = $f.DirectoryName.Substring($base.Length).TrimStart('\') -replace '\\','/'
            $folder = if ($sub) { "$rel/$sub" } else { $rel }
            if (($n -eq 1) -or ($n % $logEvery -eq 0) -or ($n -eq $r.Total)) {
                Write-SPLog ("  [{0}/{1}] {2}" -f $n, $r.Total, $(if ($sub) { "$sub/$($f.Name)" } else { $f.Name })) Info
            }
            # -Stream + -FileName: names with [ ] (real: '...for MAN [3dxWare].docx') must never go through a
            # wildcard-expanding -Path parameter.
            $fs = $null
            try {
                $fs = [IO.File]::Open($f.FullName, 'Open', 'Read', 'Read')
                Add-PnPFile -Folder $folder -FileName $f.Name -Stream $fs -ErrorAction Stop | Out-Null
                $r.Uploaded++
            } catch {
                Write-SPLog "Upload failed '$($f.Name)': $($_.Exception.Message)" Warning
            } finally { if ($fs) { $fs.Dispose() } }
        }
        $sw.Stop()
        Write-SPLog ("Uploaded {0}/{1} file(s) in {2:N0}s." -f $r.Uploaded, $r.Total, $sw.Elapsed.TotalSeconds) Info

        # VERIFY: list what SharePoint now holds and compare name + size against the local package. Only when
        # everything matches is this reported as delivered - a half-uploaded package must never look complete.
        $remote = @{}
        foreach ($x in @(Get-SPFilesRecursive -RelUrl $rel)) { $remote["$($x.RelInside)".ToLower()] = [int64]$x.Size }
        $missing = New-Object System.Collections.Generic.List[string]
        foreach ($f in $files) {
            $inside = ($f.FullName.Substring($base.Length).TrimStart('\') -replace '\\','/')
            $k = $inside.ToLower()
            if (-not $remote.ContainsKey($k))          { $missing.Add("$inside (not uploaded)"); continue }
            if ($remote[$k] -ne [int64]$f.Length)      { $missing.Add("$inside (size differs: local $($f.Length), SharePoint $($remote[$k]))") }
        }
        $r.Missing = $missing.ToArray()
        if ($missing.Count -eq 0) {
            $r.Ok = $true
            $r.Message = "Delivered to SharePoint: $rel ($($r.Total) file(s) verified)"
            Write-SPLog $r.Message Success
        } else {
            $r.Message = "Upload INCOMPLETE - $($missing.Count) of $($r.Total) file(s) did not land in SharePoint. Run the copy again (existing files are replaced)."
            Write-SPLog $r.Message Error
            foreach ($m in ($missing | Select-Object -First 20)) { Write-SPLog "    - $m" Warning }
        }
        return $r
    } catch {
        $r.Message = "SharePoint upload failed: $($_.Exception.Message)"
        Write-SPLog $r.Message Error
        return $r
    } finally {
        if ($null -ne $prevCtx) { [System.Threading.SynchronizationContext]::SetSynchronizationContext($prevCtx) }
    }
}

# ---------------------------------------------------------------- SHARED SNIPPET LIBRARY
# settings.json -> SharePoint.SnippetsFile = site-relative path of the team's snippets.json (e.g.
# "PackageSources/_PackageCompanion/snippets.json"). Empty = off (local file / SnippetsPath share as before).
# Startup: download it to the work root and use that copy. Owner edits: written locally, then uploaded back.
# First use with nothing on SharePoint yet: an OWNER's local file seeds the library (non-owners never create it).
function Get-SPSnippetsLocalPath { return (Join-Path (Get-SPWorkRoot) 'snippets.shared.json') }
function Get-SPWorkRoot { if (Get-Command Get-WorkPath -ErrorAction SilentlyContinue) { return (Get-WorkPath) }; return 'C:\temp\PackageCompanion' }
function Get-SPSnippetsRel { $cfg = Get-SPConfig; return "$($cfg.SnippetsFile)".Trim().Trim('/') }
# PnP awaits internally and deadlocks on the WPF thread: run the given work with the UI SynchronizationContext detached.
function Invoke-SPWithoutUiContext {
    param([scriptblock]$Work)
    $prev = [System.Threading.SynchronizationContext]::Current
    if ($null -ne $prev) { [System.Threading.SynchronizationContext]::SetSynchronizationContext($null) }
    try { return (& $Work) } finally { if ($null -ne $prev) { [System.Threading.SynchronizationContext]::SetSynchronizationContext($prev) } }
}
function Sync-SPSnippetsDown {
    param([string]$LocalSeed, [bool]$CanSeed = $false)
    $rel = Get-SPSnippetsRel; if (-not $rel) { return $null }
    if (-not (Connect-PBSharePoint)) { Write-SPLog 'Snippets: SharePoint not connected - using the local library.' Warning; return $null }
    $cfg = Get-SPConfig
    $local = Get-SPSnippetsLocalPath
    $dir = Split-Path $local -Parent; $name = Split-Path $local -Leaf
    $serverUrl = "$($cfg.SitePath)/$rel"
    $ok = Invoke-SPWithoutUiContext {
        try { Get-PnPFile -Url $serverUrl -Path $dir -FileName $name -AsFile -Force -ErrorAction Stop; $true } catch { $script:SPSnipErr = "$($_.Exception.Message)"; $false }
    }
    if ($ok -and (Test-Path -LiteralPath $local)) { Write-SPLog "Snippets: shared library fetched from SharePoint ($rel)." Success; return $local }
    # Nothing there yet: seed from the local file, but only an owner may create the team library.
    if ($CanSeed -and $LocalSeed -and (Test-Path -LiteralPath $LocalSeed)) {
        if (Sync-SPSnippetsUp -LocalPath $LocalSeed) { Copy-Item -LiteralPath $LocalSeed -Destination $local -Force; Write-SPLog "Snippets: seeded the shared library on SharePoint from the local file ($rel)." Success; return $local }
    }
    Write-SPLog "Snippets: no shared library at $rel ($($script:SPSnipErr)) - using the local file." Warning
    return $null
}
function Sync-SPSnippetsUp {
    param([Parameter(Mandatory)][string]$LocalPath)
    $rel = Get-SPSnippetsRel; if (-not $rel) { return $false }
    if (-not (Test-SPConnected)) { Write-SPLog 'Snippets: not signed in to SharePoint - the edit is saved locally only.' Warning; return $false }
    if (-not (Test-Path -LiteralPath $LocalPath)) { return $false }
    $folder = $rel.Substring(0, $rel.LastIndexOf('/')); $name = $rel.Substring($rel.LastIndexOf('/') + 1)
    return (Invoke-SPWithoutUiContext {
        try {
            Resolve-PnPFolder -SiteRelativePath $folder -ErrorAction Stop | Out-Null
            $fs = [IO.File]::Open($LocalPath, 'Open', 'Read', 'Read')
            try { Add-PnPFile -Folder $folder -FileName $name -Stream $fs -ErrorAction Stop | Out-Null } finally { $fs.Dispose() }
            Write-SPLog "Snippets: shared library updated on SharePoint ($rel)." Success; $true
        } catch { Write-SPLog "Snippets: upload to SharePoint failed - $($_.Exception.Message). The edit is saved locally." Warning; $false }
    })
}

# Remember where each staged predecessor came from, so Read-PredecessorModel can fetch it on first touch.
$script:SPPredMap = @{}
function Register-SPPredecessor { param([string]$LocalPath, [string]$SPRelPath) $script:SPPredMap["$LocalPath".ToLower()] = $SPRelPath }
function Get-SPPredecessorSource { param([string]$LocalPath) return $script:SPPredMap["$LocalPath".ToLower()] }

##############################################################
# OVERRIDES - capture the originals first, then replace. With the feature off, the originals run verbatim,
# so the UNC behaviour is bit-for-bit unchanged and this file is inert.
##############################################################
if (Get-Command Find-SourceFolder -ErrorAction SilentlyContinue) {
    $script:OrigFindSourceFolder = (Get-Command Find-SourceFolder).ScriptBlock
}
if (Get-Command Get-PredecessorCandidates -ErrorAction SilentlyContinue) {
    $script:OrigGetPredecessorCandidates = (Get-Command Get-PredecessorCandidates).ScriptBlock
}
if (Get-Command Read-PredecessorModel -ErrorAction SilentlyContinue) {
    $script:OrigReadPredecessorModel = (Get-Command Read-PredecessorModel).ScriptBlock
}
if (Get-Command Get-PredecessorRoots -ErrorAction SilentlyContinue) {
    $script:OrigGetPredecessorRoots = (Get-Command Get-PredecessorRoots).ScriptBlock
}

# UNC roots are SECONDARY and entirely optional. The original ends with Where-Object { Test-Path $_ }, which
# hangs per unreachable root; this filters through the bounded probe instead, so a user with no share access
# just gets an empty list quickly instead of a frozen window.
function Get-PredecessorRoots {
    $roots = @()
    if ($script:OrigGetPredecessorRoots) {
        # Rebuild the list WITHOUT the original's blocking Test-Path: read the settings the same way it does.
        $seen = @{}
        $add = {
            param($p)
            if ("$p".Trim()) { $k = "$p".TrimEnd('\').ToLower(); if (-not $seen.ContainsKey($k)) { $seen[$k] = $true; $script:SPRootScratch.Add("$p") } }
        }
        $script:SPRootScratch = New-Object System.Collections.Generic.List[string]
        & $add (Get-Setting PredecessorPath)
        foreach ($p in @(Get-Setting 'PredecessorPaths')) { & $add $p }
        & $add '\\MNDEMUCFS120.mn-man.biz\SWDistribution-Gate\CMLib_LIVE\Apps'   # 2nd LIVE repo, as in the original
        $roots = @($script:SPRootScratch.ToArray())
    }
    return @($roots | Where-Object { Test-SPUncUsable -Path $_ })
}

# SOURCE resolution chain:  SharePoint (primary)  ->  the share the tool used before (fallback)  ->  say why not.
# Never dead-ends silently: every path out of here either returns a folder or logs exactly what was tried,
# what was missing, and what the packager should do next (add the installer by hand and carry on as usual).
function Find-SourceFolder {
    param([string]$PkgName)
    $cfg = Get-SPConfig

    if (-not ($cfg.Enabled -and $cfg.UseSourceRepo)) {
        if ($script:OrigFindSourceFolder) { return (& $script:OrigFindSourceFolder $PkgName) }
        return $null
    }

    $tried = New-Object System.Collections.Generic.List[string]

    # ---- 1. SharePoint ----------------------------------------------------------------------
    $parsed = if (Get-Command Parse-PackageName -ErrorAction SilentlyContinue) { Parse-PackageName $PkgName } else { $null }
    if ($parsed -and $parsed.IsValid) {
        $p = Get-SPSourceFolder -Parsed $parsed
        if ($p) { return $p }
        $tried.Add("SharePoint: $(if ($script:SPLastSourceReason) { $script:SPLastSourceReason } else { 'not found' })")
    } else {
        # Unparseable names can still be found on the share, which matches on folder name - so fall through.
        $tried.Add("SharePoint: '$PkgName' does not follow Vendor_App_Arch_Version-Release_Lang, so it cannot be mapped to a SharePoint path")
    }

    # ---- 2. the share the tool has always used (now the fallback) ---------------------------
    if ($cfg.UseUncSourceFallback -and $script:OrigFindSourceFolder) {
        $repo = "$(Get-Setting 'RepositoryPath')".Trim()
        if (-not $repo) {
            $tried.Add('Share: no RepositoryPath is configured in settings.json')
        } elseif (-not (Test-SPUncUsable -Path $repo)) {
            # The important distinction for the two people with no share rights: this is ACCESS, not absence.
            $tried.Add("Share: no access to $repo from this machine")
            Write-SPLog "Source fallback share is not reachable from this machine - continuing with SharePoint only." Info
        } else {
            Write-SPLog "Not in SharePoint - falling back to the share: $repo" Info
            try {
                $u = & $script:OrigFindSourceFolder $PkgName
                if ($u) { Write-SPLog "Source found on the share -> $u" Success; return $u }
                $tried.Add("Share: no folder matching '$PkgName' under $repo")
            } catch {
                $tried.Add("Share: search failed - $($_.Exception.Message)")
            }
        }
    } elseif (-not $cfg.UseUncSourceFallback) {
        $tried.Add('Share: fallback disabled (settings.json -> SharePoint.UseUncSourceFallback = false)')
    }

    # ---- 3. nowhere ---------------------------------------------------------------------------
    Write-SPLog "SOURCE NOT AVAILABLE for '$PkgName'. Tried:" Warning
    foreach ($t in $tried) { Write-SPLog "    - $t" Warning }
    Write-SPLog "Build the package the normal way: use 'Add installer(s) / source' to point at the files yourself." Warning
    return $null
}

# SharePoint is PRIMARY; the UNC repos are a best-effort EXTRA. Users without share access simply get the
# SharePoint list. Same-named package in both -> SharePoint wins (its FullName is a staging path we can fetch).
function Get-PredecessorCandidates {
    param($Parsed)
    $cfg = Get-SPConfig
    if (-not ($cfg.Enabled -and $cfg.UsePredecessorRepo)) {
        if ($script:OrigGetPredecessorCandidates) { return (& $script:OrigGetPredecessorCandidates $Parsed) }
        return @()
    }

    $merged = New-Object System.Collections.Generic.List[object]
    $seen   = @{}

    foreach ($c in @(Get-SPPredecessorCandidates -Parsed $Parsed)) {
        if ($c.SPRelPath) { Register-SPPredecessor -LocalPath $c.FullName -SPRelPath $c.SPRelPath }
        $k = "$($c.Name)".ToLower()
        if ($seen.ContainsKey($k)) { continue }
        $seen[$k] = $true
        $merged.Add($c)
    }
    $spCount = $merged.Count

    # ALWAYS say what the UNC half did. "found nothing" and "never ran" must not look the same in the log - when
    # someone reports a missing predecessor, that distinction is the whole diagnosis.
    if (-not $cfg.AlsoSearchUnc) {
        Write-SPLog "Predecessors: $spCount from SharePoint (UNC search disabled - SharePoint.AlsoSearchUnc = false)." Info
    } else {
        try {
            $roots = @(Get-PredecessorRoots)
            if (@($roots).Count -eq 0) {
                Write-SPLog "Predecessors: $spCount from SharePoint. No UNC repo is reachable from this machine - SharePoint only." Info
            } else {
                foreach ($c in @(& $script:OrigGetPredecessorCandidates $Parsed)) {
                    $k = "$($c.Name)".ToLower()
                    if ($seen.ContainsKey($k)) { continue }      # already offered from SharePoint
                    $seen[$k] = $true
                    $merged.Add($c)
                }
                $uncCount = $merged.Count - $spCount
                if ($uncCount -gt 0) { Write-SPLog "Predecessors: $spCount from SharePoint + $uncCount extra found only in the UNC repo(s)." Info }
                else               { Write-SPLog "Predecessors: $spCount from SharePoint. Searched $(@($roots).Count) UNC repo(s) too - nothing there that SharePoint did not already offer." Info }
            }
        } catch {
            Write-SPLog "UNC predecessor search failed (SharePoint results kept): $($_.Exception.Message)" Warning
        }
    }

    if ($merged.Count -eq 0) { return @() }
    return @($merged.ToArray() | Sort-Object @{e={$_.Score};Descending=$true}, @{e={$_.Ver};Descending=$true}, @{e={$_.Revision};Descending=$true})
}

function Read-PredecessorModel {
    param([string]$PackagePath, [string]$PackageName, [string]$Content)
    # Lazy materialisation: a SharePoint candidate's folder does not exist until it is actually chosen.
    if ($PackagePath -and -not $Content) {
        $spRel = Get-SPPredecessorSource -LocalPath $PackagePath
        if ($spRel -and -not (Test-Path -LiteralPath (Join-Path $PackagePath '.spcomplete'))) {
            [void](Get-SPPredecessorPackage -SPRelPath $spRel -Dest $PackagePath)
        }
    }
    if ($script:OrigReadPredecessorModel) { return (& $script:OrigReadPredecessorModel $PackagePath $PackageName $Content) }
    return $null
}
