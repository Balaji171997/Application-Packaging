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

# Who the token belongs to (MSAL account), for the UI; '' when unknown.
function Get-SignedInAccount { try { return "$($Global:AccessToken.Account.Username)" } catch { return '' } }

# Launch gate: a valid token is not enough - a tenant user without an Intune role can still sign in. One cheap
# authorised read decides whether this account may see apps at all.
function Test-IntuneAccess {
    $who = Get-SignedInAccount
    try {
        [void](Invoke-GraphGet -Uri "$script:GraphBase/deviceAppManagement/mobileApps?`$top=1&`$select=id")
        return @{ Ok = $true; Who = $who; Why = '' }
    } catch {
        $m = "$($_.Exception.Message)"
        $why = $(if ($m -match 'HTTP 403') { 'this account has no Intune role that can read apps (403).' } elseif ($m -match 'HTTP 401') { 'the sign-in was not accepted by Intune (401).' } else { $m })
        Write-Log "Access check failed for '$who': $m" Warning
        return @{ Ok = $false; Who = $who; Why = $why }
    }
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
            AssignmentSummary   = (@((AsArray $asg) | ForEach-Object { "$($_.Intent): $($_.Target)" }) -join '; ')   # parenthesised: AsArray returns ,$arr and a bare pipe would hand it over as ONE item
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
#
# Cache format 3.
#   v1 flattened every event's property list into ONE string (names and values space-joined) - unrecoverable,
#      so a v1 file is loaded for who/when, flagged Legacy, and the next sync re-reads the audit log.
#   v2 kept @{ N; O; V } per property but keyed events by Intune's resourceId. An assignment event carries
#      TWO resources - the app (no properties) and the assignment "<appId>_0_0" (Intent, Target.GroupId...) -
#      and a relationship event carries "<sourceAppId>_<targetAppId>". So the app's history got the empty
#      half and the detail sat under a key nobody read. v3 folds every resource into the app(s) it belongs
#      to; a v2 file is migrated in place on load (no re-download).
$script:AuditFormat = 3

function Get-AuditCache {
    param([string]$Path)
    $cache = @{ Format = $script:AuditFormat; BackfilledFromUtc = $null; LastSyncUtc = $null; Apps = @{}; Groups = @{}; Users = @{}; Legacy = $false; Migrated = $false }
    if (-not (Test-Path $Path)) { return $cache }
    try {
        $j = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        $fmt = 0; try { $fmt = [int]$j.Format } catch {}
        $cache.BackfilledFromUtc = "$($j.BackfilledFromUtc)"
        $cache.LastSyncUtc       = "$($j.LastSyncUtc)"
        if ($j.Apps)   { foreach ($p in $j.Apps.PSObject.Properties)   { $cache.Apps[$p.Name]   = $p.Value } }
        if ($j.Groups) { foreach ($p in $j.Groups.PSObject.Properties) { $cache.Groups[$p.Name] = "$($p.Value)" } }
        if ($j.Users)  { foreach ($p in $j.Users.PSObject.Properties)  { $cache.Users[$p.Name]  = $p.Value } }
        if ($fmt -lt 2) {
            $cache.Legacy = $true
            $cache.BackfilledFromUtc = $null          # forces a full re-read on the next sync
            Write-Log 'Audit cache is format 1 (flattened history). The next sync re-reads the audit log to rebuild readable history.' Warning
        }
        if ($fmt -lt 3) { Merge-CompositeKeys -Cache $cache; $cache.Migrated = $true }
    } catch { Write-Log "AuditCache.json unreadable - starting a fresh one. ($($_.Exception.Message))" Warning }
    return $cache
}

function Save-AuditCache {
    param($Cache, [string]$Path)
    try {
        $obj = [pscustomobject]@{
            Format            = $script:AuditFormat
            BackfilledFromUtc = $Cache.BackfilledFromUtc
            LastSyncUtc       = $Cache.LastSyncUtc
            Groups            = [pscustomobject]$Cache.Groups
            Users             = [pscustomobject]$Cache.Users
            Apps              = [pscustomobject]$Cache.Apps
        }
        $json = $obj | ConvertTo-Json -Depth 10 -Compress
        [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding($false)))
    } catch { Write-Log "Could not save the audit cache: $($_.Exception.Message)" Warning }
}

# A v1 event carries its changes as one string; v2/v3 as a list. Both are read everywhere via this.
function Test-LegacyEvent { param($Event) return ($Event.Changes -is [string]) }

# Every GUID inside an audit resourceId: "<app>" -> app; "<app>_0_0" -> app; "<source>_<target>" -> both.
function Get-AppIdsFromResourceId {
    param([string]$ResourceId)
    $ids = New-Object 'System.Collections.Generic.List[string]'
    foreach ($m in [regex]::Matches("$ResourceId", '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')) {
        $g = $m.Value.ToLower(); if (-not $ids.Contains($g)) { [void]$ids.Add($g) }
    }
    return ,$ids.ToArray()
}

function New-AuditRecord { return [pscustomobject]@{ CreatedBy = ''; CreatedById = ''; CreatedWhen = ''; LastChangedBy = ''; LastChangedWhen = ''; Events = @() } }

# Put one event into one app record: merges with an existing event of the same second + type (the two
# resources of an assignment event arrive as two calls), replaces a legacy string with a structured list,
# and never trims - Intune forgets after ~a year, this file is the long-term record.
function Add-EventToRecord {
    param($Rec, $Event)
    $evs = New-Object 'System.Collections.Generic.List[object]'
    $merged = $false
    foreach ($x in (AsArray $Rec.Events)) {
        if ("$($x.When)" -eq "$($Event.When)" -and "$($x.What)" -eq "$($Event.What)") {
            if ($merged) { continue }                       # a duplicate already folded in
            $merged = $true
            if (Test-LegacyEvent $Event) {
                # legacy into legacy: keep the longer string (it names more fields); legacy into structured: drop it
                if ((Test-LegacyEvent $x) -and "$($Event.Changes)".Length -gt "$($x.Changes)".Length) { $x.Changes = $Event.Changes }
                [void]$evs.Add($x); continue
            }
            if (Test-LegacyEvent $x) { [void]$evs.Add($Event); continue }   # structured replaces legacy
            # structured into structured: union of properties
            $names = New-Object 'System.Collections.Generic.HashSet[string]'
            $list  = New-Object 'System.Collections.Generic.List[object]'
            foreach ($ch in (AsArray $x.Changes))     { if ($names.Add("$($ch.N)")) { [void]$list.Add($ch) } }
            foreach ($ch in (AsArray $Event.Changes)) { if ($names.Add("$($ch.N)")) { [void]$list.Add($ch) } }
            $x.Changes = $list.ToArray()
            if (-not "$($x.WhoId)" -and "$($Event.WhoId)") { $x.WhoId = "$($Event.WhoId)" }
            [void]$evs.Add($x); continue
        }
        [void]$evs.Add($x)
    }
    if (-not $merged) { [void]$evs.Add($Event) }
    $Rec.Events = @($evs.ToArray() | Sort-Object { "$($_.When)" } -Descending)
    return (-not $merged)
}

# v2 -> v3: fold "<app>_0_0" and "<source>_<target>" records into the app records they describe.
function Merge-CompositeKeys {
    param($Cache)
    $composite = @($Cache.Apps.Keys | Where-Object { $_ -notmatch '^[0-9a-fA-F-]{36}$' })
    if ($composite.Count -eq 0) { return }
    $moved = 0
    foreach ($key in $composite) {
        $src = $Cache.Apps[$key]
        $targets = Get-AppIdsFromResourceId $key
        foreach ($appId in $targets) {
            if (-not $Cache.Apps.ContainsKey($appId)) { $Cache.Apps[$appId] = New-AuditRecord }
            $rec = $Cache.Apps[$appId]
            foreach ($ev in (AsArray $src.Events)) { [void](Add-EventToRecord -Rec $rec -Event $ev); $moved++ }
            if ("$($src.LastChangedWhen)" -gt "$($rec.LastChangedWhen)") { $rec.LastChangedBy = "$($src.LastChangedBy)"; $rec.LastChangedWhen = "$($src.LastChangedWhen)" }
        }
        $Cache.Apps.Remove($key)
    }
    Write-Log "Audit cache migrated to format 3: $($composite.Count) resource key(s) folded into their apps ($moved event(s))." Success
}

