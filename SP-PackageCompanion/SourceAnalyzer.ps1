<#
.SYNOPSIS
  Source Analyzer - given a packaging source folder, determines the installer TOPOLOGY and emits an
  install PLAN with confidence. Deterministic + static (no execution, no sandbox). The first engine of
  the autonomous-assist packager.

  Pillars:
    1. Engine fingerprint  - read the EXE's own bytes for an installer-engine signature (NSIS / Inno /
       InstallShield / WiX-Burn / 7z-SFX / MSI-as-OLE). NO external tool needed; works everywhere.
    2. Static inner peek   - if 7-Zip is present, list/extract a bundled MSI WITHOUT running the exe
       (automates "launch exe, grab the MSI from temp" - safely, statically). Falls back to msiexec /a.
    3. Plan + confidence   - map engine -> silent switch family; classify topology; rank confidence.
       The Knowledge Base (KnowledgeBase.json) is a corroborating PRIOR, never the decider.

.EXAMPLE
  .\SourceAnalyzer.ps1 -SourcePath 'C:\temp\SomeApp'        # analyze a source folder
  .\SourceAnalyzer.ps1 -Measure -Sample 60                   # measure engine->switch accuracy vs the live KB
#>
[CmdletBinding()]
param(
    [string]$SourcePath,
    [switch]$Measure,
    [int]$Sample = 60,
    [string]$RepoPath = '\\mbddfsovpc01.mn-man.biz\SWDLive-Gate\CMLib_LIVE\Apps'
)

# ---------- engine fingerprint: scan the binary's own bytes (no execution, no external tool) ----------
function Get-InstallerEngine {
    param([Parameter(Mandatory)][string]$Path)
    $fi = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $fi) { return [pscustomobject]@{ Engine='missing'; Evidence='file not found' } }

    # MSI is an OLE compound file - check the magic first (covers MSIs given an .exe name too).
    $head = New-Object byte[] 8
    try { $fs0 = [IO.File]::OpenRead($Path); [void]$fs0.Read($head,0,8); $fs0.Close() } catch {}
    if (($head -join ',') -eq '208,207,17,224,161,177,26,225') {
        if ($fi.Extension -ieq '.msi') { return [pscustomobject]@{ Engine='MSI'; Evidence='OLE compound + .msi' } }
        return [pscustomobject]@{ Engine='MSI-as-OLE'; Evidence='OLE compound magic (likely renamed MSI)' }
    }

    # Read up to 6 MB (installer stubs live at the start) as Latin1 so every byte is searchable as a char.
    $cap = [Math]::Min([int64]6MB, $fi.Length)
    $buf = New-Object byte[] $cap
    try { $fs = [IO.File]::OpenRead($Path); [void]$fs.Read($buf,0,$cap); $fs.Close() } catch { return [pscustomobject]@{ Engine='unreadable'; Evidence="$($_.Exception.Message)" } }
    $txt = [Text.Encoding]::GetEncoding(28591).GetString($buf)   # Latin1: 1 byte -> 1 char

    # Ordered by signature specificity. First match wins.
    $sigs = [ordered]@{
        'InnoSetup'     = 'Inno Setup|JR\.Inno\.Setup|Inno Setup Setup Data'
        'NSIS'          = 'Nullsoft|NullsoftInst|NSIS Error'
        'InstallShield' = 'InstallShield|ISSetupStream|ISSetup\.dll|InstallShield Setup Launcher|_isres'
        'WiX-Burn'      = 'wixburn|WixBundle|\.wixburn|Windows Installer XML'
        '7z-SFX'        = '7zS[0-9A-Za-z]?\.sfx|7-Zip self-extr|7zXr|;!@Install@!UTF-8!'
        'WinRAR-SFX'    = 'WinRAR self-extract|__RAR_|WINRAR\.SFX'
        'InstallAware'  = 'InstallAware'
        'WiseInstall'   = 'Wise Installation|WiseMain|GLBSINGLEINST'
        'MSIX/AppX'     = 'AppxManifest|AppxBlockMap'
    }
    foreach ($e in $sigs.GetEnumerator()) {
        if ([regex]::IsMatch($txt, $e.Value)) { return [pscustomobject]@{ Engine=$e.Key; Evidence="signature: $($e.Value -split '\|' | Select-Object -First 1)" } }
    }
    return [pscustomobject]@{ Engine='unknown'; Evidence='no known installer-engine signature in first 6MB' }
}

