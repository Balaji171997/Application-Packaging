# Make Claude Code's project memory live INSIDE this repo, so it travels with git across machines.
#
# Claude Code keeps per-project memory at:   %USERPROFILE%\.claude\projects\<key>\memory
# where <key> is the working directory with ':' and '\' turned into '-'.
# This script points that folder at  <repo>\claude-memory  via a directory junction, so every memory Claude
# writes lands in the repo and nothing is lost when you change machine.
#
#   .\Setup-ClaudeMemory.ps1 -WorkingDir 'C:\Users\AW140\Downloads\files'
#   .\Setup-ClaudeMemory.ps1 -WorkingDir 'D:\Work\Application-Packaging\files'   # on a new machine
#
# Safe to re-run. If the profile folder already holds memories (e.g. Claude ran before this script), they are
# MERGED into the repo copy first, newer file winning, so neither side is thrown away.

param(
    [string]$WorkingDir = $PSScriptRoot,           # default: this repo folder - open Claude Code here and it just works
    [string]$RepoRoot = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$repoMem = Join-Path $RepoRoot 'claude-memory'
if (-not (Test-Path -LiteralPath $repoMem)) { New-Item $repoMem -ItemType Directory -Force | Out-Null }

# Claude Code's key: 'C:\Users\x\y' -> 'C--Users-x-y'
$key     = ($WorkingDir.TrimEnd('\') -replace '[:\\]', '-')
$projDir = Join-Path $env:USERPROFILE ".claude\projects\$key"
$profMem = Join-Path $projDir 'memory'

Write-Host "working dir : $WorkingDir"
Write-Host "profile key : $key"
Write-Host "profile path: $profMem"
Write-Host "repo memory : $repoMem"

if (-not (Test-Path -LiteralPath $projDir)) { New-Item $projDir -ItemType Directory -Force | Out-Null }

if (Test-Path -LiteralPath $profMem) {
    $item = Get-Item -LiteralPath $profMem -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        if ("$($item.Target)" -ieq $repoMem) { Write-Host "`nAlready linked to this repo - nothing to do." -ForegroundColor Green; return }
        Write-Host "`nExisting link points elsewhere ($($item.Target)) - replacing it."
        Remove-Item -LiteralPath $profMem -Force        # removes the link only, never the target
    } else {
        # A real folder with memories in it: merge into the repo, newer file wins, then keep a dated backup.
        $files = @(Get-ChildItem -LiteralPath $profMem -File)
        $merged = 0
        foreach ($f in $files) {
            $dst = Join-Path $repoMem $f.Name
            if (-not (Test-Path -LiteralPath $dst) -or ($f.LastWriteTimeUtc -gt (Get-Item -LiteralPath $dst).LastWriteTimeUtc)) {
                Copy-Item -LiteralPath $f.FullName -Destination $dst -Force; $merged++
            }
        }
        $bak = "$profMem.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Rename-Item -LiteralPath $profMem -NewName (Split-Path $bak -Leaf)
        Write-Host "`nMerged $merged newer/missing file(s) from the profile folder into the repo."
        Write-Host "Old profile folder kept as: $bak"
    }
}

New-Item -ItemType Junction -Path $profMem -Target $repoMem | Out-Null
$n = (Get-ChildItem -LiteralPath $profMem -File).Count
Write-Host "`nLinked. Claude Code now reads and writes $n memory file(s) straight from the repo." -ForegroundColor Green
Write-Host "Commit claude-memory\ with the rest of the repo and it follows you to any machine."
