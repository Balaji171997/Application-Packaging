# Intune.ps1 - everything that talks to Graph or shapes the data:
# auth, REST plumbing, the app pull, the audit-log cache, Notes parsing, snapshots and history.

$script:GraphBase       = 'https://graph.microsoft.com/beta'
$script:LogSink         = $null
$script:LogFile         = $null
$script:CancelRequested = $false

function Write-Log {
    param([string]$Message, [ValidateSet('Info','Success','Warning','Error')][string]$Level = 'Info')
    $line = '{0}  [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    if ($script:LogFile) { try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 } catch {} }
    if ($script:LogSink) { try { & $script:LogSink $Message $Level } catch {} }
}

# Two traps this exists to kill:
#   1. @($null) is a ONE-element array containing $null, so .Count lies about "is there anything".
#   2. `return $someArray` UNWRAPS a one-element array into the bare object, so a filter matching
#      exactly one app handed the DataGrid a PSCustomObject instead of a collection - and crashed it.
# `return ,$array` wraps once so the pipeline's unwrap hands back the array itself. Every function in
# this file that returns a collection uses that form.
function AsArray {
    param($Value)
    if ($null -eq $Value) { return ,@() }
    $out = New-Object 'System.Collections.Generic.List[object]'
    if ($Value -is [string]) { [void]$out.Add($Value) }
    elseif ($Value -is [System.Collections.IEnumerable]) { foreach ($v in $Value) { if ($null -ne $v) { [void]$out.Add($v) } } }
    else { [void]$out.Add($Value) }
    return ,$out.ToArray()
}

function Get-P { param($Obj, [string]$Name) if ($null -eq $Obj) { return $null } try { return $Obj.$Name } catch { return $null } }
function ConvertTo-ShortType { param([string]$OdataType) return ("$OdataType" -replace '^#microsoft\.graph\.', '') }

# --- auth -------------------------------------------------------------------------------------------
function Set-GraphProxy {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
    try {
        $p = [System.Net.WebRequest]::GetSystemWebProxy()
        $p.Credentials = [System.Net.CredentialCache]::DefaultCredentials
        [System.Net.WebRequest]::DefaultWebProxy = $p
    } catch { Write-Log "Could not resolve the system proxy ($($_.Exception.Message)); trying direct." Warning }
}

# MSAL.PS compiles internal C# that the CLR refuses to build from a UNC path - stage it locally first.
function Get-LocalModuleManifest {
    param([string]$ManifestPath, [string]$CacheRoot)
    if (-not $ManifestPath -or ($ManifestPath -notmatch '^\\\\')) { return $ManifestPath }
    try {
        $srcDir = Split-Path -Parent $ManifestPath
        $name   = Split-Path -Leaf $srcDir
        $cache  = Join-Path $CacheRoot $name
        $dst    = Join-Path $cache (Split-Path -Leaf $ManifestPath)
        $fresh  = (Test-Path $dst) -and ((Get-Item $dst).LastWriteTimeUtc -ge (Get-Item $ManifestPath).LastWriteTimeUtc)
        if (-not $fresh) {
            if (Test-Path $cache) { Remove-Item $cache -Recurse -Force -ErrorAction SilentlyContinue }
            Copy-Item -LiteralPath $srcDir -Destination $cache -Recurse -Force -ErrorAction Stop
            Get-ChildItem $cache -Recurse -File | ForEach-Object { try { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue } catch {} }
            Write-Log "Staged module '$name' locally for import."
        }
        if (Test-Path $dst) { return $dst }
    } catch { Write-Log "Could not stage module locally: $($_.Exception.Message)." Warning }
    return $ManifestPath
}

function Connect-Intune {
    param([Parameter(Mandatory)][string]$TenantId, [string]$ModulePath, [string]$CacheRoot)
    Set-GraphProxy
    if (-not (Get-Command Connect-MSIntuneGraph -ErrorAction SilentlyContinue)) {
        $msal = $null; $iwa = $null
        foreach ($dir in @($ModulePath) | Where-Object { $_ -and (Test-Path $_) }) {
            if (-not $msal) { $msal = Get-ChildItem -Path $dir -Recurse -Filter 'MSAL.PS.psd1'        -ErrorAction SilentlyContinue | Select-Object -First 1 }
            if (-not $iwa)  { $iwa  = Get-ChildItem -Path $dir -Recurse -Filter 'IntuneWin32App.psd1' -ErrorAction SilentlyContinue | Select-Object -First 1 }
        }
        if (-not $msal -or -not $iwa) {
            Write-Log "MSAL.PS + IntuneWin32App not found under '$ModulePath'. Fix settings.json -> ModulePath." Error
            return $false
        }
        try {
            Import-Module (Get-LocalModuleManifest $msal.FullName $CacheRoot) -ErrorAction Stop   # MSAL.PS first
            Import-Module (Get-LocalModuleManifest $iwa.FullName  $CacheRoot) -ErrorAction Stop
        } catch { Write-Log "Importing the Intune modules failed: $($_.Exception.Message)" Error; return $false }
    }
    $tenant = "$TenantId".Trim()
    if (-not $tenant) { Write-Log 'No tenant set in settings.json -> TenantId.' Error; return $false }
    try {
        # Connect-MSIntuneGraph reports failures as warnings and only sets the globals on success.
        $warns = $null
        Connect-MSIntuneGraph -TenantID $tenant -WarningVariable warns -WarningAction SilentlyContinue | Out-Null
        if (-not $Global:AuthenticationHeader -and -not $Global:AccessToken) {
            $why = if ($warns) { ($warns | ForEach-Object { "$_" }) -join ' | ' } else { 'no token (cancelled, or blocked by Conditional Access).' }
            Write-Log "Sign-in failed - $why" Error
            return $false
        }
        Write-Log "Connected to '$tenant'." Success
        return $true
    } catch { Write-Log "Connect failed: $($_.Exception.Message)" Error; return $false }
}

