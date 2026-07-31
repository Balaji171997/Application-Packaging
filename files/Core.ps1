##############################################################
# Core.ps1
# Config, logging, package-name parse, and the version-swap
# utilities that implement Plan section 1 (one-dot-prefix swap).
##############################################################

$script:BuildStamp = '2026-07-30.r220'  # shown in the WINDOW TITLE so you always know which build/pak you run

# SNIPPET OWNERS - only these Windows usernames see the Add / Edit / Delete snippet buttons (everyone else just USES the
# shared library). Baked into the ENCRYPTED pak (users get exe+pak only, so they can't read/change this - unlike
# settings.json which sits editable on the share). To add an owner: add the username here and repack. Case-insensitive.
$script:SnippetOwners = @('AW140')
function Test-IsSnippetOwner {
    $me = "$env:USERNAME".Trim().ToLower()
    return (@($script:SnippetOwners | ForEach-Object { "$_".Trim().ToLower() }) -contains $me)
}

# Folder the tool runs from - the .ps1 dir when run as scripts, the .exe dir once packaged.
# Everything (Lib\, PSADT_Template\, ConfigurationManagerPrelive\, modules) is resolved from here,
# so nothing is hard-coded to C:\ and the portable exe just works wherever it's copied.
function Get-ToolRoot {
    if ($script:ToolRoot) { return $script:ToolRoot }
    $r = $PSScriptRoot
    if (-not $r) { try { $r = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) } catch {} }
    if (-not $r) { $r = (Get-Location).Path }
    $script:ToolRoot = $r
    return $r
}
# Resolve a possibly-relative path against the tool root (absolute paths pass through unchanged).
function Resolve-ToolPath {
    param([string]$Path)
    if (-not $Path) { return $null }
    if ([IO.Path]::IsPathRooted($Path)) { return $Path }
    return (Join-Path (Get-ToolRoot) $Path)
}

# Find a built package's Icons folder from ANY path level the caller might pass (the package ROOT, the Content folder,
# or a subfolder). Icons sits at the package ROOT (a SIBLING of Content), so if the caller passes the Content folder a
# bare "<given>\Icons" misses it - which made Intune LOSE the app icon on a content update. Checks the likely spots
# (incl. the parent when given a Content folder), then any Icons folder under the path. Returns '' when none exists.
function Resolve-IconsDir {
    param([string]$PackagePath)
    if (-not $PackagePath) { return '' }
    $cands = New-Object System.Collections.Generic.List[string]
    $cands.Add((Join-Path $PackagePath 'Icons'))
    $cands.Add((Join-Path $PackagePath 'Content\Icons'))
    if ((Split-Path $PackagePath -Leaf) -match '(?i)^Content$') { $cands.Add((Join-Path (Split-Path $PackagePath -Parent) 'Icons')) }
    $hit = $cands | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if (-not $hit) {
        $hit = (Get-ChildItem -LiteralPath $PackagePath -Directory -Recurse -Depth 3 -Filter 'Icons' -ErrorAction SilentlyContinue |
                Sort-Object { ($_.FullName -split '[\\/]').Count } | Select-Object -First 1).FullName
    }
    if ($hit -and (Test-Path -LiteralPath $hit)) { return "$hit" }
    return ''
}

#region Work folders (one place for everything) -----------------
# Single base for ALL runtime output so nothing scatters across %TEMP%/C:\temp. Override via
# settings.json -> "WorkRoot". Subfolders: Logs, IntuneWin, Downloads, Build, Temp.
function Get-WorkRoot {
    if ($script:WorkRoot) { return $script:WorkRoot }
    $r = $null
    try { if (Get-Command Get-Setting -ErrorAction SilentlyContinue) { $r = Get-Setting 'WorkRoot' } } catch {}
    if (-not $r) { $r = 'C:\temp\PackageBuilder' }
    $script:WorkRoot = $r; return $r
}
function Get-WorkPath {
    param([string]$Sub)
    $p = if ($Sub) { Join-Path (Get-WorkRoot) $Sub } else { Get-WorkRoot }
    try { if (-not (Test-Path $p)) { New-Item $p -ItemType Directory -Force | Out-Null } } catch {}
    return $p
}
#endregion

