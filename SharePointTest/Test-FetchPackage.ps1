# Phase 2c: actually DOWNLOAD from SharePoint into a local staging folder.
# Separate file - nothing existing is modified. Two modes:
#
#   -Mode Source        fetch <Version>/source + <Version>/doc          (what PB's Find-SourceFolder must return)
#   -Mode Predecessor   fetch ONLY what PB reads from a predecessor:
#                         Deploy-Application.ps1 / Invoke-AppDeployToolkit.ps1
#                         Content/SupportFiles/**        (Active Setup stubs)
#                         *.mst                          ("Match predecessor MST")
#                         Icons/**
#                       and SKIPS Content/Files/*.msi|*.exe - the old installer payload PB never reads.
#                       Use -Full to take everything instead.
#
#   .\Test-FetchPackage.ps1 -PkgName '3Dconnexion_3DxWare_x64_10.9.1.650-0004_MUL' -Mode Predecessor
#   .\Test-FetchPackage.ps1 -PkgName '3Dconnexion_3DxWare_x64_10.9.1.650-0003_MUL' -Mode Source
#   ... add -WhatIf to list what WOULD download (with sizes) without downloading.

param(
    [Parameter(Mandatory)][string]$PkgName,
    [ValidateSet('Source','Predecessor')][string]$Mode = 'Source',
    [string]$DestRoot = 'C:\temp\PackageBuilder\Temp',
    [switch]$Full,
    [switch]$WhatIf
)

Import-Module (Join-Path $PSScriptRoot 'PnP.PowerShell\1.12.0\PnP.PowerShell.psd1') -ErrorAction Stop

$siteUrl    = 'https://manonlineservices.sharepoint.com/sites/SWPackaging'
$clientId   = '28bf2c22-437c-42e7-a4be-e8a0f44a8264'
$sitePath   = '/sites/SWPackaging'          # server-relative prefix Get-PnPFile needs
$libRel     = 'PackageSources'

function Parse-PkgName {
    param([string]$Name)
    $p = '^(?<Vendor>[^_]+)_(?<App>.+)_(?<Arch>x86|x64|x86_64|ALL)_(?<Ver>[^_]+)-(?<Rel>\d{4})_(?<Lang>[\w\-]+)$'
    if ($Name -match $p) {
        return [ordered]@{ Vendor=$Matches.Vendor; App=$Matches.App; Arch=$Matches.Arch
                           Version=$Matches.Ver; Release=[int]$Matches.Rel; RelStr=$Matches.Rel
                           Lang=$Matches.Lang; Matched=$true }
    }
    return [ordered]@{ Matched = $false }
}
function Parse-VersionFolder {
    param([string]$FolderName)
    if ($FolderName -match '^(?<Ver>.+)_(?<Rel>\d{4})$') { return @{ Version=$Matches.Ver; Release=[int]$Matches.Rel; Raw=$FolderName; Valid=$true } }
    return @{ Raw = $FolderName; Valid = $false }
}
function Compare-VersionString {
    param([string]$A, [string]$B)
    $x = @($A -split '[.\-]' | ForEach-Object { $n=0; if ([int]::TryParse($_,[ref]$n)) { $n } else { 0 } })
    $y = @($B -split '[.\-]' | ForEach-Object { $n=0; if ([int]::TryParse($_,[ref]$n)) { $n } else { 0 } })
    for ($i = 0; $i -lt [Math]::Max($x.Count,$y.Count); $i++) {
        $xi = if ($i -lt $x.Count) { $x[$i] } else { 0 }
        $yi = if ($i -lt $y.Count) { $y[$i] } else { 0 }
        if ($xi -lt $yi) { return -1 }; if ($xi -gt $yi) { return 1 }
    }
    return 0
}
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