function Get-AuthHeader {
    if ($Global:AccessToken -and $Global:AccessToken.ExpiresOn) {
        $exp = try { $Global:AccessToken.ExpiresOn.LocalDateTime } catch { $null }
        if ($exp -and (Get-Date) -ge $exp.AddMinutes(-5)) {
            try { Connect-MSIntuneGraph -TenantID $Global:AccessTokenTenantID -Refresh -ErrorAction Stop | Out-Null } catch {}
        }
    }
    if ($Global:AuthenticationHeader -and $Global:AuthenticationHeader.Authorization) { return @{ Authorization = "$($Global:AuthenticationHeader.Authorization)" } }
    if ($Global:AccessToken) { return @{ Authorization = "Bearer $($Global:AccessToken.AccessToken)" } }
    return $null
}

function Invoke-GraphGet {
    param([Parameter(Mandatory)][string]$Uri, [string]$Method = 'GET', $Body)
    $hdr = Get-AuthHeader
    if (-not $hdr) { throw 'Not connected to Intune.' }
    $p = @{ Method = $Method; Uri = $Uri; Headers = $hdr; ErrorAction = 'Stop' }
    if ($Body) { $p['Body'] = $(if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 12 }); $p['ContentType'] = 'application/json' }
    $reauthed = $false
    $maxTry   = 7
    for ($try = 1; $try -le $maxTry; $try++) {
        try { return Invoke-RestMethod @p }
        catch {
            $sc = $null; try { $sc = [int]$_.Exception.Response.StatusCode } catch {}
            $detail = "$($_.ErrorDetails.Message)"
            if ($sc -eq 401 -and -not $reauthed) {
                $reauthed = $true
                $h = Get-AuthHeader
                if ($h) { $p['Headers'] = $h; continue }
            }
            if ($try -ge $maxTry -or ($sc -and $sc -lt 500 -and $sc -ne 429)) {
                if ($detail) { $detail = ($detail -replace '\s+', ' ').Trim(); if ($detail.Length -gt 300) { $detail = $detail.Substring(0, 300) } }
                throw "Graph $Method $($Uri -replace '^https://graph.microsoft.com','') -> HTTP $sc$(if ($detail) { ": $detail" })"
            }
            $wait = [Math]::Min(60, [Math]::Pow(2, $try))
            if ($sc -eq 429) {
                try { $ra = [int]"$($_.Exception.Response.Headers['Retry-After'])"; if ($ra -gt 0) { $wait = [Math]::Min(120, $ra) } } catch {}
                Write-Log "Throttled by Graph (429). Waiting $wait s (retry $try of $maxTry)..." Warning
            }
            Start-Sleep -Seconds $wait
        }
    }
}

function Invoke-GraphAll {
    param([Parameter(Mandatory)][string]$Uri, [scriptblock]$OnPage, [switch]$TolerateFailure)
    $out  = New-Object 'System.Collections.Generic.List[object]'
    $next = $Uri
    $page = 0
    while ($next) {
        $r = $null
        try { $r = Invoke-GraphGet -Uri $next }
        catch {
            # Losing 20 collected pages because page 21 threw is worse than returning 20 pages.
            if ($TolerateFailure -and $out.Count -gt 0) {
                Write-Log "Paged read stopped after $page page(s) / $($out.Count) item(s): $($_.Exception.Message)" Warning
                break
            }
            throw
        }
        $page++
        if ($null -ne $r.value) { foreach ($i in $r.value) { [void]$out.Add($i) } }
        elseif ($r)             { [void]$out.Add($r) }
        if ($OnPage) { try { & $OnPage $out.Count } catch {} }
        if ($script:CancelRequested) { break }
        $next = $r.'@odata.nextLink'
    }
    return ,$out.ToArray()
}

# --- readable rule text -----------------------------------------------------------------------------
function ConvertTo-DetectionText {
    param($Rule)
    $t = ConvertTo-ShortType (Get-P $Rule '@odata.type')
    switch -Regex ($t) {
        'RegistryDetection'   { "Registry: $(Get-P $Rule 'keyPath')$(if (Get-P $Rule 'valueName') { " -> $(Get-P $Rule 'valueName')" }) [$(Get-P $Rule 'detectionType') $(Get-P $Rule 'operator') $(Get-P $Rule 'detectionValue')]" }
        'FileSystemDetection' { "File: $(Get-P $Rule 'path')\$(Get-P $Rule 'fileOrFolderName') [$(Get-P $Rule 'detectionType') $(Get-P $Rule 'operator') $(Get-P $Rule 'detectionValue')]" }
        'ProductCodeDetection'{ "MSI product code: $(Get-P $Rule 'productCode')" }
        'PowerShellScriptDetection' { 'PowerShell script detection' }
        default               { $t }
    }
}
function ConvertTo-RequirementText {
    param($Rule)
    $t = ConvertTo-ShortType (Get-P $Rule '@odata.type')
    switch -Regex ($t) {
        'RegistryRequirement'   { "Registry: $(Get-P $Rule 'keyPath') $(Get-P $Rule 'operator') $(Get-P $Rule 'detectionValue')" }
        'FileSystemRequirement' { "File: $(Get-P $Rule 'path')\$(Get-P $Rule 'fileOrFolderName')" }
        'PowerShellScriptRequirement' { "Script: $(Get-P $Rule 'displayName')" }
        default                 { $t }
    }
}
function ConvertTo-MinOsText {
    param($MinOs)
    if (-not $MinOs) { return '' }
    $set = @()
    foreach ($p in $MinOs.PSObject.Properties) { if ($p.Value -eq $true) { $set += ($p.Name -replace '^v', '') } }
    return ($set -join ', ')
}

