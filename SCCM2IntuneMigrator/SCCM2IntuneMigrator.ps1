##############################################################################################
# MAN_SCCM2IntuneMigrator.ps1
#
# ONE script that replaces the four MAN_SCCM2IntuneMgrationTool_*.ps1 variants (Icon /
# Icon_NoDetection / Icon_newPSADT). The behaviour that used to be a different FILE is now
# DETECTED PER APPLICATION at runtime:
#
#   * PSADT generation .... v3 (Deploy-Application.exe + ServiceUI) vs v4 (Invoke-AppDeployToolkit.exe)
#                           is decided from the content that is actually on the source share -
#                           _newPSADT.ps1 is no longer a separate file.
#   * Detection ........... read from the SCCM deployment type. When SCCM has NO detection clause
#                           at all, the configured branding key <BrandingKeyRoot>\<FullName>
#                           [Revision] is synthesised - that was _NoDetection.ps1.
#   * Icon ................ SCCM icon -> validated/converted to real PNG. Unusable or missing ->
#                           icon found in the SOURCE CONTENT location -> converted to PNG.
#                           Nothing found -> the default icon in Assets\DefaultAppIcon.png.
#   * Description ......... SCCM description -> else the package's "Installation instructions"
#                           .docx in the content location (BOTH the short and the detailed
#                           English description) -> else a generated one.
#   * Large content ....... NO 30 GB abort. The .intunewin is uploaded by our own chunked block
#                           uploader with mid-upload SAS renewal + per-block resume, so multi-GB
#                           applications upload instead of failing.
#
# PreLive is deliberately NOT part of this script (it stays its own tool) - only the site code /
# site server in settings.json differ there.
#
# Everything the run produces (staged content, .intunewin, per-app log, HTML/CSV/JSON report) is
# kept on disk under <ReportRoot> so a failed application can be inspected and retried.
##############################################################################################
#Requires -Version 5.1
[CmdletBinding()]
param(
    # Which profile in settings.json to use (site code / site server / tenant / naming format /
    # group pattern). Omitted -> the file's ActiveProfile, or the first profile defined.
    [string]   $ProfileName,
    # Unattended mode: migrate the named applications without showing the window.
    [switch]   $NoGui,
    [string[]] $Application,
    [string]   $SettingsPath,
    # Read everything from SCCM, build the .intunewin, but create NOTHING in Intune.
    [switch]   $WhatIfMigration
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Off

$script:ToolRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

##############################################################################################
# region SETTINGS
##############################################################################################
# NOTHING organisation-specific is hard-coded here. Every value below is a neutral fallback; the
# real site codes, site servers, tenants, key roots and naming formats live in settings.json as
# named PROFILES, so the same script serves several sites and several brands unchanged. Add a
# profile, pick it in the window (or with -Profile), and nothing in this file has to change.
$script:DefaultSettings = [ordered]@{
    # --- SCCM -------------------------------------------------------------------------------
    SiteCode                    = ''          # from the selected profile in settings.json
    SiteServer                  = ''          # from the selected profile in settings.json
    # --- Intune / Entra ---------------------------------------------------------------------
    TenantId                    = ''          # from the selected profile in settings.json
    GraphBase                   = 'https://graph.microsoft.com/beta'
    # --- Where the tool keeps its work + reports ---------------------------------------------
    ReportRoot                  = "$env:ProgramData\SCCM2IntuneMigrator"
    KeepStagedContent           = $true      # keep the exact folder that was wrapped, for inspection
    # Work space needed per application, as a multiple of the content size: the staged copy, the
    # .intunewin built from it, and the encrypted payload extracted for upload.
    WorkSpaceFactor             = 2.5
    # --- Content / packaging -----------------------------------------------------------------
    WarnContentSizeGB           = 30         # log a warning above this; 0 = never warn
    MaxContentSizeGB            = 0          # HARD stop above this; 0 = no limit (the old 30 GB abort is gone)
    BlockSizeMB                 = 10         # Azure block size for the upload; 4..50 is sensible
    SasRenewMinutes             = 40         # renew the upload SAS before it expires (~1 h)
    # --- App defaults -------------------------------------------------------------------------
    MinWindowsRelease           = '1607'
    ApplicableArchitectures     = 'x64,x86'
    RunAsAccount                = 'system'
    RestartBehavior             = 'basedOnReturnCode'
    AllowAvailableUninstall     = $true
    DefaultMaxRuntimeMinutes    = 60
    MinMaxRuntimeMinutes        = 10
    # --- Where the helper modules live ------------------------------------------------------------
    # Searched recursively, then 'Lib\PowerShell Module', 'Lib', 'Modules', the tool root, and
    # finally the modules installed on the machine.
    ModulePath                  = 'Lib\PowerShell Module'
    # --- Deployment toolkit ---------------------------------------------------------------------
    # WHICH launcher marks a package, and what to run for it. A team on a different toolkit only
    # edits this list - the tool has no toolkit knowledge of its own. Checked in order; the
    # SHALLOWEST match in the content wins. StageUtilities copies UtilitiesPath into the package
    # copy (that is how PSADT v3 gets ServiceUI.exe so the UI shows in the user session).
    Launchers = @(
        @{ Marker='Invoke-AppDeployToolkit.exe'; Name='PSADT v4'; SetupFile='Invoke-AppDeployToolkit.exe'
           InstallCmd='Invoke-AppDeployToolkit.exe Install'; UninstallCmd='Invoke-AppDeployToolkit.exe Uninstall'; StageUtilities=$false }
        @{ Marker='Invoke-AppDeployToolkit.ps1'; Name='PSADT v4'; SetupFile='Invoke-AppDeployToolkit.exe'
           InstallCmd='Invoke-AppDeployToolkit.exe Install'; UninstallCmd='Invoke-AppDeployToolkit.exe Uninstall'; StageUtilities=$false }
        @{ Marker='Deploy-Application.exe'; Name='PSADT v3'; SetupFile='Deploy-Application.exe'
           InstallCmd='.\ServiceUI.exe -process:explorer.exe Deploy-Application.exe Install'
           UninstallCmd='.\ServiceUI.exe -process:explorer.exe Deploy-Application.exe Uninstall'; StageUtilities=$true }
        @{ Marker='Deploy-Application.ps1'; Name='PSADT v3'; SetupFile='Deploy-Application.exe'
           InstallCmd='.\ServiceUI.exe -process:explorer.exe Deploy-Application.exe Install'
           UninstallCmd='.\ServiceUI.exe -process:explorer.exe Deploy-Application.exe Uninstall'; StageUtilities=$true }
    )
    UtilitiesPath               = 'Lib\PSADTv3Utilities'   # copied in when a launcher sets StageUtilities
    # --- Package naming --------------------------------------------------------------------------
    # How a package name is split into its parts. Named groups Vendor / AppName / Arch / Version /
    # Revision / Lang are all optional - whatever the regex captures is used, and anything it does
    # not capture is simply reported as missing. Leave it empty to use the underscore-separated
    # <Vendor>_<AppName>_<Arch>_<Version>-<Revision>_<Lang> fallback.
    PackageNameRegex            = ''
    # --- Detection ------------------------------------------------------------------------------
    # The per-package registry key your packages brand themselves with; the migrator reads it from
    # the SCCM clause and can synthesise it when SCCM has no detection at all. Profile-specific.
    BrandingKeyRoot             = ''
    SynthesizeBrandingWhenMissing = $true    # was the whole point of the separate _NoDetection script
    # The value under the branding key that proves the package is installed. The rule is always
    # "this value EXISTS" - the value is never compared, so nothing here depends on the revision.
    BrandingValueName           = 'Revision'
    # --- Icon --------------------------------------------------------------------------------------
    DefaultIconPath             = 'Assets\DefaultAppIcon.png'
    NormalizeIconTo256          = $true      # scale/pad whatever we end up with to a square 256x256 PNG
    # --- Description --------------------------------------------------------------------------------
    DescriptionDocxMaxScanMB    = 25         # skip absurdly large .docx when scanning the content location
    # How far ABOVE the SCCM content location to look for the package's Icons folder and its
    # request form. The content location points at (or just below) the executable, while both of
    # those usually sit at the package root - one or two levels up. The climb also stops as soon
    # as a folder is named after the package, so the search never leaves the package.
    IconSearchUpLevels          = 2
    DocSearchUpLevels           = 2
    # Deep link to an app in the Intune portal; {AppId} is substituted.
    IntunePortalUrl             = 'https://intune.microsoft.com/#view/Microsoft_Intune_Apps/SettingsMenu/~/0/appId/{AppId}'
    # --- UAT group ---------------------------------------------------------------------------------
    # The tool NEVER creates a group and NEVER assigns anything. It works out the name each
    # application should get and puts it in the report - plus the object id when a group of that
    # name happens to exist already - so the group can be created and assigned afterwards, by hand.
    # Tokens: {Vendor} {AppName} {Arch} {Version} {Revision} {Lang} {FullName}. Every token is
    # stripped to letters+digits only (no spaces, no special characters) before it is inserted.
    # The concrete pattern is profile-specific - see settings.json.
    UatGroupNamePattern         = ''
    # The app's Notes field is written as JSON; reporting tools read 'lifecycle' out of it. A
    # migrated app is a UAT candidate, so that is the default stage.
    # What goes in the app's Notes field - just who created it, nothing else.
    NotesText                   = 'Created by SCCM2IntuneMigrator'
    # The second duplicate check: an app already in Intune with the SAME uninstall detection (key
    # path incl. 32/64-bit hive + version, or the same ProductCode) is the SAME underlying product
    # even when someone else named it differently. Catching that is what stops a silent duplicate.
    UninstallSignatureShield    = $true
    # --- Duplicate protection -------------------------------------------------------------------------
    SkipIfAlreadyInIntune       = $true       # an app with the same branding key already in Intune is SKIPPED, not duplicated
    # --- Rollback ---------------------------------------------------------------------------------------
    # FailedAppOnly | FailedAppAndStop | WholeBatch
    RollbackScope               = 'FailedAppOnly'
}

# settings.json layout:
#   { "ActiveProfile": "<name>",
#     "Common":   { ...settings shared by every profile... },
#     "Profiles": { "<name>": { "DisplayName": "...", "SiteCode": "...", ... }, ... } }
# Resolution order: built-in defaults  <-  Common  <-  the selected profile.
# A flat settings.json without Common/Profiles still works (it is treated as Common).
$script:SettingsFile = $null
$script:SettingsRaw  = $null

function Import-MigratorSettingsFile {
    param([string]$Path)
    if (-not $Path) { $Path = Join-Path $script:ToolRoot 'settings.json' }
    $script:SettingsFile = $Path
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warning "settings.json was not found at $Path - the site, tenant and naming values must be configured there."
        $script:SettingsRaw = $null
        return $null
    }
    try {
        # PS 5.1: assign the parsed object first; piping ConvertFrom-Json onward can re-wrap it.
        $raw  = Get-Content -LiteralPath $Path -Raw
        $json = $raw | ConvertFrom-Json
        $script:SettingsRaw = $json
        return $json
    } catch {
        Write-Warning "settings.json could not be read ($($_.Exception.Message)); the built-in defaults are used."
        $script:SettingsRaw = $null
        return $null
    }
}

function Get-MigratorProfileNames {
    if (-not $script:SettingsRaw) { return @() }
    $p = $script:SettingsRaw.Profiles
    if (-not $p) { return @() }
    return @($p.PSObject.Properties | ForEach-Object { $_.Name })
}

function Import-MigratorSettings {
    param([string]$Path, [string]$ProfileName)
    if (-not $script:SettingsRaw -or ($Path -and $Path -ne $script:SettingsFile)) { Import-MigratorSettingsFile -Path $Path | Out-Null }
    $cfg = @{}
    foreach ($k in $script:DefaultSettings.Keys) { $cfg[$k] = $script:DefaultSettings[$k] }

    $apply = {
        param($obj)
        if (-not $obj) { return }
        foreach ($p in $obj.PSObject.Properties) {
            if ($p.Name -in 'Profiles', 'ActiveProfile', 'Common') { continue }
            if ($null -ne $p.Value -and "$($p.Value)" -ne '') { $cfg[$p.Name] = $p.Value }
        }
    }

    $json = $script:SettingsRaw
    if ($json) {
        if ($json.Common) { & $apply $json.Common } else { & $apply $json }   # flat file = Common
        if (-not $ProfileName) { $ProfileName = "$($json.ActiveProfile)".Trim() }
        $profiles = $json.Profiles
        if ($profiles) {
            $chosen = $null
            if ($ProfileName -and $profiles.PSObject.Properties.Name -contains $ProfileName) { $chosen = $profiles.$ProfileName }
            if (-not $chosen) {
                $first = @($profiles.PSObject.Properties | Select-Object -First 1)
                if ($first.Count) { $ProfileName = $first[0].Name; $chosen = $first[0].Value }
            }
            & $apply $chosen
        }
    }
    $cfg['ToolRoot']    = $script:ToolRoot
    $cfg['ProfileName'] = "$ProfileName"
    return $cfg
}

function Test-MigratorSettings {
    # Names the values a profile MUST supply, rather than letting the run fail deep inside Graph.
    param([Parameter(Mandatory)][hashtable]$Cfg)
    $missing = @()
    foreach ($k in 'SiteCode', 'SiteServer', 'TenantId') { if (-not "$($Cfg[$k])".Trim()) { $missing += $k } }
    if (-not "$($Cfg.UatGroupNamePattern)".Trim()) { $missing += 'UatGroupNamePattern' }
    if ($Cfg.SynthesizeBrandingWhenMissing -and -not "$($Cfg.BrandingKeyRoot)".Trim()) { $missing += 'BrandingKeyRoot' }
    return $missing
}

##############################################################################################
# endregion
# region ENGINE - defined as a scriptblock so the SAME code can be dot-sourced into the UI
#                 runspace AND re-created inside the background worker runspace.
##############################################################################################
$Engine = {

# --------------------------------------------------------------------------------------------
# Small helpers
# --------------------------------------------------------------------------------------------
function Resolve-MigPath {
    # A tool-relative path ('Lib\x') resolved against the tool folder; absolute paths pass through.
    param([string]$Path)
    if (-not "$Path".Trim()) { return '' }
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    return (Join-Path $script:Cfg.ToolRoot $Path)
}

function Get-MigSafeName {
    # A file-system safe token for folder / file names. Square brackets go too: they are legal in
    # a file name but PowerShell reads them as a wildcard, so a path built from an application
    # called "Foo [x64]" would break New-Item / Copy-Item unless they are removed here.
    param([string]$Name)
    $s = [regex]::Replace("$Name", '[\\/:*?"<>|\[\]]', '_')
    $s = $s -replace '\s+', '_'
    if ($s.Length -gt 120) { $s = $s.Substring(0, 120) }
    return $s.Trim('_', ' ', '.')
}

function Use-FileSystemLocation {
    # ConfigMgr's CMSite PSDrive breaks FileSystem cmdlets that use -Filter/-File/-Recurse
    # ("the provider does not support filters"), so pin the location to a real filesystem path
    # before ANY file work. Always call this after talking to SCCM.
    try { Set-Location -LiteralPath $env:SystemRoot -ErrorAction Stop } catch {}
}

function Use-SccmLocation {
    param([string]$SiteCode)
    try { Set-Location -LiteralPath "$($SiteCode):\" -ErrorAction Stop } catch {}
}

# --------------------------------------------------------------------------------------------
# Logging. Writes to the batch log, the CURRENT application's log, and the GUI queue.
# --------------------------------------------------------------------------------------------
function Write-MigLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Info','Success','Warning','Error','Step')][string]$Level = 'Info'
    )
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $tag   = switch ($Level) { 'Success' {'OK   '} 'Warning' {'WARN '} 'Error' {'ERROR'} 'Step' {'STEP '} default {'INFO '} }
    $line  = "$stamp  $tag  $Message"
    foreach ($p in @($script:BatchLogPath, $script:AppLogPath)) {
        if ($p) { try { Add-Content -LiteralPath $p -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue } catch {} }
    }
    # $null -ne, NOT a plain truthiness test: an EMPTY collection is falsy in PowerShell, so
    # "if ($script:Sync.LogQueue)" is false while the queue is empty - which is exactly when the
    # first line arrives, and no line would ever reach the window.
    if (($null -ne $script:Sync) -and ($null -ne $script:Sync.LogQueue)) {
        try { [void]$script:Sync.LogQueue.Add([pscustomobject]@{ Text = $line; Level = $Level }) } catch {}
    }
    if ($null -eq $script:Sync) {
        $c = switch ($Level) { 'Success' {'Green'} 'Warning' {'Yellow'} 'Error' {'Red'} 'Step' {'Cyan'} default {'Gray'} }
        Write-Host $line -ForegroundColor $c
    }
}

function Set-MigStatus {
    param([string]$Status, [int]$Percent = -1, [switch]$Indeterminate)
    if (-not $script:Sync) { return }
    if ($Status) { $script:Sync.Status = $Status }
    if ($Indeterminate) { $script:Sync.Indeterminate = $true } elseif ($Percent -ge 0) { $script:Sync.Indeterminate = $false; $script:Sync.Percent = $Percent }
}

function Test-MigCancelled {
    if ($script:Sync -and $script:Sync.CancelRequested) { return $true }
    return $false
}

# --------------------------------------------------------------------------------------------
# Package-name parser. The format is CONFIGURABLE (Cfg.PackageNameRegex, named groups Vendor /
# AppName / Arch / Version / Revision / Lang) so a site or a brand with a different convention
# only edits settings.json. With no regex configured it falls back to the underscore split
# <Vendor>_<AppName>_<Arch>_<Version>-<Revision>_<Lang>.
# Either way this NEVER throws - a migration corpus always holds names that do not conform, and
# the old tool crashed on those by indexing the split array blindly ($CharArray[3].Split('-')[1]).
# --------------------------------------------------------------------------------------------
function ConvertFrom-MigPackageName {
    param([Parameter(Mandatory)][string]$FullName)
    $out = [ordered]@{
        FullName = "$FullName"
        Vendor   = ''; AppName = ''; Arch = ''
        Version  = ''; Revision = ''; Language = ''
        Conforms = $false
        ParsedBy = 'split'
        Warnings = @()
    }
    $rx = "$($script:Cfg.PackageNameRegex)".Trim()
    $matched = $false
    if ($rx) {
        try {
            $m = [regex]::Match("$FullName", $rx)
            if ($m.Success) {
                $matched = $true
                $out.ParsedBy = 'regex'
                foreach ($pair in @(@('Vendor','Vendor'), @('AppName','AppName'), @('Arch','Arch'),
                                    @('Version','Version'), @('Revision','Revision'), @('Lang','Language'))) {
                    $g = $m.Groups[$pair[0]]
                    if ($g -and $g.Success) { $out[$pair[1]] = "$($g.Value)".Trim() }
                }
            } else {
                $out.Warnings += "the name does not match PackageNameRegex - fell back to the underscore split"
            }
        } catch {
            $out.Warnings += "PackageNameRegex is not a valid regular expression ($($_.Exception.Message)) - fell back to the underscore split"
        }
    }
    if (-not $matched) {
        $parts = @("$FullName" -split '_')
        if ($parts.Count -ge 1) { $out.Vendor  = $parts[0] }
        if ($parts.Count -ge 2) { $out.AppName = $parts[1] }
        if ($parts.Count -ge 3) { $out.Arch    = $parts[2] }
        if ($parts.Count -ge 4) {
            $vr = @("$($parts[3])" -split '-')
            $out.Version = $vr[0]
            if ($vr.Count -ge 2) { $out.Revision = $vr[1] }
        }
        if ($parts.Count -ge 5) { $out.Language = $parts[4] }
    }
    $out.Conforms = [bool]($out.Vendor -and $out.AppName -and $out.Version -and $out.Revision)
    if (-not $out.Vendor)   { $out.Warnings += 'no publisher segment' }
    if (-not $out.AppName)  { $out.Warnings += 'no application-name segment' }
    if (-not $out.Version)  { $out.Warnings += 'no version segment' }
    if (-not $out.Revision) { $out.Warnings += 'no revision segment (the branding rule cannot compare Revision)' }
    return $out
}

# --------------------------------------------------------------------------------------------
# DESCRIPTION
#   1. whatever SCCM holds (SDMPackageXML DisplayInfo, then the WMI LocalizedDescription),
#   2. else the package's request form (.docx) in the SOURCE CONTENT location - BOTH the
#      "Short description of the product in English" and the "Detailed description of the
#      product in English" cells are read; both are used when both are filled,
#   3. else a generated sentence, so an app is never created with an empty description.
# --------------------------------------------------------------------------------------------
function Test-MigPlaceholderText {
    param([string]$Text)
    $t = "$Text".Trim()
    if (-not $t) { return $true }
    if ($t.Length -le 3) { return $true }
    # English AND German placeholders - the forms come back in both languages, and a Word content
    # control that was never filled in still carries its prompt text.
    if ($t -match '(?i)^\s*(click here to enter text|choose an item|enter text|n\.?a\.?|none|tbd|xxx+)\s*\.?\s*$') { return $true }
    if ($t -match '(?i)^\s*(klick(en Sie)? hier[, ]*um Text einzugeben|hier klicken um Text einzugeben|text eingeben|element ausw(ae|ä|.)hlen|entf(ae|ä|.)llt|keine?)\s*\.?\s*$') { return $true }
    return $false
}

function Get-MigDocxText {
    param([Parameter(Mandatory)][string]$DocxPath)
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $zip = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($DocxPath)
        # Word writes 'word/document.xml'; some producers store the entry with a BACKSLASH
        # separator instead - match either, or the description lookup silently finds nothing.
        $entry = $zip.Entries | Where-Object { ($_.FullName -replace '\\', '/') -eq 'word/document.xml' } | Select-Object -First 1
        if (-not $entry) { return '' }
        $sr = New-Object System.IO.StreamReader($entry.Open())
        $xml = $sr.ReadToEnd(); $sr.Close()
    } catch { return '' } finally { if ($zip) { try { $zip.Dispose() } catch {} } }
    # Flatten: a table cell boundary and a paragraph both become a space; then decode entities.
    $t = $xml -replace '</w:p>', ' ' -replace '</w:tc>', ' > ' -replace '<[^>]+>', ''
    $t = [System.Net.WebUtility]::HtmlDecode($t) -replace '\s+', ' '
    return $t
}

# The SCCM content location usually points at (or just below) the folder holding the executable,
# while the package's Icons folder and its request form sit a level or two ABOVE it, at the
# package root. So we search the content folder and up to MaxUp parents - and stop the moment a
# folder's name matches the package name, because that IS the package root and nothing outside it
# belongs to this package. Without that stop, a search would wander into the whole library.
function Get-MigSearchRoots {
    param([Parameter(Mandatory)][string]$ContentPath, [int]$MaxUp = 2, [string]$PackageName)
    $roots = New-Object System.Collections.Generic.List[string]
    # With no package name there is no way to tell where this package ends and the next one
    # begins, so do NOT climb - a neighbouring package's icon or request form must never be
    # picked up as if it belonged to this one.
    if (-not "$PackageName".Trim()) { $MaxUp = 0 }
    $cur = $ContentPath
    for ($i = 0; $i -le $MaxUp; $i++) {
        if (-not $cur -or -not (Test-Path -LiteralPath $cur)) { break }
        if (-not $roots.Contains($cur)) { [void]$roots.Add($cur) }
        $leaf = Split-Path -Leaf $cur
        if ($PackageName -and ($leaf -ieq $PackageName)) { break }   # the package root - go no higher
        $parent = Split-Path -Parent $cur
        if (-not $parent -or $parent -eq $cur) { break }
        # never climb to a drive root or a bare share root
        if ($parent -match '^[A-Za-z]:\\?$' -or $parent -match '^\\\\[^\\]+\\[^\\]+\\?$') { break }
        $cur = $parent
    }
    return $roots.ToArray()
}