# Fold one page of audit events into the cache. Returns the number of events added. Group ids and actor
# ids seen are collected so the caller can resolve names once.
function Add-AuditEventsToCache {
    param($Cache, [object[]]$Events, [System.Collections.Generic.HashSet[string]]$GroupIds, [System.Collections.Generic.HashSet[string]]$ActorIds)
    $added = 0
    foreach ($e in (AsArray $Events)) {
        if ("$($e.category)" -notmatch 'Application') { continue }
        $actor  = Get-P $e 'actor'
        $who    = Get-P $actor 'userPrincipalName'
        if (-not $who) { $who = Get-P $actor 'applicationDisplayName' }
        $whoId  = "$(Get-P $actor 'userId')"
        if ($ActorIds -and $whoId -match '^[0-9a-f-]{36}$') { [void]$ActorIds.Add($whoId) }
        $when   = "$(Get-P $e 'activityDateTime')"
        $op     = "$(Get-P $e 'activityOperationType')"
        $act    = "$(Get-P $e 'activityType')"

        # 1. every property of every resource, and the app(s) this event belongs to. Newer assignments carry
        #    their OWN guid as resourceId, so the resource type decides which one is the app; the ids inside
        #    composite ids ("<app>_0_0", "<source>_<target>") are apps by construction.
        $props  = New-Object 'System.Collections.Generic.List[object]'
        $seen   = New-Object 'System.Collections.Generic.HashSet[string]'
        $appIds = New-Object 'System.Collections.Generic.List[string]'
        $anyIds = New-Object 'System.Collections.Generic.List[string]'
        foreach ($res in (AsArray (Get-P $e 'resources'))) {
            $rid  = "$(Get-P $res 'resourceId')"
            $type = "$(Get-P $res 'auditResourceType') $(Get-P $res 'type')"
            $isApp = ($rid -notmatch '^[0-9a-fA-F-]{36}$') -or ($type -notmatch 'Assignment|Relationship|Configuration|Category|Token|Policy|Setting')
            foreach ($id in (Get-AppIdsFromResourceId $rid)) {
                if (-not $anyIds.Contains($id)) { [void]$anyIds.Add($id) }
                if ($isApp -and -not $appIds.Contains($id)) { [void]$appIds.Add($id) }
            }
            foreach ($mp in (AsArray (Get-P $res 'modifiedProperties'))) {          # iterate, never pipe an AsArray result
                $name = "$(Get-P $mp 'displayName')"
                if (-not $name -or $name -eq 'DeviceManagementAPIVersion') { continue }   # API stamp changes on every write
                $old = "$(Get-P $mp 'oldValue')"; $new = "$(Get-P $mp 'newValue')"
                if ($old -eq $new) { continue }
                if (-not $seen.Add($name)) { continue }
                [void]$props.Add([pscustomobject]@{ N = $name; O = $old; V = $new })
                if ($GroupIds -and $name -eq 'Target.GroupId') {
                    foreach ($g in @($old, $new)) { if ($g -match '^[0-9a-f-]{36}$') { [void]$GroupIds.Add($g) } }
                }
            }
        }
        if ($appIds.Count -eq 0) { $appIds = $anyIds }     # no typed resource at all: keep every id rather than lose the event
        if ($appIds.Count -eq 0) { continue }

        # 2. one entry per app (a relationship belongs to both ends)
        foreach ($appId in $appIds) {
            if (-not $Cache.Apps.ContainsKey($appId)) { $Cache.Apps[$appId] = New-AuditRecord }
            $rec = $Cache.Apps[$appId]
            $ev = [pscustomobject]@{ When = $when; Who = "$who"; WhoId = $whoId; Operation = $op; What = $act; Changes = $props.ToArray() }
            if (Add-EventToRecord -Rec $rec -Event $ev) { $added++ }

            if ($act -eq 'Create MobileApp' -and $when) {
                # Oldest Create of the app itself wins - not an assignment or relationship create.
                if (-not $rec.CreatedWhen -or ($when -lt "$($rec.CreatedWhen)")) {
                    $rec.CreatedBy = "$who"; $rec.CreatedById = $whoId; $rec.CreatedWhen = $when
                }
            }
            if (-not $rec.LastChangedWhen -or ($when -gt "$($rec.LastChangedWhen)")) {
                $rec.LastChangedBy = "$who"; $rec.LastChangedWhen = $when
            }
        }
    }
    return $added
}

# Existing caches: assignment/relationship detail that was filed under a resource guid of its own (not an
# app) is re-attached to the app's detail-less twin by exact match on (timestamp, activity, actor) - the
# two are halves of ONE audit event, so the 100 ns timestamp is a safe key. Donor records that end up
# empty are dropped; records of deleted apps (they have their own Create/Delete history) are left alone.
function Repair-DetachedDetails {
    param($Cache, [string[]]$KnownAppIds)
    $known = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($id in (AsArray $KnownAppIds)) { [void]$known.Add("$id".ToLower()) }
    if ($known.Count -eq 0) { return 0 }

    # index of detailed events living under NON-app keys
    $index = @{}
    foreach ($k in @($Cache.Apps.Keys)) {
        if ($known.Contains($k.ToLower())) { continue }
        foreach ($ev in (AsArray $Cache.Apps[$k].Events)) {
            if ((Test-LegacyEvent $ev) -or (AsArray $ev.Changes).Count -eq 0) { continue }
            $key = "$($ev.When)|$($ev.What)|$($ev.Who)"
            if (-not $index.ContainsKey($key)) { $index[$key] = New-Object 'System.Collections.Generic.List[object]' }
            [void]$index[$key].Add(@{ Key = $k; Event = $ev })
        }
    }
    if ($index.Count -eq 0) { return 0 }

    $fixed = 0
    $consumed = @{}
    foreach ($k in @($Cache.Apps.Keys)) {
        if (-not $known.Contains($k.ToLower())) { continue }
        foreach ($ev in (AsArray $Cache.Apps[$k].Events)) {
            if (Test-LegacyEvent $ev) { continue }
            if ((AsArray $ev.Changes).Count -gt 0) { continue }
            if ("$($ev.What)" -notmatch 'Assignment|Relationship') { continue }
            $key = "$($ev.When)|$($ev.What)|$($ev.Who)"
            if (-not $index.ContainsKey($key)) { continue }
            $list = New-Object 'System.Collections.Generic.List[object]'
            $names = New-Object 'System.Collections.Generic.HashSet[string]'
            foreach ($d in $index[$key]) {
                foreach ($ch in (AsArray $d.Event.Changes)) { if ($names.Add("$($ch.N)")) { [void]$list.Add($ch) } }
                $consumed["$($d.Key)|$($d.Event.When)|$($d.Event.What)"] = $true
            }
            if ($list.Count) { $ev.Changes = $list.ToArray(); $fixed++ }
        }
    }
    # drop donor records whose every event was consumed
    foreach ($k in @($Cache.Apps.Keys)) {
        if ($known.Contains($k.ToLower())) { continue }
        $evs = AsArray $Cache.Apps[$k].Events
        if ($evs.Count -eq 0) { continue }
        $left = @($evs | Where-Object { -not $consumed.ContainsKey("$k|$($_.When)|$($_.What)") })
        if ($left.Count -eq 0) { $Cache.Apps.Remove($k) }
        elseif ($left.Count -lt $evs.Count) { $Cache.Apps[$k].Events = $left }
    }
    if ($fixed) { Write-Log "Re-attached detail to $fixed assignment/relationship event(s)." Success }
    return $fixed
}