function Resolve-GroupNames {
    param([string[]]$GroupIds)
    $map = @{}
    $ids = @($GroupIds | Where-Object { $_ } | Select-Object -Unique)
    if ($ids.Count -eq 0) { return $map }
    for ($i = 0; $i -lt $ids.Count; $i += 900) {
        $chunk = $ids[$i..([Math]::Min($i + 899, $ids.Count - 1))]
        try {
            $r = Invoke-GraphGet -Uri "$script:GraphBase/directoryObjects/getByIds" -Method POST -Body @{ ids = $chunk; types = @('group') }
            foreach ($g in $r.value) { $map[$g.id] = $g.displayName }
        } catch {
            Write-Log "Could not resolve group names ($($_.Exception.Message)). Showing IDs." Warning
            break
        }
    }
    return $map
}

function ConvertTo-AssignmentRows {
    param($App, [hashtable]$GroupMap)
    $rows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($a in (AsArray (Get-P $App 'assignments'))) {
        $target = Get-P $a 'target'
        $tt     = ConvertTo-ShortType (Get-P $target '@odata.type')
        $gid    = Get-P $target 'groupId'
        $name = switch -Regex ($tt) {
            'allLicensedUsers' { 'All users' }
            'allDevices'       { 'All devices' }
            'exclusionGroup'   { "EXCLUDE: $(if ($GroupMap[$gid]) { $GroupMap[$gid] } else { $gid })" }
            default            { if ($GroupMap[$gid]) { $GroupMap[$gid] } else { $gid } }
        }
        [void]$rows.Add([pscustomobject]@{
            Intent = Get-P $a 'intent'; Target = $name; GroupId = $gid; TargetType = $tt
            FilterType = Get-P $target 'deviceAndAppManagementAssignmentFilterType'
        })
    }
    return ,$rows.ToArray()
}

# --- the app pull -------------------------------------------------------------------------------------
function Get-Win32AppInventory {
    param([object[]]$Previous, [switch]$Full, [switch]$IncludeRelationships, [scriptblock]$Progress)
    $report = { param($t, $p) if ($Progress) { try { & $Progress $t $p } catch {} } }

    # Only the per-app EXTRAS are ever skipped. The app list and its assignments are re-read every
    # sync, because an assignment-only edit does NOT move lastModifiedDateTime.
    $prevMap = @{}
    if (-not $Full) { foreach ($p in (AsArray $Previous)) { if ($p.Id) { $prevMap[$p.Id] = $p } } }

    & $report 'Fetching Win32 apps...' 5
    $filter = [uri]::EscapeDataString("isof('microsoft.graph.win32LobApp')")
    $uri    = "$script:GraphBase/deviceAppManagement/mobileApps?`$filter=$filter&`$expand=assignments&`$top=50"
    $apps   = $null
    try { $apps = Invoke-GraphAll -Uri $uri -OnPage { param($n) & $report "Fetching Win32 apps... ($n so far)" 10 } }
    catch {
        Write-Log "Combined filter+expand failed ($($_.Exception.Message)); retrying without expand." Warning
        $apps = Invoke-GraphAll -Uri "$script:GraphBase/deviceAppManagement/mobileApps?`$filter=$filter&`$top=50"
        foreach ($a in $apps) {
            if ($script:CancelRequested) { break }
            try { $a | Add-Member -NotePropertyName assignments -NotePropertyValue (Invoke-GraphAll -Uri "$script:GraphBase/deviceAppManagement/mobileApps/$($a.id)/assignments") -Force } catch {}
        }
    }
    $apps = AsArray $apps
    Write-Log "Found $($apps.Count) Win32 app(s)." Success

    & $report 'Resolving assignment group names...' 25
    $gids = New-Object 'System.Collections.Generic.List[object]'
    foreach ($a in $apps) { foreach ($asg in (AsArray (Get-P $a 'assignments'))) { $g = Get-P (Get-P $asg 'target') 'groupId'; if ($g) { [void]$gids.Add($g) } } }
    $groupMap = Resolve-GroupNames -GroupIds ([string[]]$gids.ToArray())

    $rows = New-Object 'System.Collections.Generic.List[object]'
    $n = 0
    foreach ($a in $apps) {
        if ($script:CancelRequested) { break }
        $n++
        if ($n % 25 -eq 0 -or $n -eq $apps.Count) { & $report "Processing apps ($n of $($apps.Count))" (30 + [int](55 * $n / [Math]::Max(1, $apps.Count))) }

        $asg  = ConvertTo-AssignmentRows -App $a -GroupMap $groupMap
        $inst = Get-P $a 'installExperience'

        $prevApp   = $prevMap[$a.id]
        $unchanged = $prevApp -and ("$($prevApp.LastModifiedDateTime)" -eq "$(Get-P $a 'lastModifiedDateTime')")
        $relRows   = New-Object 'System.Collections.Generic.List[object]'

        if ($unchanged) {
            foreach ($r in (AsArray $prevApp.Relationships)) { [void]$relRows.Add($r) }
        }
        elseif ($IncludeRelationships -and (((Get-P $a 'supersedingAppCount') -gt 0) -or ((Get-P $a 'supersededAppCount') -gt 0) -or ((Get-P $a 'dependentAppCount') -gt 0))) {
            $rels = $null
            try { $rels = Invoke-GraphAll -Uri "$script:GraphBase/deviceAppManagement/mobileApps/$($a.id)/relationships" } catch {}
            foreach ($r in (AsArray $rels)) {
                [void]$relRows.Add([pscustomobject]@{
                    Kind = ConvertTo-ShortType (Get-P $r '@odata.type'); Direction = Get-P $r 'targetType'
                    TargetName = Get-P $r 'targetDisplayName'; TargetVer = Get-P $r 'targetDisplayVersion'
                })
            }
        }

        [void]$rows.Add([pscustomobject]@{
            Id                  = $a.id
            DisplayName         = $a.displayName
            DisplayVersion      = Get-P $a 'displayVersion'
            Publisher           = Get-P $a 'publisher'
            Developer           = Get-P $a 'developer'
            Owner               = Get-P $a 'owner'
            Notes               = Get-P $a 'notes'
            Description         = Get-P $a 'description'
            SetupFilePath       = Get-P $a 'setupFilePath'
            InstallCommandLine  = Get-P $a 'installCommandLine'
            UninstallCommandLine= Get-P $a 'uninstallCommandLine'
            RunAsAccount        = Get-P $inst 'runAsAccount'
            RestartBehavior     = Get-P $inst 'deviceRestartBehavior'
            MinimumOS           = ConvertTo-MinOsText (Get-P $a 'minimumSupportedOperatingSystem')
            SizeMB              = $(if (Get-P $a 'size') { [math]::Round((Get-P $a 'size') / 1MB, 1) } else { $null })
            ContentVersion      = Get-P $a 'committedContentVersion'
            CreatedDateTime     = Get-P $a 'createdDateTime'
            LastModifiedDateTime= Get-P $a 'lastModifiedDateTime'
            PublishingState     = Get-P $a 'publishingState'
            ScopeTags           = ((AsArray (Get-P $a 'roleScopeTagIds')) -join ', ')
            DetectionRules      = @((AsArray (Get-P $a 'detectionRules'))   | ForEach-Object { ConvertTo-DetectionText $_ })
            RequirementRules    = @((AsArray (Get-P $a 'requirementRules')) | ForEach-Object { ConvertTo-RequirementText $_ })
            Assignments         = $asg
            AssignmentSummary   = ((AsArray $asg | ForEach-Object { "$($_.Intent): $($_.Target)" }) -join '; ')
            Relationships       = $relRows.ToArray()
            SupersededByCount   = Get-P $a 'supersedingAppCount'
        })
    }
    & $report 'Apps collected.' 88
    return ,$rows.ToArray()
}