#region Self-stage to local (run-from-share -> mirror to %LOCALAPPDATA% and run there) -------------------------------
# WHY: launching the exe from a UNC/network share breaks SCCM (WMI) + Intune (WinHTTP/DNS) network calls (proven: a local
# copy works, the share doesn't). So when we detect a NETWORK launch we mirror the CORE (package-building) files to a
# LOCAL cache and RE-LAUNCH the local exe - network then works. The HEAVY SCCM/Intune modules are copied LATER, on demand
# (Ensure-PublishModulesStaged, when the user actually publishes), to keep the first launch small + fast.
function Test-NetworkPath {
    param([string]$Path)
    if (-not $Path) { return $false }
    if ($Path -match '^\\\\') { return $true }                                  # UNC
    try { $r = [IO.Path]::GetPathRoot($Path); if ($r -match '^[A-Za-z]:\\$') { return ((New-Object IO.DriveInfo $r).DriveType -eq [IO.DriveType]::Network) } } catch {}   # mapped drive
    return $false
}
function Get-LocalStageRoot { Join-Path $env:LOCALAPPDATA 'PackageBuilder' }

# Copy a single file only when the source is NEWER or the destination is missing (keeps launches/updates cheap).
function Copy-IfNewer {
    param([string]$Source, [string]$Dest)
    if (-not (Test-Path -LiteralPath $Source)) { return }
    $need = $true
    if (Test-Path -LiteralPath $Dest) { $need = ((Get-Item -LiteralPath $Source -Force).LastWriteTimeUtc -gt (Get-Item -LiteralPath $Dest -Force).LastWriteTimeUtc) }   # -Force: Get-Item THROWS on a Hidden file without it (deployed pak is Hidden) - that crashed the self-stage with "cannot find path"
    if ($need) {
        $dir = Split-Path -Parent $Dest; if ($dir -and -not (Test-Path $dir)) { New-Item $dir -ItemType Directory -Force | Out-Null }
        try { $di = Get-Item -LiteralPath $Dest -Force -ErrorAction SilentlyContinue; if ($di) { $di.IsReadOnly = $false } } catch {}
        try { Copy-Item -LiteralPath $Source -Destination $Dest -Force } catch {}
    }
}
# Mirror a folder tree copying only newer/missing files (robocopy /XO). Robust for the large ConfigMgr module tree.
function Copy-TreeNewer {
    param([string]$Source, [string]$Dest)
    if (-not (Test-Path -LiteralPath $Source)) { return }
    if (-not (Test-Path -LiteralPath $Dest)) { New-Item $Dest -ItemType Directory -Force | Out-Null }
    try { & robocopy $Source $Dest /E /XO /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null } catch {}
}

# Remember / read the share source path (so the heavy modules can be pulled later, on demand).
function Set-StageSource { param([string]$LocalRoot, [string]$Source) try { Set-Content -LiteralPath (Join-Path $LocalRoot '.source') -Value $Source -Encoding UTF8 -Force } catch {} }
function Get-StageSource {
    param([string]$ToolRoot)
    $m = Join-Path $ToolRoot '.source'
    if (Test-Path $m) { try { $v = (Get-Content -LiteralPath $m -Raw).Trim(); if ($v) { return $v } } catch {} }
    if ($env:PB_SHAREROOT) { return "$env:PB_SHAREROOT" }   # fallback: set by the relaunch (share -> local handoff)
    return ''
}