# Ids the whole cache refers to but the directories do not know yet - swept every sync, so people and
# groups from events read before the lookup existed still get their names.
function Get-UnresolvedIds {
    param($Cache)
    $groups = New-Object 'System.Collections.Generic.HashSet[string]'
    $actors = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($k in @($Cache.Apps.Keys)) {
        $rec = $Cache.Apps[$k]
        if ("$($rec.CreatedById)" -match '^[0-9a-f-]{36}$' -and -not $Cache.Users.ContainsKey("$($rec.CreatedById)")) { [void]$actors.Add("$($rec.CreatedById)") }
        foreach ($e in (AsArray $rec.Events)) {
            $w = "$($e.WhoId)"; if ($w -match '^[0-9a-f-]{36}$' -and -not $Cache.Users.ContainsKey($w)) { [void]$actors.Add($w) }
            if (Test-LegacyEvent $e) { continue }
            foreach ($ch in (AsArray $e.Changes)) {
                if ("$($ch.N)" -ne 'Target.GroupId') { continue }
                foreach ($g in @("$($ch.O)", "$($ch.V)")) { if ($g -match '^[0-9a-f-]{36}$' -and -not $Cache.Groups.ContainsKey($g)) { [void]$groups.Add($g) } }
            }
        }
    }
    return @{ Groups = $groups; Actors = $actors }
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
    $totalSeen  = 0
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $groupIds = New-Object 'System.Collections.Generic.HashSet[string]'
    $actorIds = New-Object 'System.Collections.Generic.HashSet[string]'
    # Only app events, only the fields we read. The old query pulled EVERY audit category (devices,
    # policies, enrolment...) and threw 80-90 % of it away client-side - that was the slow sync.
    $select = [uri]::EscapeDataString('id,activityDateTime,activityType,activityOperationType,category,actor,resources')
    $script:AuditCategoryFilterOk = $true
    foreach ($w in $windows) {
        if ($script:CancelRequested) { Write-Log 'Audit backfill cancelled - progress kept.' Warning; break }
        $i++
        $f = $w.From.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $t = $w.To.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $eta = ''
        if ($i -gt 1) { $per = $sw.Elapsed.TotalSeconds / ($i - 1); $left = [int]($per * ($total - $i + 1)); if ($left -ge 5) { $eta = "  ·  ~$([Math]::Ceiling($left / 60)) min left" } }
        & $report "Reading app audit log $($w.From.ToString('dd MMM yyyy')) - $($w.To.ToString('dd MMM yyyy'))  ($i of $total)$eta" (88 + [int](10 * $i / [Math]::Max(1, $total)))

        $ev = $null
        $queries = @()
        if ($script:AuditCategoryFilterOk) { $queries += "category eq 'Application' and activityDateTime gt $f and activityDateTime le $t" }
        $queries += "activityDateTime gt $f and activityDateTime le $t"       # tenants that reject the category filter
        $queries += "activityDateTime gt $f"                                   # tenants that reject the compound range
        foreach ($q in $queries) {
            try {
                $ev = Invoke-GraphAll -Uri "$script:GraphBase/deviceManagement/auditEvents?`$filter=$([uri]::EscapeDataString($q))&`$select=$select&`$top=1000" -TolerateFailure
                break
            } catch {
                if ($q -like "category eq*") { $script:AuditCategoryFilterOk = $false; Write-Log "Category filter rejected ($($_.Exception.Message)); reading all categories." Warning }
                else { Write-Log "Audit window $f..$t query failed: $($_.Exception.Message)" Warning }
                $ev = $null
            }
        }
        if ($null -eq $ev) { continue }
        $totalSeen  += (AsArray $ev).Count
        $totalAdded += (Add-AuditEventsToCache -Cache $cache -Events $ev -GroupIds $groupIds -ActorIds $actorIds)
        # Save after EVERY window - a throttle later must not cost us what we already have.
        $cache.LastSyncUtc = $nowUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
        if (-not $cache.BackfilledFromUtc -and $i -eq $total) { $cache.BackfilledFromUtc = $w.From.ToString('yyyy-MM-ddTHH:mm:ssZ') }
        Save-AuditCache -Cache $cache -Path $Path
    }
    if ($cache.BackfilledFromUtc) { $cache.Legacy = $false }

    # Directories: group ids -> names (assignments) and actor ids -> display names (people). Both are kept
    # in the cache for good, so history still reads as names after a group is deleted or a person leaves.
    # The sweep covers the WHOLE cache, not just this run, so events read before the lookup existed get names too.
    $pending = Get-UnresolvedIds -Cache $cache
    foreach ($g in $groupIds) { [void]$pending.Groups.Add($g) }
    foreach ($u in $actorIds) { [void]$pending.Actors.Add($u) }
    Update-DirectoryNames -Cache $cache -GroupIds $pending.Groups -ActorIds $pending.Actors -Report $report
    Save-AuditCache -Cache $cache -Path $Path

    $known = @($cache.Apps.Keys).Count
    Write-Log ("Audit: {0} event(s) read, {1} new, {2} app(s) with history, {3:N0}s." -f $totalSeen, $totalAdded, $known, $sw.Elapsed.TotalSeconds) Success
    return $cache
}

# Resolve unknown group ids and actor ids in ONE pass each (getByIds takes 1000 at a time).
function Update-DirectoryNames {
    param($Cache, [System.Collections.Generic.HashSet[string]]$GroupIds, [System.Collections.Generic.HashSet[string]]$ActorIds, [scriptblock]$Report)
    $unknownG = @($GroupIds | Where-Object { -not $Cache.Groups.ContainsKey($_) })
    if ($unknownG.Count -gt 0) {
        if ($Report) { & $Report "Resolving $($unknownG.Count) group name(s)..." 98 }
        $map = Resolve-GroupNames -GroupIds ([string[]]$unknownG)
        foreach ($k in $map.Keys) { $Cache.Groups[$k] = "$($map[$k])" }
        if ($map.Count -gt 0) { foreach ($g in $unknownG) { if (-not $Cache.Groups.ContainsKey($g)) { $Cache.Groups[$g] = '' } } }   # '' = looked up, gone
    }
    # People: only ids the directory has NOT answered for yet. An earlier failure (403) must not poison the
    # cache, so empties are stored only after a lookup that actually worked and still found nothing.
    $unknownU = @($ActorIds | Where-Object { -not $Cache.Users.ContainsKey($_) -or -not "$(Get-P $Cache.Users[$_] 'Name')" })
    if ($unknownU.Count -gt 0) {
        if ($Report) { & $Report "Resolving $($unknownU.Count) people..." 99 }
        $res = Resolve-UserNames -UserIds ([string[]]$unknownU)
        foreach ($k in $res.Map.Keys) { $Cache.Users[$k] = $res.Map[$k] }
        if ($res.Worked) { foreach ($u in $unknownU) { if (-not $Cache.Users.ContainsKey($u)) { $Cache.Users[$u] = [pscustomobject]@{ Name = ''; Upn = '' } } } }
        else { foreach ($u in $unknownU) { if ($Cache.Users.ContainsKey($u) -and -not "$(Get-P $Cache.Users[$u] 'Name')") { $Cache.Users.Remove($u) } } }
        $Cache.UserLookup = $res.How
    }
}

# Actor userId -> @{ Name; Upn }. Tries, in order: directoryObjects/getByIds (user + servicePrincipal),
# then /users/{id} one by one. Returns @{ Map; Worked; How } - Worked is $false when every route was denied,
# so the caller can tell "no such user" from "not allowed to ask".
function Resolve-UserNames {
    param([string[]]$UserIds)
    $map = @{}
    $ids = @($UserIds | Where-Object { $_ } | Select-Object -Unique)
    if ($ids.Count -eq 0) { return @{ Map = $map; Worked = $true; How = '' } }
    $worked = $false; $how = ''
    # 1. bulk
    $bulkOk = $true
    for ($i = 0; $i -lt $ids.Count; $i += 900) {
        $chunk = $ids[$i..([Math]::Min($i + 899, $ids.Count - 1))]
        try {
            $r = Invoke-GraphGet -Uri "$script:GraphBase/directoryObjects/getByIds" -Method POST -Body @{ ids = $chunk; types = @('user', 'servicePrincipal') }
            foreach ($u in $r.value) { $map[$u.id] = [pscustomobject]@{ Name = "$($u.displayName)"; Upn = "$(Get-P $u 'userPrincipalName')" } }
            $worked = $true; $how = 'directoryObjects/getByIds'
        } catch { $bulkOk = $false; Write-Log "People lookup via getByIds denied ($($_.Exception.Message -replace '^Graph ', ''))." Warning; break }
    }
    if ($bulkOk) { return @{ Map = $map; Worked = $worked; How = $how } }
    # 2. per user - a different permission path (User.ReadBasic.All) than the directory-wide one
    $denied = 0
    foreach ($id in ($ids | Select-Object -First 200)) {
        try {
            $u = Invoke-GraphGet -Uri "$script:GraphBase/users/$id`?`$select=id,displayName,userPrincipalName"
            if ($u) { $map[$id] = [pscustomobject]@{ Name = "$($u.displayName)"; Upn = "$(Get-P $u 'userPrincipalName')" }; $worked = $true; $how = '/users/{id}' }
        } catch {
            if ("$($_.Exception.Message)" -match 'HTTP 40[13]') { $denied++; if ($denied -ge 3) { break } }   # three denials = the route is closed
        }
    }
    if (-not $worked) { Write-Log 'The directory denies user reads for this sign-in (needs User.ReadBasic.All). Names come from Data\people.json until that is granted.' Warning }
    return @{ Map = $map; Worked = $worked; How = $how }
}

# Write display names into people.json (keys are lower-case sign-in names). Returns how many were filled.
function Set-PeopleNames {
    param([string]$Path, [hashtable]$Names)
    $people = [ordered]@{}
    if (Test-Path $Path) { try { $j = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $people[$p.Name] = "$($p.Value)" } } catch {} }
    $filled = 0
    foreach ($k in $Names.Keys) { $key = "$k".ToLower(); if ("$($Names[$k])".Trim() -and -not "$($people[$key])".Trim()) { $people[$key] = "$($Names[$k])".Trim(); $filled++ } }
    if ($filled) { [IO.File]::WriteAllText($Path, ([pscustomobject]$people | ConvertTo-Json -Depth 2), (New-Object Text.UTF8Encoding($false))) }
    return $filled
}