# --- audit cache ---------------------------------------------------------------------------------------
# Graph exposes no "created by" on the app itself. The ONLY source is the audit log, which Intune keeps
# for about a year. We walk it once in dated chunks, save after every chunk (so a throttle or a cancel
# never loses collected work), and from then on only fetch what is new.

function Get-AuditCache {
    param([string]$Path)
    $cache = @{ BackfilledFromUtc = $null; LastSyncUtc = $null; Apps = @{} }
    if (-not (Test-Path $Path)) { return $cache }
    try {
        $j = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        $cache.BackfilledFromUtc = "$($j.BackfilledFromUtc)"
        $cache.LastSyncUtc       = "$($j.LastSyncUtc)"
        if ($j.Apps) { foreach ($p in $j.Apps.PSObject.Properties) { $cache.Apps[$p.Name] = $p.Value } }
    } catch { Write-Log 'AuditCache.json unreadable - starting a fresh one.' Warning }
    return $cache
}

function Save-AuditCache {
    param($Cache, [string]$Path)
    try {
        $obj = [pscustomobject]@{
            BackfilledFromUtc = $Cache.BackfilledFromUtc
            LastSyncUtc       = $Cache.LastSyncUtc
            Apps              = [pscustomobject]$Cache.Apps
        }
        $json = $obj | ConvertTo-Json -Depth 8 -Compress
        [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding($false)))
    } catch { Write-Log "Could not save the audit cache: $($_.Exception.Message)" Warning }
}

