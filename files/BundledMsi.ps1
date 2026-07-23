##############################################################
# BundledMsi.ps1
# Pull an MSI that a WRAPPER exe bundles, so a clean MSI+MST package can be
# built WITHOUT running the installer. Two layers:
#   Test-ExeBundlesMsi  - static signature scan (no tool needed) that says whether an MSI is
#                         really embedded, vs a custom installer that builds/downloads it at runtime.
#   Find/Expand-BundledMsi - use 7-Zip (system or Lib\7za.exe) to LIST / EXTRACT the embedded MSI.
# IMPORTANT: a wrapper often also installs prerequisites / sets registry / runs custom actions that the
# bare MSI does NOT - so extraction is always opt-in and flagged for review+testing by the caller.
##############################################################

# Locate a 7-Zip CLI: bundled Lib\7za.exe first, then an installed 7-Zip, then PATH. $null if none.
function Get-ArchiveTool {
    if ($script:ArchiveTool) { return $script:ArchiveTool }
    $root = if (Get-Command Get-ToolRoot -EA SilentlyContinue) { Get-ToolRoot } else { (Get-Location).Path }
    $cands = @(
        (Join-Path $root 'Lib\7za.exe'), (Join-Path $root 'Lib\7z.exe'),
        "$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
    )
    foreach ($c in $cands) { if ($c -and (Test-Path $c)) { $script:ArchiveTool = $c; return $c } }
    foreach ($n in '7z.exe','7za.exe') { try { $p = (Get-Command $n -EA Stop).Source; if ($p) { $script:ArchiveTool = $p; return $p } } catch {} }
    return $null
}

# Static scan (no external tool): is an MSI actually embedded, or is this a custom installer that
# produces the MSI at runtime? Returns @{ HasEmbeddedMsi; Archive; Reason }. Streams in chunks so a
# big network EXE doesn't have to be loaded whole; overlaps chunk edges so a signature isn't split.
function Test-ExeBundlesMsi {
    param([Parameter(Mandatory)][string]$ExePath, [long]$MaxScan = 600MB)
    $res = @{ HasEmbeddedMsi = $false; Archive = $null; Reason = '' }
    if (-not (Test-Path $ExePath)) { $res.Reason = 'file not found'; return $res }
    $fs = $null
    try {
        $fs = [IO.File]::OpenRead($ExePath)
        $len = [Math]::Min($fs.Length, $MaxScan)
        $chunk = 8MB; $overlap = 64
        $buf = New-Object byte[] ($chunk + $overlap)
        $carry = 0; $pos = 0; $oleFound = $false; $arch = $null
        while ($pos -lt $len) {
            $toRead = [int][Math]::Min($chunk, $len - $pos)
            $n = $fs.Read($buf, $carry, $toRead)
            if ($n -le 0) { break }
            $have = $carry + $n
            $ascii = [Text.Encoding]::ASCII.GetString($buf, 0, $have)
            if (-not $arch) {
                if     ($ascii.Contains('Nullsoft'))     { $arch = 'NSIS' }
                elseif ($ascii.Contains('Inno Setup'))   { $arch = 'Inno Setup' }
                elseif ($ascii.Contains('.wixburn'))     { $arch = 'WiX Burn bundle' }
                elseif ($ascii.Contains('InstallShield')){ $arch = 'InstallShield' }
                elseif ($ascii.Contains('MSCF'))         { $arch = 'CAB/SFX' }
                elseif ($ascii.Contains('PK' + [char]3 + [char]4)) { $arch = 'Zip/SFX' }
            }
            # MSI = OLE compound doc (D0 CF 11 E0) that ALSO carries the installer marker.
            if (-not $oleFound) {
                for ($i = 0; $i -lt $have - 8; $i++) {
                    if ($buf[$i] -eq 0xD0 -and $buf[$i+1] -eq 0xCF -and $buf[$i+2] -eq 0x11 -and $buf[$i+3] -eq 0xE0) { $oleFound = $true; break }
                }
            }
            if ($oleFound -and ($ascii.Contains('Installation Database') -or $ascii.Contains('Installer'))) {
                $res.HasEmbeddedMsi = $true
            }
            # slide the tail into the head so a signature spanning the boundary still matches
            if ($have -ge $overlap) { [Array]::Copy($buf, $have - $overlap, $buf, 0, $overlap); $carry = $overlap } else { $carry = 0 }
            $pos += $n
        }
        $res.Archive = $arch
        if ($res.HasEmbeddedMsi) {
            $res.Reason = "An MSI is embedded in this EXE$(if($arch){" ($arch wrapper)"}) - it can be extracted without running the installer."
        } elseif ($arch) {
            $res.Reason = "This is a $arch wrapper but no MSI is statically embedded - it likely builds or downloads the MSI at runtime, so it cannot be extracted without running it."
        } else {
            $res.Reason = "No embedded MSI or known wrapper archive found - this is most likely a self-contained / custom installer (extract the MSI with a vendor flag, or keep it as an EXE package)."
        }
    } catch { $res.Reason = "scan failed: $($_.Exception.Message)" }
    finally { if ($fs) { $fs.Close() } }
    return $res
}