# Data\people.json - a hand-maintained sign-in name -> display name map for accounts the directory will
# not resolve (admin accounts like e3185@azure.man). The tool keeps it complete: every sign-in name seen in
# the audit is listed with an empty value for someone to fill; filled values win over everything else.
function Update-PeopleFile {
    param([string]$Path, $Cache)
    $people = [ordered]@{}
    if (Test-Path $Path) {
        try { $j = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $people[$p.Name] = "$($p.Value)" } }
        catch { Write-Log "people.json unreadable ($($_.Exception.Message)) - leaving it alone."; return $people }
    }
    $seen = @{}
    foreach ($k in $Cache.Apps.Keys) {
        $rec = $Cache.Apps[$k]
        if ("$($rec.CreatedBy)" -match '@') { $seen["$($rec.CreatedBy)".ToLower()] = 1 }
        foreach ($e in (AsArray $rec.Events)) { $w = "$($e.Who)"; if ($w -match '@') { $seen[$w.ToLower()] = 1 } }
    }
    $added = 0
    foreach ($upn in ($seen.Keys | Sort-Object)) {
        if ($people.Contains($upn)) { continue }
        # already answered by the directory? then no need to ask a human
        $known = $false
        foreach ($k in $Cache.Users.Keys) { $u = $Cache.Users[$k]; if ("$(Get-P $u 'Upn')".ToLower() -eq $upn -and "$(Get-P $u 'Name')") { $known = $true; break } }
        if ($known) { continue }
        $people[$upn] = ''; $added++
    }
    if ($added -gt 0 -or -not (Test-Path $Path)) {
        try {
            $json = [pscustomobject]$people | ConvertTo-Json -Depth 2
            [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding($false)))
            Write-Log "people.json: $added sign-in name(s) added for you to name ($($people.Count) total)."
        } catch { Write-Log "Could not write people.json: $($_.Exception.Message)" Warning }
    }
    return $people
}

# People directory for the UI: id -> name and lower-case UPN -> name. people.json entries win, then the
# directory answers, then nothing (Format-Who falls back to tidying the sign-in name).
function Build-UserMap {
    param($Cache, [string]$PeoplePath)
    $map = @{}
    if ($Cache -and $Cache.Users) {
        foreach ($k in $Cache.Users.Keys) {
            $u = $Cache.Users[$k]
            $name = "$(Get-P $u 'Name')"; $upn = "$(Get-P $u 'Upn')"
            if (-not $name) { continue }
            $map[$k] = $name
            if ($upn) { $map[$upn.ToLower()] = $name }
        }
    }
    if ($PeoplePath -and (Test-Path $PeoplePath)) {
        try {
            $j = Get-Content -LiteralPath $PeoplePath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) { if ("$($p.Value)".Trim()) { $map[$p.Name.ToLower()] = "$($p.Value)".Trim() } }
        } catch {}
        # ids whose UPN is named in people.json
        if ($Cache -and $Cache.Apps) {
            foreach ($k in @($Cache.Apps.Keys)) {
                foreach ($e in (AsArray $Cache.Apps[$k].Events)) {
                    $w = "$($e.Who)".ToLower(); $id = "$($e.WhoId)"
                    if ($id -and $map.ContainsKey($w) -and -not $map.ContainsKey($id)) { $map[$id] = $map[$w] }
                }
            }
        }
    }
    return $map
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
        # Display names for the grid and the detail pane; the UPN stays in CreatedBy/LastChangedBy for export.
        $a | Add-Member -NotePropertyName CreatedByName     -NotePropertyValue $(if ("$(Get-P $rec 'CreatedBy')")     { Format-Who "$(Get-P $rec 'CreatedBy')" "$(Get-P $rec 'CreatedById')" } else { '' }) -Force
        $a | Add-Member -NotePropertyName LastChangedByName -NotePropertyValue $(if ("$(Get-P $rec 'LastChangedBy')") { Format-Who "$(Get-P $rec 'LastChangedBy')" } else { '' }) -Force
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
            if ($f -eq 'AssignmentSummary') {
                # Compare the assignment SET, not the summary string: the string format changed once (it used
                # to space-join every assignment into one) and must not show up as a change on every app.
                $so = (@((AsArray $p.Assignments) | ForEach-Object { "$($_.Intent)|$($_.Target)" }) | Sort-Object) -join ';'
                $sn = (@((AsArray $c.Assignments) | ForEach-Object { "$($_.Intent)|$($_.Target)" }) | Sort-Object) -join ';'
                if ($so -eq $sn) { continue }
            }
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

# =====================================================================================================
# CHANGE HISTORY - the audit log translated into sentences a packager can read.
#
# Intune's audit gives us, per event, a list of modified properties with raw names ("$Collection.Rules.KeyPath[1]",
# "Settings.RestartSettings.GracePeriodInMinutes") and raw values. Three things make it unreadable as-is:
#   1. Collections arrive exploded per index; a detection rule is six properties, not one.
#   2. On a Patch, Intune re-sends collections it did NOT change with oldValue filled and newValue EMPTY.
#      That is "unchanged, re-saved", not "cleared" - and must not be shown as a change.
#   3. Notes is a JSON document, so "Notes changed" hides the one thing people care about: lifecycle.
# Everything below exists to undo those three.
# =====================================================================================================

$script:FriendlyProp = @{
    'DisplayName'='Name'; 'DisplayVersion'='Version'; 'Description'='Description'; 'Publisher'='Publisher'
    'Owner'='Owner'; 'Developer'='Developer'; 'InformationUrl'='Information URL'; 'PrivacyInformationUrl'='Privacy URL'
    'InstallCommandLine'='Install command'; 'UninstallCommandLine'='Uninstall command'; 'SetupFilePath'='Setup file'
    'FileName'='Package file'; 'Size'='Size'; 'CommittedContentVersion'='Content version'
    'InstallExperience.RunAsAccount'='Run as'; 'InstallExperience.DeviceRestartBehavior'='Restart behaviour'
    'InstallExperience.MaxRunTimeInMinutes'='Max run time (min)'; 'MinimumSupportedWindowsRelease'='Minimum Windows release'
    'ApplicableArchitectures'='Architectures'; 'AllowAvailableUninstall'='Uninstall allowed in Company Portal'
    'IsFeatured'='Featured in Company Portal'; 'PublishingState'='Publishing state'; 'LargeIcon.Type'='Icon'
    'MinimumFreeDiskSpaceInMB'='Min free disk (MB)'; 'MinimumMemoryInMB'='Min memory (MB)'
    'MinimumNumberOfProcessors'='Min processors'; 'MinimumCpuSpeedInMHz'='Min CPU (MHz)'; 'Notes'='Notes'
    'Intent'='Intent'; 'Settings.Notifications'='Notifications'; 'Settings.DeliveryOptimizationPriority'='Delivery optimisation'
    'Settings.RestartSettings.GracePeriodInMinutes'='Restart grace period (min)'
    'Settings.RestartSettings.CountdownDisplayBeforeRestartInMinutes'='Restart countdown (min)'
    'Settings.RestartSettings.RestartNotificationSnoozeDurationInMinutes'='Restart snooze (min)'
    'Settings.AutoUpdateSettings.AutoUpdateSupersededAppsState'='Auto-update superseded apps'
    'Target.DeviceAndAppManagementAssignmentFilterType'='Filter mode'; 'Target.DeviceAndAppManagementAssignmentFilterId'='Filter'
}
# Bookkeeping fields Intune writes on every save; never a change a human made.
$script:NoiseProp = '^(DeviceManagementAPIVersion|Id|CreatedDateTime|LastModifiedDateTime|IsAssigned|UploadState|DependentAppCount|DependsOnAppCount|SupersedingAppCount|SupersededAppCount|Source|SourceId|Settings\.Type|Target\.Type)$'

function Get-FriendlyFieldName { param([string]$Property) if ($script:FriendlyProp.ContainsKey("$Property")) { return $script:FriendlyProp["$Property"] } return "$Property" }

# "<null>", "" and "None" all mean "nothing" in the audit.
function Test-AuditEmpty { param([string]$Value) return ("$Value".Trim() -eq '' -or "$Value" -eq '<null>') }
function Format-AuditValue {
    param([string]$Value, [int]$Max = 160)
    if (Test-AuditEmpty $Value) { return '(empty)' }
    $v = ("$Value" -replace '\s+', ' ').Trim()
    if ($v.Length -gt $Max) { $v = $v.Substring(0, $Max - 1) + '…' }
    return $v
}
function Format-Change { param([string]$Label, [string]$Old, [string]$New) return ('{0}: {1}  ->  {2}' -f $Label, (Format-AuditValue $Old), (Format-AuditValue $New)) }