# Fold one page of audit events into the cache.
function Add-AuditEventsToCache {
    param($Cache, [object[]]$Events)
    $added = 0
    foreach ($e in (AsArray $Events)) {
        if ("$($e.category)" -notmatch 'Application') { continue }
        $actor  = Get-P $e 'actor'
        $who    = Get-P $actor 'userPrincipalName'
        if (-not $who) { $who = Get-P $actor 'applicationDisplayName' }
        $whoId  = Get-P $actor 'userId'
        $when   = "$(Get-P $e 'activityDateTime')"
        $op     = "$(Get-P $e 'activityOperationType')"
        $act    = "$(Get-P $e 'activityType')"

        foreach ($res in (AsArray (Get-P $e 'resources'))) {
            $rid = Get-P $res 'resourceId'
            if (-not $rid) { continue }

            $props = New-Object 'System.Collections.Generic.List[object]'
            foreach ($mp in (AsArray (Get-P $res 'modifiedProperties'))) {
                $old = "$(Get-P $mp 'oldValue')"; $new = "$(Get-P $mp 'newValue')"
                if ($old -eq $new) { continue }
                [void]$props.Add([pscustomobject]@{ Property = "$(Get-P $mp 'displayName')"; Old = $old; New = $new })
            }

            if (-not $Cache.Apps.ContainsKey($rid)) {
                $Cache.Apps[$rid] = [pscustomobject]@{
                    CreatedBy = ''; CreatedById = ''; CreatedWhen = ''
                    LastChangedBy = ''; LastChangedWhen = ''; Events = @()
                }
            }
            $rec = $Cache.Apps[$rid]

            $evs = New-Object 'System.Collections.Generic.List[object]'
            foreach ($x in (AsArray $rec.Events)) { [void]$evs.Add($x) }
            # Same event can arrive twice across overlapping windows.
            $dupe = $false
            foreach ($x in $evs) { if ("$($x.When)" -eq $when -and "$($x.What)" -eq $act) { $dupe = $true; break } }
            if (-not $dupe) {
                [void]$evs.Add([pscustomobject]@{
                    When = $when; Who = "$who"; WhoId = "$whoId"; Operation = $op; What = $act
                    Changes = ((AsArray $props.ToArray() | ForEach-Object { "$($_.Property): $($_.Old) -> $($_.New)" }) -join ' | ')
                })
                $added++
            }
            # Keep the file sane on a busy app.
            $rec.Events = @($evs.ToArray() | Sort-Object { "$($_.When)" } -Descending | Select-Object -First 60)

            if ($op -match 'Create' -and $when) {
                # Oldest Create wins - that is the real birth of the app.
                if (-not $rec.CreatedWhen -or ($when -lt "$($rec.CreatedWhen)")) {
                    $rec.CreatedBy = "$who"; $rec.CreatedById = "$whoId"; $rec.CreatedWhen = $when
                }
            }
            if (-not $rec.LastChangedWhen -or ($when -gt "$($rec.LastChangedWhen)")) {
                $rec.LastChangedBy = "$who"; $rec.LastChangedWhen = $when
            }
        }
    }
    return $added
}

function Update-AuditCache {
    param([string]$Path, [int]$BackfillDays = 400, [int]$ChunkDays = 30, [scriptblock]$Progress)
    $report = { param($t, $p) if ($Progress) { try { & $Progress $t $p } catch {} } }
    $cache  = Get-AuditCache -Path $Path
    $nowUtc = (Get-Date).ToUniversalTime()

    # First run walks backwards to BackfillDays. Later runs only fetch since the last successful sync,
    # with a day of overlap so nothing falls through the gap.
    $windows = New-Object 'System.Collections.Generic.List[object]'
    if (-not $cache.BackfilledFromUtc) {
        $end = $nowUtc
        $cut = $nowUtc.AddDays(-[Math]::Abs($BackfillDays))
        while ($end -gt $cut) {
            $start = $end.AddDays(-[Math]::Abs($ChunkDays))
            if ($start -lt $cut) { $start = $cut }
            [void]$windows.Add(@{ From = $start; To = $end })
            $end = $start
        }
    } else {
        $from = $nowUtc.AddDays(-2)
        try { $from = ([datetime]$cache.LastSyncUtc).AddDays(-1) } catch {}
        [void]$windows.Add(@{ From = $from; To = $nowUtc })
    }

    $total = $windows.Count
    $i = 0
    $totalAdded = 0
    foreach ($w in $windows) {
        if ($script:CancelRequested) { Write-Log 'Audit backfill cancelled - progress kept.' Warning; break }
        $i++
        $f = $w.From.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $t = $w.To.ToString('yyyy-MM-ddTHH:mm:ssZ')
        & $report "Reading audit log $($w.From.ToString('yyyy-MM-dd')) to $($w.To.ToString('yyyy-MM-dd'))  ($i of $total)" (88 + [int](10 * $i / [Math]::Max(1, $total)))

        $flt = [uri]::EscapeDataString("activityDateTime gt $f and activityDateTime le $t")
        $ev  = @()
        try { $ev = Invoke-GraphAll -Uri "$script:GraphBase/deviceManagement/auditEvents?`$filter=$flt&`$top=1000" -TolerateFailure }
        catch {
            # Some tenants reject the compound range filter - fall back to a single lower bound.
            try {
                $flt2 = [uri]::EscapeDataString("activityDateTime gt $f")
                $ev = Invoke-GraphAll -Uri "$script:GraphBase/deviceManagement/auditEvents?`$filter=$flt2&`$top=1000" -TolerateFailure
            } catch {
                Write-Log "Audit window $f..$t failed: $($_.Exception.Message)" Warning
                continue
            }
        }
        $totalAdded += (Add-AuditEventsToCache -Cache $cache -Events $ev)
        # Save after EVERY window - a throttle later must not cost us what we already have.
        $cache.LastSyncUtc = $nowUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
        if (-not $cache.BackfilledFromUtc -and $i -eq $total) { $cache.BackfilledFromUtc = $w.From.ToString('yyyy-MM-ddTHH:mm:ssZ') }
        Save-AuditCache -Cache $cache -Path $Path
    }

    $known = @($cache.Apps.Keys).Count
    Write-Log "Audit cache: $totalAdded new event(s); creator known for $known app(s)." Success
    return $cache
}