# Mirror the CORE files from a network ToolRoot to the local cache. Returns the LOCAL exe path (to re-launch), or $null
# when not a network launch / staging failed (caller then just runs in place).
function Invoke-SelfStage {
    param([string]$Root, [string]$Local, [switch]$Force)
    if (-not $Root) { return $null }
    if (-not $Force -and -not (Test-NetworkPath $Root)) { return $null }        # already local -> run in place
    $local = if ($Local) { $Local } else { Get-LocalStageRoot }
    try {
        if (-not (Test-Path $local)) { New-Item $local -ItemType Directory -Force | Out-Null }
        foreach ($f in 'PackageBuilder.exe','PackageBuilder.exe.config','PackageBuilder.pak','settings.json','snippets.json','KnowledgeBase.Recommend.json',
                       'Lib\ICSharpCode.AvalonEdit.dll','Lib\PackageBuilder.ico') {
            Copy-IfNewer -Source (Join-Path $Root $f) -Dest (Join-Path $local $f)
        }
        foreach ($t in 'PSADT_Template','Lib\PSADT_Template') { $s = Join-Path $Root $t; if (Test-Path $s) { Copy-TreeNewer -Source $s -Dest (Join-Path $local $t) } }
        foreach ($z in 'PSADT_Template.zip','Lib\PSADT_Template.zip') { Copy-IfNewer -Source (Join-Path $Root $z) -Dest (Join-Path $local $z) }
        # EXTRA TOOLS the packager drops next to the exe (PsExec.exe for SYSTEM testing, or anything in Tools\/PsExec\):
        # mirror them into the LOCAL copy too, so the relaunched local exe finds them (they were being left on the share).
        foreach ($ex in @(Get-ChildItem -LiteralPath $Root -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)^PsExec.*\.exe$' })) { Copy-IfNewer -Source $ex.FullName -Dest (Join-Path $local $ex.Name) }
        foreach ($td in 'PsExec','Tools') { $s = Join-Path $Root $td; if (Test-Path $s) { Copy-TreeNewer -Source $s -Dest (Join-Path $local $td) } }
        Set-StageSource -LocalRoot $local -Source $Root
        $exe = Join-Path $local 'PackageBuilder.exe'
        if (Test-Path $exe) { return $exe }
    } catch { if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "Self-stage to local failed: $($_.Exception.Message). Running from the current location." Warning } }
    return $null
}

# On demand (first SCCM/Intune use): mirror the HEAVY publish modules from the share source into the local cache Lib, so
# Connect-Sccm / Connect-Intune find them locally. Idempotent (newer-only). No-op when there is no share source (a full
# local copy already has everything). Safe to call from a publish runspace.
function Ensure-PublishModulesStaged {
    param([string]$ToolRoot)
    if (-not $ToolRoot) { $ToolRoot = Get-ToolRoot }
    $src = Get-StageSource -ToolRoot $ToolRoot
    if (-not $src -or -not (Test-Path $src)) { return }                         # full local copy already has the modules
    if (Get-Command Set-PbProgress -ErrorAction SilentlyContinue) { Set-PbProgress -Indeterminate -Status 'Preparing SCCM / Intune modules (first time)...' }
    foreach ($d in 'Lib\ConfigurationManagerPrelive', 'Lib\PowerShell Module', 'Lib\IntuneUtilitiesForPSADTv3') {
        $s = Join-Path $src $d; if (Test-Path $s) { Copy-TreeNewer -Source $s -Dest (Join-Path $ToolRoot $d) }
    }
    Copy-IfNewer -Source (Join-Path $src 'Lib\IntuneWinAppUtil.exe') -Dest (Join-Path $ToolRoot 'Lib\IntuneWinAppUtil.exe')
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "Publish modules staged into the local copy from $src." }
}
#endregion

#region Unblock (Mark of the Web) -------------------------------
# Windows stamps a Zone.Identifier alternate data stream ("Mark of the Web") on every file copied from a network
# share (our LIVE/Incoming shares) or downloaded from the internet. Running such an EXE then trips the "Open File -
# Security Warning" dialog / SmartScreen, which BLOCKS or badly delays the launch - a copied installer can stall for
# many seconds before it even starts. So strip the stream after EVERY copy / extract the tool does. Unblock-File is
# a no-op on files that don't have the stream, and is best-effort here (never throws, never blocks the caller).
function Unblock-PBPath {
    param([Parameter(Mandatory)][string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)) { return }
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($item.PSIsContainer) {
            Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
                ForEach-Object { try { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue } catch {} }
        } else {
            try { Unblock-File -LiteralPath $item.FullName -ErrorAction SilentlyContinue } catch {}
        }
    } catch {}
}
#endregion