function Get-MigDescriptionFromContent {
    # Returns @{ Short; Detailed; Source }. Looks for the request form in the content folder and
    # its nearest parents; the file name varies, so we match on the LABEL text inside it.
    param([Parameter(Mandatory)][string]$ContentPath, [string]$PackageName)
    $res = @{ Short = ''; Detailed = ''; Source = '' }
    if (-not $ContentPath -or -not (Test-Path -LiteralPath $ContentPath)) { return $res }
    Use-FileSystemLocation
    $maxBytes = [int64]$script:Cfg.DescriptionDocxMaxScanMB * 1MB
    $docs = New-Object System.Collections.Generic.List[object]
    foreach ($root in (Get-MigSearchRoots -ContentPath $ContentPath -MaxUp ([int]$script:Cfg.DocSearchUpLevels) -PackageName $PackageName)) {
        try {
            foreach ($d in @(Get-ChildItem -LiteralPath $root -Filter *.docx -File -Depth 1 -Recurse -ErrorAction SilentlyContinue |
                             Where-Object { $_.Name -notmatch '^~\$' -and $_.Length -lt $maxBytes })) {
                if (-not ($docs | Where-Object { $_.FullName -eq $d.FullName })) { [void]$docs.Add($d) }
            }
        } catch {}
    }
    if ($docs.Count -eq 0) { return $res }
    # Most likely candidates first (the request form / installation instructions).
    $ordered = @($docs | Sort-Object @{ Expression = { if ($_.Name -match '(?i)instruction|description|request|anforder|install') { 0 } else { 1 } } }, Name)
    # Take whatever is actually filled in - English OR German, short OR detailed. The forms are not
    # consistent across teams, so each kind has several spellings and the first that yields real
    # text wins. Anything found beats nothing found.
    $labels = [ordered]@{
        Short    = @('Short description of the product in English',
                     'Short description of the product',
                     'Short description',
                     'Kurzbeschreibung des Produkts',
                     'Kurzbeschreibung')
        Detailed = @('Detailed description of the product in English',
                     'Detailed description of the product',
                     'Detailed description',
                     'Ausf(?:ue|ü|u|.)hrliche Beschreibung des Produkts',
                     'Ausf(?:ue|ü|u|.)hrliche Beschreibung',
                     'Detaillierte Beschreibung')
    }
    # A value ends where the NEXT LABEL starts, so a short cell cannot swallow the rest of the
    # table. Only real label texts belong here - a generic word like "Installation" would cut a
    # description short the moment the description happened to use it.
    $stop = '(?:Detailed description of the product|Short description of the product|Detailed description|Short description|Dependencies|Kurzbeschreibung|Ausf(?:ue|ü|u|.)hrliche Beschreibung|Detaillierte Beschreibung|Voraussetzungen|Abh(?:ae|ä|.)ngigkeiten)'
    foreach ($d in $ordered) {
        $t = Get-MigDocxText -DocxPath $d.FullName
        if (-not $t) { continue }
        $got = $false
        foreach ($key in @('Short','Detailed')) {
            if ($res[$key]) { continue }
            foreach ($label in $labels[$key]) {
                # The separator after the label is MANDATORY (a cell break '>' or a colon). The
                # short spellings are prefixes of the long ones - "Short description" sits inside
                # "Short description of the product in English" - so without insisting on a
                # separator the short label would match mid-label and capture
                # "of the product in English > <the real value>" as if that were the description.
                $m = [regex]::Match($t, $label + '\s*(?::|>)\s*(?<v>.+?)\s*>?\s*' + $stop, 'IgnoreCase')
                if (-not $m.Success) {
                    # last cell in the table - no following label to stop at
                    $m = [regex]::Match($t, $label + '\s*(?::|>)\s*(?<v>.{4,600})', 'IgnoreCase')
                }
                if ($m.Success) {
                    $val = ($m.Groups['v'].Value.Trim() -replace '\s*>\s*$', '').Trim()
                    if (-not (Test-MigPlaceholderText $val)) {
                        $res[$key] = $val; $got = $true
                        $res["$($key)Label"] = ($label -replace '\\', '')
                        break
                    }
                }
            }
        }
        if ($got) { $res.Source = $d.FullName }
        if ($res.Short -and $res.Detailed) { break }
    }
    return $res
}

function Resolve-MigDescription {
    # Decides the final Intune description text and records WHERE it came from.
    param(
        [string]$SccmDescription,
        [string]$SccmLocalizedDescription,
        [string]$ContentPath,
        [hashtable]$Name
    )
    foreach ($cand in @($SccmDescription, $SccmLocalizedDescription)) {
        if (-not (Test-MigPlaceholderText $cand)) {
            Write-MigLog "Description taken from SCCM ($($cand.Length) chars)."
            return @{ Text = "$cand".Trim(); Source = 'SCCM' }
        }
    }
    Write-MigLog "SCCM holds no usable description - scanning the content location for the request form (.docx)..." Warning
    $doc = Get-MigDescriptionFromContent -ContentPath $ContentPath -PackageName $Name.FullName
    if ($doc.Short -or $doc.Detailed) {
        $text = if ($doc.Short -and $doc.Detailed -and ($doc.Short -ne $doc.Detailed)) {
            "$($doc.Short)`r`n`r`n$($doc.Detailed)"
        } elseif ($doc.Detailed) { $doc.Detailed } else { $doc.Short }
        $which = @(); if ($doc.Short) { $which += 'short' }; if ($doc.Detailed) { $which += 'detailed' }
        Write-MigLog "Description taken from '$(Split-Path -Leaf $doc.Source)' ($($which -join ' + ') description)." Success
        return @{ Text = $text; Source = "Document: $(Split-Path -Leaf $doc.Source) ($($which -join '+'))" }
    }
    $bits = @($Name.Vendor, $Name.AppName) | Where-Object { $_ }
    $label = if ($bits.Count) { $bits -join ' ' } else { $Name.FullName }
    $ver = if ($Name.Version) { " $($Name.Version)" } else { '' }
    Write-MigLog "No description in SCCM and none in the content documents - a generated description is used." Warning
    return @{ Text = "$label$ver. Migrated from SCCM to Intune by the SCCM2Intune migrator."; Source = 'Generated' }
}

# --------------------------------------------------------------------------------------------
# ICON
#   1. the icon stored in SCCM's SDMPackageXML - decoded and VALIDATED as a real image; if it is
#      not already a PNG (SCCM commonly stores .ico) it is converted,
#   2. else an icon found in the SOURCE CONTENT location (Icons\*.png preferred, then *.ico,
#      then anywhere in the tree), converted to PNG,
#   3. else Assets\DefaultAppIcon.png - the configured default icon (replace that ONE file to
#      rebrand the tool; no code change).
# Returns @{ Base64; Source; Detail } - Base64 is '' only if even the default is missing.
# --------------------------------------------------------------------------------------------
function ConvertTo-MigPngBytes {
    # Any image bytes (.ico with classic OR png-compressed frames, .png, .bmp, .jpg) -> PNG bytes.
    # WPF's BitmapDecoder is used first because Icon.ToBitmap() chokes on png-compressed .ico
    # frames; System.Drawing is the fallback. Optionally normalised to a square 256x256 canvas.
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $target = 256
    $normalize = [bool]$script:Cfg.NormalizeIconTo256
    try {
        Add-Type -AssemblyName PresentationCore, WindowsBase -ErrorAction Stop
        $ms = New-Object System.IO.MemoryStream(,$Bytes)
        try {
            $dec   = [System.Windows.Media.Imaging.BitmapDecoder]::Create($ms, 'None', 'OnLoad')
            $frame = $dec.Frames | Sort-Object PixelWidth -Descending | Select-Object -First 1
            if (-not $frame) { throw 'no frames' }
            $src = [System.Windows.Media.Imaging.BitmapSource]$frame
            if ($normalize) { $src = Resize-MigBitmapSquare -Source $src -Size $target }
            $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
            $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($src))
            $out = New-Object System.IO.MemoryStream
            $enc.Save($out); $bytesOut = $out.ToArray(); $out.Dispose()
            return @{ Bytes = $bytesOut; Width = [int]$src.PixelWidth; Height = [int]$src.PixelHeight }
        } finally { $ms.Dispose() }
    } catch {
        try {
            Add-Type -AssemblyName System.Drawing -ErrorAction Stop
            $ms = New-Object System.IO.MemoryStream(,$Bytes)
            $img = [System.Drawing.Image]::FromStream($ms)
            $out = New-Object System.IO.MemoryStream
            $img.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
            $bytesOut = $out.ToArray()
            $w = $img.Width; $h = $img.Height
            $out.Dispose(); $img.Dispose(); $ms.Dispose()
            return @{ Bytes = $bytesOut; Width = $w; Height = $h }
        } catch { return $null }
    }
}