function Add-AuditToApps {
    param([object[]]$Apps, $Cache)
    foreach ($a in (AsArray $Apps)) {
        $rec = $null
        if ($Cache -and $Cache.Apps.ContainsKey($a.Id)) { $rec = $Cache.Apps[$a.Id] }
        $a | Add-Member -NotePropertyName CreatedBy       -NotePropertyValue "$(Get-P $rec 'CreatedBy')"       -Force
        $a | Add-Member -NotePropertyName CreatedById     -NotePropertyValue "$(Get-P $rec 'CreatedById')"     -Force
        $a | Add-Member -NotePropertyName LastChangedBy   -NotePropertyValue "$(Get-P $rec 'LastChangedBy')"   -Force
        $a | Add-Member -NotePropertyName LastChangedWhen -NotePropertyValue "$(Get-P $rec 'LastChangedWhen')" -Force
        $a | Add-Member -NotePropertyName AuditEvents     -NotePropertyValue (AsArray (Get-P $rec 'Events'))   -Force
    }
    return $Apps
}

# --- Notes parsing + classification ----------------------------------------------------------------------
function Split-AppNameTokens {
    param([string]$Name)
    $n = ("$Name" -replace '[_\-\.\(\)\[\]]+', ' ').Trim()
    return @($n -split '\s+' | Where-Object { $_ })
}

# A test marker must be a WHOLE TOKEN at the FIRST or LAST position - never mid-name. That keeps
# "Attestation Client", "Testo Software", "Contest Manager" out of the Test bucket.
function Test-EdgeToken {
    param([string]$Name, [string[]]$Patterns)
    $tok = Split-AppNameTokens $Name
    if ($tok.Count -eq 0) { return $false }
    $edges = @($tok[0])
    if ($tok.Count -gt 1) { $edges += $tok[-1] }
    foreach ($e in $edges) { foreach ($p in $Patterns) { if ($e -match $p) { return $true } } }
    return $false
}

function Get-AppKind {
    param($App, $Cfg)
    $ver = "$($App.DisplayVersion)".Trim()
    foreach ($w in (AsArray $Cfg.WingetVersionValues)) { if ($ver -and $ver -match $w) { return 'Winget' } }
    $tok = Split-AppNameTokens "$($App.DisplayName)"
    if ($tok.Count -gt 0) { foreach ($p in (AsArray $Cfg.UpdPatterns)) { if ($tok[-1] -match $p) { return 'UPD' } } }
    if (Test-EdgeToken -Name "$($App.DisplayName)" -Patterns (AsArray $Cfg.TestPatterns)) { return 'Test' }
    return 'Standard'
}

function Get-NormalisedStage {
    param([string]$Stage)
    $s = "$Stage".Trim()
    if (-not $s) { return 'Not recorded' }
    switch -Regex ($s) {
        '^(?i)live$'       { return 'LIVE' }
        '^(?i)retired$'    { return 'RETIRED' }
        '^(?i)sat$'        { return 'SAT' }
        '^(?i)uat$'        { return 'UAT' }
        '^(?i)faileduat$'  { return 'FailedUAT' }
        '^(?i)prerollout$' { return 'PreRollout' }
        '^(?i)pilot$'      { return 'Pilot' }
        default            { return $s }
    }
}

function Get-CreationMethod {
    param([string]$Text, $Cfg)
    $t = "$Text".Trim()
    if (-not $t -or $t -eq '.') { return 'Manual (no note)' }
    foreach ($rule in (AsArray $Cfg.CreationMethodRules)) { if ($t -match $rule.Pattern) { return $rule.Method } }
    if ($t -match '(?i)manual') { return 'Manual (no note)' }
    return 'Other (see notes)'
}

# Notes sometimes carry their own dated trail: "[2025-01-30] Package was set to LIVE".
# For apps older than audit retention this is the only record that survives.
function Get-NoteEvents {
    param([string]$Text)
    $out = New-Object 'System.Collections.Generic.List[object]'
    if (-not "$Text") { return ,$out.ToArray() }
    foreach ($x in [regex]::Matches("$Text", '\[(\d{4}-\d{2}-\d{2})\]\s*([^\[]+)')) {
        $desc = ($x.Groups[2].Value -replace '\s+', ' ').Trim()
        if ($desc) { [void]$out.Add([pscustomobject]@{ When = $x.Groups[1].Value; Who = ''; What = $desc; Source = 'App notes' }) }
    }
    return ,$out.ToArray()
}

# The Notes field is a JSON document written by the team's tooling:
#   { "notes":"Created by SCCM2Intune App Migration tool.", "managed":true,
#     "status":"OK", "rollout":"", "pilot":"", "lifecycle":"SAT" }
# 797 of 801 apps use it. Parse it; the regex rules are a fallback for the few free-text ones.
function ConvertFrom-AppNotes {
    param($App, $Cfg)
    $raw = "$($App.Notes)".Trim()
    $r = [pscustomobject]@{
        Lifecycle = 'Not recorded'; CreatedVia = 'Manual (no note)'; Status = ''; ManagedText = ''
        Pilot = ''; Rollout = ''; InnerNotes = ''; RawNotes = $raw; NoteEvents = @()
    }
    if (-not $raw) { return $r }

    if ($raw.StartsWith('{')) {
        $o = $null
        try { $o = $raw | ConvertFrom-Json } catch { $o = $null }
        if ($o) {
            $r.InnerNotes = "$($o.notes)"
            $r.Status     = "$($o.status)"
            $r.Pilot      = "$($o.pilot)"
            $r.Rollout    = "$($o.rollout)"
            if ($null -ne $o.managed -and "$($o.managed)" -ne '') { $r.ManagedText = $(if ([bool]$o.managed) { 'Managed' } else { 'Unmanaged' }) }
            $r.Lifecycle  = Get-NormalisedStage "$($o.lifecycle)"
            $r.CreatedVia = Get-CreationMethod -Text $r.InnerNotes -Cfg $Cfg
            $r.NoteEvents = Get-NoteEvents -Text $r.InnerNotes
            return $r
        }
    }
    foreach ($rule in (AsArray $Cfg.LifecycleRules)) { if ($raw -match $rule.Pattern) { $r.Lifecycle = Get-NormalisedStage $rule.Stage; break } }
    $r.InnerNotes = (($raw -split '\r?\n') | Where-Object { $_.Trim() } | Select-Object -First 1)
    $r.CreatedVia = Get-CreationMethod -Text $raw -Cfg $Cfg
    $r.NoteEvents = Get-NoteEvents -Text $raw
    return $r
}