#region Logging -------------------------------------------------
$script:LogFilePath = $null
function Get-LogPath { if (-not $script:LogFilePath) { $script:LogFilePath = Join-Path (Get-WorkPath 'Logs') 'PackageBuilder.log' }; return $script:LogFilePath }
function Initialize-Log {
    try { $script:LogFilePath = Join-Path (Get-WorkPath 'Logs') 'PackageBuilder.log'; "" | Out-File $script:LogFilePath -Encoding utf8 -Force } catch {}
}
function Write-Log {
    param([Parameter(Position=0)][string]$Message, [Parameter(Position=1)][string]$Level = 'Info')
    $tag = switch ($Level) { 'Success'{'[OK]'} 'Warning'{'[!!]'} 'Error'{'[XX]'} default{'[i] '} }
    $line = "{0} {1} {2}" -f (Get-Date -Format 'HH:mm:ss'), $tag, $Message
    # Console echo ONLY in a real console host. Inside the ps2exe -noConsole exe, Write-Host is
    # rerouted to a blocking MessageBox per line ("click OK" at startup) - the log file is the
    # record there; the popups must never happen.
    if ($Host.Name -eq 'ConsoleHost') { Write-Host $line }
    try { $line | Out-File (Get-LogPath) -Encoding utf8 -Append } catch {}
}

# Report progress to the GUI. The publish runspace sets $Global:PBProgress to a synchronized
# hashtable; the window's DispatcherTimer reads it to drive the progress bar + status line.
# No-op everywhere else (CLI, Test-Build), so engine code can call it unconditionally.
function Set-PbProgress {
    param([int]$Percent = -1, [string]$Status, [switch]$Indeterminate)
    $p = $Global:PBProgress
    if (-not $p) { return }
    if ($Indeterminate)     { $p.Indeterminate = $true }
    elseif ($Percent -ge 0) { $p.Percent = $Percent; $p.Indeterminate = $false }
    if ($Status)            { $p.Status = $Status }
}
#endregion

#region Package name --------------------------------------------
function Parse-PackageName {
    param([Parameter(Mandatory)][string]$Name)
    $p = '^(?<Vendor>[^_]+)_(?<AppName>.+)_(?<Arch>x86|x64|x86_64|ALL)_(?<Version>[^_]+)-(?<Release>\d{4})_(?<Lang>[\w\-]+)$'
    if ($Name -match $p) {
        return @{ IsValid=$true; FullName=$Name; Vendor=$Matches.Vendor; AppName=$Matches.AppName
                  Arch=$Matches.Arch; Version=$Matches.Version; Release=$Matches.Release; Lang=$Matches.Lang }
    }
    return @{ IsValid=$false; FullName=$Name }
}
#endregion

#region Version swap (Plan section 1) ---------------------------
# Build ordered, longest-first (Old,New) prefix pairs down to the
# one-dot (2-component) prefix. Identical pairs are dropped.
#   1.2.3.4 -> 1.5.6.7  yields  (1.2.3.4->1.5.6.7)(1.2.3->1.5.6)(1.2->1.5)
function Get-VersionPrefixPairs {
    param([string]$OldVersion, [string]$NewVersion)
    if (-not $OldVersion -or -not $NewVersion) { return @() }
    $o = $OldVersion.Split('.'); $n = $NewVersion.Split('.')
    if ($o.Count -lt 2) { return @() }                 # no dot -> not a version, never swap
    $pairs = New-Object System.Collections.Generic.List[object]
    $seen  = New-Object System.Collections.Generic.HashSet[string]
    # Pad OLD up to NEW's length with zeros so a 3-part name-version (24.1.0) still swaps a 4-part DisplayVersion
    # (24.1.0.0 -> 26.0.0.0). NEW keeps min-truncation (a shorter new like 1.5 still yields 1.2.3.4 -> 1.5, unchanged).
    $L = [Math]::Max($o.Count, $n.Count)
    $oPad = @($o) + @('0') * [Math]::Max(0, $L - $o.Count)
    for ($k = $L; $k -ge 2; $k--) {
        $op = ($oPad[0..($k-1)]) -join '.'
        $nk = [Math]::Min($k, $n.Count)
        $np = ($n[0..($nk-1)]) -join '.'
        if ($op -ne $np -and $seen.Add($op)) {
            $pairs.Add(@{ Old = $op; New = $np })
        }
    }
    # YEAR-FORM (vendors like nCode name folders/keys "20YY.M": nCode 2024.1 64-bit, DisplayName "nCode 2024.1").
    # When the MAJOR is a 2-digit year suffix (24 -> 2024), also swap "20<oldMajor>.<oldMinor>" -> "20<newMajor>.<newMinor>"
    # (e.g. 2024.1 -> 2026.0). The required ".minor" + digit-anchors keep bare years / dates / copyrights untouched.
    if ($o.Count -ge 2 -and $n.Count -ge 2 -and $o[0] -match '^\d{2}$' -and $n[0] -match '^\d{2}$') {
        $oy = "20$($o[0]).$($o[1])"; $ny = "20$($n[0]).$($n[1])"
        if ($oy -ne $ny -and $seen.Add($oy)) { $pairs.Add(@{ Old = $oy; New = $ny }) }
    }
    # Longest Old first (so 2024.1 / 24.1.0.0 win before their shorter prefixes).
    return @($pairs | Sort-Object @{ e = { $_.Old.Length }; Descending = $true })
}

