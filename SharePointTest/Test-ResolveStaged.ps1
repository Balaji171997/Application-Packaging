# Phase 2d: PROOF OF THE SEAM.
# Load PB's own engine (read-only, nothing modified) and run its real Resolve-Source against a folder that was
# staged FROM SHAREPOINT. If PB resolves the installer here exactly as it would from the UNC repo, the whole
# integration reduces to "hand PB a different path".
#
#   .\Test-ResolveStaged.ps1 -StagedPath 'C:\temp\PackageBuilder\Temp\sp_source_152fb780'

param(
    [Parameter(Mandatory)][string]$StagedPath,
    [string]$PBRoot = 'C:\Users\AW140\Downloads\Application-Packaging\files'
)

if (-not (Test-Path -LiteralPath $StagedPath)) { Write-Host "Staged path not found: $StagedPath" -ForegroundColor Red; return }

# PB's engine modules. Dot-sourced in the same order Build-Exe.ps1 packs them.
foreach ($m in @('Core.ps1','Source.ps1')) {
    $p = Join-Path $PBRoot $m
    if (-not (Test-Path -LiteralPath $p)) { Write-Host "Missing PB module: $p" -ForegroundColor Red; return }
    . $p
}
Write-Host "Loaded PB engine from $PBRoot" -ForegroundColor DarkGray

if (-not (Get-Command Resolve-Source -ErrorAction SilentlyContinue)) {
    Write-Host "Resolve-Source not available after loading - check module list." -ForegroundColor Red; return
}

Write-Host "`nRunning PB's Resolve-Source against the SharePoint-staged folder:" -ForegroundColor Cyan
Write-Host "  $StagedPath`n" -ForegroundColor DarkGray

$res = Resolve-Source -RootPath $StagedPath

if (-not $res) { Write-Host "Resolve-Source returned nothing." -ForegroundColor Red; return }

Write-Host "Result:" -ForegroundColor Green
foreach ($k in @($res.Keys | Sort-Object)) {
    $v = $res[$k]
    if ($null -eq $v) { Write-Host ("  {0,-18}: <null>" -f $k); continue }
    if ($v -is [System.Collections.IEnumerable] -and $v -isnot [string]) {
        $items = @($v)
        Write-Host ("  {0,-18}: {1} item(s)" -f $k, $items.Count)
        foreach ($i in $items) {
            $desc = if ($i.FullName) { $i.FullName } elseif ($i.Name) { $i.Name } else { "$i" }
            Write-Host "      - $desc" -ForegroundColor DarkGray
        }
    } else {
        Write-Host ("  {0,-18}: {1}" -f $k, $v)
    }
}

$ok = $res.Valid -and @($res.Installers).Count -gt 0
Write-Host "`nVERDICT: $(if ($ok) { 'PB resolved the SharePoint-staged source successfully.' } else { 'PB did NOT resolve a usable installer here.' })" -ForegroundColor $(if ($ok) { 'Green' } else { 'Yellow' })
