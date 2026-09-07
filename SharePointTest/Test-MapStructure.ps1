# Phase 1: map the real PackageSources folder structure (Vendor / App / Version / ...).
# Read-only. Prints what it finds so we can confirm the layout before writing matching logic.
# Limits how much it walks so a first run doesn't try to enumerate the whole library.

param(
    [int]$MaxVendors = 3,     # how many Vendor folders to sample
    [int]$MaxAppsPerVendor = 3,
    [int]$MaxVersionsPerApp = 3
)

Import-Module (Join-Path $PSScriptRoot 'PnP.PowerShell\1.12.0\PnP.PowerShell.psd1') -ErrorAction Stop

$siteUrl  = 'https://manonlineservices.sharepoint.com/sites/SWPackaging'
$clientId = '28bf2c22-437c-42e7-a4be-e8a0f44a8264'   # PnP Management Shell - already trusted in this tenant
$libRel   = 'PackageSources'

Connect-PnPOnline -Url $siteUrl -ClientId $clientId -Interactive

function Show-Level {
    param([string]$RelUrl, [int]$Depth, [int]$MaxItems)
    $items = Get-PnPFolderItem -FolderSiteRelativeUrl $RelUrl -ErrorAction SilentlyContinue
    $indent = '  ' * $Depth
    $i = 0
    foreach ($it in $items) {
        $isFolder = $it.PSObject.TypeNames -match 'Folder' -or $it.GetType().Name -eq 'Folder'
        $mark = if ($isFolder) { '[D]' } else { '[F]' }
        Write-Host "$indent$mark $($it.Name)"
        $i++
        if ($i -ge $MaxItems) {
            Write-Host "$indent... ($($items.Count) total, showing first $MaxItems)" -ForegroundColor DarkGray
            break
        }
    }
    return $items
}

Write-Host "`n=== Vendor folders (top of $libRel) ===" -ForegroundColor Cyan
$vendors = Show-Level -RelUrl $libRel -Depth 0 -MaxItems $MaxVendors

foreach ($v in ($vendors | Select-Object -First $MaxVendors)) {
    $vendorRel = "$libRel/$($v.Name)"
    Write-Host "`n--- Vendor: $($v.Name) ---" -ForegroundColor Yellow
    $apps = Show-Level -RelUrl $vendorRel -Depth 1 -MaxItems $MaxAppsPerVendor

    foreach ($a in ($apps | Select-Object -First $MaxAppsPerVendor)) {
        $appRel = "$vendorRel/$($a.Name)"
        Write-Host "  App: $($a.Name)" -ForegroundColor Green
        $versions = Show-Level -RelUrl $appRel -Depth 2 -MaxItems $MaxVersionsPerApp

        foreach ($ver in ($versions | Select-Object -First $MaxVersionsPerApp)) {
            $verRel = "$appRel/$($ver.Name)"
            Write-Host "    Version: $($ver.Name)" -ForegroundColor Magenta
            $verItems = Show-Level -RelUrl $verRel -Depth 3 -MaxItems 10

            # One level deeper into 'source' and 'doc' specifically, if present.
            foreach ($sub in @('source','doc')) {
                $hit = $verItems | Where-Object { $_.Name -eq $sub }
                if ($hit) {
                    Write-Host "      -> inside '$sub':" -ForegroundColor DarkCyan
                    Show-Level -RelUrl "$verRel/$sub" -Depth 4 -MaxItems 15 | Out-Null
                }
            }
        }
    }
}

Write-Host "`nDone. Review the [D]/[F] layout above against what you expect (flat files vs Source/Documents subfolders)." -ForegroundColor Cyan
