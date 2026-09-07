# Phase 2a: given a PB package name, resolve it to a SharePoint folder and report what WOULD be fetched.
# Read-only - nothing is downloaded yet. Run this against several real package names to validate the mapping
# before we build the download step.
#
#   .\Test-ResolvePackage.ps1 -PkgName '3Dconnexion_3DxWare_x64_10.9.1.650-0001_MUL'
#   .\Test-ResolvePackage.ps1 -PkgName '3dio_ExrIO_x64_2.06.00-0002_MUL'

param(
    [Parameter(Mandatory)][string[]]$PkgName
)

Import-Module (Join-Path $PSScriptRoot 'PnP.PowerShell\1.12.0\PnP.PowerShell.psd1') -ErrorAction Stop

$siteUrl  = 'https://manonlineservices.sharepoint.com/sites/SWPackaging'
$clientId = '28bf2c22-437c-42e7-a4be-e8a0f44a8264'
$libRel   = 'PackageSources'

# Folders that hold BUILT OUTPUT, not source - never fetch these.
$script:OutputFolders = @('EQS','SCCM','Intune','Order')

# Same convention PB uses: Vendor_App_Arch_Version-Release_Lang
function Parse-PkgName {
    param([string]$Name)
    $p = '^(?<Vendor>[^_]+)_(?<App>.+)_(?<Arch>x86|x64|x86_64|ALL)_(?<Ver>[^_]+)-(?<Rel>\d{4})_(?<Lang>[\w\-]+)$'
    if ($Name -match $p) {
        return [ordered]@{
            Vendor = $Matches.Vendor; App = $Matches.App; Arch = $Matches.Arch
            Version = $Matches.Ver;   Release = $Matches.Rel; Lang = $Matches.Lang; Matched = $true
        }
    }
    return [ordered]@{ Matched = $false }
}

function Get-ChildNames {
    param([string]$RelUrl)
    $items = Get-PnPFolderItem -FolderSiteRelativeUrl $RelUrl -ErrorAction SilentlyContinue
    return @($items)
}

# Find a child folder by name, case-insensitive, with a fuzzy fallback (SharePoint casing/spacing drifts).
function Find-Child {
    param([string]$ParentRel, [string]$Want)
    $kids = Get-ChildNames -RelUrl $ParentRel
    if (-not $kids) { return $null }
    $hit = $kids | Where-Object { $_.Name -ieq $Want } | Select-Object -First 1
    if ($hit) { return $hit.Name }
    $hit = $kids | Where-Object { $_.Name -ireplace '[\s_-]','' -eq ($Want -ireplace '[\s_-]','') } | Select-Object -First 1
    if ($hit) { return $hit.Name }
    return $null
}

Connect-PnPOnline -Url $siteUrl -ClientId $clientId -Interactive

foreach ($name in $PkgName) {
    Write-Host "`n=============================================================" -ForegroundColor Cyan
    Write-Host "Package: $name" -ForegroundColor Cyan

    $id = Parse-PkgName $name
    if (-not $id.Matched) {
        Write-Host "  Name does not match Vendor_App_Arch_Version-Release_Lang - would fall back to manual selection." -ForegroundColor Yellow
        continue
    }
    $verFolder = "$($id.Version)_$($id.Release)"     # hyphen in the name becomes underscore in SharePoint
    Write-Host "  Parsed  : Vendor=$($id.Vendor)  App=$($id.App)  Version=$($id.Version)  Release=$($id.Release)"
    Write-Host "  Expected: $libRel/$($id.Vendor)/$($id.App)/$verFolder"

    $vendor = Find-Child -ParentRel $libRel -Want $id.Vendor
    if (-not $vendor) { Write-Host "  MISS: vendor folder '$($id.Vendor)' not found." -ForegroundColor Red; continue }

    $app = Find-Child -ParentRel "$libRel/$vendor" -Want $id.App
    if (-not $app) { Write-Host "  MISS: app folder '$($id.App)' not found under '$vendor'." -ForegroundColor Red; continue }

    $ver = Find-Child -ParentRel "$libRel/$vendor/$app" -Want $verFolder
    if (-not $ver) {
        Write-Host "  MISS: version folder '$verFolder' not found under '$vendor/$app'. Available:" -ForegroundColor Red
        Get-ChildNames -RelUrl "$libRel/$vendor/$app" | ForEach-Object { Write-Host "        $($_.Name)" -ForegroundColor DarkGray }
        continue
    }

    $verRel = "$libRel/$vendor/$app/$ver"
    Write-Host "  RESOLVED: $verRel" -ForegroundColor Green

    $kids    = Get-ChildNames -RelUrl $verRel
    $folders = @($kids | Where-Object { $_.GetType().Name -eq 'Folder' })
    $files   = @($kids | Where-Object { $_.GetType().Name -ne 'Folder' })

    $srcName = ($folders | Where-Object { $_.Name -ieq 'source' } | Select-Object -First 1).Name
    $docName = ($folders | Where-Object { $_.Name -ieq 'doc' }    | Select-Object -First 1).Name
    $skipped = @($folders | Where-Object { $script:OutputFolders -icontains $_.Name }).Name

    if ($srcName) {
        Write-Host "  WOULD FETCH source/:" -ForegroundColor Green
        Get-ChildNames -RelUrl "$verRel/$srcName" | ForEach-Object {
            $t = if ($_.GetType().Name -eq 'Folder') { '[D]' } else { '[F]' }
            Write-Host "        $t $($_.Name)"
        }
    } else {
        # "dumped straight into the version folder" case - loose files, minus the RITM ticket refs.
        $loose = @($files | Where-Object { $_.Name -notmatch '^RITM\d+\.txt$' })
        if ($loose.Count -gt 0) {
            Write-Host "  No source/ folder - WOULD FETCH loose files at version root:" -ForegroundColor Yellow
            $loose | ForEach-Object { Write-Host "        [F] $($_.Name)" }
        } else {
            Write-Host "  NO SOURCE FOUND (only ticket refs / output folders) - PB would fall back to manual." -ForegroundColor Yellow
        }
    }

    if ($docName) {
        Write-Host "  WOULD FETCH doc/:" -ForegroundColor Green
        Get-ChildNames -RelUrl "$verRel/$docName" | ForEach-Object { Write-Host "        [F] $($_.Name)" }
    }
    if ($skipped) { Write-Host "  SKIPPING output folders: $($skipped -join ', ')" -ForegroundColor DarkGray }
}

Write-Host "`nDone." -ForegroundColor Cyan
