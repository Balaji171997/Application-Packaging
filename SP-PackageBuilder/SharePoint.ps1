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
    UseSourceRepo      = $true      # replace RepositoryPath  (Find-SourceFolder)
    UsePredecessorRepo = $true      # SharePoint becomes the PRIMARY predecessor source
    AlsoSearchUnc      = $true      # ...and still ADD anything the UNC repos offer, IF reachable. Users with no
                                    # share access lose nothing: the probe fails fast and they get SharePoint only.
}
function Get-SPConfig {
    $cfg = @{}; foreach ($k in $script:SPDefaults.Keys) { $cfg[$k] = $script:SPDefaults[$k] }
    $over = if (Get-Command Get-Setting -ErrorAction SilentlyContinue) { Get-Setting 'SharePoint' } else { $null }
    if ($over) { foreach ($p in $over.PSObject.Properties) { if ($null -ne $p.Value -and "$($p.Value)" -ne '') { $cfg[$p.Name] = $p.Value } } }
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
function Connect-PBSharePoint {
    param([switch]$Force)
    if ($script:SPConnected -and -not $Force) { return $true }
    $cfg = Get-SPConfig
    if (-not (Get-Command Connect-PnPOnline -ErrorAction SilentlyContinue)) {
        if (-not (Import-SPPnPModule -ConfiguredPath $cfg.ModulePath)) { return $false }
    }
    try {
        Connect-PnPOnline -Url $cfg.SiteUrl -ClientId $cfg.ClientId -Interactive -ErrorAction Stop
        $script:SPConnected = $true
        Write-SPLog "SharePoint connected: $($cfg.SiteUrl)" Success
        return $true
    } catch {
        Write-SPLog "SharePoint connect failed: $($_.Exception.Message)" Error
        return $false
    }
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
    return 'C:\temp\PackageBuilder\Temp'
}

# Download a file list into $Dest, preserving RelInside structure. Returns the count downloaded.
function Invoke-SPDownload {
    param([object[]]$Files, [string]$Dest, [string]$Activity = 'Fetching from SharePoint')
    if (-not $Files -or @($Files).Count -eq 0) { return 0 }
    if (-not (Test-Path -LiteralPath $Dest)) { New-Item -Path $Dest -ItemType Directory -Force | Out-Null }
    $n = 0; $ok = 0; $total = @($Files).Count
    foreach ($f in $Files) {
        $n++
        $sub = Split-Path $f.RelInside -Parent
        $dir = if ($sub) { Join-Path $Dest $sub } else { $Dest }
        # -LiteralPath: real filenames here contain brackets ("...for MAN [3dxWare].docx") and [ ] are wildcards.
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        if (Get-Command Set-PBProgress -ErrorAction SilentlyContinue) {
            Set-PBProgress -Percent ([int](($n / $total) * 100)) -Status "$Activity ($n/$total)"
        }
        try { Get-PnPFile -Url $f.ServerUrl -Path $dir -FileName $f.Name -AsFile -Force -ErrorAction Stop; $ok++ }
        catch { Write-SPLog "Download failed '$($f.RelInside)': $($_.Exception.Message)" Warning }
    }
    # Strip Mark-of-the-Web so staged installers launch cleanly (same reason PB unblocks extracted zips).
    if (Get-Command Unblock-PBPath -ErrorAction SilentlyContinue) { try { Unblock-PBPath -Path $Dest } catch {} }
    else { Get-ChildItem -LiteralPath $Dest -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { try { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue } catch {} } }
    return $ok
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
# Download <Version>/source + <Version>/doc into a local staging folder; return that path (or $null).
function Get-SPSourceFolder {
    param([Parameter(Mandatory)]$Parsed)
    if (-not (Connect-PBSharePoint)) { return $null }
    $cfg = Get-SPConfig
    $lib = $cfg.Library

    $vendor = Find-SPChildFolder -ParentRel $lib -Want $Parsed.Vendor
    if (-not $vendor) { Write-SPLog "SharePoint: vendor '$($Parsed.Vendor)' not found." Warning; return $null }
    $app = Find-SPChildFolder -ParentRel "$lib/$vendor" -Want $Parsed.AppName
    if (-not $app) { Write-SPLog "SharePoint: app '$($Parsed.AppName)' not found under '$vendor'." Warning; return $null }
    $wantVer = Get-SPVersionFolderName $Parsed
    $ver = Find-SPChildFolder -ParentRel "$lib/$vendor/$app" -Want $wantVer
    if (-not $ver) { Write-SPLog "SharePoint: version folder '$wantVer' not found under '$vendor/$app'." Warning; return $null }

    $verRel = "$lib/$vendor/$app/$ver"
    $kids = Get-SPItems -RelUrl $verRel
    $files = New-Object System.Collections.Generic.List[object]

    foreach ($sub in @('source','doc')) {
        $hit = $kids | Where-Object { (Test-SPFolder $_) -and $_.Name -ieq $sub } | Select-Object -First 1
        if ($hit) { foreach ($f in (Get-SPFilesRecursive -RelUrl "$verRel/$($hit.Name)" -RelInside $hit.Name)) { $files.Add($f) } }
    }
    if ($files.Count -eq 0) {
        # "dumped straight into the version folder" case: loose files, minus ticket refs.
        foreach ($f in ($kids | Where-Object { -not (Test-SPFolder $_) -and $_.Name -notmatch '^RITM\d+\s*\.txt$' -and $_.Name -notlike '~$*' })) {
            $size = 0; try { $size = [int64]$f.Length } catch {}
            $files.Add([pscustomobject]@{ ServerUrl = "$($cfg.SitePath)/$verRel/$($f.Name)"; RelInside = $f.Name; Name = $f.Name; Size = $size })
        }
    }
    if ($files.Count -eq 0) { Write-SPLog "SharePoint: no source content in $verRel" Warning; return $null }

    $arr   = $files.ToArray()
    $bytes = [int64](($arr | Measure-Object -Property Size -Sum).Sum)
    $stage = Join-Path (Get-SPStageRoot) ("spsrc_" + [guid]::NewGuid().ToString('N').Substring(0,8))
    Write-SPLog ("SharePoint source: {0} file(s), {1:N1} MB from {2}" -f @($arr).Count, ($bytes/1MB), $verRel)
    $got = Invoke-SPDownload -Files $arr -Dest $stage -Activity 'Fetching source from SharePoint'
    if ($got -eq 0) { return $null }
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
    param([string]$Path, [int]$TimeoutMs = 1500)
    if (-not "$Path".Trim()) { return $false }
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

function Find-SourceFolder {
    param([string]$PkgName)
    $cfg = Get-SPConfig
    if ($cfg.Enabled -and $cfg.UseSourceRepo) {
        $parsed = if (Get-Command Parse-PackageName -ErrorAction SilentlyContinue) { Parse-PackageName $PkgName } else { $null }
        if ($parsed -and $parsed.IsValid) {
            $p = Get-SPSourceFolder -Parsed $parsed
            if ($p) { return $p }
            Write-SPLog "SharePoint source not found for '$PkgName'." Warning
            return $null
        }
        Write-SPLog "'$PkgName' does not parse - cannot map to a SharePoint path." Warning
        return $null
    }
    if ($script:OrigFindSourceFolder) { return (& $script:OrigFindSourceFolder $PkgName) }
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

    if ($cfg.AlsoSearchUnc) {
        try {
            foreach ($c in @(& $script:OrigGetPredecessorCandidates $Parsed)) {
                $k = "$($c.Name)".ToLower()
                if ($seen.ContainsKey($k)) { continue }      # already offered from SharePoint
                $seen[$k] = $true
                $merged.Add($c)
            }
            $uncCount = $merged.Count - $spCount
            if ($uncCount -gt 0) { Write-SPLog "Predecessors: $spCount from SharePoint + $uncCount extra from the UNC repos." Info }
        } catch {
            Write-SPLog "UNC predecessor search skipped: $($_.Exception.Message)" Info
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