# List the .msi (+ .mst) files inside a wrapper EXE via 7-Zip. Returns @(@{Name;Size}). Empty if no tool/none.
function Find-BundledMsi {
    param([Parameter(Mandatory)][string]$ExePath)
    $tool = Get-ArchiveTool
    if (-not $tool -or -not (Test-Path $ExePath)) { return @() }
    $out = New-Object System.Collections.Generic.List[object]
    try {
        $raw = & $tool 'l' '-slt' "$ExePath" 2>$null
        $cur = @{}
        foreach ($ln in $raw) {
            if     ($ln -match '^Path = (.+)$') { $cur = @{ Name = $Matches[1] } }
            elseif ($ln -match '^Size = (\d+)$' -and $cur.Name) { $cur.Size = [int64]$Matches[1] }
            elseif ([string]::IsNullOrWhiteSpace($ln) -and $cur.Name) {
                if ($cur.Name -match '(?i)\.msi$') { $out.Add([pscustomobject]$cur) }
                $cur = @{}
            }
        }
        if ($cur.Name -and $cur.Name -match '(?i)\.msi$') { $out.Add([pscustomobject]$cur) }
    } catch { if (Get-Command Write-Log -EA SilentlyContinue) { Write-Log "Find-BundledMsi failed: $($_.Exception.Message)" Warning } }
    return $out.ToArray()
}

# ===== RUN-AND-CAPTURE: for installers that BUILD/DECRYPT the MSI at runtime (no static extraction). The user
# runs the EXE (no sandbox here); we snapshot the temp/system folders first, then find the MSI the run dropped.
# We do NOT run the installer ourselves automatically - the user triggers it (an EDR/agent EXE actually installs).