# "gurram.balaji-ext@man.eu" -> "Gurram Balaji (ext)". Service principals and ids are left alone.
$script:UserMap = @{}      # actor id / lower-case UPN -> Entra display name (from the cache's Users directory)
function Format-Who {
    param([string]$Who, [string]$WhoId)
    $w = "$Who".Trim()
    if ("$WhoId" -and $script:UserMap.ContainsKey("$WhoId")) { return $script:UserMap["$WhoId"] }
    if ($w -and $script:UserMap.ContainsKey($w.ToLower())) { return $script:UserMap[$w.ToLower()] }
    if (-not $w) { return 'author not recorded' }
    if ($w -match '^(?<a>[a-z]+)\.(?<b>[a-z]+)(?<ext>-ext)?@') {
        $ti = (Get-Culture).TextInfo
        return ('{0} {1}{2}' -f $ti.ToTitleCase($Matches.a), $ti.ToTitleCase($Matches.b), $(if ($Matches.ext) { ' (ext)' } else { '' }))
    }
    return $w
}

# The Notes field is JSON: compare key by key so "Notes changed" becomes "Lifecycle: SAT -> LIVE".
function Get-NotesChangeLines {
    param([string]$Old, [string]$New)
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $o = $null; $n = $null
    try { if ("$Old".Trim().StartsWith('{')) { $o = "$Old" | ConvertFrom-Json } } catch {}
    try { if ("$New".Trim().StartsWith('{')) { $n = "$New" | ConvertFrom-Json } } catch {}
    if (-not $o -and -not $n) {
        if (-not (Test-AuditEmpty $Old) -or -not (Test-AuditEmpty $New)) { [void]$lines.Add((Format-Change 'Notes' $Old $New)) }
        return ,$lines.ToArray()
    }
    $labels = [ordered]@{ lifecycle = 'Lifecycle'; status = 'Status'; managed = 'Managed'; rollout = 'Rollout date'; pilot = 'Pilot date'; notes = 'Note text' }
    $keys = New-Object 'System.Collections.Generic.List[string]'
    foreach ($k in $labels.Keys) { [void]$keys.Add($k) }
    foreach ($obj in @($o, $n)) { if ($obj) { foreach ($p in $obj.PSObject.Properties) { if (-not $keys.Contains($p.Name)) { [void]$keys.Add($p.Name) } } } }
    foreach ($k in $keys) {
        $ov = "$(Get-P $o $k)"; $nv = "$(Get-P $n $k)"
        if ($ov -eq $nv) { continue }
        $label = $(if ($labels.Contains($k)) { $labels[$k] } else { "Notes.$k" })
        if ($k -eq 'lifecycle') { $ov = Get-NormalisedStage $ov; $nv = Get-NormalisedStage $nv }
        [void]$lines.Add((Format-Change $label $ov $nv))
    }
    if ($lines.Count -eq 0 -and ((-not $o) -ne (-not $n))) { [void]$lines.Add($(if ($n) { 'Notes: structured JSON written' } else { 'Notes: structured JSON removed' })) }
    return ,$lines.ToArray()
}

# One detection / requirement rule, from its exploded properties, as a sentence.
function Format-RuleText {
    param([hashtable]$R)
    $g = { param($k) $v = "$($R[$k])"; if (Test-AuditEmpty $v) { '' } else { $v } }
    $type = & $g 'DetectionType'; if (-not $type) { $type = & $g 'OperationType' }
    $val  = & $g 'DetectionValue'; if (-not $val)  { $val  = & $g 'ComparisonValue' }
    $op   = & $g 'Operator'
    $cond = $(if ($type -and $type -ne 'Exists' -and $type -ne 'NotConfigured') { " [$type $op $val]".Replace('  ', ' ') } elseif ($type -eq 'Exists') { ' [exists]' } else { '' })
    if (& $g 'ProductCode') {
        $pv = & $g 'ProductVersion'; $pvo = & $g 'ProductVersionOperator'
        return ("MSI product code $(& $g 'ProductCode')" + $(if ($pv -and $pvo -and $pvo -ne 'NotConfigured') { " (version $pvo $pv)" } else { '' }))
    }
    if (& $g 'ScriptContent' -or (& $g 'DisplayName')) { return ("PowerShell script" + $(if (& $g 'DisplayName') { " '$(& $g 'DisplayName')'" } else { '' })) }
    if (& $g 'KeyPath') {
        $vn = & $g 'ValueName'
        return ("Registry $(& $g 'KeyPath')" + $(if ($vn) { "\$vn" } else { '' }) + $cond + $(if ((& $g 'Check32BitOn64System') -eq 'True') { ' (32-bit view)' } else { '' }))
    }
    if (& $g 'Path' -or (& $g 'FileOrFolderName')) { return ("File $(& $g 'Path')\$(& $g 'FileOrFolderName')" + $cond) }
    return (($R.Keys | Sort-Object | ForEach-Object { "$_=$($R[$_])" }) -join ', ')
}

# Rebuild collections from "$Collection.<Name>.<Prop>[<i>]" entries and describe what really changed.
# Returns lines; consumes the collection entries from $Changes (callers handle the scalar rest).
function Get-CollectionChangeLines {
    param([object[]]$Changes, [string]$Operation)
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $colls = [ordered]@{}
    foreach ($c in $Changes) {
        if ("$($c.N)" -notmatch '^\$Collection\.(?<coll>[^.\[]+)(?:\.(?<prop>[^\[]+))?\[(?<i>\d+)\]$') { continue }
        $coll = $Matches.coll; $prop = $(if ($Matches.prop) { $Matches.prop } else { 'Value' }); $i = [int]$Matches.i
        # Inner map is a plain hashtable on purpose: an [ordered] dictionary indexed with an [int] reads by
        # POSITION, not by key, and throws "index out of range" for rule 1 of a two-rule change.
        if (-not $colls.Contains($coll)) { $colls[$coll] = @{} }
        if (-not $colls[$coll].ContainsKey($i)) { $colls[$coll][$i] = @{ Old = @{}; New = @{} } }
        $colls[$coll][$i].Old[$prop] = "$($c.O)"
        $colls[$coll][$i].New[$prop] = "$($c.V)"
    }
    foreach ($coll in $colls.Keys) {
        $items = $colls[$coll]
        $hasVal = { param($h) foreach ($v in $h.Values) { if (-not (Test-AuditEmpty $v)) { return $true } }; return $false }

        if ($coll -eq 'ReturnCodes') {
            $fmt = { param($side) @($items.Keys | Sort-Object | ForEach-Object { $it = $items[$_].$side; $rc = "$($it['ReturnCode'])"; $ty = "$($it['Type'])"; if (-not (Test-AuditEmpty $rc)) { "$rc $ty".Trim() } }) -join ', ' }
            $o = & $fmt 'Old'; $n = & $fmt 'New'
            if ($n -and $n -ne $o) { [void]$lines.Add($(if ($o) { "Return codes: $o  ->  $n" } else { "Return codes: $n" })) }
            continue
        }
        if ($coll -eq 'RoleScopeTagIds') {
            $o = @($items.Values | ForEach-Object { $_.Old['Value'] } | Where-Object { -not (Test-AuditEmpty $_) }) -join ', '
            $n = @($items.Values | ForEach-Object { $_.New['Value'] } | Where-Object { -not (Test-AuditEmpty $_) }) -join ', '
            if ($n -and $n -ne $o) { [void]$lines.Add("Scope tags: $(if ($o) { $o } else { '(none)' })  ->  $n") }
            continue
        }
        # DetectionRules / RequirementRules / Rules (newer API: RuleType Detection|Requirement)
        foreach ($i in ($items.Keys | Sort-Object)) {
            $it = $items[$i]
            $oldHas = & $hasVal $it.Old; $newHas = & $hasVal $it.New
            $kind = "$($it.New['RuleType'])"; if (Test-AuditEmpty $kind) { $kind = "$($it.Old['RuleType'])" }
            if (Test-AuditEmpty $kind) { $kind = $(if ($coll -match '(?i)requirement') { 'Requirement' } else { 'Detection' }) }
            $label = "$kind rule $($i + 1)"
            if ($newHas -and -not $oldHas) { [void]$lines.Add("$label added: $(Format-RuleText $it.New)"); continue }
            if ($oldHas -and -not $newHas) {
                # Patch quirk: unchanged collections come back with old filled and new empty. Only a Delete
                # operation means it was really removed.
                if ($Operation -match 'Delete') { [void]$lines.Add("$label removed: $(Format-RuleText $it.Old)") }
                continue
            }
            if ($oldHas -and $newHas) {
                $ot = Format-RuleText $it.Old; $nt = Format-RuleText $it.New
                if ($ot -ne $nt) { [void]$lines.Add("$label changed: $ot  ->  $nt") }
            }
        }
    }
    return ,$lines.ToArray()
}