# ---------- engine -> silent switch family (the deterministic mapping) + confidence ----------
function Get-EnginePlan {
    param([string]$Engine)
    switch ($Engine) {
        'MSI'           { @{ Install='/qn REBOOT=ReallySuppress (+ MST)'; Uninstall='/x <ProductCode> /qn'; Extract=$null; Conf='high' } }
        'MSI-as-OLE'    { @{ Install='rename to .msi, then /qn (+ MST)'; Uninstall='/x <ProductCode> /qn'; Extract=$null; Conf='high' } }
        'NSIS'          { @{ Install='/S'; Uninstall='Uninstall.exe /S (or QuietUninstallString)'; Extract='7z x (NSIS is a 7z/zlib archive)'; Conf='high' } }
        'InnoSetup'     { @{ Install='/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'; Uninstall='unins000.exe /VERYSILENT'; Extract='innounp (or run /SP- and capture)'; Conf='high' } }
        'InstallShield' { @{ Install='/s /v"/qn" (InstallScript-MSI) OR record /r /f1"setup.iss" then /s /f1'; Uninstall='/x /s OR MSI product code'; Extract='/extract_only or /stage_only (version-dependent)'; Conf='medium' } }
        'WiX-Burn'      { @{ Install='/quiet /norestart'; Uninstall='/uninstall /quiet'; Extract='dark.exe / msiexec layout (else sandbox-watch)'; Conf='high' } }
        '7z-SFX'        { @{ Install='wrapper - EXTRACT and recurse on the inner installer'; Uninstall='n/a (depends on inner)'; Extract='7z x'; Conf='medium' } }
        'WinRAR-SFX'    { @{ Install='wrapper - EXTRACT and recurse'; Uninstall='n/a'; Extract='7z x / WinRAR'; Conf='medium' } }
        'MSIX/AppX'     { @{ Install='Add-AppxProvisionedPackage / Add-AppxPackage'; Uninstall='Remove-AppxPackage'; Extract=$null; Conf='high' } }
        default         { @{ Install='UNKNOWN - verify in sandbox / ask AO'; Uninstall='unknown'; Extract=$null; Conf='low' } }
    }
}

# the regex that says "this recorded arg string matches this engine's expected family" (for measurement + KB corroboration)
function Test-SwitchMatchesEngine {
    # NOTE: param is $Sw, NOT $Args - $Args is a reserved PowerShell automatic variable and never binds.
    param([string]$Engine, [string]$Sw)
    if (-not $Sw) { return $null }   # nothing recorded -> can't judge
    switch ($Engine) {
        'NSIS'          { return [bool]($Sw -match '(?i)(^|\s)/S(\s|$)') }
        'InnoSetup'     { return [bool]($Sw -match '(?i)/VERYSILENT|/SILENT|/SP-|/SUPPRESSMSGBOXES') }
        'InstallShield' { return [bool]($Sw -match '(?i)/s\b|/qn|/f1|\.iss|/v') }
        'WiX-Burn'      { return [bool]($Sw -match '(?i)/quiet|/passive|/norestart') }
        'MSI'           { return [bool]($Sw -match '(?i)/qn|/quiet|ALLUSERS|REBOOT') }
        default         { return $null }
    }
}

function Find-SevenZip {
    foreach ($p in @("$env:ProgramFiles\7-Zip\7z.exe","${env:ProgramFiles(x86)}\7-Zip\7z.exe","$env:LOCALAPPDATA\Programs\7-Zip\7z.exe")) { if (Test-Path $p) { return $p } }
    $g = Get-Command 7z.exe -ErrorAction SilentlyContinue; if ($g) { return $g.Source }
    return $null
}