# Which files matter for a PREDECESSOR. $RelInside is the path under the package folder, e.g. 'Content/SupportFiles/x.ps1'.
function Test-WantPredecessorFile {
    param([string]$RelInside, [string]$FileName)
    if ($Full) { return $true }
    # PAYLOAD - never read by PB, and it hides in places you would not expect: the 3DxWare predecessor keeps a
    # 190 MB installer inside Content\SupportFiles. Exclude by extension first, whatever folder it sits in.
    if ($FileName -imatch '\.(exe|msi|msp|msu|zip|7z|rar|cab|iso|img|wim|vhdx?|msix|appx)$') { return $false }
    if ($FileName -ieq 'Deploy-Application.ps1' -or $FileName -ieq 'Invoke-AppDeployToolkit.ps1') { return $true }
    if ($FileName -imatch '\.mst$')  { return $true }
    if ($FileName -imatch '\.ico$')  { return $true }
    if ($RelInside -imatch '(^|/)SupportFiles/') { return $true }   # ActiveSetup stubs + their config files
    if ($RelInside -imatch '(^|/)Icons/')        { return $true }
    return $false
}

# Recursively collect files under a site-relative folder. Returns @(@{ServerUrl;RelInside;Name;Size}).
function Get-FilesRecursive {
    param([string]$RelUrl, [string]$RelInside = '')
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($it in (Get-Items -RelUrl $RelUrl)) {
        $childInside = if ($RelInside) { "$RelInside/$($it.Name)" } else { $it.Name }
        if (Is-Folder $it) {
            foreach ($f in (Get-FilesRecursive -RelUrl "$RelUrl/$($it.Name)" -RelInside $childInside)) { $out.Add($f) }
        } else {
            if ($it.Name -like '~$*') { continue }        # Word lock-file leftovers
            $size = 0; try { $size = [int64]$it.Length } catch {}
            $out.Add([pscustomobject]@{
                ServerUrl = "$sitePath/$RelUrl/$($it.Name)"
                RelInside = $childInside
                Name      = $it.Name
                Size      = $size
            })
        }
    }
    return $out.ToArray()
}