# The Minimum OS flags arrive as 15 booleans; say it once.
function Get-MinOsChangeLine {
    param([object[]]$Changes)
    $flags = @($Changes | Where-Object { "$($_.N)" -like 'MinimumSupportedOperatingSystem.*' })
    if ($flags.Count -eq 0) { return $null }
    $o = @($flags | Where-Object { "$($_.O)" -eq 'True' } | ForEach-Object { "$($_.N)" -replace '^.*\.V', '' -replace '_', '.' }) -join ', '
    $n = @($flags | Where-Object { "$($_.V)" -eq 'True' } | ForEach-Object { "$($_.N)" -replace '^.*\.V', '' -replace '_', '.' }) -join ', '
    if ($n -eq $o) { return $null }
    if (-not $n) { return $null }        # re-saved, not cleared
    return "Minimum OS: $(if ($o) { $o } else { '(none)' })  ->  $n"
}

function Get-AssignmentText {
    param([hashtable]$P, [hashtable]$GroupMap)
    $tt  = "$($P['Target.Type'])"
    $gid = "$($P['Target.GroupId'])"
    $target = switch -Regex ($tt) {
        'AllLicensedUsers' { 'All users' }
        'AllDevices'       { 'All devices' }
        'Exclusion'        { "EXCLUDE group $(if ($GroupMap[$gid]) { $GroupMap[$gid] } else { $gid })" }
        default            { if ($gid -and -not (Test-AuditEmpty $gid)) { "group $(if ($GroupMap[$gid]) { $GroupMap[$gid] } else { $gid })" } else { '(unknown target)' } }
    }
    $intent = "$($P['Intent'])"; if (Test-AuditEmpty $intent) { $intent = 'assigned' }
    if ($target -eq '(unknown target)' -and $intent -eq 'assigned') { return 'Assignment changed (Intune recorded no detail for this event)' }
    $extra = New-Object 'System.Collections.Generic.List[string]'
    $ft = "$($P['Target.DeviceAndAppManagementAssignmentFilterType'])"
    if ($ft -and $ft -ne 'None' -and -not (Test-AuditEmpty $ft)) { [void]$extra.Add("filter $($ft.ToLower()) $($P['Target.DeviceAndAppManagementAssignmentFilterId'])") }
    $nt = "$($P['Settings.Notifications'])"; if ($nt -and $nt -ne 'ShowAll' -and -not (Test-AuditEmpty $nt)) { [void]$extra.Add("notifications: $nt") }
    $do = "$($P['Settings.DeliveryOptimizationPriority'])"; if ($do -eq 'Foreground') { [void]$extra.Add('DO priority: foreground') }
    $au = "$($P['Settings.AutoUpdateSettings.AutoUpdateSupersededAppsState'])"; if ($au -and $au -ne 'NotConfigured' -and -not (Test-AuditEmpty $au)) { [void]$extra.Add("auto-update superseded: $au") }
    return ("$intent  ->  $target" + $(if ($extra.Count) { "  ($($extra -join ' · '))" } else { '' }))
}

function Get-RelationshipText {
    param([hashtable]$P, [string]$AppName, [string]$Verb)
    $src = "$($P['SourceDisplayName']) $($P['SourceDisplayVersion'])".Trim()
    $tgt = "$($P['TargetDisplayName']) $($P['TargetDisplayVersion'])".Trim()
    if ($P.ContainsKey('SupersedenceType')) {
        $how = "$($P['SupersedenceType'])".ToLower()
        if ("$($P['SourceDisplayName'])" -eq $AppName) { return "Supersedence $Verb - this app supersedes $tgt ($how)" }
        if ("$($P['TargetDisplayName'])" -eq $AppName) { return "Supersedence $Verb - this app is superseded by $src ($how)" }
        return "Supersedence $Verb - $src supersedes $tgt ($how)"
    }
    if ($P.ContainsKey('DependencyType')) {
        $how = $(if ("$($P['DependencyType'])" -eq 'AutoInstall') { 'auto-install' } else { 'detect only' })
        if ("$($P['SourceDisplayName'])" -eq $AppName) { return "Dependency $Verb - this app depends on $tgt ($how)" }
        if ("$($P['TargetDisplayName'])" -eq $AppName) { return "Dependency $Verb - $src depends on this app ($how)" }
        return "Dependency $Verb - $src depends on $tgt ($how)"
    }
    if (-not $src -and -not $tgt) { return "Supersedence or dependency $Verb (Intune recorded no detail for this event)" }
    return "Relationship $Verb - $src / $tgt"
}

# Legacy (format 1) events kept only the space-joined property names. Say which fields were touched.
function Get-LegacyFieldList {
    param([string]$Changes)
    if ("$Changes" -notmatch '^(?<names>[^:]*):') { return @() }
    $names = @($Matches.names -split '\s+' | Where-Object { $_ -and $_ -notmatch $script:NoiseProp })
    $seen = [ordered]@{}
    foreach ($n in $names) {
        $label = $(if ($n -match '^\$Collection\.(?<c>[^.\[]+)') { switch -Regex ($Matches.c) { 'Rules|Detection' { 'Detection/requirement rules' } 'ReturnCodes' { 'Return codes' } 'RoleScopeTagIds' { 'Scope tags' } default { $Matches.c } } }
                 elseif ($n -like 'MinimumSupportedOperatingSystem.*') { 'Minimum OS' }
                 elseif ($n -like 'Settings.RestartSettings.*') { 'Restart settings' }
                 else { Get-FriendlyFieldName $n })
        $seen[$label] = $true
    }
    return @($seen.Keys)
}