# The roots a run might drop / cache a REAL MSI into - we scan broadly and let the diff find whatever appeared.
# WiX/Burn bundles (e.g. Avigilon) cache the real app MSI under ProgramData\Package Cache (NOT C:\Windows\
# Installer, which usually holds the runtime copy / a prerequisite). C:\Windows\Installer is watched too but is
# RANKED LAST (see Get-NewMsisSince) so the extracted MSI wins. (Reading Package Cache may need elevation.)
function Get-MsiWatchDirs {
    $dirs = New-Object System.Collections.Generic.List[string]
    $cands = @(
        $env:TEMP, $env:TMP,
        (Join-Path $env:SystemRoot 'Temp'),
        (Join-Path $env:ProgramData 'Package Cache'),   # WiX/Burn bundles cache the REAL app MSI here
        (Join-Path $env:SystemRoot 'Installer')          # runtime cache - kept LAST, de-prioritised by the ranker
    )
    foreach ($d in $cands) {
        if ($d -and (Test-Path $d -ErrorAction SilentlyContinue) -and -not ($dirs -contains $d)) { $dirs.Add($d) }
    }
    return $dirs.ToArray()
}
# Is this path the Windows Installer runtime cache (the renamed install DB), as opposed to a REAL extracted MSI?
function Test-RuntimeCacheMsi { param([string]$Path) return ($Path -match '(?i)[\\/]Windows[\\/]Installer[\\/]') }
# Baseline: every .msi currently under the watch dirs -> LastWriteTimeUtc (so we can tell what the run ADDED).
function Get-MsiSnapshot {
    param([string[]]$Dirs)
    $snap = @{}
    foreach ($d in @($Dirs)) {
        try { Get-ChildItem -LiteralPath $d -Filter *.msi -File -Recurse -Depth 4 -Force -EA SilentlyContinue | ForEach-Object { $snap[$_.FullName] = $_.LastWriteTimeUtc } } catch {}
    }
    return $snap
}
# New / freshly-written .msi since the baseline (not seen before, or newer), >= MinKB. Sorted largest first.
function Get-NewMsisSince {
    param([string[]]$Dirs, [hashtable]$Snapshot, [int]$MinKB = 200)
    $out = New-Object System.Collections.Generic.List[object]
    if (-not $Snapshot) { $Snapshot = @{} }
    foreach ($d in @($Dirs)) {
        try {
            Get-ChildItem -LiteralPath $d -Filter *.msi -File -Recurse -Depth 4 -Force -EA SilentlyContinue | ForEach-Object {
                $fresh = (-not $Snapshot.ContainsKey($_.FullName)) -or ($_.LastWriteTimeUtc -gt $Snapshot[$_.FullName])
                if ($fresh -and ($_.Length / 1KB) -ge $MinKB) { $out.Add($_) }
            }
        } catch {}
    }
    # Rank REAL extracted MSIs (temp / Package Cache) ahead of the Windows\Installer runtime cache, then by
    # size - so the actual app MSI surfaces at the top, not the renamed install DB the user doesn't want.
    return @($out | Sort-Object @{ Expression = { Test-RuntimeCacheMsi $_.FullName } }, @{ Expression = { $_.Length }; Descending = $true })
}
# The program + args to actually LAUNCH an installer. Critical: an .msi/.msp has NO 'runas' shell verb (its verbs are
# Open/Repair/Uninstall only) and PsExec can't run a raw .msi either - so `Start-Process foo.msi -Verb RunAs` throws and
# the snapshot "Run installer" fails for EVERY MSI (only .exe has a 'runas' verb). Route MSI/MSP through msiexec.exe (a
# real .exe that elevates fine). An .exe launches directly. Returns @{ File; Args } - Args is '' for an exe.
function Get-InstallerRunSpec {
    param([Parameter(Mandatory)][string]$Path)
    $msiexec = Join-Path $env:SystemRoot 'System32\msiexec.exe'
    switch ([IO.Path]::GetExtension($Path).ToLower()) {
        '.msi' { return @{ File=$msiexec; Args="/i `"$Path`"" } }
        '.msp' { return @{ File=$msiexec; Args="/p `"$Path`"" } }
        default { return @{ File=$Path; Args='' } }
    }
}

# Launch an installer for a manual run/capture. Tries ELEVATED first (RunAs); if the user cancels UAC or policy
# blocks elevation ("operation canceled by the user" / 1223), falls back to a NORMAL launch so an installer whose
# OWN manifest requests elevation still gets its chance (that is the Kistler "approve UAC -> nothing happens"
# case - the forced + manifest double-elevation conflicts). MSI/MSP are launched via msiexec (see Get-InstallerRunSpec).
# Returns @{ Ok; Mode; Error }.
function Start-InstallerLaunch {
    param([Parameter(Mandatory)][string]$Path)
    $wd   = Split-Path $Path -Parent
    $spec = Get-InstallerRunSpec -Path $Path
    $sp   = @{ FilePath=$spec.File; WorkingDirectory=$wd; ErrorAction='Stop' }
    if ("$($spec.Args)".Trim()) { $sp['ArgumentList'] = $spec.Args }
    try { Start-Process @sp -Verb RunAs | Out-Null; return @{ Ok=$true; Mode='elevated'; Error='' } }
    catch {
        $msg = "$($_.Exception.Message)"
        if ($msg -match '(?i)cancel|1223|operator|denied') {   # UAC declined/blocked -> try without forcing elevation
            try { Start-Process @sp | Out-Null; return @{ Ok=$true; Mode='normal (self-elevates if needed)'; Error='' } }
            catch { return @{ Ok=$false; Mode=''; Error="$($_.Exception.Message)" } }
        }
        return @{ Ok=$false; Mode=''; Error=$msg }
    }
}

# Probe an UNKNOWN installer for its usage/silent switches by running it with the common help flags and capturing
# console output. Best-effort: many GUI installers ignore these and just sit there (we time out + kill, and say
# so). Runs NON-elevated, console hidden, output captured. Returns @(@{ Switch; Output; Note }). WARN the caller:
# a few installers act on /? - only offer this for installers we otherwise can't identify.
function Get-InstallerHelp {
    param([Parameter(Mandatory)][string]$ExePath, [int]$TimeoutSec = 8)
    $switches = @('/?','/help','--help','-h','-?')
    $results = New-Object System.Collections.Generic.List[object]
    $needElev = $false
    foreach ($sw in $switches) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $ExePath; $psi.Arguments = $sw
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        try { $psi.WorkingDirectory = (Split-Path $ExePath -Parent) } catch {}
        $p = $null
        try { $p = [System.Diagnostics.Process]::Start($psi) }
        catch {
            # Manifest demands elevation (err 740) - can't redirect + elevate at once; remember to retry elevated.
            if ("$($_.Exception.Message)" -match '(?i)requires elevation|740|operable program') { $needElev = $true; $results.Add([pscustomobject]@{ Switch=$sw; Output=''; Note='needs elevation' }) }
            else { $results.Add([pscustomobject]@{ Switch=$sw; Output=''; Note="could not start: $($_.Exception.Message)" }) }
            continue
        }
        $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill() } catch {}
            $results.Add([pscustomobject]@{ Switch=$sw; Output=''; Note='no console output within timeout - likely a GUI installer that ignores help flags (it may have shown a window; close it).' })
            continue
        }
        $text = ''
        try { $text = ("$($o.Result)`r`n$($e.Result)").Trim() } catch {}
        $results.Add([pscustomobject]@{ Switch=$sw; Output=$text; Note=''; ExitCode=$p.ExitCode })
        if ($text.Length -gt 15) { break }   # got real help text - stop trying more flags
    }
    # If nothing captured AND the EXE needs elevation (SentinelOne et al.), retry ONCE elevated, redirecting the
    # installer's output to a temp file via an elevated cmd (one UAC prompt). Reading the file gives us the help
    # text the non-elevated run couldn't. Bounded by WaitForExit so a GUI installer can't hang the UI forever.
    if ($needElev -and -not ($results | Where-Object { "$($_.Output)".Trim() })) {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("pbhelp_" + [guid]::NewGuid().ToString('N').Substring(0,8) + ".txt")
        try {
            $arg = "/c `"`"$ExePath`" /? > `"$tmp`" 2>&1`""
            $ep = Start-Process -FilePath $env:ComSpec -ArgumentList $arg -Verb RunAs -WindowStyle Hidden -PassThru -ErrorAction Stop
            if (-not $ep.WaitForExit(($TimeoutSec + 12) * 1000)) { try { $ep.Kill() } catch {} }
            $txt = ''
            try { if (Test-Path $tmp) { $txt = (Get-Content $tmp -Raw -ErrorAction SilentlyContinue) } } catch {}
            $note = if ("$txt".Trim()) { '' } else { 'ran elevated but produced no console text - the help is likely a GUI window (it was shown on screen). Check the vendor docs.' }
            $results.Add([pscustomobject]@{ Switch='/? (elevated)'; Output=("$txt").Trim(); Note=$note })
        } catch { $results.Add([pscustomobject]@{ Switch='/? (elevated)'; Output=''; Note="elevated probe declined/blocked: $($_.Exception.Message)" }) }
        finally { try { if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } } catch {} }
    }
    return $results.ToArray()
}