function Format-Size {
    param([int64]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N1} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

# ---------------------------------------------------------------- main

$id = Parse-PkgName $PkgName
if (-not $id.Matched) { Write-Host "Unparseable package name: $PkgName" -ForegroundColor Red; return }

Connect-PnPOnline -Url $siteUrl -ClientId $clientId -Interactive

$appRel = "$libRel/$($id.Vendor)/$($id.App)"
Write-Host "`nPackage : $PkgName" -ForegroundColor Cyan
Write-Host "Mode    : $Mode$(if ($Full) { ' (FULL)' })" -ForegroundColor Cyan

# Decide which SharePoint folder we are pulling from.
$fetchFrom = $null
$label     = ''
if ($Mode -eq 'Source') {
    $verFolder = "$($id.Version)_$($id.RelStr)"
    $fetchFrom = "$appRel/$verFolder"
    $label     = $verFolder
    if (-not (Get-Items -RelUrl $fetchFrom)) { Write-Host "Version folder not found: $fetchFrom" -ForegroundColor Red; return }
} else {
    $target = @{ Version = $id.Version; Release = $id.Release }
    $cands = @()
    foreach ($v in (Get-Items -RelUrl $appRel | Where-Object { Is-Folder $_ })) {
        $pv = Parse-VersionFolder $v.Name
        if (-not $pv.Valid) { continue }
        if ((Compare-VerRel -A $pv -B $target) -ge 0) { continue }
        $sccm = @(Get-Items -RelUrl "$appRel/$($v.Name)/SCCM" | Where-Object { Is-Folder $_ })
        if ($sccm.Count -eq 0) { continue }
        $pv.PkgFolder = $sccm[0].Name
        $pv.RelPath   = "$appRel/$($v.Name)/SCCM/$($sccm[0].Name)"
        $cands += ,$pv
    }
    if ($cands.Count -eq 0) { Write-Host "No predecessor found." -ForegroundColor Yellow; return }
    for ($i = 0; $i -lt $cands.Count; $i++) {
        for ($j = $i+1; $j -lt $cands.Count; $j++) {
            if ((Compare-VerRel -A $cands[$i] -B $cands[$j]) -lt 0) { $t=$cands[$i]; $cands[$i]=$cands[$j]; $cands[$j]=$t }
        }
    }
    $fetchFrom = $cands[0].RelPath
    $label     = $cands[0].PkgFolder
    Write-Host "Predecessor: $($cands[0].Raw) -> $($cands[0].PkgFolder)" -ForegroundColor Green
}
Write-Host "From    : $fetchFrom" -ForegroundColor Cyan

# Enumerate, then filter.
Write-Host "`nEnumerating..." -ForegroundColor DarkGray
$all = @()
if ($Mode -eq 'Source') {
    $kids = Get-Items -RelUrl $fetchFrom
    foreach ($sub in @('source','doc')) {
        $hit = $kids | Where-Object { (Is-Folder $_) -and $_.Name -ieq $sub } | Select-Object -First 1
        if ($hit) { $all += Get-FilesRecursive -RelUrl "$fetchFrom/$($hit.Name)" -RelInside $hit.Name }
    }
    if (@($all).Count -eq 0) {
        # "dumped straight into the version folder" case - loose files, minus ticket refs.
        $loose = @($kids | Where-Object { -not (Is-Folder $_) -and $_.Name -notmatch '^RITM\d+\s*\.txt$' -and $_.Name -notlike '~$*' })
        foreach ($f in $loose) {
            $size = 0; try { $size = [int64]$f.Length } catch {}
            $all += [pscustomobject]@{ ServerUrl = "$sitePath/$fetchFrom/$($f.Name)"; RelInside = $f.Name; Name = $f.Name; Size = $size }
        }
    }
} else {
    $everything = Get-FilesRecursive -RelUrl $fetchFrom
    $all = @($everything | Where-Object { Test-WantPredecessorFile -RelInside $_.RelInside -FileName $_.Name })
    $skipped = @($everything).Count - @($all).Count
    if ($skipped -gt 0) {
        $skippedBytes = (@($everything | Where-Object { -not (Test-WantPredecessorFile -RelInside $_.RelInside -FileName $_.Name) }) |
                         Measure-Object -Property Size -Sum).Sum
        Write-Host "Skipping $skipped file(s), $(Format-Size ([int64]$skippedBytes)) - payload PB never reads (use -Full to include)." -ForegroundColor DarkGray
    }
}

if (@($all).Count -eq 0) { Write-Host "Nothing to fetch." -ForegroundColor Yellow; return }
$total = [int64](($all | Measure-Object -Property Size -Sum).Sum)
Write-Host "$(@($all).Count) file(s), $(Format-Size $total)" -ForegroundColor Green

$stage = Join-Path $DestRoot ("sp_{0}_{1}" -f $Mode.ToLower(), ([guid]::NewGuid().ToString('N').Substring(0,8)))

if ($WhatIf) {
    Write-Host "`n[WhatIf] would download into: $stage" -ForegroundColor Yellow
    $all | ForEach-Object { Write-Host ("   {0,10}  {1}" -f (Format-Size $_.Size), $_.RelInside) }
    return
}

New-Item -Path $stage -ItemType Directory -Force | Out-Null
Write-Host "`nDownloading -> $stage" -ForegroundColor Cyan

$n = 0; $failed = 0
foreach ($f in $all) {
    $n++
    $subDir = Split-Path $f.RelInside -Parent
    $target = if ($subDir) { Join-Path $stage $subDir } else { $stage }
    # -LiteralPath: names here really do contain brackets, e.g. "...for MAN [3dxWare].docx", and [ ] are
    # wildcards to a non-literal path - Test-Path would report $false for a folder that exists.
    if (-not (Test-Path -LiteralPath $target)) { New-Item -Path $target -ItemType Directory -Force | Out-Null }
    Write-Progress -Activity "Downloading from SharePoint" -Status "$n/$(@($all).Count)  $($f.RelInside)" -PercentComplete (($n / @($all).Count) * 100)
    try {
        Get-PnPFile -Url $f.ServerUrl -Path $target -FileName $f.Name -AsFile -Force -ErrorAction Stop
    } catch {
        Write-Host "   FAILED $($f.RelInside): $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }
}
Write-Progress -Activity "Downloading from SharePoint" -Completed

# Strip Mark-of-the-Web so downloaded installers launch cleanly (same reason PB unblocks extracted zips).
Get-ChildItem -LiteralPath $stage -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    try { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue } catch {}
}

Write-Host "`nDone. $($n - $failed)/$n file(s) downloaded$(if ($failed) { ", $failed FAILED" })." -ForegroundColor $(if ($failed) { 'Yellow' } else { 'Green' })
Write-Host "STAGED AT: $stage" -ForegroundColor Green
Write-Host "(this local path is what PB's Find-SourceFolder / predecessor lookup would return)" -ForegroundColor DarkGray
