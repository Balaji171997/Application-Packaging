# Phase 2b: given the NEW package name being built, pick its PREDECESSOR from SharePoint.
# Read-only - reports the choice and why. Nothing is downloaded. Separate file; nothing else is modified.
#
#   .\Test-ResolvePredecessor.ps1 -PkgName '3Dconnexion_3DxWare_x64_10.9.1.650-0004_MUL'
#   .\Test-ResolvePredecessor.ps1 -PkgName '3Dconnexion_3DxWare_x64_10.9.1.650-0003_MUL'

param(
    [Parameter(Mandatory)][string[]]$PkgName,
    [switch]$ShowAll          # list every candidate, not just the pick
)

Import-Module (Join-Path $PSScriptRoot 'PnP.PowerShell\1.12.0\PnP.PowerShell.psd1') -ErrorAction Stop

$siteUrl  = 'https://manonlineservices.sharepoint.com/sites/SWPackaging'
$clientId = '28bf2c22-437c-42e7-a4be-e8a0f44a8264'
$libRel   = 'PackageSources'

function Parse-PkgName {
    param([string]$Name)
    $p = '^(?<Vendor>[^_]+)_(?<App>.+)_(?<Arch>x86|x64|x86_64|ALL)_(?<Ver>[^_]+)-(?<Rel>\d{4})_(?<Lang>[\w\-]+)$'
    if ($Name -match $p) {
        return [ordered]@{ Vendor=$Matches.Vendor; App=$Matches.App; Arch=$Matches.Arch
                           Version=$Matches.Ver; Release=[int]$Matches.Rel; Lang=$Matches.Lang; Matched=$true }
    }
    return [ordered]@{ Matched = $false }
}

# Version folders are '<Version>_<Release>' e.g. '10.9.1.650_0003'. Release is always 4 digits at the end.
function Parse-VersionFolder {
    param([string]$FolderName)
    if ($FolderName -match '^(?<Ver>.+)_(?<Rel>\d{4})$') {
        return @{ Version = $Matches.Ver; Release = [int]$Matches.Rel; Raw = $FolderName; Valid = $true }
    }
    return @{ Raw = $FolderName; Valid = $false }
}

# Component-wise NUMERIC compare - '10.8.7' < '10.8.7.3448', and handles 5+ components that [version] rejects.
# Returns -1 / 0 / 1.
function Compare-VersionString {
    param([string]$A, [string]$B)
    $x = @($A -split '[.\-]' | ForEach-Object { $n = 0; if ([int]::TryParse($_, [ref]$n)) { $n } else { 0 } })
    $y = @($B -split '[.\-]' | ForEach-Object { $n = 0; if ([int]::TryParse($_, [ref]$n)) { $n } else { 0 } })
    $max = [Math]::Max($x.Count, $y.Count)
    for ($i = 0; $i -lt $max; $i++) {
        $xi = if ($i -lt $x.Count) { $x[$i] } else { 0 }
        $yi = if ($i -lt $y.Count) { $y[$i] } else { 0 }
        if ($xi -lt $yi) { return -1 }
        if ($xi -gt $yi) { return 1 }
    }
    return 0
}
# Full ordering: version first, then release.
function Compare-VerRel {
    param($A, $B)
    $c = Compare-VersionString -A $A.Version -B $B.Version
    if ($c -ne 0) { return $c }
    if ($A.Release -lt $B.Release) { return -1 }
    if ($A.Release -gt $B.Release) { return 1 }
    return 0
}

function Get-Items { param([string]$RelUrl) return @(Get-PnPFolderItem -FolderSiteRelativeUrl $RelUrl -ErrorAction SilentlyContinue) }
function Is-Folder { param($Item) return $Item.GetType().Name -eq 'Folder' }

Connect-PnPOnline -Url $siteUrl -ClientId $clientId -Interactive