# One audit event -> @{ Title; Lines; Kind }.   Kind drives the icon/colour in the UI.
function ConvertTo-HistoryEntry {
    param($Event, [string]$AppName, [hashtable]$GroupMap)
    $act = "$($Event.What)"; $op = "$($Event.Operation)"
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $title = $act; $kind = 'edit'

    if (Test-LegacyEvent $Event) {
        $fields = Get-LegacyFieldList "$($Event.Changes)"
        switch -Regex ($act) {
            '^Create MobileApp$'            { $title = 'App created'; $kind = 'create' }
            '^Delete MobileApp$'            { $title = 'App deleted'; $kind = 'delete' }
            'MobileAppAssignment$'          { $title = $(switch ($op) { 'Create' { 'Assignment added' } 'Delete' { 'Assignment removed' } default { 'Assignment changed' } }); $kind = 'assign' }
            'MobileAppRelationship$'        { $title = $(if ($op -eq 'Delete') { 'Supersedence/dependency removed' } else { 'Supersedence/dependency added' }); $kind = 'relation' }
            '^Commit Content'               { $title = 'New package content committed'; $kind = 'content' }
            '^Renew Url'                    { $title = 'Content download link renewed'; $kind = 'minor' }
            'Reference MobileApp$'          { $title = $(if ($op -match 'Remove') { 'Category removed' } else { 'Category assigned' }); $kind = 'minor' }
            default                         { $title = 'App edited' }
        }
        if ($fields.Count) { [void]$lines.Add("Fields touched: $($fields -join ', ')") }
        # No per-card apology: the history header says once that legacy entries lack values.
        return @{ Title = $title; Lines = $lines.ToArray(); Kind = $kind; Legacy = $true }
    }

    $changes = @((AsArray $Event.Changes) | Where-Object { "$($_.N)" -notmatch $script:NoiseProp })
    $props = @{}
    foreach ($c in $changes) { $props["$($c.N)"] = $(if (Test-AuditEmpty "$($c.V)") { "$($c.O)" } else { "$($c.V)" }) }

    switch -Regex ($act) {
        '^Create MobileApp$' {
            $title = 'App created'; $kind = 'create'
            foreach ($k in 'DisplayVersion','InstallCommandLine','UninstallCommandLine','InstallExperience.RunAsAccount','InstallExperience.DeviceRestartBehavior','Publisher') {
                if ($props.ContainsKey($k) -and -not (Test-AuditEmpty $props[$k])) { [void]$lines.Add("$(Get-FriendlyFieldName $k): $(Format-AuditValue $props[$k])") }
            }
            foreach ($l in (Get-CollectionChangeLines -Changes $changes -Operation $op)) { [void]$lines.Add($l) }
            if ($props.ContainsKey('Notes')) { foreach ($l in (Get-NotesChangeLines '' $props['Notes'])) { [void]$lines.Add($l) } }
            break
        }
        '^Delete MobileApp$' { $title = 'App deleted'; $kind = 'delete'; break }
        'MobileAppAssignment$' {
            $kind = 'assign'
            switch ($op) {
                'Create' { $title = 'Assignment added';   [void]$lines.Add((Get-AssignmentText $props $GroupMap)) }
                'Delete' { $title = 'Assignment removed'; [void]$lines.Add((Get-AssignmentText $props $GroupMap)) }
                default  {
                    $title = 'Assignment changed'
                    foreach ($c in $changes) { if (-not (Test-AuditEmpty $c.V)) { [void]$lines.Add((Format-Change (Get-FriendlyFieldName $c.N) $c.O $c.V)) } }
                    if ($lines.Count -eq 0) { [void]$lines.Add('Assignment settings re-saved (Intune recorded no field detail).') }
                }
            }
            break
        }
        'MobileAppRelationship$' {
            $kind = 'relation'
            $verb = $(if ($op -eq 'Delete') { 'removed' } else { 'added' })
            $title = $(if ($props.ContainsKey('DependencyType')) { "Dependency $verb" } else { "Supersedence $verb" })
            [void]$lines.Add((Get-RelationshipText $props $AppName $verb))
            break
        }
        '^Commit Content' { $title = 'New package content committed'; $kind = 'content'; [void]$lines.Add('A new .intunewin was uploaded and committed.'); break }
        '^Renew Url'      { $title = 'Content download link renewed'; $kind = 'minor'; break }
        'Reference MobileApp$' {
            $kind = 'minor'
            $title = $(if ($op -match 'Remove') { 'Category removed' } else { 'Category assigned' })
            if ($props['referenceProperty']) { [void]$lines.Add("$($props['referenceProperty']): $($props['referenceValue'])") }
            break
        }
        default {
            # Patch MobileApp and anything else: scalar fields, then collections, then Notes as a key diff.
            $kind = 'edit'
            foreach ($c in $changes) {
                $n = "$($c.N)"
                if ($n -match '^\$Collection\.' -or $n -like 'MinimumSupportedOperatingSystem.*' -or $n -eq 'Notes') { continue }
                if ($n -eq 'LargeIcon.Type') { [void]$lines.Add('Icon changed'); continue }
                if ($n -eq 'CommittedContentVersion') { [void]$lines.Add("Content version: $(Format-AuditValue $c.O)  ->  $(Format-AuditValue $c.V)  (new package content)"); $kind = 'content'; continue }
                if ($n -eq 'Size' -and $c.O -match '^\d+$' -and $c.V -match '^\d+$') { [void]$lines.Add(('Size: {0:N1} MB  ->  {1:N1} MB' -f ([double]$c.O / 1MB), ([double]$c.V / 1MB))); continue }
                if (Test-AuditEmpty $c.V -and -not (Test-AuditEmpty $c.O) -and $op -notmatch 'Delete') { continue }   # re-saved, not cleared
                [void]$lines.Add((Format-Change (Get-FriendlyFieldName $n) $c.O $c.V))
            }
            $mo = Get-MinOsChangeLine -Changes $changes; if ($mo) { [void]$lines.Add($mo) }
            foreach ($l in (Get-CollectionChangeLines -Changes $changes -Operation $op)) { [void]$lines.Add($l) }
            $nc = @($changes | Where-Object { "$($_.N)" -eq 'Notes' } | Select-Object -First 1)
            # Same Patch quirk as collections: Notes re-sent unchanged arrives as old filled / new empty.
            if ($nc.Count -and -not ((Test-AuditEmpty $nc[0].V) -and -not (Test-AuditEmpty $nc[0].O) -and $op -notmatch 'Delete')) {
                foreach ($l in (Get-NotesChangeLines $nc[0].O $nc[0].V)) { [void]$lines.Add($l) }
            }

            $title = $(if ($lines.Count -eq 1 -and $lines[0] -match '^(?<f>[^:]+):') { "$($Matches.f) changed" }
                       elseif ($lines.Count -eq 0) { 'App re-saved (no visible change)' }
                       else { 'App edited' })
            if ($lines.Count -eq 1 -and $lines[0] -eq 'Icon changed') { $title = 'Icon changed'; $lines.Clear() }
            if ($lines | Where-Object { $_ -like 'Version:*' }) { $title = 'Version changed'; $kind = 'version' }
            elseif ($lines | Where-Object { $_ -like 'Lifecycle:*' }) { $title = 'Lifecycle changed'; $kind = 'lifecycle' }
        }
    }
    return @{ Title = $title; Lines = $lines.ToArray(); Kind = $kind; Legacy = $false }
}

