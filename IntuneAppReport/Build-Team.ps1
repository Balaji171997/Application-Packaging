##############################################################
# Intune App Monitor - builds the TEAM folder (maintainer only; not shipped).
#
#   IntuneAppReport.ps1 + lib\Intune.ps1 + lib\Xlsx.ps1  ->  ONE IntuneAppMonitor.exe  (ps2exe: STA, no console, own icon)
#
#   Team folder (default: Application-Packaging\Intune App Monitor, next to this source folder):
#     IntuneAppMonitor.exe      double-click to launch - no PowerShell window, no .ps1 anywhere
#     settings.json
#     lib\PowerShell Module\    MSAL.PS + IntuneWin32App
#     Data\                     the history record (AuditCache, ActivityFeed, people, ChangeLog, latest snapshot)
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\Build-Team.ps1 [-OutDir <folder>] [-NoData] [-RefreshData]
#   Re-running replaces ONLY the program (exe, settings, lib). An existing team Data\ is never touched
#   (-RefreshData copies the source record over it); people.json names are merged both ways every run.
##############################################################
param([string]$OutDir, [switch]$NoData, [switch]$RefreshData)

$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $OutDir) { $OutDir = Join-Path (Split-Path $root -Parent) 'Intune App Monitor' }    # sibling of this source folder, inside Application-Packaging
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
function Read-Source { param([string]$Path) if (-not (Test-Path $Path)) { throw "Missing: $Path" }; return ([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)).TrimStart([char]0xFEFF) }

# --- merge: param(...) stays the first statement; the two libs go in right behind it (base64 = quoting-proof) -----------
$libs = (Read-Source (Join-Path $root 'lib\Intune.ps1')) + "`n`n" + (Read-Source (Join-Path $root 'lib\Xlsx.ps1'))
$main = Read-Source (Join-Path $root 'IntuneAppReport.ps1')
$m = [regex]::Match($main, '(?s)^(?<head>.*?\r?\nparam\([^\r\n]*\)\r?\n)(?<rest>.*)$')
if (-not $m.Success) { throw 'IntuneAppReport.ps1: could not find the param(...) line.' }
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($libs))
$merged = $m.Groups['head'].Value +
          "`$script:BuildStamp = '$stamp'`n" +
          "`$script:PackedLibs = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64'))`n" +
          ". ([scriptblock]::Create(`$script:PackedLibs))`n" +
          $m.Groups['rest'].Value
$tok = $null; $errs = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($merged, [ref]$tok, [ref]$errs)
if ($errs.Count) { throw "Merged source has $($errs.Count) parse error(s) - first: L$($errs[0].Extent.StartLineNumber) $($errs[0].Message)" }

# --- icon: generated once (dark tile, three lifecycle-coloured bars) ------------------------------------------------------
$ico = Join-Path $root 'lib\IntuneAppMonitor.ico'
if (-not (Test-Path $ico)) {
    Add-Type -AssemblyName System.Drawing
    $pngs = foreach ($size in 256, 48, 32, 16) {
        $bmp = New-Object Drawing.Bitmap($size, $size, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'; $g.Clear([Drawing.Color]::Transparent)
        $r = [int]($size * 0.22); $path = New-Object Drawing.Drawing2D.GraphicsPath
        $path.AddArc(0, 0, $r, $r, 180, 90); $path.AddArc($size - $r - 1, 0, $r, $r, 270, 90); $path.AddArc($size - $r - 1, $size - $r - 1, $r, $r, 0, 90); $path.AddArc(0, $size - $r - 1, $r, $r, 90, 90); $path.CloseFigure()
        $g.FillPath((New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255, 22, 28, 36))), $path)
        $x = [int]($size * 0.22); $h = [Math]::Max(2, [int]($size * 0.12)); $gap = [int]($size * 0.08)
        $y = [int](($size - (3 * $h + 2 * $gap)) / 2)
        foreach ($b in @(@(0.56, 63, 207, 142), @(0.42, 242, 184, 75), @(0.30, 95, 168, 255))) {
            $w = [int]($size * $b[0]); $br = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255, $b[1], $b[2], $b[3])); $rr = [Math]::Min($h, 6)
            if ($size -le 16) { $g.FillRectangle($br, $x, $y, $w, $h) } else { $rp = New-Object Drawing.Drawing2D.GraphicsPath; $rp.AddArc($x, $y, $rr, $rr, 180, 90); $rp.AddArc($x + $w - $rr, $y, $rr, $rr, 270, 90); $rp.AddArc($x + $w - $rr, $y + $h - $rr, $rr, $rr, 0, 90); $rp.AddArc($x, $y + $h - $rr, $rr, $rr, 90, 90); $rp.CloseFigure(); $g.FillPath($br, $rp) }
            $y += $h + $gap
        }
        $g.Dispose(); $pms = New-Object IO.MemoryStream; $bmp.Save($pms, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
        ,@{ Size = $size; Bytes = $pms.ToArray() }
    }
    $fs = New-Object IO.MemoryStream; $bw = New-Object IO.BinaryWriter($fs)
    $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$pngs.Count); $offset = 6 + 16 * $pngs.Count
    foreach ($p in $pngs) { $s = $(if ($p.Size -ge 256) { 0 } else { $p.Size }); $bw.Write([byte]$s); $bw.Write([byte]$s); $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$p.Bytes.Length); $bw.Write([uint32]$offset); $offset += $p.Bytes.Length }
    foreach ($p in $pngs) { $bw.Write($p.Bytes) }
    $bw.Flush(); [IO.File]::WriteAllBytes($ico, $fs.ToArray()); $bw.Close()
}