# Copy a (possibly NETWORK-hosted) installer to a LOCAL writable folder, so it elevates + extracts correctly.
# Network/mapped drives are NOT visible to an elevated process (different logon session), and many wrappers
# refuse to extract next to a read-only/UNC path - that is why "approve UAC -> nothing happens". Brings small
# sibling files too (a config the wrapper may need). Returns the LOCAL exe path (or $null).
function Copy-InstallerLocal {
    param([Parameter(Mandatory)][string]$ExePath, [string]$DestRoot)
    if (-not (Test-Path $ExePath)) { return $null }
    # Already on a LOCAL drive? (The source was staged locally in step 1, or the user picked a local file.) Run it in
    # place - a second copy is pointless and only stalls the UI. Only a UNC path needs copying (it fails once the
    # installer elevates and the network token drops).
    if ($ExePath -notmatch '^\\\\') { return $ExePath }
    if (-not $DestRoot) { $DestRoot = if (Get-Command Get-WorkPath -EA SilentlyContinue) { Get-WorkPath 'RunLocal' } else { Join-Path $env:TEMP 'PBRunLocal' } }
    $dest = Join-Path $DestRoot ([IO.Path]::GetFileNameWithoutExtension($ExePath) + '_' + [guid]::NewGuid().ToString('N').Substring(0,6))
    New-Item $dest -ItemType Directory -Force | Out-Null
    $srcDir = Split-Path -Parent $ExePath
    $sib = @(Get-ChildItem -LiteralPath $srcDir -File -Force -EA SilentlyContinue)
    $mb  = (($sib | Measure-Object Length -Sum).Sum) / 1MB
    try {
        if ($sib.Count -le 40 -and $mb -le 1200) { foreach ($f in $sib) { Copy-Item -LiteralPath $f.FullName -Destination $dest -Force } }
        else { Copy-Item -LiteralPath $ExePath -Destination $dest -Force }
    } catch { if (Get-Command Write-Log -EA SilentlyContinue) { Write-Log "Copy-InstallerLocal failed: $($_.Exception.Message)" Warning }; return $null }
    # Strip Mark-of-the-Web from the copied installer (+ its siblings) so it launches instantly - no SmartScreen stall.
    if (Get-Command Unblock-PBPath -EA SilentlyContinue) { Unblock-PBPath -Path $dest }
    return (Join-Path $dest (Split-Path -Leaf $ExePath))
}
# Nested-setup awareness: a wrapper sometimes extracts ANOTHER installer (setup.exe / install.exe / a second
# .msi) and runs it. New setup-like files since the baseline, so the UI can tell the user the chain isn't an MSI.
function Get-NewSetupsSince {
    param([string[]]$Dirs, [hashtable]$Snapshot, [int]$MinKB = 500)
    $out = New-Object System.Collections.Generic.List[object]
    if (-not $Snapshot) { $Snapshot = @{} }
    foreach ($d in @($Dirs)) {
        try {
            Get-ChildItem -LiteralPath $d -File -Recurse -Depth 4 -Force -EA SilentlyContinue -Include '*.exe','*.msp' | Where-Object {
                $_.Name -match '(?i)setup|install|^.*\.msp$' -or $_.Length -gt 5MB
            } | ForEach-Object {
                $fresh = (-not $Snapshot.ContainsKey($_.FullName)) -or ($_.LastWriteTimeUtc -gt $Snapshot[$_.FullName])
                if ($fresh -and (($_.Length / 1KB) -ge $MinKB)) { $out.Add($_) }
            }
        } catch {}
    }
    return @($out | Sort-Object Length -Descending | Select-Object -First 12)
}
# Snapshot of setup-like files (for the nested-setup diff), same shape as Get-MsiSnapshot.
function Get-SetupSnapshot {
    param([string[]]$Dirs)
    $snap = @{}
    foreach ($d in @($Dirs)) {
        try { Get-ChildItem -LiteralPath $d -File -Recurse -Depth 4 -Force -EA SilentlyContinue -Include '*.exe','*.msp' | ForEach-Object { $snap[$_.FullName] = $_.LastWriteTimeUtc } } catch {}
    }
    return $snap
}
# Recently-installed products from the MsiInstaller event log (read-only) - a hint when the temp MSI was deleted.
function Get-RecentInstallerMsiFromEventLog {
    param([int]$SinceMinutes = 30)
    $out = New-Object System.Collections.Generic.List[object]
    try {
        $since = (Get-Date).AddMinutes(-$SinceMinutes)
        $ev = Get-WinEvent -FilterHashtable @{ LogName='Application'; ProviderName='MsiInstaller'; StartTime=$since } -MaxEvents 150 -EA SilentlyContinue
        foreach ($e in @($ev)) {
            $msg = "$($e.Message)"
            $name = $null
            $mm = [regex]::Match($msg, '(?i)Product Name:\s*(.+?)[\.\r\n]'); if ($mm.Success) { $name = $mm.Groups[1].Value.Trim() }
            elseif (($mm = [regex]::Match($msg, '(?i)Product:\s*(.+?)\s*--')).Success) { $name = $mm.Groups[1].Value.Trim() }
            if ($name) { $out.Add([pscustomobject]@{ Time=$e.TimeCreated; Product=$name }) }
        }
    } catch {}
    return @($out | Sort-Object Time -Descending | Select-Object -Unique Product, Time)
}
# Copy a captured MSI to $DestDir. If its folder looks like a DEDICATED extract folder (few files, holds cabs/
# transforms), bring the siblings too (external cabs are needed); otherwise just the MSI. Returns the dest MSI path.
function Copy-CapturedMsi {
    param([Parameter(Mandatory)][string]$MsiPath, [Parameter(Mandatory)][string]$DestDir, [switch]$WholeFolder)
    if (-not (Test-Path $DestDir)) { New-Item $DestDir -ItemType Directory -Force | Out-Null }
    $folder = Split-Path -Parent $MsiPath
    $siblings = @(Get-ChildItem -LiteralPath $folder -File -Force -EA SilentlyContinue)
    $dedicated = $WholeFolder -or (($siblings.Count -le 30) -and (@($siblings | Where-Object { $_.Extension -match '(?i)\.(cab|mst|msi)$' }).Count -gt 1))
    if ($dedicated) {
        foreach ($f in $siblings) { try { Copy-Item -LiteralPath $f.FullName -Destination $DestDir -Force } catch {} }
    } else {
        Copy-Item -LiteralPath $MsiPath -Destination $DestDir -Force
    }
    return (Join-Path $DestDir (Split-Path $MsiPath -Leaf))
}

