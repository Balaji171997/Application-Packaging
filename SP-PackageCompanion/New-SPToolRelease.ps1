# Build the distributable ZIP for the SharePoint-linked Package Companion.
# Users download it from SharePoint, unblock, extract, run. No UNC, no Intune, no installer.
#
#   .\New-SPToolRelease.ps1                 # full release  (~343 MB raw)
#   .\New-SPToolRelease.ps1 -NoSccm         # lean release  (~116 MB raw - drops the 227 MB ConfigMgr module)
#   .\New-SPToolRelease.ps1 -SkipPack       # don't re-pack the .pak first (use the existing one)
#
# -NoSccm is for packagers who cannot reach the UNC shares at all: SCCM publishing needs a UNC content share
# anyway, so the ConfigMgr module is dead weight for them. Everything else (build, Intune publish) still works.

param(
    [string]$OutDir  = 'C:\temp\PBRelease',
    [string]$Version = (Get-Date -Format 'yyyy.MM.dd'),
    [switch]$NoSccm,
    [switch]$SkipPack
)

$root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$ErrorActionPreference = 'Stop'

# ---- 1. re-pack the engine so the .pak actually contains SharePoint.ps1 -----------------------
if (-not $SkipPack) {
    Write-Host 'Packing engine (Pack-Engine.ps1)...' -ForegroundColor Cyan
    & (Join-Path $root 'Pack-Engine.ps1')
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Pack-Engine failed (exit $LASTEXITCODE)" }
}
$pak = Join-Path $root 'PackageCompanion.pak'
if (-not (Test-Path -LiteralPath $pak)) { throw "No PackageCompanion.pak at $pak" }

# Guard: a .pak built before the wiring fix would silently ship a UNC-only tool. Cheap to check, expensive to miss.
if (-not (Select-String -Path (Join-Path $root 'Pack-Engine.ps1') -Pattern "'SharePoint\.ps1'" -Quiet)) {
    throw "Pack-Engine.ps1 does not include SharePoint.ps1 - the release would have NO SharePoint support."
}

# Guard: the exe MUST be the thin Loader that reads PackageCompanion.pak at runtime. The other exe in this repo is
# a ps2exe build with a July engine baked INSIDE it - it ignores the .pak completely, so repacking changes nothing
# and the tool silently behaves like the old UNC-only build. That shipped in two releases before it was caught.
$exe = Join-Path $root 'PackageCompanion.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw "PackageCompanion.exe not found at $exe" }
$exeBytes = [IO.File]::ReadAllBytes($exe)
$exeText  = [Text.Encoding]::Unicode.GetString($exeBytes) + [Text.Encoding]::ASCII.GetString($exeBytes)
if ($exeText -notmatch 'PackageCompanion\.pak') {
    throw ("PackageCompanion.exe ({0:N0} KB) does not reference PackageCompanion.pak - it looks like a ps2exe build " -f ((Get-Item $exe).Length/1KB)) +
          "with the engine baked in, which would IGNORE the .pak. Copy the thin Loader exe (~54 KB) over it first."
}
Write-Host ("Loader exe verified ({0:N0} KB, reads the .pak)." -f ((Get-Item $exe).Length/1KB)) -ForegroundColor Green

# ---- 2. assemble a clean distribution folder --------------------------------------------------
$name  = "PackageCompanion-SharePoint-$Version" + $(if ($NoSccm) { '-nosccm' } else { '' })
$stage = Join-Path $OutDir $name
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -Path $stage -ItemType Directory -Force | Out-Null

# Exactly what the portable copy ships - sources and dev scripts are NOT shipped.
$files = @('PackageCompanion.exe','PackageCompanion.exe.config','PackageCompanion.pak',
           'settings.json','snippets.json','KnowledgeBase.Recommend.json','PsExec.exe')
foreach ($f in $files) {
    $p = Join-Path $root $f
    if (Test-Path -LiteralPath $p) { Copy-Item -LiteralPath $p -Destination $stage -Force }
    else { Write-Host "  (missing, skipped): $f" -ForegroundColor DarkYellow }
}