# --- compile -----------------------------------------------------------------------------------------------------------------
if (-not (Get-Command Invoke-PS2EXE -ErrorAction SilentlyContinue)) { Import-Module ps2exe -ErrorAction Stop }
$tmp = Join-Path $env:TEMP 'IntuneAppMonitor.merged.ps1'
[IO.File]::WriteAllText($tmp, $merged, (New-Object Text.UTF8Encoding($true)))
$exe = Join-Path $env:TEMP 'IntuneAppMonitor.exe'
if (Test-Path $exe) { Remove-Item $exe -Force }
Invoke-PS2EXE -inputFile $tmp -outputFile $exe -iconFile $ico -STA -noConsole -x64 `
              -title 'Intune App Monitor' -description 'Intune Win32 app reporting' -product 'Intune App Monitor' -company 'EQS Application Packaging' -version '2.0.0.0' | Out-Null
Remove-Item $tmp -Force
if (-not (Test-Path $exe)) { throw 'ps2exe did not produce IntuneAppMonitor.exe' }

# --- team folder -------------------------------------------------------------------------------------------------------------
# people.json: names typed in EITHER copy are kept - merged both ways before anything is written.
# (a rebuild once overwrote names the user had typed in the team copy; never again)
function Read-People { param([string]$Path) $m = [ordered]@{}; if (Test-Path $Path) { $j = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $m[$p.Name] = "$($p.Value)" } }; return $m }
$srcPeople  = Join-Path $root 'Data\people.json'
$teamPeople = Join-Path $OutDir 'Data\people.json'
$merged = Read-People $srcPeople; $teamMap = Read-People $teamPeople; $fromTeam = 0
foreach ($k in $teamMap.Keys) {
    if ($teamMap[$k].Trim() -and -not "$($merged[$k])".Trim()) { $merged[$k] = $teamMap[$k]; $fromTeam++ }
    elseif (-not $merged.Contains($k)) { $merged[$k] = $teamMap[$k] }
}
$peopleJson = $(if ($merged.Count) { [pscustomobject]$merged | ConvertTo-Json -Depth 3 } else { '' })
if ($peopleJson) { [IO.File]::WriteAllText($srcPeople, $peopleJson, (New-Object Text.UTF8Encoding($false))) }
if ($fromTeam) { Write-Host "people.json: $fromTeam name(s) typed in the team copy merged back into the source." -ForegroundColor Yellow }

# The PROGRAM is replaced (exe, settings, lib). An existing Data\ is the team's record and is left alone;
# the record is copied from the source only on the first build (or with -RefreshData).
$copyRecord = (-not $NoData) -and ($RefreshData -or -not (Test-Path (Join-Path $OutDir 'Data\AuditCache.json')))
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$target = Join-Path $OutDir 'IntuneAppMonitor.exe'
try { if (Test-Path $target) { Remove-Item $target -Force -ErrorAction Stop }; Move-Item $exe $target -Force -ErrorAction Stop }
catch {
    # the team exe is open right now (Windows locks a running exe) - park the new one next to it
    Move-Item $exe "$target.new" -Force
    Write-Host "IntuneAppMonitor.exe is running and cannot be replaced - the new build is saved as IntuneAppMonitor.exe.new. Close the tool, then run Build-Team.ps1 again (or rename the .new file)." -ForegroundColor Yellow
}
Copy-Item (Join-Path $root 'settings.json') $OutDir -Force
try {
    if (Test-Path (Join-Path $OutDir 'lib')) { Remove-Item (Join-Path $OutDir 'lib') -Recurse -Force -ErrorAction Stop }
    New-Item -ItemType Directory -Path (Join-Path $OutDir 'lib') -Force | Out-Null
    Copy-Item (Join-Path $root 'lib\PowerShell Module') (Join-Path $OutDir 'lib\PowerShell Module') -Recurse -Force -ErrorAction Stop
} catch { Write-Host "lib\ is in use by the running tool - kept as is (the modules do not change between builds)." -ForegroundColor Yellow }
$dataOut = Join-Path $OutDir 'Data'; New-Item -ItemType Directory -Path $dataOut -Force | Out-Null
if ($copyRecord) {       # the record - not the sign-in cache, the log or old exports
    foreach ($f in 'AuditCache.json','ActivityFeed.json','ChangeLog.json') { $p = Join-Path $root "Data\$f"; if (Test-Path $p) { Copy-Item $p $dataOut -Force } }
    $snap = Get-ChildItem (Join-Path $root 'Data\Snapshots') -Filter 'apps-*.json' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if ($snap) { New-Item -ItemType Directory -Path (Join-Path $dataOut 'Snapshots') -Force | Out-Null; Copy-Item $snap.FullName (Join-Path $dataOut 'Snapshots') -Force }
    Write-Host "Data: record copied from the source$(if ($RefreshData) { ' (-RefreshData)' } else { ' (first build)' })."
} else { Write-Host 'Data: existing team record left untouched (-RefreshData replaces it from the source).' }
if ($peopleJson) { [IO.File]::WriteAllText($teamPeople, $peopleJson, (New-Object Text.UTF8Encoding($false))) }
$size = [math]::Round(((Get-ChildItem $OutDir -Recurse -File | Measure-Object Length -Sum).Sum) / 1MB, 1)
Write-Host "Team folder: $OutDir  ($size MB, build $stamp)" -ForegroundColor Green
Get-ChildItem $OutDir | ForEach-Object { Write-Host ("   {0,-20} {1}" -f $_.Name, $(if ($_.PSIsContainer) { 'folder' } else { "$([math]::Round($_.Length/1KB)) KB" })) }