# Swap predecessor version -> new version everywhere in $Text, anchored so
# a prefix is only replaced when it is NOT bordered by another digit or dot.
# Longest-first means 1.2.3.4 is consumed before the 1.2 pass runs, and
# '11.2' / '1.2.3.4.5' / bare years are never touched.
function Invoke-VersionSwap {
    param([string]$Text, [string]$OldVersion, [string]$NewVersion)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    foreach ($p in (Get-VersionPrefixPairs -OldVersion $OldVersion -NewVersion $NewVersion)) {
        # Anchor: not bordered by another version digit. The trailing guard blocks a following digit OR ".<digit>"
        # (so 1.2 is never pulled out of 1.2.3), but ALLOWS a following ".<non-digit>" so a version-named FILE or
        # folder still swaps: "nCode 2024.1.lnk" -> "nCode 2026.0.lnk", "app_24.1.0.exe" -> "app_26.0.0.exe".
        $pat  = '(?<![\d.])' + [regex]::Escape($p.Old) + '(?!\d)(?!\.\d)'
        $Text = [regex]::Replace($Text, $pat, $p.New)
    }
    return $Text
}
#endregion

#region Config (safe - never wipes settings.json on parse failure) ----
$script:Settings          = $null
$script:SettingsPath      = $null
$script:ConfigParseFailed = $false

function Initialize-Config {
    param([string]$Path)
    $script:SettingsPath = $Path
    $defaults = [ordered]@{
        WorkRoot             = 'C:\temp\PackageBuilder'
        LocalWorkingDir      = (Join-Path (Get-WorkRoot) 'Build')
        DefaultMsiProperties = @('ALLUSERS=1','REBOOT=ReallySuppress')
        AutoDetectAuthor     = $true
        DefaultAuthor        = ''
        PredecessorPath      = '\\mbddfsovpc01.mn-man.biz\SWDLive-Gate\CMLib_LIVE\Apps'
        OutputBasePath       = 'c:\temp'
        RepositoryPath       = '\\mndemucfsm01\SEC-EQS-Lib-Gate\EQS_SEC\EQS\Packages\Incoming'
        OutgoingPath         = '\\mndemucfsm01\SEC-EQS-Lib-Gate\EQS_SEC\EQS\Packages\Outgoing'
        SharePointPath       = ''
        # Point this at ONE shared file on the team share so everyone reads + writes the SAME snippet library
        # (Add/Delete in the tool re-read + merge, so different people's additions accumulate). Empty = the local
        # snippets.json next to the exe (personal only).
        SnippetsPath         = ''
        Sccm                 = [ordered]@{
            SiteCode='G08'; SiteServer='mbdcaswvtb29843.mn-man.biz'
            ContentShare='\\mbddfsovpc01.mn-man.biz\SWDPreLive-Gate\CMLib_TEST\Apps'; DPGroup='_ALL_DPs'
            AppFolder='G08:\Application\VOLKSWAGEN\DEVELOPMENT\EQS'; CollectionFolder='G08:\DeviceCollection\DEVELOPMENT\EQS'
            LimitingCollection='All Systems'; ModuleRelPath='ConfigurationManagerPrelive\ConfigurationManager\ConfigurationManager.psd1'
            CMTracePath='C:\Windows\CCM\CMTrace.exe' }
        Intune               = [ordered]@{ TenantId=''; IntuneWinAppUtil=''; ModulePath='Lib' }
    }
    $h = @{}; foreach ($k in $defaults.Keys) { $h[$k] = $defaults[$k] }
    if ($Path -and (Test-Path $Path)) {
        try {
            $raw  = if (Get-Command Read-FileSmart -ErrorAction SilentlyContinue) { Read-FileSmart -Path $Path } else { Get-Content $Path -Raw }
            $json = $raw | ConvertFrom-Json -ErrorAction Stop
            foreach ($p in $json.PSObject.Properties) { $h[$p.Name] = $p.Value }
            $script:ConfigParseFailed = $false
            Write-Log "Config loaded: $Path"
        } catch {
            $script:ConfigParseFailed = $true
            Write-Log "settings.json is invalid - using defaults and NOT overwriting your file ($($_.Exception.Message))" Warning
        }
    } elseif ($Path) {
        # No settings file yet: write a starter with all the default paths so it's easy to edit.
        try { $defaults | ConvertTo-Json -Depth 6 | Out-File $Path -Encoding utf8 -Force; Write-Log "Wrote default settings.json -> $Path" Success }
        catch { Write-Log "Could not write default settings.json: $($_.Exception.Message)" Warning }
    }
    $script:Settings = $h
    $script:WorkRoot = $null   # re-resolve WorkRoot now that settings are loaded (honours a custom value)
}