Write-Host 'Copying Lib...' -ForegroundColor Cyan
$xd = @()
if ($NoSccm) { $xd += @('/XD', (Join-Path $root 'lib\ConfigurationManagerPrelive')) }
$rcArgs = @((Join-Path $root 'lib'), (Join-Path $stage 'Lib'), '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/R:1', '/W:1') + $xd
& robocopy @rcArgs | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed copying Lib (exit $LASTEXITCODE)" }

# ---- 3. version marker + first-run instructions -----------------------------------------------
$sp = (Get-Content (Join-Path $root 'settings.json') -Raw | ConvertFrom-Json).SharePoint
@"
Package Companion - SharePoint edition
Version   : $Version
Built     : $(Get-Date -Format 'yyyy-MM-dd HH:mm')
Flavour   : $(if ($NoSccm) { 'lean (no ConfigMgr module - cannot publish to SCCM)' } else { 'full' })
Site      : $($sp.SiteUrl)
Library   : $($sp.Library)
"@ | Set-Content -LiteralPath (Join-Path $stage 'VERSION.txt') -Encoding UTF8

@"
Package Companion - SharePoint edition - READ THIS FIRST
======================================================

1. UNBLOCK THE ZIP *BEFORE* EXTRACTING.  This matters - skip it and the tool will misbehave.
   Right-click the .zip -> Properties -> tick "Unblock" (bottom right) -> OK.  Then extract.

   Windows tags every file from a downloaded zip as "from the internet". The tool loads several
   DLLs (the script editor, the SharePoint module); those tags stop them loading. Unblocking the
   ZIP first means the extracted files are clean. If you already extracted without unblocking,
   just run Unblock-Tool.cmd from the extracted folder.

2. Extract the whole folder somewhere LOCAL, e.g. C:\Tools\PackageCompanion.
   Do not run it from inside the .zip, and do not run it from a network drive.

3. Run PackageCompanion.exe.
   The first time it touches SharePoint you will get a Microsoft sign-in prompt. Sign in with your
   normal work account. It reads the package sources you already have access to - nothing more.

WHAT THIS VERSION DOES DIFFERENTLY
   Sources and predecessors come from SharePoint:
       $($sp.SiteUrl)
       library: $($sp.Library)
   The old UNC shares are optional. If you have access they are still searched for extra
   predecessors; if you do not, they are skipped silently and everything works from SharePoint.
$(if ($NoSccm) { "
   THIS IS THE LEAN BUILD: the ConfigMgr module is not included, so SCCM publishing is unavailable.
   Building packages and publishing to Intune work normally.
" })
UPDATING
   There is no auto-update. When a new version is announced, download the new zip and replace the
   folder. Your settings.json is overwritten, so if you changed anything in it, keep a copy.

TROUBLE
   "PnP module not found"        -> the Lib folder did not extract fully; re-extract the whole zip.
   Sign-in loops or is refused   -> your account may not have access to the SharePoint library yet.
   Something looks blocked       -> run Unblock-Tool.cmd, then restart the tool.
"@ | Set-Content -LiteralPath (Join-Path $stage 'README-FIRST.txt') -Encoding UTF8

# Fallback for people who extracted before unblocking.
@"
@echo off
echo Removing the "downloaded from the internet" tag from every file here...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse -File | Unblock-File"
echo Done. You can start PackageCompanion.exe now.
pause
"@ | Set-Content -LiteralPath (Join-Path $stage 'Unblock-Tool.cmd') -Encoding ASCII

# ---- 4. zip -----------------------------------------------------------------------------------
$zip = Join-Path $OutDir "$name.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Write-Host 'Compressing (this takes a minute)...' -ForegroundColor Cyan
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)

$raw = [math]::Round((Get-ChildItem $stage -Recurse -File | Measure-Object Length -Sum).Sum / 1MB)
$zmb = [math]::Round((Get-Item $zip).Length / 1MB)
Write-Host "`nRelease ready" -ForegroundColor Green
Write-Host "  folder : $stage  ($raw MB)"
Write-Host "  zip    : $zip  ($zmb MB)"
Write-Host "`nUpload the .zip to SharePoint, and tell people to UNBLOCK IT BEFORE EXTRACTING." -ForegroundColor Yellow