# Everything that happened to one app, newest first, as readable entries:
#   @{ When; Who; WhoText; Title; Lines; Kind; Source; Legacy }
# Audit events with the same second and actor are merged into one entry (Intune writes one Patch per
# sub-resource). Snapshot diffs (this tool comparing two syncs) and dated note lines are added only when
# no audit entry already describes the same field change - they never carry an author.
function Get-ChangeHistory {
    param($App, [object[]]$ChangeLog, [hashtable]$GroupMap)
    if (-not $GroupMap) { $GroupMap = @{} }
    $entries = New-Object 'System.Collections.Generic.List[object]'
    $covered = New-Object 'System.Collections.Generic.HashSet[string]'

    # 1. audit, grouped by (second, actor)
    $groups = [ordered]@{}
    foreach ($e in (AsArray $App.AuditEvents)) {
        $stamp = "$($e.When)"; if ($stamp.Length -ge 19) { $stamp = $stamp.Substring(0, 19) }
        $key = "$stamp|$($e.Who)"
        if (-not $groups.Contains($key)) { $groups[$key] = New-Object 'System.Collections.Generic.List[object]' }
        [void]$groups[$key].Add($e)
    }
    foreach ($key in $groups.Keys) {
        $evs = @($groups[$key] | Sort-Object { "$($_.What)" })
        $parts = @($evs | ForEach-Object { ConvertTo-HistoryEntry -Event $_ -AppName "$($App.DisplayName)" -GroupMap $GroupMap })
        $lines = New-Object 'System.Collections.Generic.List[string]'
        foreach ($p in $parts) { foreach ($l in $p.Lines) { if (-not $lines.Contains($l)) { [void]$lines.Add($l) } } }
        $titles = @($parts | ForEach-Object { $_.Title } | Select-Object -Unique)
        $title  = $(if ($titles.Count -eq 1) { $titles[0] } else { ($titles | Where-Object { $_ -ne 'App re-saved (no visible change)' }) -join ' + ' })
        if (-not $title) { $title = 'App re-saved (no visible change)' }
        $kind = ($parts | ForEach-Object { $_.Kind } | Where-Object { $_ -ne 'minor' -and $_ -ne 'edit' } | Select-Object -First 1)
        if (-not $kind) { $kind = $parts[0].Kind }
        foreach ($l in $lines) {
            if ($l -match '^(?<f>[^:]+):\s*(?<o>.*?)\s+->\s+(?<n>.*)$') {
                $nv = $Matches.n -replace '\s*\([^)]*\)\s*$', ''      # "3  (new package content)" -> "3"
                [void]$covered.Add(("$($Matches.f)|$nv").ToLower())
            }
        }
        [void]$entries.Add([pscustomobject]@{
            When = "$($evs[0].When)"; Who = "$($evs[0].Who)"; WhoText = (Format-Who "$($evs[0].Who)" "$($evs[0].WhoId)")
            Title = $title; Lines = $lines.ToArray(); Kind = $kind; Source = 'Intune audit'
            Legacy = [bool]($parts | Where-Object { $_.Legacy } | Select-Object -First 1)
            App = "$($App.DisplayName)"; AppId = "$($App.Id)"
        })
    }

    # 2. dated lines inside the notes ("[2025-01-30] set to LIVE") - the only trail older than audit retention
    foreach ($e in (AsArray $App.NoteEvents)) {
        [void]$entries.Add([pscustomobject]@{ When = "$($e.When)"; Who = ''; WhoText = 'from app notes'; Title = 'Note'; Lines = @("$($e.What)"); Kind = 'note'; Source = 'App notes'; Legacy = $false; App = "$($App.DisplayName)"; AppId = "$($App.Id)" })
    }

    # 3. this tool's own snapshot diffs - only what the audit did not already explain
    $friendlySnap = @{ DisplayVersion = 'Version'; Lifecycle = 'Lifecycle'; CreatedVia = 'Created via'; NoteStatus = 'Status'; AssignmentSummary = 'Assignments'
                       InstallCommandLine = 'Install command'; UninstallCommandLine = 'Uninstall command'; SetupFilePath = 'Setup file'; RunAsAccount = 'Run as'
                       ContentVersion = 'Content version'; Publisher = 'Publisher'; Owner = 'Owner'; NotesText = 'Note text'; ManagedText = 'Managed'; PilotDate = 'Pilot date'; RolloutDate = 'Rollout date' }
    # A sync diff is stamped with the SYNC time, not the change time. When the audit already holds events
    # of the same kind for this app inside that sync window, the audit entry (real time, real author) wins.
    $syncTimes = @((AsArray $ChangeLog) | ForEach-Object { "$($_.When)" } | Sort-Object -Unique)
    $auditWhens = @{ assign = @(); edit = @() }
    foreach ($e in (AsArray $App.AuditEvents)) {
        $w = "$($e.When)"; if ($w.Length -ge 19) { $w = $w.Substring(0, 19) }
        if ("$($e.What)" -match 'MobileAppAssignment$') { $auditWhens.assign += $w } else { $auditWhens.edit += $w }
    }
    $auditCovers = {
        param([string]$syncWhen, [string]$bucket)
        $prev = ''; foreach ($t in $syncTimes) { if ($t -lt $syncWhen) { $prev = $t } }
        if (-not $prev) { try { $prev = ([datetime]$syncWhen).AddDays(-60).ToString('s') } catch { $prev = '' } }
        foreach ($w in $auditWhens[$bucket]) { if ($w -gt $prev -and $w -le $syncWhen) { return $true } }
        return $false
    }
    foreach ($c in (AsArray $ChangeLog)) {
        if ("$($c.AppId)" -ne "$($App.Id)") { continue }
        if ($c.Type -ne 'Modified') {
            # "Added" only means this tool had not seen the app before; the audit's "App created" is the real
            # birth. Show it only when there is no audit history at all. "Removed" is always worth a line.
            if ($c.Type -eq 'Added' -and (AsArray $App.AuditEvents).Count -gt 0) { continue }
            [void]$entries.Add([pscustomobject]@{ When = "$($c.When)"; Who = ''; WhoText = 'seen by sync'; Title = $(if ($c.Type -eq 'Added') { 'First seen by this tool' } else { 'No longer in Intune' }); Lines = @(); Kind = $(if ($c.Type -eq 'Added') { 'create' } else { 'delete' }); Source = 'Snapshot diff'; Legacy = $false; App = "$($App.DisplayName)"; AppId = "$($App.Id)" })
            continue
        }
        $f = $(if ($friendlySnap.ContainsKey("$($c.Property)")) { $friendlySnap["$($c.Property)"] } else { "$($c.Property)" })
        if ($covered.Contains(("$f|$($c.New)").ToLower())) { continue }
        if ("$($c.Property)" -eq 'AssignmentSummary') {
            # Old ledgers hold "changes" that were only the summary's format flipping (see Compare-Snapshots).
            # Same words in a different order or punctuation is not a change.
            $wo = @("$($c.Old)" -split '[;:\s]+' | Where-Object { $_ } | Sort-Object) -join ' '
            $wn = @("$($c.New)" -split '[;:\s]+' | Where-Object { $_ } | Sort-Object) -join ' '
            if ($wo -eq $wn) { continue }
            if (& $auditCovers "$($c.When)" 'assign') { continue }
            # Say what moved, not two long strings: "Added: required -> MDM_X", "Removed: available -> MDM_Y".
            # This is also the only place assignment TARGETS survive when Intune's audit recorded none.
            $setO = @("$($c.Old)" -split ';\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $setN = @("$($c.New)" -split ';\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $asgLines = New-Object 'System.Collections.Generic.List[string]'
            foreach ($x in $setN) { if ($setO -notcontains $x) { [void]$asgLines.Add("Added: $($x -replace ':\s*', '  ->  ')") } }
            foreach ($x in $setO) { if ($setN -notcontains $x) { [void]$asgLines.Add("Removed: $($x -replace ':\s*', '  ->  ')") } }
            if ($asgLines.Count) {
                [void]$entries.Add([pscustomobject]@{ When = "$($c.When)"; Who = ''; WhoText = 'seen by sync (author not in audit)'; Title = 'Assignments changed'; Lines = $asgLines.ToArray(); Kind = 'assign'; Source = 'Snapshot diff'; Legacy = $false; App = "$($App.DisplayName)"; AppId = "$($App.Id)" })
                continue
            }
        }
        # Content/version/lifecycle diffs: the audit's Patch events carry the same change with a real time.
        if ($f -in 'Content version','Version','Lifecycle','Install command','Uninstall command','Setup file','Run as','Publisher','Owner','Status','Managed','Note text' -and (& $auditCovers "$($c.When)" 'edit')) { continue }
        [void]$entries.Add([pscustomobject]@{ When = "$($c.When)"; Who = ''; WhoText = 'seen by sync (author not in audit)'; Title = "$f changed"; Lines = @((Format-Change $f $c.Old $c.New)); Kind = $(if ($f -eq 'Version') { 'version' } elseif ($f -eq 'Lifecycle') { 'lifecycle' } else { 'edit' }); Source = 'Snapshot diff'; Legacy = $false; App = "$($App.DisplayName)"; AppId = "$($App.Id)" })
    }

    return ,@($entries.ToArray() | Sort-Object { "$($_.When)" } -Descending)
}

# Tenant-wide activity: every entry of every app, newest first - the "what changed this week, by whom"
# report. Translating ~20k events takes a minute or two in PowerShell, so the result is kept per app in
# ActivityFeed.json with a stamp (event count, newest event, ledger rows, directory sizes); on the next
# build only apps whose stamp moved are translated again - seconds, not minutes.
$script:FeedVersion = 5
function Get-ActivityFeed {
    param([object[]]$Apps, [object[]]$ChangeLog, [hashtable]$GroupMap, [string]$CachePath, [scriptblock]$Progress)
    $apps = AsArray $Apps
    $store = @{}
    if ($CachePath -and (Test-Path $CachePath)) {
        try { $j = Get-Content -LiteralPath $CachePath -Raw -Encoding UTF8 | ConvertFrom-Json; if ([int]$j.Version -eq $script:FeedVersion) { foreach ($p in $j.Apps.PSObject.Properties) { $store[$p.Name] = $p.Value } } }
        catch { Write-Log "ActivityFeed.json unreadable - rebuilding. ($($_.Exception.Message))" Warning }
    }
    $ledgerRows = @{}
    foreach ($c in (AsArray $ChangeLog)) { $k = "$($c.AppId)"; $ledgerRows[$k] = [int]$ledgerRows[$k] + 1 }
    $dirStamp = "$($script:UserMap.Count)|$($GroupMap.Count)"

    $all = New-Object 'System.Collections.Generic.List[object]'
    $fresh = @{}
    $n = 0; $rebuilt = 0
    foreach ($a in $apps) {
        $n++
        $evs = AsArray $a.AuditEvents
        $newest = $(if ($evs.Count) { "$($evs[0].When)" } else { '' })
        $stamp = "$($evs.Count)|$newest|$([int]$ledgerRows["$($a.Id)"])|$dirStamp|$($a.DisplayName)"
        $hit = $store["$($a.Id)"]
        if ($hit -and "$($hit.Stamp)" -eq $stamp) {
            $entries = AsArray $hit.Entries
        } else {
            if ($Progress -and ($rebuilt % 50 -eq 0)) { try { & $Progress "Translating change history ($n of $($apps.Count) apps)..." -1 } catch {} }
            $entries = AsArray (Get-ChangeHistory -App $a -ChangeLog $ChangeLog -GroupMap $GroupMap)
            $rebuilt++
        }
        $fresh["$($a.Id)"] = [pscustomobject]@{ Stamp = $stamp; Entries = $entries }
        foreach ($e in $entries) { [void]$all.Add($e) }
    }
    if ($CachePath -and $rebuilt -gt 0) {
        try {
            $json = [pscustomobject]@{ Version = $script:FeedVersion; Apps = [pscustomobject]$fresh } | ConvertTo-Json -Depth 8 -Compress
            [IO.File]::WriteAllText($CachePath, $json, (New-Object Text.UTF8Encoding($false)))
        } catch { Write-Log "Could not save ActivityFeed.json: $($_.Exception.Message)" Warning }
    }
    Write-Log "Activity feed: $($all.Count) entries, $rebuilt of $($apps.Count) apps re-translated."
    return ,@($all.ToArray() | Sort-Object { "$($_.When)" } -Descending)
}

# What the history can and cannot cover, in one sentence for the UI.
function Get-HistoryCoverage {
    param($Cache)
    $from = $null; try { if ($Cache.BackfilledFromUtc) { $from = [datetime]$Cache.BackfilledFromUtc } } catch {}
    $oldest = $null
    foreach ($k in $Cache.Apps.Keys) { foreach ($e in (AsArray $Cache.Apps[$k].Events)) { $w = $null; try { $w = [datetime]"$($e.When)" } catch {}; if ($w -and (-not $oldest -or $w -lt $oldest)) { $oldest = $w } } }
    $events = 0; foreach ($k in $Cache.Apps.Keys) { $events += (AsArray $Cache.Apps[$k].Events).Count }
    [pscustomobject]@{
        From = $(if ($oldest) { $oldest } else { $from }); Events = $events; Apps = @($Cache.Apps.Keys).Count
        People = @($Cache.Users.Keys | Where-Object { "$(Get-P $Cache.Users[$_] 'Name')" }).Count
        Groups = @($Cache.Groups.Keys | Where-Object { "$($Cache.Groups[$_])" }).Count
        Legacy = [bool]$Cache.Legacy
    }
}