function Add-AppClassification {
    param([object[]]$Apps, $Cfg)
    $now = Get-Date
    foreach ($a in (AsArray $Apps)) {
        $kind = Get-AppKind -App $a -Cfg $Cfg
        $n    = ConvertFrom-AppNotes -App $a -Cfg $Cfg

        $created = $null; $modified = $null
        try { if ($a.CreatedDateTime)      { $created  = [datetime]$a.CreatedDateTime } } catch {}
        try { if ($a.LastModifiedDateTime) { $modified = [datetime]$a.LastModifiedDateTime } } catch {}

        $asgCount = (AsArray $a.Assignments).Count
        $flags = New-Object 'System.Collections.Generic.List[object]'
        if ($asgCount -eq 0)                 { [void]$flags.Add('Unassigned') }
        if ($n.Lifecycle -eq 'RETIRED')      { [void]$flags.Add('Retired') }
        if ($n.Lifecycle -eq 'FailedUAT')    { [void]$flags.Add('Failed UAT') }
        if ($n.Status -and $n.Status -ne 'OK') { [void]$flags.Add("Status $($n.Status)") }
        if ([int]$a.SupersededByCount -gt 0) { [void]$flags.Add('Superseded') }

        $a | Add-Member -NotePropertyName Kind        -NotePropertyValue $kind         -Force
        $a | Add-Member -NotePropertyName Lifecycle   -NotePropertyValue $n.Lifecycle  -Force
        $a | Add-Member -NotePropertyName CreatedVia  -NotePropertyValue $n.CreatedVia -Force
        $a | Add-Member -NotePropertyName NoteStatus  -NotePropertyValue $n.Status     -Force
        $a | Add-Member -NotePropertyName ManagedText -NotePropertyValue $n.ManagedText -Force
        $a | Add-Member -NotePropertyName PilotDate   -NotePropertyValue $n.Pilot      -Force
        $a | Add-Member -NotePropertyName RolloutDate -NotePropertyValue $n.Rollout    -Force
        $a | Add-Member -NotePropertyName NotesText   -NotePropertyValue $n.InnerNotes -Force
        $a | Add-Member -NotePropertyName RawNotes    -NotePropertyValue $n.RawNotes   -Force
        $a | Add-Member -NotePropertyName NoteEvents  -NotePropertyValue $n.NoteEvents -Force
        $a | Add-Member -NotePropertyName Created     -NotePropertyValue $(if ($created)  { $created.ToString('yyyy-MM-dd') }  else { '' }) -Force
        $a | Add-Member -NotePropertyName Modified    -NotePropertyValue $(if ($modified) { $modified.ToString('yyyy-MM-dd') } else { '' }) -Force
        $a | Add-Member -NotePropertyName AgeDays     -NotePropertyValue $(if ($created)  { [int]($now - $created).TotalDays }  else { $null }) -Force
        $a | Add-Member -NotePropertyName IdleDays    -NotePropertyValue $(if ($modified) { [int]($now - $modified).TotalDays } else { $null }) -Force
        $a | Add-Member -NotePropertyName AssignmentCount -NotePropertyValue $asgCount -Force
        $a | Add-Member -NotePropertyName Flags       -NotePropertyValue ($flags.ToArray() -join ', ') -Force
    }
    return $Apps
}

# --- snapshots + history ----------------------------------------------------------------------------------
# ConvertFrom-Json emits a JSON array as ONE pipeline item on PS 5.1, so @(... | ConvertFrom-Json)
# yields a NESTED array. Assign first, then flatten.
function ConvertFrom-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    $data = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $out  = New-Object 'System.Collections.Generic.List[object]'
    foreach ($x in $data) { [void]$out.Add($x) }
    return ,$out.ToArray()
}