# ===== WINDOWS SANDBOX: when available, the whole run-and-capture is AUTOMATIC and safe - the installer runs in
# a throwaway VM (never touches this machine) and the MSI it drops is copied out to a host folder; closing the
# sandbox discards everything (free cleanup). We map the installer in (read-only) + a work folder out (read-write)
# and auto-run a self-contained Capture.ps1 inside.
function Test-SandboxAvailable { return [bool](Test-Path "$env:SystemRoot\System32\WindowsSandbox.exe") }

# Self-contained script that runs INSIDE the sandbox (no access to this tool's modules). Snapshots the temp/
# system folders, runs the installer, and copies every NEW .msi (>=100KB) it drops to the mapped out folder as
# it appears (so a transient temp MSI is caught even if the installer later deletes it), then writes _done.txt.
$script:SandboxCaptureScript = @'
param([string]$Installer,[string]$Out,[int]$TimeoutSec=240,[string]$InstallArgs='')
$ErrorActionPreference='Continue'
New-Item $Out -ItemType Directory -Force | Out-Null
"started $(Get-Date -Format s)  installer=$Installer" | Out-File "$Out\_log.txt"
$dirs = @($env:TEMP,$env:TMP,(Join-Path $env:SystemRoot 'Temp'),(Join-Path $env:ProgramData 'Package Cache'),(Join-Path $env:SystemRoot 'Installer')) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
$base=@{}; foreach($d in $dirs){ Get-ChildItem $d -Filter *.msi -File -Recurse -Depth 4 -Force -EA SilentlyContinue | ForEach-Object { $base[$_.FullName]=$_.LastWriteTimeUtc } }
# the installer is mapped READ-ONLY (C:\src); copy it to a writable local folder so it can extract beside itself.
try { $ld='C:\inst'; New-Item $ld -ItemType Directory -Force | Out-Null
  $sd=Split-Path $Installer -Parent; $sib=@(Get-ChildItem $sd -File -Force -EA SilentlyContinue); $mb=(($sib|Measure-Object Length -Sum).Sum)/1MB
  if($sib.Count -le 40 -and $mb -le 1200){ foreach($f in $sib){ Copy-Item $f.FullName $ld -Force -EA SilentlyContinue } } else { Copy-Item $Installer $ld -Force -EA SilentlyContinue }
  $le=Join-Path $ld (Split-Path $Installer -Leaf); if(Test-Path $le){ $Installer=$le; "running from local copy $le" | Out-File "$Out\_log.txt" -Append } } catch { "local copy failed: $($_.Exception.Message)" | Out-File "$Out\_log.txt" -Append }
