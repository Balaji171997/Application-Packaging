# Refresh this SharePoint variant from the MTB source (Application-Packaging\files) WITHOUT hand-merging.
#
# This tool is a DEPLOYMENT VARIANT, not a code fork: every engine file is identical to MTB's. Only four things
# are ours, and they are preserved here:
#     SharePoint.ps1            our module (MTB has no equivalent)
#     lib\PnP.PowerShell\       our module (MTB has no equivalent)
#     settings.json             ours - has the SharePoint block, SharePoint.Enabled = true
#     the 2 wiring lines        Build-Exe.ps1 $enginiFiles + GUI.ps1 dot-source
#
# The two wiring lines are re-applied automatically after the copy, so a fresh MTB engine never silently drops
# SharePoint support. Run this after ANY change to files\, then re-pack.
#
#   .\Sync-FromMTB.ps1            # show what would change
#   .\Sync-FromMTB.ps1 -Apply     # actually sync

param(
    [string]$MtbRoot = 'C:\Users\AW140\Downloads\Application-Packaging\files',
    [switch]$Apply
)

$here = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if (-not (Test-Path -LiteralPath $MtbRoot)) { Write-Host "MTB source not found: $MtbRoot" -ForegroundColor Red; return }

# Never overwritten from MTB.
$ours = @('SharePoint.ps1','settings.json','Sync-FromMTB.ps1')

Write-Host "MTB source : $MtbRoot"
Write-Host "This tool  : $here"
Write-Host "Preserving : $($ours -join ', ')`n"

$mode = if ($Apply) { '' } else { '/L' }      # /L = list only
$xf = $ours | ForEach-Object { @('/XF', $_) }
$args = @($MtbRoot, $here, '/E', '/XD', '.claude', 'PnP.PowerShell', '/NJH', '/NJS', '/NP', '/R:1', '/W:1') + $xf
if ($mode) { $args += $mode }

& robocopy @args | Where-Object { $_ -match '\S' } | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }

if (-not $Apply) { Write-Host "`n(dry run - nothing changed. Re-run with -Apply.)" -ForegroundColor Yellow; return }

# --- re-apply the two wiring lines, in case a fresh MTB copy overwrote them --------------------------------
$changed = @()

$be = Join-Path $here 'Build-Exe.ps1'
$t  = [IO.File]::ReadAllText($be)
if ($t -notmatch "'SharePoint\.ps1'") {
    $t = $t -replace "('PSADT_V3toV4_Mappings\.ps1')\)", "`$1,`n                 # SharePoint variant: MUST stay LAST - it captures the originals it overrides.`n                 'SharePoint.ps1')"
    [IO.File]::WriteAllText($be, $t)
    $changed += 'Build-Exe.ps1 ($enginiFiles)'
}

$gui = Join-Path $here 'GUI.ps1'
$t = [IO.File]::ReadAllText($gui)
if ($t -notmatch '\.\s+"\$root\\SharePoint\.ps1"') {
    $t = $t -replace '(\.\s+"\$root\\PSADT_V3toV4_Mappings\.ps1"[^\r\n]*)', "`$1`r`n    # SharePoint variant: LAST on purpose - overrides Source/Predecessor lookups.`r`n    . `"`$root\SharePoint.ps1`""
    [IO.File]::WriteAllText($gui, $t)
    $changed += 'GUI.ps1 (dot-source)'
}

# GUI.ps1 has a SECOND, easily-missed loader: the background runspace in Invoke-PBAsync. Find-SourceFolder and
# Get-PredecessorCandidates actually execute in there, so if its dev-mode list lacks SharePoint.ps1 the tool
# quietly uses the UNC originals and looks like SharePoint was never wired up at all.
$t = [IO.File]::ReadAllText($gui)
if ($t -notmatch 'Test-Path "\$\(\$p\.root\)\\SharePoint\.ps1"') {
    $t = $t -replace '(\.\s+"\$\(\$p\.root\)\\PSADT_V3toV4_Mappings\.ps1"[^\r\n]*)', "`$1`r`n                if (Test-Path `"`$(`$p.root)\SharePoint.ps1`") { . `"`$(`$p.root)\SharePoint.ps1`" }"
    [IO.File]::WriteAllText($gui, $t)
    $changed += 'GUI.ps1 (Invoke-PBAsync runspace)'
}

# Pack-Engine.ps1 keeps its OWN engine list and is what actually builds the SHIPPED .pak. Miss this one and the
# release silently ships without SharePoint support - the tool runs UNC-only with no error at all.
$pe = Join-Path $here 'Pack-Engine.ps1'
$t = [IO.File]::ReadAllText($pe)
if ($t -notmatch "'SharePoint\.ps1'") {
    $t = $t -replace "('PSADT_V3toV4_Mappings\.ps1')\)", "`$1,`r`n                 # SharePoint variant: MUST stay LAST - it captures the originals it overrides.`r`n                 'SharePoint.ps1')"
    [IO.File]::WriteAllText($pe, $t)
    $changed += 'Pack-Engine.ps1 ($engineFiles)'
}

if ($changed) { Write-Host "`nRe-applied wiring: $($changed -join ', ')" -ForegroundColor Green }
else { Write-Host "`nWiring already present." -ForegroundColor Green }

Write-Host "Sync done. Re-pack with .\Build-Exe.ps1" -ForegroundColor Cyan