function Get-Setting {
    param([string]$Name, $Default = $null)
    if ($script:Settings -and $script:Settings.ContainsKey($Name) -and $null -ne $script:Settings[$Name]) {
        return $script:Settings[$Name]
    }
    return $Default
}

# Lift the execution policy for THIS PROCESS ONLY, so SCRIPT modules (ConfigMgr AdminUI.PS, MSAL.PS, IntuneWin32App)
# import even when the machine/user policy is Restricted/Undefined - common on the 32-bit WOW6432Node hive the ps2exe
# launcher reads. In-memory, no admin rights, no registry write, gone when the tool exits. Only a GPO-set
# MachinePolicy/UserPolicy can override it; then we warn and let the caller continue. Idempotent + cheap - both the SCCM
# and Intune module imports call it so no integration forgets it ("running scripts is disabled" was hitting Intune).
function Enable-PBProcessScripts {
    try {
        if ((Get-ExecutionPolicy -Scope Process) -eq 'Bypass') { return $true }
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop
        return $true
    } catch {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "Could not relax the execution policy for this process - a GPO may enforce it: $($_.Exception.Message)" Warning }
        return $false
    }
}

# Author DISPLAY NAME (not the login id). Priority: settings.json DefaultAuthor ->
# AD/local display name -> finally the username as a last resort.
$script:ResolvedAuthor = $null
function Get-AuthorName {
    if ($script:ResolvedAuthor) { return $script:ResolvedAuthor }
    $a = Get-Setting DefaultAuthor
    if (-not $a) {
        try {
            Add-Type -AssemblyName System.DirectoryServices.AccountManagement -ErrorAction Stop
            $a = [System.DirectoryServices.AccountManagement.UserPrincipal]::Current.DisplayName
        } catch {}
    }
    if (-not $a) { try { $a = "$(([adsi]"WinNT://$env:USERDOMAIN/$env:USERNAME,user").FullName)" } catch {} }
    if (-not $a) { $a = $env:USERNAME }
    # Strip a trailing domain/qualifier in parentheses, e.g. "Balaji, Gurram (EXTERN: FIOCC)".
    $a = ([regex]::Replace("$a", '\s*\(.*?\)\s*$', '')).Trim()
    $script:ResolvedAuthor = "$a"
    return $script:ResolvedAuthor
}

function Save-Config {
    if ($script:ConfigParseFailed) {
        Write-Log "Refusing to save settings.json: last load failed to parse (would overwrite your edits)." Warning
        return $false
    }
    if (-not $script:SettingsPath) { return $false }
    try {
        $script:Settings | ConvertTo-Json -Depth 6 | Out-File $script:SettingsPath -Encoding utf8 -Force
        Write-Log "Config saved." Success; return $true
    } catch { Write-Log "Config save failed: $($_.Exception.Message)" Error; return $false }
}
#endregion