# MSI/MSP must run through msiexec (a raw .msi has no runas/exec + args like /qn don't pass via the file association).
$runFile=$Installer; $runArgs=$InstallArgs
if($Installer -match '(?i)\.msi$'){ $runFile=(Join-Path $env:SystemRoot 'System32\msiexec.exe'); $runArgs=('/i "'+$Installer+'"'+$(if($InstallArgs){' '+$InstallArgs}else{''})) }
elseif($Installer -match '(?i)\.msp$'){ $runFile=(Join-Path $env:SystemRoot 'System32\msiexec.exe'); $runArgs=('/p "'+$Installer+'"'+$(if($InstallArgs){' '+$InstallArgs}else{''})) }
$proc=$null; try { if($runArgs){ $proc = Start-Process -FilePath $runFile -ArgumentList $runArgs -PassThru -EA Stop } else { $proc = Start-Process -FilePath $runFile -PassThru -EA Stop } } catch { "launch failed: $($_.Exception.Message)" | Out-File "$Out\_log.txt" -Append }
$copied=@{}; $deadline=(Get-Date).AddSeconds($TimeoutSec)
while((Get-Date) -lt $deadline){
  foreach($d in $dirs){ Get-ChildItem $d -Filter *.msi -File -Recurse -Depth 4 -Force -EA SilentlyContinue | ForEach-Object {
    $f=$_; $new = (-not $base.ContainsKey($f.FullName)) -or ($f.LastWriteTimeUtc -gt $base[$f.FullName])
    if($new -and (($f.Length/1KB) -ge 100) -and ($f.FullName -notlike "$Out*") -and -not $copied.ContainsKey($f.FullName)){
      try { Copy-Item $f.FullName (Join-Path $Out $f.Name) -Force
            Get-ChildItem $f.DirectoryName -File -Force -EA SilentlyContinue | Where-Object { $_.Extension -match '(?i)\.(cab|mst)$' } | ForEach-Object { Copy-Item $_.FullName (Join-Path $Out $_.Name) -Force -EA SilentlyContinue }
            $copied[$f.FullName]=$true; "captured $($f.Name) ($([math]::Round($f.Length/1MB,1))MB) from $($f.DirectoryName)" | Out-File "$Out\_log.txt" -Append } catch {}
    } } }
  if($proc -and $proc.HasExited -and $copied.Count -gt 0){ break }
  Start-Sleep -Seconds 3
}
try { if($proc -and -not $proc.HasExited){ $proc.Kill() } } catch {}
"done copied=$($copied.Count) $(Get-Date -Format s)" | Out-File "$Out\_done.txt"
'@

