##############################################################
# Package Builder - deployment protection switch (structure + read-only lock).
#
#  -Hide  (team copy): make the folder look clean AND resist accidental edits -
#      * VISIBLE + EDITABLE : the JSON config files (settings / snippets / KnowledgeBase) - users may tune these.
#      * VISIBLE + READ-ONLY: PackageBuilder.exe (the one thing users click; must not be changed).
#      * HIDDEN  + READ-ONLY: EVERYTHING else (PackageBuilder.pak, Lib\, template, ...). So opening the folder
#                             shows ONLY the exe + the JSON files, and the support files can't be casually
#                             edited or deleted. Read-only is applied recursively inside subfolders (Lib\).
#  -Show  (maintainer): unhide + clear read-only on everything.
#
# SECURITY REALITY (read this): the tool's LOGIC is ALREADY tamper-proof - it is AES-256 encrypted inside
# PackageBuilder.pak, so no user can read or change how the tool behaves. The attributes below only PREVENT
# ACCIDENTS on the exposed support files. On a folder a user copies to their OWN machine they are the owner and
# can always clear these attributes; true, enforced lock-down is only possible on a controlled SHARE via NTFS
# permissions (deny-write to users). For a copied-local folder, "encrypted pak + read-only + hidden" is the
# practical ceiling - and it already stops anyone from altering the actual tool.
#
# Run against the DEPLOYED folder:
#   powershell -ExecutionPolicy Bypass -File .\Set-ToolVisibility.ps1 -Hide -Path 'D:\Dist\PackageBuilder'
##############################################################
param([switch]$Hide, [switch]$Show, [string]$Path)

$root = if ($Path) { $Path } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $Hide -and -not $Show) { Write-Host 'Use -Hide (team copy) or -Show (maintainer). Optional: -Path <folder>.'; return }
if (-not (Test-Path -LiteralPath $root)) { Write-Host "Folder not found: $root" -ForegroundColor Red; return }

# JSON config files stay VISIBLE + EDITABLE. The exe stays VISIBLE (but read-only). Everything else is HIDDEN + read-only.
$editable = @('settings.json', 'snippets.json', 'KnowledgeBase.Recommend.json')
$exeNames = @('PackageBuilder.exe', 'PackageBuilder.ps1')   # the launcher stays visible (ps1 only if no exe yet)

function Set-ReadOnlyRecursive([string]$ItemPath, [bool]$On) {
    if (Test-Path -LiteralPath $ItemPath -PathType Container) {
        Get-ChildItem -LiteralPath $ItemPath -Recurse -File -Force -ErrorAction SilentlyContinue |
            ForEach-Object { try { $_.IsReadOnly = $On } catch {} }
    } else {
        try { (Get-Item -LiteralPath $ItemPath -Force).IsReadOnly = $On } catch {}
    }
}
function Set-Hidden($Item, [bool]$On) {
    try {
        if ($On) { $Item.Attributes = $Item.Attributes -bor  [IO.FileAttributes]::Hidden }
        else     { $Item.Attributes = $Item.Attributes -band (-bnot [IO.FileAttributes]::Hidden) }
    } catch {}
}

foreach ($item in (Get-ChildItem -LiteralPath $root -Force)) {
    if ($item.Name -eq 'Set-ToolVisibility.ps1') { continue }   # never hide/lock this helper itself
    if ($Show) {
        Set-Hidden $item $false
        Set-ReadOnlyRecursive $item.FullName $false
        continue
    }
    # -Hide
    if ($item.Name -in $editable) {
        Set-Hidden $item $false                                  # visible
        Set-ReadOnlyRecursive $item.FullName $false              # editable
    } elseif ($item.Name -in $exeNames) {
        Set-Hidden $item $false                                  # visible
        Set-ReadOnlyRecursive $item.FullName $true               # read-only (still runs)
    } else {
        Set-Hidden $item $true                                   # hide from Explorer FIRST (on the cached object)...
        Set-ReadOnlyRecursive $item.FullName $true               # ...then lock (fresh Get-Item ORs read-only onto Hidden;
                                                                 #    doing it the other way round clobbers read-only)
    }
}

# Report the resulting VISIBLE top-level (what a user sees in Explorer's default view).
$seen = @(Get-ChildItem -LiteralPath $root -Force | Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::Hidden) } | ForEach-Object { $_.Name })
$mode = if ($Hide) { 'HIDE + LOCK' } else { 'SHOW (all visible + writable)' }
Write-Host "Done ($mode) on: $root" -ForegroundColor Green
Write-Host ("Visible to users: " + ($seen -join ', '))