function Save-Snapshot {
    param([object[]]$Apps, [string]$SnapshotDir, [int]$Keep = 30)
    if (-not (Test-Path $SnapshotDir)) { New-Item -ItemType Directory -Path $SnapshotDir -Force | Out-Null }
    $file = Join-Path $SnapshotDir ('apps-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $json = ConvertTo-Json -InputObject (AsArray $Apps) -Depth 10
    [IO.File]::WriteAllText($file, $json, (New-Object Text.UTF8Encoding($false)))
    Get-ChildItem -LiteralPath $SnapshotDir -Filter 'apps-*.json' -File |
        Sort-Object Name -Descending | Select-Object -Skip $Keep | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Log "Snapshot saved: $(Split-Path -Leaf $file)"
    return $file
}

function Get-PreviousSnapshot {
    param([Parameter(Mandatory)][string]$SnapshotDir, [string]$ExcludePath)
    if (-not (Test-Path $SnapshotDir)) { return $null }
    $f = Get-ChildItem -LiteralPath $SnapshotDir -Filter 'apps-*.json' -File -ErrorAction SilentlyContinue |
         Where-Object { -not $ExcludePath -or $_.FullName -ne $ExcludePath } |
         Sort-Object Name -Descending | Select-Object -First 1
    if (-not $f) { return $null }
    try { return ConvertFrom-JsonFile -Path $f.FullName }
    catch { Write-Log "Could not read the previous snapshot: $($_.Exception.Message)" Warning; return $null }
}

$script:TrackedFields = @('DisplayVersion','Lifecycle','CreatedVia','NoteStatus','AssignmentSummary',
                          'InstallCommandLine','UninstallCommandLine','SetupFilePath','RunAsAccount',
                          'ContentVersion','Publisher','Owner','NotesText','ManagedText','PilotDate','RolloutDate')

function Compare-Snapshots {
    param([object[]]$Current, [object[]]$Previous)
    $out = New-Object 'System.Collections.Generic.List[object]'
    $prev = @{}; foreach ($p in (AsArray $Previous)) { if ($p.Id) { $prev[$p.Id] = $p } }
    $cur  = @{}; foreach ($c in (AsArray $Current))  { if ($c.Id) { $cur[$c.Id]  = $c } }
    $when = (Get-Date).ToString('s')

    foreach ($c in (AsArray $Current)) {
        if (-not $prev.ContainsKey($c.Id)) {
            [void]$out.Add([pscustomobject]@{ When = $when; AppId = $c.Id; App = $c.DisplayName; Type = 'Added'; Property = ''; Old = ''; New = '' })
            continue
        }
        $p = $prev[$c.Id]
        foreach ($f in $script:TrackedFields) {
            $o = "$($p.$f)"; $n = "$($c.$f)"
            if ($o -ne $n) {
                [void]$out.Add([pscustomobject]@{ When = $when; AppId = $c.Id; App = $c.DisplayName; Type = 'Modified'; Property = $f; Old = $o; New = $n })
            }
        }
    }
    foreach ($p in (AsArray $Previous)) {
        if ($p.Id -and -not $cur.ContainsKey($p.Id)) {
            [void]$out.Add([pscustomobject]@{ When = $when; AppId = $p.Id; App = $p.DisplayName; Type = 'Removed'; Property = ''; Old = ''; New = '' })
        }
    }
    return ,$out.ToArray()
}

function Get-ChangeLog {
    param([string]$LogPath)
    if (-not (Test-Path $LogPath)) { return @() }
    try { return ConvertFrom-JsonFile -Path $LogPath } catch { return @() }
}

function Add-ToChangeLog {
    param([object[]]$Changes, [string]$LogPath)
    $changes = AsArray $Changes
    if ($changes.Count -eq 0) { return }
    $all = New-Object 'System.Collections.Generic.List[object]'
    foreach ($x in (Get-ChangeLog -LogPath $LogPath)) { [void]$all.Add($x) }
    foreach ($x in $changes) { [void]$all.Add($x) }
    $json = ConvertTo-Json -InputObject $all.ToArray() -Depth 6
    [IO.File]::WriteAllText($LogPath, $json, (New-Object Text.UTF8Encoding($false)))
    Write-Log "Recorded $($changes.Count) change(s)."
}

# Real version transitions only - no synthetic "current version" row.
function Get-VersionHistory {
    param($App, [object[]]$ChangeLog)
    $rows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($c in (AsArray $ChangeLog)) {
        if ("$($c.AppId)" -ne "$($App.Id)") { continue }
        if ("$($c.Property)" -ne 'DisplayVersion' -and "$($c.Property)" -ne 'ContentVersion') { continue }
        [void]$rows.Add([pscustomobject]@{ When = "$($c.When)"; Field = "$($c.Property)"; From = "$($c.Old)"; To = "$($c.New)"; Who = ''; Source = 'Snapshot diff' })
    }
    foreach ($e in (AsArray $App.AuditEvents)) {
        if ("$($e.Changes)" -match '(?i)version') {
            [void]$rows.Add([pscustomobject]@{ When = "$($e.When)"; Field = 'Version'; From = ''; To = "$($e.Changes)"; Who = "$($e.Who)"; Source = 'Intune audit' })
        }
    }
    return ,@($rows.ToArray() | Sort-Object { "$($_.When)" } -Descending)
}

# Everything that ever happened to this app, newest first, from all three sources.
function Get-ModificationHistory {
    param($App, [object[]]$ChangeLog)
    $rows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($e in (AsArray $App.NoteEvents))  { [void]$rows.Add([pscustomobject]@{ When = "$($e.When)"; Who = ''; What = "$($e.What)"; Source = 'App notes' }) }
    foreach ($e in (AsArray $App.AuditEvents)) {
        $what = "$($e.What)"
        if ("$($e.Changes)") { $what = "$what - $($e.Changes)" }
        [void]$rows.Add([pscustomobject]@{ When = "$($e.When)"; Who = "$($e.Who)"; What = $what; Source = 'Intune audit' })
    }
    foreach ($c in (AsArray $ChangeLog)) {
        if ("$($c.AppId)" -ne "$($App.Id)") { continue }
        $what = $(if ($c.Type -eq 'Modified') { "$($c.Property): $($c.Old) -> $($c.New)" } else { "$($c.Type)" })
        [void]$rows.Add([pscustomobject]@{ When = "$($c.When)"; Who = ''; What = $what; Source = 'Snapshot diff' })
    }
    return ,@($rows.ToArray() | Sort-Object { "$($_.When)" } -Descending)
}
