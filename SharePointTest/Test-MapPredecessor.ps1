# Phase 1b: map how PREDECESSOR packages are stored in SharePoint.
# Read-only. Separate from Test-ResolvePackage.ps1 - nothing there is modified.
#
# Expected shape (to be confirmed by this run):
#   PackageSources/{Vendor}/{App}/{Version}_{Release}/SCCM/{FullPackageName}/...
#
#   .\Test-MapPredecessor.ps1 -Vendor '3Dconnexion' -App '3DxWare'
#   .\Test-MapPredecessor.ps1 -PkgName '3Dconnexion_3DxWare_x64_10.9.1.650-0001_MUL'

param(
    [string]$Vendor,
    [string]$App,
    [string]$PkgName,          # alternative to -Vendor/-App: parse them out of a full package name
    [int]$MaxVersions = 6,     # how many version folders to inspect
    [int]$Depth = 2            # how deep to walk inside each SCCM package folder
)

Import-Module (Join-Path $PSScriptRoot 'PnP.PowerShell\1.12.0\PnP.PowerShell.psd1') -ErrorAction Stop

$siteUrl  = 'https://manonlineservices.sharepoint.com/sites/SWPackaging'
$clientId = '28bf2c22-437c-42e7-a4be-e8a0f44a8264'
$libRel   = 'PackageSources'

if ($PkgName) {
    $p = '^(?<Vendor>[^_]+)_(?<App>.+)_(?<Arch>x86|x64|x86_64|ALL)_(?<Ver>[^_]+)-(?<Rel>\d{4})_(?<Lang>[\w\-]+)$'
    if ($PkgName -match $p) { $Vendor = $Matches.Vendor; $App = $Matches.App }
    else { Write-Host "Could not parse '$PkgName'." -ForegroundColor Red; return }
}
if (-not $Vendor -or -not $App) { Write-Host "Need -Vendor and -App (or -PkgName)." -ForegroundColor Red; return }

function Get-Items {
    param([string]$RelUrl)
    return @(Get-PnPFolderItem -FolderSiteRelativeUrl $RelUrl -ErrorAction SilentlyContinue)
}
function Is-Folder { param($Item) return $Item.GetType().Name -eq 'Folder' }

function Walk {
    param([string]$RelUrl, [int]$Level, [int]$MaxLevel)
    if ($Level -gt $MaxLevel) { return }
    foreach ($it in (Get-Items -RelUrl $RelUrl)) {
        $indent = '  ' * ($Level + 4)
        if (Is-Folder $it) {
            Write-Host "$indent[D] $($it.Name)"
            Walk -RelUrl "$RelUrl/$($it.Name)" -Level ($Level + 1) -MaxLevel $MaxLevel
        } else {
            Write-Host "$indent[F] $($it.Name)"
        }
    }
}

Connect-PnPOnline -Url $siteUrl -ClientId $clientId -Interactive

$appRel = "$libRel/$Vendor/$App"
Write-Host "`nApp path: $appRel" -ForegroundColor Cyan

$versions = @(Get-Items -RelUrl $appRel | Where-Object { Is-Folder $_ })
if (-not $versions) { Write-Host "No version folders found (check vendor/app names)." -ForegroundColor Red; return }

Write-Host "Version folders found: $($versions.Count)" -ForegroundColor Cyan
$versions | ForEach-Object { Write-Host "   $($_.Name)" -ForegroundColor DarkGray }

foreach ($v in ($versions | Select-Object -First $MaxVersions)) {
    $verRel = "$appRel/$($v.Name)"
    Write-Host "`n--- Version: $($v.Name) ---" -ForegroundColor Yellow

    $kids = Get-Items -RelUrl $verRel
    Write-Host "    version-root contents:" -ForegroundColor DarkCyan
    foreach ($k in $kids) {
        $t = if (Is-Folder $k) { '[D]' } else { '[F]' }
        Write-Host "      $t $($k.Name)"
    }

    $sccm = $kids | Where-Object { (Is-Folder $_) -and $_.Name -ieq 'SCCM' } | Select-Object -First 1
    if (-not $sccm) { Write-Host "    (no SCCM folder here)" -ForegroundColor DarkGray; continue }

    Write-Host "    inside SCCM/ :" -ForegroundColor Green
    Walk -RelUrl "$verRel/SCCM" -Level 0 -MaxLevel $Depth
}

Write-Host "`nDone. Confirm: does each SCCM/ hold ONE folder named like the full package name?" -ForegroundColor Cyan