# `powershell -File x.ps1 -PkgName "a","b"` passes ONE literal string "a,b" (no syntax parsing), so split
# defensively. A real package name never contains a comma.
$PkgName = @($PkgName | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

foreach ($name in $PkgName) {
    Write-Host "`n=============================================================" -ForegroundColor Cyan
    Write-Host "Building: $name" -ForegroundColor Cyan

    $id = Parse-PkgName $name
    if (-not $id.Matched) { Write-Host "  Unparseable name - skipping." -ForegroundColor Red; continue }
    Write-Host "  Parsed: Vendor=$($id.Vendor) App=$($id.App) Arch=$($id.Arch) Ver=$($id.Version) Rel=$($id.Release)" -ForegroundColor DarkGray

    $appRel = "$libRel/$($id.Vendor)/$($id.App)"
    $versions = @(Get-Items -RelUrl $appRel | Where-Object { Is-Folder $_ })
    if (-not $versions) { Write-Host "  No version folders under $appRel" -ForegroundColor Red; continue }

    $target = @{ Version = $id.Version; Release = $id.Release }

    # Build candidate list: parseable, strictly OLDER than target, and actually HAS a package in SCCM/.
    $candidates = @()
    foreach ($v in $versions) {
        $pv = Parse-VersionFolder $v.Name
        if (-not $pv.Valid) {
            if ($ShowAll) { Write-Host "  skip '$($v.Name)': not <Version>_<Release>" -ForegroundColor DarkGray }
            continue
        }
        if ((Compare-VerRel -A $pv -B $target) -ge 0) {
            if ($ShowAll) { Write-Host "  skip '$($v.Name)': not older than target" -ForegroundColor DarkGray }
            continue
        }
        # Must contain SCCM/<something> - stale ticket-only folders are not usable predecessors.
        $sccmKids = @(Get-Items -RelUrl "$appRel/$($v.Name)/SCCM" | Where-Object { Is-Folder $_ })
        if ($sccmKids.Count -eq 0) {
            if ($ShowAll) { Write-Host "  skip '$($v.Name)': no package in SCCM/" -ForegroundColor DarkGray }
            continue
        }
        $pv.PkgFolder = $sccmKids[0].Name
        $pv.RelPath   = "$appRel/$($v.Name)/SCCM/$($sccmKids[0].Name)"
        if ($sccmKids.Count -gt 1) { $pv.Warning = "SCCM/ holds $($sccmKids.Count) folders - took the first" }
        $candidates += ,$pv
    }

    if ($candidates.Count -eq 0) { Write-Host "  NO PREDECESSOR FOUND (no older version with a built package)." -ForegroundColor Yellow; continue }

    # Highest of the older ones = the predecessor.
    $sorted = $candidates
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        for ($j = $i + 1; $j -lt $sorted.Count; $j++) {
            if ((Compare-VerRel -A $sorted[$i] -B $sorted[$j]) -lt 0) { $t = $sorted[$i]; $sorted[$i] = $sorted[$j]; $sorted[$j] = $t }
        }
    }

    if ($ShowAll) {
        Write-Host "  Candidates (newest first):" -ForegroundColor DarkCyan
        $sorted | ForEach-Object { Write-Host "        $($_.Raw)  ->  $($_.PkgFolder)" -ForegroundColor DarkGray }
    }

    $pick = $sorted[0]
    Write-Host "  PREDECESSOR: $($pick.Raw)" -ForegroundColor Green
    Write-Host "    package  : $($pick.PkgFolder)"
    Write-Host "    path     : $($pick.RelPath)"
    if ($pick.Warning) { Write-Host "    WARNING  : $($pick.Warning)" -ForegroundColor Yellow }

    # Sanity-check the shape PB expects from a predecessor.
    $kids = Get-Items -RelUrl $pick.RelPath
    $names = @($kids | ForEach-Object { $_.Name })
    foreach ($want in @('Content','Documents','Icons')) {
        $has = $names -icontains $want
        $col = if ($has) { 'Green' } else { 'Yellow' }
        Write-Host "    $($want.PadRight(10)): $(if ($has) { 'present' } else { 'MISSING' })" -ForegroundColor $col
    }
    $content = @(Get-Items -RelUrl "$($pick.RelPath)/Content" | ForEach-Object { $_.Name })
    $v3 = $content -icontains 'Deploy-Application.ps1'
    $v4 = $content -icontains 'Invoke-AppDeployToolkit.ps1'
    Write-Host "    PSADT     : $(if ($v4) { 'v4' } elseif ($v3) { 'v3' } else { 'UNKNOWN - no toolkit script found' })" -ForegroundColor $(if ($v3 -or $v4) { 'Green' } else { 'Red' })
}

Write-Host "`nDone." -ForegroundColor Cyan
