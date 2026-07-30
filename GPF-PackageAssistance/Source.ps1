##############################################################
# Source.ps1
# Resolve a messy source folder into installers + docs. Structured
# layout is tried first; otherwise a recursive scan classifies every
# file. One installer is auto-taken; multiple are handed up to pick.
##############################################################
$script:InstallerExts = @('.exe','.msi','.msp','.iso')

#region Knowledge-base assist (engine fingerprint + recommendation lookup) ------------------------
# Fingerprint an installer's ENGINE from its own bytes (no execution, no external tool). Mirrors
# SourceAnalyzer.ps1; lives here so the packed runtime can use it. Returns the engine name.
function Get-InstallerEngine {
    param([Parameter(Mandatory)][string]$Path)
    $fi = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $fi) { return 'missing' }
    $head = New-Object byte[] 8
    try { $f0 = [IO.File]::OpenRead($Path); [void]$f0.Read($head,0,8); $f0.Close() } catch {}
    if (($head -join ',') -eq '208,207,17,224,161,177,26,225') { return $(if ($fi.Extension -ieq '.msi') { 'MSI' } else { 'MSI-as-OLE' }) }
    $cap = [Math]::Min([int64]6MB, $fi.Length)
    $buf = New-Object byte[] $cap
    try { $fs = [IO.File]::OpenRead($Path); [void]$fs.Read($buf,0,$cap); $fs.Close() } catch { return 'unreadable' }
    $txt = [Text.Encoding]::GetEncoding(28591).GetString($buf)
    $sigs = [ordered]@{
        'InnoSetup'='Inno Setup|JR\.Inno\.Setup'; 'NSIS'='Nullsoft|NullsoftInst|NSIS Error'
        'InstallShield'='InstallShield|ISSetupStream|ISSetup\.dll|_isres'; 'WiX-Burn'='wixburn|WixBundle|\.wixburn'
        '7z-SFX'='7zS[0-9A-Za-z]?\.sfx|7zXr|;!@Install@!UTF-8!'; 'WinRAR-SFX'='WinRAR self-extract|__RAR_'
        'InstallAware'='InstallAware'; 'WiseInstall'='Wise Installation|WiseMain'; 'MSIX/AppX'='AppxManifest|AppxBlockMap'
    }
    foreach ($e in $sigs.GetEnumerator()) { if ([regex]::IsMatch($txt, $e.Value)) { return $e.Key } }
    return 'unknown'
}
# Engine -> default silent switch (the fallback guess for brand-new apps).
function Get-EngineSwitch {
    param([string]$Engine)
    switch ($Engine) {
        'MSI'           { '/qn REBOOT=ReallySuppress' } 'MSI-as-OLE' { '/qn REBOOT=ReallySuppress' }
        'NSIS'          { '/S' } 'InnoSetup' { '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-' }
        'InstallShield' { '/s /v"/qn"' } 'WiX-Burn' { '/quiet /norestart' }
        'MSIX/AppX'     { '(Add-AppxProvisionedPackage)' } default { '' }
    }
}
# Engine -> default UNINSTALL silent switch (fallback when the KB has none). The uninstaller EXE differs per engine
# (Inno unins000.exe, NSIS Uninstall.exe); this is just the SILENT ARG to pass it. '' when there's no safe default.
function Get-EngineUninstallSwitch {
    param([string]$Engine)
    switch -regex ("$Engine") {
        '^MSI'              { '/qn REBOOT=ReallySuppress' }
        'InnoSetup'         { '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' }
        'NSIS'              { '/S' }
        'InstallShield'     { '/uninst /s' }
        'WiX-Burn'          { '/uninstall /quiet /norestart' }
        'InstallAware|WiseInstall' { '/s' }
        default             { '' }
    }
}
# Typical uninstaller EXE/command per engine - the uninstall exe DIFFERS from the install exe, so the hint shows
# WHAT runs the uninstall (not just the args). Used when the KB has no recorded uninstaller for this app.
function Get-EngineUninstaller {
    param([string]$Engine)
    switch -regex ("$Engine") {
        '^MSI'           { 'msiexec /x {ProductCode}' }
        'InnoSetup'      { 'unins000.exe (in the install dir)' }
        'NSIS'           { 'Uninstall.exe / uninst.exe (in the install dir)' }
        'InstallShield'  { 'the cached setup.exe -uninstall, or msiexec /x {ProductCode}' }
        'WiX-Burn'       { 'the bundle .exe /uninstall (or the Package Cache copy)' }
        'InstallAware'   { 'the install-dir uninstaller exe' }
        'WiseInstall'    { 'UNWISE.exe / the install-dir uninstaller' }
        default          { '' }
    }
}
# Runtime engine (Get-InstallerEngine) -> the engine label the KB ANALYZER recorded, so byEngine lookups line up.
$script:EngineRuntimeToKb = @{
    'NSIS'='NSIS'; 'InnoSetup'='InnoSetup'; 'InstallShield'='InstallShield'
    'MSI'='MSI'; 'MSI-as-OLE'='MSI'; 'WiX-Burn'='Burn/WiX/other'
}
$script:KBEngineIdx = $null
# Aggregate the KB's per-installer records into an engine -> {most-common install/uninstall, pkg count} index, so a
# brand-new installer with no vendor/app match still gets the params commonly used for ITS engine type. Built once,
# from data already in KnowledgeBase.Recommend.json (each byInstaller entry carries engine + install + uninstall).
function Get-KbEngineIndex {
    if ($null -ne $script:KBEngineIdx) { return $script:KBEngineIdx }
    $idx = @{}
    if ($script:KBRec -and $script:KBRec.byInstaller) {
        $seen = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($prop in $script:KBRec.byInstaller.PSObject.Properties) {
            $e = $prop.Value; $eng = "$($e.engine)"; if (-not $eng) { continue }
            if (-not $seen.Add("$eng|$($e.fromPackage)")) { continue }   # one vote per package per engine (byInstaller stores dupes)
            if (-not $idx.ContainsKey($eng)) { $idx[$eng] = @{ Install=@{}; Uninstall=@{}; Count=0 } }
            $idx[$eng].Count++
            $i = "$($e.install)".Trim();   if ($i) { $idx[$eng].Install[$i]   = 1 + [int]$idx[$eng].Install[$i] }
            $u = "$($e.uninstall)".Trim(); if ($u) { $idx[$eng].Uninstall[$u] = 1 + [int]$idx[$eng].Uninstall[$u] }
        }
    }
    $script:KBEngineIdx = $idx; return $idx
}
# Is a switch CLEAN enough to suggest generically? Rejects package-specific noise (paths, answer/log files, ACL
# commands, over-long blobs) so the engine-type suggestion never shows e.g. an icacls line or a $dirFiles\x.inf.
function Test-CleanSwitch {
    param([string]$s)
    $s = "$s".Trim()
    if (-not $s -or $s.Length -gt 80) { return $false }
    if ($s -match '(?i)\$dirfiles|\$config|\.inf\b|\.iss\b|\.properties|\.xml\b|logname|[A-Za-z]:\\|\\\\|S-1-5|/grant|icacls|takeown') { return $false }
    return $true
}
# Does a recorded silent switch actually FIT this EXE's engine? Guards the loose vendor/vendor-app tiers from
# suggesting e.g. an Inno '/VERYSILENT' onto an NSIS exe (which needs '/S'). Empty switch / unknown engine never
# conflict (return $true). Only used to BLOCK an engine-mismatched suggestion so we fall through to the engine tier.
function Test-SwitchMatchesEngine {
    param([string]$Sw, [string]$Engine)   # NOT $Switch - that name collides with the 'switch' keyword (binds to $null)
    $s = "$Sw"; if (-not $s.Trim()) { return $true }
    switch -regex ("$Engine") {
        'NSIS'          { return [bool]($s -match '(?i)(^|\s)/S(\s|$)|/D=') }
        'InnoSetup'     { return [bool]($s -match '(?i)/(VERY)?SILENT|/SP-|/SUPPRESSMSGBOXES|/NORESTART') }
        'InstallShield' { return [bool]($s -match '(?i)(^|\s)[/-]s\b|/f1|/f2') }
        'WiX-Burn'      { return [bool]($s -match '(?i)/quiet|/passive|/norestart|/log') }
        '^MSI'          { return [bool]($s -match '(?i)/qn|/qb|/quiet|=') }
        default         { return $true }   # custom / unknown engine -> can't judge, don't block
    }
}
# FULL command-line reference for an installer ENGINE - not just the silent switch. Used to suggest options
# the FIRST time (no KB data) straight from the installer's fingerprint: the packager sees every switch the
# engine supports, then picks what they need. Engine-level switches are well-known and need NO execution; the
# app-specific ones (NSIS custom flags, MSI properties) are noted where they must come from the file/vendor.
function Get-EngineParameterHelp {
    param([string]$Engine)
    switch -regex ($Engine) {
        '^MSI'           { "MSI - msiexec switches: /qn (silent) /qb (basic UI) /norestart /l*v <log>. Properties go as KEY=VALUE: ALLUSERS=1, REBOOT=ReallySuppress, INSTALLDIR=`"<path>`", TRANSFORMS=`"<mst>`", plus this MSI's OWN properties (IAGREE / AGREETOLICENSE / licence keys / feature toggles) - click 'View MSI properties' to read them from the file." }
        'InnoSetup'      { "Inno Setup - /SILENT or /VERYSILENT, /SUPPRESSMSGBOXES, /NORESTART, /NOCANCEL, /SP- (skip 'this will install' prompt), /NOICONS, /LOG[=`"<file>`"], /DIR=`"<path>`", /GROUP=`"<name>`", /COMPONENTS=`"a,b,c`", /TASKS=`"x,y`", /MERGETASKS=`"...`", /LOADINF=`"<file>`", /SAVEINF=`"<file>`", /PASSWORD=<pw>, /LANG=<lang>. Capture choices: setup.exe /SAVEINF=`"a.inf`" then reuse with /LOADINF." }
        'NSIS'           { "NSIS - /S (silent), /D=<dir> (install dir; must be the LAST arg, UNQUOTED even with spaces). NSIS has no standard component switches; any extra flags are app-specific - run 'setup.exe /?' or check the vendor docs." }
        'InstallShield'  { "InstallShield - /s (silent, usually needs a recorded response file), /v`"<msi props>`", /f1`"<response.iss>`", /f2`"<log>`", /clone_wait, /sms. RECORD a response file first: setup.exe /r /f1`"<iss>`", then install with /s /f1`"<iss>`"." }
        'WiX-Burn'       { "WiX bundle - /quiet or /passive, /norestart, /log `"<file>`", /layout `"<dir>`" (extract the MSIs without installing). MSI properties pass through as KEY=VALUE." }
        '7z-SFX'         { "7-Zip SFX - it's a self-extractor: -y -o`"<dir>`" to extract, or it runs an inner setup (RunProgram in the SFX config). Extract first ('Check for bundled MSI'), then handle the inner installer." }
        'WinRAR-SFX'     { "WinRAR SFX - /S (silent extract), -d<dir>. Self-extractor: pull out the inner installer, then handle that." }
        'InstallAware'   { "InstallAware - /s (silent), /l=`"<log>`", and app-defined PUBLIC properties as KEY=VALUE." }
        'WiseInstall'    { "Wise - /s (silent). Older engine; options are limited - check vendor docs for any property switches." }
        'MSIX|AppX'      { "MSIX/AppX - not a switch-based EXE: deploy with Add-AppxProvisionedPackage -PackagePath <msix> (device) or Add-AppxPackage (user)." }
        default          { "Engine not recognised (custom installer). Find switches in the vendor's install instructions (often a .docx/.txt/PDF in the source). Try: setup.exe /? or setup.exe --help. Common silent patterns: /S (NSIS), /VERYSILENT (Inno), /qn (MSI), -s -f1`"x.iss`" (InstallShield), --silent / --mode unattended (custom)." }
    }
}
# Look up what SIMILAR packages used. Priority: exact vendor+app (high) -> vendor (medium) -> engine guess
# (low). Loads KnowledgeBase.Recommend.json from the tool root once; silently no-ops if it isn't shipped.
# Fuzzy installer-file key (version-stripped) - MUST match the analyzer's Get-InstKey so live lookups line up.
function Get-InstKey {
    param([string]$FileName)
    if (-not $FileName) { return '' }
    $n = [IO.Path]::GetFileNameWithoutExtension($FileName).ToLower()
    $n = $n -replace '\d+(\.\d+)+[a-z]*',''
    $n = $n -replace '[_\-\s]v?\d{2,}',''
    return ($n -replace '[^a-z0-9]','')
}
$script:KBRec = $null; $script:KBRecTried = $false; $script:KBEngineIdx = $null
# Recognise a common PREREQUISITE / runtime installer by its FILENAME, so the tool installs it FIRST and with the
# right silent switches (corpus: vcredist/.NET runtimes appear in ~9% of packages, normally hand-wired). The rules are
# deliberately tight (a redistributable always carries "redist"/"runtime"/etc.) so a main app is not mis-tagged.
# Returns @{ IsPrereq=$true; Label; Install } or @{ IsPrereq=$false }.
function Get-PrerequisiteSpec {
    param([string]$Name)
    $n = ([IO.Path]::GetFileNameWithoutExtension("$Name")).ToLower()
    if (-not $n) { return @{ IsPrereq = $false } }
    $rules = @(
        @{ Re = 'vc_?redist|vcredist|visual.?c\+\+.*redist|vcpp.*redist'; Label = 'Visual C++ Redistributable'; Install = '/install /quiet /norestart' }
        @{ Re = 'windowsdesktop-runtime|dotnet-runtime|aspnetcore-runtime|dotnet-sdk';           Label = '.NET runtime';        Install = '/install /quiet /norestart' }
        @{ Re = 'ndp\d{2,3}|dotnetfx|netfx|dotnet-framework|microsoft.?\.net.?framework';        Label = '.NET Framework';      Install = '/q /norestart' }
        @{ Re = 'microsoftedgewebview2|webview2.*runtime|webview2.*setup';                        Label = 'Edge WebView2 Runtime'; Install = '/silent /install' }
        @{ Re = 'dxsetup|dxwebsetup|directx.*redist';                                             Label = 'DirectX Runtime';     Install = '/silent' }
    )
    foreach ($r in $rules) { if ($n -match $r.Re) { return @{ IsPrereq = $true; Label = $r.Label; Install = $r.Install } } }
    return @{ IsPrereq = $false }
}

function Get-KBRecommendation {
    param([string]$Vendor, [string]$App, [string]$Engine, [string]$InstallerName)
    # TIER -1 (highest): a recognised runtime PREREQUISITE -> its standard silent switches, install-FIRST. Beats the
    # corpus tiers because the switches for vc_redist/.NET are fixed and well-known.
    if ($InstallerName) {
        $pr = Get-PrerequisiteSpec -Name $InstallerName
        if ($pr.IsPrereq) {
            return @{ Install = $pr.Install; Uninstall = ''; UninstallExe = ''; AutoUpdate = @(); Confidence = 'high'
                      Source = "prerequisite/runtime ($($pr.Label)) - install BEFORE the main app"; Seen = 0; IsPrereq = $true; PrereqLabel = $pr.Label }
        }
    }
    if (-not $script:KBRecTried) {
        $script:KBRecTried = $true
        $p = Join-Path (Get-ToolRoot) 'KnowledgeBase.Recommend.json'
        if (Test-Path $p) { try { $script:KBRec = (Get-Content $p -Raw) | ConvertFrom-Json } catch {} }
    }
    # is the thing being installed an EXE with a KNOWN engine? -> prefer the EXE-specific recorded switches over
    # the package's primary (which may be the MSI's, e.g. Wireshark Npcap.msi).
    $wantExe = $Engine -and $Engine -notin 'MSI','MSI-as-OLE','MSIX/AppX','unknown','unreadable','missing'
    # is the current source NOT itself an MSI/MSIX? (covers exe + UNKNOWN-engine exe like SentinelOne, whose
    # fingerprint is 'unknown'). This - not $wantExe - is what gates the "previously packaged as MSI+MST" hint:
    # it must fire for an unidentifiable EXE too, otherwise the SentinelOne case is silently dropped.
    $srcNotMsi = "$Engine" -notin 'MSI','MSI-as-OLE','MSIX/AppX'
    # The source here is an EXE, but if the recorded recommendation INSTALLS VIA MSI, the team previously
    # extracted the MSI from this installer and shipped MSI+MST (SentinelOne, Avigilon...). Flag that on the
    # result REGARDLESS of which tier matched, so the "same installer" (Tier 0) hit doesn't hide the signal.
    $annotate = {
        param($r)
        if (-not $r) { return $r }
        # The uninstall EXE differs from the install exe. Use the KB's recorded uninstaller when present (after a
        # re-mine), else the engine's typical uninstaller, so the hint always names WHAT runs the uninstall.
        if (-not "$($r.UninstallExe)".Trim()) {
            $r.UninstallExe = if (Get-Command Get-EngineUninstaller -EA SilentlyContinue) { "$(Get-EngineUninstaller -Engine $Engine)" } else { '' }
        }
        if ($srcNotMsi -and -not $r.PackagedAsMsi -and "$($r.Install)" -match '(?i)Start-ADTMsiProcess|msiexec|\.msi(\b|''|")') {
            $r.PackagedAsMsi = $true; $r.Type = 'MSI'
            if ("$($r.Source)" -notmatch '(?i)MSI\+MST') { $r.Source = "$($r.Source) (previously packaged as MSI+MST)" }
        }
        return $r
    }
    # TIER 0 (strongest): SAME INSTALLER - fuzzy filename match (e.g. Wireshark-4.6.5-x64.exe ~ the recorded
    # Wireshark-4.4.7-x64.exe). Try the VENDOR-SCOPED key first ("<vendor>::<key>" - so a generic 'setup.exe'
    # only matches within the same vendor, never cross-app), then the bare key (stored only for SPECIFIC,
    # non-generic names). Reuse that package's exact recorded command. Confidence 'high'.
    if ($script:KBRec -and $script:KBRec.byInstaller -and $InstallerName) {
        $k = Get-InstKey $InstallerName
        if ($k) {
            $tryKeys = @(); if ($Vendor) { $tryKeys += "$($Vendor.ToLower())::$k" }; $tryKeys += $k
            foreach ($tk in $tryKeys) {
                $hit = $script:KBRec.byInstaller.PSObject.Properties | Where-Object { $_.Name -eq $tk } | Select-Object -First 1
                if ($hit -and "$($hit.Value.install)".Trim()) {
                    return (& $annotate @{ Install=$hit.Value.install; Uninstall=$hit.Value.uninstall; UninstallExe=$hit.Value.uninstaller; AutoUpdate=@(); Confidence='high'; Source="same installer: $($hit.Value.installer) (from $($hit.Value.fromPackage))"; Seen=1 })
                }
            }
        }
    }
    # exact vendor+app match (HIGH) - but ONLY if it actually recorded an install switch; many packages
    # store the switch in a $variable we couldn't capture (empty), so fall THROUGH to the engine guess
    # rather than returning a useless empty suggestion (this is why Wireshark showed nothing).
    if ($script:KBRec -and $Vendor -and $App) {
        $hit = $script:KBRec.byVendorApp.PSObject.Properties | Where-Object { $_.Name -eq "$Vendor|$App" } | Select-Object -First 1
        if ($hit) {
            if ($wantExe -and "$($hit.Value.exeInstall)".Trim()) {
                return (& $annotate @{ Install=$hit.Value.exeInstall; Uninstall=$hit.Value.uninstall; UninstallExe=$hit.Value.uninstaller; AutoUpdate=@($hit.Value.autoUpdate); Confidence='high'; Source="exact match (EXE): $($hit.Value.fromPackage)"; Seen=$hit.Value.seen })
            }
            if (-not $wantExe -and "$($hit.Value.install)".Trim()) {
                return (& $annotate @{ Install=$hit.Value.install; Uninstall=$hit.Value.uninstall; UninstallExe=$hit.Value.uninstaller; AutoUpdate=@($hit.Value.autoUpdate); Confidence='high'; Source="exact match: $($hit.Value.fromPackage)"; Seen=$hit.Value.seen })
            }
            # Source is an EXE (incl an UNKNOWN-engine EXE like SentinelOne) but this app was previously packaged as
            # MSI (the team extracted the MSI from the installer - SentinelOne, Avigilon). Tell the user, with the
            # MSI command + uninstall, so they know to extract/capture the MSI rather than expecting EXE switches.
            if ($srcNotMsi -and "$($hit.Value.type)" -match 'MSI') {
                # type=MSI is the signal (the args may be empty - many MSIs install via the MST with no extra params).
                return @{ Install=$hit.Value.install; Uninstall=$hit.Value.uninstall; UninstallExe=$hit.Value.uninstaller; AutoUpdate=@($hit.Value.autoUpdate); Confidence='medium'; Type='MSI'; PackagedAsMsi=$true; Source="exact match: $($hit.Value.fromPackage) (previously packaged as MSI+MST)"; Seen=$hit.Value.seen }
            }
        }
    }
    if ($script:KBRec -and $Vendor) {
        $hit = $script:KBRec.byVendor.PSObject.Properties | Where-Object { $_.Name -eq $Vendor } | Select-Object -First 1
        # Skip a vendor-level switch that's clearly WRONG for this EXE's engine (different product, different engine)
        # and fall through to the engine tier, which IS engine-correct - "checking the exe match" before suggesting.
        if ($hit -and "$($hit.Value.install)".Trim() -and -not ($wantExe -and -not (Test-SwitchMatchesEngine -Sw $hit.Value.install -Engine $Engine))) {
            return (& $annotate @{ Install=$hit.Value.install; Uninstall=$hit.Value.uninstall; UninstallExe=$hit.Value.uninstaller; AutoUpdate=@($hit.Value.autoUpdate); Confidence='medium'; Source="vendor '$Vendor' ($($hit.Value.seen) pkgs)"; Seen=$hit.Value.seen })
        }
    }
    # ENGINE-TYPE tier (data-backed): most-common install + uninstall across packages of the SAME engine - covers
    # custom setup engines too, and supplies an uninstall suggestion even with no vendor/app match. Low confidence.
    if ($Engine -and $Engine -notin 'missing','unreadable') {
        $idx = Get-KbEngineIndex
        $known = $script:EngineRuntimeToKb.ContainsKey($Engine)
        $buckets = if ($known) { @($script:EngineRuntimeToKb[$Engine]) } else { @('vendor-custom','unknown-args') }
        $minVotes = if ($known) { 2 } else { 3 }   # catch-all engines are heterogeneous - demand more agreement
        $instVotes=@{}; $unVotes=@{}; $cnt=0
        foreach ($b in $buckets) {
            if (-not $idx.ContainsKey($b)) { continue }
            $cnt += $idx[$b].Count
            foreach ($kv in $idx[$b].Install.GetEnumerator())   { if (Test-CleanSwitch $kv.Key) { $instVotes[$kv.Key] = $kv.Value + [int]$instVotes[$kv.Key] } }
            foreach ($kv in $idx[$b].Uninstall.GetEnumerator()) { if (Test-CleanSwitch $kv.Key) { $unVotes[$kv.Key]   = $kv.Value + [int]$unVotes[$kv.Key] } }
        }
        $bi = $instVotes.GetEnumerator() | Where-Object { $_.Value -ge $minVotes } | Sort-Object Value -Descending | Select-Object -First 1
        $bu = $unVotes.GetEnumerator()   | Where-Object { $_.Value -ge $minVotes } | Sort-Object Value -Descending | Select-Object -First 1
        if ($bi -or $bu) {
            return @{ Install=$(if($bi){"$($bi.Key)"}else{''}); Uninstall=$(if($bu){"$($bu.Key)"}else{(Get-EngineUninstallSwitch -Engine $Engine)})
                      UninstallExe=(Get-EngineUninstaller -Engine $Engine); AutoUpdate=@(); Confidence='low'; Source="most common for $Engine engine ($cnt package(s))"; Seen=$cnt }
        }
    }
    # Engine default (no KB data at all): the engine's own silent switches, incl. a sensible uninstall default.
    if ($Engine) {
        $sw  = Get-EngineSwitch -Engine $Engine
        $usw = Get-EngineUninstallSwitch -Engine $Engine
        if ("$sw".Trim() -or "$usw".Trim()) { return @{ Install="$sw"; Uninstall="$usw"; UninstallExe=(Get-EngineUninstaller -Engine $Engine); AutoUpdate=@(); Confidence='low'; Source="engine default ($Engine)"; Seen=0 } }
    }
    return $null
}
# Does a silent switch reference an ANSWER/RESPONSE file (so the packager must supply that file)? e.g.
# InstallShield /f1"setup.iss", Inno /LOADINF=, MathWorks -inputFile, generic "-f <props>" / "-i silent -f".
function Test-NeedsAnswerFile {
    param([string]$Switch)
    return [bool]("$Switch" -match '(?i)/f1|/LOADINF|-inputFile|-configurationFile|(^|\s)-f(\s|$)|-settingsFile|response')
}
# Is this installer a SECURITY / EDR / AV product? Re-running such an installer on a real endpoint is usually
# BLOCKED (tamper protection, "invalid image", or the resident AV/EDR like McAfee/SentinelOne kills the process),
# so run-and-capture / snapshot on THIS machine will fail. Steer the user to the static bundled-MSI extraction
# (no execution) or a throwaway sandbox instead. Matches the EXE name AND the package vendor/app text.
function Test-IsSecurityProduct {
    param([string]$Text)
    if (-not $Text) { return $false }
    return [bool]("$Text" -match '(?i)sentinel|crowdstrike|\bfalcon\b|mcafee|trellix|\bdefender\b|carbon\s*black|cylance|cortex|\bxdr\b|\bedr\b|symantec|\bsep\b|sophos|\beset\b|kaspersky|bitdefender|fireeye|tanium|cybereason|\bnessus\b|qualys|forcepoint|trend\s*micro|\bapex\s*one\b|huntress|\bs1\b')
}

#region Installer validation (validator checks surfaced as review items) -------------------------------
# Read one MSI Property table value (e.g. ProductVersion). $null on failure. Mirrors Get-MsiProductCode's COM use.
function Get-MsiProperty {
    param([string]$MsiPath, [string]$Property)
    if (-not (Test-Path $MsiPath)) { return $null }
    $i=$null;$db=$null;$v=$null;$r=$null
    try {
        $i  = New-Object -ComObject WindowsInstaller.Installer
        $db = $i.OpenDatabase($MsiPath,0)
        $v  = $db.OpenView("SELECT ``Value`` FROM ``Property`` WHERE ``Property`` = '$Property'")
        $v.Execute($null); $r = $v.Fetch()
        if ($r) { return $r.StringData(1) }
    } catch {} finally {
        foreach($o in @($r,$v,$db,$i)){ if($o){[Runtime.InteropServices.Marshal]::ReleaseComObject($o)|Out-Null} }
        [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    }
    return $null
}
# MSI target architecture from the SummaryInformation Template (Intel->x86, x64/Intel64/AMD64->x64). '' if unknown.
function Get-MsiTemplateArch {
    param([string]$MsiPath)
    if (-not (Test-Path $MsiPath)) { return '' }
    $i=$null;$db=$null;$si=$null
    try {
        $i  = New-Object -ComObject WindowsInstaller.Installer
        $db = $i.OpenDatabase($MsiPath,0)
        $si = $db.SummaryInformation(0)
        $tpl = "$($si.Property(7))"
        if ($tpl -match '(?i)x64|amd64|intel64|ia64') { return 'x64' }
        if ($tpl -match '(?i)intel|x86')              { return 'x86' }
    } catch {} finally {
        foreach($o in @($si,$db,$i)){ if($o){[Runtime.InteropServices.Marshal]::ReleaseComObject($o)|Out-Null} }
        [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    }
    return ''
}
# PE machine architecture of an EXE (reads the COFF header). 'x86' / 'x64' / 'ARM64' / 'unknown'.
function Get-PeArch {
    param([string]$Path)
    $fs=$null
    try {
        $fs = [IO.File]::OpenRead($Path); $br = New-Object IO.BinaryReader($fs)
        $fs.Position = 0x3C; $peOff = $br.ReadInt32()
        if ($peOff -le 0 -or $peOff -gt ($fs.Length - 6)) { return 'unknown' }
        $fs.Position = $peOff; [void]$br.ReadUInt32(); $machine = $br.ReadUInt16()
        switch ($machine) { 0x014C { 'x86' } 0x8664 { 'x64' } 0xAA64 { 'ARM64' } default { 'unknown' } }
    } catch { 'unknown' } finally { if ($fs) { $fs.Close() } }
}
# Validate the chosen installer against the package name + good practice. Returns @(review strings) - signature/
# publisher, version cross-check (installer vs package name), architecture cross-check. Surfaced in Review.
function Get-InstallerValidation {
    param([string]$Path, $Parsed)
    $out = New-Object System.Collections.Generic.List[string]
    if (-not $Path -or -not (Test-Path $Path)) { return @() }
    $ext = [IO.Path]::GetExtension($Path).ToLower(); $name = Split-Path $Path -Leaf
    # --- digital signature / publisher ---
    try {
        $sig = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
        $subj = "$($sig.SignerCertificate.Subject)"
        $cn = if ($subj -match 'CN=("?)([^",]+)') { $Matches[2].Trim() } else { $subj }
        switch ("$($sig.Status)") {
            'Valid'     { $out.Add("Signature: '$name' is signed by $cn (valid).") }
            'NotSigned' { $out.Add("Signature: '$name' is NOT digitally signed - confirm it is the official / trusted source before packaging.") }
            default     { $out.Add("Signature: '$name' status is '$($sig.Status)'$(if($cn){" ($cn)"}) - verify the source is trusted.") }
        }
    } catch {}
    # --- version cross-check (installer's real version vs the package-name version) ---
    $iv = ''
    if ($ext -eq '.msi') { $iv = "$(Get-MsiProperty -MsiPath $Path -Property 'ProductVersion')".Trim() }
    elseif ($ext -eq '.exe') { try { $fvi=[Diagnostics.FileVersionInfo]::GetVersionInfo($Path); $iv="$($fvi.ProductVersion)".Trim(); if (-not $iv) { $iv="$($fvi.FileVersion)".Trim() } } catch {} }
    if ($iv -and $Parsed -and "$($Parsed.Version)".Trim()) {
        $pn  = ("$($Parsed.Version)" -replace '[^0-9.]','').Trim('.')
        $ivn = ($iv -replace '[^0-9.]','').Trim('.')
        if ($pn -and $ivn -and -not ($ivn -like "$pn*" -or $pn -like "$ivn*")) {
            $out.Add("Version check: the installer reports version '$iv' but the package name says '$($Parsed.Version)' - confirm the package version is correct.")
        }
    }
    # --- architecture cross-check ---
    $ia = if ($ext -eq '.msi') { Get-MsiTemplateArch $Path } elseif ($ext -eq '.exe') { Get-PeArch $Path } else { '' }
    if ($ia -and $ia -ne 'unknown' -and $Parsed -and "$($Parsed.Arch)".Trim()) {
        $paNorm = if ("$($Parsed.Arch)" -match '(?i)x86') { 'x86' } elseif ("$($Parsed.Arch)" -match '(?i)x64|x86_64|amd64') { 'x64' } else { '' }
        if ($paNorm -and $ia -in 'x86','x64' -and $ia -ne $paNorm) {
            $out.Add("Architecture check: the installer is $ia but the package name says $($Parsed.Arch) - verify (an $ia installer in an $paNorm package will mis-target).")
        }
    }
    return $out.ToArray()
}
#endregion
$script:DocExts       = @('.docx','.doc','.xlsx','.xlsm','.xls','.msg','.eml','.pdf','.txt','.rtf','.md','.csv')
$script:IconExts      = @('.ico','.png')
$script:SourceNames   = @('source','sources','src','vendor source','vendorsource','vendor_source')
$script:DocNames      = @('doc','docs','document','documents','doku','documentation')
$script:IconNames     = @('icon','icons')
# GENERIC / scratch folders that carry NO package context - an installer dropped here (e.g. temp\setup.exe) has no
# meaningful siblings, so we never harvest them into Documents. Used by Get-SiblingDocItems.
$script:GenericFolderNames = @('temp','tmp','downloads','download','desktop','documents','my documents','appdata','local','locallow','roaming','cache','recent','new folder',
                               'users','public','program files','program files (x86)','programdata','windows','system32','onedrive','dropbox','google drive')

# When the user MANUALLY picks an installer that sits in a real package layout (e.g. <Pkg>\source\setup.exe) but the
# structured package root / Documentation folder can't be auto-detected, the package's docs are usually SIBLINGS of
# the 'source' folder. Return those sibling files/folders so the caller can carry them into the new Documentation.
# Returns @() when the installer's parent is GENERIC (temp\setup.exe etc.) - there are no reliable siblings there, so
# the installer just goes into Files as-is. ExcludePaths (chosen installers / icon folder) are never returned.
function Get-SiblingDocItems {
    param([string]$InstallerParent, [string[]]$ExcludePaths)
    if (-not $InstallerParent -or -not (Test-Path -LiteralPath $InstallerParent)) { return @() }
    $leafLc = "$(Split-Path -Leaf $InstallerParent)".ToLower()
    # Only harvest when the installer lives in a MEANINGFUL named source subfolder (source/src/...). A generic name
    # (temp/downloads/desktop/...) gives no reliable signal - skip, and the exe alone goes into Files.
    if ($script:SourceNames -inotcontains $leafLc) {
        # SMART one-level-up docs (user case): the installer sits in a BUILD/payload folder whose PARENT is a
        # VERSION_REVISION-named package folder (e.g. 26.0.0.0_0001\nCode26.0_Build440_win64\setup.exe). The version
        # folder's own DOC FILES (install instructions, complexity sheet .xlsx...) + doc-NAMED folders ARE the package
        # documentation - harvest ONLY those (targeted, no in-depth tree walk; other folders there are payload/builds
        # and are just logged, never hoovered into Documents).
        $gp = Split-Path -Parent $InstallerParent
        $gleaf = if ($gp) { "$(Split-Path -Leaf $gp)" } else { '' }
        if ($gp -and ($gleaf -match '^\d+(\.\d+)*[_-]\d+$') -and ($script:GenericFolderNames -inotcontains $gleaf.ToLower()) -and (Test-Path -LiteralPath $gp)) {
            $ex2 = @{}; foreach ($e in @($ExcludePaths)) { if ($e) { $ex2["$("$e".TrimEnd('\').ToLower())"] = $true } }
            $docs = New-Object System.Collections.Generic.List[string]
            $others = New-Object System.Collections.Generic.List[string]
            foreach ($c in (Get-ChildItem -LiteralPath $gp -Force -ErrorAction SilentlyContinue)) {
                $key = "$($c.FullName)".TrimEnd('\').ToLower()
                if ($key -eq "$InstallerParent".TrimEnd('\').ToLower()) { continue }   # the payload/build folder itself
                if ($ex2.ContainsKey($key)) { continue }
                if ($c.PSIsContainer) {
                    if ($script:DocNames -icontains $c.Name.ToLower()) { $docs.Add($c.FullName) } else { $others.Add($c.Name) }
                } elseif ($script:DocExts -contains $c.Extension.ToLower()) { $docs.Add($c.FullName) }
            }
            if ($docs.Count) { Write-Log "Docs found one level up (version folder '$gleaf'): $($docs.Count) item(s) -> Documents.$(if ($others.Count) { "  Other folder(s) there NOT auto-included: $($others -join ', ') - add manually if the install needs them." })" }
            return $docs.ToArray()
        }
        return @()
    }
    $grand = Split-Path -Parent $InstallerParent
    if (-not $grand -or $grand -eq $InstallerParent -or -not (Test-Path -LiteralPath $grand)) { return @() }
    if ($script:GenericFolderNames -icontains "$(Split-Path -Leaf $grand)".ToLower()) { return @() }   # grandparent generic -> not a package root
    $ex = @{}; foreach ($e in @($ExcludePaths)) { if ($e) { $ex["$("$e".TrimEnd('\').ToLower())"] = $true } }
    $items = New-Object System.Collections.Generic.List[string]
    foreach ($c in (Get-ChildItem -LiteralPath $grand -Force -ErrorAction SilentlyContinue)) {
        $key = "$($c.FullName)".TrimEnd('\').ToLower()
        if ($key -eq "$InstallerParent".TrimEnd('\').ToLower()) { continue }   # skip the source folder itself
        if ($ex.ContainsKey($key)) { continue }                                # skip chosen installers / icon folder
        if (-not $c.PSIsContainer -and ($script:InstallerExts -contains $c.Extension.ToLower())) { continue }   # skip stray installers
        $items.Add($c.FullName)
    }
    return $items.ToArray()
}

# FLAT manual-add case: the user picked an installer that sits DIRECTLY in a mixed folder (installer + docs together,
# no \source or \doc subfolder), e.g. <Pkg>\setup.exe alongside <Pkg>\manual.pdf. Documentation must be detected BY
# EXTENSION and routed to Documents; everything else (installers, and support files like .dll/.inf/.cfg/.ini that the
# install needs) stays in Files. Only DIRECT-CHILD files are judged - files inside subfolders (e.g. Firefox's payload
# tree, which often has .txt/.html that are NOT docs) are left in Files untouched.
function Get-LooseDocFiles {
    param([string]$Folder)
    if (-not $Folder -or -not (Test-Path -LiteralPath $Folder)) { return @() }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($f in (Get-ChildItem -LiteralPath $Folder -File -ErrorAction SilentlyContinue)) {
        if ($script:DocExts -contains $f.Extension.ToLower()) { $out.Add($f.FullName) }
    }
    return $out.ToArray()
}

function Get-FileClass {
    param([string]$Path)
    $e = [IO.Path]::GetExtension($Path).ToLower()
    if ($script:InstallerExts -contains $e) { return 'Installer' }
    if ($script:DocExts       -contains $e) { return 'Document'  }
    if ($script:IconExts      -contains $e) { return 'Icon'      }
    return 'Source'
}

function Find-FolderByNames {
    param([string]$Root, [string[]]$Names, [int]$MaxDepth = 6)
    if (-not (Test-Path $Root)) { return $null }
    $q = New-Object System.Collections.Generic.Queue[object]
    $q.Enqueue(@{ P = $Root; D = 0 })
    while ($q.Count -gt 0) {
        $cur = $q.Dequeue()
        if ($cur.D -ge $MaxDepth) { continue }
        $subs = $null
        try { $subs = Get-ChildItem -LiteralPath $cur.P -Directory -ErrorAction Stop } catch { continue }
        foreach ($s in $subs) {
            if ($Names -icontains $s.Name) { return $s.FullName }
            $q.Enqueue(@{ P = $s.FullName; D = $cur.D + 1 })
        }
    }
    return $null
}

function Find-InstallersUnder {
    param([string]$Folder, [int]$Depth = 0)
    if (-not (Test-Path $Folder) -or $Depth -gt 6) { return $null }
    $files = @(Get-ChildItem -LiteralPath $Folder -File -ErrorAction SilentlyContinue)
    if ($files | Where-Object { $script:InstallerExts -contains $_.Extension.ToLower() }) { return $Folder }
    # prefer a named source/src subfolder
    $named = @(Get-ChildItem -LiteralPath $Folder -Directory -ErrorAction SilentlyContinue |
               Where-Object { $script:SourceNames -icontains $_.Name })
    foreach ($n in $named) { $f = Find-InstallersUnder -Folder $n.FullName -Depth ($Depth+1); if ($f) { return $f } }
    # descend through ANY single subfolder chain (version folders, vendor folders, etc.)
    $dirs = @(Get-ChildItem -LiteralPath $Folder -Directory -ErrorAction SilentlyContinue)
    $nonDocDirs = @($dirs | Where-Object { $script:DocNames -inotcontains $_.Name -and $script:IconNames -inotcontains $_.Name })
    if ($nonDocDirs.Count -eq 1 -and -not ($files | Where-Object { $script:InstallerExts -contains $_.Extension.ToLower() })) {
        $f = Find-InstallersUnder -Folder $nonDocDirs[0].FullName -Depth ($Depth+1); if ($f) { return $f }
    }
    if ($files.Count -gt 0) { return $Folder }
    return $null
}

# Walk UP from a source path to the PACKAGE ROOT - the nearest ancestor whose folder name parses as a valid
# package name (Vendor_App_Arch_Ver-Rel_Lang). Returns $null if there is no such ancestor, so callers must NOT
# fall back to searching a whole multi-package SHARE (that is what made a Firefox build pick up the ISDOCReader
# package's Icons folder). Bounds Icons/Documents discovery to INSIDE the package being built.
function Get-PackageRootFolder {
    param([string]$Path)
    $cur = $Path
    for ($i = 0; $i -lt 8 -and $cur; $i++) {
        $leaf = Split-Path -Leaf $cur
        if ($leaf -and (Get-Command Parse-PackageName -EA SilentlyContinue)) {
            if ((Parse-PackageName -Name $leaf).IsValid) { return $cur }
        }
        $parent = Split-Path -Parent $cur
        if (-not $parent -or $parent -eq $cur) { break }
        $cur = $parent
    }
    return $null
}

# For a PREDECESSOR REUSE build, the icons come from the PREDECESSOR's own package folder on the live share
# (the new drop is usually just the installer, no Icons). Looks at <pred>\Icons first, then any Icons folder
# inside the predecessor package. Returns $null if the predecessor has none - the caller then leaves Icons EMPTY
# (we never borrow a different package's icons).
function Get-PredecessorIconsPath {
    param([string]$PredecessorPath)
    if (-not $PredecessorPath -or -not (Test-Path $PredecessorPath)) { return $null }
    $direct = Join-Path $PredecessorPath 'Icons'
    if (Test-Path $direct) { return $direct }
    return (Find-FolderByNames -Root $PredecessorPath -Names $script:IconNames -MaxDepth 4)
}

# ZIP source support (corpus: ~13% of live packages ship a .zip payload - SharePoint/downloads deliver one). Extract
# each given .zip into a LOCAL staging folder (the source share is often READ-ONLY, so never extract in place), each into
# its own subfolder so multiple zips don't collide. Returns the staging root (Find-InstallersUnder then descends into
# it), or $null on failure. Mark-of-the-Web is stripped after extraction so the extracted installer launches cleanly.
function Expand-SourceZips {
    param([object[]]$Zips)
    if (-not $Zips -or @($Zips).Count -eq 0) { return $null }
    $stage = Get-WorkPath ('Temp\zipsrc_' + [guid]::NewGuid().ToString('N').Substring(0,8))
    try { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue } catch {}
    $any = $false
    foreach ($z in @($Zips)) {
        try {
            # per-zip subfolder; ExtractToDirectory CREATES it (must NOT pre-exist), so don't make it first.
            $dest = Join-Path $stage ([IO.Path]::GetFileNameWithoutExtension($z.Name))
            [System.IO.Compression.ZipFile]::ExtractToDirectory($z.FullName, $dest)
            $any = $true
            Write-Log "Extracted source zip '$($z.Name)' -> $dest" Success
        } catch { Write-Log "Zip extract failed for '$($z.Name)': $($_.Exception.Message)" Warning }
    }
    if (-not $any) { return $null }
    try { if (Get-Command Unblock-PBPath -ErrorAction SilentlyContinue) { Unblock-PBPath -Path $stage } } catch {}
    return $stage
}

function Resolve-Source {
    param([Parameter(Mandatory)][string]$RootPath)
    if (-not (Test-Path $RootPath)) { Write-Log "Source path not found: $RootPath" Error; return @{ Valid = $false } }

    # ZIP SOURCE: if the tree has .zip payload(s) but NO real installer beside them, extract the zip(s) and resolve from
    # the extracted content (Files\ then ships the extracted payload, not the .zip). Only when there is no loose
    # installer already - a .zip sitting NEXT to an .exe/.msi is supplementary and is left as-is.
    $effRoot = $RootPath
    $zipPayload = $null
    $isGpf = (Get-Command Get-PBBrand -ErrorAction SilentlyContinue) -and (Get-PBBrand -Path 'Name' -Default 'MTB') -eq 'GPF'
    try {
        $allFiles     = @(Get-ChildItem -LiteralPath $RootPath -File -Recurse -Depth 8 -ErrorAction SilentlyContinue)
        $hasInstaller = @($allFiles | Where-Object { $script:InstallerExts -contains $_.Extension.ToLower() }).Count -gt 0
        $zips         = @($allFiles | Where-Object { $_.Extension.ToLower() -eq '.zip' })
        if ($zips.Count -gt 0 -and -not $hasInstaller) {
            if ($isGpf) {
                # GPF: NEVER extract the source zip here. The team convention is to ship the zip VERBATIM in Files\ and
                # Expand-ZipFile it at INSTALL time (to $envTemp\<app>_<version>), so extracting a multi-GB payload during
                # fetch is both wasteful (froze the UI on a 5 GB zip) and wrong (it shipped extracted content, not the zip).
                # Keep it as a single loose-zip payload; the index can be browsed on demand to pick the inner installer.
                $zipPayload = ($zips | Sort-Object Length -Descending | Select-Object -First 1).FullName
                Write-Log "GPF ZIP source: keeping '$([IO.Path]::GetFileName($zipPayload))' as-is (extracted at install, not fetch)." Success
            } else {
                $stage = Expand-SourceZips -Zips $zips
                if ($stage) { $effRoot = $stage; Write-Log "ZIP source: resolving installer from extracted content at $effRoot" }
            }
        }
    } catch {}

    $docFolder  = Find-FolderByNames -Root $RootPath -Names $script:DocNames  -MaxDepth 7
    $iconFolder = Find-FolderByNames -Root $RootPath -Names $script:IconNames -MaxDepth 7
    if (-not $iconFolder -or -not $docFolder) {
        # RootPath may be a SUBFOLDER (e.g. \source\source) - the package's Icons/Documents sit higher up. Search
        # only WITHIN the package root (the ancestor named like the package) so we find them but NEVER climb into a
        # multi-package share and grab a DIFFERENT package's Icons/Documents.
        $pkgRoot = Get-PackageRootFolder -Path $RootPath
        if ($pkgRoot -and $pkgRoot -ne $RootPath) {
            if (-not $iconFolder) { $iconFolder = Find-FolderByNames -Root $pkgRoot -Names $script:IconNames -MaxDepth 4 }
            if (-not $docFolder)  { $docFolder  = Find-FolderByNames -Root $pkgRoot -Names $script:DocNames  -MaxDepth 4 }
        }
    }
    if (-not $iconFolder) {
        # Last resort: any .ico anywhere under the root - use its folder. (Scoped to RootPath, so still safe.)
        $ico = Get-ChildItem -LiteralPath $RootPath -File -Recurse -Filter *.ico -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($ico) { $iconFolder = $ico.Directory.FullName }
    }
    if ($iconFolder) { Write-Log "Icons folder: $iconFolder" } else { Write-Log "No Icons folder found under $RootPath" Warning }
    $docItems   = New-Object System.Collections.Generic.List[string]
    if ($docFolder) { $docItems.Add($docFolder) }

    # 1. structured: a source-named folder, descend to real installer files (search the effective root - the extracted
    #    staging folder for a zip source, else the original RootPath).
    $srcFolder = Find-FolderByNames -Root $effRoot -Names $script:SourceNames -MaxDepth 7
    $installers = @(); $payloadFolder = $null; $mode = 'structured'
    if ($srcFolder) {
        $loc = Find-InstallersUnder -Folder $srcFolder
        if ($loc) {
            $payloadFolder = $loc
            $installers = @(Get-ChildItem -LiteralPath $loc -File -ErrorAction SilentlyContinue |
                            Where-Object { $script:InstallerExts -contains $_.Extension.ToLower() })
        }
    }

    # 2. loose-payload fallback: deepest content folder, any non-doc/non-icon file
    if (-not $installers -or $installers.Count -eq 0) {
        $mode = 'loose'
        # prefer payload folder if we found one (source folder with no exe/msi but other files)
        $searchRoot = if ($payloadFolder) { $payloadFolder } elseif ($srcFolder) { $srcFolder } else { $effRoot }
        $all = @()
        try { $all = Get-ChildItem -LiteralPath $searchRoot -File -Recurse -Depth 8 -ErrorAction SilentlyContinue } catch {}
        # real installers first if any appeared
        $real = @($all | Where-Object { $script:InstallerExts -contains $_.Extension.ToLower() })
        if ($real.Count -gt 0) { $installers = $real; $mode = 'scan' }
        else {
            # treat non-doc, non-icon files as loose payload candidates
            $installers = @($all | Where-Object {
                (Get-FileClass $_.FullName) -notin @('Document','Icon') })
        }
        foreach ($f in ($all | Where-Object { $script:DocExts -contains $_.Extension.ToLower() })) { $docItems.Add($f.FullName) }
        Write-Log "Source [$mode]: $($installers.Count) payload file(s) under $searchRoot" Warning
        if ($installers | Where-Object { $_.Extension.ToLower() -eq '.iso' }) {
            Write-Log "ISO detected - kept as-is (mount/extract during scripting)." Warning
        }
    } else {
        Get-ChildItem -LiteralPath $RootPath -File -ErrorAction SilentlyContinue |
            Where-Object { $script:DocExts -contains $_.Extension.ToLower() } |
            ForEach-Object { $docItems.Add($_.FullName) }
        Get-ChildItem -LiteralPath $RootPath -Directory -ErrorAction SilentlyContinue |
            Where-Object {
                ($script:SourceNames -inotcontains $_.Name) -and
                ($script:IconNames   -inotcontains $_.Name) -and
                ($script:DocNames    -inotcontains $_.Name)
            } | ForEach-Object { $docItems.Add($_.FullName) }
    }

    # The folder whose CONTENTS become Files\ (the "last source folder"): the deepest installer
    # folder for a structured source, else the scanned root. Install-command paths are made
    # relative to this, so an installer in a subfolder keeps that subfolder under DirFiles.
    $payloadRoot = if ($payloadFolder) { $payloadFolder }
                   elseif ($searchRoot) { $searchRoot }
                   elseif ($installers.Count -gt 0) { Split-Path -Parent $installers[0].FullName }
                   else { $effRoot }

    # PARITY with the MANUAL-pick flow (user rule: Fetch must be as smart as manual): when the resolver found NO docs
    # INSIDE the root, look where the manual path looks - siblings of a 'source'-named installer parent, the
    # VERSION_REV-named grandparent's doc files/doc folders (one level ABOVE the root), or nothing when the parent is
    # generic (Get-SiblingDocItems carries all those guards). Only fires when docs are otherwise EMPTY - never
    # disturbs the structured/scan results.
    if ($docItems.Count -eq 0 -and $installers.Count -gt 0 -and (Get-Command Get-SiblingDocItems -EA SilentlyContinue)) {
        $ip = Split-Path -Parent $installers[0].FullName
        foreach ($s in @(Get-SiblingDocItems -InstallerParent $ip -ExcludePaths @($installers | ForEach-Object { $_.FullName }))) { $docItems.Add($s) }
        if ($docItems.Count) { Write-Log "Docs found via manual-parity harvest (outside the source root): $($docItems.Count) item(s) -> Documents." }
    }

    Write-Log "Resolve-Source [$mode]: $($installers.Count) installer/payload, $($docItems.Count) doc item(s); payloadRoot=$payloadRoot"
    return @{
        Valid       = ($installers.Count -gt 0)
        Mode        = $mode
        RootPath    = $RootPath
        PayloadRoot = $payloadRoot
        Installers  = $installers
        DocItems    = $docItems.ToArray()
        IconsPath   = $iconFolder
        ZipPayload  = $zipPayload   # GPF: the source is a single .zip kept VERBATIM (Expand-ZipFile at install, not fetch)
    }
}

# Installer-type entries at the FIRST MEANINGFUL LEVEL inside a zip, read from the central directory (INSTANT - no
# extraction). Rule (user): if the zip wraps a single top folder, step ONE level into it; then list the installer-type
# files sitting AT that level only (never the deep app binaries under it). "Installer type" includes scripts the team
# uses as installers: .exe/.msi/.msp AND .bat/.cmd/.ps1. Returns @{ RelPath; Name; Extension } - the RelPath is what the
# install command runs after Expand-ZipFile (i.e. $envTemp\<App>_<Ver>\<RelPath>). Empty when the zip is unreadable.
function Get-ZipInstallerEntries {
    param([string]$ZipPath)
    if (-not $ZipPath -or -not (Test-Path -LiteralPath $ZipPath)) { return @() }
    try { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue } catch {}
    $rx = '(?i)\.(exe|msi|msp|bat|cmd|ps1)$'
    try {
        $z = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        try {
            # SINGLE pass over the (possibly huge) entry list: track top-level segments + any root file, and collect the
            # installer-type candidates as we go (each remembers its own top segment + one-level-in flag).
            $tops = New-Object System.Collections.Generic.HashSet[string]
            $rootFile = $false
            $cands = New-Object System.Collections.Generic.List[object]
            foreach ($e in $z.Entries) {
                if (-not $e.Name) { continue }                 # directory entry
                $fn  = ($e.FullName -replace '\\', '/')        # normalise: real zips use '/', .NET CreateFromDirectory uses '\'
                $sl  = $fn.IndexOf('/')
                $top = if ($sl -ge 0) { $fn.Substring(0, $sl) } else { $fn }
                [void]$tops.Add($top)
                if ($sl -lt 0) { $rootFile = $true }
                if ($e.Name -match $rx) {
                    $secondSl = if ($sl -ge 0) { $fn.IndexOf('/', $sl + 1) } else { -1 }
                    $cands.Add([pscustomobject]@{ FullName=$fn; Top=$top; HasRootSlash=($sl -ge 0); OneLevelIn=($sl -ge 0 -and $secondSl -lt 0); AtRoot=($sl -lt 0); Name=$e.Name; SizeKB=[math]::Round($e.Length/1KB) })
                }
            }
            $singleTop = ($tops.Count -eq 1 -and -not $rootFile)   # zip wraps ONE top folder, nothing loose at the root
            $out = New-Object System.Collections.Generic.List[object]
            foreach ($c in $cands) {
                $keep = if ($singleTop) { $c.OneLevelIn } else { $c.AtRoot }   # one step into the wrapper, else zip-root files
                if (-not $keep) { continue }
                [void]$out.Add([pscustomobject]@{ RelPath=($c.FullName -replace '/', '\'); Name=$c.Name; Extension=[IO.Path]::GetExtension($c.Name).ToLower(); SizeKB=$c.SizeKB })
            }
        } finally { $z.Dispose() }
    } catch { return @() }
    # real installers first (exe/msi), then scripts; by name
    return @($out | Sort-Object @{e={ if ($_.Extension -in '.msi','.exe') {0} else {1} }}, Name)
}

# Path of $Full relative to $Base (e.g. 'sub\App.msi'); just the filename if not under $Base.
function Get-RelativePath {
    param([string]$Base, [string]$Full)
    if (-not $Base) { return [IO.Path]::GetFileName($Full) }
    $b = $Base.TrimEnd('\','/') + '\'
    if ("$Full".StartsWith($b, [StringComparison]::OrdinalIgnoreCase)) { return $Full.Substring($b.Length) }
    return [IO.Path]::GetFileName($Full)
}

function Select-Installers {
    param([object[]]$Installers)
    if (-not $Installers -or $Installers.Count -eq 0) { return @{ Empty = $true } }
    if ($Installers.Count -eq 1) { return @{ Auto = $true; Chosen = @($Installers[0]) } }
    return @{ NeedsPrompt = $true; Options = $Installers }
}

# Vendor/client-provided MST for an MSI: prefer a sibling .mst with the same base
# name, else the only .mst in the folder. Returns $null if none. This MST is the
# BASE transform - it must be MODIFIED with our defaults, never regenerated from
# scratch, or the vendor's customizations are lost.
function Find-VendorMst {
    param([string]$MsiPath)
    if (-not $MsiPath) { return $null }
    $dir  = Split-Path -Parent $MsiPath
    $base = [IO.Path]::GetFileNameWithoutExtension($MsiPath)
    $exact = Join-Path $dir "$base.mst"
    if (Test-Path $exact) { return $exact }
    # "single .mst in the folder -> use it" is only safe when the folder holds ONE MSI. In a MULTI-MSI bundle
    # (the bundled-wrapper picker drops several MSIs in one folder) a single stray transform would otherwise be
    # applied to EVERY MSI - so only take that fallback for a single-MSI folder; otherwise require an exact name.
    $msts = @(Get-ChildItem -LiteralPath $dir -Filter *.mst -File -ErrorAction SilentlyContinue)
    $msis = @(Get-ChildItem -LiteralPath $dir -Filter *.msi -File -ErrorAction SilentlyContinue)
    if ($msts.Count -eq 1 -and $msis.Count -le 1) { return $msts[0].FullName }
    return $null
}

# Dump the WHOLE source folder into $Dest verbatim (recursively, structure preserved).
# Nothing is filtered by file TYPE - license/info .txt, .ini, .varfile, .dll, nested payload
# all land in Files\ as-is. The ONLY things skipped are the dedicated Documents / Icons
# named subfolders (handled separately into the package's Documents\ and Icons\).
function Copy-PayloadTree {
    param([string]$SrcFolder, [string]$Dest, [bool]$ExcludeDocIcon = $true, [string[]]$ExcludeFiles = @())
    if (-not (Test-Path $SrcFolder)) { return }
    $exFolders = @(@($script:DocNames) + @($script:IconNames) | ForEach-Object { $_.ToLower() })
    # Specific files routed elsewhere (e.g. flat-folder loose docs that go to Documents) - never copy them into Files.
    $exFiles = @{}; foreach ($e in @($ExcludeFiles)) { if ($e) { $exFiles["$("$e".TrimEnd('\').ToLower())"] = $true } }
    foreach ($f in @(Get-ChildItem -LiteralPath $SrcFolder -File -Recurse -ErrorAction SilentlyContinue)) {
        if ($exFiles.ContainsKey("$($f.FullName)".TrimEnd('\').ToLower())) { continue }
        $rel  = $f.FullName.Substring($SrcFolder.Length).TrimStart('\','/')
        if ($ExcludeDocIcon) {
            $segs = @($rel -split '[\\/]')
            $skip = $false
            if ($segs.Count -gt 1) { foreach ($s in $segs[0..($segs.Count-2)]) { if ($exFolders -contains $s.ToLower()) { $skip = $true; break } } }
            if ($skip) { continue }
        }
        $target = Join-Path $Dest $rel
        $tdir   = Split-Path $target -Parent
        if (-not (Test-Path $tdir)) { New-Item $tdir -ItemType Directory -Force | Out-Null }
        Copy-Item -LiteralPath $f.FullName -Destination $target -Force
    }
}

function Copy-ResolvedSource {
    param(
        [hashtable]$Resolved, [object[]]$ChosenInstallers,
        [Parameter(Mandatory)][string]$InstallerDest,
        [Parameter(Mandatory)][string]$DocDest, [string]$IconDest
    )
    foreach ($d in @($InstallerDest, $DocDest)) { if (-not (Test-Path $d)) { New-Item $d -ItemType Directory -Force | Out-Null } }
    # Manual selection: copy ONLY the picked files (flat). Structured source: dump the WHOLE
    # last source folder verbatim (all folders/files). Scan/loose (no source folder): dump the
    # payload root with our differentiation (skip Documents/Icons folders).
    $manual = ($Resolved -and $Resolved.Manual)
    if ($manual) {
        foreach ($inst in $ChosenInstallers) { Copy-Item -LiteralPath $inst.FullName -Destination $InstallerDest -Force }
    } else {
        $root = if ($Resolved -and $Resolved.PayloadRoot) { $Resolved.PayloadRoot } else { Split-Path -Parent $ChosenInstallers[0].FullName }
        $excludeDocIcon = ($Resolved.Mode -ne 'structured')   # structured = copy everything
        # DocItems that are FILES sitting UNDER the payload root (the flat-folder loose docs) must go to Documents
        # ONLY, not be duplicated into Files - exclude them from the tree copy.
        $rootLc = "$root".TrimEnd('\').ToLower()
        $docFilesUnderRoot = @(@($Resolved.DocItems) | Where-Object {
            $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) -and ("$_".ToLower().StartsWith($rootLc + '\'))
        })
        Copy-PayloadTree -SrcFolder $root -Dest $InstallerDest -ExcludeDocIcon $excludeDocIcon -ExcludeFiles $docFilesUnderRoot
    }
    foreach ($item in $Resolved.DocItems) { if (Test-Path $item) { Copy-Item -LiteralPath $item -Destination $DocDest -Recurse -Force } }
    if ($IconDest -and $Resolved.IconsPath -and (Test-Path $Resolved.IconsPath)) {
        if (-not (Test-Path $IconDest)) { New-Item $IconDest -ItemType Directory -Force | Out-Null }
        Copy-Item -LiteralPath "$($Resolved.IconsPath)\*" -Destination $IconDest -Recurse -Force
    }
    # Everything was copied from the LIVE network share -> strip Mark-of-the-Web so the packaged installers run
    # without a SmartScreen / "Open File - Security Warning" prompt during testing and on the endpoint.
    if (Get-Command Unblock-PBPath -EA SilentlyContinue) { foreach ($d in @($InstallerDest, $DocDest, $IconDest)) { if ($d) { Unblock-PBPath -Path $d } } }
    Write-Log "Copied $($ChosenInstallers.Count) installer(s) -> $InstallerDest; docs -> $DocDest (unblocked)" Success
}

# Estimate the install footprint (MB) of what we copy into Files\: the chosen installers
# plus their sibling payload (excluding docs/icons/other installers). Used to auto-fill
# $adtSession.FreeSpace for a fresh package.
function Get-PayloadSizeMB {
    param([object[]]$ChosenInstallers, [int]$MinMB = 150, [int]$InstalledMB = 0)
    $bytes = [long]0
    $seen  = @{}
    foreach ($inst in @($ChosenInstallers)) {
        if (-not $inst) { continue }
        if (Test-Path $inst.FullName) { $bytes += (Get-Item -LiteralPath $inst.FullName).Length }
        $dir = Split-Path -Parent $inst.FullName
        if ($dir -and -not $seen.ContainsKey($dir)) {
            $seen[$dir] = $true
            foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Recurse -ErrorAction SilentlyContinue)) {
                if ((Get-FileClass $f.FullName) -in @('Document','Icon','Installer')) { continue }
                $bytes += $f.Length
            }
        }
    }
    $mb = if ($bytes -le 0) { 0 } else { [int][math]::Ceiling($bytes / 1MB) }
    # FreeSpace = the LARGEST of: the SOURCE payload (installer file(s) + their sibling payload), the ACTUAL installed
    # footprint when a snapshot measured it (-InstalledMB), and a sane FLOOR (default 150 MB) - so a small installer
    # never produces a too-low requirement, and the installed size (always bigger than the compressed installer) wins
    # when known.
    return [Math]::Max([Math]::Max($mb, [int]$InstalledMB), [int]$MinMB)
}

# Resolve the icon for an ARP / shortcut entry, by the team's priority:
#   1. an .ico in the resolved Icons folder
#   2. one of the chosen shortcut target exes
#   3. any .exe whose base name resembles the AppName or Vendor
#   4. $null  (none found - caller leaves the icon out)
function Resolve-ArpIcon {
    param([hashtable]$Resolved, [string[]]$TargetExes = @(), [string]$AppName, [string]$Vendor)
    if ($Resolved.IconsPath -and (Test-Path $Resolved.IconsPath)) {
        $ico = Get-ChildItem -LiteralPath $Resolved.IconsPath -File -Filter *.ico -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($ico) { return $ico.FullName }
    }
    foreach ($t in $TargetExes) { if ($t -and (Test-Path $t)) { return $t } }
    $needle = (@($AppName, $Vendor) | Where-Object { $_ }) -join '|'
    if ($needle -and $Resolved.RootPath -and (Test-Path $Resolved.RootPath)) {
        $exe = Get-ChildItem -LiteralPath $Resolved.RootPath -File -Recurse -Filter *.exe -ErrorAction SilentlyContinue |
               Where-Object { $_.BaseName -match "(?i)$needle" } | Select-Object -First 1
        if ($exe) { return $exe.FullName }
    }
    return $null
}

# Place the resolved icon at <SupportFiles>\Icon.ico - what Set-MTBApplicationWizardEntry reads.
# An .ico is copied as-is; an .exe has its associated icon extracted and saved as .ico.
function Save-ArpIcon {
    param([string]$IconSource, [string]$SupportFilesDir)
    if (-not $IconSource -or -not (Test-Path $IconSource)) { return $false }
    if (-not (Test-Path $SupportFilesDir)) { New-Item $SupportFilesDir -ItemType Directory -Force | Out-Null }
    $dest = Join-Path $SupportFilesDir 'Icon.ico'
    try {
        if ([IO.Path]::GetExtension($IconSource).ToLower() -eq '.ico') {
            Copy-Item -LiteralPath $IconSource -Destination $dest -Force
        } else {
            Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
            $ic = [System.Drawing.Icon]::ExtractAssociatedIcon($IconSource)
            if (-not $ic) { return $false }
            $fs = [IO.File]::Open($dest, 'Create')
            try { $ic.Save($fs) } finally { $fs.Close(); $ic.Dispose() }
        }
        return $true
    } catch { Write-Log "ARP icon save failed: $($_.Exception.Message)" Warning; return $false }
}
# Find a package's SOURCE folder in the Incoming repository by name (exact, EQS_-prefixed, then fuzzy). ENGINE-level
# (not GUI): runs inside background runspaces (Invoke-PBAsync) that load only the engine modules.
function Find-SourceFolder {
    param([string]$PkgName)
    $repo = Get-Setting RepositoryPath
    if (-not $repo -or -not (Test-Path $repo)) { return $null }
    foreach ($n in @($PkgName, "EQS_$PkgName", ($PkgName -replace '^EQS_',''))) {
        $p = Join-Path $repo $n; if (Test-Path $p) { return $p }
    }
    $m = Get-ChildItem $repo -Directory -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -like "*$PkgName*" } | Select-Object -First 1
    if ($m) { return $m.FullName }
    return $null
}