# Set up + LAUNCH a sandbox capture. Returns @{ Out; Work; Wsb } (host paths) so the caller can poll $Out for the
# captured .msi + _done.txt, or $null if the sandbox isn't available. Non-blocking (the sandbox runs on its own).
function Start-SandboxCapture {
    param([Parameter(Mandatory)][string]$ExePath, [string]$WorkRoot, [string]$InstallArgs = '', [int]$TimeoutSec = 240)
    if (-not (Test-SandboxAvailable) -or -not (Test-Path $ExePath)) { return $null }
    if (-not $WorkRoot) { $WorkRoot = if (Get-Command Get-WorkPath -EA SilentlyContinue) { Get-WorkPath 'Sandbox' } else { Join-Path $env:TEMP 'PBSandbox' } }
    $work = Join-Path $WorkRoot ('cap_' + [guid]::NewGuid().ToString('N'))
    $out  = Join-Path $work 'out'
    New-Item $out -ItemType Directory -Force | Out-Null
    Set-Content (Join-Path $work 'Capture.ps1') $script:SandboxCaptureScript -Encoding UTF8
    $srcDir = Split-Path -Parent $ExePath; $exeName = Split-Path -Leaf $ExePath
    $argEsc = ($InstallArgs -replace '"','&quot;')
    $wsb = @"
<Configuration>
  <MappedFolders>
    <MappedFolder><HostFolder>$srcDir</HostFolder><SandboxFolder>C:\src</SandboxFolder><ReadOnly>true</ReadOnly></MappedFolder>
    <MappedFolder><HostFolder>$work</HostFolder><SandboxFolder>C:\work</SandboxFolder><ReadOnly>false</ReadOnly></MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\work\Capture.ps1 -Installer "C:\src\$exeName" -Out C:\work\out -TimeoutSec $TimeoutSec -InstallArgs "$argEsc"</Command>
  </LogonCommand>
</Configuration>
"@
    $wsbPath = Join-Path $work 'capture.wsb'
    Set-Content $wsbPath $wsb -Encoding UTF8
    try { Start-Process -FilePath "$env:SystemRoot\System32\WindowsSandbox.exe" -ArgumentList "`"$wsbPath`"" -EA Stop }
    catch { if (Get-Command Write-Log -EA SilentlyContinue) { Write-Log "Sandbox launch failed: $($_.Exception.Message)" Warning }; return $null }
    return @{ Out = $out; Work = $work; Wsb = $wsbPath }
}

# Extract .msi / .mst from a wrapper EXE into $DestDir via 7-Zip. Returns the extracted MSI FileInfo(s).
function Expand-BundledMsi {
    param([Parameter(Mandatory)][string]$ExePath, [Parameter(Mandatory)][string]$DestDir)
    $tool = Get-ArchiveTool
    if (-not $tool) { return @() }
    if (-not (Test-Path $DestDir)) { New-Item $DestDir -ItemType Directory -Force | Out-Null }
    # Flatten to $DestDir (-e), but AUTO-RENAME on a name clash (-aou) instead of silently overwriting (-y alone):
    # a suite wrapper can hold two MSIs with the SAME leaf name in different internal folders, and overwriting would
    # lose one from the install chain. -aou keeps both (App.msi, App_1.msi) so the picker shows them all.
    try { & $tool 'e' '-y' '-aou' '-r' "-o$DestDir" "$ExePath" '*.msi' '*.mst' 2>$null | Out-Null }
    catch { if (Get-Command Write-Log -EA SilentlyContinue) { Write-Log "Expand-BundledMsi failed: $($_.Exception.Message)" Warning }; return @() }
    # Extracted from a wrapper that itself carried Mark-of-the-Web -> unblock so the extracted MSI installs cleanly.
    if (Get-Command Unblock-PBPath -EA SilentlyContinue) { Unblock-PBPath -Path $DestDir }
    return @(Get-ChildItem -LiteralPath $DestDir -Filter *.msi -File -EA SilentlyContinue | Sort-Object Length -Descending)
}