# static inner peek: does this EXE contain an MSI we can pull WITHOUT running it?
function Get-InnerMsi {
    param([string]$Path)
    $sz = Find-SevenZip
    if (-not $sz) { return @{ Tool='none'; InnerMsi=@(); Note='7-Zip not present on this machine; on the packaging box this would list/extract the bundled MSI' } }
    try {
        $list = & $sz l -- "$Path" 2>$null
        $msis = @($list | Select-String -Pattern '([^\s]+\.msi)$' -AllMatches | ForEach-Object { ($_.Line -split '\s+')[-1] } | Where-Object { $_ -match '\.msi$' } | Select-Object -Unique)
        return @{ Tool='7-Zip'; InnerMsi=$msis; Note=$(if($msis){'bundled MSI(s) extractable statically with: 7z x'}else{'no MSI inside (or not a 7z-readable archive)'}) }
    } catch { return @{ Tool='7-Zip'; InnerMsi=@(); Note="7z list failed: $($_.Exception.Message)" } }
}

# ---------- analyze a source FOLDER -> topology + plan ----------
function Get-SourceAnalysis {
    param([Parameter(Mandatory)][string]$SourcePath)
    if (-not (Test-Path $SourcePath)) { return @{ Ok=$false; Message="Source not found: $SourcePath" } }
    $all = Get-ChildItem -LiteralPath $SourcePath -Recurse -File -ErrorAction SilentlyContinue
    $msi = @($all | Where-Object Extension -ieq '.msi')
    $exe = @($all | Where-Object Extension -ieq '.exe' | Where-Object { $_.Name -notmatch '(?i)^(Deploy-Application|Invoke-AppDeployToolkit)' })
    $msp = @($all | Where-Object Extension -ieq '.msp')

    $installers = New-Object System.Collections.Generic.List[object]
    foreach ($f in ($msi + $exe)) {
        $eng = Get-InstallerEngine -Path $f.FullName
        $plan = Get-EnginePlan -Engine $eng.Engine
        $inner = if ($eng.Engine -in 'NSIS','7z-SFX','WinRAR-SFX','InstallShield','WiX-Burn' -or $f.Extension -ieq '.exe') { Get-InnerMsi -Path $f.FullName } else { @{ InnerMsi=@() } }
        $installers.Add([pscustomobject]@{
            Name = $f.Name; SizeMB=[math]::Round($f.Length/1MB,1); Ext=$f.Extension.ToLower()
            Engine = $eng.Engine; Evidence = $eng.Evidence
            Install = $plan.Install; Uninstall = $plan.Uninstall; Extract = $plan.Extract; Confidence = $plan.Conf
            InnerMsi = @($inner.InnerMsi)
        })
    }
    # topology
    $topo = if ($installers.Count -eq 0) { 'NoInstaller' }
            elseif (($installers | Where-Object { $_.InnerMsi.Count }).Count) { 'WrapperMSI' }
            elseif ($installers.Count -eq 1 -and $installers[0].Ext -eq '.msi') { 'SingleMSI' }
            elseif ($installers.Count -eq 1) { 'SingleEXE' }
            else { 'Multiple' }
    $overall = if ($installers.Count) { (@($installers.Confidence) | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name } else { 'low' }
    return @{ Ok=$true; SourcePath=$SourcePath; Topology=$topo; Installers=@($installers)
             FileCounts=@{ msi=$msi.Count; exe=$exe.Count; msp=$msp.Count; total=$all.Count }; Confidence=$overall }
}

# ===================== MEASUREMENT MODE =====================
# Sample real packages from the live share, fingerprint their installer EXE, derive the silent switch, and
# compare against the switch the package's script ACTUALLY used (from KnowledgeBase.json) -> real hit-rate.
function Invoke-Measurement {
    param([int]$N, [string]$Repo)
    $kbFile = Join-Path (Split-Path -Parent $PSCommandPath) 'KnowledgeBase.json'
    if (-not (Test-Path $kbFile)) { Write-Host "Run Analyze-KnowledgeBase.ps1 first (need KnowledgeBase.json)." -ForegroundColor Red; return }
    $kb = (Get-Content $kbFile -Raw | ConvertFrom-Json).packages
    # measure on EXE packages that recorded a switch (so we have ground truth)
    $cand = @($kb | Where-Object { $_.InstallerType -eq 'EXE' -and $_.InstallArgs }) | Get-Random -Count ([Math]::Min($N, 400))
    $rows = New-Object System.Collections.Generic.List[object]
    $i=0
    foreach ($p in $cand) {
        $i++; Write-Progress -Activity 'Measuring engine->switch accuracy' -Status "$i/$($cand.Count) $($p.Name)" -PercentComplete ([int](100*$i/$cand.Count))
        $files = Join-Path (Join-Path $Repo $p.Name) 'Content\Files'
        if (-not (Test-Path $files)) { continue }
        # Fingerprint the candidate installer exes (largest first, cap 4) and take the FIRST one that resolves
        # to a known engine - the installer is usually identifiable among the files, even if it isn't the biggest.
        $exes = Get-ChildItem -LiteralPath $files -Filter *.exe -Recurse -ErrorAction SilentlyContinue | Sort-Object Length -Descending | Select-Object -First 4
        if (-not $exes) { continue }
        $eng = 'unknown'; $picked = $null
        foreach ($x in $exes) { $e = (Get-InstallerEngine -Path $x.FullName).Engine; if ($e -notin 'unknown','unreadable','missing') { $eng = $e; $picked = $x.Name; break } }
        if (-not $picked) { $picked = $exes[0].Name }
        $match = Test-SwitchMatchesEngine -Engine $eng -Sw $p.InstallArgs
        $rows.Add([pscustomobject]@{ Package=$p.Name; Exe=$picked; Engine=$eng; RecordedArgs=$p.InstallArgs; Match=$match })
    }
    Write-Progress -Activity 'Measuring' -Completed
    $det   = @($rows | Where-Object { $_.Engine -notin 'unknown','unreadable','missing' })
    $judge = @($rows | Where-Object { $null -ne $_.Match })
    $hit   = @($judge | Where-Object { $_.Match })
    Write-Host ""
    Write-Host "===== ENGINE-FINGERPRINT MEASUREMENT (n=$($rows.Count) EXE packages) =====" -ForegroundColor Cyan
    Write-Host ("Engine identified (not unknown) : {0}/{1}  ({2}%)" -f $det.Count, $rows.Count, [math]::Round(100*$det.Count/[Math]::Max(1,$rows.Count)))
    Write-Host ("Derived switch MATCHED reality  : {0}/{1}  ({2}%)  <- of those we could judge" -f $hit.Count, $judge.Count, [math]::Round(100*$hit.Count/[Math]::Max(1,$judge.Count)))
    Write-Host "engine distribution:" -ForegroundColor Cyan
    $rows | Group-Object Engine | Sort-Object Count -Descending | ForEach-Object { "  {0,5}  {1}" -f $_.Count, $_.Name }
    Write-Host "sample MISMATCHES (engine vs recorded switch) - where the heuristic disagreed:" -ForegroundColor Yellow
    @($judge | Where-Object { -not $_.Match }) | Select-Object -First 8 | ForEach-Object { "  [{0,-13}] {1}  args='{2}'" -f $_.Engine, $_.Package, $_.RecordedArgs }
}

# ---------- entry ----------
if ($Measure) { Invoke-Measurement -N $Sample -Repo $RepoPath; return }
if ($SourcePath) {
    $r = Get-SourceAnalysis -SourcePath $SourcePath
    if (-not $r.Ok) { Write-Host $r.Message -ForegroundColor Red; return }
    Write-Host "Source: $($r.SourcePath)" -ForegroundColor Cyan
    Write-Host "Topology: $($r.Topology)   (files: $($r.FileCounts.msi) msi, $($r.FileCounts.exe) exe, $($r.FileCounts.msp) msp)   overall confidence: $($r.Confidence)"
    foreach ($i in $r.Installers) {
        Write-Host ("  - {0}  [{1}]  ({2})" -f $i.Name, $i.Engine, $i.Confidence) -ForegroundColor Green
        Write-Host ("      install  : {0}" -f $i.Install)
        Write-Host ("      uninstall: {0}" -f $i.Uninstall)
        if ($i.InnerMsi.Count) { Write-Host ("      bundled MSI: {0}  (extract: {1})" -f ($i.InnerMsi -join ', '), $i.Extract) -ForegroundColor Yellow }
        Write-Host ("      evidence : {0}" -f $i.Evidence) -ForegroundColor DarkGray
    }
    return
}
Write-Host "Usage: -SourcePath <folder>   |   -Measure [-Sample N]" -ForegroundColor Yellow