function Resize-MigBitmapSquare {
    # Scale to fit a square canvas keeping the aspect ratio, padding transparent. A 2430x1368
    # banner therefore stays the same picture instead of being stretched.
    param([Parameter(Mandatory)]$Source, [int]$Size = 256)
    try {
        if ($Source.PixelWidth -eq $Size -and $Source.PixelHeight -eq $Size) { return $Source }
        $scale = [Math]::Min($Size / [double]$Source.PixelWidth, $Size / [double]$Source.PixelHeight)
        $w = [Math]::Max(1, [int][Math]::Round($Source.PixelWidth  * $scale))
        $h = [Math]::Max(1, [int][Math]::Round($Source.PixelHeight * $scale))
        $x = [int](($Size - $w) / 2); $y = [int](($Size - $h) / 2)
        $dv = New-Object System.Windows.Media.DrawingVisual
        $dc = $dv.RenderOpen()
        $dc.DrawImage($Source, (New-Object System.Windows.Rect($x, $y, $w, $h)))
        $dc.Close()
        $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($Size, $Size, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
        $rtb.Render($dv)
        $rtb.Freeze()
        return $rtb
    } catch { return $Source }
}

function Test-MigImageBytes {
    # Cheap magic-number sanity check before we even try to decode.
    param([byte[]]$Bytes)
    if (-not $Bytes -or $Bytes.Length -lt 8) { return $false }
    $b = $Bytes
    if ($b[0] -eq 0x89 -and $b[1] -eq 0x50 -and $b[2] -eq 0x4E -and $b[3] -eq 0x47) { return $true }   # PNG
    if ($b[0] -eq 0x00 -and $b[1] -eq 0x00 -and ($b[2] -eq 0x01 -or $b[2] -eq 0x02)) { return $true }  # ICO / CUR
    if ($b[0] -eq 0x42 -and $b[1] -eq 0x4D) { return $true }                                            # BMP
    if ($b[0] -eq 0xFF -and $b[1] -eq 0xD8) { return $true }                                            # JPEG
    if ($b[0] -eq 0x47 -and $b[1] -eq 0x49 -and $b[2] -eq 0x46) { return $true }                        # GIF
    return $false
}

function Get-MigIconFromContent {
    # Look for the product icon around the content location: the content folder itself and up to
    # a couple of parents (an Icons folder normally sits at the PACKAGE root, above the folder the
    # executable is in), stopping at the package folder so the search never wanders into the wider
    # library. Toolkit artwork (AppDeployToolkitLogo / Banner) is skipped - that is the toolkit's
    # picture, not the product's.
    param([Parameter(Mandatory)][string]$ContentPath, [string]$PackageName)
    if (-not $ContentPath -or -not (Test-Path -LiteralPath $ContentPath)) { return $null }
    Use-FileSystemLocation
    $skip = '(?i)AppDeployToolkit(Logo|Banner)|Banner\.png$|_Banner|Splash'
    $all = New-Object System.Collections.Generic.List[object]
    foreach ($root in (Get-MigSearchRoots -ContentPath $ContentPath -MaxUp ([int]$script:Cfg.IconSearchUpLevels) -PackageName $PackageName)) {
        try {
            # the root itself (top level) plus one level of subfolders - that reaches <root>\Icons
            foreach ($f in @(Get-ChildItem -LiteralPath $root -File -Depth 1 -Recurse -ErrorAction SilentlyContinue |
                             Where-Object { $_.Extension -match '(?i)^\.(ico|png)$' -and $_.FullName -notmatch $skip -and $_.Length -gt 100 })) {
                if (-not ($all | Where-Object { $_.FullName -eq $f.FullName })) { [void]$all.Add($f) }
            }
        } catch {}
    }
    if ($all.Count -eq 0) { return $null }
    # Ranking: inside an "Icons" folder wins; a .png that has a same-named .ico sibling wins (that
    # pair is the packaged product icon); then .ico; then anything left, biggest first.
    $ranked = @($all | Sort-Object `
        @{ Expression = { if ($_.DirectoryName -match '(?i)\\Icons?$') { 0 } else { 1 } } },
        @{ Expression = { if ($_.Extension -match '(?i)png' -and (Test-Path -LiteralPath (Join-Path $_.DirectoryName ($_.BaseName + '.ico')))) { 0 } else { 1 } } },
        @{ Expression = { if ($_.Extension -match '(?i)ico') { 0 } else { 1 } } },
        @{ Expression = { $_.Length }; Descending = $true })
    foreach ($f in ($ranked | Select-Object -First 8)) {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
            if (-not (Test-MigImageBytes $bytes)) { continue }
            $png = ConvertTo-MigPngBytes -Bytes $bytes
            if ($png) { return @{ Bytes = $png.Bytes; File = $f.FullName; Width = $png.Width; Height = $png.Height } }
        } catch { continue }
    }
    return $null
}

function Resolve-MigIcon {
    param([string]$SccmIconBase64, [string]$ContentPath, [string]$PackageName)
    # --- 1. the SCCM icon -----------------------------------------------------------------
    if ("$SccmIconBase64".Trim()) {
        $raw = $null
        try { $raw = [Convert]::FromBase64String(("$SccmIconBase64" -replace '\s', '')) } catch { $raw = $null }
        if ($raw -and (Test-MigImageBytes $raw)) {
            $png = ConvertTo-MigPngBytes -Bytes $raw
            if ($png) {
                $wasPng = ($raw[0] -eq 0x89 -and $raw[1] -eq 0x50)
                $how = if ($wasPng) { 'already PNG' } else { 'converted to PNG' }
                Write-MigLog "Icon: using the icon stored in SCCM ($how, $($png.Width)x$($png.Height))." Success
                return @{ Base64 = [Convert]::ToBase64String($png.Bytes); Source = 'SCCM'; Detail = "$how, $($png.Width)x$($png.Height)" }
            }
            Write-MigLog "Icon: the SCCM icon decoded but could not be converted to PNG - looking in the content location instead." Warning
        } else {
            Write-MigLog "Icon: the icon stored in SCCM is not a usable image - looking in the content location instead." Warning
        }
    } else {
        Write-MigLog "Icon: SCCM holds no icon - looking in the content location..." Warning
    }
    # --- 2. an icon in the source content -------------------------------------------------
    $found = Get-MigIconFromContent -ContentPath $ContentPath -PackageName $PackageName
    if ($found) {
        Write-MigLog "Icon: using '$(Split-Path -Leaf $found.File)' from the content location (converted to PNG, $($found.Width)x$($found.Height))." Success
        return @{ Base64 = [Convert]::ToBase64String($found.Bytes); Source = 'Content'; Detail = "$(Split-Path -Leaf $found.File) -> PNG $($found.Width)x$($found.Height)" }
    }
    # --- 3. the configured default icon -----------------------------------------------------
    $def = Resolve-MigPath $script:Cfg.DefaultIconPath
    if ($def -and (Test-Path -LiteralPath $def)) {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($def)
            $png = ConvertTo-MigPngBytes -Bytes $bytes
            if ($png) {
                Write-MigLog "Icon: no icon in SCCM and none in the content - the default icon is used." Warning
                return @{ Base64 = [Convert]::ToBase64String($png.Bytes); Source = 'Default'; Detail = "default icon ($($png.Width)x$($png.Height))" }
            }
            Write-MigLog "Icon: the default icon is used (as-is)." Warning
            return @{ Base64 = [Convert]::ToBase64String($bytes); Source = 'Default'; Detail = 'default icon (raw)' }
        } catch { }
    }
    Write-MigLog "Icon: no icon at all could be resolved and $($script:Cfg.DefaultIconPath) is missing - the app is created WITHOUT an icon." Warning
    return @{ Base64 = ''; Source = 'None'; Detail = 'no icon' }
}

# --------------------------------------------------------------------------------------------
# SCCM connection + application list
# --------------------------------------------------------------------------------------------
function Connect-MigSccm {
    param([string]$SiteCode, [string]$SiteServer)
    Use-FileSystemLocation
    if (-not (Get-Module ConfigurationManager)) {
        # The console INSTALLED ON THIS MACHINE wins: its version matches the site it administers,
        # which the bundled copy cannot guarantee - that copy came from whichever console it was
        # taken from, and a module out of step with the site can fail or behave oddly. The bundled
        # copy is the fallback, for a machine with no console installed at all.
        $mod = $null; $tried = @()
        if ("$env:SMS_ADMIN_UI_PATH".Trim()) {
            $installed = Join-Path (Split-Path -Parent "$env:SMS_ADMIN_UI_PATH") 'ConfigurationManager.psd1'
            $tried += $installed
            if (Test-Path -LiteralPath $installed) { $mod = $installed; Write-MigLog 'Using the ConfigurationManager module from the console installed on this machine.' }
        }
        if (-not $mod) {
            $bundled = Resolve-MigPath 'Lib\ConfigurationManager\ConfigurationManager.psd1'
            $tried += $bundled
            if (Test-Path -LiteralPath $bundled) { $mod = $bundled; Write-MigLog 'No ConfigMgr console on this machine - using the copy bundled with the tool.' }
        }
        if (-not $mod) { throw "The ConfigurationManager module was not found. Looked for:`r`n  $($tried -join "`r`n  ")`r`nInstall the ConfigMgr console, or put the module under the tool's Lib\ConfigurationManager\." }
        Write-MigLog "Importing the ConfigurationManager module from $mod..."
        # It is a SCRIPT module: on a machine whose (often 32-bit) execution policy is Restricted
        # the import dies with "running scripts is disabled". Lift it for THIS PROCESS only.
        try { Set-ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue } catch {}
        Import-Module $mod -ErrorAction Stop
    }
    if (-not (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) {
        Write-MigLog "Mapping the SCCM site drive $($SiteCode): -> $SiteServer..."
        New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $SiteServer -Scope Script -ErrorAction Stop | Out-Null
    }
    Use-SccmLocation -SiteCode $SiteCode
    Write-MigLog "Connected to SCCM site $SiteCode on $SiteServer." Success
    Use-FileSystemLocation
    return $true
}

function Get-MigSccmApplicationList {
    param([string]$SiteCode)
    Use-SccmLocation -SiteCode $SiteCode
    $apps = @(Get-CMApplication -Fast -ErrorAction Stop |
              Select-Object LocalizedDisplayName, DateCreated, DateLastModified, SoftwareVersion, Manufacturer, IsDeployed, NumberOfDeploymentTypes |
              Sort-Object LocalizedDisplayName)
    Use-FileSystemLocation
    return $apps
}

# --------------------------------------------------------------------------------------------
# DETECTION - map every SCCM detection clause we understand onto its Graph equivalent.
# The old scripts handled registry + MSI only; file/folder and script clauses are mapped too so
# fewer applications need a hand-built rule afterwards.
# --------------------------------------------------------------------------------------------
function ConvertTo-MigGraphOperator {
    param([string]$SccmOperator)
    switch -Regex ("$SccmOperator") {
        '(?i)^(IsEquals|Equals|Equal)$'                    { return 'equal' }
        '(?i)^(NotEquals|IsNotEquals|NotEqual)$'           { return 'notEqual' }
        '(?i)^(GreaterEquals|GreaterThanOrEqual)$'         { return 'greaterThanOrEqual' }
        '(?i)^(LessEquals|LessThanOrEqual)$'               { return 'lessThanOrEqual' }
        '(?i)^(GreaterThan|Greater)$'                      { return 'greaterThan' }
        '(?i)^(LessThan|Less)$'                            { return 'lessThan' }
        default                                            { return 'equal' }
    }
}

function ConvertTo-MigDetectionType {
    param([string]$SccmDataType)
    switch -Regex ("$SccmDataType") {
        '(?i)version'          { return 'version' }
        '(?i)int|double|float' { return 'integer' }
        default                { return 'string' }
    }
}

function Get-MigDetectionRules {
    # Returns @{ Rules = @(...); Summary = 'text'; Synthesised = $bool }
    param(
        [Parameter(Mandatory)][string]$SiteCode,
        [Parameter(Mandatory)][string]$ApplicationName,
        [Parameter(Mandatory)][hashtable]$Name
    )
    $rules   = New-Object System.Collections.Generic.List[object]
    $summary = New-Object System.Collections.Generic.List[string]
    $clauses = @()
    Use-SccmLocation -SiteCode $SiteCode
    try {
        $dts = @(Get-CMDeploymentType -ApplicationName $ApplicationName -ErrorAction Stop)
        foreach ($dt in $dts) {
            $c = @(Get-CMDeploymentTypeDetectionClause -InputObject $dt -ErrorAction SilentlyContinue)
            if ($c) { $clauses += $c }
        }
    } catch {
        Write-MigLog "Could not read the deployment type's detection clauses: $($_.Exception.Message)" Warning
    }
    Use-FileSystemLocation

    # A clause counts as THE branding clause when the configured key root appears anywhere in its
    # key path - that is what separates the packages' own per-package key from a vendor uninstall
    # key. With no key root configured, nothing is treated as branding.
    $brandingRoot = "$($script:Cfg.BrandingKeyRoot)"
    $brandingRx   = if ($brandingRoot) { '(?i)' + [regex]::Escape($brandingRoot) } else { '(?!x)x' }

    foreach ($clause in $clauses) {
        $settingType = ''
        try { $settingType = "$($clause.Setting.GetType().Name)" } catch {}
        $sourceType  = "$($clause.Setting.SourceType)"

        # ---- MSI product code -------------------------------------------------------------
        if ($settingType -eq 'MSISettingInstance' -or $sourceType -match '(?i)^MSI$') {
            $pc = "$($clause.Setting.ProductCode)".Trim()
            if ($pc) {
                $rules.Add(@{ '@odata.type' = '#microsoft.graph.win32LobAppProductCodeDetection'; productCode = $pc })
                $summary.Add("MSI product code $pc")
                Write-MigLog "Detection: MSI product code $pc"
            }
            continue
        }

        # ---- registry ----------------------------------------------------------------------
        if ($sourceType -match '(?i)^Registry') {
            $keyPath = "$($clause.Setting.Location)".Trim()
            if (-not $keyPath) { continue }
            $valueName = "$($clause.Setting.ValueName)".Trim()
            # SCCM's Is64Bit means "this key is 64-bit"; Intune's check32BitOn64System is the inverse.
            $check32 = $false
            try { $check32 = -not [bool]$clause.Setting.Is64Bit } catch {}
            $isBranding = ($keyPath -match $brandingRx)
            $rule = @{
                '@odata.type'        = '#microsoft.graph.win32LobAppRegistryDetection'
                keyPath              = (Add-MigHkeyPrefix $keyPath)
                valueName            = $valueName
                check32BitOn64System = $check32
            }
            if (-not $valueName) {
                # key-exists clause
                $rule['detectionType'] = 'exists'
                $rule['operator']      = 'notConfigured'
                $rule['detectionValue'] = $null
                $summary.Add("registry key exists: $($rule.keyPath)")
            } elseif ($isBranding) {
                # THE BRANDING KEY IS ALWAYS "value exists" - never a value comparison, whatever
                # SCCM happened to hold. The key is written per package, so its mere presence
                # proves this exact package is installed; comparing the Revision on top only adds
                # a way for detection to go wrong (a re-branded or hand-edited value would then
                # read as "not installed").
                $rule['detectionType']  = 'exists'
                $rule['operator']       = 'notConfigured'
                $rule['detectionValue'] = $null
                $summary.Add("branding: $($rule.keyPath) [$valueName] exists")
            } else {
                $expected = "$($clause.Constant.Value)".Trim()
                $rule['detectionType']  = (ConvertTo-MigDetectionType "$($clause.DataType.TypeName)")
                $rule['operator']       = (ConvertTo-MigGraphOperator "$($clause.Operator)")
                $rule['detectionValue'] = $expected
                $summary.Add("registry: $($rule.keyPath) [$valueName] $($rule.operator) '$expected'")
            }
            $rules.Add($rule)
            Write-MigLog "Detection: $($summary[$summary.Count-1])$(if($check32){' (32-bit hive)'})"
            continue
        }

        # ---- file / folder -------------------------------------------------------------------
        if ($sourceType -match '(?i)^(File|Folder)') {
            $path = "$($clause.Setting.Path)".Trim()
            $fof  = "$($clause.Setting.FileOrFolderName)".Trim()
            if (-not $path) { continue }
            $check32 = $false
            try { $check32 = -not [bool]$clause.Setting.Is64Bit } catch {}
            $rule = @{
                '@odata.type'        = '#microsoft.graph.win32LobAppFileSystemDetection'
                path                 = $path
                fileOrFolderName     = $fof
                check32BitOn64System = $check32
            }
            $expected = "$($clause.Constant.Value)".Trim()
            if ($expected -and "$($clause.DataType.TypeName)" -match '(?i)version') {
                $rule['detectionType']  = 'version'
                $rule['operator']       = (ConvertTo-MigGraphOperator "$($clause.Operator)")
                $rule['detectionValue'] = $expected
                $summary.Add("file version: $path\$fof $($rule.operator) $expected")
            } else {
                $rule['detectionType']  = if ($sourceType -match '(?i)Folder') { 'exists' } else { 'exists' }
                $rule['operator']       = 'notConfigured'
                $rule['detectionValue'] = $null
                $summary.Add("file/folder exists: $path\$fof")
            }
            $rules.Add($rule)
            Write-MigLog "Detection: $($summary[$summary.Count-1])"
            continue
        }

        # ---- custom script ---------------------------------------------------------------------
        if ($sourceType -match '(?i)^Script') {
            $body = "$($clause.Setting.ScriptText)"
            if (-not $body) { try { $body = "$($clause.Setting.Script)" } catch {} }
            if ($body) {
                $rules.Add(@{
                    '@odata.type'          = '#microsoft.graph.win32LobAppPowerShellScriptDetection'
                    scriptContent          = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($body))
                    enforceSignatureCheck  = $false
                    runAs32Bit             = $false
                })
                $summary.Add('custom PowerShell detection script (carried over from SCCM)')
                Write-MigLog "Detection: custom script clause carried over ($($body.Length) chars)." Warning
            }
            continue
        }

        Write-MigLog "Detection: an SCCM clause of type '$sourceType' cannot be expressed in Intune and was skipped." Warning
    }

    $synth = $false
    if ($rules.Count -eq 0) {
        # This is what MAN_SCCM2IntuneMgrationTool_Icon_NoDetection.ps1 did as a separate file.
        if ($script:Cfg.SynthesizeBrandingWhenMissing -and $Name.FullName) {
            # Same rule as above: the branding value EXISTING is the detection. The key path is
            # per package, so nothing needs comparing.
            $key = "HKEY_LOCAL_MACHINE\$($script:Cfg.BrandingKeyRoot)\$($Name.FullName)"
            $rules.Add(@{
                '@odata.type'        = '#microsoft.graph.win32LobAppRegistryDetection'
                keyPath              = $key
                valueName            = "$($script:Cfg.BrandingValueName)"
                detectionType        = 'exists'
                operator             = 'notConfigured'
                detectionValue       = $null
                check32BitOn64System = $false
            })
            $summary.Add("SYNTHESISED branding: $key [$($script:Cfg.BrandingValueName)] exists")
            $synth = $true
            Write-MigLog "Detection: SCCM has no detection clause - the branding key $key [$($script:Cfg.BrandingValueName)] exists was synthesised." Warning
        } else {
            Write-MigLog "Detection: SCCM has no detection clause and no branding key could be built for this package." Error
        }
    }
    # Return a plain array. A SINGLE rule must still serialise as a JSON ARRAY - a bare object makes
    # Graph reject the create with "detectionRules ... does not match the schema".
    return @{ Rules = $rules.ToArray(); Summary = ($summary -join ' | '); Synthesised = $synth }
}

function Add-MigHkeyPrefix {
    # SCCM stores 'SOFTWARE\...' without a hive; Graph wants a full HKEY_ path. An already-qualified
    # path (HKEY_..., HKLM:\, HKLM\) is normalised rather than double-prefixed.
    param([string]$KeyPath)
    $k = "$KeyPath".Trim()
    if (-not $k) { return $k }
    if ($k -match '^(?i)HKEY_') { return $k }
    if ($k -match '^(?i)HKLM:?\\')  { return ($k -replace '^(?i)HKLM:?\\',  'HKEY_LOCAL_MACHINE\') }
    if ($k -match '^(?i)HKCU:?\\')  { return ($k -replace '^(?i)HKCU:?\\',  'HKEY_CURRENT_USER\') }
    if ($k -match '^(?i)HKCR:?\\')  { return ($k -replace '^(?i)HKCR:?\\',  'HKEY_CLASSES_ROOT\') }
    return "HKEY_LOCAL_MACHINE\$($k.TrimStart('\'))"
}

# --------------------------------------------------------------------------------------------
# Exit codes from the SCCM deployment type -> Graph returnCodes.
# --------------------------------------------------------------------------------------------
function Get-MigReturnCodes {
    param($Digest)
    $map = @{
        '0'    = 'success'; '1707' = 'success'
        '3010' = 'softReboot'; '1641' = 'hardReboot'
        '1618' = 'retry'; '60012' = 'retry'
    }
    $out = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    try {
        foreach ($dt in @($Digest.DeploymentType)) {
            foreach ($ec in @($dt.Installer.CustomData.ExitCodes.ExitCode)) {
                $code = "$($ec.Code)".Trim()
                if (-not $code -or $seen.ContainsKey($code)) { continue }
                $type = switch -Regex ("$($ec.Class)") {
                    '(?i)success'    { 'success' }
                    '(?i)hardreboot' { 'hardReboot' }
                    '(?i)softreboot' { 'softReboot' }
                    '(?i)fastretry'  { 'retry' }
                    default          { 'failed' }
                }
                $seen[$code] = $true
                [void]$out.Add(@{ returnCode = [int]$code; type = $type })
            }
        }
    } catch {}
    foreach ($k in $map.Keys) {
        if (-not $seen.ContainsKey($k)) { [void]$out.Add(@{ returnCode = [int]$k; type = $map[$k] }); $seen[$k] = $true }
    }
    return $out.ToArray()
}

# --------------------------------------------------------------------------------------------
# Read EVERYTHING we need for one application out of SCCM.
# --------------------------------------------------------------------------------------------
function Get-MigSccmApplication {
    param([Parameter(Mandatory)][string]$SiteCode, [Parameter(Mandatory)][string]$DisplayName)
    Use-SccmLocation -SiteCode $SiteCode
    $app = Get-CMApplication -Name $DisplayName -ErrorAction Stop
    if (-not $app) { throw "Application '$DisplayName' was not found in SCCM site $SiteCode." }
    $sdm = "$($app.SDMPackageXML)"
    $localizedName = "$($app.LocalizedDisplayName)"
    $localizedDesc = "$($app.LocalizedDescription)"
    Use-FileSystemLocation

    $digest = $null
    try { $digest = ([xml]$sdm).AppMgmtDigest } catch { throw "The SDMPackageXML of '$DisplayName' could not be parsed: $($_.Exception.Message)" }

    $info = $null
    try { $info = $digest.Application.DisplayInfo.Info } catch {}
    if (-not $info) { try { $info = $digest.Application.DisplayInfo.FirstChild } catch {} }

    # Content location, run time, and SCCM's OWN install/uninstall command lines. Those command
    # lines matter for a package that is not built on a deployment toolkit: they are the only
    # record of how the thing is actually installed, and we reuse them verbatim (wrapped).
    $contentPath = ''
    $execContext = ''
    $runTime     = 0
    $installCmd  = ''
    $uninstCmd   = ''
    foreach ($dt in @($digest.DeploymentType)) {
        if (-not $contentPath) { $contentPath = "$($dt.Installer.Contents.Content.Location)".Trim() }
        if (-not $execContext) { $execContext = "$($dt.Installer.ExecutionContext)".Trim() }
        foreach ($arg in @($dt.Installer.InstallAction.Args.Arg)) {
            if ("$($arg.Name)" -eq 'ExecuteTime') { $t = 0; if ([int]::TryParse("$($arg.'#text')", [ref]$t)) { $runTime = $t } }
            if ("$($arg.Name)" -eq 'InstallCommandLine' -and -not $installCmd) { $installCmd = "$($arg.'#text')".Trim() }
        }
        foreach ($arg in @($dt.Installer.UninstallAction.Args.Arg)) {
            # SCCM stores the uninstall line under the same arg name as the install one
            if ("$($arg.Name)" -eq 'InstallCommandLine' -and -not $uninstCmd) { $uninstCmd = "$($arg.'#text')".Trim() }
        }
        if ($contentPath) { break }
    }
    if ($runTime -lt [int]$script:Cfg.MinMaxRuntimeMinutes) { $runTime = [int]$script:Cfg.DefaultMaxRuntimeMinutes }

    # Icon: SDMPackageXML carries it as base64 between <Icon><Data> ... </Data></Icon>.
    $iconB64 = ''
    try {
        $m = [regex]::Match($sdm, '(?is)<Icon[^>]*>\s*<Data>(?<b>.*?)</Data>\s*</Icon>')
        if ($m.Success) { $iconB64 = $m.Groups['b'].Value }
    } catch {}

    return @{
        DisplayName    = $localizedName
        Title          = "$($info.Title)".Trim()
        Publisher      = "$($info.Publisher)".Trim()
        SccmVersion    = "$($info.Version)".Trim()
        Description    = "$($info.Description)".Trim()
        LocalizedDesc  = $localizedDesc
        ContentPath    = $contentPath
        ExecutionCtx   = $execContext
        MaxRuntimeMin  = $runTime
        SccmInstall    = $installCmd
        SccmUninstall  = $uninstCmd
        IconBase64     = $iconB64
        ReturnCodes    = (Get-MigReturnCodes -Digest $digest)
        Digest         = $digest
    }
}

# --------------------------------------------------------------------------------------------
# PSADT GENERATION - decided from the content that is actually there, per application. This is
# what used to force a separate _newPSADT.ps1 script.
# --------------------------------------------------------------------------------------------
function Get-MigLaunchers {
    # The configured launcher list, normalised. settings.json delivers PSCustomObjects; the
    # built-in default is hashtables - this makes both look the same to the caller.
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($l in @($script:Cfg.Launchers)) {
        if (-not $l) { continue }
        $marker = if ($l -is [hashtable]) { "$($l.Marker)" } else { "$($l.Marker)" }
        if (-not "$marker".Trim()) { continue }
        # WrapServiceUI defaults to StageUtilities: if a launcher needs ServiceUI copied in, its
        # commands need the ServiceUI wrap too. A launcher can set it explicitly to separate them.
        $wrap = if ($null -ne $l.WrapServiceUI) { [bool]$l.WrapServiceUI } else { [bool]$l.StageUtilities }
        [void]$out.Add([pscustomobject]@{
            Marker         = "$($l.Marker)"
            Name           = $(if ("$($l.Name)".Trim()) { "$($l.Name)" } else { "$($l.Marker)" })
            SetupFile      = "$($l.SetupFile)"
            InstallCmd     = "$($l.InstallCmd)"
            UninstallCmd   = "$($l.UninstallCmd)"
            StageUtilities = [bool]$l.StageUtilities
            WrapServiceUI  = $wrap
        })
    }
    return $out.ToArray()
}

# The FILE an SCCM command line actually runs, resolved inside the content. "setup.exe /S",
# '"Sub\setup.exe" -q', 'msiexec /i "App.msi" /qn' -> the .exe/.msi that is really there.
# Returns the FileInfo, or $null when nothing in the command matches a file in the content.
function Get-MigCommandTarget {
    param([Parameter(Mandatory)][string]$ContentFolder, [string]$Command)
    if (-not "$Command".Trim()) { return $null }
    Use-FileSystemLocation
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches("$Command", '(?i)[""]?(?<f>[^""\s/]*[\w .\-()]+\.(?:exe|msi|msp|cmd|bat|ps1|vbs))[""]?')) {
        $leaf = Split-Path -Leaf ($m.Groups['f'].Value.Trim())
        # msiexec/cmd/powershell are the RUNNER, not the payload - keep looking past them
        if ($leaf -match '(?i)^(msiexec|cmd|powershell|pwsh|wscript|cscript|rundll32)\.exe$') { continue }
        if ($leaf -and -not $names.Contains($leaf)) { [void]$names.Add($leaf) }
    }
    foreach ($n in $names) {
        $hit = Get-ChildItem -LiteralPath $ContentFolder -Filter $n -File -Recurse -Depth 4 -ErrorAction SilentlyContinue |
               Sort-Object { ($_.FullName -split '[\\/]').Count } | Select-Object -First 1
        if ($hit) { return $hit }
    }
    return $null
}

function Resolve-MigDeployment {
    # Decides HOW this package gets installed by Intune. Three cases, in priority order:
    #
    #   1. A toolkit launcher that runs directly (PSADT v4 / Invoke-AppDeployToolkit.exe)
    #      -> wrap the folder holding it, copy NOTHING in.
    #   2. A toolkit launcher that needs helpers (PSADT v3 / Deploy-Application.exe)
    #      -> wrap the folder holding it, and copy ServiceUI.exe + Deploy-Application.exe(+.config)
    #         in beside it so the install runs visibly in the user session.
    #   3. No toolkit at all - a plain installer (setup.exe, an .msi, a script)
    #      -> wrap the folder holding the file SCCM's own command line runs, copy ServiceUI.exe in
    #         beside it, and reuse SCCM's install/uninstall command lines wrapped in ServiceUI.
    #
    # Anything else returns $null with a Reason, and the caller tells the user plainly.
    # Returns @{ Root; Generation; SetupFile; InstallCmd; UninstallCmd; StageUtilities; Explain; Reason }
    param(
        [Parameter(Mandatory)][string]$ContentFolder,
        [string]$SccmInstall,
        [string]$SccmUninstall
    )
    Use-FileSystemLocation
    if (-not (Test-Path -LiteralPath $ContentFolder)) { return @{ Reason = "the content location '$ContentFolder' is not reachable" } }

    # ---- 1 + 2: a configured toolkit launcher -------------------------------------------------
    $best = $null
    foreach ($l in (Get-MigLaunchers)) {
        $found = $null
        try {
            $found = Get-ChildItem -LiteralPath $ContentFolder -Filter $l.Marker -File -Recurse -Depth 4 -ErrorAction SilentlyContinue |
                     Where-Object { $_.FullName -notmatch '(?i)\\Frontend\\' } |
                     Sort-Object { ($_.FullName -split '[\\/]').Count } | Select-Object -First 1
        } catch {}
        if (-not $found) { continue }
        $depth = ($found.FullName -split '[\\/]').Count
        # first launcher in the configured order wins at equal depth, so the list is a priority list
        if ((-not $best) -or ($depth -lt $best.Depth)) { $best = @{ Depth = $depth; File = $found; Launcher = $l } }
    }
    if ($best) {
        $l = $best.Launcher
        # THE COMMANDS COME FROM SCCM - for every kind of package. That deployment type is the
        # record of how this application is really installed, switches and all, so it is what
        # moves to Intune. The launcher's configured command is only a fallback for a deployment
        # type that has none.
        $instSrc = 'SCCM'
        $install   = "$SccmInstall".Trim()
        $uninstall = "$SccmUninstall".Trim()
        if (-not $install)   { $install   = "$($l.InstallCmd)";   $instSrc = 'the launcher default (SCCM had none)' }
        if (-not $uninstall) { $uninstall = "$($l.UninstallCmd)" }
        # ... and where the launcher needs ServiceUI they get exactly the wrap the packaging tool
        # uses, so a migrated app and a freshly packaged one carry the same command line.
        if ($l.WrapServiceUI) {
            $install   = ConvertTo-MigServiceUiCommand $install
            $uninstall = ConvertTo-MigServiceUiCommand $uninstall
        }
        $explain = if ($l.StageUtilities) {
            "$($l.Name): found $($l.Marker). The .intunewin is built from the folder holding it, $($script:Cfg.UtilitiesPath) is copied in beside it, and the commands (from $instSrc) are wrapped in ServiceUI so the install shows in the user session."
        } else {
            "$($l.Name): found $($l.Marker). The .intunewin is built from the folder holding it, NOTHING is copied in - this toolkit runs directly - and the commands come from $instSrc."
        }
        return @{
            Root = $best.File.DirectoryName; Generation = $l.Name; SetupFile = $l.SetupFile
            InstallCmd = $install; UninstallCmd = $uninstall
            StageUtilities = $l.StageUtilities; Explain = $explain; Reason = ''
            CommandSource = $instSrc; NoUninstall = (-not "$uninstall".Trim())
        }
    }

    # ---- 3: no toolkit - a plain installer, driven by SCCM's own command lines -----------------
    if (-not "$SccmInstall".Trim()) {
        return @{ Reason = "no deployment toolkit was found in the content AND the SCCM deployment type has no install command line, so there is nothing to say how this package installs" }
    }
    $target = Get-MigCommandTarget -ContentFolder $ContentFolder -Command $SccmInstall
    if (-not $target) {
        return @{ Reason = "no deployment toolkit was found, and the file SCCM's install command runs ('$SccmInstall') is not present in the content location" }
    }
    $root = $target.DirectoryName
    $install = ConvertTo-MigServiceUiCommand -Command $SccmInstall
    $uninstall = if ("$SccmUninstall".Trim()) { ConvertTo-MigServiceUiCommand -Command $SccmUninstall } else { '' }
    $explain = "Plain installer (no deployment toolkit): SCCM runs '$($target.Name)'. The .intunewin is built from the folder holding it, ServiceUI.exe is copied in beside it, and SCCM's own command lines are reused, wrapped in ServiceUI so the install shows in the user session."
    return @{
        Root = $root; Generation = 'Plain installer'; SetupFile = $target.Name
        InstallCmd = $install; UninstallCmd = $uninstall
        StageUtilities = $true; Explain = $explain; Reason = ''
        NoUninstall = (-not "$SccmUninstall".Trim())
    }
}

function ConvertTo-MigServiceUiCommand {
    # Wrap a command in ServiceUI so Intune runs it in the USER session and its UI is visible.
    # Identical to the wrap the packaging tool uses, so a migrated app and a freshly packaged one
    # carry the exact same command line: unquote a leading "Something.exe" (SCCM stores
    # '"Deploy-Application.exe" Install') and prefix ServiceUI. Whatever switches the command
    # already had are preserved inside the wrap; an already-wrapped command is left alone.
    param([string]$Command)
    $c = "$Command".Trim()
    if (-not $c) { return $c }
    if ($c -match '(?i)\bServiceUI(\.exe)?\b') { return $c }
    $c = $c -replace '^"([^"]+\.exe)"', '$1'
    return ".\ServiceUI.exe -process:explorer.exe $c"
}

function Initialize-MigLauncherUtilities {
    # Copy the utilities next to the launcher in the STAGED COPY - the source share is never
    # touched. A toolkit package gets the whole set (its launcher exe + .config are REPLACED with
    # the tool's known-good copies); a plain installer only gets what it is missing, so a
    # non-toolkit package never has a toolkit exe dropped into it.
    param(
        [Parameter(Mandatory)][string]$ContentRoot,
        [Parameter(Mandatory)][string]$SetupFile,
        [string[]]$OnlyFiles
    )
    $src = Resolve-MigPath $script:Cfg.UtilitiesPath
    if (-not (Test-Path -LiteralPath $src)) {
        Write-MigLog "The utilities folder '$src' does not exist - whatever the install command needs must already be in the content." Warning
    } else {
        $copied = @(); $skipped = @()
        foreach ($f in @(Get-ChildItem -LiteralPath $src -File -ErrorAction SilentlyContinue)) {
            if ($f.Name -ieq 'IntuneWinAppUtil.exe') { continue }   # the packager never ships inside a package
            if ($OnlyFiles -and ($OnlyFiles -notcontains $f.Name)) { $skipped += $f.Name; continue }
            $existed = Test-Path -LiteralPath (Join-Path $ContentRoot $f.Name)
            Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $ContentRoot $f.Name) -Force
            $copied += "$($f.Name)$(if ($existed) { ' (replaced)' } else { ' (added)' })"
        }
        if ($copied.Count) { Write-MigLog "Copied into the package: $($copied -join ', ')" }
        if ($skipped.Count) { Write-MigLog "Not copied (this package does not need them): $($skipped -join ', ')" }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $ContentRoot $SetupFile))) {
        throw "The setup file '$SetupFile' is not in the staged content - the install command would fail on the device. Check UtilitiesPath ($($script:Cfg.UtilitiesPath))."
    }
}

function Test-MigCommandFilesPresent {
    # Whatever the install command actually launches must be inside the package, or the deployment
    # fails on the device with a useless error. Check every .exe the command names.
    param([Parameter(Mandatory)][string]$ContentRoot, [string]$Command)
    $missing = @()
    foreach ($m in [regex]::Matches("$Command", '(?i)(?<![\w\\/:.-])\.?\\?(?<f>[\w .\-]+\.exe)')) {
        $f = $m.Groups['f'].Value.Trim()
        if (-not $f) { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $ContentRoot $f))) { $missing += $f }
    }
    return ($missing | Select-Object -Unique)
}

# --------------------------------------------------------------------------------------------
# Build the .intunewin. The staged copy that gets wrapped is KEPT next to the .intunewin, with a
# manifest, so a failure can be inspected without re-running.
# --------------------------------------------------------------------------------------------
# Free bytes on the drive a path lives on, or -1 when it cannot be determined (a UNC target, say).
function Get-MigFreeSpace {
    param([string]$Path)
    try {
        $full = [IO.Path]::GetFullPath($Path)
        if ($full -match '^\\\\') { return -1 }          # a share - the server's free space is not ours to judge
        return ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($full))).AvailableFreeSpace
    } catch { return -1 }
}

function Get-MigFolderSize {
    param([string]$Path)
    Use-FileSystemLocation
    try {
        $m = Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
        return [int64]$m.Sum
    } catch { return [int64]0 }
}

function New-MigIntuneWinPackage {
    param(
        [Parameter(Mandatory)][string]$SourceContent,
        [Parameter(Mandatory)][string]$FullName,
        [Parameter(Mandatory)][string]$WorkFolder,
        [Parameter(Mandatory)][string]$Generation,
        [Parameter(Mandatory)][string]$SetupFile,
        [switch]$StageUtilities,
        [string]$InstallCommand,
        [string[]]$StageOnly
    )
    Use-FileSystemLocation
    $util = Resolve-MigPath 'Lib\IntuneWinAppUtil.exe'
    if (-not (Test-Path -LiteralPath $util)) {
        $found = Get-ChildItem -LiteralPath (Resolve-MigPath 'Lib') -Filter 'IntuneWinAppUtil.exe' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $util = $found.FullName }
    }
    if (-not (Test-Path -LiteralPath $util)) { throw "IntuneWinAppUtil.exe was not found under $(Resolve-MigPath 'Lib')." }

    $staged = Join-Path $WorkFolder 'StagedContent'
    if (Test-Path -LiteralPath $staged) { Remove-Item -LiteralPath $staged -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -Path $staged -ItemType Directory -Force | Out-Null

    Set-MigStatus -Indeterminate -Status "Copying content from the SCCM source share..."
    Write-MigLog "Copying content: $SourceContent  ->  $staged"
    # per-item + -LiteralPath so a folder name containing [ ] copies correctly
    foreach ($it in @(Get-ChildItem -LiteralPath $SourceContent -Force -ErrorAction Stop)) {
        Copy-Item -LiteralPath $it.FullName -Destination $staged -Recurse -Force -ErrorAction Stop
    }
    if ($StageUtilities) { Initialize-MigLauncherUtilities -ContentRoot $staged -SetupFile $SetupFile -OnlyFiles $StageOnly }

    $setupPath = Join-Path $staged $SetupFile
    if (-not (Test-Path -LiteralPath $setupPath)) {
        throw "The setup file '$SetupFile' is not present in the staged content ($staged) - the package cannot be wrapped."
    }
    # The install command usually names more than the setup file (ServiceUI.exe, a helper exe).
    # Catch a missing one HERE, where it is fixable, instead of on the device.
    if ($InstallCommand) {
        $absent = @(Test-MigCommandFilesPresent -ContentRoot $staged -Command $InstallCommand)
        if ($absent.Count) {
            throw "The install command needs $($absent -join ', '), which is not in the package. Put it in $($script:Cfg.UtilitiesPath) and set StageUtilities on the launcher in settings.json."
        }
    }

    $outFolder = Join-Path $WorkFolder 'Output'
    if (-not (Test-Path -LiteralPath $outFolder)) { New-Item -Path $outFolder -ItemType Directory -Force | Out-Null }
    Get-ChildItem -LiteralPath $outFolder -Filter *.intunewin -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

    $cmdLine = "IntuneWinAppUtil.exe -c `"$staged`" -s `"$SetupFile`" -o `"$outFolder`" -q"
    Write-MigLog "Building the .intunewin -> $cmdLine"
    Set-MigStatus -Indeterminate -Status 'Building the .intunewin package...'
    $utilOut = @(& $util -c "$staged" -s "$SetupFile" -o "$outFolder" -q 2>&1 | ForEach-Object { "$_" })
    $made = Get-ChildItem -LiteralPath $outFolder -Filter *.intunewin -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $made) {
        $tail = (@($utilOut | Where-Object { $_ } | Select-Object -Last 5) -join ' | ')
        throw "IntuneWinAppUtil did not produce a .intunewin (exit $LASTEXITCODE)$(if($tail){": $tail"})"
    }
    $dest = Join-Path $outFolder "$(Get-MigSafeName $FullName).intunewin"
    if ($made.FullName -ne $dest) { Move-Item -LiteralPath $made.FullName -Destination $dest -Force }

    $manifest = @(
        "Package      : $FullName",
        "Built        : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "PSADT        : $Generation",
        "SCCM source  : $SourceContent",
        "Wrapped root : $staged",
        "Setup file   : $SetupFile",
        "Command      : $cmdLine",
        '',
        'Content tree that shipped inside the .intunewin:'
    ) + @(Get-ChildItem -LiteralPath $staged -Recurse -Force -ErrorAction SilentlyContinue |
          ForEach-Object { '  ' + $_.FullName.Substring($staged.Length).TrimStart('\') + $(if ($_.PSIsContainer) { '\' } else { "  ($([math]::Round($_.Length/1KB,1)) KB)" }) })
    Set-Content -LiteralPath (Join-Path $WorkFolder '_IntuneWin-manifest.txt') -Value $manifest -Encoding UTF8

    if (-not $script:Cfg.KeepStagedContent) { Remove-Item -LiteralPath $staged -Recurse -Force -ErrorAction SilentlyContinue }
    Write-MigLog ".intunewin built: $dest ($([math]::Round((Get-Item -LiteralPath $dest).Length/1MB,1)) MB)" Success
    return $dest
}

# --------------------------------------------------------------------------------------------
# GRAPH - auth header, request wrapper, chunked blob upload.
# The header is produced by MSAL.PS / Connect-MSIntuneGraph on the UI thread; the worker gets the
# bearer string through $Sync and asks the UI thread for a fresh one when it expires.
# --------------------------------------------------------------------------------------------
function Set-MigProxyCredentials {
    # A machine.config <defaultProxy> that fails to build throws inside MSAL ("Error creating the
    # Web Proxy ..."). Resolving the WinINET proxy directly bypasses that config section.
    try {
        $sys = [System.Net.WebRequest]::GetSystemWebProxy()
        if ($sys) {
            try { $sys.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials } catch {}
            [System.Net.WebRequest]::DefaultWebProxy = $sys
        }
    } catch {
        try { [System.Net.WebRequest]::DefaultWebProxy = $null } catch {}
    }
}

# Where to look for the helper modules, most specific first. NOTE the @( ) around each call:
# "Resolve-MigPath 'a', (Resolve-MigPath 'b')" would pass ONE ARRAY as the single parameter
# instead of calling it twice - that exact mistake is what made the tool report the modules as
# missing while they were sitting in Lib\PowerShell Module.
function Get-MigModuleSearchRoots {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($rel in @("$($script:Cfg.ModulePath)", 'Lib\PowerShell Module', 'Lib', 'Modules', '.')) {
        if (-not "$rel".Trim()) { continue }
        $p = Resolve-MigPath $rel
        if ($p -and -not $out.Contains($p)) { [void]$out.Add($p) }
    }
    return $out.ToArray()
}

function Find-MigModuleManifest {
    # The tool folder first (a portable copy must use its OWN modules), then whatever is installed
    # on the machine, so a workstation that already has the modules works with no Lib\ at all.
    param([Parameter(Mandatory)][string]$ManifestName)
    foreach ($root in (Get-MigModuleSearchRoots)) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $hit = Get-ChildItem -LiteralPath $root -Recurse -Filter $ManifestName -File -ErrorAction SilentlyContinue |
               Sort-Object FullName | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    $modName = $ManifestName -replace '\.psd1$', ''
    $inst = Get-Module -ListAvailable -Name $modName -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending | Select-Object -First 1
    if ($inst -and $inst.Path) { return $inst.Path }
    return $null
}

function Copy-MigModuleLocal {
    # Only UNC paths are staged; anything local is returned unchanged.
    param([Parameter(Mandatory)][string]$ManifestPath)
    if ($ManifestPath -notmatch '^\\\\') { return $ManifestPath }
    try {
        $srcDir = Split-Path -Parent $ManifestPath
        $name   = Split-Path -Leaf $srcDir
        $cache  = Join-Path (Join-Path (Resolve-MigPath $script:Cfg.ReportRoot) '_modules') $name
        $dstManifest = Join-Path $cache (Split-Path -Leaf $ManifestPath)
        $fresh = (Test-Path -LiteralPath $dstManifest) -and
                 ((Get-Item -LiteralPath $dstManifest).LastWriteTimeUtc -ge (Get-Item -LiteralPath $ManifestPath).LastWriteTimeUtc)
        if (-not $fresh) {
            if (Test-Path -LiteralPath $cache) { Remove-Item -LiteralPath $cache -Recurse -Force -ErrorAction SilentlyContinue }
            New-Item -Path (Split-Path -Parent $cache) -ItemType Directory -Force | Out-Null
            Copy-Item -LiteralPath $srcDir -Destination $cache -Recurse -Force -ErrorAction Stop
            Get-ChildItem -LiteralPath $cache -Recurse -File -ErrorAction SilentlyContinue |
                ForEach-Object { try { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue } catch {} }
            Write-MigLog "Staged the module '$name' from the share to a local cache so it can be imported."
        }
        if (Test-Path -LiteralPath $dstManifest) { return $dstManifest }
    } catch {
        Write-MigLog "Could not stage the module locally ($($_.Exception.Message)); importing it straight from the share." Warning
    }
    return $ManifestPath
}

function Connect-MigIntune {
    # Runs on the UI thread. Uses the IntuneWin32App module ONLY to obtain a token - every Graph
    # call and the whole content upload are done by this script.
    param([Parameter(Mandatory)][string]$TenantId)
    Set-MigProxyCredentials
    if (-not (Get-Command Connect-MSIntuneGraph -ErrorAction SilentlyContinue)) {
        $msal = Find-MigModuleManifest -ManifestName 'MSAL.PS.psd1'
        $iwa  = Find-MigModuleManifest -ManifestName 'IntuneWin32App.psd1'
        if (-not $msal -or -not $iwa) {
            $lookedIn = (Get-MigModuleSearchRoots) -join "`r`n  "
            $whatIsMissing = @()
            if (-not $msal) { $whatIsMissing += 'MSAL.PS' }
            if (-not $iwa)  { $whatIsMissing += 'IntuneWin32App' }
            throw "Could not find $($whatIsMissing -join ' and '). Searched (recursively):`r`n  $lookedIn`r`nAlso checked the modules installed on this machine. Put the module folder under the tool's Lib\PowerShell Module\, or set 'ModulePath' in settings.json."
        }
        Write-MigLog "Using MSAL.PS from $msal"
        Write-MigLog "Using IntuneWin32App from $iwa"
        try { Set-ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue } catch {}
        # A module on a UNC share can fail to import ("Cannot add type. Compilation errors
        # occurred.") because MSAL.PS compiles C# that references its own DLLs and the compiler
        # will not load those from a remote path. Staging to a local cache first fixes it; a
        # local path passes straight through.
        $msal = Copy-MigModuleLocal -ManifestPath $msal
        $iwa  = Copy-MigModuleLocal -ManifestPath $iwa
        Import-Module $msal -ErrorAction Stop      # MSAL.PS first - IntuneWin32App depends on it
        Import-Module $iwa  -ErrorAction Stop
    }
    $warns = $null
    Connect-MSIntuneGraph -TenantID $TenantId -WarningVariable warns -WarningAction SilentlyContinue | Out-Null
    if (-not $Global:AuthenticationHeader -and -not $Global:AccessToken) {
        $why = if ($warns) { ($warns | ForEach-Object { "$_" }) -join ' | ' } else { 'sign-in returned no token (cancelled, or blocked by Conditional Access).' }
        throw "No token after sign-in - $why"
    }
    return (Get-MigAuthHeaderValue)
}

function Get-MigAuthHeaderValue {
    if ($Global:AuthenticationHeader -and $Global:AuthenticationHeader.Authorization) { return "$($Global:AuthenticationHeader.Authorization)" }
    if ($Global:AccessToken) { return "Bearer $($Global:AccessToken.AccessToken)" }
    return ''
}

function Request-MigTokenRefresh {
    # Called from the worker. Raises a flag the UI thread's dispatcher timer picks up, then waits
    # for the refreshed bearer string. Returns $true when a new token arrived.
    if (-not $script:Sync) { return $false }
    $script:Sync.ReauthRequested = $true
    $deadline = (Get-Date).AddMinutes(5)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        if (-not $script:Sync.ReauthRequested) {
            if ("$($script:Sync.AuthHeader)".Trim()) { $script:Auth = "$($script:Sync.AuthHeader)"; return $true }
            return $false
        }
        if ($script:Sync.CancelRequested) { return $false }
    }
    return $false
}

function Invoke-MigGraph {
    param([Parameter(Mandatory)][string]$Method, [Parameter(Mandatory)][string]$Uri, $Body)
    if (-not "$($script:Auth)".Trim()) { throw 'Not signed in to Intune (no bearer token).' }
    $p = @{ Method = $Method; Uri = $Uri; Headers = @{ Authorization = "$($script:Auth)" }; ErrorAction = 'Stop' }
    if ($Body) {
        $json = if ($Body -is [string]) { "$Body" } else { $Body | ConvertTo-Json -Depth 20 -Compress }
        # PS 5.1 encodes a STRING body as ASCII, which mangles any non-ASCII character in a vendor's
        # description/publisher and makes Graph answer 400 "Unable to read JSON request payload".
        # Sending explicit UTF-8 BYTES keeps the body byte-exact.
        $p['Body']        = [Text.Encoding]::UTF8.GetBytes($json)
        $p['ContentType'] = 'application/json; charset=utf-8'
    }
    $reauthed = $false
    for ($try = 1; $try -le 4; $try++) {
        try { return Invoke-RestMethod @p }
        catch {
            $sc = $null; try { $sc = [int]$_.Exception.Response.StatusCode } catch {}
            $detail = "$($_.ErrorDetails.Message)"
            if (-not $detail) {
                try { $rs = $_.Exception.Response.GetResponseStream(); $sr = New-Object IO.StreamReader($rs); $detail = $sr.ReadToEnd(); $sr.Close() } catch {}
            }
            if ($sc -eq 401 -and -not $reauthed) {
                $reauthed = $true
                Write-MigLog 'The Intune token expired mid-operation - refreshing and retrying...' Warning
                if (Request-MigTokenRefresh) { $p['Headers'] = @{ Authorization = "$($script:Auth)" }; continue }
            }
            if ($try -ge 4 -or ($sc -and $sc -lt 500 -and $sc -ne 429)) {
                if ($detail) { $detail = ($detail -replace '\s+', ' ').Trim(); if ($detail.Length -gt 700) { $detail = $detail.Substring(0, 700) } }
                throw "Graph $Method $($Uri -replace '\?.*$','') -> HTTP $sc$(if ($detail) { ": $detail" })"
            }
            $wait = [Math]::Min(20, 3 * $try)
            if ($sc -eq 429) { try { $ra = [int]"$($_.Exception.Response.Headers['Retry-After'])"; if ($ra -gt 0) { $wait = [Math]::Min(60, $ra) } } catch {} }
            Start-Sleep -Seconds $wait
        }
    }
}

function Get-MigIntuneWinMetadata {
    param([Parameter(Mandatory)][string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -like '*Detection.xml' } | Select-Object -First 1
        if (-not $entry) { throw "Detection.xml was not found inside $Path" }
        $sr = New-Object System.IO.StreamReader($entry.Open()); [xml]$xml = $sr.ReadToEnd(); $sr.Close()
    } finally { $zip.Dispose() }
    $i = $xml.ApplicationInfo
    return [pscustomobject]@{ InnerFileName = $i.FileName; Size = [int64]$i.UnencryptedContentSize; Enc = $i.EncryptionInfo }
}

function Expand-MigEncryptedPayload {
    param([Parameter(Mandatory)][string]$IntuneWinPath, [Parameter(Mandatory)][string]$InnerFileName, [Parameter(Mandatory)][string]$WorkFolder)
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $tmp = Join-Path $WorkFolder ("payload_{0}.bin" -f ([guid]::NewGuid().ToString('N')))
    $zip = [System.IO.Compression.ZipFile]::OpenRead($IntuneWinPath)
    try {
        $e = $zip.Entries | Where-Object { $_.FullName -like "*Contents/$InnerFileName" -or $_.FullName -like "*Contents\$InnerFileName" } | Select-Object -First 1
        if (-not $e) { throw "The encrypted payload '$InnerFileName' was not found inside the .intunewin." }
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $tmp, $true)
    } finally { $zip.Dispose() }
    return $tmp
}

function Wait-MigFileState {
    param([Parameter(Mandatory)][string]$FileUri, [Parameter(Mandatory)][string]$Stage, [int]$TimeoutSec = 1800)
    $deadline = (Get-Date).AddSeconds($TimeoutSec); $state = ''
    do {
        Start-Sleep -Seconds 4
        if (Test-MigCancelled) { throw 'Cancelled by the operator.' }
        $f = $null
        try { $f = Invoke-MigGraph GET $FileUri }
        catch { Write-MigLog "Upload status poll hiccup at '$Stage' ($($_.Exception.Message)) - still polling..." Warning; continue }
        $state = "$($f.uploadState)"
        if ($state -eq "$($Stage)Success") { return $f }
        if ($state -eq "$($Stage)Failed")  { throw "The Intune upload stage '$Stage' failed (uploadState = $state)." }
    } while ((Get-Date) -lt $deadline)
    throw "Timed out at the Intune upload stage '$Stage' (last state: $state)."
}

function Wait-MigCommittable {
    # Commit is rejected until the SAS request OR its renewal has settled to a success state.
    param([Parameter(Mandatory)][string]$FileUri, [int]$TimeoutSec = 600)
    $deadline = (Get-Date).AddSeconds($TimeoutSec); $state = ''
    do {
        $f = $null
        try { $f = Invoke-MigGraph GET $FileUri }
        catch { Start-Sleep -Seconds 4; continue }
        $state = "$($f.uploadState)"
        if ($state -eq 'azureStorageUriRequestSuccess' -or $state -eq 'azureStorageUriRenewalSuccess') { return $f }
        if ($state -like '*Failed') { throw "The upload failed before commit (uploadState = $state)." }
        Start-Sleep -Seconds 4
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for a committable upload state (last: $state)."
}

function Send-MigBlob {
    # THE large-application path. One kept-alive HttpClient, raw block PUTs, SAS renewal on a timer
    # AND on a failed block (resume, not restart). This is what removes the old 30 GB abort.
    param([Parameter(Mandatory)][string]$SasUri, [Parameter(Mandatory)][string]$FilePath, [Parameter(Mandatory)][string]$FileUri)
    $blockSize = [int]$script:Cfg.BlockSizeMB * 1MB
    $total  = (Get-Item -LiteralPath $FilePath).Length
    $blocks = [Math]::Max(1, [Math]::Ceiling($total / $blockSize))
    $ids    = New-Object System.Collections.Generic.List[string]

    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
    $handler = New-Object System.Net.Http.HttpClientHandler
    try {
        $handler.Proxy = [System.Net.WebRequest]::DefaultWebProxy; $handler.UseProxy = $true
        if ($handler.Proxy) { $handler.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials }
    } catch {}
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromMinutes(20)

    $put = {
        param($u, [byte[]]$buf, [int]$len, [hashtable]$reqHdrs, [string]$ctype, [string]$what)
        for ($t = 1; $t -le 4; $t++) {
            $req = $null
            try {
                $req = New-Object System.Net.Http.HttpRequestMessage -ArgumentList ([System.Net.Http.HttpMethod]::Put, $u)
                $content = New-Object System.Net.Http.ByteArrayContent -ArgumentList ($buf, [int]0, [int]$len)
                $content.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue -ArgumentList $ctype
                $req.Content = $content
                if ($reqHdrs) { foreach ($k in $reqHdrs.Keys) { [void]$req.Headers.TryAddWithoutValidation($k, "$($reqHdrs[$k])") } }
                $resp = $client.SendAsync($req).GetAwaiter().GetResult()
                $code = [int]$resp.StatusCode; $resp.Dispose()
                if ($code -ge 200 -and $code -lt 300) { return }
                throw "HTTP $code"
            } catch {
                if ($t -ge 4) { throw "$what failed after retries: $($_.Exception.Message)" }
                Start-Sleep -Seconds ([Math]::Min(30, 3 * $t))
            } finally { if ($req) { $req.Dispose() } }
        }
    }

    $fs = [System.IO.File]::OpenRead($FilePath)
    $lastRenew = Get-Date
    $started   = Get-Date
    try {
        $buffer = New-Object byte[] $blockSize
        $idx = 0; $sent = 0L
        while (($read = $fs.Read($buffer, 0, $buffer.Length)) -gt 0) {
            if (Test-MigCancelled) { throw 'Cancelled by the operator.' }
            if (((Get-Date) - $lastRenew).TotalMinutes -ge [int]$script:Cfg.SasRenewMinutes) {
                try {
                    Write-MigLog 'Renewing the upload SAS (long upload)...'
                    Invoke-MigGraph POST "$FileUri/renewUpload" '{}' | Out-Null
                    $r = Wait-MigFileState -FileUri $FileUri -Stage 'azureStorageUriRenewal'
                    $SasUri = $r.azureStorageUri; $lastRenew = Get-Date
                } catch { Write-MigLog "The scheduled SAS renewal failed ($($_.Exception.Message)) - continuing; a failed block will renew and resume." Warning }
            }
            $blockId = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($idx.ToString('D6')))
            $ids.Add($blockId)
            $ok = $false
            for ($round = 1; $round -le 3 -and -not $ok; $round++) {
                $uri = "$SasUri&comp=block&blockid=$([uri]::EscapeDataString($blockId))"
                try { & $put $uri $buffer $read @{ 'x-ms-blob-type' = 'BlockBlob' } 'application/octet-stream' "Block $idx"; $ok = $true }
                catch {
                    if ($round -ge 3) { throw }
                    Write-MigLog "Block $idx failed ($($_.Exception.Message)); renewing the SAS and resuming from the same block..." Warning
                    try {
                        Invoke-MigGraph POST "$FileUri/renewUpload" '{}' | Out-Null
                        $r = Wait-MigFileState -FileUri $FileUri -Stage 'azureStorageUriRenewal'
                        $SasUri = $r.azureStorageUri; $lastRenew = Get-Date
                    } catch {}
                }
            }
            $idx++; $sent += $read
            $mbSent = [math]::Round($sent / 1MB, 1); $mbTotal = [math]::Round($total / 1MB, 1)
            $elapsed = ((Get-Date) - $started).TotalSeconds
            $rate = if ($elapsed -gt 1) { [math]::Round(($sent / 1MB) / $elapsed, 1) } else { 0 }
            if (($idx % 10) -eq 0 -or $idx -eq $blocks) { Write-MigLog ("Upload: block {0}/{1} - {2} of {3} MB ({4} MB/s)" -f $idx, $blocks, $mbSent, $mbTotal, $rate) }
            Set-MigStatus -Percent ([int](20 + 60 * ($sent / [double]$total))) -Status ("Uploading $mbSent / $mbTotal MB  (block $idx of $blocks, $rate MB/s)")
        }
        $list = '<?xml version="1.0" encoding="utf-8"?><BlockList>' + (($ids | ForEach-Object { "<Latest>$_</Latest>" }) -join '') + '</BlockList>'
        $listBytes = [Text.Encoding]::UTF8.GetBytes($list)
        Write-MigLog "Committing the block list ($($ids.Count) blocks)..."
        Set-MigStatus -Percent 82 -Status 'Committing the uploaded blocks...'
        & $put "$SasUri&comp=blocklist" $listBytes $listBytes.Length $null 'text/plain' 'Block-list commit'
    } finally {
        $fs.Close(); $fs.Dispose()
        try { $client.Dispose(); $handler.Dispose() } catch {}
    }
}

function Set-MigAppContent {
    param([Parameter(Mandatory)][string]$AppId, [Parameter(Mandatory)][string]$IntuneWinPath, [Parameter(Mandatory)][string]$WorkFolder)
    $meta    = Get-MigIntuneWinMetadata -Path $IntuneWinPath
    $payload = Expand-MigEncryptedPayload -IntuneWinPath $IntuneWinPath -InnerFileName $meta.InnerFileName -WorkFolder $WorkFolder
    try {
        $encSize = (Get-Item -LiteralPath $payload).Length
        $appUri  = "$($script:Cfg.GraphBase)/deviceAppManagement/mobileApps/$AppId"
        $base    = "$appUri/microsoft.graph.win32LobApp/contentVersions"
        $cv  = Invoke-MigGraph POST $base '{}'
        $vid = $cv.id
        $fileBody = @{
            '@odata.type' = '#microsoft.graph.mobileAppContentFile'
            name          = $meta.InnerFileName
            size          = [int64]$meta.Size
            sizeEncrypted = [int64]$encSize
            manifest      = $null
            isDependency  = $false
        }
        $file    = Invoke-MigGraph POST "$base/$vid/files" $fileBody
        $fileUri = "$base/$vid/files/$($file.id)"
        $ready   = Wait-MigFileState -FileUri $fileUri -Stage 'azureStorageUriRequest'
        Write-MigLog "Uploading $([math]::Round($encSize/1MB,1)) MB to Azure blob storage..."
        Set-MigStatus -Percent 20 -Status 'Uploading the content to Azure...'
        Send-MigBlob -SasUri $ready.azureStorageUri -FilePath $payload -FileUri $fileUri
        $commit = @{ fileEncryptionInfo = @{
            encryptionKey        = $meta.Enc.EncryptionKey
            macKey               = $meta.Enc.MacKey
            initializationVector = $meta.Enc.InitializationVector
            mac                  = $meta.Enc.Mac
            profileIdentifier    = 'ProfileVersion1'
            fileDigest           = $meta.Enc.FileDigest
            fileDigestAlgorithm  = $meta.Enc.FileDigestAlgorithm } }
        Set-MigStatus -Percent 84 -Status 'Finalising the upload (commit)...'
        $committed = $false
        for ($ct = 1; $ct -le 6 -and -not $committed; $ct++) {
            Wait-MigCommittable -FileUri $fileUri | Out-Null
            try { Invoke-MigGraph POST "$fileUri/commit" $commit | Out-Null; $committed = $true }
            catch {
                $em = "$($_.Exception.Message)"
                if ($ct -ge 6 -or $em -notmatch 'commit can not be started|transitioned to|SAS request or renewal') { throw }
                Write-MigLog "Commit is not ready yet (the SAS renewal is still settling); retrying in 10 s ($ct of 6)..." Warning
                Start-Sleep -Seconds 10
            }
        }
        Set-MigStatus -Percent 90 -Status 'Waiting for Intune to confirm the upload...'
        Wait-MigFileState -FileUri $fileUri -Stage 'commitFile' | Out-Null
        Set-MigStatus -Percent 93 -Status 'Setting the committed content version...'
        Invoke-MigGraph PATCH $appUri (@{ '@odata.type' = '#microsoft.graph.win32LobApp'; committedContentVersion = "$vid" }) | Out-Null
        Write-MigLog "Content version $vid committed." Success
        return $vid
    } finally { Remove-Item -LiteralPath $payload -Force -ErrorAction SilentlyContinue }
}

# --------------------------------------------------------------------------------------------
# Duplicate guard - is this package already in Intune? Matched on the BRANDING KEY, never on the
# display name (Intune happily hosts several apps with the same name).
# --------------------------------------------------------------------------------------------
function Clear-MigAppListCache { $script:Win32AppCache = $null }

function Get-MigIntuneWin32Apps {
    # Cached for the run. Without this a 20-application batch listed every Win32 app in the whole
    # tenant 20 times over, just to answer "does this one already exist?".
    if ($script:Win32AppCache) { return $script:Win32AppCache }
    $apps = New-Object System.Collections.Generic.List[object]
    $uri = "$($script:Cfg.GraphBase)/deviceAppManagement/mobileApps?`$filter=isof('microsoft.graph.win32LobApp')"
    $guard = 0
    while ($uri -and $guard -lt 300) {
        $guard++
        $r = $null
        try { $r = Invoke-MigGraph GET $uri } catch { break }
        foreach ($a in @($r.value)) { [void]$apps.Add($a) }
        $uri = "$($r.'@odata.nextLink')"
    }
    $script:Win32AppCache = $apps.ToArray()
    return $script:Win32AppCache
}

# -1 / 0 / 1. Real version compare when both look like versions, otherwise a plain text compare,
# so odd values ("23.006.20320", "8", "2024a") never throw.
function Compare-MigVersion {
    param([string]$A, [string]$B)
    $ca = ("$A" -replace '[^0-9.]', '').Trim('.'); $cb = ("$B" -replace '[^0-9.]', '').Trim('.')
    if ($ca -and $cb) {
        while (($ca.ToCharArray() | Where-Object { $_ -eq '.' }).Count -lt 1) { $ca = "$ca.0" }
        while (($cb.ToCharArray() | Where-Object { $_ -eq '.' }).Count -lt 1) { $cb = "$cb.0" }
        $va = $null; $vb = $null
        if ([version]::TryParse($ca, [ref]$va) -and [version]::TryParse($cb, [ref]$vb)) { return $va.CompareTo($vb) }
    }
    return [string]::Compare("$A", "$B", $true)
}

# The stage recorded in the app's Notes JSON (LIVE / UAT / RETIRED / ...), or 'unknown'.
function Get-MigAppLifecycle {
    param($App)
    $n = "$($App.notes)".Trim()
    if ($n -match '^\s*\{') { try { $j = $n | ConvertFrom-Json; if ("$($j.lifecycle)".Trim()) { return "$($j.lifecycle)".Trim().ToUpper() } } catch {} }
    if ($n -match '(?i)"?lifecycle"?\s*[:=]\s*"?([A-Za-z]+)') { return $Matches[1].ToUpper() }
    return 'unknown'
}

# Every app in Intune that looks like ANOTHER VERSION of this package - same publisher and product,
# any version. Classified against the version being migrated so the user can decide what to do.
function Get-MigRelatedApps {
    param([Parameter(Mandatory)][hashtable]$Name)
    $out = New-Object System.Collections.Generic.List[object]
    $appTok = ([regex]::Replace("$($Name.AppName)", '[^A-Za-z0-9]', '')).ToLowerInvariant()
    if (-not $appTok) { return $out.ToArray() }
    $venTok = ([regex]::Replace("$($Name.Vendor)", '[^A-Za-z0-9]', '')).ToLowerInvariant()
    foreach ($a in @(Get-MigIntuneWin32Apps)) {
        $dn = ([regex]::Replace("$($a.displayName)", '[^A-Za-z0-9]', '')).ToLowerInvariant()
        if (-not $dn) { continue }
        $nameHit = $dn.Contains($appTok) -or $appTok.Contains($dn)
        $pubTok  = ([regex]::Replace("$($a.publisher)", '[^A-Za-z0-9]', '')).ToLowerInvariant()
        $pubHit  = (-not $venTok) -or (-not $pubTok) -or $pubTok.Contains($venTok) -or $venTok.Contains($pubTok)
        if (-not ($nameHit -and $pubHit)) { continue }
        $ver = "$($a.displayVersion)".Trim()
        $cmp = Compare-MigVersion $ver "$($Name.Version)"
        $rel = if ($cmp -eq 0) { 'Same' } elseif ($cmp -lt 0) { 'Lower' } else { 'Higher' }
        [void]$out.Add([pscustomobject]@{
            Id = "$($a.id)"; DisplayName = "$($a.displayName)"; Version = $ver
            Lifecycle = (Get-MigAppLifecycle -App $a); Relation = $rel
            Created = "$($a.createdDateTime)" })
    }
    return @($out | Sort-Object @{ Expression = { switch ($_.Relation) { 'Same' {0} 'Higher' {1} default {2} } } }, Version)
}

# Make the newly created app supersede the older ones (Intune "update" supersedence).
function Add-MigSupersedence {
    param([Parameter(Mandatory)][string]$NewAppId, [Parameter(Mandatory)][string[]]$OldAppIds)
    $rels = @($OldAppIds | Where-Object { $_ } | Select-Object -Unique | ForEach-Object {
        @{ '@odata.type' = '#microsoft.graph.mobileAppSupersedence'; supersedenceType = 'update'; targetId = "$_" } })
    if (-not $rels.Count) { return 0 }
    Invoke-MigGraph POST "$($script:Cfg.GraphBase)/deviceAppManagement/mobileApps/$NewAppId/updateRelationships" (@{ relationships = @($rels) }) | Out-Null
    Write-MigLog "Supersedence: this app now supersedes $($rels.Count) older version(s)." Success
    return $rels.Count
}

# --- the SECOND duplicate check ---------------------------------------------------------------
# The branding key finds a package this team already migrated. This finds the same PRODUCT already
# in Intune under someone else's name: same uninstall detection (key path incl. the 32/64-bit hive
# + the version) or the same MSI ProductCode. That is what a non-branded, out-of-band copy shares
# even when the display name and the branding key are completely different.
function Get-MigUninstallSignature {
    param($Rules)
    $sig = @{ KeyPath = ''; ValueName = ''; Is32Bit = $false; Version = ''; ProductCode = '' }
    $brandRx = if ("$($script:Cfg.BrandingKeyRoot)".Trim()) { '(?i)' + [regex]::Escape($script:Cfg.BrandingKeyRoot) } else { '(?!x)x' }
    foreach ($r in @($Rules)) {
        $od = "$($r.'@odata.type')"
        if ($od -match '(?i)ProductCodeDetection') { if (-not $sig.ProductCode) { $sig.ProductCode = "$($r.productCode)".Trim() }; continue }
        if ($od -match '(?i)RegistryDetection') {
            $kp = "$($r.keyPath)"
            if (-not $kp -or ($kp -match $brandRx)) { continue }   # the branding rule is not an identity
            if (-not $sig.KeyPath) {
                $sig.KeyPath   = $kp
                $sig.ValueName = "$($r.valueName)".Trim()
                $sig.Is32Bit   = [bool]$r.check32BitOn64System
                $sig.Version   = "$($r.detectionValue)".Trim()
            }
        }
    }
    return $sig
}

# PURE. Does an existing app's detection match our signature, and does it carry a branding key?
# Registry: key path + value name + version + 32/64-bit must all match; the operator and the
# datatype are deliberately ignored. ProductCode: the GUID matches directly, or appears in the key.
function Test-MigAppMatchesUninstall {
    param($DetectionRules, [hashtable]$Sig)
    $branded = $false; $match = $false
    $brandRx = if ("$($script:Cfg.BrandingKeyRoot)".Trim()) { '(?i)' + [regex]::Escape($script:Cfg.BrandingKeyRoot) } else { '(?!x)x' }
    foreach ($r in @($DetectionRules)) {
        $kp = "$($r.keyPath)"
        if ($kp -and ($kp -match $brandRx)) { $branded = $true; continue }
        $od = "$($r.'@odata.type')"
        if ($od -match '(?i)ProductCodeDetection') {
            if ($Sig.ProductCode -and "$($r.productCode)".Trim() -ieq $Sig.ProductCode) { $match = $true }
            continue
        }
        if ($od -match '(?i)RegistryDetection' -and $kp) {
            $sameKey  = $Sig.KeyPath -and ($kp.TrimEnd('\') -ieq $Sig.KeyPath.TrimEnd('\'))
            $sameName = (-not $Sig.ValueName) -or (-not "$($r.valueName)".Trim()) -or ("$($r.valueName)".Trim() -ieq $Sig.ValueName)
            $sameBits = ([bool]$r.check32BitOn64System -eq $Sig.Is32Bit)
            $sameVer  = (-not $Sig.Version) -or ("$($r.detectionValue)".Trim() -ieq $Sig.Version)
            if ($sameKey -and $sameName -and $sameBits -and $sameVer) { $match = $true }
            elseif ($Sig.ProductCode -and ($kp -match [regex]::Escape($Sig.ProductCode)) -and $sameBits -and $sameVer) { $match = $true }
        }
    }
    return @{ Match = $match; Branded = $branded }
}

function Find-MigUninstallMatches {
    param([hashtable]$Sig, [hashtable]$Name)
    $out = New-Object System.Collections.Generic.List[object]
    if (-not $Sig.KeyPath -and -not $Sig.ProductCode) { return $out.ToArray() }
    $wantVer = "$($Name.Version)".Trim()
    $appTok  = ([regex]::Replace("$($Name.AppName)", '[^A-Za-z0-9]', '')).ToLowerInvariant()
    $cands = @(Get-MigIntuneWin32Apps | Where-Object {
        $v = "$($_.displayVersion)".Trim()
        $dn = ([regex]::Replace("$($_.displayName)", '[^A-Za-z0-9]', '')).ToLowerInvariant()
        ($wantVer -and ($v -ieq $wantVer)) -or ($appTok -and $dn -and ($dn.Contains($appTok) -or $appTok.Contains($dn)))
    })
    foreach ($a in $cands) {
        $full = $null
        try { $full = Invoke-MigGraph GET "$($script:Cfg.GraphBase)/deviceAppManagement/mobileApps/$($a.id)" } catch { continue }
        $res = Test-MigAppMatchesUninstall -DetectionRules $full.detectionRules -Sig $Sig
        if (-not $res.Match) { continue }
        [void]$out.Add([pscustomobject]@{
            Id = "$($full.id)"; Name = "$($full.displayName)"; Branded = [bool]$res.Branded
            Lifecycle = (Get-MigAppLifecycle -App $full) })
    }
    return $out.ToArray()
}

# Which of these applications are ALREADY in Intune? Run before anything is created so the user
# gets ONE question instead of a modal interrupting every second application mid-batch.
function Get-MigDuplicatePreflight {
    param([Parameter(Mandatory)][string[]]$Applications)
    $out = New-Object System.Collections.Generic.List[object]
    $i = 0
    foreach ($appName in $Applications) {
        $i++
        if (Test-MigCancelled) { break }
        Set-MigStatus -Indeterminate -Status "Checking $i of $($Applications.Count) against Intune..."
        $nm = ConvertFrom-MigPackageName -FullName $appName
        $related = @()
        try { $related = @(Get-MigRelatedApps -Name $nm) }
        catch { Write-MigLog "Could not check '$appName' against Intune: $($_.Exception.Message)" Warning; continue }
        if (-not $related.Count) { continue }
        $same   = @($related | Where-Object { $_.Relation -eq 'Same' })
        $lower  = @($related | Where-Object { $_.Relation -eq 'Lower' })
        $higher = @($related | Where-Object { $_.Relation -eq 'Higher' })
        foreach ($r in $related) {
            Write-MigLog "'$appName': Intune already has '$($r.DisplayName)' v$($r.Version) [$($r.Relation.ToLower())]$(if ($r.Lifecycle -and $r.Lifecycle -ne 'unknown') { " - lifecycle $($r.Lifecycle)" }), AppId $($r.Id)." Warning
        }
        [void]$out.Add([pscustomobject]@{
            Application = $appName; Version = "$($nm.Version)"
            Same = $same; Lower = $lower; Higher = $higher; All = $related })
    }
    return $out.ToArray()
}

function Find-MigExistingApp {
    param([Parameter(Mandatory)][hashtable]$Name)
    $rx = '(?i)' + [regex]::Escape("$($script:Cfg.BrandingKeyRoot)\$($Name.FullName)")
    $all = @(Get-MigIntuneWin32Apps)
    $nameKey = ([regex]::Replace("$($Name.AppName)", '[^A-Za-z0-9]', '')).ToLowerInvariant()
    $cand = @($all | Where-Object {
        $dv = "$($_.displayVersion)".Trim()
        $dn = ([regex]::Replace("$($_.displayName)", '[^A-Za-z0-9]', '')).ToLowerInvariant()
        ($Name.Version -and $dv -ieq "$($Name.Version)") -or ($nameKey -and $dn -and ($dn.Contains($nameKey) -or $nameKey.Contains($dn)))
    })
    foreach ($a in $cand) {
        $full = $null
        try { $full = Invoke-MigGraph GET "$($script:Cfg.GraphBase)/deviceAppManagement/mobileApps/$($a.id)" } catch { continue }
        if (@($full.detectionRules) | Where-Object { "$($_.keyPath)" -match $rx }) { return $full }
    }
    return $null
}

# --------------------------------------------------------------------------------------------
# UAT GROUP - MDM_MN_SWW_<vendor>_<appname>_UAT. Every token is reduced to letters and digits, so
# the group name never contains a space or a special character.
# --------------------------------------------------------------------------------------------
function Get-MigGroupToken {
    param([string]$Value)
    return [regex]::Replace("$Value", '[^A-Za-z0-9]', '')
}

function Resolve-MigUatGroupName {
    param([Parameter(Mandatory)][hashtable]$Name)
    $n = "$($script:Cfg.UatGroupNamePattern)"
    $map = @{
        '{Vendor}'   = (Get-MigGroupToken $Name.Vendor)
        '{AppName}'  = (Get-MigGroupToken $Name.AppName)
        '{Arch}'     = (Get-MigGroupToken $Name.Arch)
        '{Version}'  = (Get-MigGroupToken $Name.Version)
        '{Revision}' = (Get-MigGroupToken $Name.Revision)
        '{Lang}'     = (Get-MigGroupToken $Name.Language)
        '{FullName}' = (Get-MigGroupToken $Name.FullName)
    }
    foreach ($k in $map.Keys) { $n = $n.Replace($k, $map[$k]) }
    $n = $n -replace '_{2,}', '_'          # a missing token must not leave a double underscore
    $n = $n.Trim('_')
    return $n
}

function Get-MigEntraGroup {
    param([Parameter(Mandatory)][string]$DisplayName)
    $esc = $DisplayName -replace "'", "''"
    $r = Invoke-MigGraph GET "$($script:Cfg.GraphBase)/groups?`$filter=displayName eq '$esc'&`$select=id,displayName"
    $hits = @($r.value)
    if ($hits.Count -ge 1) { return $hits[0] }
    return $null
}

function Resolve-MigUatGroup {
    # READ ONLY. The tool never creates a group - it works out the name the application should get
    # and reports it, and looks the name up so the report can carry the object id when the group
    # happens to exist already. Returns @{ Name; Id; Exists }.
    param([Parameter(Mandatory)][hashtable]$Name)
    $gname = Resolve-MigUatGroupName -Name $Name
    if (-not $gname) {
        Write-MigLog 'No UAT group name could be built - check UatGroupNamePattern in settings.json.' Warning
        return @{ Name = ''; Id = ''; Exists = $false }
    }
    Set-MigStatus -Indeterminate -Status "Looking up the UAT group $gname..."
    $existing = $null
    try { $existing = Get-MigEntraGroup -DisplayName $gname }
    catch {
        # not fatal: the name still goes in the report, the sign-in simply cannot read groups
        Write-MigLog "UAT group '$gname': could not check whether it exists ($($_.Exception.Message)). The name is still reported." Warning
        return @{ Name = $gname; Id = ''; Exists = $false }
    }
    if ($existing) {
        Write-MigLog "UAT group '$gname' already exists ($($existing.id))." Success
        return @{ Name = $gname; Id = "$($existing.id)"; Exists = $true }
    }
    Write-MigLog "UAT group '$gname' does not exist yet - reported so it can be created afterwards." Warning
    return @{ Name = $gname; Id = ''; Exists = $false }
}

# --------------------------------------------------------------------------------------------
# ROLLBACK - remove the application this run created. Nothing else needs undoing: the tool never
# creates a group and never assigns, so the app is the only thing it can leave behind.
# --------------------------------------------------------------------------------------------
function Undo-MigApplication {
    param([Parameter(Mandatory)][hashtable]$State)
    $problems = New-Object System.Collections.Generic.List[string]
    if ($State.AppId) {
        try {
            Invoke-MigGraph DELETE "$($script:Cfg.GraphBase)/deviceAppManagement/mobileApps/$($State.AppId)" | Out-Null
            Write-MigLog "Rollback: deleted the half-created Intune app $($State.AppId)." Warning
        } catch { $problems.Add("the app $($State.AppId) could not be deleted - it may still be in the portal: $($_.Exception.Message)") }
    }
    if ($problems.Count) { return ($problems -join ' ; ') }
    return ''
}

# --------------------------------------------------------------------------------------------
# MIGRATE ONE APPLICATION. Returns a result record for the report. It never throws - a failure
# is rolled back and reported, so a batch always finishes with a full picture.
# --------------------------------------------------------------------------------------------
function Invoke-MigApplication {
    param(
        [Parameter(Mandatory)][string]$DisplayName,
        [switch]$DryRun
    )
    $started = Get-Date
    $result = [ordered]@{
        Application    = $DisplayName
        Status         = 'Failed'
        Publisher      = ''
        AppDisplayName = ''
        Version        = ''
        Revision       = ''
        Architecture   = ''
        Language       = ''
        Psadt          = ''
        AppId          = ''
        PortalUrl      = ''      # deep link straight to this app in the Intune portal
        ContentVersion = ''
        UatGroup       = ''      # the group this app needs - REPORTED ONLY, never created or assigned
        UatGroupId     = ''      # filled in only when a group of that name already exists
        UatGroupExists = $false
        Supersedes     = ''    # ids of the older versions this app was made to supersede
        IconSource     = ''
        IconDetail     = ''
        DescriptionSrc = ''
        Detection      = ''
        ContentSizeMB  = 0
        SourcePath     = ''
        IntuneWinPath  = ''
        WorkFolder     = ''
        LogPath        = ''
        DurationSec    = 0
        Message        = ''
        Warnings       = ''
    }
    # Per-application work folder + log. Two different SCCM names can sanitise to the SAME safe
    # name ("App:One" and "App|One" both become "App_One"), so a folder that is already taken gets
    # a suffix - otherwise the second application would overwrite the first one's package and log.
    $safe = Get-MigSafeName $DisplayName
    $work = Join-Path $script:RunFolder $safe
    if (Test-Path -LiteralPath $work) {
        $n = 2
        while (Test-Path -LiteralPath (Join-Path $script:RunFolder "$safe($n)")) { $n++ }
        $safe = "$safe($n)"
        $work = Join-Path $script:RunFolder $safe
    }
    New-Item -Path $work -ItemType Directory -Force | Out-Null
    $script:AppLogPath = Join-Path $work "$safe.log"
    if (-not (Test-Path -LiteralPath $script:AppLogPath)) { New-Item -Path $script:AppLogPath -ItemType File -Force | Out-Null }
    $result.WorkFolder = $work
    $result.LogPath    = $script:AppLogPath

    $state = @{ AppId = '' }
    # the operator can mark individual applications to be left alone in the review dialog
    if ($script:SkipApps -and $script:SkipApps.ContainsKey($DisplayName)) {
        $result.Status  = 'Skipped'
        $result.Message = "$($script:SkipApps[$DisplayName])"
        $result.DurationSec = [int]((Get-Date) - $started).TotalSeconds
        Write-MigLog "===== $DisplayName ===== $($result.Message)" Warning
        return $result
    }
    $warnings = New-Object System.Collections.Generic.List[string]

    try {
        Write-MigLog "===== $DisplayName =====" Step
        Set-MigStatus -Indeterminate -Status "Reading '$DisplayName' from SCCM..."

        # ---------- 1. read from SCCM ---------------------------------------------------------
        $sccm = Get-MigSccmApplication -SiteCode $script:Cfg.SiteCode -DisplayName $DisplayName
        $name = ConvertFrom-MigPackageName -FullName $sccm.DisplayName
        foreach ($w in @($name.Warnings)) { $warnings.Add($w); Write-MigLog "Package name: $w" Warning }
        $result.Publisher      = $name.Vendor
        $result.AppDisplayName = if ($name.AppName) { $name.AppName } else { $sccm.DisplayName }
        $result.Version        = $name.Version
        $result.Revision       = $name.Revision
        $result.Architecture   = $name.Arch
        $result.Language       = $name.Language
        $result.SourcePath     = $sccm.ContentPath
        if (-not $name.Vendor)  { throw "The package name '$($sccm.DisplayName)' yields no publisher - Intune requires one. Fix the name in SCCM or adjust PackageNameRegex." }
        if (-not $name.Version) { throw "The package name '$($sccm.DisplayName)' yields no version - Intune requires one. Fix the name in SCCM or adjust PackageNameRegex." }
        Write-MigLog "Parsed ($($name.ParsedBy)): publisher '$($name.Vendor)', app '$($name.AppName)', arch '$($name.Arch)', version '$($name.Version)', revision '$($name.Revision)', language '$($name.Language)'."

        if (-not $sccm.ContentPath) { throw 'The SCCM deployment type has no content location - there is nothing to package.' }
        if (-not (Test-Path -LiteralPath $sccm.ContentPath)) { throw "The content location '$($sccm.ContentPath)' is not reachable from this machine (permissions, or the share is offline)." }

        # ---------- 2. already in Intune? -----------------------------------------------------
        # The pre-flight has usually answered this already; the direct check is the fallback for
        # an unattended run. What happens next is the user's decision, taken once up front.
        if (-not $DryRun) {
            $dup = $null
            if ($script:KnownDuplicates -and $script:KnownDuplicates.ContainsKey($DisplayName)) {
                $dup = $script:KnownDuplicates[$DisplayName]
            } elseif ($script:Cfg.SkipIfAlreadyInIntune) {
                Set-MigStatus -Indeterminate -Status 'Checking whether this app is already in Intune...'
                try {
                    $e = Find-MigExistingApp -Name $name
                    if ($e) { $dup = [pscustomobject]@{ AppId = "$($e.id)"; DisplayName = "$($e.displayName)"; Created = "$($e.createdDateTime)" } }
                } catch { Write-MigLog "The duplicate check could not run ($($_.Exception.Message)) - continuing." Warning }
            }
            if ($dup) {
                if ("$($script:DuplicateAction)" -eq 'Create') {
                    $warnings.Add("a copy already exists (AppId $($dup.AppId)) - a second one was created on your instruction")
                    Write-MigLog "Already in Intune as '$($dup.DisplayName)' (AppId $($dup.AppId)), but you chose to create another copy." Warning
                } else {
                    $result.Status  = 'Skipped'
                    $result.AppId   = "$($dup.AppId)"
                    $result.PortalUrl = "$($script:Cfg.IntunePortalUrl)".Replace('{AppId}', "$($dup.AppId)")
                    $result.Message = "Skipped - the same version is already in Intune (created $($dup.Created)). Nothing was created."
                    Write-MigLog $result.Message Warning
                    $result.DurationSec = [int]((Get-Date) - $started).TotalSeconds
                    return $result
                }
            }
        }

        # ---------- 3. content size (no 30 GB abort any more) ----------------------------------
        Set-MigStatus -Indeterminate -Status 'Measuring the source content...'
        $bytes = Get-MigFolderSize -Path $sccm.ContentPath
        $gb = [math]::Round($bytes / 1GB, 2)
        $result.ContentSizeMB = [math]::Round($bytes / 1MB, 1)
        Write-MigLog "Source content: $gb GB ($($result.ContentSizeMB) MB) at $($sccm.ContentPath)"
        $maxGb = [double]$script:Cfg.MaxContentSizeGB
        if ($maxGb -gt 0 -and $gb -ge $maxGb) { throw "The content is $gb GB, above the configured MaxContentSizeGB of $maxGb." }
        # The content is copied locally, wrapped, and its encrypted payload extracted - roughly
        # 2.5x the content size on the work drive. Say so NOW rather than dying half way through a
        # copy with a raw "there is not enough space on the disk".
        $needBytes = [int64]($bytes * [double]$script:Cfg.WorkSpaceFactor)
        $free = Get-MigFreeSpace -Path $script:RunFolder
        if ($free -ge 0) {
            Write-MigLog ("Work drive: {0} GB free, about {1} GB needed for this application." -f [math]::Round($free/1GB,1), [math]::Round($needBytes/1GB,1))
            if ($free -lt $needBytes) {
                throw ("Not enough free space to package this application. {0} needs about {1} GB free on {2}, but only {3} GB is available. Free some space, or point ReportRoot in settings.json at a bigger drive." -f
                       $sccm.DisplayName, [math]::Round($needBytes/1GB,1), [IO.Path]::GetPathRoot($script:RunFolder), [math]::Round($free/1GB,1))
            }
        }
        $warnGb = [double]$script:Cfg.WarnContentSizeGB
        if ($warnGb -gt 0 -and $gb -ge $warnGb) {
            $warnings.Add("large content ($gb GB)")
            Write-MigLog "The content is $gb GB. This is uploaded in blocks with SAS renewal and resume, so it will take a while but it will not fail on size." Warning
        }

        # ---------- 4. how does this package install? -------------------------------------------
        if ("$($sccm.SccmInstall)".Trim())   { Write-MigLog "SCCM install command   : $($sccm.SccmInstall)" }
        if ("$($sccm.SccmUninstall)".Trim()) { Write-MigLog "SCCM uninstall command : $($sccm.SccmUninstall)" }
        $psadt = Resolve-MigDeployment -ContentFolder $sccm.ContentPath -SccmInstall $sccm.SccmInstall -SccmUninstall $sccm.SccmUninstall
        if (-not $psadt -or $psadt.Reason) {
            $known = (@(Get-MigLaunchers | ForEach-Object { $_.Marker }) -join ', ')
            $why = if ($psadt) { $psadt.Reason } else { 'the content could not be inspected' }
            throw "Cannot work out how to install this package: $why. Looked for these launchers: $known. Integrate it in Intune by hand, or add its launcher to 'Launchers' in settings.json."
        }
        $result.Psadt = $psadt.Generation
        Write-MigLog $psadt.Explain Success
        Write-MigLog "Wrapping folder   : $($psadt.Root)"
        Write-MigLog "Setup file        : $($psadt.SetupFile)"
        Write-MigLog "Install command   : $($psadt.InstallCmd)"
        if ("$($psadt.UninstallCmd)".Trim()) {
            Write-MigLog "Uninstall command : $($psadt.UninstallCmd)"
        } else {
            $warnings.Add('no uninstall command (SCCM has none)')
            Write-MigLog "Uninstall command : NONE - the SCCM deployment type has no uninstall command line, so the Intune app is created without one. Add it in the portal if users need to be able to uninstall." Warning
        }
        if ($psadt.Generation -eq 'Plain installer') {
            $warnings.Add('plain installer - SCCM commands reused via ServiceUI')
        }

        # ---------- 5. description --------------------------------------------------------------
        $desc = Resolve-MigDescription -SccmDescription $sccm.Description -SccmLocalizedDescription $sccm.LocalizedDesc `
                                       -ContentPath $sccm.ContentPath -Name $name
        $result.DescriptionSrc = $desc.Source
        if ($desc.Source -eq 'Generated') { $warnings.Add('description was generated (none in SCCM, none in the documents)') }

        # ---------- 6. icon ------------------------------------------------------------------------
        $icon = Resolve-MigIcon -SccmIconBase64 $sccm.IconBase64 -ContentPath $sccm.ContentPath -PackageName $name.FullName
        $result.IconSource = $icon.Source
        $result.IconDetail = $icon.Detail
        if ($icon.Source -eq 'Default') { $warnings.Add('default icon used') }
        if ($icon.Source -eq 'None')    { $warnings.Add('NO icon') }

        # ---------- 7. detection ---------------------------------------------------------------------
        $det = Get-MigDetectionRules -SiteCode $script:Cfg.SiteCode -ApplicationName $sccm.DisplayName -Name $name
        $result.Detection = $det.Summary
        if (@($det.Rules).Count -eq 0) { throw 'No detection rule could be built from SCCM and none could be synthesised - Intune would accept the app but never detect it.' }
        if ($det.Synthesised) { $warnings.Add('detection rule synthesised (SCCM had none)') }

        # ---------- 7b. the second duplicate check ---------------------------------------------------
        # The branding key check finds what THIS team migrated. This finds the same product already
        # in Intune under a different name. An application the operator already reviewed is left
        # alone - they have seen it and decided.
        if (-not $DryRun -and $script:Cfg.UninstallSignatureShield -and
            -not ($script:ReviewedApps -and $script:ReviewedApps.ContainsKey($DisplayName))) {
            $sig = Get-MigUninstallSignature -Rules $det.Rules
            if ($sig.KeyPath -or $sig.ProductCode) {
                $hits = @()
                try { $hits = @(Find-MigUninstallMatches -Sig $sig -Name $name) }
                catch { Write-MigLog "The uninstall-detection check could not run ($($_.Exception.Message)) - continuing." Warning }
                $unbranded = @($hits | Where-Object { -not $_.Branded })
                if ($unbranded.Count) {
                    $lines = @($unbranded | ForEach-Object { "$($_.Name) (AppId $($_.Id)$(if ($_.Lifecycle -and $_.Lifecycle -ne 'unknown') { ", $($_.Lifecycle)" }))" })
                    $result.Status  = 'Skipped'
                    $result.AppId   = "$(@($unbranded)[0].Id)"
                    $result.PortalUrl = "$($script:Cfg.IntunePortalUrl)".Replace('{AppId}', "$($result.AppId)")
                    $result.Message = "The same product is already in Intune under another name: $($lines -join '; '). Nothing was created - check it before migrating this one."
                    Write-MigLog $result.Message Warning
                    $result.DurationSec = [int]((Get-Date) - $started).TotalSeconds
                    $result.Warnings = ($warnings -join '; ')
                    return $result
                }
            }
        }

        # ---------- 8. build the .intunewin ------------------------------------------------------------
        # A plain installer only needs ServiceUI.exe copied in - never a toolkit exe it does not use.
        $stageOnly = if ($psadt.Generation -eq 'Plain installer') { @('ServiceUI.exe') } else { $null }
        $iw = New-MigIntuneWinPackage -SourceContent $psadt.Root -FullName $sccm.DisplayName -WorkFolder $work `
                                      -Generation $psadt.Generation -SetupFile $psadt.SetupFile `
                                      -StageUtilities:([bool]$psadt.StageUtilities) -InstallCommand $psadt.InstallCmd `
                                      -StageOnly $stageOnly
        $result.IntuneWinPath = $iw

        # The UAT group is REPORTED, never created. Working it out BEFORE the app is created means
        # the name is in the report even for an application that fails later. A dry run resolves
        # the NAME only and makes no Graph call, so "dry run" really is offline.
        $grp = if ($DryRun) { @{ Name = (Resolve-MigUatGroupName -Name $name); Id = ''; Exists = $false } }
               else         { Resolve-MigUatGroup -Name $name }
        $result.UatGroup       = $grp.Name
        $result.UatGroupId     = $grp.Id
        $result.UatGroupExists = $grp.Exists
        # No warning when the group does not exist yet: that is the normal case, and the group
        # column in the report already carries the name that needs creating.

        if ($DryRun) {
            $result.Status  = 'DryRun'
            $result.Message = "Everything was read and the .intunewin was built. Nothing was created in Intune. Package: $iw"
            Write-MigLog $result.Message Success
            $result.DurationSec = [int]((Get-Date) - $started).TotalSeconds
            $result.Warnings = ($warnings -join '; ')
            return $result
        }

        # ---------- 9. create the Win32 app ---------------------------------------------------------------
        Set-MigStatus -Percent 12 -Status "Creating the Intune app '$($result.AppDisplayName)'..."
        $body = @{
            '@odata.type'                  = '#microsoft.graph.win32LobApp'
            displayName                    = "$($result.AppDisplayName)"
            description                    = "$($desc.Text)"
            publisher                      = "$($name.Vendor)"
            displayVersion                 = "$($name.Version)"
            isFeatured                     = $false
            fileName                       = "$(Get-MigSafeName $sccm.DisplayName).intunewin"
            setupFilePath                  = $psadt.SetupFile
            installCommandLine             = $psadt.InstallCmd
            uninstallCommandLine           = $psadt.UninstallCmd
            applicableArchitectures        = "$($script:Cfg.ApplicableArchitectures)"
            minimumSupportedWindowsRelease = "$($script:Cfg.MinWindowsRelease)"
            allowAvailableUninstall        = [bool]$script:Cfg.AllowAvailableUninstall
            installExperience              = @{
                runAsAccount          = "$($script:Cfg.RunAsAccount)"
                deviceRestartBehavior = "$($script:Cfg.RestartBehavior)"
                maxRunTimeInMinutes   = [int]$sccm.MaxRuntimeMin
            }
            returnCodes                    = @($sccm.ReturnCodes)
            # @() so a SINGLE rule still serialises as a JSON array - a bare object is rejected
            # by Graph with "detectionRules ... does not match the schema".
            detectionRules                 = @($det.Rules)
            # Notes is JSON, not prose - the reporting tools read 'lifecycle' out of it, so a
            # migrated app lands in the right stage instead of showing up as 'unknown'.
            # Notes says WHO created the app and nothing else - the same one-liner the packaging
            # tool writes. Everything about the migration lives in this run's log and report, not
            # in the app record.
            notes                          = "$($script:Cfg.NotesText)"
        }
        if ($icon.Base64) { $body['largeIcon'] = @{ type = 'image/png'; value = $icon.Base64 } }

        $app = Invoke-MigGraph POST "$($script:Cfg.GraphBase)/deviceAppManagement/mobileApps" $body
        if (-not $app.id) { throw 'Creating the app returned no id.' }
        $state.AppId      = "$($app.id)"
        $result.AppId     = "$($app.id)"
        $result.PortalUrl = "$($script:Cfg.IntunePortalUrl)".Replace('{AppId}', "$($app.id)")
        Write-MigLog "Intune app created. AppId = $($app.id)" Success
        if ($result.PortalUrl) { Write-MigLog "Open in Intune: $($result.PortalUrl)" }

        # ---------- 10. upload the content ------------------------------------------------------------------
        $vid = Set-MigAppContent -AppId $state.AppId -IntuneWinPath $iw -WorkFolder $work
        $result.ContentVersion = "$vid"

        # ---------- 10b. supersede the older versions the operator picked ------------------------------------
        if ($script:SupersedeMap -and $script:SupersedeMap.ContainsKey($DisplayName)) {
            $targets = @($script:SupersedeMap[$DisplayName])
            if ($targets.Count) {
                Set-MigStatus -Percent 95 -Status 'Setting supersedence...'
                try {
                    $n = Add-MigSupersedence -NewAppId $state.AppId -OldAppIds $targets
                    $result.Supersedes = ($targets -join ' ')
                    $warnings.Add("supersedes $n older version(s)")
                } catch {
                    # the app itself is fine - supersedence is an extra relationship
                    $warnings.Add("supersedence could not be set: $($_.Exception.Message)")
                    Write-MigLog "The app was created, but supersedence could not be set: $($_.Exception.Message). Set it in the portal." Warning
                }
            }
        }

        Set-MigStatus -Percent 100 -Status "Done: $($result.AppDisplayName)"
        $result.Status  = 'Success'
        # The UAT group is REPORTED, never created and never assigned - that is done afterwards.
        $tail = if ($grp.Name) { ". UAT group: $($grp.Name)" } else { '' }
        $result.Message = "Created. AppId $($result.AppId), content version $vid$tail"
        Write-MigLog $result.Message Success
    }
    catch {
        $err = "$($_.Exception.Message)"
        Write-MigLog "FAILED: $err" Error
        try { if ($_.ScriptStackTrace) { Write-MigLog "at: $((($_.ScriptStackTrace -split "`n") | Select-Object -First 1).Trim())" } } catch {}
        $result.Status = if ("$err" -match '(?i)cancelled by the operator') { 'Cancelled' } else { 'Failed' }
        $rb = ''
        if ($state.AppId) {
            Set-MigStatus -Indeterminate -Status 'Rolling back...'
            Write-MigLog 'Rolling back everything this application created...' Warning
            $rb = Undo-MigApplication -State $state
        }
        if ($rb) {
            $result.Status  = "$($result.Status) (rollback incomplete)"
            $result.Message = "$err -- ROLLBACK INCOMPLETE, clean up by hand: $rb"
            Write-MigLog "ROLLBACK INCOMPLETE - manual cleanup needed: $rb" Error
        } else {
            $suffix = if ($state.AppId) { ' Everything this application created was rolled back; retrying is safe.' } else { ' Nothing was created.' }
            $result.Message = "$err$suffix"
            $result.AppId = ''
        }
        if ($result.IntuneWinPath) { $result.Message += " The built .intunewin was kept for a manual upload: $($result.IntuneWinPath)" }
    }
    finally {
        $script:AppLogPath = $null
    }
    $result.DurationSec = [int]((Get-Date) - $started).TotalSeconds
    $result.Warnings    = ($warnings -join '; ')
    return $result
}

# --------------------------------------------------------------------------------------------
# BATCH
# --------------------------------------------------------------------------------------------
function Initialize-MigRun {
    param([Parameter(Mandatory)][hashtable]$Cfg)
    $script:Cfg = $Cfg
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $root  = Resolve-MigPath $Cfg.ReportRoot
    $script:RunFolder   = Join-Path $root "Run_$stamp"
    New-Item -Path $script:RunFolder -ItemType Directory -Force | Out-Null
    $script:BatchLogPath = Join-Path $script:RunFolder '_Batch.log'
    New-Item -Path $script:BatchLogPath -ItemType File -Force | Out-Null
    $script:AppLogPath = $null
    return $script:RunFolder
}

function Invoke-MigBatch {
    param(
        [Parameter(Mandatory)][string[]]$Applications,
        [string]$Intent = 'available',
        [switch]$DryRun
    )
    $results = New-Object System.Collections.Generic.List[object]
    $total = @($Applications).Count
    $i = 0
    Write-MigLog "Batch start: $total application(s); profile '$($script:Cfg.ProfileName)'; site $($script:Cfg.SiteCode) on $($script:Cfg.SiteServer); tenant $($script:Cfg.TenantId)$(if ($DryRun) { '; DRY RUN - nothing will be created' })." Step
    foreach ($appName in $Applications) {
        $i++
        if (Test-MigCancelled) {
            Write-MigLog 'Cancelled - the remaining applications were not started.' Warning
            foreach ($rest in @($Applications | Select-Object -Skip ($i - 1))) {
                [void]$results.Add([pscustomobject]@{ Application = $rest; Status = 'Not started'; Message = 'The batch was cancelled before this application was reached.' })
            }
            break
        }
        if ($script:Sync) { $script:Sync.CurrentIndex = $i; $script:Sync.CurrentTotal = $total; $script:Sync.CurrentApp = $appName }
        Write-MigLog "--- ($i of $total) $appName ---" Step
        $r = Invoke-MigApplication -DisplayName $appName -DryRun:$DryRun
        [void]$results.Add([pscustomobject]$r)
        # $null -ne again: an empty Results list is falsy, and it is empty for the FIRST result -
        # a plain truthiness test would drop it and the window's summary would be short by one.
        if (($null -ne $script:Sync) -and ($null -ne $script:Sync.Results)) { try { [void]$script:Sync.Results.Add([pscustomobject]$r) } catch {} }

        if ($r.Status -like 'Failed*' -and "$($script:Cfg.RollbackScope)" -eq 'FailedAppAndStop') {
            Write-MigLog "RollbackScope is FailedAppAndStop - the batch stops here." Warning
            foreach ($rest in @($Applications | Select-Object -Skip $i)) {
                [void]$results.Add([pscustomobject]@{ Application = $rest; Status = 'Not started'; Message = 'The batch stopped after an earlier failure (RollbackScope = FailedAppAndStop).' })
            }
            break
        }
        if ($r.Status -like 'Failed*' -and "$($script:Cfg.RollbackScope)" -eq 'WholeBatch') {
            Write-MigLog 'RollbackScope is WholeBatch - removing every application this run created...' Warning
            foreach ($done in @($results | Where-Object { $_.Status -eq 'Success' })) {
                $undo = @{ AppId = "$($done.AppId)" }
                $prob = Undo-MigApplication -State $undo
                $done.Status  = if ($prob) { 'Rolled back (incomplete)' } else { 'Rolled back' }
                $done.Message = if ($prob) { "Removed because a later application failed. MANUAL CLEANUP: $prob" } else { 'Removed because a later application failed (RollbackScope = WholeBatch).' }
            }
            foreach ($rest in @($Applications | Select-Object -Skip $i)) {
                [void]$results.Add([pscustomobject]@{ Application = $rest; Status = 'Not started'; Message = 'The batch was rolled back after an earlier failure.' })
            }
            break
        }
    }
    Write-MigLog "Batch finished: $(@($results | Where-Object { $_.Status -eq 'Success' }).Count) succeeded, $(@($results | Where-Object { $_.Status -like 'Failed*' }).Count) failed, $(@($results | Where-Object { $_.Status -eq 'Skipped' }).Count) skipped." Step
    return $results.ToArray()
}

# --------------------------------------------------------------------------------------------
# REPORTS - HTML (to read), CSV (to filter) and JSON (to feed another tool). All three carry the
# App ID and the UAT group, which is what the hand-over needs.
# --------------------------------------------------------------------------------------------
function ConvertTo-MigHtmlText { param([string]$Text) return [System.Net.WebUtility]::HtmlEncode("$Text") }

# The report is for reading, so each row gets ONE short note - the thing that needs acting on.
# Everything verbose (publisher, revision, detection rules, icon detail, full messages) stays in
# the CSV and JSON alongside it, and in the per-application log.
function Get-MigShortNote {
    param($Row)
    $st = "$($Row.Status)"
    if ($st -eq 'Success') {
        if ("$($Row.Warnings)") { return (Get-MigTrim $Row.Warnings 140) }
        return ''
    }
    # A skip is never just "already in Intune" - say WHICH situation it was, so the report can be
    # acted on without opening a log.
    if ($st -eq 'Skipped') { return (Get-MigTrim $Row.Message 260) }
    if ($st -eq 'DryRun')  { return 'built, nothing created' }
    return (Get-MigTrim $Row.Message 260)
}
function Get-MigTrim {
    param([string]$Text, [int]$Max = 200)
    $s = ("$Text" -replace '\s+', ' ').Trim()
    if ($s.Length -gt $Max) { $s = $s.Substring(0, $Max).TrimEnd() + '...' }
    return $s
}
# 'Document: Installation instructions.docx (short+detailed)' -> 'Document'
function Get-MigShortSource {
    param([string]$Source)
    $s = "$Source"
    if ($s -match '^\s*Document') { return 'Document' }
    return $s
}

function Write-MigReports {
    param([Parameter(Mandatory)]$Results, [Parameter(Mandatory)][string]$RunFolder)
    # Most actionable first: failures, then skips, then the rest.
    $rows = @($Results | Sort-Object @{ Expression = {
        switch -Regex ("$($_.Status)") { '^Failed' { 0 } '^Rolled' { 1 } '^Skipped$' { 2 } '^Not started$' { 4 } default { 3 } } } }, Application)
    $html = Join-Path $RunFolder 'MigrationReport.html'


    $ok      = @($rows | Where-Object { $_.Status -eq 'Success' }).Count
    $failed  = @($rows | Where-Object { "$($_.Status)" -like 'Failed*' }).Count
    $skipped = @($rows | Where-Object { $_.Status -eq 'Skipped' }).Count
    $other   = $rows.Count - $ok - $failed - $skipped

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine(@"
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>SCCM to Intune migration report</title>
<style>
 body   { font-family: Segoe UI, sans-serif; background:#f4f5f7; color:#222; margin:0; padding:24px; }
 h1     { font-size:22px; margin:0 0 4px 0; }
 .sub   { color:#666; font-size:13px; margin-bottom:18px; }
 .cards { display:flex; gap:12px; margin-bottom:20px; flex-wrap:wrap; }
 .card  { background:#fff; border-radius:6px; padding:14px 20px; box-shadow:0 1px 4px rgba(0,0,0,.12); min-width:110px; }
 .card .n { font-size:26px; font-weight:600; } .card .l { font-size:12px; color:#666; text-transform:uppercase; letter-spacing:.5px; }
 .ok .n { color:#1c7c2e; } .bad .n { color:#c62828; } .warn .n { color:#b26a00; } .neutral .n { color:#37474f; }
 table  { border-collapse:collapse; width:100%; background:#fff; box-shadow:0 1px 4px rgba(0,0,0,.12); font-size:13px; }
 thead tr { background:#20232a; color:#fff; text-align:left; }
 th, td { padding:9px 12px; vertical-align:top; border-bottom:1px solid #e6e6e6; }
 tbody tr:hover { background:#fafbfc; }
 .s-Success  { color:#1c7c2e; font-weight:600; }
 .s-Failed   { color:#c62828; font-weight:600; }
 .s-Skipped  { color:#b26a00; font-weight:600; }
 .s-Other    { color:#37474f; font-weight:600; }
 code   { background:#eef0f3; padding:1px 5px; border-radius:3px; font-size:12px; }
 .muted { color:#777; font-size:12px; }
 .wrap  { max-width:520px; word-break:break-word; }
</style></head><body>
<h1>SCCM to Intune migration report</h1>
<div class="sub">$(ConvertTo-MigHtmlText (Get-Date -Format 'dddd, dd MMMM yyyy HH:mm')) &nbsp;&middot;&nbsp;
 profile <b>$(ConvertTo-MigHtmlText $script:Cfg.ProfileName)</b> &nbsp;&middot;&nbsp;
 site <b>$(ConvertTo-MigHtmlText $script:Cfg.SiteCode)</b> on $(ConvertTo-MigHtmlText $script:Cfg.SiteServer) &nbsp;&middot;&nbsp;
 tenant <b>$(ConvertTo-MigHtmlText $script:Cfg.TenantId)</b> &nbsp;&middot;&nbsp;
 run by $(ConvertTo-MigHtmlText $env:USERNAME)</div>
<div class="cards">
 <div class="card ok"><div class="n">$ok</div><div class="l">Migrated</div></div>
 <div class="card bad"><div class="n">$failed</div><div class="l">Failed</div></div>
 <div class="card warn"><div class="n">$skipped</div><div class="l">Skipped</div></div>
 <div class="card neutral"><div class="n">$other</div><div class="l">Other</div></div>
</div>
<table><thead><tr>
 <th>Application</th><th>Status</th><th>Intune app</th><th>UAT group</th>
 <th>Install</th><th>Icon</th><th>Description</th><th>Size</th><th>Note</th>
</tr></thead><tbody>
"@)
    foreach ($r in $rows) {
        $st = "$($r.Status)"
        $cls = if ($st -eq 'Success') { 's-Success' } elseif ($st -like 'Failed*') { 's-Failed' } elseif ($st -eq 'Skipped') { 's-Skipped' } else { 's-Other' }
        $grp = if ("$($r.UatGroup)") { ConvertTo-MigHtmlText $r.UatGroup } else { '<span class="muted">-</span>' }
        $appid = if ("$($r.AppId)") {
            $code = "<code>$(ConvertTo-MigHtmlText $r.AppId)</code>"
            if ("$($r.PortalUrl)") { "$code<br><a href='$(ConvertTo-MigHtmlText $r.PortalUrl)' target='_blank'>open in Intune &#8599;</a>" } else { $code }
        } else { '<span class="muted">-</span>' }
        $logLink = if ("$($r.LogPath)" -and (Test-Path -LiteralPath "$($r.LogPath)")) { "<br><a class='muted' href='$([uri]::EscapeUriString("file:///$($r.LogPath -replace '\\','/')"))'>log</a>" } else { '' }
        [void]$sb.AppendLine(@"
<tr>
 <td><b>$(ConvertTo-MigHtmlText $r.Application)</b>$logLink</td>
 <td class="$cls">$(ConvertTo-MigHtmlText $st)</td>
 <td>$appid</td>
 <td>$grp</td>
 <td>$(ConvertTo-MigHtmlText $r.Psadt)</td>
 <td>$(ConvertTo-MigHtmlText $r.IconSource)</td>
 <td>$(ConvertTo-MigHtmlText (Get-MigShortSource $r.DescriptionSrc))</td>
 <td>$(if ($r.ContentSizeMB) { "$([math]::Round([double]$r.ContentSizeMB / 1024, 2)) GB" } else { '-' })</td>
 <td class="wrap">$(ConvertTo-MigHtmlText (Get-MigShortNote $r))</td>
</tr>
"@)
    }
    [void]$sb.AppendLine(@"
</tbody></table>
<p class="muted">Everything this run produced - staged content, .intunewin packages and per-application logs - is kept under
 $(ConvertTo-MigHtmlText $RunFolder), so a failed application can be inspected and retried without re-reading SCCM.</p>
</body></html>
"@)
    try { Set-Content -LiteralPath $html -Value $sb.ToString() -Encoding UTF8 } catch { Write-MigLog "The HTML report could not be written: $($_.Exception.Message)" Warning }
    Write-MigLog "Reports written: $html" Success
    return @{ Html = $html }
}

# --------------------------------------------------------------------------------------------
# Worker entry point - called inside the background runspace by the window, and directly by the
# unattended (-NoGui) path.
# --------------------------------------------------------------------------------------------
function Start-MigWorker {
    param([Parameter(Mandatory)]$Sync)
    $script:Sync = $Sync
    $script:Cfg  = $Sync.Cfg
    $script:Auth = "$($Sync.AuthHeader)"
    $script:RunFolder    = $Sync.RunFolder
    $script:BatchLogPath = $Sync.BatchLogPath
    $script:AppLogPath   = $null
    # what the user answered to the "already in Intune" question, and what the pre-flight found
    $script:DuplicateAction = "$($Sync.DuplicateAction)"
    $script:KnownDuplicates = $Sync.KnownDuplicates
    $script:SupersedeMap    = $Sync.SupersedeMap
    $script:SkipApps        = $Sync.SkipApps
    $script:ReviewedApps    = $Sync.ReviewedApps
    Clear-MigAppListCache
    try {
        Connect-MigSccm -SiteCode $script:Cfg.SiteCode -SiteServer $script:Cfg.SiteServer | Out-Null
        $res = Invoke-MigBatch -Applications @($Sync.Queue) -DryRun:([bool]$Sync.DryRun)
        $Sync.Report = Write-MigReports -Results $res -RunFolder $script:RunFolder
        $Sync.Final  = $res
    } catch {
        Write-MigLog "The batch stopped with an unhandled error: $($_.Exception.Message)" Error
        $Sync.FatalError = "$($_.Exception.Message)"
        try { $Sync.Report = Write-MigReports -Results @($Sync.Results) -RunFolder $script:RunFolder } catch {}
    } finally {
        $Sync.Running = $false
        Set-MigStatus -Percent 100 -Status 'Finished.'
    }
}

}   # ---- end of $Engine ------------------------------------------------------------------------

##############################################################################################
# endregion
# region RUN
##############################################################################################
. $Engine     # the engine functions are now available in THIS runspace too

$script:Cfg = Import-MigratorSettings -Path $SettingsPath -ProfileName $ProfileName

# --------------------------------------------------------------------------------------------
# Unattended path (-NoGui). Same engine, no window.
# --------------------------------------------------------------------------------------------
if ($NoGui) {
    $missing = Test-MigratorSettings -Cfg $script:Cfg
    if ($missing.Count) { throw "settings.json profile '$($script:Cfg.ProfileName)' is missing: $($missing -join ', ')" }
    if (-not $Application -or @($Application).Count -eq 0) { throw 'Give -Application <name> [,<name>] (or drop -NoGui to use the window).' }
    $run = Initialize-MigRun -Cfg $script:Cfg
    Write-MigLog "Unattended run. Profile '$($script:Cfg.ProfileName)'. Output folder: $run" Step
    $script:Auth = Connect-MigIntune -TenantId $script:Cfg.TenantId
    Connect-MigSccm -SiteCode $script:Cfg.SiteCode -SiteServer $script:Cfg.SiteServer | Out-Null
    $results = Invoke-MigBatch -Applications @($Application) -DryRun:$WhatIfMigration
    $rep = Write-MigReports -Results $results -RunFolder $run
    $results | Format-Table Application, Status, AppId, UatGroup -AutoSize
    Write-Host "`nReport: $($rep.Html)" -ForegroundColor Cyan
    return
}

##############################################################################################
# WINDOW
##############################################################################################
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing

# One row in the grid. A real class with INotifyPropertyChanged, so the tick box is genuinely
# two-way and the Status/Detail cells update themselves the moment the worker reports a result -
# no grid rebuild, no lost selection, no flicker.
if (-not ('MigAppRow' -as [type])) {
    Add-Type -TypeDefinition @'
using System.ComponentModel;
public class MigAppRow : INotifyPropertyChanged {
    public event PropertyChangedEventHandler PropertyChanged;
    private void N(string p) { var h = PropertyChanged; if (h != null) h(this, new PropertyChangedEventArgs(p)); }
    private bool _selected;      public bool   Selected { get { return _selected; } set { _selected = value; N("Selected"); } }
    private string _name = "";   public string Name     { get { return _name; }     set { _name = value;     N("Name"); } }
    private string _version = "";public string Version  { get { return _version; }  set { _version = value;  N("Version"); } }
    private string _created = "";public string Created  { get { return _created; }  set { _created = value;  N("Created"); } }
    private string _status = ""; public string Status   { get { return _status; }   set { _status = value;   N("Status"); } }
    private string _detail = ""; public string Detail   { get { return _detail; }   set { _detail = value;   N("Detail"); } }
    private string _url = "";    public string PortalUrl{ get { return _url; }      set { _url = value;      N("PortalUrl"); } }
}

public class MigReviewRow : INotifyPropertyChanged {
    public event PropertyChangedEventHandler PropertyChanged;
    private void N(string p) { var h = PropertyChanged; if (h != null) h(this, new PropertyChangedEventArgs(p)); }
    public string Application  { get; set; }
    public string NewVersion   { get; set; }
    public string Found        { get; set; }
    public string Relation     { get; set; }
    public string Lifecycle    { get; set; }
    private string _action = ""; public string Action { get { return _action; } set { _action = value; N("Action"); } }
    public string[] Actions    { get; set; }
    public string SupersedeIds { get; set; }
}
'@ -ErrorAction Stop
}

$xamlText = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="SCCM to Intune migration" Height="760" Width="1220"
        WindowStartupLocation="CenterScreen" Background="#F2F3F5"
        FontFamily="Segoe UI" FontSize="12">
  <Window.Resources>
    <!-- flat, quiet buttons; one accented primary action -->
    <Style x:Key="Flat" TargetType="Button">
      <Setter Property="Background" Value="#FFFFFF"/>
      <Setter Property="Foreground" Value="#22262B"/>
      <Setter Property="BorderBrush" Value="#CFD4DA"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="14,6"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="4" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#EDEFF2"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource Flat}">
      <Setter Property="Background" Value="#0F6CBD"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="BorderBrush" Value="#0F6CBD"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="22,7"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="4" Background="{TemplateBinding Background}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#115EA3"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Background" Value="#9BB8D3"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="White"/>
      <Setter Property="CornerRadius" Value="6"/>
      <Setter Property="BorderBrush" Value="#E1E4E8"/>
      <Setter Property="BorderThickness" Value="1"/>
    </Style>
    <Style x:Key="Field" TargetType="TextBox">
      <Setter Property="Height" Value="28"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="Padding" Value="6,0"/>
      <Setter Property="BorderBrush" Value="#CFD4DA"/>
    </Style>
    <Style x:Key="Cap" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#6A737D"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="Margin" Value="0,0,0,3"/>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>   <!-- header -->
      <RowDefinition Height="Auto"/>   <!-- connection -->
      <RowDefinition Height="*"/>      <!-- grid -->
      <RowDefinition Height="Auto"/>   <!-- log -->
      <RowDefinition Height="Auto"/>   <!-- footer -->
    </Grid.RowDefinitions>

    <!-- ============================ header ============================ -->
    <Border Grid.Row="0" Background="#1F2937" Padding="18,12">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0">
          <TextBlock Text="SCCM to Intune migration" Foreground="White" FontSize="17" FontWeight="SemiBold"/>
          <TextBlock Name="LblSub" Foreground="#9CA3AF" FontSize="11" Margin="0,2,0,0"/>
        </StackPanel>
        <StackPanel Grid.Column="1" Margin="0,0,14,0" VerticalAlignment="Center">
          <TextBlock Text="PROFILE" Foreground="#9CA3AF" FontSize="9" Margin="0,0,0,3"/>
          <ComboBox Name="CbProfile" Width="170" Height="26"/>
        </StackPanel>
        <Border Grid.Column="2" Name="Pill" CornerRadius="11" Background="#374151" Padding="12,5" VerticalAlignment="Center">
          <TextBlock Name="LblConn" Text="Not connected" Foreground="#E5E7EB" FontSize="11" FontWeight="SemiBold"/>
        </Border>
      </Grid>
    </Border>

    <!-- ============================ connection ============================ -->
    <Border Grid.Row="1" Name="ConnPanel" Style="{StaticResource Card}" Margin="14,12,14,0" Padding="14,10">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="2*"/><ColumnDefinition Width="12"/>
          <ColumnDefinition Width="*"/><ColumnDefinition Width="12"/>
          <ColumnDefinition Width="1.4*"/><ColumnDefinition Width="16"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0">
          <TextBlock Text="SCCM site server" Style="{StaticResource Cap}"/>
          <TextBox Name="TxtServer" Style="{StaticResource Field}"/>
        </StackPanel>
        <StackPanel Grid.Column="2">
          <TextBlock Text="Site code" Style="{StaticResource Cap}"/>
          <TextBox Name="TxtSite" Style="{StaticResource Field}"/>
        </StackPanel>
        <StackPanel Grid.Column="4">
          <TextBlock Text="Intune tenant" Style="{StaticResource Cap}"/>
          <TextBox Name="TxtTenant" Style="{StaticResource Field}"/>
        </StackPanel>
        <Button Grid.Column="6" Name="BtnConnect" Content="Connect" Style="{StaticResource Primary}"
                VerticalAlignment="Bottom" Height="28"/>
      </Grid>
    </Border>

    <!-- ============================ applications ============================ -->
    <Border Grid.Row="2" Style="{StaticResource Card}" Margin="14,12,14,0" Padding="0">
      <Grid>
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>

        <Grid Grid.Row="0" Margin="14,12,14,10">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <TextBlock Grid.Column="0" Text="Filter" VerticalAlignment="Center" Margin="0,0,8,0" Foreground="#6A737D"/>
          <Grid Grid.Column="1" HorizontalAlignment="Left" Width="330">
            <TextBox Name="TxtSearch" Style="{StaticResource Field}"
                     ToolTip="Type part of an application name to narrow the list. Ticks are kept while you filter."/>
            <!-- placeholder: hidden as soon as anything is typed -->
            <TextBlock Name="LblSearchHint" Text="part of an application name..." IsHitTestVisible="False"
                       VerticalAlignment="Center" Margin="8,0,0,0" Foreground="#A8AEB5" FontStyle="Italic"/>
          </Grid>
          <TextBlock Grid.Column="2" Name="LblCount" VerticalAlignment="Center" Margin="16,0,14,0" Foreground="#6A737D"/>
          <Button Grid.Column="4" Name="BtnSelectNone" Content="Clear ticks"    Style="{StaticResource Flat}" Height="28"/>
        </Grid>

        <DataGrid Grid.Row="1" Name="GridApps" AutoGenerateColumns="False" CanUserAddRows="False"
                  HeadersVisibility="Column" RowHeaderWidth="0" BorderThickness="0"
                  GridLinesVisibility="Horizontal" HorizontalGridLinesBrush="#EEF0F2"
                  SelectionMode="Single" RowHeight="26" AlternatingRowBackground="#FAFBFC">
          <DataGrid.ColumnHeaderStyle>
            <Style TargetType="DataGridColumnHeader">
              <Setter Property="Background" Value="#F6F7F9"/>
              <Setter Property="Foreground" Value="#454B52"/>
              <Setter Property="FontWeight" Value="SemiBold"/>
              <Setter Property="Padding" Value="8,6"/>
              <Setter Property="BorderBrush" Value="#E1E4E8"/>
              <Setter Property="BorderThickness" Value="0,0,0,1"/>
            </Style>
          </DataGrid.ColumnHeaderStyle>
          <DataGrid.Columns>
            <DataGridCheckBoxColumn Width="42" Binding="{Binding Selected, UpdateSourceTrigger=PropertyChanged}">
              <DataGridCheckBoxColumn.HeaderTemplate>
                <DataTemplate><TextBlock Text="" ToolTip="Tick the applications to migrate"/></DataTemplate>
              </DataGridCheckBoxColumn.HeaderTemplate>
              <DataGridCheckBoxColumn.ElementStyle>
                <Style TargetType="CheckBox">
                  <Setter Property="HorizontalAlignment" Value="Center"/>
                  <Setter Property="VerticalAlignment" Value="Center"/>
                </Style>
              </DataGridCheckBoxColumn.ElementStyle>
              <DataGridCheckBoxColumn.EditingElementStyle>
                <Style TargetType="CheckBox">
                  <Setter Property="HorizontalAlignment" Value="Center"/>
                  <Setter Property="VerticalAlignment" Value="Center"/>
                </Style>
              </DataGridCheckBoxColumn.EditingElementStyle>
            </DataGridCheckBoxColumn>
            <DataGridTextColumn Header="Application" Binding="{Binding Name}" Width="2.4*" IsReadOnly="True"/>
            <DataGridTextColumn Header="Version" Binding="{Binding Version}" Width="110" IsReadOnly="True"/>
            <DataGridTextColumn Header="Created" Binding="{Binding Created}" Width="110" IsReadOnly="True"/>
            <DataGridTextColumn Header="Status" Binding="{Binding Status}" Width="120" IsReadOnly="True">
              <DataGridTextColumn.ElementStyle>
                <Style TargetType="TextBlock">
                  <Setter Property="FontWeight" Value="SemiBold"/>
                  <Setter Property="VerticalAlignment" Value="Center"/>
                  <Style.Triggers>
                    <DataTrigger Binding="{Binding Status}" Value="Migrated"><Setter Property="Foreground" Value="#1A7F37"/></DataTrigger>
                    <DataTrigger Binding="{Binding Status}" Value="Failed"><Setter Property="Foreground" Value="#C62828"/></DataTrigger>
                    <DataTrigger Binding="{Binding Status}" Value="Skipped"><Setter Property="Foreground" Value="#B26A00"/></DataTrigger>
                    <DataTrigger Binding="{Binding Status}" Value="Working..."><Setter Property="Foreground" Value="#0F6CBD"/></DataTrigger>
                    <DataTrigger Binding="{Binding Status}" Value="Built (dry run)"><Setter Property="Foreground" Value="#0F6CBD"/></DataTrigger>
                  </Style.Triggers>
                </Style>
              </DataGridTextColumn.ElementStyle>
            </DataGridTextColumn>
            <DataGridTextColumn Header="Result" Binding="{Binding Detail}" Width="2.6*" IsReadOnly="True"
                                ClipboardContentBinding="{Binding Detail}">
              <DataGridTextColumn.ElementStyle>
                <Style TargetType="TextBlock">
                  <Setter Property="Foreground" Value="#6A737D"/>
                  <Setter Property="VerticalAlignment" Value="Center"/>
                  <Setter Property="TextTrimming" Value="CharacterEllipsis"/>
                  <Setter Property="ToolTip" Value="{Binding Detail}"/>
                </Style>
              </DataGridTextColumn.ElementStyle>
            </DataGridTextColumn>
          </DataGrid.Columns>
        </DataGrid>

        <!-- what the empty list says for itself -->
        <StackPanel Grid.Row="1" Name="EmptyHint" VerticalAlignment="Center" HorizontalAlignment="Center" IsHitTestVisible="False">
          <TextBlock Name="LblEmpty1" Text="No applications loaded" FontSize="15" Foreground="#8A9199" HorizontalAlignment="Center"/>
          <TextBlock Name="LblEmpty2" Text="Check the connection details above and press Connect." FontSize="11.5"
                     Foreground="#A8AEB5" Margin="0,6,0,0" HorizontalAlignment="Center"/>
        </StackPanel>
      </Grid>
    </Border>

    <!-- ============================ log ============================ -->
    <Expander Grid.Row="3" Name="ExpLog" Header="Activity log" Margin="14,10,14,0" Foreground="#454B52" IsExpanded="False">
      <Border Style="{StaticResource Card}" Margin="0,6,0,0">
        <TextBox Name="TxtLog" Height="170" IsReadOnly="True" BorderThickness="0" Padding="8"
                 TextWrapping="NoWrap" FontFamily="Consolas" FontSize="11"
                 Background="#1E1E1E" Foreground="#D4D4D4"
                 VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
      </Border>
    </Expander>

    <!-- ============================ footer ============================ -->
    <Border Grid.Row="4" Background="White" BorderBrush="#E1E4E8" BorderThickness="0,1,0,0" Padding="14,10" Margin="0,12,0,0">
      <Grid>
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <Grid Grid.Row="0" Margin="0,0,0,8">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <ProgressBar Grid.Column="0" Name="Bar" Height="6" Minimum="0" Maximum="100"
                       Background="#EDEFF2" Foreground="#0F6CBD" BorderThickness="0"/>
          <TextBlock Grid.Column="1" Name="LblStatus" Margin="14,0,0,0" VerticalAlignment="Center"
                     Foreground="#454B52" FontSize="11"/>
        </Grid>
        <Grid Grid.Row="1">
          <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <CheckBox Grid.Column="0" Name="ChkDryRun" VerticalAlignment="Center" Content="Dry run - build only, create nothing in Intune"
                    Foreground="#454B52"/>
          <TextBlock Grid.Column="1" Name="LblRunFolder" VerticalAlignment="Center" Margin="18,0,0,0"
                     Foreground="#8A9199" FontSize="11" TextTrimming="CharacterEllipsis"/>
          <StackPanel Grid.Column="2" Orientation="Horizontal">
            <Button Name="BtnOpenReport" Content="Open report" Style="{StaticResource Flat}" Height="30" Margin="0,0,8,0" IsEnabled="False"/>
            <Button Name="BtnCancel"     Content="Cancel"      Style="{StaticResource Flat}" Height="30" Margin="0,0,8,0" IsEnabled="False"/>
            <Button Name="BtnMigrate"    Content="Migrate"     Style="{StaticResource Primary}" Height="30" IsEnabled="False"/>
          </StackPanel>
        </Grid>
      </Grid>
    </Border>

    <!-- ============================ busy overlay ============================ -->
    <Border Name="Overlay" Grid.Row="0" Grid.RowSpan="5" Background="#B0202634" Visibility="Collapsed">
      <Border Background="White" CornerRadius="8" Padding="30,24" Width="420"
              VerticalAlignment="Center" HorizontalAlignment="Center">
        <StackPanel>
          <TextBlock Name="LblBusy" Text="Connecting..." FontSize="15" FontWeight="SemiBold"
                     Foreground="#22262B" HorizontalAlignment="Center"/>
          <TextBlock Name="LblBusySub" Text="" FontSize="11.5" Foreground="#6A737D"
                     HorizontalAlignment="Center" Margin="0,7,0,0" TextWrapping="Wrap" TextAlignment="Center"/>
          <ProgressBar IsIndeterminate="True" Height="4" Margin="0,20,0,0"
                       Background="#EDEFF2" Foreground="#0F6CBD" BorderThickness="0"/>
        </StackPanel>
      </Border>
    </Border>
  </Grid>
</Window>
'@

[xml]$xaml = $xamlText
$reader = New-Object System.Xml.XmlNodeReader $xaml
$Win = [Windows.Markup.XamlReader]::Load($reader)

# Every control in one hashtable, and everything else in $State. The handlers further down are
# PLAIN scriptblocks - deliberately NOT .GetNewClosure(). A closure runs in its own module scope:
# it sees captured VARIABLES but not the script's own FUNCTIONS, so a handler calling
# Connect-MigIntune / Add-UiLog would die on the click with "the term is not recognized".
$UI = @{}
foreach ($n in 'LblSub','CbProfile','Pill','LblConn','ConnPanel','TxtServer','TxtSite','TxtTenant','BtnConnect',
               'TxtSearch','LblSearchHint','LblCount','BtnSelectNone','GridApps',
               'EmptyHint','LblEmpty1','LblEmpty2','ExpLog','TxtLog','Overlay','LblBusy','LblBusySub',
               'Bar','LblStatus','ChkDryRun','LblRunFolder','BtnOpenReport','BtnCancel','BtnMigrate') {
    $UI[$n] = $Win.FindName($n)
}

$Sync = [hashtable]::Synchronized(@{
    Window   = $Win; Cfg = $script:Cfg
    LogQueue = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
    Results  = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
    Status = ''; Percent = 0; Indeterminate = $false
    Running = $false; CancelRequested = $false; ReauthRequested = $false
    AuthHeader = ''; Queue = @(); DryRun = $false
    RunFolder = ''; BatchLogPath = ''; Report = $null; FatalError = ''
    ConnectState = 'idle'; ConnectApps = $null; ConnectError = ''
    PreflightState = 'idle'; PreflightResult = $null; PreflightError = ''; PendingSelected = @()
    SkipApps = @{}; SupersedeMap = @{}; KnownDuplicates = @{}; DuplicateAction = 'Skip'; ReviewedApps = @{}
    CurrentIndex = 0; CurrentTotal = 0; CurrentApp = ''
})
$State = @{
    UI = $UI; Sync = $Sync; Connected = $false
    Rows = New-Object System.Collections.ObjectModel.ObservableCollection[MigAppRow]
    View = $null; RowByName = @{}; Worker = $null; Handle = $null
    ConnectWorker = $null; ConnectHandle = $null
    PreflightWorker = $null; PreflightHandle = $null
    ReportPath = ''; SeenResults = 0; EngineText = $Engine.ToString()
}
# The engine logs through $script:Sync - point it at the same hashtable so the work the UI thread
# does itself (sign-in, SCCM connect, reading the list) also lands in the activity log.
$script:Sync = $Sync

function Add-UiLog {
    param([string]$Text, [string]$Level = 'Info')
    $box = $State.UI.TxtLog
    $box.AppendText("$Text`r`n")
    if ($box.Text.Length -gt 400000) { $box.Text = $box.Text.Substring($box.Text.Length - 300000) }
    $box.ScrollToEnd()
}

function Show-UiBusy {
    # A blocking-looking overlay with an animated bar. The bar only really animates while the UI
    # thread is free, which is why the slow part of connecting is pushed to a runspace below.
    param([string]$Title, [string]$Detail = '')
    $State.UI.LblBusy.Text = $Title
    $State.UI.LblBusySub.Text = $Detail
    $State.UI.Overlay.Visibility = 'Visible'
    # Force one render pass so the overlay is actually on screen before anything blocks.
    # Priority FIRST here too - the (Delegate, params object[]) overload would pass the priority
    # to the action as an argument and throw "Parameter count mismatch".
    $State.UI.Overlay.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [action]{})
}
function Hide-UiBusy { $State.UI.Overlay.Visibility = 'Collapsed' }

function Set-UiConnected {
    param([string]$Text, [string]$Colour)
    $State.UI.LblConn.Text = $Text
    $State.UI.Pill.Background = (New-Object System.Windows.Media.SolidColorBrush(
        [System.Windows.Media.ColorConverter]::ConvertFromString($Colour)))
}

function Update-UiCount {
    $total = $State.Rows.Count
    $shown = 0
    foreach ($r in $State.Rows) { if (-not $State.View -or $State.View.Filter -eq $null -or $State.View.Filter.Invoke($r)) { $shown++ } }
    $ticked = @($State.Rows | Where-Object { $_.Selected }).Count
    $State.UI.LblCount.Text = if ($shown -eq $total) { "$total applications  -  $ticked ticked" }
                              else { "$shown of $total shown  -  $ticked ticked" }
    # an empty grid explains itself instead of showing a blank slab
    if ($State.UI.EmptyHint) {
        if ($shown -gt 0) { $State.UI.EmptyHint.Visibility = 'Collapsed' }
        else {
            $State.UI.EmptyHint.Visibility = 'Visible'
            if ($total -gt 0) {
                $State.UI.LblEmpty1.Text = 'Nothing matches the filter'
                $State.UI.LblEmpty2.Text = "None of the $total applications matches what you typed."
            } elseif ($State.Connected) {
                $State.UI.LblEmpty1.Text = 'This site has no applications'
                $State.UI.LblEmpty2.Text = 'SCCM returned an empty application list.'
            } else {
                $State.UI.LblEmpty1.Text = 'No applications loaded'
                $State.UI.LblEmpty2.Text = 'Check the connection details above and press Connect.'
            }
        }
    }
}

function Set-UiBusy {
    param([bool]$Busy)
    $State.UI.BtnMigrate.IsEnabled  = (-not $Busy) -and $State.Connected
    $State.UI.BtnConnect.IsEnabled  = -not $Busy
    $State.UI.BtnCancel.IsEnabled   = $Busy
    $State.UI.CbProfile.IsEnabled   = -not $Busy
    $State.UI.ChkDryRun.IsEnabled   = -not $Busy
    $State.UI.BtnSelectNone.IsEnabled = -not $Busy
}

# --- profile list ------------------------------------------------------------------------------
$profileNames = @(Get-MigratorProfileNames)
if ($profileNames.Count) {
    $UI.CbProfile.ItemsSource = $profileNames
    $sel = if ($script:Cfg.ProfileName -and ($profileNames -contains $script:Cfg.ProfileName)) { $script:Cfg.ProfileName } else { $profileNames[0] }
    $UI.CbProfile.SelectedItem = $sel
} else {
    $UI.CbProfile.ItemsSource = @('(none in settings.json)')
    $UI.CbProfile.SelectedIndex = 0
    $UI.CbProfile.IsEnabled = $false
}

function Sync-UiFromConfig {
    $UI.TxtServer.Text = "$($script:Cfg.SiteServer)"
    $UI.TxtSite.Text   = "$($script:Cfg.SiteCode)"
    $UI.TxtTenant.Text = "$($script:Cfg.TenantId)"
    $UI.ChkDryRun.IsChecked = $false
    $grp = if ("$($script:Cfg.UatGroupNamePattern)".Trim()) { "UAT group naming: $($script:Cfg.UatGroupNamePattern)" } else { 'No UAT group pattern configured' }
    $UI.LblSub.Text = "$grp   -   UAT groups are REPORTED only: never created, never assigned"
}
Sync-UiFromConfig

# --- the grid's view: filtering never touches the ticks, because the tick lives on the row -------
$State.View = [System.Windows.Data.CollectionViewSource]::GetDefaultView($State.Rows)
$State.View.Filter = [Predicate[object]]{
    param($item)
    $q = "$($State.UI.TxtSearch.Text)".Trim()
    if (-not $q) { return $true }
    return ("$($item.Name)" -like "*$q*")
}
$UI.GridApps.ItemsSource = $State.View

# ================================ handlers ======================================================
$UI.CbProfile.Add_SelectionChanged({
    $p = "$($State.UI.CbProfile.SelectedItem)"
    if (-not $p -or $p -like '(none*') { return }
    $script:Cfg = Import-MigratorSettings -Path $SettingsPath -ProfileName $p
    $State.Sync.Cfg = $script:Cfg
    Sync-UiFromConfig
    $State.Connected = $false
    $State.UI.BtnMigrate.IsEnabled = $false
    $State.Rows.Clear(); $State.RowByName = @{}
    Update-UiCount
    Set-UiConnected 'Not connected' '#374151'
    $State.UI.ConnPanel.Visibility = 'Visible'
    Add-UiLog "Profile switched to '$p' - site $($script:Cfg.SiteCode) on $($script:Cfg.SiteServer), tenant $($script:Cfg.TenantId). Connect again."
})

$UI.BtnConnect.Add_Click({
    $ui = $State.UI
    $script:Cfg.SiteServer = "$($ui.TxtServer.Text)".Trim()
    $script:Cfg.SiteCode   = "$($ui.TxtSite.Text)".Trim()
    $script:Cfg.TenantId   = "$($ui.TxtTenant.Text)".Trim()
    $State.Sync.Cfg = $script:Cfg
    $missing = Test-MigratorSettings -Cfg $script:Cfg
    if ($missing.Count) {
        [System.Windows.MessageBox]::Show("These settings are still empty:`r`n`r`n  $($missing -join "`r`n  ")`r`n`r`nFill them in above, or add them to the profile in settings.json.", 'Missing settings', 'OK', 'Warning') | Out-Null
        return
    }
    $ui.BtnConnect.IsEnabled = $false
    $ui.LblStatus.Text = 'Connecting...'
    Set-UiConnected 'Connecting...' '#B26A00'

    # Step 1 - sign in. This has to stay on the UI thread: MSAL puts up its own sign-in window.
    Show-UiBusy 'Signing in to Intune' "Tenant $($script:Cfg.TenantId). A sign-in window may appear - complete it there."
    try {
        Add-UiLog "Signing in to Intune (tenant $($script:Cfg.TenantId))..."
        $script:Auth = Connect-MigIntune -TenantId $script:Cfg.TenantId
        $State.Sync.AuthHeader = $script:Auth
        Add-UiLog 'Signed in to Intune.'
    } catch {
        Hide-UiBusy
        Add-UiLog "CONNECT FAILED: $($_.Exception.Message)" 'Error'
        Set-UiConnected 'Not connected' '#C62828'
        $ui.LblStatus.Text = 'Not connected'
        $ui.BtnConnect.IsEnabled = $true
        $ui.ExpLog.IsExpanded = $true
        [System.Windows.MessageBox]::Show("$($_.Exception.Message)", 'Sign-in failed', 'OK', 'Error') | Out-Null
        return
    }

    # Step 2 - the SLOW part (importing the ConfigMgr module, mapping the site drive, reading
    # every application) runs in its own runspace, so the overlay keeps animating and the window
    # stays alive instead of looking hung. The timer picks the result up.
    Show-UiBusy "Loading applications from $($script:Cfg.SiteCode)" "Connecting to $($script:Cfg.SiteServer) and reading the application list. On a large site this takes a minute."
    Add-UiLog "Connecting to SCCM $($script:Cfg.SiteCode) on $($script:Cfg.SiteServer)..."
    $s = $State.Sync
    $s.ConnectState = 'running'; $s.ConnectApps = $null; $s.ConnectError = ''
    $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
    $rs.SessionStateProxy.SetVariable('Sync',     $s)
    $rs.SessionStateProxy.SetVariable('ToolRoot', $script:ToolRoot)
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript(@"
`$ErrorActionPreference = 'Stop'
Set-StrictMode -Off
`$script:ToolRoot = `$ToolRoot
$($State.EngineText)
`$script:Sync = `$Sync
`$script:Cfg  = `$Sync.Cfg
try {
    Connect-MigSccm -SiteCode `$script:Cfg.SiteCode -SiteServer `$script:Cfg.SiteServer | Out-Null
    `$Sync.ConnectApps  = @(Get-MigSccmApplicationList -SiteCode `$script:Cfg.SiteCode)
    `$Sync.ConnectState = 'done'
} catch {
    `$Sync.ConnectError = "`$(`$_.Exception.Message)"
    `$Sync.ConnectState = 'failed'
}
"@)
    $State.ConnectWorker = $ps
    $State.ConnectHandle = $ps.BeginInvoke()
})

$UI.TxtSearch.Add_TextChanged({
    $State.UI.LblSearchHint.Visibility = if ("$($State.UI.TxtSearch.Text)".Length) { 'Collapsed' } else { 'Visible' }
    if ($State.View) { $State.View.Refresh() }
    Update-UiCount
})

$UI.BtnSelectNone.Add_Click({
    foreach ($r in $State.Rows) { $r.Selected = $false }
    Update-UiCount
})
# Ticking a box must update the counter. $State.UI is a HASHTABLE - it has no .Dispatcher; asking
# it for one is what threw "You cannot call a method on a null-valued expression" on every click.
# The dispatcher belongs to a real control.
# double-click a migrated row to open that app in the Intune portal
$UI.GridApps.Add_MouseDoubleClick({
    $row = $State.UI.GridApps.SelectedItem
    if ($row -and "$($row.PortalUrl)") { Start-Process "$($row.PortalUrl)" }
})
$UI.GridApps.Add_CurrentCellChanged({ Update-UiCount })
$UI.GridApps.Add_PreviewMouseLeftButtonUp({
    # The PRIORITY goes FIRST. BeginInvoke([action]{...}, 'Background') binds to the
    # BeginInvoke(Delegate, params object[]) overload instead, which hands 'Background' to the
    # action as an argument - and a zero-parameter action then dies with "Parameter count
    # mismatch", killing the window on the first click.
    $State.UI.GridApps.Dispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::Background, [action]{ Update-UiCount }) | Out-Null
})

# --- the pump: worker log/progress/results into the window, and the token refresh ---------------
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(300)
$timer.Add_Tick({
    $s = $State.Sync; $ui = $State.UI
    if ($s.LogQueue.Count) {
        $take = @()
        while ($s.LogQueue.Count -gt 0) { $take += $s.LogQueue[0]; $s.LogQueue.RemoveAt(0); if ($take.Count -ge 200) { break } }
        foreach ($l in $take) { Add-UiLog $l.Text $l.Level }
    }
    if ($s.Indeterminate) { $ui.Bar.IsIndeterminate = $true }
    else { $ui.Bar.IsIndeterminate = $false; $ui.Bar.Value = [int]$s.Percent }
    $prefix = if ($s.CurrentTotal) { "($($s.CurrentIndex) of $($s.CurrentTotal))  " } else { '' }
    if ("$($s.Status)") { $ui.LblStatus.Text = "$prefix$($s.Status)" }

    # mark the application currently being worked on
    if ($s.Running -and "$($s.CurrentApp)") {
        $cur = $State.RowByName["$($s.CurrentApp)"]
        if ($cur -and -not $cur.Status) { $cur.Status = 'Working...' }
    }
    # fold in results as they arrive - the row objects notify the grid themselves
    while ($State.SeenResults -lt $s.Results.Count) {
        $r = $s.Results[$State.SeenResults]; $State.SeenResults++
        $row = $State.RowByName["$($r.Application)"]
        if (-not $row) { continue }
        $row.Status = switch -Regex ("$($r.Status)") {
            '^Success$'   { 'Migrated' }
            '^DryRun$'    { 'Built (dry run)' }
            '^Skipped$'   { 'Skipped' }
            '^Cancelled$' { 'Cancelled' }
            '^Failed'     { 'Failed' }
            default       { "$($r.Status)" }
        }
        # short: the id when it worked, the reason when it did not
        $row.Detail = switch -Regex ("$($r.Status)") {
            '^Success$'  { "$($r.AppId)" }
            '^Skipped$'  { $m = ("$($r.Message)" -replace '\s+', ' ').Trim()
                            if ($m.Length -gt 150) { $m.Substring(0,150).TrimEnd() + '...' } else { $m } }
            '^DryRun$'   { 'built, nothing created' }
            default      { $s = ("$($r.Message)" -replace '\s+', ' ').Trim()
                           if ($s.Length -gt 150) { $s.Substring(0,150).TrimEnd() + '...' } else { $s } }
        }
        $row.PortalUrl = "$($r.PortalUrl)"
    }

    # --- the version / duplicate pre-flight finished? -----------------------------------------
    if ($State.PreflightWorker -and ("$($s.PreflightState)" -eq 'done' -or "$($s.PreflightState)" -eq 'failed')) {
        $pfState = "$($s.PreflightState)"
        $s.PreflightState = 'idle'
        try { $State.PreflightWorker.EndInvoke($State.PreflightHandle) | Out-Null } catch {}
        try { $State.PreflightWorker.Dispose() } catch {}
        $State.PreflightWorker = $null; $State.PreflightHandle = $null
        Hide-UiBusy
        $sel = @($s.PendingSelected)
        if ($pfState -eq 'failed') {
            Add-UiLog "The Intune check failed: $($s.PreflightError)" 'Error'
            $go = [System.Windows.MessageBox]::Show(
                "Could not check what is already in Intune:`r`n`r`n$($s.PreflightError)`r`n`r`nMigrate anyway? Existing versions would not be detected.",
                'Check failed', 'YesNo', 'Warning')
            if ($go -eq 'Yes') { Start-MigrationRun -Selected $sel -Dry $false -Skips @{} -Supersede @{} }
            else { $ui.LblStatus.Text = 'Cancelled - nothing was created' }
        } else {
            $found = @($s.PreflightResult)
            if (-not $found.Count) {
                Add-UiLog 'None of these is in Intune yet - migrating all of them.'
                Start-MigrationRun -Selected $sel -Dry $false -Skips @{} -Supersede @{}
            } else {
                $decision = Show-MigReviewDialog -Findings $found
                if ($null -eq $decision) {
                    Add-UiLog 'Cancelled at the review - nothing was created.' 'Warning'
                    $ui.LblStatus.Text = 'Cancelled - nothing was created'
                } else {
                    $reviewed = @{}; foreach ($fi in $found) { $reviewed["$($fi.Application)"] = $true }
                    Start-MigrationRun -Selected $sel -Dry $false -Skips $decision.Skips -Supersede $decision.Supersede -Reviewed $reviewed
                }
            }
        }
    }
    # --- the background connect finished? ---------------------------------------------------
    if ($State.ConnectWorker -and ("$($s.ConnectState)" -eq 'done' -or "$($s.ConnectState)" -eq 'failed')) {
        # NOT $state - PowerShell variable names are case-INSENSITIVE, so that name would overwrite
        # the $State hashtable this entire window runs on.
        $connState = "$($s.ConnectState)"
        $s.ConnectState = 'idle'
        try { $State.ConnectWorker.EndInvoke($State.ConnectHandle) | Out-Null } catch {}
        try { $State.ConnectWorker.Dispose() } catch {}
        $State.ConnectWorker = $null; $State.ConnectHandle = $null
        Hide-UiBusy
        $ui.BtnConnect.IsEnabled = $true
        if ($connState -eq 'failed') {
            Add-UiLog "CONNECT FAILED: $($s.ConnectError)" 'Error'
            Set-UiConnected 'Not connected' '#C62828'
            $ui.LblStatus.Text = 'Not connected'
            $ui.ExpLog.IsExpanded = $true
            [System.Windows.MessageBox]::Show("$($s.ConnectError)", 'Could not read the SCCM site', 'OK', 'Error') | Out-Null
        } else {
            $apps = @($s.ConnectApps)
            $State.Rows.Clear(); $State.RowByName = @{}
            foreach ($a in $apps) {
                $row = New-Object MigAppRow
                $row.Name    = "$($a.LocalizedDisplayName)"
                $row.Version = "$($a.SoftwareVersion)"
                $row.Created = $(try { ([datetime]$a.DateCreated).ToString('yyyy-MM-dd') } catch { '' })
                $State.Rows.Add($row)
                $State.RowByName[$row.Name] = $row
            }
            $State.Connected = $true
            Update-UiCount
            $ui.BtnMigrate.IsEnabled = $true
            $ui.ConnPanel.Visibility = 'Collapsed'   # the form has done its job - give the space to the list
            Set-UiConnected "$($script:Cfg.SiteCode) - $($script:Cfg.TenantId)" '#1A7F37'
            $ui.LblStatus.Text = "$($apps.Count) applications loaded"
            Add-UiLog "Connected. $($apps.Count) applications. Tick the ones to migrate, then press Migrate."
        }
    }

    if ($s.ReauthRequested) {
        try {
            Add-UiLog 'Refreshing the Intune sign-in...'
            $s.AuthHeader = Connect-MigIntune -TenantId $s.Cfg.TenantId
            $script:Auth  = $s.AuthHeader
            Add-UiLog 'Sign-in refreshed.'
        } catch { Add-UiLog "The sign-in could not be refreshed: $($_.Exception.Message)" 'Error'; $s.AuthHeader = '' }
        $s.ReauthRequested = $false
    }

    if ($State.Worker -and -not $s.Running) {
        try { $State.Worker.EndInvoke($State.Handle) | Out-Null } catch {}
        try { $State.Worker.Dispose() } catch {}
        $State.Worker = $null; $State.Handle = $null
        Set-UiBusy $false
        $ui.Bar.IsIndeterminate = $false; $ui.Bar.Value = 100
        $res  = @($s.Results)
        $ok   = @($res | Where-Object { $_.Status -eq 'Success' }).Count
        $dry  = @($res | Where-Object { $_.Status -eq 'DryRun' }).Count
        $bad  = @($res | Where-Object { "$($_.Status)" -like 'Failed*' }).Count
        $skip = @($res | Where-Object { $_.Status -eq 'Skipped' }).Count
        $ui.LblStatus.Text = "Finished - $ok migrated, $bad failed, $skip skipped$(if ($dry) { ", $dry built (dry run)" })"
        if ($s.Report -and $s.Report.Html) { $ui.BtnOpenReport.IsEnabled = $true; $State.ReportPath = $s.Report.Html }
        $pending = @($res | Where-Object { "$($_.UatGroup)" -and -not $_.UatGroupExists }).Count
        $msg = "Migration finished.`r`n`r`n  migrated : $ok`r`n  failed   : $bad`r`n  skipped  : $skip"
        if ($dry)     { $msg += "`r`n  dry run  : $dry" }
        if ($pending) { $msg += "`r`n`r`n$pending application(s) name a UAT group that does not exist yet - the names are in the report." }
        if ($s.FatalError) { $msg += "`r`n`r`nThe batch stopped early: $($s.FatalError)" }
        $msg += "`r`n`r`nEverything is under:`r`n$($s.RunFolder)"
        [System.Windows.MessageBox]::Show($msg, 'Migration finished', 'OK', $(if ($bad -or $s.FatalError) { 'Warning' } else { 'Information' })) | Out-Null
    }
})
$timer.Start()

$UI.BtnMigrate.Add_Click({
    $ui = $State.UI; $s = $State.Sync
    $selected = @($State.Rows | Where-Object { $_.Selected } | ForEach-Object { $_.Name })
    if ($selected.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Tick at least one application in the list.', 'Nothing ticked', 'OK', 'Information') | Out-Null
        return
    }
    $dry = [bool]$ui.ChkDryRun.IsChecked
    $missing = Test-MigratorSettings -Cfg $script:Cfg
    if ($missing.Count) {
        [System.Windows.MessageBox]::Show("These settings are still empty:`r`n`r`n  $($missing -join "`r`n  ")", 'Missing settings', 'OK', 'Warning') | Out-Null
        return
    }
    $what = if ($dry) {
        "DRY RUN`r`n`r`n$($selected.Count) application(s) will be read and packaged. NOTHING will be created in Intune."
    } else {
        "$($selected.Count) application(s) will be created in Intune (tenant $($script:Cfg.TenantId)).`r`n`r`nNothing is assigned and no group is created - each application's UAT group name simply goes in the report."
    }
    $ans = [System.Windows.MessageBox]::Show("$what`r`n`r`nIf an application fails, everything it created is rolled back.`r`n`r`nStart now?", 'Confirm migration', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }

    # A dry run creates nothing, so there is nothing to ask about - go straight in.
    if ($dry) { Start-MigrationRun -Selected $selected -Dry $true -Skips @{} -Supersede @{}; return }

    # Otherwise find out FIRST what is already in Intune - the same version, an older one, or a
    # newer one - so everything is decided in ONE dialog before anything is created, instead of a
    # prompt interrupting the batch every so often.
    Show-UiBusy 'Checking Intune' "Looking for versions of these $($selected.Count) application(s) that are already there."
    $s.Cfg = $script:Cfg
    $s.PendingSelected = $selected
    $s.PreflightState = 'running'; $s.PreflightResult = $null; $s.PreflightError = ''
    $s.AuthHeader = $script:Auth
    $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
    $rs.SessionStateProxy.SetVariable('Sync',     $s)
    $rs.SessionStateProxy.SetVariable('ToolRoot', $script:ToolRoot)
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript(@"
`$ErrorActionPreference = 'Stop'
Set-StrictMode -Off
`$script:ToolRoot = `$ToolRoot
$($State.EngineText)
`$script:Sync = `$Sync
`$script:Cfg  = `$Sync.Cfg
`$script:Auth = "`$(`$Sync.AuthHeader)"
try {
    Clear-MigAppListCache
    `$Sync.PreflightResult = @(Get-MigDuplicatePreflight -Applications @(`$Sync.PendingSelected))
    `$Sync.PreflightState  = 'done'
} catch {
    `$Sync.PreflightError = "`$(`$_.Exception.Message)"
    `$Sync.PreflightState = 'failed'
}
"@)
    $State.PreflightWorker = $ps
    $State.PreflightHandle = $ps.BeginInvoke()
})

# One row per application that already has a version in Intune. Kept separate from the dialog so
# the wording and the choices can be tested without putting a window on screen.
function New-MigReviewRows {
    param([Parameter(Mandatory)]$Findings)
    $rows = New-Object System.Collections.ObjectModel.ObservableCollection[MigReviewRow]
    foreach ($fi in @($Findings)) {
        $r = New-Object MigReviewRow
        $r.Application = "$($fi.Application)"
        $r.NewVersion  = "$($fi.Version)"
        $same = @($fi.Same); $lower = @($fi.Lower); $higher = @($fi.Higher)
        $bits = @()
        # a brand that does not record a lifecycle in Notes simply shows the version - no "[unknown]"
        foreach ($x in @($fi.All)) {
            $lc = "$($x.Lifecycle)"
            $bits += "v$($x.Version)$(if ($lc -and $lc -ne 'unknown') { " [$lc]" })"
        }
        $r.Found     = ($bits -join ', ')
        $r.Lifecycle = ((@($fi.All) | ForEach-Object { $_.Lifecycle } | Select-Object -Unique) -join '/')
        # Each situation gets exactly TWO choices, and the wording NAMES the situation so the
        # decision - and the note that ends up in the report - is unambiguous.
        if ($same.Count) {
            $r.Relation = "SAME version (v$(@($same)[0].Version)) already in Intune"
            $r.Actions  = @('Skip - do not migrate', 'Continue - migrate anyway')
            $r.Action   = 'Skip - do not migrate'
        } elseif ($higher.Count) {
            $r.Relation = "HIGHER version (v$(@($higher)[0].Version)) already in Intune"
            $r.Actions  = @('Skip - do not migrate', 'Continue - migrate anyway')
            $r.Action   = 'Skip - do not migrate'
        } else {
            $r.Relation = "LOWER version (v$(@($lower)[0].Version)) already in Intune"
            $r.Actions  = @("Add supersedence - migrate and supersede v$(@($lower)[0].Version)", 'Skip - do not migrate')
            $r.Action   = "Add supersedence - migrate and supersede v$(@($lower)[0].Version)"
        }
        $r.SupersedeIds = ((@($lower | ForEach-Object { $_.Id })) -join ';')
        $rows.Add($r)
    }
    return $rows
}

# Turn the answered rows into what the run needs. Also separate so it can be tested directly.
function Get-MigReviewDecision {
    param([Parameter(Mandatory)]$Rows)
    $skips = @{}; $sup = @{}
    foreach ($r in @($Rows)) {
        $act = "$($r.Action)"
        if ($act -like 'Skip*') {
            # this exact sentence becomes the note in the report AND in the tool's Result column
            $skips["$($r.Application)"] = "Skipped - $($r.Relation)."
        } elseif ($act -like 'Add supersedence*') {
            $ids = @("$($r.SupersedeIds)" -split ';' | Where-Object { $_ })
            if ($ids.Count) { $sup["$($r.Application)"] = $ids }
        }
        # 'Continue - migrate anyway' needs neither: the application just runs normally
    }
    return @{ Skips = $skips; Supersede = $sup }
}

# --- the review dialog -------------------------------------------------------------------------
# Returns $null if the operator cancels, otherwise @{ Skips = @{name=reason}; Supersede = @{name=@(ids)} }.
function Show-MigReviewDialog {
    param([Parameter(Mandatory)]$Findings)
    $rows = New-MigReviewRows -Findings $Findings

    $dlgXaml = Get-MigReviewXaml
    [xml]$x = $dlgXaml
    $dlg = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $x))
    $g   = $dlg.FindName('GridReview')
    $g.ItemsSource = $rows
    $dlg.FindName('LblIntro').Text =
        "$(@($Findings).Count) of the ticked applications already have a version in Intune. Choose what to do with each one - the rest of the run is unaffected. NOTHING has been created yet."
    $anyLc = @($Findings | ForEach-Object { @($_.All) } | Where-Object { $_.Lifecycle -and $_.Lifecycle -ne 'unknown' }).Count
    $dlg.FindName('LblFoot').Text = $(if ($anyLc) { 'Lifecycle in brackets is read from each existing app''s Notes field.' }
                                       else { 'These apps record no lifecycle in their Notes, so only the version is shown.' })
    $script:__reviewOk = $false
    $dlg.FindName('BtnGo').Add_Click({ $script:__reviewOk = $true; $dlg.Close() })
    $dlg.FindName('BtnAbort').Add_Click({ $script:__reviewOk = $false; $dlg.Close() })
    try { $dlg.Owner = $State.Sync.Window } catch {}
    $null = $dlg.ShowDialog()
    if (-not $script:__reviewOk) { return $null }
    return (Get-MigReviewDecision -Rows $rows)
}

# Everything the actual run needs. Split out so it can be started either straight away (dry run)
# or once the review dialog has been answered.
function Start-MigrationRun {
    param([string[]]$Selected, [bool]$Dry, [hashtable]$Skips, [hashtable]$Supersede, [hashtable]$Reviewed = @{})
    $ui = $State.UI; $s = $State.Sync
    Show-UiBusy 'Starting the migration' "Preparing the work folder for $($Selected.Count) application(s)."
    foreach ($r in $State.Rows) { if ($r.Selected) { $r.Status = ''; $r.Detail = ''; $r.PortalUrl = '' } }
    $ui.TxtLog.Clear()
    $s.Cfg = $script:Cfg
    $run = Initialize-MigRun -Cfg $script:Cfg
    $s.RunFolder = $run; $s.BatchLogPath = $script:BatchLogPath
    $s.Queue = $Selected; $s.DryRun = $Dry; $s.AuthHeader = $script:Auth
    $s.SkipApps = $Skips; $s.SupersedeMap = $Supersede; $s.ReviewedApps = $Reviewed
    $s.KnownDuplicates = @{}; $s.DuplicateAction = 'Create'   # the review dialog has already decided
    $s.CancelRequested = $false; $s.ReauthRequested = $false; $s.FatalError = ''
    $s.Percent = 0; $s.Status = 'Starting...'; $s.Indeterminate = $true
    $s.CurrentIndex = 0; $s.CurrentTotal = $Selected.Count; $s.CurrentApp = ''
    $s.Results.Clear(); $State.SeenResults = 0
    $ui.LblRunFolder.Text = "Output: $run"
    $ui.BtnOpenReport.IsEnabled = $false
    Set-UiBusy $true

    # the batch runs in its own runspace so the window keeps painting and stays cancellable
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions  = 'ReuseThread'
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('Sync',     $s)
    $rs.SessionStateProxy.SetVariable('ToolRoot', $script:ToolRoot)
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript(@"
`$ErrorActionPreference = 'Stop'
Set-StrictMode -Off
`$script:ToolRoot = `$ToolRoot
$($State.EngineText)
try { Start-MigWorker -Sync `$Sync } catch { `$Sync.FatalError = "`$(`$_.Exception.Message)"; `$Sync.Running = `$false }
"@)
    $s.Running = $true
    $State.Worker = $ps
    $State.Handle = $ps.BeginInvoke()
    Hide-UiBusy
    $extra = ''
    if ($Skips.Count)     { $extra += " $($Skips.Count) left alone." }
    if ($Supersede.Count) { $extra += " $($Supersede.Count) will supersede an older version." }
    Add-UiLog "Started: $($Selected.Count) application(s)$(if ($Dry) { ' (dry run)' }). Output folder: $run.$extra"
}

# The review dialog's markup, kept in its own function so the surrounding code stays readable.
function Get-MigReviewXaml {
    return @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Already in Intune" Height="540" Width="1180" WindowStartupLocation="CenterOwner"
        Background="#F2F3F5" FontFamily="Segoe UI" FontSize="12" ShowInTaskbar="False">
  <Grid Margin="16">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel Grid.Row="0" Margin="0,0,0,12">
      <TextBlock Text="Some of these applications already have a version in Intune"
                 FontSize="15" FontWeight="SemiBold" Foreground="#22262B"/>
      <TextBlock Name="LblIntro" Foreground="#6A737D" Margin="0,5,0,0" TextWrapping="Wrap"/>
    </StackPanel>
    <DataGrid Grid.Row="1" Name="GridReview" AutoGenerateColumns="False" CanUserAddRows="False"
              HeadersVisibility="Column" RowHeaderWidth="0" GridLinesVisibility="Horizontal"
              HorizontalGridLinesBrush="#EEF0F2" Background="White" RowHeight="30"
              SelectionMode="Single" BorderBrush="#E1E4E8" AlternatingRowBackground="#FAFBFC">
      <DataGrid.ColumnHeaderStyle>
        <Style TargetType="DataGridColumnHeader">
          <Setter Property="Background" Value="#F6F7F9"/>
          <Setter Property="Foreground" Value="#454B52"/>
          <Setter Property="FontWeight" Value="SemiBold"/>
          <Setter Property="Padding" Value="8,6"/>
          <Setter Property="BorderBrush" Value="#E1E4E8"/>
          <Setter Property="BorderThickness" Value="0,0,0,1"/>
        </Style>
      </DataGrid.ColumnHeaderStyle>
      <DataGrid.Columns>
        <DataGridTextColumn Header="Application" Binding="{Binding Application}" Width="2.0*" IsReadOnly="True"/>
        <DataGridTextColumn Header="Migrating" Binding="{Binding NewVersion}" Width="80" IsReadOnly="True"/>
        <DataGridTextColumn Header="Already in Intune" Binding="{Binding Found}" Width="1.1*" IsReadOnly="True"/>
        <DataGridTextColumn Header="Situation" Binding="{Binding Relation}" Width="2.1*" IsReadOnly="True">
          <DataGridTextColumn.ElementStyle>
            <Style TargetType="TextBlock">
              <Setter Property="VerticalAlignment" Value="Center"/>
              <Setter Property="TextTrimming" Value="CharacterEllipsis"/>
              <Style.Triggers>
                <DataTrigger Binding="{Binding Relation}" Value="SAME version already in Intune">
                  <Setter Property="Foreground" Value="#B26A00"/><Setter Property="FontWeight" Value="SemiBold"/>
                </DataTrigger>
              </Style.Triggers>
            </Style>
          </DataGridTextColumn.ElementStyle>
        </DataGridTextColumn>
        <!-- a template column, so the dropdown is ALWAYS visible and one click changes it -
             a DataGridComboBoxColumn only looks like a dropdown once the cell is in edit mode -->
        <DataGridTemplateColumn Header="What to do" Width="2.6*">
          <DataGridTemplateColumn.CellTemplate>
            <DataTemplate>
              <ComboBox ItemsSource="{Binding Actions}"
                        SelectedItem="{Binding Action, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}"
                        Margin="2,3" Padding="6,2" VerticalContentAlignment="Center"/>
            </DataTemplate>
          </DataGridTemplateColumn.CellTemplate>
        </DataGridTemplateColumn>
      </DataGrid.Columns>
    </DataGrid>
    <Grid Grid.Row="2" Margin="0,14,0,0">
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <TextBlock Grid.Column="0" Name="LblFoot" VerticalAlignment="Center" Foreground="#6A737D" FontSize="11"/>
      <StackPanel Grid.Column="2" Orientation="Horizontal">
        <Button Name="BtnAbort" Content="Cancel the whole run" Width="160" Height="30" Margin="0,0,8,0"/>
        <Button Name="BtnGo"    Content="Continue" Width="130" Height="30" Background="#0F6CBD" Foreground="White" FontWeight="SemiBold" BorderThickness="0"/>
      </StackPanel>
    </Grid>
  </Grid>
</Window>
'@
}


$UI.BtnCancel.Add_Click({
    $State.Sync.CancelRequested = $true
    Add-UiLog 'Cancel requested - the current application finishes its current step, then the batch stops.' 'Warning'
    $State.UI.BtnCancel.IsEnabled = $false
})

$UI.BtnOpenReport.Add_Click({
    if ($State.ReportPath -and (Test-Path -LiteralPath $State.ReportPath)) { Invoke-Item -LiteralPath $State.ReportPath }
})

$Win.Add_Closing({
    if ($State.Sync.Running) {
        $a = [System.Windows.MessageBox]::Show('A migration is still running. Close anyway? The application being processed is left as it is - check the report folder afterwards.', 'Still running', 'YesNo', 'Warning')
        if ($a -ne 'Yes') { $_.Cancel = $true; return }
        $State.Sync.CancelRequested = $true
    }
    try { $timer.Stop() } catch {}
})

$UI.LblStatus.Text = 'Not connected'
Update-UiCount
Add-UiLog "SCCM to Intune migrator - profile '$($script:Cfg.ProfileName)'. Check the connection details, then press Connect."
$null = $Win.ShowDialog()
