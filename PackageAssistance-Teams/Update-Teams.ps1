# ==============================================================================
#  Refresh the TEAM copies from the source folders.                  (maintainer)
# ==============================================================================
#  Source (edit here)            Team copy (give this to the team)
#    GPF-PackageAssistance\  -->   PackageAssistance-Teams\GPF_PackageAssistance\
#    PAG-PackageAssistance\  -->   PackageAssistance-Teams\PAG_PackageAssistance\
#    MTB-PackageAssistance\  -->   PackageAssistance-Teams\MTB_PackageAssistance\
#
#  For each brand: run Pack-Engine.ps1 (merges every .ps1 into PackageAssistance.pak),
#  then copy the pak + the sidecar data files (settings, snippets, knowledge base) and
#  mirror Lib\. The loader exe is never rebuilt - the team keeps running the same exe and
#  picks up the new pak automatically.
#
#    .\Update-Teams.ps1              all three brands
#    .\Update-Teams.ps1 -Brand GPF   one brand
#    .\Update-Teams.ps1 -NoPack      copy only (pak already built)
# ==============================================================================
[CmdletBinding()]
param([ValidateSet('GPF','PAG','MTB','All')][string]$Brand = 'All', [switch]$NoPack)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$brands = if ($Brand -eq 'All') { 'GPF','PAG','MTB' } else { @($Brand) }
foreach ($b in $brands) {
    $src = Join-Path $repo "$b-PackageAssistance"
    $dst = Join-Path $PSScriptRoot "$b`_PackageAssistance"
    if (-not (Test-Path $src)) { throw "source folder missing: $src" }
    if (-not (Test-Path $dst)) { throw "team folder missing: $dst (create it once with exe + exe.config + PsExec.exe)" }
    Write-Host "== $b" -ForegroundColor Cyan
    if (-not $NoPack) {
        Push-Location $src
        try { & powershell -NoProfile -ExecutionPolicy Bypass -File .\Pack-Engine.ps1 | Select-String 'Packed' | ForEach-Object { Write-Host "   $($_.Line)" } }
        finally { Pop-Location }
    }
    foreach ($f in 'PackageAssistance.pak','settings.json','snippets.json','KnowledgeBase.Recommend.json') {
        $s = Join-Path $src $f; if (Test-Path $s) { Copy-Item $s (Join-Path $dst $f) -Force; Write-Host "   copied $f" }
    }
    # Lib\ (templates, modules) - the source folder spells it 'lib' or 'Lib'; the team copy is 'Lib'
    $lib = @(Get-ChildItem $src -Directory | Where-Object { $_.Name -ieq 'lib' })[0]
    if ($lib) { & robocopy $lib.FullName (Join-Path $dst 'Lib') /E /NFL /NDL /NJH /NJS /NP | Out-Null; Write-Host "   Lib mirrored" }
    $same = (Get-FileHash (Join-Path $src 'PackageAssistance.pak')).Hash -eq (Get-FileHash (Join-Path $dst 'PackageAssistance.pak')).Hash
    Write-Host ("   pak in team folder matches source: {0}" -f $same) -ForegroundColor $(if ($same) { 'Green' } else { 'Red' })
}
